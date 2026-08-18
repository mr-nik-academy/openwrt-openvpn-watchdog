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
#              minutes, WAN is restarted and
#              OpenVPN + Passwall2 are reloaded.
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

restart_openvpn() {
    local REASON=$1
    NOW=$(date +%s)
    LAST=$(cat "$TSFILE" 2>/dev/null || echo 0)
    DIFF=$((NOW - LAST))

    if [ "$DIFF" -gt 60 ]; then
        echo "$NOW" > "$TSFILE"

        # چک پنجره زمانی 10 دقیقه
        WINDOW_START=$(cat "$RESTART_WINDOW_FILE" 2>/dev/null || echo 0)
        WINDOW_DIFF=$((NOW - WINDOW_START))
        if [ "$WINDOW_DIFF" -gt 600 ]; then
            # بیشتر از 10 دقیقه گذشته، counter رو ریست کن
            echo "0" > "$RESTART_COUNT_FILE"
            echo "$NOW" > "$RESTART_WINDOW_FILE"
        fi

        COUNT=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo 0)
        COUNT=$((COUNT + 1))
        echo "$COUNT" > "$RESTART_COUNT_FILE"

        log "$REASON, restarting OpenVPN (restart #$COUNT in current window)"
        service openvpn restart

        if [ "$COUNT" -ge 3 ]; then
            log "3 restarts within 10 minutes — stopping OpenVPN, restarting WAN"

            # خاموش کردن OpenVPN
            service openvpn stop
            sleep 2

            # ری استارت WAN
            ifdown wan
            sleep 10
            ifup wan
            sleep 10

            # روشن کردن مجدد OpenVPN
            log "Restarting OpenVPN after WAN recovery"
            service openvpn start
            sleep 2

            # ری استارت Passwall2
            log "Restarting Passwall2"
            /etc/init.d/passwall2 restart

            # ریست counter و پنجره زمانی
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

    sleep 30
done
EOF
chmod +x /etc/mrnik-openvpn-watchdog.sh
/etc/init.d/mrnik-openvpn-watchdog restart
sleep 5
logread | grep mrnik-openvpn-watchdog | tail -3
