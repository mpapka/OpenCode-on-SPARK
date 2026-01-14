#!/bin/bash
#
# setup-opencode-minimax-distributed.sh
#
# Complete setup script for distributed OpenCode + MiniMax-M2.1 across TWO SPARKS:
# - Downloads MiniMax-M2.1 UD-Q2_K_XL model (~86GB)
# - Builds llama.cpp with CUDA and RPC support
# - Sets up Ray cluster across two machines
# - Launches distributed llama.cpp server
# - Configures OpenCode to use distributed server
#
# Usage:
# 1. On SPARK1 (head node):
#    ./setup-opencode-minimax-distributed.sh --head
#
# 2. On SPARK2 (worker node):
#    ./setup-opencode-minimax-distributed.sh --worker <head_node_ip>
#
# This script is restartable - it will skip completed steps.
#

set -e

# Configuration
MODEL_DIR="$HOME/models/minimax-m2.1"
MODEL_NAME="MiniMax-M2.1-UD-Q2_K_XL"
MODEL_FILE1="MiniMax-M2.1-UD-Q2_K_XL-00001-of-00002.gguf"
MODEL_FILE2="MiniMax-M2.1-UD-Q2_K_XL-00002-of-00002.gguf"
MODEL_URL_BASE="https://huggingface.co/unsloth/MiniMax-M2.1-GGUF/resolve/main/UD-Q2_K_XL"
MODEL_SIZE1=49950511392  # ~50GB
MODEL_SIZE2=35967481120  # ~36GB
LLAMA_CPP_DIR="$HOME/llama.cpp"
SERVER_PORT=8080
CTX_SIZE=131072
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
RAY_PORT=6379

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if a file is fully downloaded (by size)
check_file_complete() {
    local file="$1"
    local expected_size="$2"

    if [[ -f "$file" ]]; then
        local actual_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
        if [[ "$actual_size" -ge "$expected_size" ]]; then
            return 0
        fi
    fi
    return 1
}

# Download a file with resume support
download_file() {
    local url="$1"
    local output="$2"
    local expected_size="$3"

    if check_file_complete "$output" "$expected_size"; then
        log_success "$(basename "$output") already downloaded"
        return 0
    fi

    log_info "Downloading $(basename "$output")..."
    wget -c -q --show-progress "$url" -O "$output"

    if check_file_complete "$output" "$expected_size"; then
        log_success "$(basename "$output") download complete"
        return 0
    else
        log_error "$(basename "$output") download incomplete"
        return 1
    fi
}

# Download model files
download_model() {
    log_info "=== Downloading MiniMax-M2.1 UD-Q2_K_XL ==="

    mkdir -p "$MODEL_DIR"
    cd "$MODEL_DIR"

    local file1_complete=false
    local file2_complete=false

    if check_file_complete "$MODEL_FILE1" "$MODEL_SIZE1"; then
        log_success "$MODEL_FILE1 already exists"
        file1_complete=true
    fi

    if check_file_complete "$MODEL_FILE2" "$MODEL_SIZE2"; then
        log_success "$MODEL_FILE2 already exists"
        file2_complete=true
    fi

    if $file1_complete && $file2_complete; then
        log_success "Model already fully downloaded ($(du -sh "$MODEL_DIR" | cut -f1))"
        return 0
    fi

    log_info "Starting parallel downloads..."

    local pids=()

    if ! $file1_complete; then
        wget -c -q --show-progress "$MODEL_URL_BASE/$MODEL_FILE1" -O "$MODEL_FILE1" &
        pids+=($!)
    fi

    if ! $file2_complete; then
        wget -c -q --show-progress "$MODEL_URL_BASE/$MODEL_FILE2" -O "$MODEL_FILE2" &
        pids+=($!)
    fi

    local failed=false
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=true
        fi
    done

    if $failed; then
        log_error "Some downloads failed. Re-run the script to resume."
        return 1
    fi

    log_success "Model download complete ($(du -sh "$MODEL_DIR" | cut -f1))"
}

