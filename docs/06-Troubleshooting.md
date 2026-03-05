# 06 — Troubleshooting

## Overview

Every problem we encountered during Project Janus and how we solved it. All real issues.

---

## Problem: All HTTPS Blocked (curl returns 000)

**Symptom**: `curl` to any HTTPS site returns 000 from the school network.

**Root cause**: A transparent proxy intercepts all HTTPS traffic at the application level.

**Solution**: Use Nekobox in **TUN mode**. TUN creates raw TCP connections at the network layer, bypassing the transparent proxy.

---

## Problem: EOF After ~300ms (SNI Filtering)

**Symptom**: Nekobox connects but every request dies with EOF:

```
ERROR [300ms] connection: open connection to ... using outbound/vless[proxy]: EOF
```

**Root cause**: The firewall inspects the SNI field in TLS ClientHello and terminates connections with blocked domains.

**Diagnosis**: If the VLESS link has `sni=janus.nature46.uk`, the SNI is blocked.

**Solution**: Use a Cloudflare Worker for SNI fronting. The link must have `sni=janus-relay.YOUR_ACCOUNT.workers.dev` (workers.dev passes the SNI filter).

See [04 - Proxmox Setup, Step 6](04-Proxmox-Homelab-Setup.md#step-6-create-cloudflare-worker-sni-fronting).

---

## Problem: 3x-ui Won't Install in LXC

**Symptom**: Installation hangs at systemd service setup.

**Root cause**: Unprivileged LXC containers have limited systemd support.

**Solution**: Use a privileged container with nesting:

```bash
pct create 109 ... --features nesting=1
```

If 3x-ui still fails, install Xray-core directly:

```bash
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
```

---

## Problem: 3x-ui Requires SSL Certificate

**Symptom**: Installation demands a certificate.

**Solution**: Generate self-signed cert first:

```bash
openssl req -x509 -newkey rsa:2048 -keyout /root/key.pem -out /root/cert.pem \
  -days 365 -nodes -subj "/CN=janus"
```

Choose **option 3** (Custom) during install.

---

## Problem: Xray Returns 404 Instead of 400

**Symptom**: `curl http://localhost:8080/secretpath` returns 404.

**Root cause**: Xray needs the Host header to match the configured host.

**Solution**: Include the Host header:

```bash
curl -s -o /dev/null -w "%{http_code}" -H "Host: janus.yourdomain.com" http://localhost:8080/secretpath
# Returns: 400 (correct — Xray rejects non-VLESS HTTP)
```

Cloudflare sends this header automatically, so clients work fine.

---

## Problem: Inbound Not Loading After Creation

**Symptom**: 3x-ui panel shows the inbound but port 8080 doesn't respond.

**Diagnosis**:
```bash
cat /usr/local/x-ui/bin/config.json | grep secretpath
ss -tlnp | grep 8080
```

**Solution**: Restart 3x-ui:
```bash
x-ui restart
```

---

## Problem: Cloudflare Returns 302 Redirect

**Symptom**: Connections return 302 instead of reaching Xray.

**Root cause**: Cloudflare Access (Zero Trust) is intercepting the request.

**Solution**: Create a bypass rule:

**Zero Trust → Access → Applications** → New:
- Subdomain: `janus.yourdomain.com`
- Action: **Bypass**

---

## Problem: Lost Remote Access After Killing cloudflared

**Symptom**: Killed the tunnel process and lost the only remote access path.

**Prevention**:
- Use `systemctl restart cloudflared` instead of `killall`
- Set up a secondary access path (Tailscale, second tunnel)
- Enable auto-start: `systemctl enable cloudflared`

---

## Problem: "Reset connection by peer" on Client

**Symptom**: Nekobox shows "reset connection by peer" errors.

**Root cause**: TUN mode needs root privileges.

**Solution**:
```bash
sudo ./nekobox
```

---

## Problem: Nekobox Download Fails

**Symptom**: `wget` or installer script stops mid-download.

**Solution**: Use `curl` with resume capability:

```bash
curl -L -C - -o nekoray.zip https://github.com/MatsuriDayo/nekoray/releases/download/4.0.1/nekoray-4.0.1-2024-12-12-linux64.zip
```

Run multiple times — `-C -` resumes from where it stopped.

---

## Problem: Cloudflare SSL Mode Causes Errors

**Root cause**: Wrong SSL mode in Cloudflare dashboard.

| Mode | Works? |
|------|--------|
| Flexible | ❌ Breaks WebSocket |
| **Full** | **✅ Correct** |
| Full (Strict) | ❌ Rejects self-signed cert |

---

## Problem: "Bad Request" in Browser

**Symptom**: Visiting `https://janus.yourdomain.com/secretpath` shows "Bad Request".

**This is normal.** Xray only accepts VLESS protocol, not HTTP. A 400 response confirms the chain works.

| Response | Meaning |
|----------|---------|
| 400 | ✅ Xray reachable (working!) |
| 404 | ⚠️ Wrong path or Xray not running |
| 302 | ❌ Cloudflare Access blocking |
| 502 | ❌ Tunnel can't reach Xray |
| Timeout | ❌ Tunnel down or IP blocked |

---

## Diagnostic Commands

```bash
# Check Xray status
x-ui status
ss -tlnp | grep 8080

# Check config
cat /usr/local/x-ui/bin/config.json | grep secretpath

# Check database
sqlite3 /etc/x-ui/x-ui.db "SELECT remark, port, enable FROM inbounds;"

# Test locally (needs Host header)
curl -s -o /dev/null -w "%{http_code}" -H "Host: janus.yourdomain.com" http://localhost:8080/secretpath

# Test through Cloudflare
curl -s -o /dev/null -w "%{http_code}" https://janus.yourdomain.com/secretpath

# Test through Worker
curl -s -o /dev/null -w "%{http_code}" https://janus-relay.YOUR_ACCOUNT.workers.dev/secretpath

# Check tunnel
pct exec 101 -- rc-service cloudflared status
```

---

**Back to**: [README](../README.md)
