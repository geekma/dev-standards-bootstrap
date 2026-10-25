#!/usr/bin/env bash
# session-gate.sh — 会话内执法（v3.28.0）：把门禁从"commit 时刻"左移到"会话内"。
#
# 根因（CHG-071/BUG-040~055 复盘）：执法链锚在 commit（pre-commit/CI），而 Agent
# 会话产物长期停留在工作区不提交 → pre-commit/CI 永不点火 → 六件套缺口、溯源缺口
# 无任何机器红灯。本脚本由客户端 Session Hook / Plugin 在**会话事件**里调用：
#   · 会话开始（start）→ 跑一次跨文档一致性审计，把存量红灯亮给本会话；
#   · 会话空闲/收尾（idle）→ 跑 agent-gate --stage stop 等价检查，把未闭环写进报告。
#
# 调用方（由 install-hook-adapter 按当前客户端自适应生成，本脚本不感知客户端；
# v3.64.0 起 opencode 适配为四段式：探测 runtime→实时检索官方文档→生成形状候选→
# 逐 runtime 沙箱真加载探测 + 本脚本功能标记仲裁，装毕对最终文件复验）：
#   claude  : .claude/settings.json SessionStart/Stop hook（stdout 注入会话上下文）
#   opencode: .opencode/plugins/dev-standards-gate.js（session.created / session.idle；dual-active 形状）
#   其他    : Git hooks + CI 兜底（校验仓库，不校验编辑器）
#
# 语义：start 永不阻断（exit 0），红灯 = 报告文件 + stdout 摘要；
#       idle 同样 exit 0（软执法 + 落盘报告）；硬阻断仍由 gate --stage stop（Claude
#       Stop hook）与 Git hooks 承担——本脚本只负责"让红灯被看见"。
#
# 【机制细节（唯一权威；v3.70.0 CHG-045 自 DS §2.9.6 形状移出，本块与
#   install-hook-adapter.sh 头注释同源互为镜像）】
#   · 遥测活性自检（v3.63.0，REQ-1037）：`status/idle` 校验 `session-tool-stats.json.updated_at`
#     新鲜度（窗口 `AGENT_GUARD_SESSION_TELEMETRY_STALE_MIN` 分钟，默认 30）与「已接线但零遥测」
#     两态，异常亮 YELLOW 失联提示——adapter 与客户端插件 API 漂移致静默失联
#     （2026-09 opencode 1.18.x 实证）由此可见化，软执法不阻断。
#   · adapter 兼容性基线（v3.63.0，REQ-1036；v3.64.0 契约发现替代静态映射，CHG-084）：
#     install-hook-adapter 生成物须匹配各客户端现行扩展协议；同机多 runtime 契约互斥实证
#     （opencode homebrew CLI 1.18.x 只认 `server()`、Desktop 内置 CLI 2.0.x 只执行 `setup()`
#     并 schema 拒 `server`-only default）证明「版本→形状静态映射」不可行——v3.64.0 起
#     opencode 适配为四段式契约发现（探测 runtime→实时检索官方文档→形状候选→逐 runtime
#     沙箱真加载仲裁 + session-gate 功能标记，fail-closed ADAPTER-E11/E12/E13），生成物为
#     dual-active 形状（各 runtime 各执行其一）；静态结构断言（ADAPTER-E09/E10，v3.63.0）
#     由真加载探测与遥测活性自检替代废止；cursor 按 hooks 文档事件名、gemini/codex 无仓级
#     hook 面只如实声明不变；协议核对时点与最低兼容版本随模板头注维护。
#   · 长任务等待/全量回归软执法（v3.73.0，CHG-096，REQ-1100/1102）：`count tool` 可携带
#     命令片段（cmd head）供两个独立计数器分类。抽取顺序：环境变量 DEV_STDARDS_CMD_HEAD
#     （插件注入面，值整体透传不进 shell 重解析，防引号注入）> argv 第 4 参 > stdin JSON
#     `tool_input.command`（仅 `count tool -` 读 stdin 的既有路径一次读出 tool_name 与
#     command）；片段抽首行、截 200 字符。
#     判定口径：①sleep_polls——片段首 token 匹配 `^[[:space:]]*sleep[[:space:]]+[0-9]`
#     才计数；`while ! 判据; do sleep 30; done` 形态首 token 为 while，天然豁免；
#     `bash -c 'sleep 5'` 包裹形态首 token 为 bash，不识别（已知边界，接受）。
#     ②full_suite——仅当仓库根 `.agent-governance.yml` 声明 `full_test_patterns`（逗号
#     分隔「锚定全量形态」ERE 列表，形状仿 smoke_paths，示例 `^<runner> test$`，按项目
#     测试命令方言声明）且片段命中任一 pattern 才计数；不声明=关闭（fail-open），非法
#     正则该条跳过不报错。两个计数器都要求片段非空（片段仅由 shell 类工具调用产生；
#     name-only 调用不计数）。
#     降级路径：harness 取不到命令片段时保持 name-only 计数（v3.39.0 现状行为）——遥测
#     退化为探索预算口径，sleep_polls/full_suite 两计数器停摆（软执法不阻塞，取不到
#     不算违规）。
#     阈值：AGENT_GUARD_SLEEP_POLL_LIMIT / AGENT_GUARD_FULL_TEST_LIMIT，默认均 2，
#     达阈值在 idle/status 亮 YELLOW 并要求 09「重要上下文」登记（硬执法仍在 gate 层）。
#   · edit/write 密度软执法（v3.77.0，CHG-101，REQ-1124/1127）：`count tool` 小写化
#     工具名含 `edit` 或 `write` 子串（Edit/Write/MultiEdit 命名族）计入 `edits`
#     （同步计入 other 总口径，既有读者不受影响）；阈值 AGENT_GUARD_EDIT_LIMIT 默认 40，
#     达阈值 idle/status 亮 YELLOW 要求 09 登记。name-only 降级路径同样可用（不依赖
#     cmd head）；旧 stats 文件缺 `edits` 键读 0（stat_get 既有兼容语义）。
#   · 编辑时刻硬拦 + 阶段感知谓词（v3.89.0，CHG-117，REQ-1199/1203，DES-1957/1961）：
#     `check` 模式在轮次超限判定后新增 edit/write 族谓词——hook 入参（stdin JSON 的
#     `tool_name` 与 `file_path|path|filePath|target_file` 字段，字段拼写面与 gate
#     extract_file_from_hook_input 同表）解析出目标路径后：先判无账（源码路径编辑且
#     无活跃变更、无当日缺陷组、AGENT_GUARD_ALLOW_UNACCOUNTED 未设 → exit 2，§2.17.2b
#     信号③三选项文案），后判阶段（AGENT_GUARD_STAGE_GATES≠0 时按路径映射：源码编辑
#     需 G-测试门（活跃变更 04 用例矩阵+TC 落点清单）或 bug 凭证（当日缺陷组骨架锚点
#     在场 + bugfix-log 登记行）；02/03 编辑需 G-规格门（该变更目录 01 REQ 表在位）；
#     04 编辑需 G-设计门（02+03+03.5 在位）；00-intent/00-governance/00.5/01、bugs 六件套
#     目录、模板与骨架路径不拦——流程动作本身）。hook 入参给绝对路径时按 git toplevel /
#     PWD 归一为仓库相对路径再判归属（Claude PreToolUse 契约），仓库外路径不归本仓治理；
#     取不到 hook 入参路径的客户端（如
#     opencode 插件未透传 tool_input）降级为不拦（与轮次检查同降级路径），由 staged/
#     audit 兜底——三层冗余。stdin 读取带上限（read -t 2），永不闭合的管道不挂死；
#     `AGENT_GUARD_CHECK_STDIN=0` 可整体关闭入参解析面。源码路径判定用
#     sg_is_code_path——与 agent-gate is_code_path 同表同源（两侧互钉同步义务，
#     gate 无法被 source：其顶层有 git 解析与目录副作用）。
#   · SKIP_VERIFY 收窄判定口径（v3.89.0，CHG-117，DES-1958）：idle 的 stop 等价调用
#     在 AGENT_GUARD_SKIP_VERIFY=1 之外只注入内部标记
#     AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle（仅本脚本→gate 的进程环境传递）；该标记
#     不构成任何豁免——gate 侧「无账源码改动」检查根本不消费 SKIP_VERIFY（豁免键
#     只有三个结构性豁免 + AGENT_GUARD_ALLOW_UNACCOUNTED），外部手工设置同值对也无
#     越权效果（防伪装：标记只声明语义，不是开关）。
#
# 零依赖：bash 3.2+、git；被调脚本缺失时降级为显式提示，不猜不编。
set -uo pipefail

