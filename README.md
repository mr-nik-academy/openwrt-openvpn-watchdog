# OpenVPN Watchdog for OpenWrt
**by Mr Nik**

A smart watchdog script for OpenWrt routers that monitors OpenVPN connectivity
by pinging Iranian and foreign sites, and automatically restarts OpenVPN.
If OpenVPN restarts 3 times within 10 minutes, a full recovery sequence is triggered.
Works whether you're running **Passwall2** or **PBR** alongside OpenVPN.

---

## Features
- Monitors OpenVPN service status
- Pings 3 Iranian sites: `digikala.com`, `varzesh3.com`, `mci.ir`
- Pings 3 foreign sites: `youtube.com`, `instagram.com`, `x.com`
- Smart state-based logging (only logs when status changes)
- Restarts OpenVPN automatically when connectivity fails
- Detects whether Passwall2 is actually running (via its xray/sing-box process)
- **Full recovery sequence** if 3 restarts happen within 10 minutes:
  1. Stop OpenVPN
  2. Flag Passwall2's nftset for flush (if Passwall2 is active)
  3. Start OpenVPN
  4. Wait for `tun0` to come up (up to 20s)
  5. Restart Passwall2 to rebuild its nftables rules
  6. Reset counter and resume normal monitoring

> **Note:** PBR needs no restart step here — it restarts automatically whenever the OpenVPN service itself restarts.

---

## How It Works

Every 60 seconds the script runs one cycle:

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
- Counter resets if more than 10 minutes passed since the first restart
- If counter reaches 3 within 10 minutes → full recovery sequence:

```
Stop OpenVPN
  ↓
Passwall2 active? → Flag nftset for flush
  ↓
Start OpenVPN
  ↓
Wait for tun0 to come up (up to 20s)
  ↓
Passwall2 active? → Restart Passwall2 (rebuilds tun0-dependent rules)
Not active (PBR mode)? → Skip — PBR already restarted itself
  ↓
Reset counter → Resume monitoring
```

**Why OpenVPN starts *before* Passwall2 restarts:** Passwall2's nftables ruleset references `tun0` by name. Restarting it while `tun0` doesn't exist yet throws `Interface does not exist` errors and leaves rules broken. Bringing OpenVPN up first and confirming `tun0` is present avoids this entirely.

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
- OpenVPN installed and configured (`tun0` tunnel interface)
- Passwall2 (optional) or PBR (optional)

---

## Known Limitations / Roadmap
- Only OpenVPN is supported for now — Cisco OpenConnect support (auto-detecting which VPN protocol is active) is planned.
- Passwall2's process paths (`/tmp/etc/passwall2/bin/...`) are based on a tested setup; adjust in the script if yours differs.

---

## YouTube Channel
📺 Mr Nik — [Mrnik academy YouTube] (https://www.youtube.com/@MrNikAcademy)
---

## License
MIT License — Free to use and modify
