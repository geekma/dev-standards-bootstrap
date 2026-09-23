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
  start|idle|status|count) ;;
  *) echo "usage: scripts/session-gate.sh start|idle|status|count turn|count tool <name|->" >&2; exit 2 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || pwd)
cd "$ROOT" 2>/dev/null || true

# 路径字面量保持 bootstrap.sh transform_src 可改写形态（自定义目录根时随装随改）
GATE="scripts/agent-gate"
AUDIT="tests/audit-docs-consistency.sh"
STATE_DIR=".agent-state"
REPORT="$STATE_DIR/session-gate-last.md"
STATS_FILE="$STATE_DIR/session-tool-stats.json"
WATER_FILE="$STATE_DIR/session-water.json"

mkdir -p "$STATE_DIR"

# ---- 会话遥测（v3.39.0，CHG-042）：轮次/工具计数的通用层 --------------------
# 设计裁定：计数逻辑只活在这里（bash，任意 harness 可接线），客户端适配器只做
# 事件转发——Claude 走 UserPromptSubmit/PostToolUse hook，OpenCode 插件走
# chat.message / message.part.updated；无适配器的 harness 天然零开销跳过。
# gate begin 只读磁盘水位文件（§2.9.6），永不依赖客户端运行时。

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S; }

reset_state() {
  printf '{"turns":0,"bash":0,"grep":0,"other":0,"total":0,"updated_at":"%s"}\n' "$(now_iso)" > "$STATS_FILE"
  printf '{"turns":0,"session":"","updated_at":"%s"}\n' "$(now_iso)" > "$WATER_FILE"
}

stat_get() { sed -n "s/.*\"$1\":[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$STATS_FILE" 2>/dev/null | head -1; }

stat_write() { # turns bash grep other total
  printf '{"turns":%s,"bash":%s,"grep":%s,"other":%s,"total":%s,"updated_at":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "$(now_iso)" > "$STATS_FILE"
}

water_write() { # <turns>
  printf '{"turns":%s,"session":"","updated_at":"%s"}\n' "$1" "$(now_iso)" > "$WATER_FILE"
}

stats_line() {
  printf 'session-gate: session stats — turns %s, bash %s, grep %s, other %s (resource discipline baseline: bash <= 20)' \
    "$(stat_get turns)" "$(stat_get bash)" "$(stat_get grep)" "$(stat_get other)"
}

stats_warnings() { # 软执法黄灯：idle/status 时提示，不阻断（硬执法在 gate begin/stop）
  local b t limit
  b=$(stat_get bash); t=$(stat_get turns); limit="${AGENT_GUARD_SESSION_TURN_LIMIT:-50}"
  if [[ "${b:-0}" -gt 20 ]]; then
    emit "session-gate: YELLOW — bash calls ${b} > 20 this session (AGENTS.md 纪律 1/2 勘探预算)——合并检索或下放子代理，超标原因在 09「重要上下文」登记"
    report_add "- YELLOW: bash 调用 ${b} 次超勘探预算（20）——合并/下放，超标原因登记 09"
  fi
  if [[ "${t:-0}" -gt "$limit" ]]; then
    emit "session-gate: YELLOW — ${t} turns > ${limit} (§2.9.6)——handoff 换挡，gate begin 已拒开新变更"
    report_add "- YELLOW: 会话 ${t} 轮超 ${limit} 换挡线（§2.9.6）——handoff"
  fi
}

emit() { # 摘要进 stdout（Claude SessionStart 会把 stdout 注入上下文）+ 全文落盘
  printf '%s\n' "$1"
}

if [[ "$mode" == "count" ]]; then
  sub="${2:-}"
  case "$sub" in
    turn)
      [[ -s "$STATS_FILE" ]] || reset_state
      t=$(stat_get turns); t=$(( ${t:-0} + 1 ))
      b=$(stat_get bash); g=$(stat_get grep); o=$(stat_get other); tot=$(stat_get total)
      stat_write "$t" "${b:-0}" "${g:-0}" "${o:-0}" "${tot:-0}"
      water_write "$t"
      limit="${AGENT_GUARD_SESSION_TURN_LIMIT:-50}"
      if [[ "$t" -ge "$limit" && $(( (t - limit) % 10 )) -eq 0 ]]; then
        emit "session-gate: TURN LIMIT — ${t} turns >= ${limit} (§2.9.6)——handoff 换挡；gate begin 拒开新变更（AGENT_GUARD_ALLOW_OVER_WATER=1 豁免须登记 09）"
      fi
      ;;
    tool)
      name="${3:-}"
      if [[ "$name" == "-" ]]; then
        name=$(sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -1)
      fi
      lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
      [[ -s "$STATS_FILE" ]] || reset_state
      t=$(stat_get turns); b=$(stat_get bash); g=$(stat_get grep); o=$(stat_get other); tot=$(stat_get total)
      case "$lc" in
        bash) b=$(( ${b:-0} + 1 )) ;;
        grep) g=$(( ${g:-0} + 1 )) ;;
        *)    o=$(( ${o:-0} + 1 )) ;;
      esac
      stat_write "${t:-0}" "${b:-0}" "${g:-0}" "${o:-0}" "$(( ${tot:-0} + 1 ))"
      ;;
    *) echo "usage: scripts/session-gate.sh count turn|count tool <name|->" >&2; exit 2 ;;
  esac
  exit 0