mode="${1:-}"
  case "$mode" in
  start|idle|status|check|count) ;;
  *) echo "usage: scripts/session-gate.sh start|idle|status|check|count turn|count tool <name|-> [cmd-head]" >&2; exit 2 ;;
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
# message.updated（user role）/ message.part.updated，Cursor 走 beforeSubmitPrompt /
# postToolUse；无适配器的 harness 天然零开销跳过。
# gate begin 只读磁盘水位文件（§2.9.6），永不依赖客户端运行时。

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S; }

reset_state() {
  printf '{"turns":0,"bash":0,"grep":0,"other":0,"sleep_polls":0,"full_suite":0,"total":0,"edits":0,"updated_at":"%s"}\n' "$(now_iso)" > "$STATS_FILE"
  printf '{"turns":0,"session":"","updated_at":"%s"}\n' "$(now_iso)" > "$WATER_FILE"
  # v3.63.0（REQ-1033，DES-1822）：会话起点标记——agent-gate begin 的 GATE-E89
  # 以「交付时刻晚于本会话起点」判定同会话交付后未换挡；新会话 start 重置起点后放行。
  printf '{"started_at":"%s"}\n' "$(now_iso)" > "${STATE_DIR}/session-started.json"
}

stat_get() { # <key> — 缺键（旧格式 stats 文件，CHG-096 前schema）读数默认 0（向后兼容）
  local v
  v=$(sed -n "s/.*\"$1\":[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$STATS_FILE" 2>/dev/null | head -1)
  printf '%s' "${v:-0}"
}

