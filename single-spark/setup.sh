#!/bin/bash
#
# setup.sh
#
# Complete setup script for OpenCode + MiniMax-M2.1 on NVIDIA GPUs:
# - Downloads MiniMax-M2.1 UD-Q2_K_XL model (~86GB)
# - Builds llama.cpp with CUDA support (if not already built)
# - Installs OpenCode CLI
# - Configures OpenCode to use local llama.cpp server
# - Launches model server with 128K context
#
# This script is restartable - it will skip completed steps.
#
# Usage: ./setup.sh [OPTIONS]
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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

    # Download both files (can be parallelized)
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

    # Download missing files in parallel
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

    # Wait for downloads
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

# Build llama.cpp with CUDA support
build_llamacpp() {
    log_info "=== Building llama.cpp with CUDA ==="

    # Check if already built
    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ -x "$server_bin" ]]; then
        log_success "llama.cpp already built at $LLAMA_CPP_DIR"
        return 0
    fi

    # Check for required tools
    if ! command -v cmake &> /dev/null; then
        log_error "cmake not found. Please install: sudo apt-get install cmake"
        return 1
    fi

    if ! command -v git &> /dev/null; then
        log_error "git not found. Please install: sudo apt-get install git"
        return 1
    fi

    # Find g++ compiler
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

    # Find CUDA
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

    # Clone llama.cpp if needed
    if [[ ! -d "$LLAMA_CPP_DIR" ]]; then
        log_info "Cloning llama.cpp..."
        git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_DIR"
    else
        log_info "llama.cpp repository already exists"
    fi

    cd "$LLAMA_CPP_DIR"

    # Configure with CMake
    log_info "Configuring build with CUDA support..."
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

    # Build
    log_info "Building llama.cpp (this may take several minutes)..."
    export PATH="$cuda_path/bin:$PATH"
    cmake --build build -j$(nproc)

    if [[ $? -ne 0 ]]; then
        log_error "Build failed"
        return 1
    fi

    # Verify build
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

    # Verify installation
    if command -v opencode &> /dev/null; then
        log_success "OpenCode installed successfully"
        return 0
    fi

    # Check common installation locations
    local opencode_path=""
    if [[ -f "$HOME/.opencode/bin/opencode" ]]; then
        opencode_path="$HOME/.opencode/bin"
    elif [[ -f "$HOME/.local/bin/opencode" ]]; then
        opencode_path="$HOME/.local/bin"
    fi

    if [[ -n "$opencode_path" ]]; then
        log_warn "OpenCode installed to $opencode_path - adding to PATH for this session"
        export PATH="$opencode_path:$PATH"

        # Update shell rc files if not already there
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

# Generate OpenCode configuration
generate_config() {
    log_info "=== Generating OpenCode Configuration ==="

    mkdir -p "$OPENCODE_CONFIG_DIR"

    local config_file="$OPENCODE_CONFIG_DIR/opencode.json"

    # Always regenerate to ensure correct settings
    cat > "$config_file" << 'JSONEOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-cpp": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "MiniMax-M2.1 (llama.cpp)",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "minimax-m2.1": {
          "name": "MiniMax-M2.1 UD-Q2_K_XL",
          "tools": true
        }
      }
    }
  },
  "model": "llama-cpp/minimax-m2.1"
}
JSONEOF

    log_success "OpenCode config written to $config_file"

    # Also create a project-local config if in a project directory
    if [[ -d ".git" ]] && [[ ! -f "opencode.json" ]]; then
        cp "$config_file" "./opencode.json"
        log_info "Also created local opencode.json in current directory"
    fi
}

# Check if llama-server is running
is_server_running() {
    if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
        return 0
    fi
    return 1
}

# Launch llama.cpp server
launch_server() {
    log_info "=== Launching llama.cpp Server ==="

    # Check if server is already running
    if is_server_running; then
        log_success "llama-server already running on port $SERVER_PORT"
        return 0
    fi

    # Check if model exists
    local model_path="$MODEL_DIR/$MODEL_FILE1"
    if [[ ! -f "$model_path" ]]; then
        log_error "Model not found: $model_path"
        log_info "Run with --download-only first"
        return 1
    fi

    # Check if llama-server exists
    local server_bin="$LLAMA_CPP_DIR/build/bin/llama-server"
    if [[ ! -x "$server_bin" ]]; then
        log_error "llama-server not found at $server_bin"
        log_info "Please build llama.cpp first"
        return 1
    fi

    # Shutdown any existing server
    if [[ -x "$HOME/llamacpp-shutdown.sh" ]]; then
        "$HOME/llamacpp-shutdown.sh" 2>/dev/null || true
    fi

    # Launch server
    log_info "Starting llama-server..."
    log_info "  Model: $MODEL_NAME"
    log_info "  Port: $SERVER_PORT"
    log_info "  Context: $CTX_SIZE"

    nohup "$server_bin" \
        -m "$model_path" \
        --host 0.0.0.0 \
        --port "$SERVER_PORT" \
        --ctx-size "$CTX_SIZE" \
        --n-gpu-layers 99 \
        --jinja \
        > /tmp/llama-server-minimax-m2.1.log 2>&1 &

    local server_pid=$!
    echo "$server_pid" > /tmp/llama-server.pid

    # Wait for server to be ready
    log_info "Waiting for server to initialize..."
    local max_wait=300  # 5 minutes for large model
    local waited=0

    while ! is_server_running; do
        sleep 2
        waited=$((waited + 2))

        # Check if process died
        if ! kill -0 "$server_pid" 2>/dev/null; then
            log_error "Server process died. Check /tmp/llama-server-minimax-m2.1.log"
            tail -20 /tmp/llama-server-minimax-m2.1.log
            return 1
        fi

        if [[ $waited -ge $max_wait ]]; then
            log_error "Server failed to start within ${max_wait}s"
            return 1
        fi

        printf "."
    done
    echo

    log_success "Server is ready!"
    log_info "API endpoint: http://localhost:$SERVER_PORT/v1/chat/completions"
}

