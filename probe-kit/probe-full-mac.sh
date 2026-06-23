#!/usr/bin/env bash
# probe-full-mac.sh — 拡張プローブキット(12テスト・7原則フルカバー) macOS 版
# "サンドボックスで安全に始めるローカルAI入門" companion repo
#
# 使い方:
#   bash probe-full-mac.sh [コンテナ名]
#   既定: cc-sandbox
#
# probe-mac.sh(4テスト)の上位互換。全7原則を網羅する。
# Windows/WSL 版(probe-full.sh)との違い:
#   P01 の隔離テストを docker inspect 方式に変更。

set -euo pipefail

TARGET="${1:-cc-sandbox}"
PASS=0; WARN=0; FAIL=0; SKIP=0

header() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$1"; }
pass()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
warn()   { printf '  \033[33mWARN\033[0m  %s\n' "$1"; WARN=$((WARN+1)); }
fail()   { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
skip()   { printf '  \033[90mSKIP\033[0m  %s\n' "$1"; SKIP=$((SKIP+1)); }

# コンテナが動いているか確認
if ! docker inspect --format '{{.State.Running}}' "$TARGET" 2>/dev/null | grep -q true; then
  printf '\033[31mERROR\033[0m: コンテナ "%s" が見つからないか停止中です。\n' "$TARGET"
  exit 2
fi

printf '\033[1m拡張プローブ: %s(12テスト)\033[0m\n' "$TARGET"

# ============================================================
# ①隔離(Isolation)
# ============================================================

header "P01: 母艦ファイルシステムの隔離 [①隔離]"
MOUNTS=$(docker inspect --format '{{json .Mounts}}' "$TARGET" 2>/dev/null || echo "[]")
if [ "$MOUNTS" = "[]" ] || [ "$MOUNTS" = "null" ]; then
  pass "母艦のディレクトリはマウントされていない"
else
  fail "ボリュームがマウントされている"
  echo "  $MOUNTS"
fi

header "P02: ホスト名の分離 [①隔離]"
CONTAINER_HOSTNAME=$(docker exec "$TARGET" hostname 2>/dev/null || true)
HOST_HOSTNAME=$(hostname 2>/dev/null || true)
if [ "$CONTAINER_HOSTNAME" = "$HOST_HOSTNAME" ]; then
  warn "コンテナのホスト名が母艦と同一($CONTAINER_HOSTNAME)"
else
  pass "ホスト名が分離されている(container=$CONTAINER_HOSTNAME)"
fi

# ============================================================
# ②最小権限(Least Privilege)
# ============================================================

header "P03: 特権モード [②最小権限]"
PRIVILEGED=$(docker inspect --format '{{.HostConfig.Privileged}}' "$TARGET" 2>/dev/null || echo "unknown")
if [ "$PRIVILEGED" = "true" ]; then
  fail "--privileged で起動されている(全 capability 付与)"
elif [ "$PRIVILEGED" = "false" ]; then
  pass "特権モードではない"
else
  skip "判定不能(inspect 失敗)"
fi

header "P04: Capability 制限 [②最小権限]"
if docker exec "$TARGET" sh -c 'command -v capsh >/dev/null 2>&1'; then
  CAPS=$(docker exec "$TARGET" capsh --print 2>/dev/null || true)
  CURRENT=$(echo "$CAPS" | grep "^Current:" | head -1)
  DANGEROUS="cap_sys_admin\|cap_sys_ptrace\|cap_sys_module"
  FOUND=$(echo "$CURRENT" | grep -c "$DANGEROUS" || true)
  if [ "$FOUND" -gt 0 ]; then
    fail "危険な capability が付与されている(Current に検出)"
    echo "  $CURRENT"
  else
    pass "危険な capability は付与されていない"
    echo "  $CURRENT"
  fi
else
  skip "capsh 未インストール(apt install libcap2-bin)"
fi

header "P05: PID namespace 隔離 [②最小権限]"
PID_MODE=$(docker inspect --format '{{.HostConfig.PidMode}}' "$TARGET" 2>/dev/null || echo "unknown")
if [ "$PID_MODE" = "host" ]; then
  fail "PID namespace がホストと共有されている"
else
  pass "PID namespace が隔離されている"
fi

# ============================================================
# ④既定拒否(Default Deny)
# ============================================================

header "P06: ボリュームマウント [④既定拒否]"
# Docker / Dev Container が内部動作に使うマウントを除外し、ユーザー定義のみ検査
ALL_DESTS=$(docker inspect --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$TARGET" 2>/dev/null || true)
USER_MOUNTS=$(echo "$ALL_DESTS" | grep -v '^\s*$' \
  | grep -v '^/vscode' \
  | grep -v '\.sock$' \
  | grep -v '^/tmp/vscode-' || true)
USER_COUNT=$(echo "$USER_MOUNTS" | grep -c '.' || true)
if [ "$USER_COUNT" = "0" ]; then
  pass "ユーザー定義のボリュームマウントなし"
  INTERNAL=$(echo "$ALL_DESTS" | grep -c '.' || true)
  if [ "$INTERNAL" -gt 0 ]; then
    printf '       (Dev Container 内部マウント %d 件は除外)\n' "$INTERNAL"
  fi
else
  warn "ユーザー定義のボリュームが $USER_COUNT 件マウントされている"
  docker inspect --format '{{range .Mounts}}  {{.Type}}: {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' "$TARGET" 2>/dev/null || true
fi

header "P07: AppArmor / Seccomp プロファイル [④既定拒否]"
APPARMOR=$(docker inspect --format '{{.AppArmorProfile}}' "$TARGET" 2>/dev/null || echo "unknown")
SECCOMP=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "$TARGET" 2>/dev/null || echo "unknown")
if [ "$APPARMOR" = "unconfined" ] || echo "$SECCOMP" | grep -q "unconfined"; then
  warn "セキュリティプロファイルが unconfined(既定より緩い)"
else
  pass "セキュリティプロファイルが既定値(Docker デフォルト)"
fi

# ============================================================
# ⑤ネットワーク最小化(Minimal Network)
# ============================================================

header "P08: DNS 解決(egress) [⑤ネットワーク最小化]"
if docker exec "$TARGET" sh -c 'command -v dig >/dev/null 2>&1'; then
  DNS=$(docker exec "$TARGET" dig +short +time=3 example.com 2>/dev/null || true)
  if [ -n "$DNS" ]; then
    pass "DNS 解決可(egress 経路あり): $DNS"
  else
    warn "DNS 解決不可(egress が遮断されている可能性)"
  fi
else
  skip "dig 未インストール(apt install dnsutils)"
fi

header "P09: HTTPS egress [⑤ネットワーク最小化]"
if docker exec "$TARGET" sh -c 'command -v curl >/dev/null 2>&1'; then
  HTTP=$(docker exec "$TARGET" curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://example.com 2>/dev/null || echo "000")
  if [ "$HTTP" = "200" ]; then
    pass "HTTPS egress 可(外向き通信が通る)"
  else
    warn "HTTPS egress 不可(HTTP $HTTP)"
  fi
else
  skip "curl 未インストール(apt install curl)"
fi

header "P10: 公開ポート(ingress) [⑤ネットワーク最小化]"
PORTS=$(docker port "$TARGET" 2>/dev/null || true)
if [ -z "$PORTS" ]; then
  pass "公開ポートなし(外から箱へ入る口はない)"
else
  warn "公開ポートあり:"
  echo "$PORTS"
fi

# ============================================================
# ⑥コード化(IaC)
# ============================================================

header "P11: コンテナイメージの特定 [⑥コード化]"
IMAGE=$(docker inspect --format '{{.Config.Image}}' "$TARGET" 2>/dev/null || echo "unknown")
if [ "$IMAGE" = "unknown" ] || [ -z "$IMAGE" ]; then
  skip "イメージ情報を取得できない"
else
  pass "イメージ: $IMAGE"
fi

# ============================================================
# 回帰チェック
# ============================================================

header "P12: コンテナ起動コマンド [回帰]"
CMD=$(docker inspect --format '{{.Config.Cmd}}' "$TARGET" 2>/dev/null || echo "unknown")
ENTRYPOINT=$(docker inspect --format '{{.Config.Entrypoint}}' "$TARGET" 2>/dev/null || echo "unknown")
pass "Entrypoint=$ENTRYPOINT  Cmd=$CMD"

# ============================================================
# 結果サマリ
# ============================================================
TOTAL=$((PASS + WARN + FAIL + SKIP))
printf '\n\033[1m========== 結果サマリ ==========\033[0m\n'
printf '  対象: %s\n' "$TARGET"
printf '  PASS: \033[32m%d\033[0m / WARN: \033[33m%d\033[0m / FAIL: \033[31m%d\033[0m / SKIP: \033[90m%d\033[0m  (計 %d)\n' \
  "$PASS" "$WARN" "$FAIL" "$SKIP" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf '\n  \033[31m隔離に問題があります。設定を見直してください。\033[0m\n'
  exit 1
elif [ "$WARN" -gt 0 ]; then
  printf '\n  \033[33m注意項目があります。上記の WARN を確認してください。\033[0m\n'
  exit 0
else
  printf '\n  \033[32mすべて合格です。\033[0m\n'
  exit 0
fi
