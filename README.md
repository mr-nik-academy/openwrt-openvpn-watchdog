# OpenVPN Watchdog for OpenWrt
**by Mr Nik**

A smart watchdog script for OpenWrt routers that monitors OpenVPN connectivity
by pinging Iranian and foreign sites, and automatically restarts OpenVPN.
If OpenVPN restarts 3 times within 10 minutes, a full recovery sequence is triggered.

---

## Features
- Monitors OpenVPN service status
- Pings 3 Iranian sites: `digikala.com`, `varzesh3.com`, `mci.ir`
- Pings 3 foreign sites: `youtube.com`, `instagram.com`, `x.com`
- Smart state-based logging (only logs when status changes)
- Restarts OpenVPN automatically when connectivity fails
- **Full recovery sequence** if 3 restarts happen within 10 minutes:
  1. Stop OpenVPN
  2. Flush Passwall2 nftset and restart Passwall2
  3. Wait 10 seconds
  4. Start OpenVPN
  5. Reset counter and resume normal monitoring

---

## How It Works

Every 30 seconds the script runs one cycle:

**1 — OpenVPN status check:**
- Just started → log `running, watchdog active`
- Just stopped → log `stopped, watchdog inactive`
- No change → no log

**2 — Iranian sites check:**
- ping `digikala.com` → failed → wait 5s
- ping `varzesh3.com` → failed → wait 5s
- ping `mci.ir` → failed → trigger restart

**3 — Foreign sites check** *(only if Iranian sites are OK)*
- ping `youtube.com` → failed → wait 5s
- ping `instagram.com` → failed → wait 5s
- ping `x.com` → failed → trigger restart

**4 — Restart logic:**
- Each restart increments a counter
- Counter resets if more than 10 minutes passed since first restart
- If counter reaches 3 within 10 minutes → full recovery sequence:

```
Stop OpenVPN
  ↓
Flush Passwall2 nftset + Restart Passwall2
  ↓
Wait 10 seconds
  ↓
Start OpenVPN
  ↓
Reset counter → Resume monitoring
```

---

## Installation

### Step 1 — Create the main script

```bash
cat > /etc/mrnik-openvpn-watchdog.sh << 'SCRIPT'
[paste script content here]
SCRIPT
chmod +x /etc/mrnik-openvpn-watchdog.sh
```

### Step 2 — Create the init.d service

```bash
cat > /etc/init.d/mrnik-openvpn-watchdog << 'SCRIPT'
[paste init.d content here]
SCRIPT
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

## Requirements
- OpenWrt 23.xx or later
- OpenVPN installed and configured
- Passwall2 installed

---

## YouTube Channel
📺 Mr Nik — Mrnik academy YouTube

---

## License
MIT License — Free to use and modify
