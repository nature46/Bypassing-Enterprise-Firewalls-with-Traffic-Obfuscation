# 05 — Client Configuration

## Overview

This guide covers setting up the proxy client. **TUN mode is essential** — it creates raw TCP connections that bypass the transparent proxy.

---

## The VLESS Link

```
vless://YOUR_UUID@janus-relay.YOUR_ACCOUNT.workers.dev:443?type=ws&encryption=none&path=%2Fsecretpath&host=janus-relay.YOUR_ACCOUNT.workers.dev&security=tls&sni=janus-relay.YOUR_ACCOUNT.workers.dev#janus-aules
```

| Part | Value | Purpose |
|------|-------|---------|
| Protocol | `vless://` | VLESS proxy protocol |
| UUID | `YOUR_UUID` | Personal authentication key |
| Address | `janus-relay...workers.dev` | Worker URL (allowed SNI) |
| Port | `443` | Standard HTTPS |
| type | `ws` | WebSocket transport |
| path | `/secretpath` | Server endpoint |
| host | `janus-relay...workers.dev` | HTTP Host header |
| security | `tls` | TLS encryption |
| sni | `janus-relay...workers.dev` | **Must be workers.dev** (passes SNI filter) |

---

## Linux — Nekobox

### Installation

```bash
# Method 1: Direct download
curl -L -o nekoray.zip https://github.com/MatsuriDayo/nekoray/releases/download/4.0.1/nekoray-4.0.1-2024-12-12-linux64.zip
unzip nekoray.zip
cd nekoray

# Install dependencies
sudo apt install -y libqt5widgets5 libqt5network5 libqt5svg5 libqt5x11extras5

# Run (needs sudo for TUN mode!)
sudo ./nekobox
```

> **Important**: Run with `sudo` — TUN mode needs root privileges to create the virtual network interface.

### Import and Connect

1. Copy the VLESS link to clipboard
2. Open Nekobox
3. **Program** → **Add profile from clipboard** (or Ctrl+V)
4. Right-click the profile → **Start**
5. **Enable TUN Mode** (critical — without this, the transparent proxy blocks everything)

### Verify

- `https://ifconfig.me` → Should show your home server's public IP
- `https://youtube.com` → Should load
- `https://reddit.com` → Should load

### Why TUN Mode is Critical

| Mode | What it does | Works at Aules? |
|------|-------------|-----------------|
| **System Proxy** | Sets HTTP/SOCKS proxy in system settings | ❌ Transparent proxy intercepts |
| **TUN Mode** | Creates virtual network interface, raw TCP | ✅ **Bypasses transparent proxy** |

---

## Windows — V2RayN

### Installation

1. Download from [V2RayN releases](https://github.com/2dust/v2rayN/releases)
2. Extract and run `v2rayN.exe`

### Import and Connect

1. Copy VLESS link → **Servers** → **Import from clipboard**
2. Right-click → **Set as active server**
3. Enable **TUN mode** in settings (or use System Proxy if TUN isn't available)

---

## Mobile Clients

### Android — V2RayNG

1. Install from [GitHub](https://github.com/2dust/v2rayNG/releases) or Google Play
2. Tap `+` → **Import from clipboard**
3. Connect

### iOS — Shadowrocket / Streisand

1. Install from App Store (paid)
2. Add server → paste VLESS link
3. Connect

---

## Troubleshooting

### "Connection refused" or timeout

- Verify the link uses the **Worker URL** (not `nature46.uk` directly)
- Check port is `443`
- Ensure `security=tls` is in the link

### EOF errors (~300ms)

```
ERROR connection: open connection ... using outbound/vless[proxy]: EOF
```

This means **SNI filtering** is blocking the connection. Make sure the `sni` field in the link points to the Worker (`workers.dev`), not your custom domain.

### "Reset connection by peer"

Run Nekobox with `sudo`:
```bash
sudo ./nekobox
```

TUN mode requires root privileges.

### Connected but no internet

- Verify TUN mode is active (not just System Proxy)
- Check Nekobox logs (View → Logs)
- Try disabling IPv6

---

**Next**: [06 - Troubleshooting](06-Troubleshooting.md) — Complete problem-solving guide
