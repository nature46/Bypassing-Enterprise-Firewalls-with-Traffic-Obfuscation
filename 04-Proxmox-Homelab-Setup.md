# 04 — Proxmox Homelab Setup (Final Solution)

## Overview

This is the working solution. It runs Xray-core on a Proxmox LXC container at home and uses Cloudflare Tunnel to make it accessible through trusted Cloudflare IPs.

**Requirements**:
- A server running Proxmox VE (or any Linux box)
- A Cloudflare account with a domain
- An existing Cloudflare Tunnel (or willingness to create one)

---

## Step 1: Create the LXC Container

From the Proxmox host shell:

```bash
# Download Ubuntu template if you don't have it
pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst

# Create the container
pct create 109 local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname janus \
  --memory 1024 \
  --cores 2 \
  --rootfs local-lvm:8 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.0.103/24,gw=192.168.0.1 \
  --nameserver 8.8.8.8 \
  --features nesting=1 \
  --start 1 \
  --password YOUR_PASSWORD
```

### Important Notes

- **Use a privileged container** (default) — 3x-ui needs systemd, which has issues in unprivileged LXC
- **Set DNS explicitly** (`--nameserver 8.8.8.8`) — some LXC containers inherit broken DNS
- **Enable nesting** (`--features nesting=1`) — required for systemd inside containers
- **Use a static IP** — the Cloudflare Tunnel config points to this IP

### Verify the container

```bash
pct exec 109 -- ping -c 2 google.com
pct exec 109 -- ip a | grep inet
```

---

## Step 2: Install Xray-core

Enter the container and install:

```bash
pct exec 109 -- bash

# Update system
apt update && apt upgrade -y

# Install Xray-core
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# Verify
/usr/local/bin/xray version
```

---

## Step 3: Install 3x-ui Panel

```bash
# Generate self-signed cert first (3x-ui requires SSL setup)
openssl req -x509 -newkey rsa:2048 -keyout /root/key.pem -out /root/cert.pem \
  -days 365 -nodes -subj "/CN=janus"

# Install 3x-ui
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o install.sh
bash install.sh
```

During installation:
- Panel port: `2053`
- When asked for SSL certificate method: choose **3** (Custom)
- Certificate path: `/root/cert.pem`
- Key path: `/root/key.pem`

Access the panel: `https://192.168.0.103:2053/YOUR_BASEPATH`

> **Tip**: If the panel shows "Install panel first", restart: `x-ui restart`

---

## Step 4: Create VLESS + WebSocket Inbound

In the 3x-ui panel, create a new inbound:

| Field | Value | Why |
|-------|-------|-----|
| Notas | `janus-cloudflare` | Identification |
| Protocol | `vless` | Lightweight, no encryption overhead |
| Port | `8080` | Cloudflare Tunnel will forward here |
| Transmisión | `ws` (WebSocket) | HTTP-compatible, passes through CDNs |
| Path | `/secretpath` | Acts as a secret key — random string recommended |
| Host | `janus.yourdomain.com` | Your Cloudflare subdomain |
| Security | `None` | Cloudflare handles TLS |
| Sniffing | Enabled | Better DNS handling |

### Why These Settings?

