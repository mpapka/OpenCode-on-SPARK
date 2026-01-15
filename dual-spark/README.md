# Dual SPARK Setup (Ray + vLLM)

Run [OpenCode](https://opencode.ai) with distributed model serving across **two DGX SPARK machines** using Ray cluster and vLLM.

## Overview

| Component | Details |
|-----------|---------|
| **Hardware** | Two DGX Sparks with GB10 GPUs (256GB total unified memory) |
| **Model** | [MiniMax-M2.1](https://huggingface.co/unsloth/MiniMax-M2.1-GGUF) or OSS120B |
| **Runtime** | [vLLM](https://github.com/vllm-project/vllm) on [Ray](https://www.ray.io/) cluster |
| **Parallelism** | Tensor parallel across 2 GPUs |
| **Frontend** | [OpenCode](https://opencode.ai) - AI coding assistant CLI |

## Quick Start

### On SPARK1 (Head Node)
```bash
cd dual-spark
./startHead.sh
./serve.sh
```

### On SPARK2 (Worker Node)
```bash
cd dual-spark
./startWorker.sh
```

The worker script auto-detects the head node IP if you've already run `startHead.sh` on SPARK1.

## Scripts

| Script | Description |
|--------|-------------|
| `setup.sh` | Check prerequisites, pull Docker image, download models |
| `runCluster.sh` | Core Ray cluster Docker launcher |
| `startHead.sh` | Starts Ray head node on SPARK1 |
| `startWorker.sh` | Starts Ray worker node on SPARK2 |
| `serve.sh` | Launches vLLM serve with tensor parallelism |
| `shutdown.sh` | Stops all distributed services |

## Initial Setup

Before first use, run the setup script to verify prerequisites:

```bash
# Check prerequisites and pull Docker image
./setup.sh

# Check only (no downloads)
./setup.sh --check-only

# Pre-download a model
./setup.sh --download-model --model meta-llama/Llama-3.1-70B-Instruct
```

The setup script checks:
- Docker installation and GPU access
- NVIDIA Container Toolkit
- Network tools (for auto-detection)
- HuggingFace cache directory

## Configuration

Edit environment variables in scripts or set them inline:

```bash
# Use OSS120B model
modelType=oss120b ./serve.sh

# Custom port
portBind=9000 ./serve.sh

# Custom tensor parallel size (match your GPU count)
tensorParallelSize=2 ./serve.sh
```

### Default Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Model | `unsloth/MiniMax-M2.1-GGUF` | Primary model |
| Port | `8080` | API endpoint |
| Tensor Parallel Size | `2` | One GPU per machine |
| Max Model Length | `131072` | Context window (128K) |
| GPU Memory | `0.88` | Memory utilization |

## Using Different Models

The dual-spark setup uses vLLM which can load models directly from HuggingFace. Models are specified via environment variables.

### Quick Model Switch

```bash
# Use a different model by setting modelTag
modelTag=meta-llama/Llama-3.1-70B-Instruct ./serve.sh

# Use the built-in OSS120B shortcut
modelType=oss120b ./serve.sh
```

### Step 1: Choose Your Model

vLLM supports most HuggingFace transformer models. The model must:
- Fit in combined GPU memory (~238GB for dual SPARK)
- Be supported by vLLM (see [vLLM supported models](https://docs.vllm.ai/en/latest/models/supported_models.html))

### Step 2: Launch with Model

```bash
# Set model and launch
modelTag=<huggingface-model-id> ./serve.sh

# With custom settings
modelTag=<model-id> maxModelLen=65536 gpuMemoryUtilization=0.90 ./serve.sh
```

### Step 3: Update OpenCode Config

Edit `opencode.json` (and `~/.config/opencode/opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "vllm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "<Model-Display-Name>",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "<model-id>": {
          "name": "<Model-Display-Name>",
          "tools": true
        }
      }
    }
  },
  "model": "vllm/<model-id>"
}
```

### Example: Using Llama-3.1-70B

```bash
# Launch with Llama 3.1 70B
modelTag=meta-llama/Llama-3.1-70B-Instruct ./serve.sh

# Update opencode.json
{
  "provider": {
    "vllm": {
      "name": "Llama 3.1 70B (Distributed)",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "meta-llama/Llama-3.1-70B-Instruct": {
          "name": "Llama 3.1 70B Instruct",
          "tools": true
        }
      }
    }
  },
  "model": "vllm/meta-llama/Llama-3.1-70B-Instruct"
}
```

### Pre-downloading Models

Models are downloaded on first use. To pre-download:

```bash
# Install huggingface-cli if needed
pip install huggingface_hub

# Download model to cache
huggingface-cli download <model-id>

# Or use setup.sh
./setup.sh --download-model --model <model-id>
```

### serve.sh Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `modelTag` | `unsloth/MiniMax-M2.1-GGUF` | HuggingFace model ID |
| `modelType` | `minimax` | Shortcut: `oss120b` for OSS-120B |
| `tensorParallelSize` | `2` | Number of GPUs for tensor parallelism |
| `maxModelLen` | `131072` | Maximum context length |
| `gpuMemoryUtilization` | `0.88` | Fraction of GPU memory to use |
| `portBind` | `8080` | API port |
| `extraVllmArgs` | (empty) | Additional vLLM arguments |

### Compatible Models (Dual SPARK)

| Model | Size | Command |
|-------|------|---------|
| MiniMax-M2.1 | ~86GB | `./serve.sh` (default) |
| OSS-120B | ~120GB | `modelType=oss120b ./serve.sh` |
| Llama-3.1-70B | ~140GB | `modelTag=meta-llama/Llama-3.1-70B-Instruct ./serve.sh` |
| Llama-3.1-405B (Q4) | ~200GB | `modelTag=... ./serve.sh` |
| Qwen2.5-72B | ~145GB | `modelTag=Qwen/Qwen2.5-72B-Instruct ./serve.sh` |
| Mixtral-8x22B | ~90GB | `modelTag=mistralai/Mixtral-8x22B-Instruct-v0.1 ./serve.sh` |

See `docs/MODEL_SELECTION.md` for more options.

## Auto-Detection

The scripts auto-detect:
- Network interface (InfiniBand or Ethernet)
- IP addresses for both head and worker nodes
- Required environment variables

To manually specify:
```bash
headIp=192.168.1.100 ./startWorker.sh
mnIfName=ib0 ./startHead.sh
```

## Network Requirements

| Port | Purpose |
|------|---------|
| `6379` | Ray cluster communication |
| `8080` | vLLM API endpoint |

Ensure both machines can reach each other on these ports.

## Using with OpenCode

```bash
# Apply distributed config
cp opencode.json ~/.config/opencode/opencode.json

# Start OpenCode
opencode
```

## Coordinated Shutdown

For shutting down both nodes from the head:

```bash
# Configure worker hostname
echo 'worker-hostname-or-ip' > ~/.opencode/worker_host

# Shutdown both nodes
./shutdown.sh --all
```

## Troubleshooting

### Container not found
```bash
docker ps | grep node-
```

### Worker connection failed
```bash
# On head node
docker exec <container> ray status

# Check network
ping <worker_ip>
```

### API not accessible
```bash
docker exec <container> tail -f /tmp/vllmServe.log
```

### Check logs
```bash
# Head node logs
cat /tmp/runClusterHead.log

# Worker node logs
cat /tmp/runClusterWorker.log

# vLLM logs
docker exec <container> cat /tmp/vllmServe.log
```

## Documentation

- [Model Selection](docs/MODEL_SELECTION.md) - Quantization options for dual-node setups
- [OpenCode Config](docs/OPENCODE_CONFIG.md) - Configuration guide

## When to Use Dual SPARK

Choose Dual SPARK when:
- You have two DGX Sparks available
- You need larger models (>119GB)
- You want tensor parallelism for faster inference
- You need the throughput of vLLM

For simpler single-machine setup, see the [Single SPARK setup](../single-spark/).
