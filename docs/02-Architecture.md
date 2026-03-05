# 02 — Architecture: Technical Deep-Dive

## Overview

This document explains each component in the Project Janus stack, why it was chosen, and how the pieces fit together to bypass a 5-layer enterprise firewall.

---

## Component Breakdown

### Xray-core — The Proxy Engine

[Xray-core](https://github.com/XTLS/Xray-core) is a high-performance network proxy tool. It accepts connections using the VLESS protocol and forwards them to the internet.

**Why Xray-core**:

| Feature | Xray-core | V2Ray | Shadowsocks |
|---------|-----------|-------|-------------|
| VLESS protocol | ✅ | ✅ | ❌ |
| Reality (TLS camouflage) | ✅ | ❌ | ❌ |
| WebSocket transport | ✅ | ✅ | Plugin needed |
| Active development | ✅ | Slower | ✅ |

### VLESS Protocol — Lightweight and Fast

VLESS is a stateless proxy protocol. Compared to VMess, it has zero encryption overhead because TLS handles that layer.

```
Client sends:    [VLESS header: UUID + destination] [payload data]
Server receives: Validates UUID → Forwards payload to destination
```

The UUID acts as authentication — each user gets their own UUID for access control.

### WebSocket Transport — Hiding in Plain Sight

WebSocket is used by millions of websites (Slack, Discord, trading platforms). Running VLESS inside WebSocket makes the traffic indistinguishable from normal web traffic.

**Why not raw TCP?** Cloudflare Tunnel only supports HTTP/WebSocket, not raw TCP. WebSocket on port 443 also blends with legitimate HTTPS traffic.

### Cloudflare Worker — SNI Fronting

The [Cloudflare Worker](https://developers.cloudflare.com/workers/) is the critical innovation that defeated the Aules firewall's SNI filtering.

**The problem**: The firewall inspects the TLS SNI field and blocks connections with `nature46.uk`.

**The solution**: A Worker running on `janus-relay.jonpeter46.workers.dev` receives the client's connection with an allowed SNI (`workers.dev`) and internally rewrites the request to `janus.nature46.uk`:

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url);
    url.hostname = "janus.nature46.uk";
    const newRequest = new Request(url, request);
    newRequest.headers.set("Host", "janus.nature46.uk");
    return fetch(newRequest);
  }
}
```

**What the firewall sees**: TLS connection to a Cloudflare IP with SNI `workers.dev` — completely legitimate.

**What actually happens**: The Worker forwards everything to `janus.nature46.uk` which routes through the Cloudflare Tunnel to the home server.

### Cloudflare Tunnel — The Bridge

[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) creates an encrypted outbound connection from the home server to Cloudflare's edge network.

**Key properties**:

- **Outbound only**: No incoming connections needed
- **No ports needed**: Works behind CG-NAT and firewalls
- **Free tier**: No cost
- **Trusted IPs**: Cloudflare's IP ranges pass enterprise firewalls

### 3x-ui — Management Interface

[3x-ui](https://github.com/MHSanaei/3x-ui) provides a web GUI for Xray-core:

- Create/delete inbounds and client accounts
- Monitor traffic per user
- Export VLESS connection URIs
- Configure transport settings

### Nekobox — The Client (TUN Mode is Critical)

[Nekobox](https://github.com/MatsuriDayo/nekoray) runs on the student's device and has two modes:

- **System Proxy**: Routes browser traffic through the proxy (uses system network stack)
- **TUN Mode**: Creates a virtual network interface that captures ALL traffic at the network layer

**TUN mode is essential** for the Aules bypass. The transparent proxy intercepts traffic from the system network stack (which is why `curl` returns 000). TUN mode operates below this layer, creating raw TCP connections that the proxy can't intercept.

---

## Complete Traffic Flow

```
Step 1: Nekobox (TUN mode) creates raw TCP connection
        → Bypasses transparent proxy (Layer 3)

