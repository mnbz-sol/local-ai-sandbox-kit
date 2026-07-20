#!/usr/bin/env bash
# probe-mac.sh — 最小プローブキット(4テスト) macOS 版
# "サンドボックスで安全に始めるローカルAI入門" 実践編(Mac) 第4章 対応
#
# 使い方:
#   bash probe-mac.sh [コンテナ名]
#   既定: cc-sandbox
#
# Windows/WSL 版(probe.sh)との違い:
#   P01 の隔離テストを docker inspect 方式に変更。
#   Mac の Docker Desktop ではホストマウントのパスに決まった
#   プレフィックスが無いため、mountinfo の grep では検出できない。

set -euo pipefail

TARGET="${1:-cc-sandbox}"
PASS=0; WARN=0; FAIL=0

header() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
pass()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
warn()   { printf '  \033[33mWARN\033[0m  %s\n' "$1"; WARN=$((WARN+1)); }
fail()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }

# コンテナが動いているか確認
if ! docker inspect --format '{{.State.Running}}' "$TARGET" 2>/dev/null | grep -q true; then
  printf '\033[31mERROR\033[0m: コンテナ "%s" が見つからないか停止中です。\n' "$TARGET"
  exit 2
fi

header "Probe: $TARGET"

# --- P01: 隔離(母艦マウント) ---
header "P01: 母艦が見えないか(隔離)"
MOUNTS=$(docker inspect --format '{{json .Mounts}}' "$TARGET" 2>/dev/null || echo "[]")
if [ "$MOUNTS" = "[]" ] || [ "$MOUNTS" = "null" ]; then
  pass "母艦のディレクトリはマウントされていない"
else
  fail "ボリュームがマウントされている"
  echo "  $MOUNTS"
fi

# --- P07: 権限(capability) ---
header "P07: 権限は絞られているか(最小権限)"
if docker exec "$TARGET" sh -c 'command -v capsh >/dev/null 2>&1'; then
  CAPS=$(docker exec "$TARGET" capsh --print 2>/dev/null || true)
  CURRENT=$(echo "$CAPS" | grep "^Current:" | head -1)
  if echo "$CURRENT" | grep -qE "cap_sys_admin|^Current: *=ep *\$"; then
    fail "危険な capability が付与されている(cap_sys_admin または Current: =ep 単体を検出)"
  else
    pass "特権モードではない(capability が制限されている)"
  fi
  echo "  $CURRENT"
else
  warn "capsh 未インストール(apt install libcap2-bin で導入可)"
fi

# --- P08: ネットワーク(DNS/HTTP) ---
header "P08: 通信経路(ネットワーク最小化)"
if docker exec "$TARGET" sh -c 'command -v dig >/dev/null 2>&1'; then
  DNS=$(docker exec "$TARGET" dig +short example.com 2>/dev/null || true)
  if [ -n "$DNS" ]; then
    pass "DNS 解決可(egress 経路あり): $DNS"
  else
    warn "DNS 解決不可(egress が遮断されている可能性)"
  fi
else
  warn "dig 未インストール(apt install dnsutils で導入可)"
fi

if docker exec "$TARGET" sh -c 'command -v curl >/dev/null 2>&1'; then
  HTTP=$(docker exec "$TARGET" curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://example.com 2>/dev/null || echo "000")
  if [ "$HTTP" = "200" ]; then
    pass "HTTPS egress 可(外向き通信が通る)"
  else
    warn "HTTPS egress 不可(HTTP $HTTP)"
  fi
else
  warn "curl 未インストール(apt install curl で導入可)"
fi

# --- P11: ポート公開 ---
header "P11: 公開ポート"
PORTS=$(docker port "$TARGET" 2>/dev/null || true)
if [ -z "$PORTS" ]; then
  pass "公開ポートなし(外から箱へ入る口はない)"
else
  warn "公開ポートあり:"
  echo "$PORTS"
fi

# --- 結果サマリ ---
printf '\n\033[1m--- 結果 ---\033[0m\n'
printf '  PASS: %d / WARN: %d / FAIL: %d\n' "$PASS" "$WARN" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  printf '  \033[31m隔離に問題があります。設定を見直してください。\033[0m\n'
  exit 1
elif [ "$WARN" -gt 0 ]; then
  printf '  \033[33mツール未導入の項目があります。\033[0m\n'
  exit 0
else
  printf '  \033[32mすべて合格です。\033[0m\n'
  exit 0
fi
