# Quick Reference: Dual SPARK Setup

## Start Distributed Setup

**SPARK1 (Head):**
```bash
./startHead.sh
./serve.sh
```

**SPARK2 (Worker):**
```bash
./startWorker.sh
```

## Switch OpenCode to Distributed Mode
```bash
cp opencode.json ~/.config/opencode/opencode.json
opencode
```

## Stop Everything
```bash
./shutdown.sh
```

## Check Status
```bash
docker exec <container> ray status
```

## Use OSS120B Model
```bash
modelType=oss120b ./serve.sh
```

## Manual Head IP Detection
```bash
ip -4 addr show | grep inet
```

## View Logs
```bash
docker exec <container> tail -f /tmp/vllmServe.log
```

## Restore Single-Machine Mode
```bash
# Go to single-spark directory
cd ../single-spark
./setup.sh --launch-only
cp opencode.json ~/.config/opencode/opencode.json
```

---

**Files:**
- `runCluster.sh` - Core Ray cluster Docker launcher
- `startHead.sh` - Start head node (saves IP auto)
- `startWorker.sh` - Start worker node (reads IP auto)
- `serve.sh` - Launch vLLM serve
- `shutdown.sh` - Stop all services
- `opencode.json` - OpenCode config for distributed mode
- `README.md` - Full documentation