- **No TLS/Reality**: Cloudflare terminates TLS on their edge. Your server receives plain HTTP from the tunnel.
- **WebSocket**: The only transport compatible with Cloudflare Tunnel (it doesn't support raw TCP)
- **Port 8080**: Internal port, not exposed to the internet. Only Cloudflare Tunnel connects here.
- **Secret path**: Anyone hitting `/` gets a 404. Only connections to `/secretpath` are proxied.

---

## Step 5: Configure Cloudflare Tunnel

### If you already have a tunnel running

Edit the tunnel config on your Cloudflare Tunnel container:

```bash
# On the Cloudflare Tunnel LXC (e.g., LXC-101)
nano /etc/cloudflared/config.yml
```

Add the Janus ingress **before** the catch-all 404:

```yaml
  # Project Janus (VLESS proxy)
  - hostname: janus.yourdomain.com
    service: http://192.168.0.103:8080
```

Create the DNS record and restart:

```bash
cloudflared tunnel route dns YOUR_TUNNEL_NAME janus.yourdomain.com
# Restart the tunnel daemon (depends on your setup)
rc-service cloudflared restart   # Alpine
systemctl restart cloudflared    # Debian/Ubuntu
```

### If you're creating a new tunnel

```bash
# Install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared-linux-amd64
mv cloudflared-linux-amd64 /usr/local/bin/cloudflared

# Authenticate
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create janus-tunnel

# Create config
cat > /etc/cloudflared/config.yml << 'EOF'
tunnel: YOUR_TUNNEL_ID
credentials-file: /root/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: janus.yourdomain.com
    service: http://192.168.0.103:8080
  - service: http_status:404
EOF

# Create DNS record
cloudflared tunnel route dns janus-tunnel janus.yourdomain.com

# Run
cloudflared tunnel run janus-tunnel
```

---

## Step 6: Cloudflare Dashboard Settings

### SSL/TLS Mode

**Dashboard → yourdomain.com → SSL/TLS → Overview**

Set to: **Full** (not Flexible, not Full Strict)

- **Flexible** breaks WebSocket
- **Full Strict** requires a valid cert on your origin (the self-signed cert won't work)
- **Full** is the correct setting

### WebSockets

**Dashboard → yourdomain.com → Network**

Ensure WebSockets is **ON** (usually enabled by default).

### Cloudflare Access (Zero Trust) — CRITICAL

If you use Cloudflare Access policies to protect your subdomains, you **must** bypass the Janus subdomain. Otherwise, Access intercepts the VLESS connection and returns a 302 redirect to the login page.

**Zero Trust → Access → Applications**

Create a bypass rule:
- Application name: `Janus Bypass`
- Subdomain: `janus.yourdomain.com`
- Action: **Bypass**

---

## Step 7: Verify the Chain

### Test from your home network

```bash
# 1. Test Xray directly (from same LAN)
curl -s -o /dev/null -w "%{http_code}" http://192.168.0.103:8080/secretpath
# Expected: 400 (Bad Request — Xray expects VLESS, not HTTP. This is normal!)

# 2. Test through Cloudflare
curl -s -o /dev/null -w "%{http_code}" https://janus.yourdomain.com/secretpath
# Expected: 400 (same reason — means Cloudflare reaches Xray successfully!)
# If you get 302 → Cloudflare Access is intercepting (see Step 6)
# If you get 502 → Tunnel can't reach the Xray container (check IP/port)
```

### Test with a real client

Import the VLESS link in Nekobox and check:
1. `https://ifconfig.me` → Should show your home public IP
2. `https://youtube.com` → Should load normally

---

## Step 8: Multi-User Support

### Adding clients

In 3x-ui panel:
1. Open the `janus-cloudflare` inbound
2. Click **Cliente** → **Añadir cliente**
3. A new UUID is generated automatically
4. Set a name in the "email" field (it's just a label, e.g., `pablo`, `david`)
5. Save

### Exporting links

Each client gets their own `vless://` link. Export from the panel, then modify for external use:

**Panel exports** (local format):
```
vless://UUID@192.168.0.103:8080?type=ws&path=/secretpath&security=none
```

**You need** (Cloudflare format):
```
vless://UUID@CLOUDFLARE_IP:443?type=ws&path=/secretpath&host=janus.yourdomain.com&security=tls&sni=janus.yourdomain.com
```

Changes:
- Address: `192.168.0.103` → Cloudflare IP (e.g., `104.21.33.188`)
- Port: `8080` → `443`
- Security: `none` → `tls`
- Add: `host` and `sni` = your Cloudflare subdomain

### Finding your Cloudflare IP

```bash
dig janus.yourdomain.com +short
# Returns something like: 104.21.33.188
```

Use this IP as the address in the VLESS link. This bypasses DNS filtering at the school.

### Disabling a user

In the panel, toggle the client's status or delete them. Their UUID becomes invalid immediately.

---

## Complete Example Config

See [configs/](../configs/) for ready-to-use configuration files.

---

**Next**: [05 - Client Configuration](05-Client-Configuration.md) — Setting up the student's device
