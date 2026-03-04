# 03 — AWS EC2 Setup (Phase 1)

## Overview

The first approach used an AWS EC2 instance running VLESS Reality. This worked perfectly from home networks but was **blocked at the school** due to AWS IP range filtering.

This guide is included for completeness and because VLESS Reality is an excellent technique for networks that don't block cloud IPs.

---

## Prerequisites

- AWS account (Academy credits or free tier)
- SSH key pair
- Domain name (optional for Reality, required for other methods)

---

## Step 1: Launch EC2 Instance

### Instance Configuration

| Setting | Value |
|---------|-------|
| AMI | Ubuntu 24.04 LTS |
| Instance type | t3.small (2 vCPU, 2GB RAM) |
| Region | us-east-1 (or closest to you) |
| Storage | 20GB gp3 |
| Security Group | Allow TCP 443 inbound from 0.0.0.0/0 |

### Security Group Rules

```
Inbound:
  - TCP 443 from 0.0.0.0/0 (VLESS proxy)
  - TCP 22  from YOUR_IP/32 (SSH management)
  - TCP 2053 from YOUR_IP/32 (3x-ui panel)

Outbound:
  - All traffic allowed
```

---

## Step 2: Install 3x-ui + Xray

SSH into the instance and run:

```bash
ssh -i labsuser.pem ubuntu@YOUR_EC2_IP

# Update system
sudo apt update && sudo apt upgrade -y

# Install 3x-ui (includes Xray-core)
sudo bash -c "$(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
```

During installation:
- Set panel port: `2053`
- Set username and password
- For SSL: choose option 3 (custom) and generate self-signed cert:

```bash
sudo openssl req -x509 -newkey rsa:2048 -keyout /root/key.pem -out /root/cert.pem -days 365 -nodes -subj "/CN=proxy"
```

---

## Step 3: Configure VLESS Reality Inbound

Access the panel at `https://YOUR_EC2_IP:2053/YOUR_BASEPATH`

Create a new inbound with these settings:

| Field | Value |
|-------|-------|
| Protocol | vless |
| Port | 443 |
| Transport | tcp |
| Security | reality |
| SNI (dest) | microsoft.com:443 |
| Sniffing | Enabled (HTTP, TLS, QUIC, FAKEDNS) |

### How Reality Works

VLESS Reality makes your proxy impersonate a real HTTPS server. When someone connects to port 443:

- **With the correct UUID**: Traffic is proxied through VLESS
- **Without the UUID**: The connection is transparently forwarded to microsoft.com, making the server appear to be a legitimate Microsoft server

This defeats active probing — censors can't distinguish your proxy from the real microsoft.com.

---

## Step 4: Test from Home

Export the `vless://` link from 3x-ui and import it into your client:

- **Windows**: V2RayN → Import from clipboard
- **Linux**: Nekobox → Import from clipboard

Verify:
1. Visit `https://ifconfig.me` — should show the EC2 public IP
2. Visit `https://youtube.com` — should load normally
3. Check DNS leaks at `https://dnsleaktest.com`

---

## Why This Failed at School

Testing from the Aules network:

```bash
# Direct TCP test to EC2
$ timeout 3 bash -c "echo >/dev/tcp/3.230.166.65/443"
# Result: TIMEOUT → BLOCKED

# The firewall blocks the entire AWS IP range
# It doesn't matter that Reality makes the traffic look legitimate
# The connection never reaches the server
```

**Lesson learned**: IP reputation trumps traffic disguise. If the destination IP is blacklisted, no amount of protocol obfuscation helps.

---

## When to Use This Approach

VLESS Reality on a cloud server is the right choice when:

- The network **doesn't block cloud provider IPs** (most home ISPs, cafes, hotels)
- You need **maximum protocol stealth** (Reality defeats DPI and active probing)
- You want a **simple single-server setup** (no tunnel infrastructure needed)
- **Latency isn't critical** (cloud server may be far from you)

For networks that block cloud IPs (like Aules), see [04 - Proxmox Homelab Setup](04-Proxmox-Homelab-Setup.md).

---

**Next**: [04 - Proxmox Homelab Setup](04-Proxmox-Homelab-Setup.md) — The solution that actually works at school
