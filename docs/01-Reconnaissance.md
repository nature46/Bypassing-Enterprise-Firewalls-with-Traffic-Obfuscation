# 01 — Reconnaissance: Mapping the Aules Firewall

## Overview

Before building anything, we needed to understand exactly what the school firewall blocks and what it allows. This phase involved systematic testing from inside the Aules network at IES Jaume I (Borriana, Spain).

All data in this document was collected live from the Aules network on March 5, 2026.

---

## Network Environment

The Aules network is a managed educational network provided by the Generalitat Valenciana:

- **Network type**: Wired + WiFi campus network
- **Gateway**: 172.30.20.1
- **DNS**: 127.0.0.53 (systemd-resolved, forwarding to internal resolvers)
- **Internet access**: Heavily filtered through multi-layer firewall
- **Public IP**: Not visible (outbound HTTPS blocked by transparent proxy)

---

## Testing Methodology

We used basic tools available on the school's Linux machines:

```bash
# TCP port reachability
timeout 3 bash -c "echo >/dev/tcp/TARGET_IP/443" && echo "OPEN" || echo "CLOSED"

# DNS resolution
dig +short DOMAIN

# HTTPS response
curl -sk --connect-timeout 5 -o /dev/null -w "%{http_code}" https://TARGET
```

---

## Layer 1: IP-Level Filtering

### Results

```
OPEN    Cloudflare      (1.1.1.1)
OPEN    Cloudflare-CDN  (104.21.33.188)
OPEN    Microsoft       (13.107.42.14)
OPEN    Microsoft-Azure (20.70.246.20)
CLOSED  AWS-EC2         (3.230.166.65)
CLOSED  Google Cloud    (142.250.185.206)
CLOSED  Oracle Cloud    (129.151.40.1)
```

### Interpretation

The firewall blocks TCP connections to cloud hosting provider IP ranges (AWS, GCP, Oracle) but allows CDN providers (Cloudflare) and major vendors (Microsoft). Blocking these would break too many legitimate websites and services.

---

## Layer 2: DNS Manipulation

### Results

```
BLOCKED    nature46.uk          → no response
HIJACKED   google.com           → forcesafesearch.google.com
OK         reddit.com           → 151.101.1.140
OK         store.steampowered.com → 2.19.221.101
OK         workers.dev          → 104.18.13.15
OK         pages.dev            → 104.18.20.135
OK         youtube.com          → 172.217.171.46
OK         twitch.tv            → 151.101.194.167
OK         anydesk.com          → 104.18.31.170
OK         teamviewer.com       → 52.223.21.92
```

### Interpretation

The DNS layer does two things:

1. **Blocks custom domains**: `nature46.uk` returns no response at all
2. **Hijacks search engines**: `google.com` redirects to `forcesafesearch.google.com` to enforce safe search

Most mainstream domains resolve normally — the filtering happens at other layers.

---

## Layer 3: HTTPS/TLS Transparent Proxy

### Results

Every HTTPS request via `curl` fails with code **000** (connection terminated):

```
000    https://reddit.com
000    https://store.steampowered.com
000    https://youtube.com
000    https://twitch.tv
000    https://anydesk.com
000    https://teamviewer.com
000    https://parsec.app
000    https://workers.dev
000    https://nature46.uk
```

### Interpretation

This is the most aggressive layer. A **transparent proxy** intercepts all HTTPS traffic at the application level and terminates connections. Even sites that resolve DNS correctly and have allowed IPs are blocked here.

This explains why services like Steam, Reddit, AnyDesk, TeamViewer, and Parsec don't work from Aules — the transparent proxy kills the HTTPS connection before it completes.

**Key observation**: `curl` (which uses the system's network stack) gets blocked, but **Nekobox in TUN mode** (which creates raw TCP connections at the network layer) bypasses this proxy entirely. This is the critical exploit.

---

## Layer 4: SNI Filtering

### Results (from Nekobox logs)

When connecting via Nekobox to a Cloudflare IP with `nature46.uk` in the SNI:

```
ERROR [300ms] connection: open connection to proxmox.nature46.uk:443 using outbound/vless[proxy]: EOF
ERROR [300ms] connection: open connection to gemini.google.com:443 using outbound/vless[proxy]: EOF
```

Every connection with a blacklisted SNI dies with EOF after ~300ms.

When connecting with `workers.dev` in the SNI:

```
✅ Connection established successfully
```

### Interpretation

Even when bypassing the transparent proxy (via TUN mode), the firewall inspects the **SNI field** in the TLS ClientHello message. The SNI is sent in plaintext before encryption begins, so the firewall can read it.

Blocked SNI patterns include:
- `nature46.uk` (custom domain)
- Likely other flagged domains

Allowed SNI patterns include:
- `workers.dev` (Cloudflare platform)
- `pages.dev` (Cloudflare platform)
- Microsoft domains

---

## Layer 5: Port Filtering

### Results

```
OPEN    Cloudflare:80    (HTTP)
OPEN    Cloudflare:443   (HTTPS)
OPEN    Cloudflare:8080  (HTTP Alternate)
CLOSED  Cloudflare:8443  (HTTPS Alternate)
CLOSED  Cloudflare:2053  (Custom)
```

### Interpretation

Standard web ports (80, 443, 8080) are open. Non-standard ports are blocked.

---

## Complete Firewall Model

```
┌─────────────────────────────────────────────────────────┐
│                   AULES FIREWALL                        │
│                                                         │
│  Layer 1: IP Blocklist                                  │
│  ├── ❌ AWS, Google Cloud, Oracle → TCP RST             │
│  └── ✅ Cloudflare, Microsoft → PASS                   │
│                                                         │
│  Layer 2: DNS Manipulation                              │
│  ├── ❌ nature46.uk → no response                      │
│  ├── ⚠️ google.com → forcesafesearch.google.com        │
│  └── ✅ workers.dev, reddit.com → normal resolution    │
│                                                         │
│  Layer 3: Transparent HTTPS Proxy                       │
│  ├── Intercepts all HTTPS at application level          │
│  ├── ❌ curl/browser HTTPS → 000 (terminated)          │
│  └── ✅ Raw TCP (TUN mode) → BYPASSES this layer       │
│                                                         │
│  Layer 4: SNI Inspection                                │
│  ├── ❌ nature46.uk in SNI → EOF at 300ms              │
│  └── ✅ workers.dev in SNI → PASS                      │
│                                                         │
│  Layer 5: Port Filtering                                │
│  ├── ✅ 80, 443, 8080 → OPEN                           │
│  └── ❌ 8443, 2053 → CLOSED                            │
└─────────────────────────────────────────────────────────┘
```

---

## Attack Vector

The bypass chain exploits every layer simultaneously:

1. **IP**: Connect to Cloudflare IP (trusted) ✅
2. **DNS**: Use IP address directly, skip DNS entirely ✅
3. **Transparent Proxy**: Use TUN mode to create raw TCP (bypasses proxy) ✅
4. **SNI**: Use `workers.dev` as SNI (Cloudflare platform, allowed) ✅
5. **Port**: Use port 443 (standard HTTPS) ✅

```
[Nekobox TUN] → TCP:443 → Cloudflare IP → TLS (SNI: workers.dev) → Worker → Tunnel → Xray → Internet
```

---

## Recon Script

See [scripts/recon.sh](../scripts/recon.sh) for the automated reconnaissance script used to collect this data.

---

**Next**: [02 - Architecture](02-Architecture.md) — How we designed the solution based on these findings
