#!/bin/bash
#
# shutdown.sh
#
# Clean shutdown of the distributed OpenCode infrastructure across two SPARKS.
#
# Usage:
#   ./shutdown.sh              # Shutdown local node only
#   ./shutdown.sh --all        # Shutdown local + remote worker
#   ./shutdown.sh --worker     # Shutdown remote worker only
#   ./shutdown.sh --force      # Force kill without graceful drain
#
# Environment variables:
#   WORKER_HOST  - Worker node hostname/IP (default: reads from ~/.opencode/worker_host)
#   DRAIN_TIMEOUT - Seconds to wait for graceful drain (default: 30)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

: "${DRAIN_TIMEOUT:=30}"
: "${WORKER_HOST:=}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SHUTDOWN_LOCAL=true
SHUTDOWN_WORKER=false
FORCE_KILL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            SHUTDOWN_WORKER=true
            shift
            ;;
        --worker)
            SHUTDOWN_LOCAL=false
            SHUTDOWN_WORKER=true
            shift
            ;;
        --force)
            FORCE_KILL=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--all|--worker] [--force]"
            echo "  --all     Shutdown local node and remote worker"
            echo "  --worker  Shutdown remote worker only"
            echo "  --force   Force kill without graceful drain"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

get_worker_host() {
    if [[ -n "$WORKER_HOST" ]]; then
        echo "$WORKER_HOST"
        return
    fi
    local hostfile="$HOME/.opencode/worker_host"
    if [[ -f "$hostfile" ]]; then
        cat "$hostfile"
    fi
}

get_head_container() {
    docker ps --format '{{.Names}}' | grep -E '^node-' | head -n 1 || true
}

graceful_vllm_shutdown() {
    local container="$1"
    if [[ -z "$container" ]]; then
        return 0
    fi

    log_info "Sending graceful shutdown to vLLM..."

    # Check if vLLM is running in the container
    if ! docker exec "$container" pgrep -f "vllm" >/dev/null 2>&1; then
        log_info "vLLM not running in container"
        return 0
    fi

    # Send SIGTERM for graceful shutdown
    docker exec "$container" pkill -TERM -f "vllm" 2>/dev/null || true

    if [[ "$FORCE_KILL" == "true" ]]; then
        log_info "Force mode: skipping drain wait"
        docker exec "$container" pkill -9 -f "vllm" 2>/dev/null || true
        return 0
    fi

    # Wait for graceful drain
    log_info "Waiting up to ${DRAIN_TIMEOUT}s for vLLM to drain..."
    local elapsed=0
    while [[ $elapsed -lt $DRAIN_TIMEOUT ]]; do
        if ! docker exec "$container" pgrep -f "vllm" >/dev/null 2>&1; then
            log_success "vLLM shut down gracefully"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo

    log_warn "vLLM did not exit gracefully, forcing..."
    docker exec "$container" pkill -9 -f "vllm" 2>/dev/null || true
}

stop_ray_gracefully() {
    local container="$1"
    if [[ -z "$container" ]]; then
        return 0
    fi

    log_info "Stopping Ray in container $container..."
    docker exec "$container" ray stop 2>/dev/null || true
    sleep 2
}

shutdown_local_containers() {
    log_info "Stopping local Ray containers..."

    local containers
    containers=$(docker ps --format '{{.Names}}' | grep -E '^node-' || true)

    if [[ -z "$containers" ]]; then
        log_info "No Ray containers running locally"
        return 0
    fi

    echo "$containers" | while read -r c; do
        if [[ -n "$c" ]]; then
            log_info "Stopping container: $c"
            docker stop -t 10 "$c" 2>/dev/null || log_warn "Could not stop $c"
            docker rm "$c" 2>/dev/null || true
            log_success "Container $c removed"
        fi
    done
}

