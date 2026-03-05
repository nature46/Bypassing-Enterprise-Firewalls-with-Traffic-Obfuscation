#!/bin/bash
# =============================================
# Project Janus — Network Reconnaissance Script
# =============================================
# Maps all 5 firewall layers: IP blocklist, DNS manipulation,
# transparent proxy, SNI filtering, and port filtering.
#
# Usage: chmod +x recon.sh && ./recon.sh
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "========================================"
echo "  Project Janus — Network Recon"
echo "  $(date)"
echo "========================================"

# --- Layer 1: IP Blocklist ---
echo ""
echo -e "${CYAN}=== LAYER 1: IP BLOCKLIST (TCP 443) ===${NC}"
declare -A targets=(
    ["Cloudflare"]="1.1.1.1"
    ["Cloudflare-CDN"]="104.21.33.188"
    ["Microsoft"]="13.107.42.14"
    ["Microsoft-Azure"]="20.70.246.20"
    ["AWS-EC2"]="3.230.166.65"
    ["Google-Cloud"]="142.250.185.206"
    ["Oracle-Cloud"]="129.151.40.1"
)

for name in "${!targets[@]}"; do
    ip="${targets[$name]}"
    if timeout 3 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null; then
        echo -e "  ${GREEN}OPEN${NC}    $name ($ip)"
    else
        echo -e "  ${RED}CLOSED${NC}  $name ($ip)"
    fi
done

# --- Layer 2: DNS Manipulation ---
echo ""
echo -e "${CYAN}=== LAYER 2: DNS RESOLUTION ===${NC}"
domains=("nature46.uk" "google.com" "reddit.com" "store.steampowered.com" "workers.dev" "pages.dev" "youtube.com" "twitch.tv" "anydesk.com" "teamviewer.com")

for domain in "${domains[@]}"; do
    result=$(dig +short "$domain" 2>/dev/null | head -1)
    if [ -z "$result" ]; then
        echo -e "  ${RED}BLOCKED${NC} $domain"
    elif echo "$result" | grep -q "forcesafesearch"; then
        echo -e "  ${YELLOW}HIJACKED${NC} $domain → $result"
    else
        echo -e "  ${GREEN}OK${NC}      $domain → $result"
    fi
done

# --- Layer 3: Transparent Proxy ---
echo ""
echo -e "${CYAN}=== LAYER 3: HTTPS TRANSPARENT PROXY ===${NC}"
urls=("https://reddit.com" "https://youtube.com" "https://workers.dev" "https://1.1.1.1" "https://microsoft.com" "https://google.com")

for url in "${urls[@]}"; do
    code=$(curl -sk --connect-timeout 5 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    if [ "$code" = "000" ]; then
        echo -e "  ${RED}000${NC}     $url (connection killed)"
    elif [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
        echo -e "  ${GREEN}$code${NC}     $url"
    else
        echo -e "  ${YELLOW}$code${NC}     $url"
    fi
done

# --- Layer 5: Port Filtering ---
echo ""
echo -e "${CYAN}=== LAYER 5: PORT FILTERING (Cloudflare IP) ===${NC}"
for port in 80 443 8080 8443 2053; do
    if timeout 3 bash -c "echo >/dev/tcp/104.21.33.188/$port" 2>/dev/null; then
        echo -e "  ${GREEN}OPEN${NC}    Cloudflare:$port"
    else
        echo -e "  ${RED}CLOSED${NC}  Cloudflare:$port"
    fi
done

# --- Network Info ---
echo ""
echo -e "${CYAN}=== NETWORK INFO ===${NC}"
echo "  Gateway: $(ip route | grep default | awk '{print $3}')"
echo "  DNS: $(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')"
echo "  Public IP: $(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo 'UNREACHABLE')"

echo ""
echo "========================================"
echo "  Recon complete"
echo "  Note: Layer 4 (SNI filtering) requires"
echo "  a VLESS client to test properly."
echo "========================================"
