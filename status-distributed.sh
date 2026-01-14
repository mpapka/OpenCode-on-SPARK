#!/bin/bash
#
# status-distributed.sh
#
# Check status of the distributed OpenCode infrastructure across two SPARKS.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== Distributed OpenCode Status ==="
echo

# Check Ray cluster
echo "Ray Cluster:"
headC=$(docker ps --format '{{.Names}}' | grep -E '^node-' | head -n 1 || true)
if [[ -n "$headC" ]]; then
    echo -e "  Head container: ${GREEN}$headC${NC}"
    
    # Check worker
    workerC=$(docker ps --format '{{.Names}}' | grep -E '^node-' | tail -n 1 || true)
    if [[ -n "$workerC" ]]; then
        echo -e "  Worker container: ${GREEN}$workerC${NC}"
    else
        echo -e "  Worker container: ${RED}Not found${NC}"
    fi
    
    # Get ray status
    echo
    echo "Ray status:"
    docker exec "$headC" ray status 2>/dev/null || log_warn "Could not get ray status"
else
    echo -e "  Head container: ${RED}Not running${NC}"
fi

echo

# Check vLLM API
echo "vLLM API (port 8080):"
if curl -s "http://localhost:8080/health" >/dev/null 2>&1; then
    echo -e "  Status: ${GREEN}Running${NC}"
    curl -s "http://localhost:8080/v1/models" | jq -r '.data[0].id // "unknown"' 2>/dev/null && echo "  Model loaded"
else
    echo -e "  Status: ${RED}Not running${NC}"
fi

echo

# Check OpenCode config
echo "OpenCode:"
if [[ -f "$HOME/.config/opencode/opencode.json" ]]; then
    echo -e "  Config: ${GREEN}Configured${NC}"
else
    echo -e "  Config: ${RED}Not configured${NC}"
fi

echo

# Network connectivity
echo "Network:"
mn_iface=$(ip -o link show up | awk -F': ' '$2!="lo"{print $2}' | head -n1 || true)
if [[ -n "$mn_iface" ]]; then
    ip_addr=$(ip -4 -o addr show dev "$mn_iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)
    if [[ -n "$ip_addr" ]]; then
        echo -e "  Interface: ${GREEN}$mn_iface${NC}"
        echo -e "  IP: ${GREEN}$ip_addr${NC}"
    else
        echo -e "  Interface: ${YELLOW}$mn_iface (no IPv4)${NC}"
    fi
else
    echo -e "  Interface: ${RED}Not found${NC}"
fi
