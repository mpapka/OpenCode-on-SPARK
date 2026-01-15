#!/bin/bash
#
# shutdown.sh - Clean shutdown of MiniMax-M2.1 llama-server
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SERVER_PORT=8080

echo "=== Shutting down MiniMax-M2.1 Server ==="
echo

# Find and kill llama-server processes
PIDS=$(pgrep -f "llama-server.*minimax" 2>/dev/null || true)

if [[ -z "$PIDS" ]]; then
    # Try broader search
    PIDS=$(pgrep -f "llama-server" 2>/dev/null || true)
fi

if [[ -n "$PIDS" ]]; then
    log_info "Found llama-server process(es): $PIDS"

    for PID in $PIDS; do
        log_info "Sending SIGTERM to PID $PID..."
        kill -TERM "$PID" 2>/dev/null || true
    done

    # Wait for graceful shutdown
    log_info "Waiting for graceful shutdown..."
    sleep 2

    # Check if still running
    for PID in $PIDS; do
        if kill -0 "$PID" 2>/dev/null; then
            log_warn "Process $PID still running, sending SIGKILL..."
            kill -9 "$PID" 2>/dev/null || true
        fi
    done

    log_success "llama-server stopped"
else
    log_info "No llama-server processes found"
fi

# Check if port is still in use
if lsof -i :$SERVER_PORT &>/dev/null; then
    log_warn "Port $SERVER_PORT still in use, killing..."
    fuser -k $SERVER_PORT/tcp 2>/dev/null || true
    sleep 1
fi

# Clean up PID file if exists
if [[ -f /tmp/llama-server.pid ]]; then
    rm -f /tmp/llama-server.pid
    log_info "Removed PID file"
fi

# Verify shutdown
if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
    log_warn "Server still responding on port $SERVER_PORT"
    exit 1
else
    log_success "Server stopped successfully"
fi

echo
echo "To restart: ./setup.sh --launch-only"