Step 2: TCP connects to Cloudflare IP (104.21.x.x:443)
        → Passes IP blocklist (Layer 1)
        → Uses port 443 (Layer 5)

Step 3: TLS handshake with SNI "janus-relay.jonpeter46.workers.dev"
        → Passes SNI filter (Layer 4) — workers.dev is allowed

Step 4: Worker receives HTTPS request
        → Rewrites hostname to janus.nature46.uk
        → Forwards internally within Cloudflare

Step 5: Cloudflare routes to the tunnel for janus.nature46.uk
        → Tunnel delivers to home server (192.168.0.103:8080)

Step 6: Xray-core validates UUID and processes VLESS request
        → Forwards traffic to the internet

Step 7: Response travels back through the same chain
```

---

## Network Diagram

```
                    SCHOOL NETWORK (Aules)
    ┌──────────────────────────────────────────────┐
    │                                              │
    │  ┌──────────┐    TCP 443      ┌──────────┐  │
    │  │ Student  │ ──────────────▶ │ Firewall │  │
    │  │ Nekobox  │  CF IP + SNI:   │ 5 layers │  │
    │  │ TUN mode │  workers.dev    └────┬─────┘  │
    │  └──────────┘                      │ ✅     │
    │   bypasses                         │        │
    │   transparent                      │        │
    │   proxy                            │        │
    └────────────────────────────────────┼────────┘
                                         │
                          ┌──────────────▼──────────────┐
                          │     CLOUDFLARE EDGE          │
                          │                              │
                          │  ┌──────────────────────┐   │
                          │  │   Worker (janus-relay)│   │
                          │  │   Rewrites host to    │   │
                          │  │   janus.nature46.uk   │   │
                          │  └──────────┬───────────┘   │
                          │             │               │
                          │  ┌──────────▼───────────┐   │
                          │  │   Tunnel Routing      │   │
                          │  │   janus.nature46.uk   │   │
                          │  └──────────┬───────────┘   │
                          └─────────────┼───────────────┘
                                        │
                          Cloudflare Tunnel (outbound)
                                        │
                    HOME NETWORK (Borriana)
    ┌───────────────────────────────────┼──────────┐
    │                                   │          │
    │  ┌──────────┐   tunnel    ┌──────▼──────┐   │
    │  │ Proxmox  │◀═══════════▶│ LXC-101     │   │
    │  │  Odin    │             │ cloudflared │   │
    │  │ .0.100   │             │ .0.111      │   │
    │  └──────────┘             └─────────────┘   │
    │                                   │          │
    │                           ┌──────▼──────┐   │
    │                           │ LXC-109     │   │
    │                           │ Janus       │   │
    │                           │ Xray :8080  │   │
    │                           │ 3x-ui :2053 │   │
    │                           │ .0.103      │   │
    │                           └──────┬──────┘   │
    │                                  │          │
    │                           ┌──────▼──────┐   │
    │                           │   Router    │   │
    │                           │  CG-NAT    │   │
    │                           └──────┬──────┘   │
    └──────────────────────────────────┼──────────┘
                                       │
                                  ┌────▼────┐
                                  │ Internet │
                                  └──────────┘
```

---

## Security Considerations

### What the firewall sees

```
Source:      Student's PC (172.30.x.x)
Destination: Cloudflare IP (104.21.x.x:443)
SNI:         janus-relay.jonpeter46.workers.dev
Protocol:    TLS 1.3 WebSocket
Content:     Encrypted — invisible to DPI
```

This is indistinguishable from any website using Cloudflare Workers.

### What Cloudflare sees

- WebSocket traffic from Worker to origin
- VLESS payload is opaque binary data
- Low traffic volume doesn't trigger review

### What the home ISP sees

- Standard Cloudflare Tunnel connection (outbound)
- Identical to millions of legitimate tunnel users
- CG-NAT is irrelevant (outbound connection)

---

**Next**: [03 - AWS EC2 Setup](03-AWS-EC2-Setup.md) — Alternative approach using VLESS Reality
