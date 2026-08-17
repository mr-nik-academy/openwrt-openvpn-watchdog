cat > /etc/mrnik-openvpn-watchdog.sh << 'EOF'
#!/bin/sh
# ============================================
# OpenVPN Watchdog Script
# Author: Mr Nik
# Description: Monitors OpenVPN connectivity
#              by pinging Iranian and foreign
#              sites and restarts OpenVPN
#              if all pings fail.
#              Every 3 restarts, WAN is also
#              restarted.
# ============================================

TSFILE=/tmp/mrnik-openvpn-last-restart.ts
OVPN_STATE=/tmp/mrnik-openvpn-service-state
RESTART_COUNT_FILE=/tmp/mrnik-openvpn-restart-count

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

restart_openvpn() {
    local REASON=$1
    NOW=$(date +%s)
    LAST=$(cat "$TSFILE" 2>/dev/null || echo 0)
    DIFF=$((NOW - LAST))
    if [ "$DIFF" -gt 60 ]; then
        echo "$NOW" > "$TSFILE"

        COUNT=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo 0)
        COUNT=$((COUNT + 1))
        echo "$COUNT" > "$RESTART_COUNT_FILE"

        log "$REASON, restarting OpenVPN (restart #$COUNT)"
        service openvpn restart

        if [ "$COUNT" -ge 3 ]; then
            log "3 restarts reached, restarting WAN interface too"
            ifdown wan
            sleep 5
            ifup wan
            echo "0" > "$RESTART_COUNT_FILE"
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

    sleep 30
done
EOF
chmod +x /etc/mrnik-openvpn-watchdog.sh