stat_write() { # turns bash grep other sleep_polls full_suite total edits
  printf '{"turns":%s,"bash":%s,"grep":%s,"other":%s,"sleep_polls":%s,"full_suite":%s,"total":%s,"edits":%s,"updated_at":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$(now_iso)" > "$STATS_FILE"
}

water_write() { # <turns>
  printf '{"turns":%s,"session":"","updated_at":"%s"}\n' "$1" "$(now_iso)" > "$WATER_FILE"
}

# v3.73.0（CHG-096，REQ-1102）：仓库根 .agent-governance.yml 声明的「锚定全量形态」
# ERE 列表（flat key `full_test_patterns`，逗号分隔，形状仿 smoke_paths）。
# 不声明=关闭（fail-open，返回非零）；机制细则唯一权威=本文件头注释。
gov_full_test_patterns() {
  [[ -f .agent-governance.yml ]] || return 1
  sed -nE 's/^[[:space:]]*full_test_patterns:[[:space:]]*([^#]*).*$/\1/p' .agent-governance.yml 2>/dev/null | head -1
}

full_suite_hit() { # <cmd_head> — 命中任一声明 pattern 即 0；非法正则该条跳过（fail-open 不报错）
  local pats p
  pats=$(gov_full_test_patterns) || return 1
  [[ -n "$pats" ]] || return 1
  IFS=',' read -r -a __ftp <<< "$pats" || true
  for p in "${__ftp[@]}"; do
    p="${p#"${p%%[![:space:]]*}"}"   # ltrim（只去首尾空白；pattern 内部空格是语义，保留）
    p="${p%"${p##*[![:space:]]}"}"   # rtrim
    [[ -n "$p" ]] || continue
    if printf '%s' "$1" | grep -Eq -- "$p" 2>/dev/null; then return 0; fi
  done
  return 1
}

stats_line() {
  printf 'session-gate: session stats — turns %s, bash %s, grep %s, other %s (resource discipline baseline: bash <= 20)' \
    "$(stat_get turns)" "$(stat_get bash)" "$(stat_get grep)" "$(stat_get other)"
}

# v3.76.0 (CHG-100, REQ-1117): 验证通道状态行——读 agent-gate stop 落盘的最近一次
# 判定（.agent-state/verify-channel.json）。缺档显式"未记录"，绝不猜："没配"与
# "被跳过"必须可区分（另一仓"验证从未真正跑过却无痕"的规范侧根因）。
# 字段序固定（gate 写入端唯一权威）：state/source/command/exit_code/reason/...
channel_line() {
  local f="$STATE_DIR/verify-channel.json" st src cmd reason
  if [[ ! -s "$f" ]]; then
    printf -- '- 验证通道：未记录（本会话尚未跑到 stop 判定；可用 scripts/agent-gate verify-channel 现测）\n'
    return 0
  fi
  st=$(sed -n 's/.*"state":"\([^"]*\)".*/\1/p' "$f" | head -1)
  src=$(sed -n 's/.*"source":"\([^"]*\)".*/\1/p' "$f" | head -1)
  cmd=$(sed -n 's/.*"command":"\(.*\)","exit_code".*/\1/p' "$f" | head -1)
  reason=$(sed -n 's/.*"reason":"\(.*\)","env_fingerprint".*/\1/p' "$f" | head -1)
  if [[ -n "$cmd" ]]; then
    printf -- '- 验证通道：%s（source=%s，command=%s）\n' "${st:-unknown}" "${src:--}" "$cmd"
  else
    printf -- '- 验证通道：%s（source=%s，%s）\n' "${st:-unknown}" "${src:--}" "${reason:-无原因记录}"
  fi
}

iso_to_epoch() { # <iso8601Z> — GNU date -d first, BSD date -j -f fallback, 0 on failure
  local s="$1"
  if date -u -d "$s" +%s >/dev/null 2>&1; then
    date -u -d "$s" +%s
  else
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null || echo 0
  fi
}

telemetry_liveness() { # v3.63.0（REQ-1037，DES-1825）：事件源活性自检（软执法 YELLOW）
  # 背景（REQ-1036 实证）：adapter 生成物与客户端插件 API 漂移时，插件在客户端启动
  # 时加载失败（仅服务器日志 WARN），事件源归零、三层防线静默降级。本检查把"死了"
  # 从不可见日志提升为 agent 可见信号。窗口 AGENT_GUARD_SESSION_TELEMETRY_STALE_MIN
  # （分钟，默认 30）可调；只提示不阻断（fail-open）。
  local now ts age stale stale_min
  stale_min="${AGENT_GUARD_SESSION_TELEMETRY_STALE_MIN:-30}"
  [[ "$stale_min" =~ ^[0-9]+$ ]] || stale_min=30
  stale=$(( stale_min * 60 ))
  now=$(date -u +%s)
  if [[ -s "$STATS_FILE" ]]; then
    ts=$(sed -n 's/.*"updated_at":"\([^"]*\)".*/\1/p' "$STATS_FILE" | head -1)
    age=$(( now - $(iso_to_epoch "${ts:-}") ))
    if [[ $age -gt $stale ]]; then
      emit "session-gate: YELLOW — telemetry stale ($(( age / 60 ))min > ${stale_min}min): event source likely NOT loaded (client plugin schema drift?) — check client logs for 'failed to load plugin'; enforcement degraded to Git hooks + CI"
    fi
  elif [[ -d .opencode/plugins || -f .claude/settings.json || -f .cursor/hooks.json ]]; then
    emit "session-gate: YELLOW — adapter wiring present but zero telemetry: plugin/hook not firing (client did not load it?) — check client logs for 'failed to load plugin' / hook errors"
  fi
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
  # v3.73.0（CHG-096，REQ-1100/1102）：长任务等待 + 全量回归两盏黄灯（软执法）
  local sp fs slimit flimit
  sp=$(stat_get sleep_polls); fs=$(stat_get full_suite)
  slimit="${AGENT_GUARD_SLEEP_POLL_LIMIT:-2}"; flimit="${AGENT_GUARD_FULL_TEST_LIMIT:-2}"
  case "$slimit" in ''|*[!0-9]*) slimit=2 ;; esac
  case "$flimit" in ''|*[!0-9]*) flimit=2 ;; esac
  if [[ "$sp" -ge "$slimit" ]]; then
    emit "session-gate: YELLOW — sleep-poll calls ${sp} >= ${slimit} (AGENTS.md 纪律 10 长任务等待)——改用前台 timeout / while 单调用 / 后台通知三式之一，等待原因在 09「重要上下文」登记"
    report_add "- YELLOW: sleep 轮询 ${sp} 次达阈值 ${slimit}（长任务等待纪律）——合法三式改写，原因登记 09"
  fi
  if [[ "$fs" -ge "$flimit" ]]; then
    emit "session-gate: YELLOW — full-suite runs ${fs} >= ${flimit} (AGENTS.md 纪律 7 定向验证/全量回归)——模块/单测级验证先行，全量回归交门禁触发，直跑原因在 09「重要上下文」登记"
    report_add "- YELLOW: 全量回归直跑 ${fs} 次达阈值 ${flimit}（定向验证/全量回归）——原因登记 09"
  fi
  # v3.77.0（CHG-101，REQ-1124/1127）：edit/write 族密度黄灯（软执法）——小步高频
  # 读写同一形态 = 请求数 × 上下文水位乘数失控；提示合并批量，不阻断。
  local e elimit
  e=$(stat_get edits)
  elimit="${AGENT_GUARD_EDIT_LIMIT:-40}"
  case "$elimit" in ''|*[!0-9]*) elimit=40 ;; esac
  if [[ "${e:-0}" -ge "$elimit" ]]; then
    emit "session-gate: YELLOW — edit/write calls ${e} >= ${elimit} (AGENTS.md 纪律 12 调用批处理)——同文件多段合并一次 edit、独立命令 && 合并/并行，超标原因在 09「重要上下文」登记"
    report_add "- YELLOW: edit/write 调用 ${e} 次达阈值 ${elimit}（调用批处理）——合并批量，原因登记 09"
  fi
}

