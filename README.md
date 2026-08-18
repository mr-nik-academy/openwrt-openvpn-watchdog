# OpenVPN Watchdog for OpenWrt
**by Mr Nik**

A smart watchdog script for OpenWrt routers that monitors OpenVPN connectivity
by pinging Iranian and foreign sites, and automatically restarts OpenVPN.
If OpenVPN restarts 3 times within 10 minutes, a full recovery sequence is triggered.

---

## Features
- Monitors OpenVPN service status
- Pings 3 Iranian sites: digikala.com, varzesh3.com, mci.ir
- Pings 3 foreign sites: youtube.com, instagram.com, x.com
- Smart state-based logging (only logs when status changes)
- Restarts OpenVPN automatically when connectivity fails
- If 3 restarts happen within 10 minutes → full recovery sequence:
  1. Stop OpenVPN
  2. Restart WAN interface
  3. Wait 10 seconds
  4. Start OpenVPN
  5. Restart Passwall2 after 2 seconds
  6. Reset counter and resume normal monitoring

---

## How It Works

Every 30 seconds the script runs one cycle:

**Step 1 — Check OpenVPN status:**
- If OpenVPN just started → log `running, watchdog active`
- If OpenVPN just stopped → log `stopped, watchdog inactive`
- No change → no log

**Step 2 — Iranian sites check:**
- ping digikala.com → if failed, wait 5s
- ping varzesh3.com → if failed, wait 5s
- ping mci.ir → if failed → trigger restart

**Step 3 — Foreign sites check (only if Iranian sites are OK):**
- ping youtube.com → if failed, wait 5s
- ping instagram.com → if failed, wait 5s
- ping x.com → if failed → trigger restart

**Step 4 — Restart logic:**
- Each restart increments a counter
- If more than 10 minutes have passed since first restart → counter resets
- If counter reaches 3 within 10 minutes → full recovery sequence runs

---

## Installation

### Step 1 — Create the main script
```bash
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
            log "3 restarts within 10 minutes — stopping OpenVPN, restarting WAN"

            service openvpn stop
            sleep 2

            ifdown wan
            sleep 10
            ifup wan
            sleep 10

            log "Restarting OpenVPN after WAN recovery"
            service openvpn start
            sleep 2

            log "Restarting Passwall2"
            /etc/init.d/passwall2 restart

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
```

### Step 2 — Create the init.d service
```bash
cat > /etc/init.d/mrnik-openvpn-watchdog << 'EOF'
#!/bin/sh /etc/rc.common
# OpenVPN Watchdog - by Mr Nik
START=99
STOP=10
start() {
    if [ -f /tmp/mrnik-openvpn-watchdog.pid ]; then
        kill $(cat /tmp/mrnik-openvpn-watchdog.pid) 2>/dev/null
    fi
    /etc/mrnik-openvpn-watchdog.sh &
    echo $! > /tmp/mrnik-openvpn-watchdog.pid
    logger -p notice -t mrnik-openvpn-watchdog "service started, PID $!"
}
stop() {
    if [ -f /tmp/mrnik-openvpn-watchdog.pid ]; then
        kill $(cat /tmp/mrnik-openvpn-watchdog.pid) 2>/dev/null
        rm -f /tmp/mrnik-openvpn-watchdog.pid
    fi
}
EOF
chmod +x /etc/init.d/mrnik-openvpn-watchdog
```

### Step 3 — Enable and start
```bash
/etc/init.d/mrnik-openvpn-watchdog enable
/etc/init.d/mrnik-openvpn-watchdog start
```

### Step 4 — Verify
```bash
ps | grep mrnik-openvpn-watchdog | grep -v grep
logread | grep mrnik-openvpn-watchdog | tail -5
```

---

## Check Logs
```bash
logread | grep mrnik-openvpn-watchdog | tail -10
```

---

## Removal
```bash
/etc/init.d/mrnik-openvpn-watchdog stop
/etc/init.d/mrnik-openvpn-watchdog disable
rm /etc/mrnik-openvpn-watchdog.sh
rm /etc/init.d/mrnik-openvpn-watchdog
rm -f /tmp/mrnik-openvpn-watchdog.pid
rm -f /tmp/mrnik-openvpn-last-restart.ts
rm -f /tmp/mrnik-openvpn-service-state
rm -f /tmp/mrnik-openvpn-restart-count
rm -f /tmp/mrnik-openvpn-restart-window
rm -f /tmp/mrnik-openvpn-ping-*
```

---

## YouTube Channel
📺 Mr Nik — www.youtube.com/@MrNikAcademy

---

## License
MIT License — Free to use and modify