# Show status
show_status() {
    echo "=== Setup Status ==="
    echo

    # Model status
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

    # llama.cpp status
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

    # OpenCode status
    echo "OpenCode:"
    if command -v opencode &> /dev/null; then
        local version=$(opencode --version 2>/dev/null || echo "installed")
        echo -e "  Status: ${GREEN}Installed${NC} ($version)"
    else
        echo -e "  Status: ${RED}Not installed${NC}"
    fi
    echo

    # Config status
    echo "Configuration:"
    if [[ -f "$OPENCODE_CONFIG_DIR/opencode.json" ]]; then
        echo -e "  Status: ${GREEN}Configured${NC}"
        echo "  Path: $OPENCODE_CONFIG_DIR/opencode.json"
    else
        echo -e "  Status: ${RED}Not configured${NC}"
    fi
    echo

    # Server status
    echo "llama-server:"
    if is_server_running; then
        echo -e "  Status: ${GREEN}Running${NC}"
        echo "  Endpoint: http://localhost:$SERVER_PORT"
        # Quick health check
        local health=$(curl -s "http://localhost:$SERVER_PORT/health" | head -c 100)
        echo "  Health: $health"
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
    local download_only=false
    local launch_only=false
    local show_status_only=false
    local test_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --download-only)
                download_only=true
                shift
                ;;
            --launch-only)
                launch_only=true
                shift
                ;;
            --status)
                show_status_only=true
                shift
                ;;
            --test)
                test_only=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Complete setup script for OpenCode + MiniMax-M2.1 on NVIDIA GPUs"
                echo
                echo "Options:"
                echo "  --download-only   Only download model, build llama.cpp, and install OpenCode"
                echo "  --launch-only     Only launch the server (assumes everything is installed)"
                echo "  --status          Show current setup status"
                echo "  --test            Test inference on running server"
                echo "  --help            Show this help"
                echo
                echo "Without options, performs full setup:"
                echo "  1. Download MiniMax-M2.1 model (~86GB)"
                echo "  2. Build llama.cpp with CUDA support (if not already built)"
                echo "  3. Install OpenCode CLI"
                echo "  4. Generate configuration (128K context)"
                echo "  5. Launch llama-server"
                echo "  6. Test inference"
                echo
                echo "Requirements:"
                echo "  - NVIDIA GPU with CUDA support"
                echo "  - ~90GB disk space for model"
                echo "  - ~85GB GPU memory"
                echo "  - cmake, g++, git, wget"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if $show_status_only; then
        show_status
        exit 0
    fi

    if $test_only; then
        test_inference
        exit $?
    fi

    echo "=============================================="
    echo "  OpenCode + MiniMax-M2.1 Setup Script"
    echo "=============================================="
    echo

    if $launch_only; then
        generate_config
        launch_server
        echo
        show_status
        exit 0
    fi

    # Full setup
    download_model
    echo

    build_llamacpp
    echo

    install_opencode
    echo

    generate_config
    echo

    if ! $download_only; then
        launch_server
        echo

        # Quick test
        sleep 2
        test_inference
    fi

    echo
    show_status

    echo
    log_success "Setup complete!"
    echo
    echo "To use OpenCode with MiniMax-M2.1:"
    echo "  1. Make sure the server is running:"
    echo "     ./setup.sh --launch-only"
    echo
    echo "  2. Reload your shell to add OpenCode to PATH:"
    echo "     exec zsh    (or: exec bash)"
    echo
    echo "  3. Navigate to a project and run OpenCode:"
    echo "     cd ~/your-project"
    echo "     opencode"
    echo
    echo "Server details:"
    echo "  - Context size: 128K tokens"
    echo "  - Port: $SERVER_PORT"
    echo "  - Model: MiniMax-M2.1 (228B params, 10B active)"
    echo
    echo "Check status anytime:"
    echo "  ./status.sh"
}

main "$@"
