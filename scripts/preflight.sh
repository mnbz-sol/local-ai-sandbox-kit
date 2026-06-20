#!/usr/bin/env bash
# preflight.sh — Linux 環境適性ゲート
# 「サンドボックスで安全に始めるローカルAI入門」実践編 第1章の前に実行
#
# 使い方:
#   bash preflight.sh

set -euo pipefail

printf '\n\033[1;36m=== preflight: 環境適性チェック (Linux) ===\033[0m\n\n'

VERDICT="PASS"

check() {
  local name="$1" value="$2" status="$3" note="${4:-}"
  local color
  case "$status" in
    PASS) color="\033[32m" ;;
    WARN) color="\033[33m" ;;
    FAIL) color="\033[31m" ;;
    *)    color="\033[90m" ;;
  esac
  printf '  %-20s %-30s [%b%s\033[0m]\n' "$name" "$value" "$color" "$status"
  [ -n "$note" ] && printf '  %20s %s\n' "" "$note"

  if [ "$status" = "FAIL" ]; then VERDICT="FAIL"; fi
  if [ "$status" = "WARN" ] && [ "$VERDICT" = "PASS" ]; then VERDICT="WARN"; fi
}

# --- arch ---
ARCH=$(uname -m)
check "arch" "$ARCH" "info"

# --- cpu_name ---
CPU_NAME=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
check "cpu" "$CPU_NAME" "info"

# --- ram_gb ---
RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
RAM_GB=$(( RAM_KB / 1024 / 1024 ))
if [ "$RAM_GB" -ge 32 ]; then
  check "ram" "${RAM_GB} GB" "PASS" "32GB以上: 実測表の環境と同等"
elif [ "$RAM_GB" -ge 16 ]; then
  check "ram" "${RAM_GB} GB" "PASS" "16GB以上: 本書の手順を完遂可能"
elif [ "$RAM_GB" -ge 8 ]; then
  check "ram" "${RAM_GB} GB" "WARN" "16GB未満: 小型モデル(1B)のみ動作可能"
else
  check "ram" "${RAM_GB} GB" "FAIL" "8GB未満: 本書の手順を完遂できない可能性が高い"
fi

# --- disk_free_gb ---
DISK_FREE=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -d ' G' || echo 0)
if [ "$DISK_FREE" -ge 20 ]; then
  check "disk_free" "${DISK_FREE} GB (/)" "PASS"
elif [ "$DISK_FREE" -ge 10 ]; then
  check "disk_free" "${DISK_FREE} GB (/)" "WARN" "20GB 以上を推奨"
else
  check "disk_free" "${DISK_FREE} GB (/)" "FAIL" "ディスク空き不足"
fi

# --- virtualization ---
VT="not detected"
if grep -qE 'vmx|svm' /proc/cpuinfo 2>/dev/null; then
  VT="enabled"
  check "virtualization" "$VT" "PASS"
elif [ -f /sys/module/kvm/parameters/nested ] || lsmod 2>/dev/null | grep -q kvm; then
  VT="kvm loaded"
  check "virtualization" "$VT" "PASS"
else
  check "virtualization" "$VT" "WARN" "KVM/VT-x が検出されません"
fi

# --- docker ---
if command -v docker >/dev/null 2>&1; then
  DOCKER_VER=$(docker --version 2>/dev/null || echo "installed (version unknown)")
  check "docker" "$DOCKER_VER" "PASS"
else
  check "docker" "not found" "WARN" "Docker のインストールが必要です（第1章参照）"
fi

# --- tier ---
if [ "$RAM_GB" -ge 32 ]; then TIER="recommended"
elif [ "$RAM_GB" -ge 16 ]; then TIER="standard"
elif [ "$RAM_GB" -ge 8 ];  then TIER="minimum"
else TIER="unsupported"; fi

# --- verdict ---
printf '\n'
case "$VERDICT" in
  PASS) printf '  verdict: \033[32m%s\033[0m (tier: %s)\n' "$VERDICT" "$TIER" ;;
  WARN) printf '  verdict: \033[33m%s\033[0m (tier: %s)\n' "$VERDICT" "$TIER" ;;
  FAIL) printf '  verdict: \033[31m%s\033[0m (tier: %s)\n' "$VERDICT" "$TIER" ;;
esac
printf '\n'

case "$VERDICT" in
  FAIL) exit 2 ;;
  WARN) exit 1 ;;
  *)    exit 0 ;;
esac
