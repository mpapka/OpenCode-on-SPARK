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
| `runCluster.sh` | Core Ray cluster Docker launcher |
| `startHead.sh` | Starts Ray head node on SPARK1 |
| `startWorker.sh` | Starts Ray worker node on SPARK2 |
| `serve.sh` | Launches vLLM serve with tensor parallelism |
| `shutdown.sh` | Stops all distributed services |

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