# Build llama.cpp with CUDA and RPC support
build_llamacpp() {
    log_info "=== Building llama.cpp with CUDA + RPC ==="

    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ -x "$server_bin" ]]; then
        log_success "llama.cpp already built at $LLAMA_CPP_DIR"
        return 0
    fi

    if ! command -v cmake &> /dev/null; then
        log_error "cmake not found. Please install: sudo apt-get install cmake"
        return 1
    fi

    if ! command -v git &> /dev/null; then
        log_error "git not found. Please install: sudo apt-get install git"
        return 1
    fi

    local gpp_compiler=""
    if command -v g++-13 &> /dev/null; then
        gpp_compiler="/usr/bin/g++-13"
    elif command -v g++-12 &> /dev/null; then
        gpp_compiler="/usr/bin/g++-12"
    elif command -v g++ &> /dev/null; then
        gpp_compiler=$(which g++)
    else
        log_error "g++ not found. Please install: sudo apt-get install g++"
        return 1
    fi
    log_info "Using compiler: $gpp_compiler"

    local cuda_path=""
    if [[ -d "/usr/local/cuda" ]]; then
        cuda_path="/usr/local/cuda"
    elif [[ -d "/usr/local/cuda-13" ]]; then
        cuda_path="/usr/local/cuda-13"
    elif [[ -d "/usr/local/cuda-12" ]]; then
        cuda_path="/usr/local/cuda-12"
    else
        log_error "CUDA not found in /usr/local/cuda*"
        log_info "Please install CUDA toolkit or specify CUDA path"
        return 1
    fi
    log_info "Using CUDA: $cuda_path"

    if [[ ! -d "$LLAMA_CPP_DIR" ]]; then
        log_info "Cloning llama.cpp..."
        git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
    else
        log_info "llama.cpp repository already exists"
    fi

    cd "$LLAMA_CPP_DIR"

    log_info "Configuring build with CUDA + RPC support..."
    export PATH="$cuda_path/bin:$PATH"

    CUDAHOSTCXX="$gpp_compiler" cmake -B build \
        -DGGML_CUDA=ON \
        -DGGML_RPC=ON \
        -DGGML_CUDA_F16=ON \
        -DCMAKE_CUDA_HOST_COMPILER="$gpp_compiler" \
        -DLLAMA_CURL=OFF

    if [[ $? -ne 0 ]]; then
        log_error "CMake configuration failed"
        return 1
    fi

    log_info "Building llama.cpp (this may take several minutes)..."
    export PATH="$cuda_path/bin:$PATH"
    cmake --build build -j$(nproc)

    if [[ $? -ne 0 ]]; then
        log_error "Build failed"
        return 1
    fi

    if [[ -x "$server_bin" ]]; then
        log_success "llama.cpp built successfully"
        log_info "Server binary: $server_bin"
        return 0
    else
        log_error "Build completed but llama-server not found"
        return 1
    fi
}

# Install OpenCode
install_opencode() {
    log_info "=== Installing OpenCode ==="

    if command -v opencode &> /dev/null; then
        local version=$(opencode --version 2>/dev/null || echo "unknown")
        log_success "OpenCode already installed (version: $version)"
        return 0
    fi

    log_info "Installing OpenCode..."
    curl -fsSL https://opencode.ai/install | bash

    if command -v opencode &> /dev/null; then
        log_success "OpenCode installed successfully"
        return 0
    fi

    local opencode_path=""
    if [[ -f "$HOME/.opencode/bin/opencode" ]]; then
        opencode_path="$HOME/.opencode/bin"
    elif [[ -f "$HOME/.local/bin/opencode" ]]; then
        opencode_path="$HOME/.local/bin"
    fi

    if [[ -n "$opencode_path" ]]; then
        log_warn "OpenCode installed to $opencode_path - adding to PATH for this session"
        export PATH="$opencode_path:$PATH"

        local shell_rc=""
        if [[ -n "$ZSH_VERSION" ]]; then
            shell_rc="$HOME/.zshrc"
        elif [[ -n "$BASH_VERSION" ]]; then
            shell_rc="$HOME/.bashrc"
        fi

        if [[ -n "$shell_rc" ]] && [[ -f "$shell_rc" ]]; then
            if ! grep -q "/.opencode/bin" "$shell_rc" 2>/dev/null; then
                echo "" >> "$shell_rc"
                echo "# opencode" >> "$shell_rc"
                echo "export PATH=\"$opencode_path:\$PATH\"" >> "$shell_rc"
                log_info "Added OpenCode to PATH in $shell_rc"
            fi
        fi

        log_success "OpenCode installed successfully"
        return 0
    else
        log_error "OpenCode installation failed - binary not found"
        return 1
    fi
}

