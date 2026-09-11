cat > /etc/mrnik-openvpn-watchdog.sh << 'EOF'
#!/bin/sh
# ============================================
# OpenVPN Watchdog Script
# Author: Mr Nik
# Description: Monitors OpenVPN connectivity
#              by pinging Iranian and foreign
#              sites and restarts OpenVPN
#              if all pings fail.
#              If 3 restarts happen within 10
#              minutes, a full recovery sequence
#              is triggered. OpenVPN is brought
#              back up FIRST (so tun0 exists),
#              then if passwall2 is active its
#              nftset is flushed and it's
#              restarted (rebuilding rules that
#              reference tun0). PBR is NOT
#              restarted here since it restarts
#              automatically whenever the OpenVPN
#              service itself restarts.
# ============================================

TSFILE=/tmp/mrnik-openvpn-last-restart.ts
OVPN_STATE=/tmp/mrnik-openvpn-service-state
RESTART_COUNT_FILE=/tmp/mrnik-openvpn-restart-count
RESTART_WINDOW_FILE=/tmp/mrnik-openvpn-restart-window

log() {
    logger -p notice -t mrnik-openvpn-watchdog "$1"
}

check_ping() {
    local HOST=$1
    local PREV_KEY=$2
    local PREV=$(cat "/tmp/mrnik-openvpn-ping-$PREV_KEY" 2>/dev/null || echo "ok")

    if ping -c 2 -W 4 "$HOST" > /dev/null 2>&1; then
        if [ "$PREV" = "failed" ]; then
            log "$HOST: FAILED -> OK"
            echo "ok" > "/tmp/mrnik-openvpn-ping-$PREV_KEY"
        fi
        return 0
    else
        if [ "$PREV" = "ok" ]; then
            log "$HOST: OK -> FAILED"
            echo "failed" > "/tmp/mrnik-openvpn-ping-$PREV_KEY"
        fi
        return 1
    fi
}

# Detect whether passwall2 is active (based on its real core process: xray or sing-box)
is_passwall2_active() {
    if pgrep -f "/tmp/etc/passwall2/bin/xray" > /dev/null 2>&1 || \
       pgrep -f "/tmp/etc/passwall2/bin/sing-box" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

restart_openvpn() {
    local REASON=$1
    NOW=$(date +%s)
    LAST=$(cat "$TSFILE" 2>/dev/null || echo 0)
    DIFF=$((NOW - LAST))

    if [ "$DIFF" -gt 60 ]; then
        echo "$NOW" > "$TSFILE"

        WINDOW_START=$(cat "$RESTART_WINDOW_FILE" 2>/dev/null || echo 0)
        WINDOW_DIFF=$((NOW - WINDOW_START))
        if [ "$WINDOW_DIFF" -gt 600 ]; then
            echo "0" > "$RESTART_COUNT_FILE"
            echo "$NOW" > "$RESTART_WINDOW_FILE"
        fi

        COUNT=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo 0)
        COUNT=$((COUNT + 1))
        echo "$COUNT" > "$RESTART_COUNT_FILE"

        log "$REASON, restarting OpenVPN (restart #$COUNT in current window)"
        service openvpn restart

        if [ "$COUNT" -ge 3 ]; then
            log "3 restarts within 10 minutes — starting full recovery sequence"

            PW2_WAS_ACTIVE=0
            if is_passwall2_active; then
                PW2_WAS_ACTIVE=1
            fi

            # Stop OpenVPN
            log "Stopping OpenVPN"
            service openvpn stop
            sleep 2

            if [ "$PW2_WAS_ACTIVE" -eq 1 ]; then
                # Flag the nftset for flush now; this doesn't need tun0 to exist
                log "passwall2 active — flagging nftset for flush"
                uci set passwall2.@global[0].flush_set=1
                uci commit passwall2
            fi

            # Bring OpenVPN back up
            log "Restarting OpenVPN after recovery"
            service openvpn start

            if [ "$PW2_WAS_ACTIVE" -eq 1 ]; then
                # Wait for tun0 to actually come up (up to 20s) before restarting passwall2
                WAIT=0
                TUN0_UP=0
                while [ "$WAIT" -lt 20 ]; do
                    if ip link show tun0 > /dev/null 2>&1; then
                        TUN0_UP=1
                        break
                    fi
                    sleep 1
                    WAIT=$((WAIT + 1))
                done

                if [ "$TUN0_UP" -eq 1 ]; then
                    log "tun0 confirmed up after ${WAIT}s — restarting passwall2 to rebuild nftables rules"
                else
                    log "tun0 still not up after ${WAIT}s — restarting passwall2 anyway (rules may fail and need a manual retry)"
                fi
                /etc/init.d/passwall2 restart
                sleep 5
            else
                log "passwall2 not active (likely PBR mode) — skipping passwall2 step; PBR restarts automatically with OpenVPN"
            fi

            # Reset counter and time window
            echo "0" > "$RESTART_COUNT_FILE"
            echo "$(date +%s)" > "$RESTART_WINDOW_FILE"

            log "Recovery complete, resuming watchdog cycle"
        fi
    fi
}

while true; do
    if pgrep -f "/usr/sbin/openvpn" > /dev/null 2>&1; then
        PREV_OVPN=$(cat "$OVPN_STATE" 2>/dev/null || echo "unknown")
        if [ "$PREV_OVPN" != "running" ]; then
            log "OpenVPN service is running, watchdog active"
            echo "running" > "$OVPN_STATE"
        fi

        if ! check_ping "digikala.com" "digikala"; then
            sleep 5
            if ! check_ping "varzesh3.com" "varzesh3"; then
                sleep 5
                if ! check_ping "mci.ir" "mci"; then
                    restart_openvpn "all 3 iranian pings failed"
                fi
            fi
        else
            if ! check_ping "youtube.com" "youtube"; then
                sleep 5
                if ! check_ping "instagram.com" "instagram"; then
                    sleep 5
                    if ! check_ping "x.com" "xcom"; then
                        restart_openvpn "all 3 foreign pings failed"
                    fi
                fi
            fi
        fi

    else
        PREV_OVPN=$(cat "$OVPN_STATE" 2>/dev/null || echo "unknown")
        if [ "$PREV_OVPN" != "stopped" ]; then
            log "OpenVPN service is stopped, watchdog inactive"
            echo "stopped" > "$OVPN_STATE"
        fi
    fi

    sleep 60
done
EOF
chmod +x /etc/mrnik-openvpn-watchdog.sh
