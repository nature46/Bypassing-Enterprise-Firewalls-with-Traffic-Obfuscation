# 05 — Client Configuration

## Overview

This guide covers setting up the proxy client on Linux (Nekobox) and Windows (V2RayN).

---

## The VLESS Link

You'll receive a link like this from the server admin:

```
vless://YOUR_UUID@104.21.33.188:443?type=ws&encryption=none&path=%2Fsecretpath&host=janus.yourdomain.com&security=tls&sni=janus.yourdomain.com#janus-aules
```

### Link breakdown

| Part | Value | Meaning |
|------|-------|---------|
| Protocol | `vless://` | VLESS proxy protocol |
| UUID | `YOUR_UUID` | Your personal authentication key |
| Address | `104.21.33.188` | Cloudflare IP (bypasses DNS blocking) |
| Port | `443` | Standard HTTPS port |
| type | `ws` | WebSocket transport |
| path | `/secretpath` | Server endpoint path |
| host | `janus.yourdomain.com` | HTTP Host header for Cloudflare routing |
| security | `tls` | TLS encryption (Cloudflare edge) |
| sni | `janus.yourdomain.com` | TLS Server Name Indication |
| fragment | `#janus-aules` | Display name (cosmetic only) |

---

## Linux — Nekobox (Recommended)

### Installation

```bash
# Method 1: Installer script
bash <(curl -fsSL https://raw.githubusercontent.com/ohmydevops/nekoray-installer/main/throne-linux.sh)

# Method 2: Manual download
wget https://github.com/MatsuriDayo/nekoray/releases/download/4.0.1/nekoray-4.0.1-2024-12-12-linux64.zip
unzip nekoray-4.0.1-2024-12-12-linux64.zip
cd nekoray
./nekobox
```

### Dependencies (if needed)

```bash
sudo apt install -y libqt5widgets5 libqt5network5 libqt5svg5 libqt5x11extras5
```

### Import and Connect

1. Copy the VLESS link to clipboard
2. Open Nekobox
3. Click **Program** → **Add profile from clipboard** (or Ctrl+V)
4. The profile appears in the list
5. Right-click → **Start** (or double-click)
6. Enable **TUN Mode** for system-wide proxy (routes ALL traffic through the proxy)

### Verify Connection

Open Firefox and navigate to:
- `https://ifconfig.me` — should show your home server's public IP
- `https://youtube.com` — should load if it was blocked before

### TUN Mode vs System Proxy

| Mode | How it works | Use case |
|------|-------------|----------|
| **System Proxy** | Sets HTTP/SOCKS proxy in system settings | Browser traffic only |
| **TUN Mode** | Creates virtual network interface, captures all traffic | Everything (browsers, apps, CLI) |

**Recommended**: TUN Mode for complete bypass.

---

## Windows — V2RayN

### Installation

1. Download from [V2RayN releases](https://github.com/2dust/v2rayN/releases)
2. Extract the ZIP file
3. Run `v2rayN.exe`

### Import and Connect

1. Copy the VLESS link
2. In V2RayN: **Servers** → **Import from clipboard**
3. The server appears in the list
4. Right-click → **Set as active server**
5. Click **System Proxy** → **Set as system proxy** in the bottom toolbar

### Verify

Same as Linux — check `ifconfig.me` and try accessing blocked sites.

---

## Mobile Clients

### Android — V2RayNG

1. Install from [GitHub releases](https://github.com/2dust/v2rayNG/releases) or Google Play
2. Tap `+` → **Import from clipboard**
3. Tap the profile → Connect

### iOS — Shadowrocket / Streisand

1. Install from App Store (paid)
2. Add server → scan QR code or paste VLESS link
3. Toggle connection on

---

## Troubleshooting Client Issues

### "Connection refused" or timeout

- Check that the VLESS link uses the **Cloudflare IP** (not the local server IP)
- Verify port is `443` (not `8080`)
- Ensure `security=tls` is in the link

### DNS errors in logs

```
dns: exchange failed: unexpected HTTP response status: 302
```

This means Cloudflare Access is intercepting the connection. The server admin needs to create a bypass rule (see [04 - Proxmox Setup](04-Proxmox-Homelab-Setup.md#step-6-cloudflare-dashboard-settings)).

### Connected but no internet

- Check that the TUN mode or system proxy is active
- Try disabling IPv6 on the client
- Check Nekobox logs for errors (View → Logs)

### "Bad Request" when testing in browser

Visiting `https://janus.yourdomain.com/secretpath` in a browser gives "Bad Request" — this is **normal**. The endpoint only accepts VLESS protocol connections, not regular HTTP.

---

## DNS Blocking Workaround

If the restricted network blocks DNS resolution of your domain:

1. Find the Cloudflare IP for your domain:
   ```bash
   # From a non-restricted network
   dig janus.yourdomain.com +short
   ```
2. Use this IP as the **address** in the VLESS link
3. Keep the `host` and `sni` fields as the domain name

The client connects to the IP directly (bypassing DNS) but sends the domain in the TLS SNI and HTTP Host headers so Cloudflare knows where to route the traffic.

---

**Next**: [06 - Troubleshooting](06-Troubleshooting.md) — Detailed problem-solving guide
