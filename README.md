# OpenCode on DGX SPARK

Run [OpenCode](https://opencode.ai) with local LLMs on NVIDIA DGX Spark hardware.

This repository provides two infrastructure options for running AI coding assistants locally:

| Setup | Directory | Description |
|-------|-----------|-------------|
| **Single SPARK** | [`single-spark/`](single-spark/) | One DGX Spark using llama.cpp |
| **Dual SPARK** | [`dual-spark/`](dual-spark/) | Two DGX Sparks using Ray + vLLM |

## Quick Start

### Single SPARK (Recommended for simplicity)

```bash
cd single-spark
./setup.sh
opencode
```

### Dual SPARK (For larger models or higher throughput)

**On SPARK1 (Head):**
```bash
cd dual-spark
./startHead.sh
./serve.sh
```

**On SPARK2 (Worker):**
```bash
cd dual-spark
./startWorker.sh
```

## Comparison

| Feature | Single SPARK | Dual SPARK |
|---------|-------------|------------|
| **Hardware** | 1x DGX Spark | 2x DGX Sparks |
| **Memory** | ~119GB usable | ~238GB usable |
| **Runtime** | llama.cpp | vLLM on Ray cluster |
| **Setup Complexity** | Simple (one script) | Moderate (head + worker + serve) |
| **Default Model** | MiniMax-M2.1 UD-Q2_K_XL | MiniMax-M2.1 or OSS120B |
| **Max Model Size** | ~100GB | ~200GB |
| **Context Window** | 128K tokens | 128K tokens |
| **Inference** | ~30-35 tok/s | Varies by model |
| **Tool Support** | Yes | Yes |

## Hardware Requirements

### Single SPARK
- NVIDIA DGX Spark with GB10 GPU (128GB unified memory)
- ~90GB disk space for model
- CUDA 12.0+ or 13.0+

### Dual SPARK
- 2x NVIDIA DGX Spark with GB10 GPU
- Network connectivity between nodes (InfiniBand or Ethernet)
- Docker with NVIDIA container runtime
- SSH access between nodes (for coordinated shutdown)

## When to Choose Each Setup

### Choose Single SPARK when:
- You have one DGX Spark available
- The model fits in ~119GB memory
- You want the simplest setup
- You prefer direct llama.cpp performance
- You're doing development or testing

### Choose Dual SPARK when:
- You have two DGX Sparks available
- You need larger models (>119GB)
- You want tensor parallelism across GPUs
- You need vLLM's optimized serving
- You're running production workloads

## Model Support

Both setups support the same models, but with different memory constraints:

| Model | Size | Single SPARK | Dual SPARK |
|-------|------|--------------|------------|
| MiniMax-M2.1 UD-Q2_K_XL | ~86GB | Yes | Yes |
| MiniMax-M2.1 Q3_K_M | ~209GB | No | Yes |
| OSS120B | ~120GB | No | Yes |
| Qwen3-Coder-30B-A3B | ~20GB | Yes | Yes |
| Llama-3.1-70B Q4_K_M | ~40GB | Yes | Yes |

## Project Structure

```
OpenCode-on-SPARK/
├── README.md                 # This file
├── LICENSE                   # MIT License
├── single-spark/             # Single SPARK setup (llama.cpp)
│   ├── README.md
│   ├── setup.sh              # Full setup script
│   ├── status.sh             # Status checker
│   ├── shutdown.sh           # Clean shutdown
│   ├── opencode.json         # OpenCode config
│   └── docs/                 # Documentation
└── dual-spark/               # Dual SPARK setup (Ray + vLLM)
    ├── README.md
    ├── QUICKSTART.md         # Quick reference
    ├── runCluster.sh         # Ray cluster launcher
    ├── startHead.sh          # Head node setup
    ├── startWorker.sh        # Worker node setup
    ├── serve.sh              # vLLM serving
    ├── shutdown.sh           # Distributed shutdown
    ├── opencode.json         # OpenCode config
    └── docs/                 # Documentation
```

## Switching Between Setups

To switch from one setup to another:

```bash
# Switch to Single SPARK
cd single-spark
./setup.sh --launch-only
cp opencode.json ~/.config/opencode/opencode.json

# Switch to Dual SPARK
cd dual-spark
./startHead.sh  # on head node
./serve.sh      # on head node
./startWorker.sh  # on worker node
cp opencode.json ~/.config/opencode/opencode.json
```

## Documentation

Each setup directory contains its own documentation:

- **Single SPARK**: `single-spark/docs/`
  - Building llama.cpp
  - Model selection guide
  - OpenCode configuration

- **Dual SPARK**: `dual-spark/docs/`
  - Model selection guide
  - OpenCode configuration

## Related Projects

- [OpenCode](https://github.com/sst/opencode) - AI coding assistant
- [llama.cpp](https://github.com/ggml-org/llama.cpp) - LLM inference engine
- [vLLM](https://github.com/vllm-project/vllm) - High-throughput LLM serving
- [Ray](https://www.ray.io/) - Distributed computing framework

## License

MIT License - see [LICENSE](LICENSE)

## Acknowledgments

- [Unsloth](https://github.com/unsloth/unsloth) for optimized GGUF quantizations
- [MiniMax](https://www.minimax.io/) for releasing M2.1 to open source
- [ggml-org](https://github.com/ggml-org) for llama.cpp
- [NVIDIA](https://www.nvidia.com/) for DGX Spark and vLLM container
