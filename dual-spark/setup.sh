#!/bin/bash
#
# setup.sh
#
# Setup script for Dual SPARK infrastructure (Ray + vLLM).
# Checks prerequisites, pulls Docker image, and optionally pre-downloads models.
#
# Usage: ./setup.sh [OPTIONS]
#
# Options:
#   --check-only      Only check prerequisites, don't pull/download anything
#   --pull-image      Pull the vLLM Docker image
#   --download-model  Download model to HuggingFace cache
#   --model <name>    Model to download (default: unsloth/MiniMax-M2.1-GGUF)
#   --help            Show this help
#
# Without options, performs full setup check and image pull.
#

set -e

# Configuration
: "${vllmImage:=nvcr.io/nvidia/vllm:25.11-py3}"
: "${hfCacheDir:=$HOME/.cache/huggingface}"
: "${defaultModel:=unsloth/MiniMax-M2.1-GGUF}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Parse arguments
CHECK_ONLY=false
PULL_IMAGE=false
DOWNLOAD_MODEL=false
MODEL_NAME="$defaultModel"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --pull-image)
            PULL_IMAGE=true
            shift
            ;;
        --download-model)
            DOWNLOAD_MODEL=true
            shift
            ;;
        --model)
            MODEL_NAME="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Setup script for Dual SPARK infrastructure (Ray + vLLM)"
            echo
            echo "Options:"
            echo "  --check-only      Only check prerequisites, don't pull/download"
            echo "  --pull-image      Pull the vLLM Docker image"
            echo "  --download-model  Download model to HuggingFace cache"
            echo "  --model <name>    Model to download (default: $defaultModel)"
            echo "  --help            Show this help"
            echo
            echo "Without options, performs prerequisite check and pulls Docker image."
            echo
            echo "Environment variables:"
            echo "  vllmImage         Docker image (default: $vllmImage)"
            echo "  hfCacheDir        HuggingFace cache directory (default: $hfCacheDir)"
            echo
            echo "Examples:"
            echo "  ./setup.sh                              # Check prerequisites + pull image"
            echo "  ./setup.sh --check-only                 # Only check prerequisites"
            echo "  ./setup.sh --download-model             # Download default model"
            echo "  ./setup.sh --model mistralai/Mistral-7B # Use different model"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# If no specific action requested, do check + pull
if ! $CHECK_ONLY && ! $PULL_IMAGE && ! $DOWNLOAD_MODEL; then
    PULL_IMAGE=true
fi

echo "======================================================================"
echo "           Dual SPARK Setup (Ray + vLLM)                              "
echo "======================================================================"

# Track overall status
PREREQ_OK=true

#
# Check Docker
#
log_section "Docker"

if command -v docker &> /dev/null; then
    docker_version=$(docker --version 2>/dev/null | head -1)
    log_success "Docker installed: $docker_version"
else
    log_error "Docker not installed"
    log_info "Install: https://docs.docker.com/engine/install/"
    PREREQ_OK=false
fi

# Check Docker daemon
if docker info &> /dev/null; then
    log_success "Docker daemon running"
else
    log_error "Docker daemon not accessible"
    log_info "Either start Docker or add your user to the docker group:"
    log_info "  sudo usermod -aG docker \$USER && newgrp docker"
    PREREQ_OK=false
fi

#
# Check NVIDIA Container Toolkit
#
log_section "NVIDIA Container Toolkit"

if command -v nvidia-container-cli &> /dev/null; then
    log_success "nvidia-container-cli found"
elif [[ -f /usr/bin/nvidia-container-runtime ]]; then
    log_success "nvidia-container-runtime found"
else
    log_warn "NVIDIA Container Toolkit may not be installed"
    log_info "Install: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
fi

# Check Docker can access GPU
if docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then
    log_success "Docker nvidia runtime available"
else
    log_warn "Docker nvidia runtime not detected in 'docker info'"
    log_info "This may still work if --gpus flag is supported"
fi

# Test GPU access in Docker
log_info "Testing GPU access in Docker..."
if docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &> /dev/null; then
    log_success "Docker can access GPUs"
else
    log_error "Docker cannot access GPUs"
    log_info "Ensure NVIDIA Container Toolkit is properly configured"
    PREREQ_OK=false
fi

#
# Check GPU Hardware
#
log_section "GPU Hardware"

if command -v nvidia-smi &> /dev/null; then
    gpu_count=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    gpu_mem=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)

    log_success "Found $gpu_count GPU(s)"
    log_info "  GPU: $gpu_name"
    log_info "  Memory: $gpu_mem"
