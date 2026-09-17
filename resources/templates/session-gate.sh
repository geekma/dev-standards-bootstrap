#!/usr/bin/env bash
# session-gate.sh — 会话内执法（v3.28.0）：把门禁从"commit 时刻"左移到"会话内"。
#
# 根因（CHG-071/BUG-040~055 复盘）：执法链锚在 commit（pre-commit/CI），而 Agent
# 会话产物长期停留在工作区不提交 → pre-commit/CI 永不点火 → 六件套缺口、溯源缺口
# 无任何机器红灯。本脚本由客户端 Session Hook / Plugin 在**会话事件**里调用：
#   · 会话开始（start）→ 跑一次跨文档一致性审计，把存量红灯亮给本会话；
#   · 会话空闲/收尾（idle）→ 跑 agent-gate --stage stop 等价检查，把未闭环写进报告。
#
# 调用方（由 install-hook-adapter 按当前客户端自适应生成，本脚本不感知客户端）：
#   claude  : .claude/settings.json SessionStart/Stop hook（stdout 注入会话上下文）
#   opencode: .opencode/plugins/dev-standards-gate.js（session.created / session.idle）
#   其他    : Git hooks + CI 兜底（校验仓库，不校验编辑器）
#
# 语义：start 永不阻断（exit 0），红灯 = 报告文件 + stdout 摘要；
#       idle 同样 exit 0（软执法 + 落盘报告）；硬阻断仍由 gate --stage stop（Claude
#       Stop hook）与 Git hooks 承担——本脚本只负责"让红灯被看见"。
#
# 零依赖：bash 3.2+、git；被调脚本缺失时降级为显式提示，不猜不编。
set -uo pipefail

mode="${1:-}"
case "$mode" in
  start|idle|status) ;;
  *) echo "usage: scripts/session-gate.sh start|idle|status" >&2; exit 2 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || pwd)
cd "$ROOT" 2>/dev/null || true

# 路径字面量保持 bootstrap.sh transform_src 可改写形态（自定义目录根时随装随改）
GATE="scripts/agent-gate"
AUDIT="tests/audit-docs-consistency.sh"
STATE_DIR=".agent-state"
REPORT="$STATE_DIR/session-gate-last.md"

mkdir -p "$STATE_DIR"

emit() { # 摘要进 stdout（Claude SessionStart 会把 stdout 注入上下文）+ 全文落盘
  printf '%s\n' "$1"
}

report_init() {
  {
    echo "# session-gate 报告 (${mode} @ $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown))"
    echo
  } > "$REPORT"
}

report_add() {
  printf '%s\n' "$1" >> "$REPORT"
}

has_code_changes() {
  command -v git >/dev/null 2>&1 || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  # 代码/配置类改动（排除文档产物与状态文件）：与 agent-gate is_code_path 同口径的
  # 粗粒度近似——有非 docs/、非 .agent-state 改动即视为"源码改动未留痕"。
  git status --porcelain 2>/dev/null | grep -vE '^\s*[AM?]+ +("?(docs/|\.agent-state/|\.agent-governance\.yml|\.claude/|\.opencode/|\.cursor/|\.gemini/))' | grep -q . 
}

case "$mode" in
  status)
    [[ -f "$REPORT" ]] && cat "$REPORT" || echo "session-gate: no report yet (run start/idle)"
    exit 0
    ;;
esac

report_init

if [[ "$mode" == "start" ]]; then
  if [[ ! -f "$AUDIT" ]]; then
    emit "session-gate: $AUDIT not found — cross-doc audit skipped (install --core first)"
    report_add "- $AUDIT 缺失，审计未跑（先接 --core 层）"
    exit 0
  fi
  # 存量红灯亮给本会话：--only-fail 只打 FAIL/skip 行（v3.23.0），输出天然紧凑
  out=$(bash "$AUDIT" --only-fail 2>&1 | tail -40)
  summary=$(printf '%s' "$out" | grep -E 'passed, [0-9]+ failed' | tail -1)
  reds=$(printf '%s' "$out" | grep -c '^FAIL' || true)
  if [[ "${reds:-0}" -gt 0 ]]; then
    emit "session-gate: GATE RED — $summary; 存量缺口见 ${REPORT}（失败项即 §2.14 回填清单）"
  else
    emit "session-gate: audit GREEN — $summary"
  fi
  {
    echo "## 审计输出（--only-fail）"
    echo '```'
    printf '%s\n' "$out"
    echo '```'
  } >> "$REPORT"
  exit 0
fi

# mode == idle：stop 等价检查
# active-change 的权威路径与 agent-gate 同源：git rev-parse --git-path
# agent-governance/active-change（落 .git/ 下，不污染工作区）。
active=""
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  af=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  [[ -f "$af" ]] && active=$(tr -d '[:space:]' < "$af" 2>/dev/null || true)
fi

if [[ -n "$active" && -x "$GATE" ]]; then
  emit "session-gate: running gate stop for active change $active ..."
  # 软执法：跳过 verification_command（可能是 mvn test 级全量回归，session.idle
  # 每轮触发跑不起）。结构/证据类校验照跑；全量回归由真实交付线（Claude Stop
  # hook / pre-commit / CI）承担——那里不设 AGENT_GUARD_SKIP_VERIFY。
  out=$(AGENT_GUARD_SKIP_VERIFY=1 bash "$GATE" --stage stop 2>&1 | tail -40); rc=$?
  if [[ "$rc" -eq 0 ]]; then
    emit "session-gate: stop checks GREEN ($active)"
    report_add "- gate --stage stop：通过（${active}）"
  else
    emit "session-gate: GATE RED — gate --stage stop 未过（${active}），处置清单见 $REPORT"
    report_add "- **gate --stage stop 未通过（exit ${rc}）**："
    report_add '```'
    printf '%s\n' "$out" >> "$REPORT"
    report_add '```'
  fi
elif [[ -n "$active" ]]; then
  emit "session-gate: $GATE missing — stop checks skipped (install --guard first)"
  report_add "- $GATE 缺失，stop 检查未跑"
else
  if has_code_changes; then
    emit "session-gate: GATE RED — source/config changed with NO active change (begin <id> first); see $REPORT"
    report_add "- **源码/配置有改动但无活跃变更**：先 \`$GATE begin <变更号>\`，修完不留痕 = §5 违规"
    report_add '- 改动清单（git status --porcelain 前 20 行）：'
    report_add '```'
    git status --porcelain 2>/dev/null | head -20 >> "$REPORT"
    report_add '```'
  else
    emit "session-gate: nothing to enforce (no active change, no code changes)"
    report_add "- 无活跃变更、无代码改动：无事可查"
  fi
fi

exit 0
