# 02 — Architecture: Technical Deep-Dive

## Overview

This document explains each component in the Project Janus stack, why it was chosen, and how the pieces fit together.

---

## Component Breakdown

### Xray-core — The Proxy Engine

[Xray-core](https://github.com/XTLS/Xray-core) is a high-performance network proxy tool. It's the engine that actually tunnels your traffic through the firewall.

**What it does**: Accepts incoming connections using the VLESS protocol, then forwards them to the internet.

**Why Xray-core over alternatives**:

| Feature | Xray-core | V2Ray | Shadowsocks |
|---------|-----------|-------|-------------|
| VLESS protocol | ✅ | ✅ | ❌ |
| Reality (TLS camouflage) | ✅ | ❌ | ❌ |
| WebSocket transport | ✅ | ✅ | Plugin needed |
| Active development | ✅ | Slower | ✅ |
| Performance | Excellent | Good | Good |

### VLESS Protocol — Lightweight and Fast

VLESS is a stateless proxy protocol that carries your traffic inside a thin wrapper. Compared to VMess (its predecessor), VLESS has no encryption overhead because TLS handles that layer.

**How it works**:

```
Client sends:    [VLESS header: UUID + destination] [payload data]
Server receives: Validates UUID → Forwards payload to destination
Server returns:  [Response data] → Client
```

The UUID acts as the authentication key — anyone with the correct UUID can use the proxy.

### WebSocket Transport — Hiding in Plain Sight

WebSocket is a standard web protocol used by millions of websites (Slack, Discord, trading platforms, etc.). By running VLESS inside WebSocket:

- The firewall sees normal WebSocket traffic to a Cloudflare IP
- The connection upgrades from HTTP to WebSocket on the `/secretpath` endpoint
- All subsequent data flows through the WebSocket tunnel

**Why not raw TCP?** Raw TCP to a custom port would be blocked. WebSocket rides on HTTP/HTTPS (port 443), which is always allowed.

### Cloudflare Tunnel — The Bridge

[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) creates an encrypted outbound connection from your server to Cloudflare's edge network. 

**Key properties**:

- **Outbound only**: Your server connects to Cloudflare, not the other way around
- **No ports needed**: Works behind CG-NAT, firewalls, whatever
- **Free tier**: No cost for basic usage
- **Trusted IPs**: Cloudflare's IP ranges are whitelisted by most enterprise firewalls

**Traffic flow**:

```
1. Client → HTTPS request to Cloudflare IP (104.21.x.x:443)
2. Cloudflare edge → Routes to your tunnel based on hostname/SNI
3. Cloudflare tunnel → Delivers to your server (http://192.168.0.103:8080)
4. Xray-core → Processes VLESS request, forwards to internet
5. Response travels back through the same path
```

### 3x-ui — Management Interface

[3x-ui](https://github.com/MHSanaei/3x-ui) provides a web GUI for managing Xray-core:

- Create/delete proxy inbounds
- Manage client accounts (individual UUIDs)
- Monitor traffic per user
- Export connection URIs for clients
- Configure transport and security settings

**Panel access**: `https://YOUR_SERVER_IP:2053/YOUR_BASEPATH`

### Nekobox / V2RayN — Client Applications

These are the applications that run on the student's device:

- **Nekobox** (Linux): Creates a TUN interface that captures all system traffic and routes it through the proxy
- **V2RayN** (Windows): Configures system proxy settings to route traffic through VLESS

Both accept VLESS URIs (the `vless://...` links) for easy configuration.

---

## Why Two Approaches?

### Approach 1: AWS EC2 + VLESS Reality (Direct)

```
[Client] ──TCP 443──▶ [AWS EC2: Xray + Reality] ──▶ [Internet]
```

**VLESS Reality** makes the proxy server impersonate a legitimate HTTPS server (like microsoft.com). If someone probes the server, they see what appears to be a real Microsoft website.

**Why it failed at school**: The Aules firewall blocks all AWS EC2 IP ranges at the IP level. It doesn't matter how well the traffic is disguised — if the destination IP is blacklisted, the connection never happens.

### Approach 2: Proxmox + Cloudflare Tunnel (CDN Fronting)

```
[Client] ──HTTPS 443──▶ [Cloudflare CDN] ══tunnel══▶ [Home Server: Xray + WS] ──▶ [Internet]
```

**VLESS WebSocket** through Cloudflare solves the IP reputation problem. The client talks to Cloudflare (trusted IP), Cloudflare relays to the home server through the tunnel.

**Why Reality isn't used here**: VLESS Reality needs raw TCP access to the proxy. Cloudflare Tunnel only supports HTTP/WebSocket. That's fine — Cloudflare provides the TLS layer, so Reality's camouflage isn't needed.

---

## Security Considerations

### What the firewall sees

```
Source:      Student's PC (10.x.x.x)
Destination: 104.21.33.188:443 (Cloudflare CDN)
Protocol:    TLS 1.3
SNI:         janus.nature46.uk (or any valid CF domain)
Content:     Encrypted (TLS) — invisible to DPI
```

This is indistinguishable from browsing any Cloudflare-hosted website.

### What Cloudflare sees

Cloudflare can see the WebSocket traffic content (since it terminates TLS), but:

- VLESS payload is additional encrypted data
- Cloudflare processes millions of WebSocket connections
- Individual low-traffic connections don't trigger review

### What your ISP sees (home connection)

- An outbound Cloudflare Tunnel connection (standard cloudflared traffic)
- This is identical to millions of legitimate Cloudflare Tunnel users
- CG-NAT is irrelevant since the tunnel is outbound

---

## Network Diagram (Complete)

```
                    SCHOOL NETWORK (Aules)
    ┌──────────────────────────────────────────────┐
    │                                              │
    │  ┌──────────┐    HTTPS/443    ┌──────────┐  │
    │  │ Student  │ ──────────────▶ │ Firewall │  │
    │  │ Nekobox  │  Cloudflare IP  │          │  │
    │  └──────────┘   104.21.x.x   └────┬─────┘  │
    │                                    │ ✅      │
    └────────────────────────────────────┼─────────┘
                                         │
                          ┌──────────────▼──────────────┐
                          │     CLOUDFLARE EDGE          │
                          │  Madrid / Barcelona PoPs     │
                          │                              │
                          │  TLS termination             │
                          │  WebSocket relay              │
                          │  Tunnel routing               │
                          └──────────────┬──────────────┘
                                         │
                          Cloudflare Tunnel (outbound)
                                         │
                    HOME NETWORK (Borriana)
    ┌────────────────────────────────────┼─────────┐
    │                                    │         │
    │  ┌──────────┐    tunnel    ┌──────▼──────┐  │
    │  │ Proxmox  │◀════════════▶│ LXC-101     │  │
    │  │  Odin    │              │ cloudflared │  │
    │  │ .0.100   │              │ .0.111      │  │
    │  └──────────┘              └─────────────┘  │
    │                                    │         │
    │                            ┌──────▼──────┐  │
    │                            │ LXC-109     │  │
    │                            │ Janus       │  │
    │                            │ Xray :8080  │  │
    │                            │ 3x-ui :2053 │  │
    │                            │ .0.103      │  │
    │                            └──────┬──────┘  │
    │                                   │         │
    │                            ┌──────▼──────┐  │
    │                            │   Router    │  │
    │                            │  CG-NAT    │  │
    │                            └──────┬──────┘  │
    └───────────────────────────────────┼─────────┘
                                        │
                                   ┌────▼────┐
                                   │ Internet │
                                   └──────────┘
```

---

**Next**: [03 - AWS EC2 Setup](03-AWS-EC2-Setup.md) — The first approach (and why it wasn't enough)