# Get network interface with IPv4
get_ip_addr() {
    local iface="$1"
    ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

# Detect network interface
detect_interface() {
    if command -v ibdev2netdev >/dev/null 2>&1; then
        while read -r iface; do
            [[ -n "${iface:-}" ]] || continue
            ip4="$(get_ip_addr "$iface" || true)"
            [[ -n "${ip4:-}" ]] && { echo "$iface"; return 0; }
        done < <(ibdev2netdev 2>/dev/null | awk '/==>/{for(i=1;i<=NF;i++) if($i=="==>") print $(i+1)}' | tr -d '()')
    fi

    while read -r iface; do
        [[ -n "${iface:-}" ]] || continue
        ip4="$(get_ip_addr "$iface" || true)"
        [[ -n "${ip4:-}" ]] && { echo "$iface"; return 0; }
    done < <(ip -o link show up | awk -F': ' '$2!="lo"{print $2}')

    return 1
}

# Generate OpenCode configuration for distributed setup
generate_config() {
    log_info "=== Generating OpenCode Configuration ==="

    mkdir -p "$OPENCODE_CONFIG_DIR"

    local config_file="$OPENCODE_CONFIG_DIR/opencode.json"

    cat > "$config_file" << 'JSONEOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "MiniMax-M2.1 Distributed (llama.cpp)",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "minimax-m2.1": {
          "name": "MiniMax-M2.1 UD-Q2_K_XL (Distributed)",
          "tools": true
        }
      }
    }
  },
  "model": "llama-cpp/minimax-m2.1"
}
JSONEOF

    log_success "OpenCode config written to $config_file"
}

# Check if server is running
is_server_running() {
    curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null
}

# Start Ray head node
start_ray_head() {
    log_info "=== Starting Ray Head Node ==="

    local mn_iface="${1:-auto}"
    local head_ip=""

    if [[ "$mn_iface" == "auto" ]]; then
        mn_iface="$(detect_interface)" || die "Could not detect network interface"
        log_info "Auto-detected interface: $mn_iface"
    fi

    head_ip="$(get_ip_addr "$mn_iface")"
    [[ -n "$head_ip" ]] || die "No IP address on $mn_iface"

    log_info "Head node IP: $head_ip"
    log_info "Ray port: $RAY_PORT"

    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ ! -x "$server_bin" ]]; then
        log_error "llama-server not found at $server_bin"
        return 1
    fi

    local model_path="$MODEL_DIR/$MODEL_FILE1"
    if [[ ! -f "$model_path" ]]; then
        log_error "Model not found: $model_path"
        return 1
    fi

    log_info "Starting llama-server with RPC tensor parallelism..."

    nohup "$server_bin" \
        -m "$model_path" \
        --host 0.0.0.0 \
        --port "$SERVER_PORT" \
        --ctx-size "$CTX_SIZE" \
        --n-gpu-layers 99 \
        --jinja \
        --rpc \
        --rpc-host "$head_ip" \
        --rpc-port 8081 \
        > /tmp/llama-server-head.log 2>&1 &

    local server_pid=$!
    echo "$server_pid" > /tmp/llama-server.pid

    log_info "Waiting for server to initialize..."
    local max_wait=300
    local waited=0

    while ! is_server_running; do
        sleep 2
        waited=$((waited + 2))

        if ! kill -0 "$server_pid" 2>/dev/null; then
            log_error "Server process died. Check /tmp/llama-server-head.log"
            tail -20 /tmp/llama-server-head.log
            return 1
        fi

        if [[ $waited -ge $max_wait ]]; then
            log_error "Server failed to start within ${max_wait}s"
            return 1
        fi

        printf "."
    done
    echo

    log_success "Head server is ready!"
    log_info "API endpoint: http://localhost:$SERVER_PORT/v1/chat/completions"
    log_info "RPC endpoint: $head_ip:8081"
}

