# Building llama.cpp for DGX Spark

This guide covers building llama.cpp with CUDA support for NVIDIA DGX Spark (GB10 GPU).

## Prerequisites

```bash
# Install build dependencies
sudo apt-get update
sudo apt-get install -y build-essential cmake git

# Ensure CUDA is installed (should be pre-installed on DGX Spark)
nvcc --version

# Install GCC-12 (required for CUDA 13.0 compatibility)
sudo apt-get install -y gcc-12 g++-12
```

## Clone and Build

```bash
# Clone llama.cpp
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp

# Configure with CUDA support
# Note: GB10 with CUDA 13.0 requires GCC-12 as the host compiler
CUDAHOSTCXX=/usr/bin/g++-12 cmake -B build \
  -DGGML_CUDA=ON \
  -DGGML_RPC=ON \
  -DGGML_CUDA_F16=ON \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
  -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-12

# Build (use all cores)
cmake --build build -j$(nproc)
```

## Verify Build

```bash
# Check that llama-server was built
ls -la build/bin/llama-server

# Quick test
./build/bin/llama-server --help
```

## Key Binaries

After building, these binaries are available in `build/bin/`:

| Binary | Purpose |
|--------|---------|
| `llama-server` | OpenAI-compatible HTTP server |
| `llama-cli` | Interactive inference CLI |
| `llama-quantize` | Model quantization tool |
| `llama-bench` | Performance benchmarking |
| `rpc-server` | RPC endpoint for distributed inference |

## Build Options

### Enable/Disable Features

```bash
# Basic CUDA build
cmake -B build -DGGML_CUDA=ON

# With RPC for multi-node (memory expansion)
cmake -B build -DGGML_CUDA=ON -DGGML_RPC=ON

# With FP16 CUDA kernels
cmake -B build -DGGML_CUDA=ON -DGGML_CUDA_F16=ON

# Without CURL (if not needed)
cmake -B build -DGGML_CUDA=ON -DLLAMA_CURL=OFF
```

## Troubleshooting

### GCC Version Error

```
error: #error -- unsupported GNU version! gcc versions later than 12 are not supported!
```

**Solution**: Use GCC-12 as the CUDA host compiler:
```bash
CUDAHOSTCXX=/usr/bin/g++-12 cmake -B build -DGGML_CUDA=ON
```

### ARM SVE Errors

```
error: "__SVFloat32_t" is undefined
```

**Solution**: This is also resolved by using GCC-12 instead of GCC-13+.

### CUDA Not Found

```
CMake Error: CUDA toolkit not found
```

**Solution**: Ensure CUDA is in your PATH:
```bash
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

## Updating llama.cpp

```bash
cd ~/llama.cpp
git pull
cmake --build build -j$(nproc)
```

## Multi-Node RPC Setup

For using two DGX Sparks together (memory expansion, not tensor parallelism):

```bash
# On remote node - start RPC server
./build/bin/rpc-server -H 0.0.0.0 -p 50052

# On primary node - connect via RPC
./build/bin/llama-server \
  -m model.gguf \
  --rpc remote-ip:50052 \
  --n-gpu-layers 99
```

See [spark-multi-node](https://github.com/rick-stevens-ai/spark-multi-node) for automated scripts.
