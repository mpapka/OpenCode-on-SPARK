# Model Selection Guide

This guide helps you choose the right model and quantization for your DGX Spark setup.

## Memory Constraints

| Configuration | Available Memory | Recommended Model Size |
|--------------|------------------|----------------------|
| Single DGX Spark | ~119GB usable | Up to 100GB |
| Two DGX Sparks (RPC) | ~238GB usable | Up to 200GB |

## MiniMax-M2.1 Quantizations

All quantizations from [unsloth/MiniMax-M2.1-GGUF](https://huggingface.co/unsloth/MiniMax-M2.1-GGUF):

| Quantization | Size | Quality | Single Spark | Dual Spark |
|-------------|------|---------|--------------|------------|
| BF16 | ~912GB | Best | No | No |
| Q8_0 | ~484GB | Excellent | No | No |
| Q6_K | ~374GB | Very Good | No | Yes |
| Q5_K_M | ~324GB | Good | No | Yes |
| Q4_K_M | ~268GB | Good | No | Yes |
| Q3_K_M | ~209GB | Acceptable | No | Yes |
| **UD-Q2_K_XL** | **~86GB** | **Good** | **Yes** | Yes |
| UD-Q2_K | ~78GB | Acceptable | Yes | Yes |
| UD-IQ2_XXS | ~50GB | Lower | Yes | Yes |
| UD-IQ1_M | ~40GB | Lowest | Yes | Yes |

**Recommendation**: UD-Q2_K_XL offers the best quality that fits on a single DGX Spark.

## Alternative Coding Models

### For Single DGX Spark

| Model | Size | Speed | Coding Quality |
|-------|------|-------|----------------|
| MiniMax-M2.1 UD-Q2_K_XL | 86GB | ~33 tok/s | Excellent |
| Qwen3-Coder-30B-A3B Q4_K_M | ~20GB | ~77 tok/s | Very Good |
| DeepSeek-Coder-V2-Lite Q4_K_M | ~10GB | ~100 tok/s | Good |
| Llama-3.1-70B Q4_K_M | ~40GB | ~45 tok/s | Good |

### For Dual DGX Spark (RPC)

| Model | Size | Notes |
|-------|------|-------|
| Qwen3-Coder-480B Q2_K | ~168GB | May have CUDA kernel issues |
| DeepSeek-V3 Q2_K | ~350GB | Requires careful layer splitting |
| Llama-3.1-405B Q2_K | ~180GB | Works well with RPC |

## GB10 Compatibility Notes

The GB10 GPU (compute capability 12.1) has some kernel limitations:

### What Works
- Standard dense models (Llama, Qwen non-MoE)
- MoE models via llama.cpp GGUF
- FP16, BF16, and all Q-format quantizations

### What May Fail
- Some very large attention dimensions (SOFT_MAX kernel issues)
- FP4/NVFP4 MoE models via vLLM/SGLang
- Models requiring specific SM versions

## Quantization Quality Guide

### Unsloth Dynamic (UD-) Quantizations

Unsloth's "Ultra Dynamic" quantizations use importance-aware mixed precision:
- Critical layers get higher precision
- Less important layers get lower precision
- Better quality per bit than standard quantization

### Standard Quantizations

| Type | Bits/Weight | Quality Impact |
|------|-------------|----------------|
| Q8_0 | 8.0 | ~1% quality loss |
| Q6_K | 6.5 | ~2% quality loss |
| Q5_K_M | 5.5 | ~3% quality loss |
| Q4_K_M | 4.8 | ~5% quality loss |
| Q3_K_M | 3.9 | ~8% quality loss |
| Q2_K | 2.6 | ~15% quality loss |
| IQ2_XXS | 2.1 | ~20% quality loss |
| IQ1_M | 1.75 | ~25% quality loss |

## Downloading Models

### From HuggingFace

```bash
# Using wget with resume support
wget -c "https://huggingface.co/unsloth/MiniMax-M2.1-GGUF/resolve/main/UD-Q2_K_XL/MiniMax-M2.1-UD-Q2_K_XL-00001-of-00002.gguf"

# Using huggingface-cli
pip install huggingface_hub
huggingface-cli download unsloth/MiniMax-M2.1-GGUF --include "UD-Q2_K_XL/*" --local-dir ./models
```

### Verifying Downloads

```bash
# Check file sizes
ls -lh models/*.gguf

# Verify with sha256 (if checksums available)
sha256sum models/*.gguf
```

## Performance Tuning

### Context Size vs Speed

Larger context uses more memory and can slow inference:

| Context | Memory Overhead | Use Case |
|---------|-----------------|----------|
| 4096 | Minimal | Quick tasks |
| 8192 | Low | Standard coding |
| 16384 | Moderate | Large files |
| 32768 | High | Multi-file context |

### Batch Size

For interactive use, smaller batch sizes give faster first-token latency:

```bash
llama-server -m model.gguf --batch-size 512  # Default
llama-server -m model.gguf --batch-size 256  # Faster response
```

## Benchmarking

Test model performance before committing:

```bash
# Quick benchmark
./build/bin/llama-bench -m model.gguf -n 128 -p 512

# Detailed benchmark
./build/bin/llama-bench -m model.gguf -n 128,256,512 -p 128,256,512 -r 3
```