else
    log_error "nvidia-smi not found"
    PREREQ_OK=false
fi

#
# Check Network Tools
#
log_section "Network Tools"

if command -v ip &> /dev/null; then
    log_success "ip command available"
else
    log_warn "ip command not found (needed for auto-detection)"
fi

if command -v ssh &> /dev/null; then
    log_success "ssh available (needed for coordinated shutdown)"
else
    log_warn "ssh not found"
fi

# Check for InfiniBand (optional)
if command -v ibdev2netdev &> /dev/null; then
    ib_devices=$(ibdev2netdev 2>/dev/null | grep -c "==>" || echo "0")
    if [[ "$ib_devices" -gt 0 ]]; then
        log_success "InfiniBand detected ($ib_devices devices)"
    else
        log_info "No active InfiniBand devices (will use Ethernet)"
    fi
else
    log_info "InfiniBand tools not installed (will use Ethernet)"
fi

#
# Check HuggingFace Cache
#
log_section "HuggingFace Cache"

mkdir -p "$hfCacheDir"
log_info "Cache directory: $hfCacheDir"

if [[ -w "$hfCacheDir" ]]; then
    log_success "Cache directory writable"
    cache_size=$(du -sh "$hfCacheDir" 2>/dev/null | cut -f1)
    log_info "Current cache size: $cache_size"
else
    log_error "Cache directory not writable: $hfCacheDir"
    PREREQ_OK=false
fi

#
# Check OpenCode
#
log_section "OpenCode CLI"

if command -v opencode &> /dev/null; then
    version=$(opencode --version 2>/dev/null || echo "installed")
    log_success "OpenCode installed: $version"
else
    log_warn "OpenCode not installed"
    log_info "Install: curl -fsSL https://opencode.ai/install | bash"
fi

#
# Summary of prerequisite check
#
log_section "Prerequisite Summary"

if $PREREQ_OK; then
    log_success "All prerequisites met"
else
    log_error "Some prerequisites are missing (see above)"
    if $CHECK_ONLY; then
        exit 1
    fi
fi

if $CHECK_ONLY; then
    echo
    log_info "Run without --check-only to pull Docker image"
    exit 0
fi

#
# Pull Docker Image
#
if $PULL_IMAGE; then
    log_section "Docker Image"

    log_info "Image: $vllmImage"

    # Check if image exists locally
    if docker image inspect "$vllmImage" &> /dev/null; then
        log_success "Image already exists locally"
        image_size=$(docker image inspect "$vllmImage" --format='{{.Size}}' 2>/dev/null)
        image_size_gb=$(echo "scale=2; $image_size / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "unknown")
        log_info "Image size: ${image_size_gb}GB"
    else
        log_info "Pulling image (this may take a while)..."
        if docker pull "$vllmImage"; then
            log_success "Image pulled successfully"
        else
            log_error "Failed to pull image"
            log_info "You may need to authenticate with NVIDIA NGC:"
            log_info "  docker login nvcr.io"
            exit 1
        fi
    fi
fi

#
# Download Model
#
if $DOWNLOAD_MODEL; then
    log_section "Model Download"

    log_info "Model: $MODEL_NAME"
    log_info "Cache: $hfCacheDir"

    # Check if huggingface-cli is available
    if command -v huggingface-cli &> /dev/null; then
        log_info "Downloading model using huggingface-cli..."
        huggingface-cli download "$MODEL_NAME" --local-dir "$hfCacheDir/hub/models--${MODEL_NAME//\//__}"
        log_success "Model downloaded"
    else
        log_warn "huggingface-cli not found"
        log_info "Install with: pip install huggingface_hub"
        log_info "Or the model will be downloaded automatically on first serve"
        log_info ""
        log_info "Manual download:"
        log_info "  pip install huggingface_hub"
        log_info "  huggingface-cli download $MODEL_NAME"
    fi
fi

#
# Final Instructions
#
log_section "Next Steps"

echo
echo "Setup complete! To start the distributed cluster:"
echo
echo "  1. On SPARK1 (head node):"
echo "     ./startHead.sh"
echo "     ./serve.sh"
echo
echo "  2. On SPARK2 (worker node):"
echo "     ./startWorker.sh"
echo
echo "  3. Configure OpenCode:"
echo "     cp opencode.json ~/.config/opencode/opencode.json"
echo "     opencode"
echo
echo "To use a different model:"
echo "  modelTag=<model-name> ./serve.sh"
echo
echo "See README.md for model configuration details."
echo
