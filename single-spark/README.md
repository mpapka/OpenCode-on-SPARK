# Single SPARK Setup (llama.cpp)

Run [OpenCode](https://opencode.ai) with local LLMs on a **single NVIDIA DGX Spark** using llama.cpp.

## Overview

| Component | Details |
|-----------|---------|
| **Hardware** | Single DGX Spark with GB10 GPU (128GB unified memory) |
| **Model** | [MiniMax-M2.1](https://huggingface.co/unsloth/MiniMax-M2.1-GGUF) - 456B MoE (21B active) |
| **Quantization** | UD-Q2_K_XL (~86GB) |
| **Runtime** | [llama.cpp](https://github.com/ggml-org/llama.cpp) with CUDA backend |
| **Frontend** | [OpenCode](https://opencode.ai) - AI coding assistant CLI |

## Quick Start

```bash
# From the single-spark directory
cd single-spark

# Run full setup (download model, install OpenCode, configure, launch)
./setup.sh

# Once complete, start coding!
opencode
```

## What the Setup Script Does

1. **Downloads MiniMax-M2.1 UD-Q2_K_XL** (~86GB, 2 files)
   - Supports resume if interrupted
   - Verifies file integrity

2. **Builds llama.cpp with CUDA support** (if not already built)
   - Automatically detects CUDA installation
   - Finds compatible g++ compiler
   - Compiles with all CPU cores

3. **Installs OpenCode** if not already present

4. **Generates configuration** (`~/.config/opencode/opencode.json`)

5. **Launches llama-server** with optimal settings
   - GPU acceleration (all layers offloaded)
   - **128K context window** (131,072 tokens)

## Scripts

| Script | Description |
|--------|-------------|
| `setup.sh` | Full setup: download, install, configure, launch |
| `status.sh` | Show status of model, server, and configuration |
| `shutdown.sh` | Clean shutdown of llama-server |

## Usage

```bash
# Full setup (first time)
./setup.sh

# Check status
./status.sh

# Shutdown server
./shutdown.sh

# Download only (no server launch)
./setup.sh --download-only

# Launch server only (after download)
./setup.sh --launch-only

# Test inference
./setup.sh --test
```

## Requirements

### Hardware
- NVIDIA GPU with 85GB+ VRAM (tested on DGX Spark GB10)
- ~90GB disk space for model
- Multi-core CPU for faster compilation

### Software
- Ubuntu 22.04+ or similar Linux
- CUDA 12.0+ or 13.0+
- cmake, g++, git, wget

## Model Performance

| Metric | Value |
|--------|-------|
| Inference Speed | ~30-35 tokens/second |
| Memory Usage | ~86GB of 128GB |
| Startup Time | ~2-3 minutes |
| Context Window | 128K tokens |

## Configuration

The setup script creates `~/.config/opencode/opencode.json`. You can also copy `opencode.json` from this directory:

```bash
cp opencode.json ~/.config/opencode/opencode.json
```

### Customizing Context Size

Edit `CTX_SIZE` in `setup.sh`:

```bash
# Change: CTX_SIZE=131072
# To:     CTX_SIZE=196608  # For 192K context
```

## Troubleshooting

### Server won't start
```bash
tail -100 /tmp/llama-server-minimax-m2.1.log
```

### Out of memory
Try a smaller quantization (see `docs/MODEL_SELECTION.md`):
- `UD-IQ2_XXS` (~50GB)
- `UD-IQ1_M` (~40GB)

### OpenCode can't connect
```bash
curl http://localhost:8080/health
```

### OpenCode command not found
```bash
exec zsh    # or: exec bash
# Or manually:
export PATH="$HOME/.opencode/bin:$PATH"
```

## Documentation

- [Building llama.cpp](docs/BUILDING_LLAMA_CPP.md) - Manual build instructions
- [Model Selection](docs/MODEL_SELECTION.md) - Quantization options and alternatives
- [OpenCode Config](docs/OPENCODE_CONFIG.md) - Configuration guide

## When to Use Single SPARK

Choose Single SPARK when:
- You have one DGX Spark available
- The model fits in ~119GB usable memory
- You want the simplest setup
- You prefer direct llama.cpp performance

For larger models or higher throughput, see the [Dual SPARK setup](../dual-spark/).
