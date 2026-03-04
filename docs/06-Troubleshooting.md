# 06 — Troubleshooting

## Overview

This document catalogs every problem we encountered during Project Janus and how we solved it. These are real issues, not theoretical scenarios.

---

## Problem: AWS EC2 IP Blocked at School

**Symptom**: VLESS Reality works from home but times out from school network.

**Diagnosis**:
```bash
timeout 3 bash -c "echo >/dev/tcp/3.230.166.65/443" && echo "OPEN" || echo "CLOSED"
# Result: CLOSED
```

**Root cause**: The school firewall blocks cloud provider IP ranges (AWS, GCP, Oracle) at the IP level.

**Solution**: Use Cloudflare Tunnel instead. Traffic goes to Cloudflare IPs (trusted by the firewall), then Cloudflare relays to your server through a tunnel.

---

## Problem: 3x-ui Won't Install in LXC Container

**Symptom**: Installation script downloads and extracts files but hangs indefinitely when trying to set up the systemd service.

**Root cause**: Unprivileged LXC containers have limited systemd functionality. 3x-ui's installer expects full systemd support.

**Solution**: Use a privileged container with nesting enabled:

```bash
pct create 109 local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
  --hostname janus \
  --features nesting=1 \
  ...
```

If 3x-ui still fails, install Xray-core directly (works without systemd):

```bash
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
```

---

## Problem: LXC Container Has No Internet

**Symptom**: `ping google.com` from inside the LXC returns "Network unreachable" or times out.

**Diagnosis**:
```bash
ip route | grep default
# Check: Is the gateway correct?

cat /etc/resolv.conf
# Check: Is there a nameserver configured?
```

**Possible causes**:

1. **IP conflict**: Another device on the network has the same IP
   ```bash
   # From Proxmox host (with LXC stopped):
   ping 192.168.0.103
   # If it responds → IP conflict
   ```

2. **Wrong gateway**: The gateway IP doesn't match your router
   ```bash
   # Fix:
   pct set 109 --net0 name=eth0,bridge=vmbr0,ip=192.168.0.103/24,gw=192.168.0.1
   ```

3. **Missing DNS**: No nameserver in resolv.conf
   ```bash
   echo "nameserver 8.8.8.8" > /etc/resolv.conf
   ```

---

## Problem: 3x-ui SSL Certificate Required

**Symptom**: During installation, the script demands an SSL certificate and won't proceed without one.

**Solution**: Generate a self-signed certificate before running the installer:

```bash
openssl req -x509 -newkey rsa:2048 -keyout /root/key.pem -out /root/cert.pem \
  -days 365 -nodes -subj "/CN=janus"
```

When the installer asks for SSL setup, choose **option 3** (Custom) and provide:
- Certificate path: `/root/cert.pem`
- Key path: `/root/key.pem`

---

## Problem: Xray Inbound Not Loading

**Symptom**: 3x-ui panel shows the inbound, but Xray's config file doesn't include it. Port 8080 doesn't respond.

**Diagnosis**:
```bash
cat /usr/local/x-ui/bin/config.json | grep secretpath
# If empty → inbound not injected

ss -tlnp | grep 8080
# If empty → Xray not listening on that port
```

**Root cause**: 3x-ui stores inbounds in a SQLite database and injects them into Xray's config at runtime. Sometimes the injection fails after creating a new inbound.

**Solution**: Restart 3x-ui:
```bash
x-ui restart
```

Verify:
```bash
cat /usr/local/x-ui/bin/config.json | grep secretpath
# Should now show the path

ss -tlnp | grep 8080
# Should show Xray listening
```

---

## Problem: Cloudflare Returns 302 Redirect

**Symptom**: Connections through Cloudflare return HTTP 302 instead of reaching Xray.

**Diagnosis**:
```bash
curl -s -o /dev/null -w "%{http_code}" https://janus.yourdomain.com/secretpath
# Returns: 302
```

**Root cause**: Cloudflare Access (Zero Trust) is intercepting the request and redirecting to the login page.

**Solution**: Create a bypass rule in Cloudflare Zero Trust:

