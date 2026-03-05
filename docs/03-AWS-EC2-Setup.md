# 03 — AWS EC2 Setup (Alternative Approach)

## Overview

This approach uses an AWS EC2 instance running VLESS Reality. It works from most networks including some school WiFi networks, but **may not work from networks that block cloud provider IPs** at the TCP level.

VLESS Reality is included here because it's an excellent technique that provides maximum stealth against DPI (Deep Packet Inspection).

---

## Prerequisites

- AWS account (Academy credits or free tier)
- SSH key pair

---

## Step 1: Launch EC2 Instance

| Setting | Value |
|---------|-------|
| AMI | Ubuntu 24.04 LTS |
| Instance type | t3.small (2 vCPU, 2GB RAM) |
| Storage | 20GB gp3 |
| Security Group | TCP 443 from 0.0.0.0/0, TCP 22 from YOUR_IP |

---

## Step 2: Install 3x-ui + Xray

```bash
ssh -i labsuser.pem ubuntu@YOUR_EC2_IP

sudo apt update && sudo apt upgrade -y

# Generate SSL certificate
sudo openssl req -x509 -newkey rsa:2048 -keyout /root/key.pem -out /root/cert.pem \
  -days 365 -nodes -subj "/CN=proxy"

# Install 3x-ui
sudo bash -c "$(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)"
```

---

## Step 3: Configure VLESS Reality Inbound

In the 3x-ui panel, create an inbound:

| Field | Value |
|-------|-------|
| Protocol | vless |
| Port | 443 |
| Transport | tcp |
| Security | reality |
| SNI (dest) | microsoft.com:443 |
| Sniffing | Enabled |

### How Reality Works

VLESS Reality makes your proxy impersonate microsoft.com. Connections without the correct UUID are transparently forwarded to the real Microsoft server, making the proxy undetectable by active probing.

---

## Step 4: Test

Import the `vless://` link into V2RayN (Windows) or Nekobox (Linux) and verify:

1. `https://ifconfig.me` → Should show EC2 public IP
2. `https://youtube.com` → Should load normally

---

## Limitations

- **IP reputation**: Some enterprise firewalls block AWS IP ranges at TCP level
- **Cost**: EC2 charges apply (~€8-15/month)
- **Latency**: Server may be far from your location

For networks that block cloud IPs or filter by SNI, see [04 - Proxmox Homelab Setup](04-Proxmox-Homelab-Setup.md) for the Cloudflare Worker solution.

---

**Next**: [04 - Proxmox Homelab Setup](04-Proxmox-Homelab-Setup.md) — The solution that works everywhere
