# 01 — Reconnaissance: Mapping the Aules Firewall

## Overview

Before building anything, we needed to understand exactly what the school firewall blocks and what it allows. This phase involved systematic testing from inside the Aules network at IES Jaume I (Borriana, Spain).

---

## Network Environment

The Aules network is a managed educational network provided by the Generalitat Valenciana. Key characteristics:

- **Network type**: Wired + WiFi campus network
- **IP range**: Managed by the regional education authority
- **DNS servers**: Internal resolvers (10.239.3.7 and system resolver)
- **Internet access**: Filtered through an enterprise firewall
- **Authentication**: Network-level (device connects directly, no proxy required)

---

## Testing Methodology

We tested connectivity using basic tools available on any Linux machine:

```bash
# TCP port test (does port 443 respond?)
timeout 3 bash -c "echo >/dev/tcp/TARGET_IP/443" && echo "OPEN" || echo "CLOSED"

# HTTP response test
curl -sk --connect-timeout 5 -o /dev/null -w "%{http_code}" https://TARGET

# DNS resolution test
nslookup DOMAIN
dig DOMAIN @10.239.3.7
```

---

## Results: IP-Level Filtering

### Cloud Provider IPs — BLOCKED

The firewall maintains blocklists of major cloud provider IP ranges:

```
AWS EC2 (3.230.166.65:443)          → CLOSED
Google Cloud (142.250.185.206:443)  → CLOSED
Oracle Cloud (129.151.40.1:443)     → CLOSED
```

### CDN / Trusted Provider IPs — ALLOWED

CDN providers and major tech vendors pass through:

```
Cloudflare (1.1.1.1:443)           → OPEN
Microsoft (20.70.246.20:443)       → OPEN
Cloudflare CDN (104.21.x.x:443)   → OPEN
```

### Interpretation

The firewall uses **IP reputation lists** — it blocks entire IP ranges associated with cloud hosting providers (where someone might run a proxy or VPN) but allows IPs belonging to CDN providers and major vendors (blocking these would break too many legitimate websites).

---

## Results: DNS Filtering

### Custom Domains — BLOCKED

```bash
$ nslookup nature46.uk
# Server: 10.239.3.7
# ** server can't find nature46.uk: No answer

$ nslookup nature46.uk 8.8.8.8
# Connection timed out (external DNS also blocked)
```

The firewall intercepts DNS queries and blocks resolution of specific domains.

### Cloudflare Subdomains — ALLOWED

```bash
$ nslookup workers.dev
# Resolves successfully

$ nslookup pages.dev
# Resolves successfully
```

Cloudflare platform domains are not filtered.

### Interpretation

DNS filtering blocks custom/unknown domains but cannot block major platform domains without breaking legitimate services.

---

## Results: HTTP-Level Behavior

```bash
$ curl -v https://amazon.com
# Returns 503 (reaches server, gets error)

$ curl -v https://nature46.uk
# Returns 000 (timeout — never reaches server)

$ curl -v https://youtube.com
# Returns 200 (some sites accessible)
```

The firewall does **not** require an HTTP proxy for outbound connections. Direct HTTPS on port 443 works to allowed destinations.

---

## Firewall Model Summary

Based on our testing, the Aules firewall implements three layers of filtering:

```
Layer 1: IP Blocklist
├── Blocks cloud provider ranges (AWS, GCP, Oracle, etc.)
├── Allows CDN providers (Cloudflare, Akamai, Fastly)
└── Allows major vendors (Microsoft, Google services)

Layer 2: DNS Filtering
├── Intercepts DNS queries via internal resolver
├── Blocks resolution of flagged/unknown domains
└── Cannot block major platform domains (workers.dev, etc.)

Layer 3: Protocol Inspection (Limited)
├── Allows standard HTTPS on port 443
├── No HTTP proxy requirement
├── No apparent deep packet inspection of TLS content
└── WebSocket connections pass through normally
```

---

## Attack Vector Identified

The gap in the firewall is clear:

1. **Cloudflare IPs are trusted** → Route traffic through Cloudflare
2. **WebSocket over HTTPS is allowed** → Use WebSocket as transport
3. **DNS blocks can be bypassed** → Connect to Cloudflare IP directly with SNI header
4. **No DPI on TLS content** → Encrypted proxy traffic is invisible

This leads to the architecture:

```
[Client] → HTTPS/WSS to Cloudflare IP → Cloudflare Tunnel → Home Proxy Server → Internet
```

---

## Recon Script

Here's the script we used for testing (run from inside the target network):

```bash
#!/bin/bash
# Project Janus — Network Reconnaissance Script
# Run from inside the restricted network

echo "=== Project Janus Network Recon ==="
echo "Date: $(date)"
echo ""

# IP-level tests
echo "--- IP Reachability (TCP 443) ---"
for target in \
    "1.1.1.1:Cloudflare" \
    "20.70.246.20:Microsoft" \
    "3.230.166.65:AWS-EC2" \
    "142.250.185.206:Google" \
    "129.151.40.1:Oracle"; do
    ip=$(echo $target | cut -d: -f1)
    name=$(echo $target | cut -d: -f2)
    timeout 3 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null && echo "$name ($ip) → OPEN" || echo "$name ($ip) → CLOSED"
done

echo ""
echo "--- DNS Resolution ---"
for domain in nature46.uk workers.dev pages.dev google.com; do
    result=$(nslookup $domain 2>/dev/null | grep "Address:" | tail -1)
    echo "$domain → ${result:-BLOCKED}"
done

echo ""
echo "--- HTTP Tests ---"
for url in https://1.1.1.1 https://nature46.uk https://workers.dev; do
    code=$(curl -sk --connect-timeout 5 -o /dev/null -w "%{http_code}" $url 2>/dev/null)
    echo "$url → HTTP $code"
done
```

---

**Next**: [02 - Architecture](02-Architecture.md) — How we designed the solution based on these findings
