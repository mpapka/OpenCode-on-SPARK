#!/usr/bin/env bash
set -euo pipefail

: "${mnIfName:=auto}"
: "${headIp:=auto}"
: "${vllmImage:=nvcr.io/nvidia/vllm:25.11-py3}"
: "${hfCacheDir:=$HOME/.cache/huggingface}"
: "${rayStartTimeoutSec:=300}"
: "${pollIntervalSec:=5}"

scriptTag="startHead"

if [[ -t 1 ]]; then
  cReset=$'\033[0m'; cRed=$'\033[31m'; cGreen=$'\033[32m'; cYellow=$'\033[33m'; cBlue=$'\033[34m'
else
  cReset=""; cRed=""; cGreen=""; cYellow=""; cBlue=""
fi

ts() { date +"%Y-%m-%d %H:%M:%S"; }
logInfo() { echo "${cBlue}$(ts) INFO  [$scriptTag]${cReset} $*"; }
logWarn() { echo "${cYellow}$(ts) WARN  [$scriptTag]${cReset} $*" >&2; }
logErr()  { echo "${cRed}$(ts) ERROR [$scriptTag]${cReset} $*" >&2; }
logOk()   { echo "${cGreen}$(ts) OK    [$scriptTag]${cReset} $*"; }
die() { logErr "$*"; exit 1; }

checkDocker() { docker info >/dev/null 2>&1; }
ensureDocker() { checkDocker || die "Docker not accessible. Fix docker group then logout/login."; }

getIpv4OnIface() {
  ip -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

detectMnIfNameWithIpv4() {
  if command -v ibdev2netdev >/dev/null 2>&1; then
    while read -r iface; do
      [[ -n "${iface:-}" ]] || continue
      ip4="$(getIpv4OnIface "$iface" || true)"
      [[ -n "${ip4:-}" ]] && { echo "$iface"; return 0; }
    done < <(ibdev2netdev 2>/dev/null | awk '/==>/{for(i=1;i<=NF;i++) if($i=="==>") print $(i+1)}' | tr -d '()')
  fi

  while read -r iface; do
    [[ -n "${iface:-}" ]] || continue
    ip4="$(getIpv4OnIface "$iface" || true)"
    [[ -n "${ip4:-}" ]] && { echo "$iface"; return 0; }
  done < <(ip -o link show up | awk -F': ' '$2!="lo"{print $2}')

  return 1
}

resolveNetwork() {
  if [[ "$mnIfName" == "auto" ]]; then
    mnIfName="$(detectMnIfNameWithIpv4)" || die "Could not detect NIC with IPv4. Run: ip -4 addr"
    logOk "Auto-detected mnIfName=$mnIfName"
  fi

  ipAddr="$(getIpv4OnIface "$mnIfName" || true)"
  [[ -n "${ipAddr:-}" ]] || die "No IPv4 on $mnIfName. Run: ip -4 addr show $mnIfName"

  if [[ "$headIp" == "auto" ]]; then
    headIp="$ipAddr"
    logOk "Auto-detected headIp=$headIp from $mnIfName"
  fi

  mkdir -p "$HOME/.opencode"
  echo "$headIp" > "$HOME/.opencode/head_node_ip"
  logInfo "Saved head IP to $HOME/.opencode/head_node_ip"
}

getHeadContainerName() {
  docker ps --format '{{.Names}}' | grep -E '^node-' | head -n 1 || true
}

waitForHeadContainer() {
  logInfo "Waiting for head container (node-*)..."
  startTime="$(date +%s)"
  while true; do
    c="$(getHeadContainerName)"
    if [[ -n "${c:-}" ]]; then
      logOk "Found head container: $c"
      echo "$c"
      return 0
    fi
    nowTime="$(date +%s)"
    (( nowTime - startTime > rayStartTimeoutSec )) && die "Timed out waiting for container. Check /tmp/runClusterHead.log"
    sleep "$pollIntervalSec"
  done
}

ensureDocker
resolveNetwork

logInfo "Using configuration:"
logInfo "  mnIfName=$mnIfName"
logInfo "  headIp=$headIp"
logInfo "  vllmImage=$vllmImage"
logInfo "  hfCacheDir=$hfCacheDir"

logInfo "Starting Ray head via run_cluster.sh (detached)..."
nohup bash ./run_cluster.sh "$vllmImage" "$headIp" --head "$hfCacheDir" \
  -e VLLM_HOST_IP="$headIp" \
  -e UCX_NET_DEVICES="$mnIfName" \
  -e NCCL_SOCKET_IFNAME="$mnIfName" \
  -e OMPI_MCA_btl_tcp_if_include="$mnIfName" \
  -e GLOO_SOCKET_IFNAME="$mnIfName" \
  -e TP_SOCKET_IFNAME="$mnIfName" \
  -e RAY_memory_monitor_refresh_ms=0 \
  >/tmp/runClusterHead.log 2>&1 &

logOk "Head launcher pid=$! (logs: /tmp/runClusterHead.log)"

headC="$(waitForHeadContainer)"
logOk "Head container is up: $headC"

logInfo "NOW start the worker on aspark01:"
logInfo "  ./startWorker.sh"