# Start Ray worker node
start_ray_worker() {
    log_info "=== Starting Ray Worker Node ==="

    local head_ip="$1"
    local mn_iface="${2:-auto}"

    [[ -n "$head_ip" ]] || die "Head IP required for worker"

    if [[ "$mn_iface" == "auto" ]]; then
        mn_iface="$(detect_interface)" || die "Could not detect network interface"
        log_info "Auto-detected interface: $mn_iface"
    fi

    local worker_ip="$(get_ip_addr "$mn_iface")"
    [[ -n "$worker_ip" ]] || die "No IP address on $mn_iface"

    log_info "Worker node IP: $worker_ip"
    log_info "Head node IP: $head_ip"

    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ ! -x "$server_bin" ]]; then
        log_error "llama-server not found at $server_bin"
        return 1
    fi

    local model_path="$MODEL_DIR/$MODEL_FILE1"
    if [[ ! -f "$model_path" ]]; then
        log_error "Model not found: $model_path"
        return 1
    fi

    log_info "Starting llama-server as worker..."

    nohup "$server_bin" \
        -m "$model_path" \
        --host 0.0.0.0 \
        --port "$SERVER_PORT" \
        --ctx-size "$CTX_SIZE" \
        --n-gpu-layers 99 \
        --jinja \
        --rpc \
        --rpc-worker \
        --rpc-host "$worker_ip" \
        --rpc-port 8081 \
        --rpc-connect "$head_ip" \
        > /tmp/llama-server-worker.log 2>&1 &

    local server_pid=$!
    echo "$server_pid" > /tmp/llama-server-worker.pid

    log_info "Worker server starting..."
    sleep 5

    log_success "Worker server started on $worker_ip:$SERVER_PORT"
    log_info "Connecting to head at $head_ip:8081"
}

# Show status
show_status() {
    echo "=== Distributed Setup Status ==="
    echo

    echo "Model: MiniMax-M2.1 UD-Q2_K_XL"
    if [[ -d "$MODEL_DIR" ]]; then
        local size=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
        if check_file_complete "$MODEL_DIR/$MODEL_FILE1" "$MODEL_SIZE1" && \
           check_file_complete "$MODEL_DIR/$MODEL_FILE2" "$MODEL_SIZE2"; then
            echo -e "  Status: ${GREEN}Downloaded${NC} ($size)"
        else
            echo -e "  Status: ${YELLOW}Partial${NC} ($size)"
        fi
    else
        echo -e "  Status: ${RED}Not downloaded${NC}"
    fi
    echo "  Path: $MODEL_DIR"
    echo

    echo "llama.cpp:"
    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ -x "$server_bin" ]]; then
        echo -e "  Status: ${GREEN}Built${NC}"
        echo "  Path: $LLAMA_CPP_DIR"
    elif [[ -d "$LLAMA_CPP_DIR" ]]; then
        echo -e "  Status: ${YELLOW}Cloned, not built${NC}"
        echo "  Path: $LLAMA_CPP_DIR"
    else
        echo -e "  Status: ${RED}Not installed${NC}"
    fi
    echo

    echo "OpenCode:"
    if command -v opencode &> /dev/null; then
        local version=$(opencode --version 2>/dev/null || echo "installed")
        echo -e "  Status: ${GREEN}Installed${NC} ($version)"
    else
        echo -e "  Status: ${RED}Not installed${NC}"
    fi
    echo

    echo "llama-server:"
    if is_server_running; then
        echo -e "  Status: ${GREEN}Running${NC}"
        echo "  Endpoint: http://localhost:$SERVER_PORT"
    else
        echo -e "  Status: ${RED}Not running${NC}"
    fi
    echo
}

