# Distributed OpenCode Infrastructure (Dual SPARKS)

This setup deploys OpenCode with distributed model serving across **two SPARKS machines** using Ray cluster and vLLM.

## Model

By default, this uses **MiniMax-M2.1-UD-Q2_K_XL** (~86GB, 228B params). To use **OSS120B** instead, set:
```bash
modelTag=openai/gpt-oss-120b ./serveDistributed.sh
```

## Quick Start

### On SPARK1 (Head Node)
```bash
./startHead.sh
./serveDistributed.sh
```

### On SPARK2 (Worker Node)
```bash
./startWorker.sh
```
The worker script will auto-detect the head node IP if you configure it in the script.

## Files

| File | Description |
|------|-------------|
| `startHead.sh` | Starts Ray head node on SPARK1 |
| `startWorker.sh` | Starts Ray worker node on SPARK2 |
| `serveDistributed.sh` | Launches vLLM serve with tensor parallelism |
| `status-distributed.sh` | Checks cluster status |
| `shutdown-distributed.sh` | Stops all distributed services |
| `opencode-distributed.json` | OpenCode config for distributed mode |

## Configuration

Edit environment variables in scripts or set them inline:

```bash
# Use OSS120B model
modelTag=openai/gpt-oss-120b ./serveDistributed.sh

# Custom port
portBind=9000 ./serveDistributed.sh

# Custom tensor parallel size (match your GPU count)
tensorParallelSize=2 ./serveDistributed.sh
```

### Default Settings
- **Model**: `unsloth/MiniMax-M2.1-GGUF` (or OSS120B)
- **Port**: `8080`
- **Tensor Parallel Size**: `2` (one GPU per machine)
- **Max Model Length**: `131072`
- **GPU Memory**: `0.88`

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
cp opencode-distributed.json ~/.config/opencode/opencode.json

# Start OpenCode
opencode
```

## Troubleshooting

**Container not found:**
```bash
docker ps | grep node-
```

**Worker connection failed:**
```bash
# On head node
docker exec <container> ray status

# Check network
ping <worker_ip>
```

**API not accessible:**
```bash
docker exec <container> tail -f /tmp/vllmServe.log
```

## Alternative: llama.cpp RPC Mode

For llama.cpp-based distributed serving instead of vLLM:

```bash
# On SPARK1
./setup-opencode-minimax-distributed.sh --head

# On SPARK2
./setup-opencode-minimax-distributed.sh --worker <spark1_ip>
```

This uses llama.cpp's built-in RPC for tensor parallelism.
