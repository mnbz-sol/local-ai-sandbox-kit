#!/usr/bin/env bash
# sizing-bench.sh — サイジング実測スクリプト（CPU経路）
#
# cc-sandbox コンテナ内で実行する。Ollama が起動済みであること。
#
# 使い方:
#   docker cp sizing-bench.sh cc-sandbox:/tmp/
#   docker exec cc-sandbox bash /tmp/sizing-bench.sh
#
# カスタムモデルリスト:
#   docker exec cc-sandbox bash /tmp/sizing-bench.sh llama3.2:1b llama3.2:3b

set -uo pipefail

PROMPT="Explain what a Docker container is in exactly three sentences."
API="http://127.0.0.1:11434"

if [ $# -gt 0 ]; then
  MODELS=("$@")
else
  MODELS=(
    "llama3.2:1b"
    "llama3.2:3b"
    "gemma3:4b"
    "llama3.1:8b"
  )
fi

wait_for_ollama() {
  local retries=10
  while [ $retries -gt 0 ]; do
    if curl -sf "$API" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    retries=$((retries - 1))
  done
  echo "ERROR: Ollama is not running at $API" >&2
  exit 1
}

unload_all() {
  local loaded
  loaded=$(curl -sf "$API/api/ps" 2>/dev/null || echo '{"models":[]}')
  echo "$loaded" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | while read -r m; do
    curl -sf "$API/api/generate" -d "{\"model\":\"$m\",\"keep_alive\":0}" >/dev/null 2>&1 || true
  done
  sleep 2
}

extract_field() {
  local json="$1" field="$2"
  echo "$json" | grep -o "\"${field}\":[0-9]*" | head -1 | grep -o '[0-9]*$'
}

echo ""
echo "=== sizing-bench: サイジング実測 (CPU) ==="
echo ""
echo "date      : $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"

cpu_name=$(cat /proc/cpuinfo 2>/dev/null | grep 'model name' | head -1 | sed 's/.*: //')
mem_total=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")
echo "cpu       : ${cpu_name:-unknown}"
echo "container : ${mem_total}GB visible"
echo "prompt    : \"$PROMPT\""
echo ""

wait_for_ollama

HEADER=$(printf "| %-18s | %6s | %8s | %8s | %10s | %s" \
  "model" "params" "tok/s" "tokens" "model_mem" "note")
SEP=$(printf "| %-18s | %6s | %8s | %8s | %10s | %s" \
  "------------------" "------" "--------" "--------" "----------" "----")

echo "$HEADER |"
echo "$SEP |"

for model in "${MODELS[@]}"; do
  echo "# pulling $model ..." >&2
  if ! ollama pull "$model" >/dev/null 2>&1; then
    printf "| %-18s | %6s | %8s | %8s | %10s | %s |\n" \
      "$model" "-" "-" "-" "-" "pull failed"
    continue
  fi

  unload_all

  echo "# warming up $model ..." >&2
  warmup=$(curl -sf "$API/api/generate" -d "{\"model\":\"$model\",\"prompt\":\"hi\",\"stream\":false}" 2>/dev/null || echo "")
  if [ -z "$warmup" ]; then
    printf "| %-18s | %6s | %8s | %8s | %10s | %s |\n" \
      "$model" "-" "-" "-" "-" "load failed"
    continue
  fi
  sleep 1

  ps_out=$(curl -sf "$API/api/ps" 2>/dev/null || echo "")
  size_vram=$(extract_field "$ps_out" "size_vram")
  if [ -n "$size_vram" ] && [ "$size_vram" -gt 0 ] 2>/dev/null; then
    mem_mb=$((size_vram / 1048576))
    mem_label="${mem_mb}MB"
  else
    size_val=$(extract_field "$ps_out" "size")
    if [ -n "$size_val" ] && [ "$size_val" -gt 0 ] 2>/dev/null; then
      mem_mb=$((size_val / 1048576))
      mem_label="${mem_mb}MB"
    else
      mem_label="?"
    fi
  fi

  params=$(echo "$model" | grep -oE '[0-9]+(\.[0-9]+)?[bB]' | head -1)
  [ -z "$params" ] && params="?"

  echo "# benchmarking $model ..." >&2
  result=$(curl -sf "$API/api/generate" -d "{
    \"model\": \"$model\",
    \"prompt\": \"$PROMPT\",
    \"stream\": false
  }" 2>/dev/null || echo "")

  if [ -z "$result" ]; then
    printf "| %-18s | %6s | %8s | %8s | %10s | %s |\n" \
      "$model" "$params" "-" "-" "$mem_label" "generate failed"
    continue
  fi

  eval_count=$(extract_field "$result" "eval_count")
  eval_duration=$(extract_field "$result" "eval_duration")
  total_duration=$(extract_field "$result" "total_duration")

  note=""
  if [ -n "$eval_count" ] && [ -n "$eval_duration" ] && [ "$eval_duration" -gt 0 ] 2>/dev/null; then
    tok_s=$(awk "BEGIN {printf \"%.1f\", $eval_count * 1000000000 / $eval_duration}")
  else
    tok_s="-"
    note="eval parse error"
  fi

  [ -z "$eval_count" ] && eval_count="-"

  printf "| %-18s | %6s | %8s | %8s | %10s | %s |\n" \
    "$model" "$params" "$tok_s" "$eval_count" "$mem_label" "$note"
done

echo ""
echo "=== done ==="
echo ""
echo "# 計測条件: CPU推論（GPU未使用）、Docker コンテナ内、各モデル1回計測"
echo "# tok/s = eval_count / (eval_duration / 1e9)"
echo "# model_mem = Ollama が報告するモデルのメモリ使用量"
