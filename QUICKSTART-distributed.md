# Quick Reference: Distributed OpenCode

## Start Distributed Setup

**SPARK1 (Head):**
```bash
./startHead.sh
./serveDistributed.sh
```

**SPARK2 (Worker):**
```bash
./startWorker.sh
```

## Switch OpenCode to Distributed Mode
```bash
cp opencode-distributed.json ~/.config/opencode/opencode.json
opencode
```

## Stop Everything
```bash
./shutdown-distributed.sh
```

## Check Status
```bash
./status-distributed.sh
```

## Use OSS120B Model
```bash
modelType=oss120b ./serveDistributed.sh
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
./setup-opencode-minimax.sh --launch-only
cp opencode.json ~/.config/opencode/opencode.json
```

---

**Files:**
- `startHead.sh` - Start head node (saves IP auto)
- `startWorker.sh` - Start worker node (reads IP auto)
- `serveDistributed.sh` - Launch vLLM serve
- `status-distributed.sh` - Check cluster status
- `shutdown-distributed.sh` - Stop all services
- `opencode-distributed.json` - OpenCode config
- `README-distributed.md` - Full documentation
