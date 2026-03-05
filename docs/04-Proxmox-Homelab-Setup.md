# 04 — Proxmox Homelab Setup (Final Solution)

## Overview

This is the complete working solution. It runs Xray-core on a Proxmox LXC container at home, uses Cloudflare Tunnel for connectivity, and a Cloudflare Worker for SNI fronting to bypass even the most aggressive firewalls.

**Requirements**:
- A server running Proxmox VE (or any Linux box)
- A Cloudflare account with a domain
- A Cloudflare Tunnel (existing or new)

---

## Step 1: Create the LXC Container

```bash
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

**Notes**:
- Use a **privileged container** — 3x-ui needs full systemd support
- **Set DNS explicitly** — LXC containers sometimes inherit broken DNS
- **Enable nesting** — required for systemd inside containers

---

## Step 2: Install Xray-core + 3x-ui

```bash
pct exec 109 -- bash

apt update && apt upgrade -y

# Generate self-signed cert (3x-ui requires SSL)
openssl req -x509 -newkey rsa:2048 -keyout /root/key.pem -out /root/cert.pem \
  -days 365 -nodes -subj "/CN=janus"

# Install 3x-ui
curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o install.sh
bash install.sh
```

During installation, choose **option 3** (Custom) for SSL and provide `/root/cert.pem` and `/root/key.pem`.

---

## Step 3: Create VLESS + WebSocket Inbound

In the 3x-ui panel (`https://192.168.0.103:2053/YOUR_BASEPATH`):

| Field | Value | Why |
|-------|-------|-----|
| Protocol | `vless` | Lightweight, no encryption overhead |
| Port | `8080` | Internal port for Cloudflare Tunnel |
| Transport | `ws` (WebSocket) | HTTP-compatible, works through CDNs |
| Path | `/secretpath` | Random string — acts as secret key |
| Host | `janus.yourdomain.com` | Your Cloudflare subdomain |
| Security | `None` | Cloudflare handles TLS |
| Sniffing | Enabled | Better DNS handling |

---

## Step 4: Configure Cloudflare Tunnel

Add the Janus ingress to your tunnel config **before** the catch-all 404:

```yaml
  # Project Janus
  - hostname: janus.yourdomain.com
    service: http://192.168.0.103:8080
```

Create DNS record and restart:

```bash
cloudflared tunnel route dns YOUR_TUNNEL_NAME janus.yourdomain.com
systemctl restart cloudflared    # or rc-service cloudflared restart
```

---

## Step 5: Cloudflare Dashboard Settings

### SSL/TLS Mode → **Full**

| Mode | Works? | Why |
|------|--------|-----|
| Flexible | ❌ | Breaks WebSocket |
| **Full** | **✅** | **Correct setting** |
| Full (Strict) | ❌ | Rejects self-signed certs |

### Cloudflare Access — Bypass Required

If you use Zero Trust Access policies, **bypass the Janus subdomain**:

**Zero Trust → Access → Applications** → Create:
- Subdomain: `janus.yourdomain.com`
- Action: **Bypass**

Without this, Access returns 302 redirects that break VLESS connections.

---

## Step 6: Create Cloudflare Worker (SNI Fronting)

This is the key step that defeats SNI filtering. The Worker provides an allowed SNI (`workers.dev`) while internally routing to your tunnel domain.

### Create the Worker

1. **Cloudflare Dashboard** → **Workers & Pages** (main menu, not inside a domain)
2. Click **Create** → **Worker** → **"Hello World" template**
3. Name: `janus-relay`
4. Click **Deploy**
5. Click **Edit Code**
6. Replace all code with:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url);
    url.hostname = "janus.yourdomain.com";

    const newRequest = new Request(url, request);
    newRequest.headers.set("Host", "janus.yourdomain.com");

    return fetch(newRequest);
  }
}
```

7. **Save and Deploy**

### Verify the Worker

```bash
curl -sk https://janus-relay.YOUR_ACCOUNT.workers.dev/secretpath
# Should return: Bad Request (Xray rejecting non-VLESS HTTP — this is correct!)
```

---

## Step 7: Verify the Complete Chain

```bash
# Test Xray directly (from LAN)
curl -s -o /dev/null -w "%{http_code}" -H "Host: janus.yourdomain.com" http://192.168.0.103:8080/secretpath
# Expected: 400

# Test through Cloudflare Tunnel
curl -s -o /dev/null -w "%{http_code}" https://janus.yourdomain.com/secretpath
# Expected: 400 (or 302 if Access bypass is missing)

# Test through Worker
curl -s -o /dev/null -w "%{http_code}" https://janus-relay.YOUR_ACCOUNT.workers.dev/secretpath
# Expected: 400
```

---

## Step 8: Build the Client Link

The VLESS link for restricted networks uses the Worker URL:

```
vless://UUID@janus-relay.YOUR_ACCOUNT.workers.dev:443?type=ws&encryption=none&path=%2Fsecretpath&host=janus-relay.YOUR_ACCOUNT.workers.dev&security=tls&sni=janus-relay.YOUR_ACCOUNT.workers.dev#janus-aules
```

**Important**: Both `host` and `sni` must point to the Worker domain, not your custom domain. This ensures the SNI in the TLS handshake is `workers.dev` (allowed) rather than your domain (blocked).

---

## Step 9: Multi-User Support

### Adding clients

In 3x-ui: open the inbound → **Client** → **Add client** → new UUID generated automatically → set a name in the "email" field → Save.

### Link format per user

```
vless://USER_UUID@janus-relay.YOUR_ACCOUNT.workers.dev:443?type=ws&encryption=none&path=%2Fsecretpath&host=janus-relay.YOUR_ACCOUNT.workers.dev&security=tls&sni=janus-relay.YOUR_ACCOUNT.workers.dev#janus-USERNAME
```

Each user has a unique UUID. You can monitor traffic per user and disable individuals from the panel.

---

**Next**: [05 - Client Configuration](05-Client-Configuration.md) — Setting up the student's device
