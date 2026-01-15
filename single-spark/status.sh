#!/bin/bash
#
# status.sh - Check status of MiniMax-M2.1 setup and server
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
MODEL_DIR="$HOME/models/minimax-m2.1"
MODEL_FILE1="MiniMax-M2.1-UD-Q2_K_XL-00001-of-00002.gguf"
MODEL_FILE2="MiniMax-M2.1-UD-Q2_K_XL-00002-of-00002.gguf"
MODEL_SIZE1=49950511392  # ~50GB
MODEL_SIZE2=35967481120  # ~36GB
SERVER_PORT=8080
OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"

# Check if file is complete
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

echo "======================================================================"
echo "           OpenCode + MiniMax-M2.1 Status (Single SPARK)              "
echo "======================================================================"
echo

# Model Status
echo -e "${CYAN}Model: MiniMax-M2.1 UD-Q2_K_XL${NC}"
echo "  Path: $MODEL_DIR"

if [[ -d "$MODEL_DIR" ]]; then
    size=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
    file1_ok=false
    file2_ok=false

    if check_file_complete "$MODEL_DIR/$MODEL_FILE1" "$MODEL_SIZE1"; then
        file1_ok=true
    fi
    if check_file_complete "$MODEL_DIR/$MODEL_FILE2" "$MODEL_SIZE2"; then
        file2_ok=true
    fi

    if $file1_ok && $file2_ok; then
        echo -e "  Status: ${GREEN}Downloaded${NC} ($size)"
    elif [[ -f "$MODEL_DIR/$MODEL_FILE1" ]] || [[ -f "$MODEL_DIR/$MODEL_FILE2" ]]; then
        echo -e "  Status: ${YELLOW}Partial${NC} ($size)"
        $file1_ok && echo -e "    File 1: ${GREEN}OK${NC}" || echo -e "    File 1: ${RED}Missing${NC}"
        $file2_ok && echo -e "    File 2: ${GREEN}OK${NC}" || echo -e "    File 2: ${RED}Missing${NC}"
    else
        echo -e "  Status: ${RED}Not downloaded${NC}"
    fi
else
    echo -e "  Status: ${RED}Not downloaded${NC}"
fi
echo

# OpenCode Status
echo -e "${CYAN}OpenCode CLI${NC}"
if command -v opencode &> /dev/null; then
    version=$(opencode --version 2>/dev/null || echo "unknown")
    echo -e "  Status: ${GREEN}Installed${NC} (v$version)"

    # Check if in PATH
    which_path=$(which opencode 2>/dev/null)
    echo "  Path: $which_path"
else
    echo -e "  Status: ${RED}Not installed${NC}"
    echo "  Install: curl -fsSL https://opencode.sh/install.sh | sh"
fi
echo

# Configuration Status
echo -e "${CYAN}Configuration${NC}"
if [[ -f "$OPENCODE_CONFIG" ]]; then
    echo -e "  Status: ${GREEN}Configured${NC}"
    echo "  Path: $OPENCODE_CONFIG"

    # Show configured model
    model=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$OPENCODE_CONFIG" 2>/dev/null | tail -1 | cut -d'"' -f4)
    if [[ -n "$model" ]]; then
        echo "  Default Model: $model"
    fi
else
    echo -e "  Status: ${RED}Not configured${NC}"
    echo "  Run: ./setup.sh"
fi
echo

# Server Status
echo -e "${CYAN}llama-server${NC}"
echo "  Port: $SERVER_PORT"

# Check if process is running
PIDS=$(pgrep -f "llama-server" 2>/dev/null || true)
if [[ -n "$PIDS" ]]; then
    echo -e "  Process: ${GREEN}Running${NC} (PID: $PIDS)"
else
    echo -e "  Process: ${RED}Not running${NC}"
fi

# Check if server responds
if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
    health=$(curl -s "http://localhost:$SERVER_PORT/health")
    echo -e "  Health: ${GREEN}Responding${NC}"

    # Get model info
    model_id=$(curl -s "http://localhost:$SERVER_PORT/v1/models" 2>/dev/null | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    if [[ -n "$model_id" ]]; then
        echo "  Loaded Model: $model_id"
    fi

    echo "  Endpoint: http://localhost:$SERVER_PORT/v1/chat/completions"
else
    echo -e "  Health: ${RED}Not responding${NC}"
fi
echo

# GPU Status
echo -e "${CYAN}GPU${NC}"
if command -v nvidia-smi &> /dev/null; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    gpu_mem=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)

    if [[ -n "$gpu_name" ]]; then
        echo "  Device: $gpu_name"
        if [[ -n "$gpu_mem" ]]; then
            used=$(echo "$gpu_mem" | cut -d',' -f1 | tr -d ' ')
            total=$(echo "$gpu_mem" | cut -d',' -f2 | tr -d ' ')
            # Handle N/A or non-numeric values
            if [[ "$used" =~ ^[0-9]+$ ]] && [[ "$total" =~ ^[0-9]+$ ]] && [[ "$total" -gt 0 ]]; then
                pct=$((used * 100 / total))
                echo "  Memory: ${used}MiB / ${total}MiB (${pct}%)"
            else
                echo "  Memory: Unified memory (shared with system)"
            fi
        fi
    fi
else
    echo -e "  Status: ${YELLOW}nvidia-smi not available${NC}"
fi
echo

# Quick Actions
echo -e "${CYAN}Quick Actions${NC}"
if curl -s "http://localhost:$SERVER_PORT/health" &>/dev/null; then
    echo "  Stop server:  ./shutdown.sh"
    echo "  Use OpenCode: opencode"
    echo "  Test API:     curl http://localhost:$SERVER_PORT/v1/chat/completions \\"
    echo "                  -H 'Content-Type: application/json' \\"
    echo "                  -d '{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}'"
else
    echo "  Start server: ./setup.sh --launch-only"
    echo "  Full setup:   ./setup.sh"
fi
echo
