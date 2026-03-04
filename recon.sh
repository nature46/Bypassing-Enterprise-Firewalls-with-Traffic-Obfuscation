#!/bin/bash
# =============================================
# Project Janus — Network Reconnaissance Script
# =============================================
# Run this from inside a restricted network to map
# what the firewall blocks and allows.
#
# Usage: chmod +x recon.sh && ./recon.sh
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "  Project Janus — Network Recon"
echo "  $(date)"
echo "========================================"
echo ""

# --- IP Reachability Tests (TCP 443) ---
echo "--- TCP 443 Reachability ---"
declare -A targets=(
    ["Cloudflare"]="1.1.1.1"
    ["Microsoft"]="20.70.246.20"
    ["AWS EC2"]="3.230.166.65"
    ["Google Cloud"]="142.250.185.206"
    ["Oracle Cloud"]="129.151.40.1"
    ["Akamai CDN"]="23.45.67.89"
)

for name in "${!targets[@]}"; do
    ip="${targets[$name]}"
    if timeout 3 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null; then
        echo -e "  ${GREEN}OPEN${NC}    $name ($ip)"
    else
        echo -e "  ${RED}CLOSED${NC}  $name ($ip)"
    fi
done

echo ""

# --- DNS Resolution Tests ---
echo "--- DNS Resolution ---"
domains=("nature46.uk" "workers.dev" "pages.dev" "google.com" "cloudflare.com")

for domain in "${domains[@]}"; do
    result=$(nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | head -1 | awk '{print $2}')
    if [ -n "$result" ]; then
        echo -e "  ${GREEN}OK${NC}      $domain → $result"
    else
        echo -e "  ${RED}BLOCKED${NC} $domain"
    fi
done

echo ""

# --- HTTP Response Tests ---
echo "--- HTTP Response Codes ---"
urls=("https://1.1.1.1" "https://cloudflare.com" "https://youtube.com" "https://amazon.com")

for url in "${urls[@]}"; do
    code=$(curl -sk --connect-timeout 5 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    if [ "$code" = "000" ]; then
        echo -e "  ${RED}TIMEOUT${NC} $url"
    elif [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
        echo -e "  ${GREEN}$code${NC}     $url"
    else
        echo -e "  ${YELLOW}$code${NC}     $url"
    fi
done

echo ""

# --- Network Info ---
echo "--- Network Info ---"
echo "  Default gateway: $(ip route | grep default | awk '{print $3}')"
echo "  DNS servers: $(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')"
echo "  Public IP: $(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "UNREACHABLE")"

echo ""
echo "========================================"
echo "  Recon complete"
echo "========================================"