fi

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
    # v3.39.0（CHG-042）：会话水位 + 勘探统计观测（§2.9.6 / AGENTS.md 纪律节）——只展示；执法在 gate begin
    if [[ -s "$STATS_FILE" ]]; then
      stats_line
      echo
      stats_warnings
    fi
    exit 0
    ;;
esac

report_init

if [[ "$mode" == "start" ]]; then
  reset_state
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
    # v3.43.0 (REQ-959): 缺陷发现入口——会话内信号交互三选项（软执法，fail-open）。
    # 主 Agent 须就红灯信号询问用户并按选择动态处置，不得静默跳过（忽略须 09 理由）。
    if [[ -x "scripts/bug-autointent" ]]; then
      emit "session-gate: 缺陷信号交互三选项（§2.17.2 v3.43.0）——①建骨架：scripts/bug-autointent --source audit-red --failing \"<失败项>\"；②登记 FU（P09 追加行）；③忽略（须 09「重要上下文」理由）"
    else
      emit "session-gate: 缺陷信号交互提示（降级）：bug-autointent 未安装——登记 FU 或在 09「重要上下文」登记忽略理由"
    fi
  else
    emit "session-gate: audit GREEN — $summary"
  fi
  {
    echo "## 审计输出（--only-fail）"
    echo '```'
    printf '%s\n' "$out"
    echo '```'
  } >> "$REPORT"

  # v3.34.0（CHG-034）：规则 10 自查表注入——活跃变更四主体互异在会话开始即可见
  # （执法点前移：防跑偏而非防事后）。只读展示，不阻断（start 永不 exit 非 0）。
  active_file=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  if [[ -n "$active_file" && -s "$active_file" ]]; then
    cid=$(tr -d '[:space:]' < "$active_file" 2>/dev/null || true)
    gov="docs/changes/$cid/00-governance.json"
    # 批次治理文件是纯 JSON（无 ## 锚点），按 change_id 字段匹配定位（终审[中]项修复）
    [[ -s "$gov" ]] || gov=$(grep -ls "\"change_id\"[[:space:]]*:[[:space:]]*\"$cid\"" docs/changes/BATCH-*/00-governance.json 2>/dev/null | head -1)
    if [[ -n "$gov" && -s "$gov" ]]; then
      jf() { sed -nE "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" <<<"$1" | head -1; }
      rec=$(tr -d '\n\r' < "$gov" | sed 's/}[[:space:]]*,[[:space:]]*{/}\n{/g' | grep "\"change_id\"[[:space:]]*:[[:space:]]*\"$cid\"" | head -1)
      sa=$(jf "$rec" spec_author); io=$(jf "$rec" implementation_owner)
      to=$(jf "$rec" test_owner);   ro=$(jf "$rec" review_owner)
      conflict=""
      [[ -n "$sa" && "$sa" == "$ro" ]] && conflict="$conflict spec_author=review_owner"
      [[ -n "$io" && "$io" == "$ro" ]] && conflict="$conflict implementation=review_owner"
      {
        echo "## 规则 10 自查表（v3.34.0）"
        echo "| 主体 | 标识 |"
        echo "|---|---|"
        echo "| spec_author（作者） | ${sa:-（未声明）} |"
        echo "| implementation_owner（实现） | ${io:-（未声明）} |"
        echo "| test_owner（测试） | ${to:-（未声明）} |"
        echo "| review_owner（评审） | ${ro:-（未声明）} |"
        echo ""
        echo "判定：$([[ -n "$conflict" ]] && echo "⚠ 冲突：$conflict —— 按 §2.1 规则 10 打回重派" || echo "互异达标（B 层仍需独立签署实质，标识互异≠独立性证明）")"
      } >> "$REPORT"
      if [[ -n "$conflict" ]]; then
        emit "session-gate: 规则 10 冲突 —$conflict（见 ${REPORT} 自查表）"
      fi
    fi
  fi
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

# v3.39.0（CHG-042）：勘探预算 + 换挡黄灯（软执法，idle 收尾可见；硬执法在 gate begin）
stats_warnings

exit 0
