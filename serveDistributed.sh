#!/bin/bash
#
# serveDistributed.sh
#
# Launch vLLM serve on a distributed Ray cluster spanning two SPARKS.
#
# Usage:
# 1. On SPARK1 (head): ./startHead.sh first
# 2. On SPARK2 (worker): ./startWorker.sh <head_ip> first
# 3. Then run this script on either machine
#

set -e

: "${modelTag:=unsloth/MiniMax-M2.1-GGUF}"
: "${modelType:=minimax}"
: "${hostBind:=0.0.0.0}"
: "${portBind:=8080}"
: "${tensorParallelSize:=2}"
: "${maxModelLen:=131072}"
: "${gpuMemoryUtilization:=0.88}"
: "${extraVllmArgs:=}"
: "${apiWaitTimeoutSec:=900}"
: "${pollIntervalSec:=5}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

scriptTag="serveDistributed"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
logInfo() { echo "${BLUE}$(ts) INFO  [$scriptTag]${NC} $*"; }
logWarn() { echo "${YELLOW}$(ts) WARN  [$scriptTag]${NC} $*" >&2; }
logErr()  { echo "${RED}$(ts) ERROR [$scriptTag]${NC} $*" >&2; }
logOk()   { echo "${GREEN}$(ts) OK    [$scriptTag]${NC} $*"; }
die() { logErr "$*"; exit 1; }

headC="$(docker ps --format '{{.Names}}' | grep -E '^node-' | head -n 1 || true)"
[[ -n "${headC:-}" ]] || die "No head node-* container found. Run startHead.sh first."

if [[ "$modelType" == "oss120b" ]]; then
    modelTag="openai/gpt-oss-120b"
fi

logInfo "Head container: $headC"
logInfo "Model: $modelTag"
logInfo "Launching vLLM serve in container (log: /tmp/vllmServe.log)..."

docker exec -d "$headC" bash -lc "
set -e
nohup vllm serve '$modelTag' \
  --host '$hostBind' \
  --port '$portBind' \
  --tensor-parallel-size '$tensorParallelSize' \
  --max-model-len '$maxModelLen' \
  --gpu-memory-utilization '$gpuMemoryUtilization' \
  $extraVllmArgs \
  >/tmp/vllmServe.log 2>&1 &
" >/dev/null

logOk "vLLM serve launched."
logInfo "Follow logs: docker exec -it $headC tail -f /tmp/vllmServe.log"

fetchModelsJson() {
  if curl -fsS "http://127.0.0.1:${portBind}/v1/models" 2>/dev/null; then
    return 0
  fi
  docker exec -i "$headC" bash -lc "curl -fsS http://127.0.0.1:${portBind}/v1/models" 2>/dev/null
}

logInfo "Waiting for API readiness on port ${portBind} (timeout ${apiWaitTimeoutSec}s)..."
startTime="$(date +%s)"

while true; do
  modelsJson="$(fetchModelsJson || true)"

  if [[ -n "${modelsJson:-}" ]]; then
    if echo "$modelsJson" | grep -q "\"max_model_len\":${maxModelLen}"; then
      logOk "API ready and max_model_len=${maxModelLen}"

      if curl -fsS "http://127.0.0.1:${portBind}/v1/models" >/dev/null 2>&1; then
        logOk "Host can reach API at http://127.0.0.1:${portBind}"
      else
        logWarn "API reachable inside container, but host curl failed."
        logWarn "Since run_cluster.sh uses --network host, host access *should* work."
      fi
      break
    else
      logWarn "API responded but max_model_len not yet seen; still initializing..."
    fi
  fi

  nowTime="$(date +%s)"
  if (( nowTime - startTime > apiWaitTimeoutSec )); then
    logWarn "Last 120 lines of vLLM log:"
    docker exec -i "$headC" bash -lc 'tail -n 120 /tmp/vllmServe.log || true' >&2
    die "Timed out waiting for API readiness."
  fi

  sleep "$pollIntervalSec"
done

logInfo "Client example (safe max_tokens=3072):"
cat <<EOF
curl -s http://127.0.0.1:${portBind}/v1/chat/completions \\
  -H "Content-Type: application/json" \\
  -d '{
    "model":"${modelTag}",
    "messages":[{"role":"user", "content":"Write a hello world in Python"}],
    "temperature":0.2,
    "max_tokens":3072
  }' | python3 -m json.tool
EOF

log_success "Distributed vLLM serving ready!"
