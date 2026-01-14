#!/bin/bash
#
# shutdown-distributed.sh
#
# Shutdown the distributed OpenCode infrastructure across two SPARKS.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "=== Shutting Down Distributed OpenCode ==="
echo

# Stop vLLM serve
echo "Stopping vLLM serve..."
pkill -f "vllm serve" 2>/dev/null && log_info "vLLM serve stopped" || log_info "vLLM serve not running"

# Stop llama-server
echo "Stopping llama-server..."
pkill -f "llama-server" 2>/dev/null && log_info "llama-server stopped" || log_info "llama-server not running"

# Stop Ray containers
echo "Stopping Ray containers..."
containers=$(docker ps --format '{{.Names}}' | grep -E '^node-' || true)
if [[ -n "$containers" ]]; then
    echo "$containers" | while read -r c; do
        log_info "Stopping $c..."
        docker stop "$c" 2>/dev/null && log_info "$c stopped" || log_info "Could not stop $c"
    done
    docker rm "$containers" 2>/dev/null || true
else
    log_info "No Ray containers running"
fi

echo
log_success "Distributed infrastructure shutdown complete"