emit() { # 摘要进 stdout（Claude SessionStart 会把 stdout 注入上下文）+ 全文落盘
  printf '%s\n' "$1"
}

# v3.89.0（CHG-117，DES-1957/1961）：路径根解析 + 源码路径判定。
# sg_cfg_path 与 agent-gate cfg_path 同规则（env > .agent-governance.yml paths.* > 默认）。
sg_cfg_path() { # <key> <default>
  local v=""
  if [[ -f .agent-governance.yml ]]; then
    v=$(sed -nE "s/^[[:space:]]*$1:[[:space:]]*([^#]*).*$/\1/p" .agent-governance.yml 2>/dev/null \
        | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$v" ]] || v="$2"
  printf '%s' "$v"
}
sg_re_escape() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
DOCS_ROOT="${AGENT_GUARD_DOCS_DIR:-$(sg_cfg_path docs docs)}"
SCRIPTS_ROOT="${AGENT_GUARD_SCRIPTS_DIR:-$(sg_cfg_path scripts scripts)}"
TESTS_ROOT="${AGENT_GUARD_TESTS_DIR:-$(sg_cfg_path tests tests)}"
GITHOOKS_ROOT="${AGENT_GUARD_GITHOOKS_DIR:-$(sg_cfg_path githooks .githooks)}"
CHANGE_ROOT="${AGENT_GUARD_CHANGE_ROOT:-$(sg_cfg_path change_root "$DOCS_ROOT/changes")}"
BUGS_ROOT="${AGENT_GUARD_BUGS_ROOT:-$(sg_cfg_path bugs_root "$DOCS_ROOT/bugs")}"
DOCS_RE=$(sg_re_escape "$DOCS_ROOT"); SCRIPTS_RE=$(sg_re_escape "$SCRIPTS_ROOT")
TESTS_RE=$(sg_re_escape "$TESTS_ROOT"); GITHOOKS_RE=$(sg_re_escape "$GITHOOKS_ROOT")
CHANGE_ROOT_RE=$(sg_re_escape "$CHANGE_ROOT")

sg_is_code_path() { # <path>
  # session-gate 本地副本——与 scripts/agent-gate 的 is_code_path **同表同源**：
  # 同步义务互钉（两处各留注释；gate 不能被 source——其顶层有 git 解析与目录解析副作用）。
  # 改任一侧的排除面/扩展名表，必须同步另一侧与 tests/audit-docs-consistency.sh 的 G16 副本。
  local p="$1"
  [[ "$p" =~ ^(${DOCS_RE}/|\.github/|\.agent-governance/|README|AGENTS\.md|CLAUDE\.md|GEMINI\.md) ]] && return 1
  [[ "$p" =~ ^(${GITHOOKS_RE}/|\.claude/|\.cursor/|\.gemini/|\.opencode/|\.agent-state/|\.agent-governance\.yml$|${SCRIPTS_RE}/agent-gate$|${SCRIPTS_RE}/session-gate\.sh$|${SCRIPTS_RE}/install-hook-adapter$|${SCRIPTS_RE}/check-standards-compliance\.sh$|${SCRIPTS_RE}/stamp-provenance\.sh$|${SCRIPTS_RE}/generate-reading-pack\.sh$|${SCRIPTS_RE}/behavior-extract\.sh$|${SCRIPTS_RE}/lib-suite-tree-fingerprint\.sh$|${SCRIPTS_RE}/lib-suite-lock\.sh$|${TESTS_RE}/run-tests\.sh$|${TESTS_RE}/audit-docs-consistency\.sh$) ]] && return 1
  [[ "$p" =~ \.(c|cc|cpp|cs|go|java|js|jsx|kt|kts|php|py|rb|rs|scala|sh|sql|swift|ts|tsx|vue)$ ]]
}

# v3.89.0（CHG-117）：hook 入参路径归一化。Claude PreToolUse 的 tool_input.file_path
# 是**绝对路径**，而 sg_is_code_path / CHANGE_ROOT 前缀判定按仓库相对路径设计——
# 不归一则 02/03/04 阶段谓词永不命中（静默假绿）。按 git toplevel（含符号链接的物理
# 路径兜底）或 PWD 剥前缀；仓库外路径原样返回，由调用方降级不拦。
sg_repo_relative() { # <path> -> repo-relative when inside the worktree, unchanged otherwise
  local p="$1" root rp rr
  p="${p#./}"
  [[ "$p" == /* ]] || { printf '%s' "$p"; return 0; }
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$root" ]]; then
    case "$p" in
      "$root"/*) printf '%s' "${p#"$root"/}"; return 0 ;;
    esac
    # macOS /var → /private/var 类符号链接：hook 与 git 可能各自给出物理/逻辑路径
    rp=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) || rp=""
    rr=$(cd "$root" 2>/dev/null && pwd -P) || rr=""
    if [[ -n "$rp" && -n "$rr" ]]; then
      case "$rp" in
        "$rr") printf '%s' "${p##*/}"; return 0 ;;
        "$rr"/*) printf '%s' "${rp#"$rr"/}/${p##*/}"; return 0 ;;
      esac
    fi
  fi
  if [[ -n "${PWD:-}" ]]; then
    case "$p" in "$PWD"/*) printf '%s' "${p#"$PWD"/}"; return 0 ;; esac
  fi
  printf '%s' "$p"
}

if [[ "$mode" == "count" ]]; then
  sub="${2:-}"
  case "$sub" in
    turn)
      [[ -s "$STATS_FILE" ]] || reset_state
      t=$(stat_get turns); t=$(( ${t:-0} + 1 ))
      b=$(stat_get bash); g=$(stat_get grep); o=$(stat_get other)
      sp=$(stat_get sleep_polls); fs=$(stat_get full_suite); tot=$(stat_get total); e=$(stat_get edits)
      stat_write "$t" "${b:-0}" "${g:-0}" "${o:-0}" "${sp:-0}" "${fs:-0}" "${tot:-0}" "${e:-0}"
      water_write "$t"
      limit="${AGENT_GUARD_SESSION_TURN_LIMIT:-50}"
      if [[ "$t" -ge "$limit" && $(( (t - limit) % 10 )) -eq 0 ]]; then
        emit "session-gate: TURN LIMIT — ${t} turns >= ${limit} (§2.9.6)——handoff 换挡；gate begin 拒开新变更（AGENT_GUARD_ALLOW_OVER_WATER=1 豁免须登记 09）"
      fi
      ;;
    tool)
      name="${3:-}"
      cmd_head="${4:-}"
      # v3.73.0（CHG-096，REQ-1100/1102）：命令片段抽取顺序——env DEV_STDARDS_CMD_HEAD
      # （插件注入面，值整体透传）> argv 第 4 参 > stdin JSON tool_input.command（仅
      # `count tool -` 既有读 stdin 路径；一次读出 tool_name 与 command）。抽首行、
      # 截 200 字符；取不到=name-only 降级（两计数器停摆）。细则唯一权威=头注释。
      cmd_head="${DEV_STDARDS_CMD_HEAD:-$cmd_head}"
      if [[ "$name" == "-" ]]; then
        stdin_json=$(cat 2>/dev/null || true)
        name=$(printf '%s' "$stdin_json" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        if [[ -z "$cmd_head" ]]; then
          cmd_head=$(printf '%s' "$stdin_json" | sed -n 's/.*"tool_input"[[:space:]]*:[[:space:]]*{.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        fi
      fi
      cmd_head=$(printf '%s' "$cmd_head" | head -1 | cut -c1-200)
      lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
      [[ -s "$STATS_FILE" ]] || reset_state
      t=$(stat_get turns); b=$(stat_get bash); g=$(stat_get grep); o=$(stat_get other)
      sp=$(stat_get sleep_polls); fs=$(stat_get full_suite); tot=$(stat_get total); e=$(stat_get edits)
      case "$lc" in
        bash) b=$(( ${b:-0} + 1 )) ;;
        grep) g=$(( ${g:-0} + 1 )) ;;
        *edit*|*write*) e=$(( ${e:-0} + 1 )); o=$(( ${o:-0} + 1 )) ;;
        *)    o=$(( ${o:-0} + 1 )) ;;
      esac
      if [[ -n "$cmd_head" ]]; then
        if printf '%s' "$cmd_head" | grep -Eq '^[[:space:]]*sleep[[:space:]]+[0-9]'; then
          sp=$(( ${sp:-0} + 1 ))
        fi
        if full_suite_hit "$cmd_head"; then
          fs=$(( ${fs:-0} + 1 ))
        fi
      fi
      stat_write "${t:-0}" "${b:-0}" "${g:-0}" "${o:-0}" "${sp:-0}" "${fs:-0}" "$(( ${tot:-0} + 1 ))" "${e:-0}"
      ;;
    *) echo "usage: scripts/session-gate.sh count turn|count tool <name|-> [cmd-head]" >&2; exit 2 ;;
  esac
  exit 0
fi

if [[ "$mode" == "check" ]]; then
  # v3.58.0 (REQ-1008): tool-level handoff hard stop, called by PreToolUse /
  # tool.execute.before adapters (install-hook-adapter). Fail-closed only when
  # a water file exists AND turns >= limit — uninstalled repos and fresh
  # sessions are never blocked (exit 0). Override: AGENT_GUARD_SESSION_TURN_LIMIT.
  # v3.63.0 (REQ-1035, D): `-ge` 口径为两处统一基线——check（此处）与 gate begin
  # E74 均在 turn == limit 时拦截（旧 begin 侧 `-gt` 放行第 50 轮整，已修）。
  if [[ -s "$WATER_FILE" ]]; then
    t=$(sed -nE 's/.*"turns"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$WATER_FILE" | head -1)
    limit="${AGENT_GUARD_SESSION_TURN_LIMIT:-50}"
    if [[ "${t:-0}" -ge "$limit" ]]; then
      echo "session-gate: HARD STOP — ${t} turns >= ${limit} (§2.9.6): run /handoff, write the handoff doc, continue in a new session; AGENT_GUARD_SESSION_TURN_LIMIT=<n> re-arms (justification goes in 09 重要上下文)." >&2
      exit 2
    fi
  fi
  # v3.89.0 (CHG-117, REQ-1199/1203, DES-1957/1961): edit-time hard stop.
  # 判定口径唯一权威 = 本文件头注释「编辑时刻硬拦」块；这里只落实现。
  sg_edit_predicate() {
    # 仅 edit/write 族工具参与（纪律 12 命名族口径，与 count tool 同源）
    local lc
    lc=$(printf '%s' "${SG_TOOL:-}" | tr '[:upper:]' '[:lower:]')
    case "$lc" in *edit*|*write*) ;; *) return 0 ;;
    esac
    [[ -n "${SG_FILE:-}" ]] || return 0   # 取不到路径 = 降级不拦（三层冗余兜底）
    # 绝对路径归一（见 sg_repo_relative 头注）；仓库外路径不归本仓治理
    SG_FILE=$(sg_repo_relative "$SG_FILE")
    [[ "$SG_FILE" != /* ]] || return 0
    # 流程动作本身永不拦：00-intent / 00-governance / 00.5 / 01-spec、bugs 根下、
    # 目标仓入口模板目录（<docs>/templates/ —— new-change 骨架生成面）
    case "$SG_FILE" in
      */00-intent.md|*/00-governance.json|*/00.5-communication.md|*/01-spec.md) return 0 ;;
      "$BUGS_ROOT"/*|"$DOCS_ROOT"/templates/*) return 0 ;;
    esac
    # 路径归属：变更产物 02/03/04 面或源码面
    local cid sgdir
    if [[ "$SG_FILE" =~ ^${CHANGE_ROOT_RE}/([^/]+)/ ]] && printf '%s' "${SG_FILE##*/}" | grep -qE '^(02|03|04)-'; then
      # 02/03/04 阶段谓词（REQ-1203）：AGENT_GUARD_STAGE_GATES=0 时整体跳过——
      # 仅源码面保留无账判定（REQ-1199 语义），文档产物面回归放行
      [[ "${AGENT_GUARD_STAGE_GATES:-1}" == "0" ]] && return 0
      cid="${BASH_REMATCH[1]}"
      sgdir="$CHANGE_ROOT/$cid"
      case "$SG_FILE" in
        */02-*|*/03-*)
          # G-规格门：该变更目录 01 REQ 表在位
          if [[ ! -s "$sgdir/01-spec.md" ]] || ! grep -qE 'REQ-[0-9]+' "$sgdir/01-spec.md" 2>/dev/null; then
            echo "session-gate: HARD STOP — 编辑 $SG_FILE 缺 G-规格门（docs/changes/$cid/01-spec.md 的 REQ 表在位即放行）；补 01-spec REQ-xxx 行后重试，或 AGENT_GUARD_STAGE_GATES=0 关闭阶段谓词层（理由登记 09）(standards §2.16.2/§2.17, v3.89.0 CHG-117)" >&2
            exit 2
          fi ;;
        */04-*)
          # G-设计门：该变更目录 02（三维+回滚）+03（选型/范式）+03.5（任务拆解）在位
          design_gate=1
          [[ -s "$sgdir/02-code-impact-analysis.md" ]] || design_gate=0
          [[ -s "$sgdir/03-modification-plan.md" ]] || design_gate=0
          [[ -s "$sgdir/03.5-tasks.md" ]] || design_gate=0
          if [[ "$design_gate" != 1 ]]; then
            echo "session-gate: HARD STOP — 编辑 $SG_FILE 缺 G-设计门（docs/changes/$cid/ 02 三维影响+回滚、03 选型比较+既有范式关系 与 03.5 任务拆解 在位即放行）；补产物后重试，或 AGENT_GUARD_STAGE_GATES=0 关闭阶段谓词层（理由登记 09）(standards §2.16.2/§2.17, v3.89.0 CHG-117)" >&2
            exit 2
          fi ;;
      esac
      return 0
    fi
    # 源码面（sg_is_code_path 同表同源，gate is_code_path 互钉）
    sg_is_code_path "$SG_FILE" || return 0   # 非源码非产物 = 不拦（docs-only 天然豁免）
    # 无账判定（REQ-1199，先于阶段判定）：无活跃变更 + 无当日缺陷组 + 未豁免 → 硬拦
    local af paid=0
    af=$(git rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
    [[ -n "$af" && -s "$af" ]] && paid=1
    [[ -d "$BUGS_ROOT/BATCH-$(date -u +%Y%m%d)" ]] && paid=1
    if [[ "$paid" != 1 ]]; then
      if [[ "${AGENT_GUARD_ALLOW_UNACCOUNTED:-}" == "1" ]]; then
        return 0   # 豁免不静默：staged/stop 的 GATE-E125BYPASS 台账承接（此处无台账写面，不重复）
      fi
      echo "session-gate: HARD STOP — 编辑/写入源码路径 $SG_FILE 但无活跃变更、无当日缺陷组（§2.17.2b 信号③三选项）：①建骨架 scripts/agent-gate begin <变更号>（或 new-change）；②缺陷走当日组 docs/bugs/BATCH-<UTC日>/（bug-autointent）；③忽略须 09「重要上下文」登记理由（AGENT_GUARD_ALLOW_UNACCOUNTED=1 仅显式豁免用）(v3.89.0 CHG-117)" >&2
      exit 2
    fi
    # 阶段判定（REQ-1203）：AGENT_GUARD_STAGE_GATES=0 时整体跳过，仅剩无账判定
    [[ "${AGENT_GUARD_STAGE_GATES:-1}" == "0" ]] && return 0
    if [[ "$paid" == 1 && -n "$af" && -s "$af" ]]; then
      # 活跃变更在场：G-测试门（04 用例矩阵 + TC 落点清单在位）
      local id d04 ok4=1
      id=$(tr -d '[:space:]' < "$af" 2>/dev/null || true)
      d04="$CHANGE_ROOT/$id/04-test-scripts.md"
      [[ -s "$d04" ]] || ok4=0
      [[ "$ok4" == 1 ]] && { grep -qE 'TC-[0-9]+' "$d04" 2>/dev/null || ok4=0; }
      [[ "$ok4" == 1 ]] && { grep -q '^## TC 落点清单' "$d04" 2>/dev/null || ok4=0; }
      if [[ "$ok4" != 1 ]]; then
        echo "session-gate: HARD STOP — 源码编辑缺 G-测试门（docs/changes/$id/04-test-scripts.md 用例矩阵 TC-xxx + 覆盖维度 与 「TC 落点清单」节在位即放行）；先过 agent-gate --stage testplan，或 AGENT_GUARD_STAGE_GATES=0 关闭阶段谓词层（理由登记 09）(standards §2.16.2/§2.17, v3.89.0 CHG-117)" >&2
        exit 2
      fi
      return 0
    fi
    # 当日缺陷组在场（无活跃变更）：bug 凭证 = 组骨架锚点 + bugfix-log 登记行
    local bd bid cred=0
    bd="$BUGS_ROOT/BATCH-$(date -u +%Y%m%d)/01-diagnosis.md"
    if [[ -s "$bd" ]]; then
      while IFS= read -r bid; do
        [[ -n "$bid" ]] || continue
        if [[ -s "$DOCS_ROOT/bugfix-log.md" ]] && grep -qE "^### ${bid}([[:space:]]|：|:|$)" "$DOCS_ROOT/bugfix-log.md" 2>/dev/null; then
          cred=1; break
        fi
      done < <(grep -ohE '^##[[:space:]]+BUG-[0-9A-Za-z_-]+' "$bd" 2>/dev/null | awk '{print $2}')
    fi
    if [[ "$cred" != 1 ]]; then
      echo "session-gate: HARD STOP — 源码编辑缺 bug 凭证（当日缺陷组 01-diagnosis 骨架锚点 + docs/bugfix-log.md 「### BUG-xxx」登记行在位即放行；或补全后重试）(standards §2.17.2b/§2.5 阶段 6, v3.89.0 CHG-117)" >&2
      exit 2
    fi
    return 0
  }
  if [[ "${AGENT_GUARD_CHECK_STDIN:-1}" == "1" ]] && [[ ! -t 0 ]]; then
    # 有界读取：适配器入参是有限 JSON 块，EOF 即回；永不闭合的管道 2s 超时放弃
    #（降级=不拦）。末段无换行（printf 型 JSON、heredoc 差异）也要并入——read 以
    # EOF 退出时残留值必须补收，否则整块入参被静默丢弃=降级假绿。取字段拼写面与
    # gate extract_file_from_hook_input 同表。
    SG_INPUT=""
    sg_ln=""
    while IFS= read -r -t 2 sg_ln; do
      SG_INPUT+="$sg_ln"$'\n'
      sg_ln=""
    done
    [[ -n "$sg_ln" ]] && SG_INPUT+="$sg_ln"
    SG_TOOL=$(printf '%s' "$SG_INPUT" | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
    SG_FILE=$(printf '%s' "$SG_INPUT" | sed -nE 's/.*"(file_path|path|filePath|target_file)"[[:space:]]*:[[:space:]]*"([^"\\]+)".*/\2/p' | head -1)
    sg_edit_predicate
  fi
  exit 0
fi

report_init() {
  {
    echo "# session-gate 报告 (${mode} @ $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown))"
    echo
  } > "$REPORT"
  # 探针关联标记（CHG-084 评审 A5）：install-hook-adapter 真加载终验注入 AGENT_GUARD_SESSION_TAG；
  # 该变量存在=本次 start 由安装探针触发，写入报告作为确定性功能证据（mtime 判据可被同仓其他
  # 活跃会话的 hook 写入污染）。日常会话无此变量，行为不变。
  if [[ -n "${AGENT_GUARD_SESSION_TAG:-}" ]]; then
    printf 'probe-tag: %s\n' "$AGENT_GUARD_SESSION_TAG" >> "$REPORT"
  fi
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
    # v3.76.0 (CHG-100, REQ-1117)：验证通道状态（四态可见化）
    channel_line
    # v3.39.0（CHG-042）：会话水位 + 勘探统计观测（§2.9.6 / AGENTS.md 纪律节）——只展示；执法在 gate begin
    if [[ -s "$STATS_FILE" ]]; then
      stats_line
      echo
      stats_warnings
    fi
    # v3.63.0（REQ-1037）：遥测活性自检——插件静默失联可见化（软执法）
    telemetry_liveness
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
  # v3.89.0（CHG-117，DES-1958）：追加内部标记 AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle
  # （仅本调用链注入）。判定口径见头注释「SKIP_VERIFY 收窄判定口径」：gate 的
  # 无账源码改动检查不消费 SKIP_VERIFY，无账照跑照红；标记只声明语义不构成豁免，
  # 外部手工设置同值对无越权效果。
  out=$(AGENT_GUARD_SKIP_VERIFY=1 AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle bash "$GATE" --stage stop 2>&1 | tail -40); rc=$?
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
# v3.63.0（REQ-1037）：遥测活性自检（软执法，idle 收尾可见）
telemetry_liveness

exit 0