# Test inference
test_inference() {
    log_info "=== Testing Inference ==="

    if ! is_server_running; then
        log_error "Server is not running"
        return 1
    fi

    log_info "Sending test request..."

    local response=$(curl -s "http://localhost:$SERVER_PORT/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d '{
            "model": "minimax-m2.1",
            "messages": [{"role": "user", "content": "Write a hello world function in Python."}],
            "max_tokens": 100,
            "temperature": 1.0
        }')

    local content=$(echo "$response" | jq -r '.choices[0].message.content // .error.message // "No response"')

    echo
    echo "Response:"
    echo "$content"
    echo

    if [[ "$content" != "No response" ]] && [[ "$content" != *"error"* ]]; then
        log_success "Inference working!"
    else
        log_error "Inference failed"
        return 1
    fi
}

# Main
main() {
    local mode=""
    local head_ip=""
    local mn_iface="auto"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --head)
                mode="head"
                shift
                ;;
            --worker)
                mode="worker"
                shift
                ;;
            --iface)
                mn_iface="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Complete distributed setup for OpenCode + MiniMax-M2.1"
                echo
                echo "Options:"
                echo "  --head           Start as head node (run on SPARK1)"
                echo "  --worker <ip>    Start as worker node (run on SPARK2)"
                echo "  --iface <name>   Specify network interface (default: auto)"
                echo "  --status         Show current setup status"
                echo "  --test           Test inference on running server"
                echo "  --help           Show this help"
                echo
                echo "Without options, performs full local setup"
                echo
                echo "Distributed Setup:"
                echo "  1. On SPARK1 (head):"
                echo "     ./setup-opencode-minimax-distributed.sh --head"
                echo
                echo "  2. On SPARK2 (worker):"
                echo "     ./setup-opencode-minimax-distributed.sh --worker <spark1_ip>"
                echo
                echo "Requirements:"
                echo "  - Two NVIDIA GPUs with CUDA support"
                echo "  - ~90GB disk space for model"
                echo "  - Network connectivity between machines"
                echo "  - cmake, g++, git, wget"
                exit 0
                ;;
            *)
                if [[ -z "$mode" ]]; then
                    head_ip="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ "$mode" == "--status" ]]; then
        show_status
        exit 0
    fi

    if [[ "$mode" == "--test" ]]; then
        test_inference
        exit $?
    fi

    echo "======================================================"
    echo "  OpenCode + MiniMax-M2.1 Distributed Setup Script"
    echo "======================================================"
    echo

    download_model
    echo

    build_llamacpp
    echo

    install_opencode
    echo

    generate_config
    echo

    if [[ "$mode" == "head" ]]; then
        start_ray_head "$mn_iface"
    elif [[ "$mode" == "worker" ]]; then
        start_ray_worker "$head_ip" "$mn_iface"
    else
        log_info "Running local (non-distributed) setup"
        is_server_running || {
            local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
            local model_path="$MODEL_DIR/$MODEL_FILE1"

            nohup "$server_bin" \
                -m "$model_path" \
                --host 0.0.0.0 \
                --port "$SERVER_PORT" \
                --ctx-size "$CTX_SIZE" \
                --n-gpu-layers 99 \
                --jinja \
                > /tmp/llama-server.log 2>&1 &

            sleep 10
        }
    fi

    echo
    show_status

    echo
    log_success "Setup complete!"
    echo
    echo "Usage:"
    echo "  ./setup-opencode-minimax-distributed.sh --help"
}

main "$@"