shutdown_local_processes() {
    # Stop any standalone llama-server processes
    if pgrep -f "llama-server" >/dev/null 2>&1; then
        log_info "Stopping llama-server processes..."
        pkill -TERM -f "llama-server" 2>/dev/null || true
        sleep 2
        pkill -9 -f "llama-server" 2>/dev/null || true
        log_success "llama-server stopped"
    fi

    # Kill any orphaned runCluster.sh processes
    if pgrep -f "runCluster.sh" >/dev/null 2>&1; then
        log_info "Stopping runCluster.sh processes..."
        pkill -TERM -f "runCluster.sh" 2>/dev/null || true
        sleep 1
        pkill -9 -f "runCluster.sh" 2>/dev/null || true
    fi

    # Also check for old run_cluster.sh processes
    if pgrep -f "run_cluster.sh" >/dev/null 2>&1; then
        log_info "Stopping run_cluster.sh processes..."
        pkill -TERM -f "run_cluster.sh" 2>/dev/null || true
        sleep 1
        pkill -9 -f "run_cluster.sh" 2>/dev/null || true
    fi
}

shutdown_worker_node() {
    local worker_host
    worker_host=$(get_worker_host)

    if [[ -z "$worker_host" ]]; then
        log_warn "Worker host not configured. Set WORKER_HOST or create ~/.opencode/worker_host"
        return 1
    fi

    log_info "Shutting down worker node: $worker_host"

    # Test SSH connectivity
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$worker_host" "echo ok" >/dev/null 2>&1; then
        log_error "Cannot connect to worker via SSH: $worker_host"
        log_info "Ensure SSH keys are configured for passwordless access"
        return 1
    fi

    # Run shutdown on worker
    local force_flag=""
    [[ "$FORCE_KILL" == "true" ]] && force_flag="--force"

    log_info "Executing remote shutdown on $worker_host..."
    ssh "$worker_host" "
        # Stop containers
        containers=\$(docker ps --format '{{.Names}}' | grep -E '^node-' || true)
        if [[ -n \"\$containers\" ]]; then
            echo \"\$containers\" | while read -r c; do
                echo \"Stopping container: \$c\"
                docker stop -t 10 \"\$c\" 2>/dev/null || true
                docker rm \"\$c\" 2>/dev/null || true
            done
        fi

        # Stop any llama-server
        pkill -TERM -f 'llama-server' 2>/dev/null || true
        sleep 1
        pkill -9 -f 'llama-server' 2>/dev/null || true

        # Stop runCluster.sh
        pkill -TERM -f 'runCluster.sh' 2>/dev/null || true
        pkill -9 -f 'runCluster.sh' 2>/dev/null || true

        # Stop run_cluster.sh (old name)
        pkill -TERM -f 'run_cluster.sh' 2>/dev/null || true
        pkill -9 -f 'run_cluster.sh' 2>/dev/null || true

        echo 'Worker shutdown complete'
    " 2>&1 | while read -r line; do
        log_info "[worker] $line"
    done

    log_success "Worker node shutdown complete"
}

cleanup_state_files() {
    log_info "Cleaning up state files..."
    rm -f /tmp/runClusterHead.log 2>/dev/null || true
    rm -f /tmp/runClusterWorker.log 2>/dev/null || true
    rm -f /tmp/vllmServe.log 2>/dev/null || true
    rm -f /tmp/llama-server.pid 2>/dev/null || true
    rm -f "$HOME/.opencode/head_launcher.pid" 2>/dev/null || true
    rm -f "$HOME/.opencode/worker_launcher.pid" 2>/dev/null || true
    rm -f "$HOME/.opencode/head_container" 2>/dev/null || true
    rm -f "$HOME/.opencode/worker_container" 2>/dev/null || true
}

# Main execution
echo "=== Shutting Down Distributed OpenCode ==="
echo

if [[ "$SHUTDOWN_WORKER" == "true" ]]; then
    shutdown_worker_node || log_warn "Worker shutdown had issues"
    echo
fi

if [[ "$SHUTDOWN_LOCAL" == "true" ]]; then
    # Get head container for graceful vLLM shutdown
    head_container=$(get_head_container)

    if [[ -n "$head_container" ]]; then
        graceful_vllm_shutdown "$head_container"
        stop_ray_gracefully "$head_container"
    fi

    shutdown_local_containers
    shutdown_local_processes
    cleanup_state_files
fi

echo
log_success "Distributed infrastructure shutdown complete"