1. Go to **Zero Trust → Access → Applications**
2. Find the rule that covers `*.yourdomain.com`
3. Add a bypass policy for `janus.yourdomain.com`

Or create a new application:
- Subdomain: `janus.yourdomain.com`
- Action: **Bypass**

After the fix:
```bash
curl -s -o /dev/null -w "%{http_code}" https://janus.yourdomain.com/secretpath
# Returns: 400 (expected — Xray doesn't serve HTTP)
```

---

## Problem: Lost Remote Access After Killing cloudflared

**Symptom**: Ran `killall cloudflared` to restart the tunnel, but the tunnel was the only remote access path to the server.

**Root cause**: Cloudflare Tunnel was the sole remote access mechanism. Killing it severed the connection with no way to restart it remotely.

**Solution**: This requires physical access to the server (or another remote access path like IPMI, NAS terminal, etc.).

**Prevention**:
- Never `killall cloudflared` — use `rc-service cloudflared restart` instead
- Set up a secondary access path (Tailscale, ZeroTier, or a second tunnel)
- Enable auto-start so the tunnel recovers from reboots:
  ```bash
  rc-update add cloudflared default  # Alpine
  systemctl enable cloudflared       # Debian/Ubuntu
  ```

---

## Problem: DNS Blocked at School

**Symptom**: `nslookup yourdomain.com` returns "No answer" from the school network.

**Root cause**: The school firewall intercepts DNS queries and blocks resolution of flagged domains.

**Solution**: The VLESS client doesn't need DNS. Configure the client to connect directly to the Cloudflare IP:

```
# Instead of:
vless://UUID@janus.yourdomain.com:443?...

# Use:
vless://UUID@104.21.33.188:443?...&host=janus.yourdomain.com&sni=janus.yourdomain.com
```

The `host` and `sni` fields tell Cloudflare which tunnel to route to, even though the connection goes to an IP address.

Find the Cloudflare IP:
```bash
# From a non-restricted network:
dig janus.yourdomain.com +short
```

---

## Problem: Cloudflare SSL Mode Causes Errors

**Symptom**: Client connects but gets TLS errors or connection resets.

**Root cause**: Cloudflare SSL mode set to "Flexible" or "Full (Strict)".

**Solution**: Set SSL to **Full** in the Cloudflare dashboard:

| Mode | Behavior | Works? |
|------|----------|--------|
| Off | No encryption | ❌ |
| Flexible | CF→Origin is HTTP | ❌ WebSocket breaks |
| **Full** | **CF→Origin is HTTP, CF→Client is HTTPS** | **✅** |
| Full (Strict) | Requires valid origin cert | ❌ Self-signed fails |

---

## Problem: "Bad Request" When Testing in Browser

**Symptom**: Visiting `https://janus.yourdomain.com/secretpath` shows "Bad Request".

**This is normal!** Xray expects VLESS protocol connections, not regular HTTP. A 400 response means the chain works correctly — Cloudflare reached Xray, and Xray rejected the non-VLESS request.

| Response | Meaning |
|----------|---------|
| 400 Bad Request | ✅ Xray is reachable (working!) |
| 404 Not Found | ⚠️ Wrong path or Xray not running |
| 302 Redirect | ❌ Cloudflare Access blocking |
| 502 Bad Gateway | ❌ Tunnel can't reach Xray |
| Timeout | ❌ Tunnel down or IP blocked |

---

## Diagnostic Commands Reference

```bash
# Check if Xray is running
ps aux | grep xray
ss -tlnp | grep 8080

# Check Xray config
cat /usr/local/x-ui/bin/config.json | grep -A5 secretpath

# Check inbound in database
sqlite3 /etc/x-ui/x-ui.db "SELECT remark, port, enable FROM inbounds;"

# Restart 3x-ui + Xray
x-ui restart

# Check Cloudflare Tunnel status
cloudflared tunnel info YOUR_TUNNEL_NAME

# Test WebSocket through Cloudflare
curl -s -o /dev/null -w "%{http_code}" https://janus.yourdomain.com/secretpath

# Test direct (from LAN)
curl -s -o /dev/null -w "%{http_code}" http://192.168.0.103:8080/secretpath
```

---

**Back to**: [README](../README.md)
