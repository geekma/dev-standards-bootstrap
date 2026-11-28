#!/usr/bin/env bash
# install-hook-adapter.sh — 按目标仓当前 Agent 环境自适应生成会话内执法接线（v3.28.0）。
#
# 设计原则（"不写死"）：
#   · 客户端是**探测**出来的，不是假设的：env 变量 / CLI on PATH / 仓库内配置目录
#     三路证据，命中即安装，多个全装（一台机器多个客户端是常态）。
#   · 每个 client 一个 adapter 函数，schema 差异全部封装在各自函数里；
#     scripts/agent-gate 与 scripts/session-gate.sh 是唯一校验逻辑，客户端只做接线。
#   · 生成后**必须验证**（JSON 可解析 / JS 可通过语法检查 / hook 脚本 bash -n），
#     验证不过即报错退出——"生成了"不等于"接上了"。
#   · 已有用户配置**永不静默覆盖**：claude 走 JSON 合并（幂等去重），静态 schema
#     走 diff + --force；opencode 插件是生成物（文件头声明），重装即整体重写。
#   · 无 hook 能力的客户端（如 codex）不造假接线：如实说明由 Git hooks + CI 兜底
#     （它们校验仓库本身，不依赖编辑器）。
#
# 【机制细节（唯一权威；v3.70.0 CHG-045 自 DS §2.9.6 形状移出，本块与
#   session-gate.sh 头注释同源互为镜像）】
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
#   · 长任务等待/全量回归软执法（v3.73.0，CHG-096，REQ-1100/1102）：opencode 插件
#     message.part.updated 从 `part.state.input` 取命令片段（候选键 command|cmd|script，
#     string 非空才取，抽首行截 200 字符），经 DEV_STDARDS_CMD_HEAD 环境变量传给
#     `count tool`（bun `$` 插值整体透传防注入 / execFile env 选项无 shell 面）；取不到
#     传空=name-only 降级（两计数器停摆，现状行为）。Claude/cursor hook 走 stdin JSON
#     `tool_input.command` 无需 adapter 改动；判定口径/阈值唯一权威=session-gate.sh 头注释。
set -euo pipefail
case "${AGENT_GUARD_FORCE_OS:-$(uname -s 2>/dev/null || echo unknown)}" in
  MINGW*|MSYS*|CYGWIN*) export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' ;;
esac

is_windows_shell() {
  case "${AGENT_GUARD_FORCE_OS:-$(uname -s 2>/dev/null || echo unknown)}" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

has_real_python3() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1
}

resolve_hook_bash() {
  if ! is_windows_shell; then
    printf 'bash'
    return 0
  fi
  if [[ -n "${DEV_STANDARDS_HOOK_BASH:-}" && -x "${DEV_STANDARDS_HOOK_BASH}" ]]; then
    printf '%s' "$DEV_STANDARDS_HOOK_BASH"
    return 0
  fi
  if [[ -x /usr/bin/bash ]]; then
    printf '/usr/bin/bash'
    return 0
  fi
  local p b
  local IFS=':'
  for p in ${PATH:-}; do
    [[ -n "$p" ]] || continue
    case "$p" in
      *System32*|*system32*|*WindowsApps*) continue ;;
    esac
    for b in "$p/bash.exe" "$p/bash"; do
      if [[ -x "$b" ]]; then
        printf '%s' "$b"
        return 0
      fi
    done
  done
  printf 'bash'
}

resolve_hook_cmd_prefix() {
  is_windows_shell || return 0
  local hook_bash
  hook_bash="$(resolve_hook_bash)"
  if [[ "$hook_bash" == *" "* ]]; then
    printf 'MSYS_NO_PATHCONV=1 "%s" ' "$hook_bash"
  else
    printf 'MSYS_NO_PATHCONV=1 %s ' "$hook_bash"
  fi
}

usage() {
  cat <<'EOF'
Usage: install-hook-adapter.sh [--detect | --client <name>] [--force] [--all] [--offline] [--reprobe]

Detects the AI coding clients present in this environment/repo and writes the
session-enforcement wiring for each:

  claude    .claude/settings.json          JSON-merge: SessionStart(session-gate start)
                                           + UserPromptSubmit/PostToolUse(count) + PreToolUse(check)
                                           + PreToolUse(agent-gate pre-write) + Stop(stop)
  opencode  .opencode/plugins/dev-standards-gate.js
            .opencode/command/gate-check.md
                                            four-stage wiring (v3.64.0, CHG-084):
                                            (1) detect runtimes (PATH CLI + Desktop
                                            bundled CLI, --version each) ->
                                            (2) fetch official plugin docs live
                                            (source URL recorded; --offline skips) ->
                                            (3) generate shape candidates ->
                                            (4) per-runtime sandbox real-load probes
                                            (client "failed to load plugin" line +
                                            session-gate.sh functional marker
                                            arbitrate) + final-file verification.
                                            Fail-closed: no verified contract, no
                                            file (ADAPTER-E11/E12). Shape is never
                                            hardcoded.
  cursor    .cursor/hooks.json             sessionStart + beforeSubmitPrompt(count turn)
                                           + postToolUse(count tool) + preToolUse(pre-write+check)
                                           + stop  (shape per cursor hooks docs — cursor.com/docs/agent/hooks:
                                           sessionStart/beforeSubmitPrompt/postToolUse/preToolUse/stop; verified 2026-09)
  gemini    (no repo-scoped hook surface)  note only: Git hooks + CI are the
                                           enforcement line
  codex     (no repo-scoped hook surface)  note only: Git hooks + CI are the
                                           enforcement line

Flags:
  --detect                 print the detection matrix and exit
  --print-contract         print the client-agnostic 3-event hook contract (for dynamic Agent wiring)
  --print-global-contract  print the user-level cross-workspace router hook contract
  --verify-wiring <path>   verify a dynamically generated hook config and record runtime.json
  --client <name>          force-install for one client (claude|opencode|cursor|gemini|codex)
  --all                    install for every detected client (default when no --client)
  --offline                skip network doc fetches during opencode probing (or AGENT_GUARD_OFFLINE=1)
  --reprobe                ignore cached opencode arbitration result and force fresh probes (or AGENT_GUARD_REPROBE=1)
  --force                  overwrite existing static-schema configs that differ (diff is shown)
EOF
}

print_contract() {
  cat <<'EOF'
{
  "contract_version": "1",
  "principle": "Capability-driven dynamic wiring (v4.5.0, CHG-149): the running Agent inspects its own client hook docs/schema at install, upgrade, or first skill run and generates a thin repo-scoped wiring file; never hardcode an exhaustive client list.",
  "events": {
    "SessionStart": {
      "command": "bash scripts/session-gate.sh start",
      "blocking": false
    },
    "PreToolUse": {
      "matcher_intent": "file write / edit tools (e.g. write_file, edit_file, Write, Edit)",
      "commands": [
        "bash scripts/agent-gate --stage pre-write --file <target_path>",
        "bash scripts/session-gate.sh check"
      ],
      "blocking": true
    },
    "Stop": {
      "command": "bash scripts/session-gate.sh idle",
      "blocking": false
    }
  },
  "verify_command": "bash scripts/install-hook-adapter --verify-wiring <generated-config-path>",
  "windows_note": "On Windows Git Bash / MSYS2, ensure Git Bash precedes C:\\Windows\\System32\\bash.exe (WSL stub) in PATH or invoke /usr/bin/bash explicitly with MSYS_NO_PATHCONV=1.",
  "fallback": "If the current Agent genuinely has no repository-scoped hook surface, rely on Git hooks (.githooks) + CI without fabricating invalid config."
}
EOF
}

print_global_contract() {
  cat <<'EOF'
{
  "contract_version": "1",
  "scope": "user-global-cross-workspace",
  "principle": "Cross-workspace router hook (v4.5.1, CHG-150): resolves the target file's own git repository root so editing Repo B from a session opened in Repo A still triggers Repo B's agent-gate --stage pre-write.",
  "PreToolUse": {
    "matcher_intent": "file write / edit tools across any workspace",
    "router_script": [
      "target=\"${1:-${TOOL_FILE_PATH:-}}\"",
      "[ -n \"$target\" ] || exit 0",
      "repo=$(git -C \"$(dirname \"$target\")\" rev-parse --show-toplevel 2>/dev/null) || exit 0",
      "sdir=$(sed -nE '/^paths:[[:space:]]*$/,/^[^[:space:]#]/s/^[[:space:]]+scripts:[[:space:]]*([^#]*).*$/\\1/p' \"$repo/.agent-governance.yml\" 2>/dev/null | head -1 | tr -d \"[:space:]\\\"'\")",
      "sdir=\"${sdir:-scripts}\"",
      "if [ -x \"$repo/$sdir/agent-gate\" ]; then",
      "  ( cd \"$repo\" && bash \"$repo/$sdir/agent-gate\" --stage pre-write --file \"$target\" )",
      "fi"
    ],
    "blocking": true
  },
  "windows_note": "On Windows Git Bash / MSYS2, avoid C:\\Windows\\System32\\bash.exe (WSL stub); use Git Bash (/usr/bin/bash) with MSYS_NO_PATHCONV=1.",
  "notes": "Install in user-level client hooks (e.g. ~/.claude/settings.json or global client hook config); skips repositories without <scripts>/agent-gate (resolves paths.scripts from .agent-governance.yml, default scripts)."
}
EOF
}

adapter_scripts_dir() {
  local s=""
  if [[ -n "${AGENT_GUARD_SCRIPTS_DIR:-}" ]]; then
    s="$AGENT_GUARD_SCRIPTS_DIR"
  elif [[ -f .agent-governance.yml ]]; then
    s=$(sed -nE '/^paths:[[:space:]]*$/,/^[^[:space:]#]/s/^[[:space:]]+scripts:[[:space:]]*([^#]*).*$/\1/p' .agent-governance.yml 2>/dev/null \
        | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$s" ]] || s="scripts"
  printf '%s' "$s"
}

json_sanity_check() { # <file> — zero-dep fallback when python3/jq/node absent
  awk '
    BEGIN { b=0; k=0; q=0; esc=0; non_ws=0; first="" }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (first == "" && c !~ /[ \t\r\n]/) first = c
        if (c !~ /[ \t\r\n]/) non_ws = 1
        if (esc) { esc = 0; continue }
        if (q) {
          if (c == "\\") esc = 1
          else if (c == "\"") q = 0
          continue
        }
        if (c == "\"") { q = 1; continue }
        if (c == "{") b++
        else if (c == "}") { b--; if (b < 0) exit 1 }
        else if (c == "[") k++
        else if (c == "]") { k--; if (k < 0) exit 1 }
      }
    }
    END {
      if (!non_ws || (first != "{" && first != "[") || q != 0 || b != 0 || k != 0) exit 1
    }
  ' "$1"
}

verify_wiring() { # <config-path>
  local cfg="$1" sdir=""
  [[ -n "$cfg" && -f "$cfg" ]] || die "ADAPTER-E14: --verify-wiring target not found: ${cfg:-<empty>}"
  case "$cfg" in
    *.json)
      if has_real_python3; then
        python3 -m json.tool "$cfg" >/dev/null 2>&1 || die "ADAPTER-E14: invalid JSON in $cfg"
      elif command -v jq >/dev/null 2>&1; then
        jq empty "$cfg" >/dev/null 2>&1 || die "ADAPTER-E14: invalid JSON in $cfg"
      elif command -v node >/dev/null 2>&1; then
        node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$cfg" >/dev/null 2>&1 || die "ADAPTER-E14: invalid JSON in $cfg"
      else
        json_sanity_check "$cfg" || die "ADAPTER-E14: invalid JSON in $cfg"
      fi ;;
  esac
  if ! grep -qE 'session-gate|agent-gate' "$cfg" 2>/dev/null; then
    die "ADAPTER-E14: $cfg lacks session-gate or agent-gate hook wiring"
  fi
  sdir=$(adapter_scripts_dir)
  if grep -q 'session-gate' "$cfg" 2>/dev/null && [[ ! -f "$sdir/session-gate.sh" ]]; then
    die "ADAPTER-E14: $cfg references session-gate but $sdir/session-gate.sh is missing"
  fi
  if grep -q 'agent-gate' "$cfg" 2>/dev/null && [[ ! -f "$sdir/agent-gate" ]]; then
    die "ADAPTER-E14: $cfg references agent-gate but $sdir/agent-gate is missing"
  fi
  local rid="${AGENT_RUNTIME:-agents-hooks}"
  local rfam="json-hooks"
  [[ "$cfg" == *.js || "$cfg" == *.ts ]] && rfam="plugin-api"
  runtime_record "$rid" "$rfam" "$rid"
  ok "self-proof: dynamic wiring verified ($cfg carries session-gate/agent-gate hooks; runtime=$rid family=$rfam scripts=$sdir)"
}

detect_clients() { # -> whitespace-separated names, one per line
  # v4.5.0 (CHG-149, REQ-1389): strict priority — active process env > repo-scoped
  # config (including generic .agents/hooks.json) > PATH CLI fallback.
  # Never let a globally installed CLI on PATH hijack a different running Agent.
  local found=0
  # 1) Active process environment markers
  if [[ "${CLAUDECODE:-}" == "1" ]]; then echo claude; found=1; fi
  if [[ -n "${OPENCODE:-}" || -n "${OPENCODE_SESSION_ID:-}" ]]; then echo opencode; found=1; fi
  if [[ -n "${CURSOR_AGENT:-}" || -n "${CURSOR_TRACE_ID:-}" ]]; then echo cursor; found=1; fi
  if [[ "${GEMINI_CLI:-}" == "1" ]]; then echo gemini; found=1; fi
  if [[ -n "${CODEX_HOME:-}" ]]; then echo codex; found=1; fi
  # 2) Repository-scoped config in target repo
  if [[ -f .agents/hooks.json ]]; then echo agents-hooks; found=1; fi
  if [[ -d .claude && "${CLAUDECODE:-}" != "1" ]]; then echo claude; found=1; fi
  if [[ ( -f opencode.json || -f opencode.jsonc || -d .opencode ) && -z "${OPENCODE:-}${OPENCODE_SESSION_ID:-}" ]]; then echo opencode; found=1; fi
  if [[ -d .cursor && -z "${CURSOR_AGENT:-}${CURSOR_TRACE_ID:-}" ]]; then echo cursor; found=1; fi
  if [[ -d .gemini && "${GEMINI_CLI:-}" != "1" ]]; then echo gemini; found=1; fi
  if [[ -d .codex && -z "${CODEX_HOME:-}" ]]; then echo codex; found=1; fi
  # 3) Global PATH CLI fallback (only when neither env nor repo config matched)
  if [[ "$found" -eq 0 ]]; then
    if command -v claude >/dev/null 2>&1; then echo claude; fi
    if command -v opencode >/dev/null 2>&1; then echo opencode; fi
    if command -v codex >/dev/null 2>&1; then echo codex; fi
  fi
}

die() { echo "install-hook-adapter: $1" >&2; exit 2; }
note() { echo "install-hook-adapter: $1" >&2; }
ok() { echo "install-hook-adapter: $1"; }

# v3.90.1 (CHG-123, P0-1): protocol family, not product name. Products are
# unbounded; the hook protocols they speak are not. Classification drives the
# runtime ledger and the "unknown => visible" exit path.
runtime_family() { # <client-name> -> family
  case "$1" in
    claude|cursor|agents-hooks) printf 'json-hooks' ;;
    opencode)                   printf 'plugin-api' ;;
    gemini)                     [[ -f .agents/hooks.json ]] && printf 'json-hooks' || printf 'git+ci' ;;
    codex)                      printf 'git+ci' ;;
    *)                          [[ -f .agents/hooks.json ]] && printf 'json-hooks' || printf 'unknown' ;;
  esac
}

runtime_record() { # <runtime-id> <family> <clients...>
  local id="$1" fam="$2" clients="$3" st prev prev_fam ts
  st=".agent-state"
  mkdir -p "$st" 2>/dev/null || return 0
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
  prev=""; prev_fam=""
  [[ -s "$st/runtime.json" ]] \
    && prev=$(sed -n 's/.*"runtime_id":"\([^"]*\)".*/\1/p' "$st/runtime.json" | head -1 || true)
  [[ -s "$st/runtime.json" ]] \
    && prev_fam=$(sed -n 's/.*"family":"\([^"]*\)".*/\1/p' "$st/runtime.json" | head -1 || true)
  printf '{"runtime_id":"%s","family":"%s","clients":"%s","generated_at":"%s"}\n' \
    "$id" "$fam" "$clients" "$ts" > "$st/runtime.json" 2>/dev/null || true
  if [[ -n "$prev" && "$prev" != "$id" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$prev" "${prev_fam:-unknown}" "$id" "$fam" \
      >> "$st/runtime-transitions.tsv" 2>/dev/null || true
    note "WARN runtime changed: $prev (${prev_fam:-unknown}) -> $id ($fam) — re-probe wiring and recheck the enforcement layers (P0-1)"
  fi
}

runtime_layers() { # <id> — what is actually enforcing right now
  case "$1" in
    claude|cursor|opencode|agents-hooks) echo "in-session (hook/plugin) + Git hooks + CI" ;;
    gemini)
      if [[ -f .agents/hooks.json ]]; then echo "in-session (hook/plugin) + Git hooks + CI"
      else echo "Git hooks + CI (use --print-contract to wire repo hooks dynamically if supported)"
      fi ;;
    codex) echo "Git hooks + CI (this client has no repo-level hook surface)" ;;
    *)
      if [[ -f .agents/hooks.json ]]; then echo "in-session (hook/plugin) + Git hooks + CI"
      else echo "Git hooks + CI only (no in-session layer); AGENTS.md is read-only guidance"
      fi ;;
  esac
}

need_gate() {
  [[ -x scripts/agent-gate ]] || die "ADAPTER-E01: scripts/agent-gate not found or not executable — install the enforcement package first (bootstrap --guard)"
  [[ -f scripts/session-gate.sh ]] || die "ADAPTER-E02: scripts/session-gate.sh not found — upgrade the enforcement package (v3.28.0+)"
  bash -n scripts/session-gate.sh || die "ADAPTER-E03: scripts/session-gate.sh fails bash -n"
}

# ---------- claude：JSON 合并（保用户既有 hooks，按 command 串幂等去重） ----------
adapter_claude() {
  has_real_python3 || die "ADAPTER-E05: python3 required to merge .claude/settings.json (or use --print-contract for zero-dep dynamic wiring)"
  local f=".claude/settings.json" cmd_prefix=""
  cmd_prefix="$(resolve_hook_cmd_prefix)"
  # CHG-161（REQ-1610/1611，DES-1610）语义去重：键 =（事件, matcher, 归一化命令），只处理本项目写入的 6 条；
  # 同键保留首个并迁到规范形态，其余删除；用户自有 hook 原样保留；内容无变化不写盘（幂等），有变化先备份；
  # 写后从磁盘重读，断言每键恰好 1 条。
  python3 - "$f" "$cmd_prefix" <<'PY' || die "ADAPTER-E15: merging $f failed or the exactly-once check did not hold (file left as it was before the write; see the message above)"
import copy, datetime, json, os, re, shutil, sys
path = sys.argv[1]
prefix = sys.argv[2]
# CHG-162（REQ-1620，DES-1620）：命令锚定到项目根，不依赖会话 cwd；变量缺失回退 '.'（等价旧行为）
ANCHOR = '"${CLAUDE_PROJECT_DIR:-.}"/'
existed = os.path.exists(path)
d = {}
if existed:
    with open(path) as fh:
        d = json.load(fh)
orig = copy.deepcopy(d)
hooks = d.setdefault("hooks", {})

def norm(cmd):
    c = cmd or ""
    if prefix and c.startswith(prefix):
        c = c[len(prefix):]  # 已知前缀直接剥离（含带空格的 bash 路径）
    else:
        # 其它机器写入的前缀：必须消费到 bash/bash.exe（含带引号与旧版未加引号路径），防目录名含空格+scripts/ 时误剥
        c = re.sub(r'^MSYS_NO_PATHCONV=1\s+(?:"[^"]*?bash(?:\.exe)?"|(?:[^\n]*[/\\\s])?bash(?:\.exe)?)\s+(?=(?:\./)?scripts/|' + re.escape(ANCHOR) + r'scripts/)', '', c)
    c = re.sub(r'^bash\s+', '', c)
    if c.startswith(ANCHOR):
        c = c[len(ANCHOR):]
    return re.sub(r'^\./', '', c)

# (事件, matcher；None=条目不带 matcher 字段, 规范命令)
WIRINGS = [
    ("SessionStart", "", "scripts/session-gate.sh start"),
    ("PreToolUse", "Edit|Write", "scripts/agent-gate --stage pre-write"),
    ("Stop", None, "scripts/agent-gate --stage stop"),
    # v3.39.0（CHG-042）会话遥测：计数逻辑在 session-gate.sh 通用层，Claude 只做事件转发
    ("UserPromptSubmit", "", "scripts/session-gate.sh count turn"),
    ("PostToolUse", "Bash|Grep|Glob|Read|Task", "scripts/session-gate.sh count tool -"),
    # v3.58.0（REQ-1008）handoff 硬拦：PreToolUse exit 2 = Claude 原生块工具（stderr 回给 Agent）
    ("PreToolUse", "Bash|Edit|Write|Task|Grep|Glob|Read", "scripts/session-gate.sh check"),
]
KEYS = {(s, m or "", w) for s, m, w in WIRINGS}

seen = set()
for stage in list(hooks.keys()):
    lst = hooks[stage]
    if not isinstance(lst, list):
        continue
    kept = []
    for e in lst:
        if not isinstance(e, dict) or not isinstance(e.get("hooks"), list):
            kept.append(e)
            continue
        m = e.get("matcher") or ""
        nh = []
        for hk in e["hooks"]:
            if isinstance(hk, dict):
                k = (stage, m, norm(hk.get("command")))
                if k in KEYS:
                    if k in seen:
                        continue
                    seen.add(k)
                    if hk.get("command") != prefix + ANCHOR + k[2]:
                        hk["command"] = prefix + ANCHOR + k[2]
            nh.append(hk)
        if not nh:
            continue
        e["hooks"] = nh
        kept.append(e)
    hooks[stage] = kept

for stage, matcher, want in WIRINGS:
    if (stage, matcher or "", want) in seen:
        continue
    entry = {"hooks": [{"type": "command", "command": prefix + ANCHOR + want}]}
    if matcher is not None:
        entry = {"matcher": matcher, **entry}
    hooks.setdefault(stage, []).append(entry)

def tally(dd):
    cnt = {k: 0 for k in KEYS}
    hs = dd.get("hooks", {}) if isinstance(dd, dict) else {}
    if not isinstance(hs, dict):
        return cnt
    for stage, lst in hs.items():
        if not isinstance(lst, list):
            continue
        for e in lst:
            hl = e.get("hooks", []) if isinstance(e, dict) else []
            if not isinstance(hl, list):
                continue
            for hk in hl:
                if not isinstance(hk, dict):
                    continue
                k = (stage, e.get("matcher") or "", norm(hk.get("command")))
                if k in cnt:
                    cnt[k] += 1
    return cnt

def check(dd, where):
    cnt = tally(dd)
    bad = [k for k, n in cnt.items() if n != 1]
    if bad:
        sys.exit("hook wiring not exactly-once (%s): " % where + "; ".join("%s|%s|%s x%d" % (k + (cnt[k],)) for k in sorted(bad)))

# 写盘前先在内存里校验：失败时磁盘文件保持原样
check(d, "before write")

if d != orig:
    if existed:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        shutil.copy2(path, path + ".bak-" + stamp)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as fh:
        json.dump(d, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

# 生成后验证：从磁盘重读，JSON 必须可解析，6 条接线每键恰好 1 条
check(json.load(open(path)), "after write")
PY
  ok "claude -> $f merged + verified (SessionStart audit / pre-write / stop / telemetry count turn+tool / handoff hard-stop check)"
}

# ---------- opencode：四段式接线（探测 → 文档契约发现 → 生成 → 真加载验证） ----------
# v3.64.0（CHG-084，REQ-1038/1039，DES-1827/1828）：插件形状**永不写死**。候选形状集只是
# 探测输入，唯一仲裁 = 装机客户端自己的行为（`failed to load plugin` 错误行 + session-gate
# 功能标记）。同机多 runtime 契约互斥（homebrew CLI 1.18.x 实测 `default { id, server }`
# 可执行、setup/effect 同拒；Desktop 内置 CLI 2.0.x 实测 schema 要求 effect|setup 且
# server 被拒——v3.63.0 缺陷根因），逐 runtime 沙箱真加载探测，全部通过才落盘；无法确证
# 契约即 fail-closed（ADAPTER-E11/E12），绝不产出「看似接上」的静默死亡形状。
# 事件目录注（v3.38.0 起）：`chat.message` 已从 opencode 事件目录移除，回合计数走
# `message.updated` + user-role 过滤（见下方候选代码的事件映射）；最低兼容 opencode 1.18.x。
OPENCODE_PLUGIN='.opencode/plugins/dev-standards-gate.js'
OPENCODE_COMMAND='.opencode/command/gate-check.md'
OC_PROBE_WINDOW="${AGENT_GUARD_PROBE_WINDOW:-15}"
# 官方插件文档（安装/更新时实时检索；来源 URL 记入生成物契约头 —— REQ-1038）
OC_DOCS_URLS="https://opencode.ai/v2/docs/build/plugins/migrate-v1 https://opencode.ai/v2/docs/plugins https://opencode.ai/docs/plugins"
OC_TMP=""; OC_PROBE_ROOT=""
OC_ANY_EXEC=false; OC_ALL_INCONCL=true
OC_RESULTS=""
OC_WROTE=false

oc_ensure_tmp() { # 惰性创建 + EXIT 兜底回收（--detect/无 runtime/门禁死路径不再泄漏临时目录）
  [[ -n "$OC_TMP" && -d "$OC_TMP" ]] && return 0
  OC_TMP="$(mktemp -d)"; OC_PROBE_ROOT="$(mktemp -d)"
  trap '[[ -n "$OC_TMP" ]] && rm -rf "$OC_TMP" "$OC_PROBE_ROOT" 2>/dev/null || true' EXIT
}

oc_cleanup() { rm -rf "$OC_TMP" "$OC_PROBE_ROOT" 2>/dev/null || true; }

oc_clean_repo_litter() { # 终验探针在真实仓根的临时痕——成功/失败路径都必须清（评审 B1）
  # 两遍清扫：opencode 客户端被杀后可能有延迟的状态异步落盘（实测 .oc-xdg 内
  # tui/tabs.json 在 rm 后数秒内被复活），第二遍兜住 straggler。
  for _i in 1 2; do
    sleep 0.2
    rm -rf "$PWD/.oc-xdg" 2>/dev/null || true
    rm -f "$PWD/probe-serve.out" "$PWD/probe.pid" "$PWD/probe-run.out" "$PWD/probe-session.json" 2>/dev/null || true
  done
}

# 实时探测 runtime 清单与版本（REQ-1038 ①）：homebrew CLI 走 `opencode --version`；
# Desktop 内置 CLI 走 macOS 实证路径 glob（其余平台尽力探测，未检出即如实报告）。
# 测试注入：DEV_STANDARDS_OPENCODE_BIN / DEV_STANDARDS_OPENCODE_DESKTOP_BIN（路径不可执行=抑制该项）。
detect_opencode_runtimes() { # -> "kind|version|bin" 行（新版本在前）
  local bin="${DEV_STANDARDS_OPENCODE_BIN:-}" v
  if [[ -n "$bin" ]]; then
    if [[ -x "$bin" ]]; then
      v="$(oc_ver_of "$bin")"
      [[ -n "$v" ]] && echo "cli|$v|$bin"
    fi
  else
    bin="$(command -v opencode 2>/dev/null || true)"
    if [[ -n "$bin" && -x "$bin" ]]; then
      v="$(oc_ver_of "$bin")"
      [[ -n "$v" ]] && echo "cli|$v|$bin"
    fi
  fi
  local dbin="${DEV_STANDARDS_OPENCODE_DESKTOP_BIN:-}" f
  if [[ -n "$dbin" ]]; then
    if [[ -x "$dbin" ]]; then
      v="$(oc_ver_of "$dbin")"
      [[ -n "$v" ]] && echo "desktop|$v|$dbin"
    fi
  else
    local glob_dir="$HOME/Library/Application Support/ai.opencode.desktop/cli"
    while IFS= read -r f; do
      [[ -x "$f" ]] || continue
      v="$(oc_ver_of "$f")"
      [[ -n "$v" ]] && echo "desktop|$v|$f"
    done < <(ls -1d "$glob_dir"/*/opencode-cli 2>/dev/null | sort -Vr | head -3)
  fi
}

# 后台拉起 runtime（独立进程组 + stdin 断开）：CLI 会 fork 子服务进程，
# 单杀 PID 留孤儿写手，会与下一轮探针的沙箱清理竞态——必须整组杀（CHG-084 实测教训）。
oc_spawn_bg() { # <logfile> <pidfile> <workdir> <cmd...>
  python3 - "$@" <<'JSPAWN'
import os, subprocess, sys
logfile, pidfile, workdir = sys.argv[1], sys.argv[2], sys.argv[3]
cmd = sys.argv[4:]
env = dict(os.environ)
with open(logfile, "wb") as f:
    p = subprocess.Popen(cmd, cwd=workdir, stdout=f, stderr=subprocess.STDOUT,
                         stdin=subprocess.DEVNULL, start_new_session=True, env=env)
open(pidfile, "w").write(str(p.pid))
JSPAWN
}
oc_kill_bg() { # <pidfile>
  local pid; pid="$(cat "$1" 2>/dev/null || true)"
  [[ -z "$pid" ]] && return 0
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  sleep 0.2
  if kill -0 -- "-$pid" 2>/dev/null || kill -0 "$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    sleep 0.2
  fi
}

# 版本探测统一走 XDG 重定向（绝不触碰用户真实 opencode 状态；沙箱/CI 亦不因日志写失败而误判缺版本）
oc_ver_of() { # <bin> -> version string
  oc_ensure_tmp
  mkdir -p "$OC_TMP/xdg-v" 2>/dev/null || true
  env XDG_CONFIG_HOME="$OC_TMP/xdg-v/c" XDG_DATA_HOME="$OC_TMP/xdg-v/d" \
      XDG_STATE_HOME="$OC_TMP/xdg-v/s" XDG_CACHE_HOME="$OC_TMP/xdg-v/z" \
      OPENCODE_DISABLE_AUTOUPDATE=1 \
      "$1" --version 2>/dev/null | head -1 | sed -e 's/^opencode //' -e 's/^v//' | tr -d '\r' || true
}

oc_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
PY
}

# 单次真加载探测（沙箱内、XDG 全重定向——绝不触碰用户真实 opencode 状态）。
# 载入层裁决 = 客户端日志 `failed to load plugin` 行（功能层由调用方另测，缺一不可）。
oc_probe() { # <kind: cli|desktop> <bin> <workdir> -> echoes PASS|FAIL|INCONCLUSIVE
  OC_PROBE_DETAIL=""
  local kind="$1" bin="$2" workdir="$3"
  local xdg="$workdir/.oc-xdg"
  rm -rf "$xdg" 2>/dev/null || true; mkdir -p "$xdg/config" "$xdg/data" "$xdg/state" "$xdg/cache"
  local pid i listened="" port
  if [[ "$kind" == "cli" ]]; then
    port="$(oc_free_port 2>/dev/null)" || port=""
    if [[ -n "$port" ]]; then
      oc_spawn_bg "$workdir/probe-serve.out" "$workdir/probe.pid" "$workdir" \
        env XDG_CONFIG_HOME="$xdg/config" XDG_DATA_HOME="$xdg/data" \
            XDG_STATE_HOME="$xdg/state" XDG_CACHE_HOME="$xdg/cache" \
            OPENCODE_DISABLE_AUTOUPDATE=1 OPENCODE_DISABLE_MODELS_FETCH=1 \
            "$bin" serve --port "$port" --hostname 127.0.0.1
      local poll_step="0.2" poll_iters=15
      case "${OC_PROBE_WINDOW:-3}" in 0.*) poll_step="0.02" ;; esac
      poll_iters=$(awk -v w="${OC_PROBE_WINDOW:-3}" -v s="$poll_step" 'BEGIN{n=int((w/s)+0.999); if(n<1)n=1; print n}')
      for ((i = 0; i < poll_iters; i++)); do
        grep -q "server listening" "$workdir/probe-serve.out" 2>/dev/null && { listened=true; break; }
        sleep "$poll_step" 2>/dev/null || sleep 0.2
      done
      if [[ "$listened" == true ]]; then
        # 免凭据触发 session.created（实证：POST /session 不调用模型）
        curl -s -m 5 -X POST "http://127.0.0.1:$port/session" -H 'content-type: application/json' \
          -d '{}' -o "$workdir/probe-session.json" 2>/dev/null
        [[ -s "$workdir/probe-session.json" ]] || sleep "$poll_step" 2>/dev/null || sleep 0.2
        [[ -s "$workdir/probe-session.json" ]] || { curl -s -m 5 -X POST "http://127.0.0.1:$port/session" \
          -H 'content-type: application/json' -d '{}' -o "$workdir/probe-session.json" 2>/dev/null || true; }
        sleep "$poll_step" 2>/dev/null || sleep 0.2
        oc_kill_bg "$workdir/probe.pid"
      else
        oc_kill_bg "$workdir/probe.pid"
        port=""
      fi
    fi
    if [[ -z "$port" ]]; then
      # 回退原语：opencode run --print-logs（无 serve 能力环境；会话先于模型调用创建）
      oc_spawn_bg "$workdir/probe-run.out" "$workdir/probe.pid" "$workdir" \
        env XDG_CONFIG_HOME="$xdg/config" XDG_DATA_HOME="$xdg/data" \
            XDG_STATE_HOME="$xdg/state" XDG_CACHE_HOME="$xdg/cache" \
            OPENCODE_DISABLE_AUTOUPDATE=1 OPENCODE_DISABLE_MODELS_FETCH=1 \
            "$bin" run --print-logs "hi"
      sleep "$OC_PROBE_WINDOW"
      oc_kill_bg "$workdir/probe.pid"
    fi
  else
    # Desktop 内置 CLI 原语：--standalone（免凭据下事件照发，实证 2.0.20）
    oc_spawn_bg "$workdir/probe-run.out" "$workdir/probe.pid" "$workdir" \
      env XDG_CONFIG_HOME="$xdg/config" XDG_DATA_HOME="$xdg/data" \
          XDG_STATE_HOME="$xdg/state" XDG_CACHE_HOME="$xdg/cache" \
          OPENCODE_DISABLE_AUTOUPDATE=1 OPENCODE_DISABLE_MODELS_FETCH=1 \
          "$bin" "$workdir" --standalone --auto --print-logs --log-level info --prompt "hi"
    sleep "$OC_PROBE_WINDOW"
    oc_kill_bg "$workdir/probe.pid"
  fi
  case "${OC_PROBE_WINDOW:-3}" in
    0.*) sleep 0.02 2>/dev/null || sleep 0.2 ;;
    *) sleep 0.2 ;;
  esac
  local logs lf failed=""
  logs="$(find "$xdg" -name '*.log' 2>/dev/null || true)"
  if [[ -z "$logs" ]]; then
    echo "INCONCLUSIVE|probe-no-log(runtime did not run?)"; return
  fi
  while IFS= read -r lf; do
    [[ -f "$lf" ]] || continue
    if grep -h "failed to load plugin" "$lf" 2>/dev/null | grep -qF "dev-standards-gate"; then
      failed="$lf"; break
    fi
  done <<< "$logs"
  if [[ -n "$failed" ]]; then
    echo "FAIL|client-rejected(failed-to-load line in $(basename "$lf"))"; return
  fi
  echo "PASS|"
}

oc_build_candidate() { # <name> -> echoes candidate file path（形状是数据不是代码）
  local name="$1"
  local out="$OC_TMP/cand-$name.js"
  case "$name" in
    dual-active)
      { cat "$OC_TMP/header.txt"
        echo "// shape: dual-active — default { id, setup: DevStandardsGateV2, server: DevStandardsGate }"
        echo "//   (universal: CLI 1.18.x executes server() and never setup(); Desktop 2.0.x executes"
        echo "//    setup() and never server() — exactly one implementation runs per runtime, probed)"
        cat "$OC_TMP/frag-v1.js"; echo
        cat "$OC_TMP/frag-v2.js"; echo
        echo 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2, server: DevStandardsGate }'
      } > "$out" ;;
    server-only)
      { cat "$OC_TMP/header.txt"
        echo "// shape: server-only — default { id, server: DevStandardsGate }"
        echo "//   (homebrew CLI 1.18.x contract; Desktop 2.0.x schema rejects it — v3.63.0 defect shape)"
        cat "$OC_TMP/frag-v1.js"; echo
        echo 'export default { id: "dev-standards-gate", server: DevStandardsGate }'
      } > "$out" ;;
    setup-v2)
      { cat "$OC_TMP/header.txt"
        echo "// shape: setup-v2 — default { id, setup: DevStandardsGateV2 }"
        echo "//   (Desktop 2.0.x contract; CLI 1.18.x execution layer rejects default objects without server())"
        cat "$OC_TMP/frag-v2.js"; echo
        echo 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2 }'
      } > "$out" ;;
    *) return 1 ;;
  esac
  echo "$out"
}

# 仲裁：候选 × 逐 runtime（载入层 PASS + 功能标记 sg-call start 落盘 = 双条件）。
# 仅「无 failed-to-load 行」不判过——schema 过但 hooks 被丢弃的功能死形状必须在此拦截。
oc_arbitrate() { # <candidates> <runtimes> <label> ; sets OC_WINNER/OC_RESULTS；OC_ANY_EXEC/OC_ALL_INCONCL 跨轮合并（round-1 拒载证据不被 primary-only 轮覆盖）
  OC_WINNER=""
  local candidates="$1" runtimes="$2" label="$3"
  local cand cand_file sb verdict func_ok results kind ver bin all_pass pv detail win attempt
  for cand in $candidates; do
    cand_file="$(oc_build_candidate "$cand")" || { note "opencode: unknown candidate '$cand' skipped"; continue; }
    results=""; all_pass=true
    while IFS='|' read -r kind ver bin; do
      [[ -z "$kind" ]] && continue
      sb="$OC_PROBE_ROOT/probe-$kind-$ver-$cand"
      rm -rf "$sb"; mkdir -p "$sb/.opencode/plugins" "$sb/scripts" "$sb/out"
      cp "$cand_file" "$sb/.opencode/plugins/dev-standards-gate.js"
      # 功能标记桩：候选真实代码链（session.created -> $/child_process -> bash scripts/session-gate.sh）
      printf '#!/usr/bin/env bash\nprintf "%%s\\n" "sg-call $*" >> "%s/out/sg-runs.log"\n' "$sb" > "$sb/scripts/session-gate.sh"
      chmod +x "$sb/scripts/session-gate.sh"
      # 桌面 runtime 冷启动可达 10s+：每 runtime 三段窗（1x/2x/3x）重试，防时序假阴
      verdict=""; func_ok=false
      local detail=""
      for attempt in 1 2 3; do
        win="$OC_PROBE_WINDOW"; [[ "$attempt" != 1 ]] && win=$(awk -v w="$OC_PROBE_WINDOW" -v a="$attempt" 'BEGIN{printf "%.2f", w*a}')
        verdict=""; detail=""
        pv="$(OC_PROBE_WINDOW="$win" oc_probe "$kind" "$bin" "$sb")"
        verdict="${pv%%|*}"; detail="${pv#*|}"
        func_ok=false
        [[ -f "$sb/out/sg-runs.log" ]] && grep -q "sg-call start" "$sb/out/sg-runs.log" && func_ok=true
        [[ "$verdict" == "PASS" && "$func_ok" == true ]] && break
        # 客户端确定性拒载不随窗口变长而改变——早退，不为死候选白烧 2x/3x 窗
        [[ "$verdict" == "FAIL" ]] && break
      done
      # 探针子壳中途死于 set -e（spawn/curl 等意外）时：归 INCONCLUSIVE，不留空 detail 假 FAIL
      if [[ -z "$verdict" ]]; then
        verdict="INCONCLUSIVE"; detail="probe-subshell-died(unexpected abort inside oc_probe)"
      fi
      if [[ "$verdict" == "PASS" && "$func_ok" == true ]]; then
        results="$results $kind=$ver:PASS(function)"
        OC_ANY_EXEC=true; OC_ALL_INCONCL=false
      elif [[ "$verdict" == "INCONCLUSIVE" ]]; then
        results="$results $kind=$ver:INCONCLUSIVE($detail)"
        all_pass=false
      else
        OC_ANY_EXEC=true; OC_ALL_INCONCL=false
        if [[ "$verdict" == "PASS" ]]; then
          results="$results $kind=$ver:FAIL(loaded-but-no-functional-marker)"
        else
          results="$results $kind=$ver:FAIL($detail)"
        fi
        all_pass=false
      fi
    done <<< "$runtimes"
    OC_RESULTS="$OC_RESULTS
    attempt[$label] candidate[$cand]:$results"
    if [[ "$all_pass" == true ]]; then OC_WINNER="$cand"; return 0; fi
  done
}

adapter_opencode() {
  oc_ensure_tmp
  OC_WROTE=false
  need_gate
  local runtimes; runtimes="$(detect_opencode_runtimes || true)"
  if [[ -z "$runtimes" ]]; then
    note "opencode: no opencode runtime detected (CLI/PATH + Desktop bundled CLI both absent) — opencode adapter skipped, NOT silently (Git hooks + CI remain the enforcement line)"
    return 0
  fi
  oc_note_detect() { while IFS='|' read -r k v b; do [[ -n "$k" ]] && note "opencode: detected runtime $k version=$v"; done <<< "$runtimes"; }
  oc_note_detect

  # ② 文档契约发现（REQ-1038 ②）：实时检索官方文档；来源 URL 必须记录；网络不可达时
  # 如实声明并完全依赖 runtime 探测裁决——绝不凭记忆/静态映射表断言形状。
  local contract_source="official docs unreachable at install time; arbitrated-by-runtime-probe-only"
  local u
  if [[ "${OC_OFFLINE:-0}" == "1" ]]; then
    contract_source="offline mode (--offline / AGENT_GUARD_OFFLINE=1); arbitrated-by-runtime-probe-only"
    note "opencode: offline mode active — skipping remote docs fetch ($contract_source)"
  else
    for u in $OC_DOCS_URLS; do
      if curl -fsSL -m 8 "$u" -o "$OC_TMP/docs.html" 2>/dev/null && [[ -s "$OC_TMP/docs.html" ]]; then
        contract_source="$u (fetched live at install time; shape cross-checked by runtime probes)"
        break
      fi
    done
  fi
  # 候选集：AI 安装会话可经 DEV_STANDARDS_OPENCODE_CONTRACT（JSON）注入候选序与来源；
  # 缺省用内置候选序。无论来源，最终形状一律由真加载探测裁决——候选不是真理，探针才是。
  local candidates="dual-active server-only setup-v2"
  if [[ -n "${DEV_STANDARDS_OPENCODE_CONTRACT:-}" ]] && has_real_python3; then
    local inj=""
    inj="$(OC_CONTRACT_JSON="$DEV_STANDARDS_OPENCODE_CONTRACT" python3 - <<'PY' 2>/dev/null || true
import json, os
try:
    d = json.loads(os.environ["OC_CONTRACT_JSON"])
    c = d.get("candidates") or []
    if c:
        print(" ".join(str(x) for x in c))
    s = d.get("source") or ""
    if s:
        print("SOURCE:" + s)
except Exception:
    pass
PY
)"
    if [[ -n "$inj" ]]; then
      local line
      while IFS= read -r line; do
        case "$line" in
          SOURCE:*) contract_source="${line#SOURCE:}" ;;
          *) [[ -n "$line" ]] && candidates="$line" ;;
        esac
      done <<< "$inj"
      note "opencode: contract candidates injected via DEV_STANDARDS_OPENCODE_CONTRACT (still probe-arbitrated)"
    fi
  fi

  # ③ 生成形状片段（hooks 体单一权威，两套 runtime API 各一份，逻辑与 v3.63.0 等价）
  cat > "$OC_TMP/header.txt" <<'HDR'
// dev-standards-gate.js — generated by scripts/install-hook-adapter (v3.64.0, CHG-084).
// Regenerated on reinstall/upgrade; manual edits will be overwritten.
// All counting/telemetry LOGIC lives in scripts/session-gate.sh (bash, harness-agnostic);
// this file is a thin event forwarder carrying TWO runtime implementations of one wiring:
//   export const DevStandardsGate   — v1 hooks API (homebrew CLI 1.18.x: server() runs; setup() never does)
//   export const DevStandardsGateV2 — v2 setup API (Desktop bundled CLI 2.0.x: setup() runs; server() never does)
// Which implementation executes is decided by the runtime itself and was verified by
// per-runtime sandbox real-load probes at install time (client "failed to load plugin"
// line + session-gate.sh functional marker are the only arbiters — never trust a shape,
// see SKILL.md install-hook-adapter section). Event wiring (both implementations):
//   session.created      -> session-gate.sh start   (audit + telemetry reset)
//   message.updated      -> session-gate.sh count turn      (§2.9.6 water level; user role only)
//   message.part.updated -> session-gate.sh count tool <name> [cmd-head via DEV_STDARDS_CMD_HEAD]   (exploration budget + v3.73.0 wait/full-suite soft counters)
//   tool.execute.before  -> session-gate.sh check       (v3.58.0 handoff hard stop: throw on rc 2)
//   session.idle         -> session-gate.sh idle    (gate --stage stop 等价检查落盘)
HDR
  cat > "$OC_TMP/frag-v1.js" <<'JS'
// v1 hooks 实现（homebrew CLI 1.18.x 实测：`$`、client.app.log、directory 全链探针通过）
export const DevStandardsGate = async ({ client, $, directory }) => {
  const run = async (mode) => {
    try {
      const res = await $`bash scripts/session-gate.sh ${mode}`.cwd(directory).nothrow().quiet()
      await relay(String(res.stdout || ""))
    } catch {}
  }
  const countTurn = async () => {
    try {
      const res = await $`bash scripts/session-gate.sh count turn`.cwd(directory).nothrow().quiet()
      await relay(String(res.stdout || ""))
    } catch {}
  }
  const countTool = async (tool, cmd) => {
    try {
      // v3.73.0 (CHG-096, REQ-1100/1102): pass the command head via env — the value
      // is interpolated as ONE literal word by Bun shell (no shell re-parsing, no
      // quote injection); empty cmd = name-only degradation (existing behavior).
      const res = await $`DEV_STDARDS_CMD_HEAD=${cmd} bash scripts/session-gate.sh count tool ${tool}`.cwd(directory).nothrow().quiet()
      await relay(String(res.stdout || ""))
    } catch {}
  }
  // v3.58.0 (REQ-1008): handoff hard stop — throw blocks the tool call (fail-closed)
  const check = async () => {
    const res = await $`bash scripts/session-gate.sh check`.cwd(directory).nothrow().quiet()
    if ((res.exitCode ?? 0) === 2) {
      throw new Error(String(res.stderr || "").trim() || "session-gate: HARD STOP — turn limit reached (§2.9.6): run /handoff and continue in a new session")
    }
  }
  const relay = async (out) => {
    for (const line of out.split("\n")) {
      if (!line.startsWith("session-gate:")) continue
      const level = line.includes("GATE RED") || line.includes("YELLOW") || line.includes("TURN LIMIT") ? "warn" : "info"
      try {
        await client.app.log({ body: { service: "dev-standards-gate", level, message: line } })
      } catch {}
    }
  }
  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        await run("start")
      } else if (event.type === "message.updated") {
        // Count a "turn" only on user messages. If a future payload drops the
        // role field we fall back to counting (over-count = earlier handoff
        // warning — the safe direction; silent under-count would dead the line).
        try {
          const role = event.properties && event.properties.info && event.properties.info.role
          if (role === "assistant") return
        } catch {}
        await countTurn()
      } else if (event.type === "message.part.updated") {
        try {
          const p = event.properties && event.properties.part
          if (p && p.type === "tool" && p.tool) {
            // v3.73.0 (CHG-096): best-effort command head from part.state.input
            // (candidate keys command|cmd|script; first line, 200 chars). Unavailable
            // = empty string = name-only degradation (two soft counters idle).
            let cmd = ""
            try {
              const inp = p.state && p.state.input
              const raw = inp && (inp.command || inp.cmd || inp.script)
              if (typeof raw === "string" && raw) cmd = raw.split("\n")[0].slice(0, 200)
            } catch {}
            await countTool(p.tool, cmd)
          }
        } catch {}
      } else if (event.type === "session.idle") {
        await run("idle")
      }
    },
    "tool.execute.before": async () => {
      await check()
    },
  }
}
JS
  cat > "$OC_TMP/frag-v2.js" <<'JS'
import { execFile as _ocExecFile, execFileSync as _ocExecFileSync } from "node:child_process"
const _ocRun = (dir, args, env) => new Promise((resolve) => {
  _ocExecFile("bash", ["scripts/session-gate.sh", ...args], { cwd: dir, timeout: 15000, env: env || process.env }, (err, stdout) => {
    resolve({ out: String(stdout || "") })
  })
})
const _ocRelay = async (ctx, out) => {
  for (const line of String(out || "").split("\n")) {
    if (!line.startsWith("session-gate:")) continue
    const level = line.includes("GATE RED") || line.includes("YELLOW") || line.includes("TURN LIMIT") ? "warn" : "info"
    try { await ctx.app.log({ body: { service: "dev-standards-gate", level, message: line } }) } catch {}
  }
}
// v2 setup 实现（Desktop 内置 CLI 2.0.x 实测：setup() 持 v2 ctx（app/location/event/tool/...），
// server() 不被调用；ctx.event.subscribe 流式事件、ctx.tool.hook 同步 throw 硬拦均探针通过）
export const DevStandardsGateV2 = async (ctx) => {
  const dir = (ctx && ctx.location && ctx.location.directory) || process.cwd()
  const controller = new AbortController()
  void (async () => {
    try {
      for await (const ev of ctx.event.subscribe({ signal: controller.signal })) {
        try {
          if (ev.type === "session.created") {
            _ocRun(dir, ["start"]).then((r) => _ocRelay(ctx, r.out)).catch(() => {})
          } else if (ev.type === "message.updated") {
            try {
              const info = ev.properties && ev.properties.info
              if (info && info.role === "assistant") continue
            } catch {}
            _ocRun(dir, ["count", "turn"]).then((r) => _ocRelay(ctx, r.out)).catch(() => {})
          } else if (ev.type === "message.part.updated") {
            let tool = ""
            let cmd = ""
            try {
              const p = ev.properties && ev.properties.part
              if (p && p.type === "tool" && p.tool) {
                tool = p.tool
                // v3.73.0 (CHG-096): command head via execFile env option (no shell,
                // no injection surface); unavailable = name-only degradation.
                const inp = p.state && p.state.input
                const raw = inp && (inp.command || inp.cmd || inp.script)
                if (typeof raw === "string" && raw) cmd = raw.split("\n")[0].slice(0, 200)
              }
            } catch {}
            if (tool) {
              const env = cmd ? { ...process.env, DEV_STDARDS_CMD_HEAD: cmd } : process.env
              _ocRun(dir, ["count", "tool", tool], env).then((r) => _ocRelay(ctx, r.out)).catch(() => {})
            }
          } else if (ev.type === "session.idle") {
            _ocRun(dir, ["idle"]).then((r) => _ocRelay(ctx, r.out)).catch(() => {})
          }
        } catch {}
      }
    } catch {}
  })()
  // v3.58.0 (REQ-1008): handoff hard stop — 同步 throw 阻断工具调用（fail-closed；rc 2 = 轮次超限）
  try {
    await ctx.tool.hook("execute.before", () => {
      let status = 0
      let errOut = ""
      try {
        _ocExecFileSync("bash", ["scripts/session-gate.sh", "check"], { cwd: dir, timeout: 15000 })
      } catch (e) {
        status = (e && e.status) || 0
        errOut = String((e && e.stderr) || "")
        if (status !== 2) return
      }
      if (status === 2) {
        throw new Error(errOut.trim() || "session-gate: HARD STOP — turn limit reached (§2.9.6): run /handoff and continue in a new session")
      }
    })
  } catch {}
  return () => { try { controller.abort() } catch {} }
}
JS

  # ④ 逐 runtime 真加载仲裁（REQ-1039 / DES-1827；v4.6.0 CHG-151：按 runtime+候选模板哈希缓存）
  local oc_cache_file=".agent-state/opencode-arbitration-cache.tsv" oc_cache_key="" oc_cache_hit=0
  local _rt_sig _tpl_sig
  _rt_sig=$(printf '%s' "$runtimes" | cksum | awk '{print $1}')
  _tpl_sig=$(cat "$OC_TMP/header.txt" "$OC_TMP/frag-v1.js" "$OC_TMP/frag-v2.js" 2>/dev/null | cksum | awk '{print $1}')
  oc_cache_key="${_rt_sig}-${_tpl_sig}-$(printf '%s' "$candidates" | tr ' ' '+')"
  if [[ "${OC_REPROBE:-0}" != "1" && -s "$oc_cache_file" ]]; then
    local _cached_row _cw _ce13
    _cached_row=$(awk -F'\t' -v k="$oc_cache_key" '$1==k {r=$0} END{print r}' "$oc_cache_file" 2>/dev/null || true)
    if [[ -n "$_cached_row" ]]; then
      _cw=$(printf '%s' "$_cached_row" | awk -F'\t' '{print $2}')
      _ce13=$(printf '%s' "$_cached_row" | awk -F'\t' '{print $3}')
      case "$_cw" in
        dual-active|server-only|setup-v2)
          oc_build_candidate "$_cw" >/dev/null
          OC_WINNER="$_cw"
          OC_E13="${_ce13:-0}"
          OC_ANY_EXEC=true; OC_ALL_INCONCL=false
          OC_RESULTS=" cached-arbitration(key=${oc_cache_key} winner=${OC_WINNER})"
          oc_cache_hit=1
          note "opencode: arbitration cache hit ($OC_WINNER; pass --reprobe to refresh)"
          ;;
      esac
    fi
  fi
  if [[ "$oc_cache_hit" != "1" ]]; then
    oc_arbitrate "$candidates" "$runtimes" "all-runtimes"
    if [[ -z "$OC_WINNER" ]] && [[ "$(wc -l <<< "$runtimes" | tr -d ' ')" -gt 1 ]]; then
      # DES-1827 互斥回退：主用 runtime（探测序首个）择形，被牺牲 runtime 显式告警（E13）
      local primary; primary="$(head -1 <<< "$runtimes")"
      note "opencode: no shape passed EVERY runtime; retrying against PRIMARY runtime only (${primary%%|*}) — DES-1827"
      oc_arbitrate "$candidates" "$primary" "primary-only"
      if [[ -n "$OC_WINNER" ]]; then
        OC_E13="1"
        note "ADAPTER-E13 (warn): shape '$OC_WINNER' verified for the PRIMARY runtime only — other detected runtimes may reject or not execute this adapter; see arbitration matrix and consider upgrading the other runtime"
      fi
    fi
    if [[ -z "$OC_WINNER" ]]; then
      note "opencode: arbitration matrix:$OC_RESULTS"
      oc_cleanup
      if [[ "$OC_ALL_INCONCL" == true ]]; then
        die "ADAPTER-E11: opencode runtime(s) detected but the real-load probe produced no verdict (no client log / probe aborted / no known candidate executed) — contract cannot be established, refusing to guess a shape (DES-1828 fail-closed)"
      else
        die "ADAPTER-E12: every candidate shape was rejected or functionally dead on at least one detected runtime — refusing to write a silently-dead adapter (CHG-084 fail-closed)"
      fi
    fi
  fi
  note "opencode: arbitration winner '$OC_WINNER' —$OC_RESULTS"

  # 落盘（带契约证据头；既有文件先备份，终验失败即回滚）
  mkdir -p .opencode/plugins .opencode/command
  local backup=""
  if [[ -f "$OPENCODE_PLUGIN" ]]; then backup="$OC_TMP/previous-plugin.js"; cp "$OPENCODE_PLUGIN" "$backup"; fi
  local rt_line="" ver_list="" kind ver bin
  while IFS='|' read -r kind ver bin; do
    [[ -z "$kind" ]] && continue
    rt_line="$rt_line $kind=$ver"
    ver_list="${ver_list:+$ver_list,}$ver"
  done <<< "$runtimes"
  {
    echo "// contract-runtime:$rt_line"
    echo "// contract-version: $ver_list"
    echo "// contract-shape: $OC_WINNER (arbitrated by per-runtime probes at install time — never hardcoded)"
    echo "// contract-source: $contract_source"
    echo "// contract-verified-at: $(date -u '+%FT%TZ') via per-runtime real-load probes + session-gate functional markers:"
    printf '%s\n' "$OC_RESULTS" | sed 's/^/\/\/ /'
    echo "// final-file probes: PENDING"
    cat "$OC_TMP/cand-$OC_WINNER.js"
  } > "$OPENCODE_PLUGIN"
  cat > "$OPENCODE_COMMAND" <<'MD'
---
description: 跑一次 dev-standards 会话门禁检查（audit + stop 等价）
---
执行 `bash scripts/session-gate.sh start` 与 `bash scripts/session-gate.sh idle`，
读取 `.agent-state/session-gate-last.md`，向用户汇报全部 RED 项与处置清单（§2.14 回填清单）。
只报告，不自动修复；修复须走正式变更流程（agent-gate begin → … → stop）。
重启客户端后若怀疑适配器未生效：检查客户端日志有无本文件的 `failed to load plugin` 行
（v3.64.0 起安装器已做真加载验证，此命令用于装后复查），并确认 `.agent-state/`
遥测文件随会话刷新（`session-gate status` YELLOW 失联 = 适配器未被加载）。
MD
  # 快检保留为前置（不再作为验证充分的依据——REQ-1039）
  if command -v bun >/dev/null 2>&1; then
    bun "$OPENCODE_PLUGIN" >/dev/null 2>&1 \
      || { [[ -n "$backup" ]] && cp "$backup" "$OPENCODE_PLUGIN"; oc_cleanup; die "ADAPTER-E04: opencode plugin failed load check (bun)"; }
  elif command -v node >/dev/null 2>&1; then
    local _mjs; _mjs="$(mktemp).mjs"
    cp "$OPENCODE_PLUGIN" "$_mjs"
    node --check "$_mjs" 2>/dev/null \
      || { rm -f "$_mjs"; [[ -n "$backup" ]] && cp "$backup" "$OPENCODE_PLUGIN"; oc_cleanup; die "ADAPTER-E05: opencode plugin failed syntax check (node)"; }
    rm -f "$_mjs"
  else
    note "bun/node not found — syntax pre-check skipped (runtime probes still arbitrate)"
  fi

  # ⑤ 最终文件级真加载复验（REQ-1039：对每个检出 runtime，在真实路径上复跑探测；
  #    CLI 走 serve+POST 免模型调用；desktop 走 --standalone。功能证据 = 真实
  #    session-gate.sh start 在 .agent-state 落盘文件的 mtime 前进。）
  mkdir -p .agent-state
  touch "$OC_TMP/final-marker"
  # 功能证据关联标记（防同仓其他活跃会话的 hook 写入污染 mtime 判据）：
  # 安装器给探针注入 AGENT_GUARD_SESSION_TAG，session-gate start 把它写进报告；
  # 旧版 session-gate.sh（无 probe-tag 行）自动回落 mtime 判据（能力探测，不硬失败）。
  local tag_supported=false
  grep -q 'probe-tag' scripts/session-gate.sh 2>/dev/null && tag_supported=true
  local oc_session_tag="dsb-final-$$-$(date -u +%H%M%S 2>/dev/null || echo 0)"
  export AGENT_GUARD_SESSION_TAG="$oc_session_tag"
  local final_results="" fkind fver fbin fv fdetail pv advanced final_fail=""
  local oc_final_wait="0.5" oc_retry_wait="1" oc_retry_win
  case "${OC_PROBE_WINDOW:-3}" in 0.*) oc_final_wait="0.05"; oc_retry_wait="0.1" ;; esac
  oc_retry_win=$(awk -v w="${OC_PROBE_WINDOW:-3}" 'BEGIN{printf "%.2f", w*3}')
  while IFS='|' read -r fkind fver fbin; do
    [[ -z "$fkind" ]] && continue
    fv=""; fdetail=""
    pv="$(oc_probe "$fkind" "$fbin" "$PWD")"
    fv="${pv%%|*}"; fdetail="${pv#*|}"
    sleep "$oc_final_wait" 2>/dev/null || sleep 0.5
    if [[ "$tag_supported" == true ]]; then
      advanced="$(grep -F "probe-tag: $oc_session_tag" .agent-state/session-gate-last.md 2>/dev/null | head -1 || true)"
    else
      advanced="$(find .agent-state -maxdepth 1 \( -name 'session-gate-last.md' -o -name 'session-started.json' \) -newer "$OC_TMP/final-marker" 2>/dev/null | head -1 || true)"
    fi
    if [[ "$fv" == "PASS" && -n "$advanced" ]]; then
      final_results="$final_results $fkind=$fver:PASS(function)"
    else
      # 一次加窗重试（真实 start 可能慢于探测窗：audit --only-fail 耗时随仓大小浮动）；
      # 重试窗上限 ×2→×3（上限放宽，补偿步进收紧）
      pv="$(OC_PROBE_WINDOW="$oc_retry_win" oc_probe "$fkind" "$fbin" "$PWD")"
      fv="${pv%%|*}"; fdetail="${pv#*|}"
      sleep "$oc_retry_wait" 2>/dev/null || sleep 1
      if [[ "$tag_supported" == true ]]; then
        advanced="$(grep -F "probe-tag: $oc_session_tag" .agent-state/session-gate-last.md 2>/dev/null | head -1 || true)"
      else
        advanced="$(find .agent-state -maxdepth 1 \( -name 'session-gate-last.md' -o -name 'session-started.json' \) -newer "$OC_TMP/final-marker" 2>/dev/null | head -1 || true)"
      fi
      if [[ "$fv" == "PASS" && -n "$advanced" ]]; then
        final_results="$final_results $fkind=$fver:PASS(function,retried)"
      else
        final_results="$final_results $fkind=$fver:FAIL($fv${fdetail:+;}$fdetail)"
        final_fail="${final_fail:+$final_fail, }$fkind=$fver"
      fi
    fi
  done <<< "$runtimes"
  if [[ -n "$final_fail" ]]; then
    note "opencode: arbitration matrix:$OC_RESULTS"
    if [[ -n "$backup" ]]; then cp "$backup" "$OPENCODE_PLUGIN"; else rm -f "$OPENCODE_PLUGIN"; fi
    oc_clean_repo_litter
    oc_cleanup
    die "ADAPTER-E12: final-file real-load verification failed for $final_fail — previous adapter restored (or file removed); adapter NOT installed (CHG-084 fail-closed)"
  fi
  # E13 预警若被终验推翻（全部 runtime 终验 PASS），显式解除，不留误导性告警
  if [[ "${OC_E13:-}" == "1" ]]; then
    note "ADAPTER-E13 resolved: final-file probes PASSED on every detected runtime — the primary-only concern did not materialize"
  fi
  sed -i.bak "s|final-file probes: PENDING|final-file probes:$final_results|" "$OPENCODE_PLUGIN" 2>/dev/null \
    && rm -f "$OPENCODE_PLUGIN.bak" \
    || { oc_clean_repo_litter; oc_cleanup; die "ADAPTER-E14: contract header stamping failed (sed); adapter NOT installed (CHG-084 fail-closed)"; }
  # v4.6.0 (CHG-151, REQ-1414): persist arbitration winner ONLY after final-file verification passes
  if [[ "$oc_cache_hit" != "1" && -n "$oc_cache_key" && -n "$OC_WINNER" ]]; then
    mkdir -p "$(dirname "$oc_cache_file")" 2>/dev/null || true
    { [[ -f "$oc_cache_file" ]] && grep -vF "${oc_cache_key}"$'\t' "$oc_cache_file" | tail -n 15; printf '%s\t%s\t%s\t%s\n' "$oc_cache_key" "$OC_WINNER" "${OC_E13:-0}" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"; } > "$oc_cache_file.tmp" 2>/dev/null \
      && mv "$oc_cache_file.tmp" "$oc_cache_file" 2>/dev/null || rm -f "$oc_cache_file.tmp"
  fi
  # 清扫终验探针在真实仓根留下的临时痕（.oc-xdg/probe-*）——成功与失败路径共用
  oc_clean_repo_litter
  OC_WROTE=true
  oc_cleanup
  ok "opencode -> $OPENCODE_PLUGIN + $OPENCODE_COMMAND written + runtime-verified:$final_results (shape=$OC_WINNER; source=$contract_source)"
}

# ---------- cursor / gemini：静态 schema（保守保留 v3.17 行为，diff + --force） ----------
static_schema() { # name path
  local tool="$1" path="$2" content="" cmd_prefix="" cmd_prefix_json=""
  cmd_prefix="$(resolve_hook_cmd_prefix)"
  cmd_prefix_json="${cmd_prefix//\\/\\\\}"
  cmd_prefix_json="${cmd_prefix_json//\"/\\\"}"
  case "$tool" in
    cursor) content="{
  \"version\": 1,
  \"hooks\": {
    \"sessionStart\": [
      { \"command\": \"${cmd_prefix_json}scripts/session-gate.sh start\" }
    ],
    \"beforeSubmitPrompt\": [
      { \"command\": \"${cmd_prefix_json}scripts/session-gate.sh count turn\" }
    ],
    \"postToolUse\": [
      { \"matcher\": \"Shell|Read|Grep|Task\", \"command\": \"${cmd_prefix_json}scripts/session-gate.sh count tool -\" }
    ],
    \"preToolUse\": [
      { \"matcher\": \"Write\", \"command\": \"${cmd_prefix_json}scripts/agent-gate --stage pre-write\" },
      { \"matcher\": \"Shell|Write|Task|Grep|Read\", \"command\": \"${cmd_prefix_json}scripts/session-gate.sh check\" }
    ],
    \"stop\": [
      { \"command\": \"${cmd_prefix_json}scripts/agent-gate --stage stop\" }
    ]
  }
}"
    ;;
    gemini) content='' ;;  # v3.63.0 (REQ-1036): gemini CLI has no repository-scoped hook surface — handled by no_hook_surface, never write fabricated config keys
  esac
  if [[ -e "$path" ]]; then
    if [[ "$content" == "$(cat "$path")" ]]; then
      ok "$tool -> $path already up to date."
      return 0
    fi
    if [[ "${FORCE:-false}" != true ]]; then
      note "$tool -> $path exists with different content, diff:"
      diff -u "$path" <(printf '%s\n' "$content") >&2 || true
      note "$tool -> re-run with --force to overwrite, or merge manually (existing hooks preserved)"
      return 1
    fi
  fi
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  # 静态 schema 同样过验证
  if has_real_python3; then
    python3 -m json.tool "$path" >/dev/null 2>&1 || die "ADAPTER-E06: $tool -> $path is not valid JSON after write"
  else
    json_sanity_check "$path" || die "ADAPTER-E06: $tool -> $path is not valid JSON after write"
  fi
  # v3.63.0 (REQ-1036, DES-1824): cursor 结构断言——遥测/硬拦键必须就位（假绿防线）
  if [[ "$tool" == "cursor" ]]; then
    grep -q '"beforeSubmitPrompt"' "$path" || die "ADAPTER-E10: cursor hooks.json missing beforeSubmitPrompt (turn telemetry dead)"
    grep -q '"preToolUse"' "$path" || die "ADAPTER-E10: cursor hooks.json missing preToolUse (handoff hard stop dead)"
  fi
  ok "$tool -> $path written + JSON verified (pre-write wired; session audit relies on Git hooks + CI)"
}

# ---------- codex / gemini：无仓级 hook 面，如实声明兜底路径（v3.63.0 REQ-1036） ----------
no_hook_surface() { # <tool>
  # v3.63.0: gemini 曾被写入伪造的 "hooks/BeforeTool" settings.json 键（客户端不
  # 识别、静默无效 = 假绿）；codex 的 notify 面仅在用户级 ~/.codex/config.toml，
  # 无仓级作用域。两者统一如实声明：会话时执法不可接线，兜底 = Git hooks + CI +
  # AGENTS.md 纪律层。协议形状核对时点：2026-09（cursor 依据 hooks 文档，opencode
  # 依据 1.18.x 插件 schema 与本机日志实证）。
  note "$1 has no repository-scoped hook/plugin surface (verified 2026-09) — session-time wiring NOT possible; enforcement line = Git hooks (core.hooksPath -> .githooks) + CI (agent-governance) + AGENTS.md discipline layer."
  # R07-6 (07-review): repos upgraded from pre-v3.63.0 templates may carry the
  # fabricated gemini config (never functional) — surface it instead of letting
  # stale fake wiring sit as false evidence.
  if [[ "$1" == "gemini" && -f .gemini/settings.json ]] && grep -q "agent-governance\|agent-gate" .gemini/settings.json 2>/dev/null; then
    note "gemini: .gemini/settings.json contains a fabricated dev-standards hooks block from a pre-v3.63.0 template (never functional) — remove the 'hooks' key manually; your own non-dev-standards content stays untouched"
  fi
  return 0
}

adapter_codex() {
  no_hook_surface codex
}

# ---------- main ----------
mode_install=true
client=""
all=false
OC_OFFLINE="${AGENT_GUARD_OFFLINE:-0}"
OC_REPROBE="${AGENT_GUARD_REPROBE:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detect) mode_install=false ;;
    --print-contract) print_contract; exit 0 ;;
    --print-global-contract) print_global_contract; exit 0 ;;
    --verify-wiring)
      [[ -n "${2:-}" ]] || die "ADAPTER-E14: --verify-wiring requires a file path"
      verify_wiring "$2"; exit 0 ;;
    --canary)
      # v3.91.0 (CHG-127, G10): behavioural canary — write a marker, verify it
      # survived into the repo's hook scope, then report. Never mutates config.
      _cm="$PWD/.agent-state/canary-$(date -u +%s).json"
      mkdir -p "$(dirname "$_cm")" 2>/dev/null || true
      printf '{"canary":true,"ts":"%s","runtime":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "${AGENT_RUNTIME:-unknown}" > "$_cm" 2>/dev/null
      if [[ -s "$_cm" ]]; then echo "canary: ok ($_cm)"; else echo "canary: FAILED to write ($_cm)"; exit 2; fi
      exit 0
      ;;
    --client) client="${2:-}"; [[ -n "$client" ]] || die "ADAPTER-E07: --client requires a name"; shift ;;
    --offline) OC_OFFLINE=1 ;;
    --reprobe) OC_REPROBE=1 ;;
    --force) export FORCE=true ;;
    --all) all=true ;;
    -h|--help) usage; exit 0 ;;
    claude|opencode|cursor|gemini|codex) client="$1" ;;
    *) note "unknown argument '$1'"; usage >&2; exit 2 ;;
  esac
  shift
done

matrix=$(detect_clients || true)
# v3.90.1 (CHG-123, P0-1): env > detected config shape > unknown. AGENT_RUNTIME is
# the user's explicit override (highest), mirroring AGENT_GUARD_MODEL.
# AGENT_GUARD_RUNTIME_PROBE=0 is the single switch back to the legacy product-name
# behaviour (visible in --detect, no runtime ledger written).
if [[ "${AGENT_GUARD_RUNTIME_PROBE:-1}" == "0" ]]; then
  if [[ "$mode_install" == false ]]; then
    echo "install-hook-adapter: runtime probe disabled (AGENT_GUARD_RUNTIME_PROBE=0) — legacy product-name detection:"
    if [[ -z "$matrix" ]]; then
      echo "  (none detected — Git hooks + CI remain the enforcement line)"
      exit 0
    fi
    for c in $matrix; do echo "  - $c"; done
    exit 0
  fi
else
runtime_id="${AGENT_RUNTIME:-}"
[[ -n "$runtime_id" ]] || runtime_id=$(printf '%s\n' "$matrix" | head -1)
[[ -n "$runtime_id" ]] || runtime_id="unknown"
runtime_fam=$(runtime_family "$runtime_id")
# REQ-1307 withdrawn (CHG-130): --detect is the runtime *detection* ledger's only
# writer (T26c pins .agent-state/runtime.json + the transition line), so the
# probe is deliberately stateful. Making it read-only would break the documented
# handshake rather than fix a defect.
runtime_record "$runtime_id" "$runtime_fam" "$(printf '%s' "$matrix" | tr '\n' ' ')"

if [[ "$mode_install" == false ]]; then
  echo "install-hook-adapter: detection matrix (env / CLI on PATH / repo config):"
  echo "  runtime: $runtime_id (family: $runtime_fam)"
  echo "  effective layers: $(runtime_layers "$runtime_id")"
  if [[ -z "$matrix" ]]; then
    echo "  (none detected) — in-session enforcement is NOT active; Git hooks + CI remain the line"
    echo "  declare the client with AGENT_RUNTIME=<claude|opencode|cursor|gemini|codex> when detection cannot see it (exit 3 = unknown, never silent success)"
    exit 3
  fi
  for c in $matrix; do echo "  - $c ($(runtime_family "$c"))"; done
  exit 0
fi
fi

need_gate

if [[ -n "$client" ]]; then
  case "$client" in
    claude|opencode|cursor|gemini|codex) ;;
    *) die "ADAPTER-E08: unsupported client '$client' (supported: claude opencode cursor gemini codex)" ;;
  esac
  targets="$client"
else
  targets="$matrix"
  if [[ -z "$targets" ]]; then
    note "no supported client detected — nothing wired; effective layers: $(runtime_layers unknown)"
    note "Git hooks + CI still enforce (they validate the repo, not the editor). Declare the client with AGENT_RUNTIME=<name> if detection cannot see it (P0-1)."
    exit 0
  fi
fi

installed=0
for c in $targets; do
  case "$c" in
    claude)   adapter_claude   && installed=$((installed+1)) || note "claude wiring failed" ;;
    opencode)
      OC_WROTE=false
      if adapter_opencode; then
        [[ "$OC_WROTE" == true ]] && installed=$((installed+1))
      else
        note "opencode wiring failed"
      fi ;;
    cursor)   static_schema cursor .cursor/hooks.json   && installed=$((installed+1)) || true ;;
    agents-hooks)
      if [[ -f .agents/hooks.json ]] && verify_wiring .agents/hooks.json >/dev/null 2>&1; then
        ok "agents-hooks -> .agents/hooks.json verified"
        installed=$((installed+1))
      else
        note "agents-hooks wiring invalid or incomplete (.agents/hooks.json)"
      fi ;;
    gemini)   no_hook_surface gemini ;;
    codex)    adapter_codex ;;
  esac
done

if [[ "$installed" -eq 0 ]]; then
  note "no config was written (static-schema conflicts need --force; see notes above)"
  exit 2
fi

# v3.82.0 (CHG-109, REQ-1160): post-wiring self-proof — a config that does not
# carry the session-gate wiring would silently downgrade to zero telemetry and
# no turn enforcement (live incident: adapter not loaded client-side, stats
# all-zero for a whole session). Client-side LOADING still cannot be proven
# from here: after the first bash call, run scripts/session-gate status —
# YELLOW liveness means the adapter is dead (check client logs).
for c in $targets; do
  case "$c" in
    claude)   sp_f=".claude/settings.json" ;;
    opencode) sp_f=".opencode/plugins/dev-standards-gate.js" ;;
    cursor)   sp_f=".cursor/hooks.json" ;;
    *)        sp_f="" ;;
  esac
  [[ -z "$sp_f" ]] && continue
  if [[ -f "$sp_f" ]] && grep -q "session-gate" "$sp_f"; then
    ok "self-proof: $c wiring verified ($sp_f carries session-gate hooks)"
  else
    note "self-proof FAIL: $c config $sp_f missing or lacks session-gate wiring — the client will NOT load the adapter (telemetry + turn enforcement dead); check client logs; after your first bash call run scripts/session-gate status (YELLOW = adapter dead)"
  fi
done

ok "$installed client(s) wired; session enforcement active for supported clients"
# CHG-160: 按 agent 的模型/窗口声明入口。只打印变量名，不写入也不猜任何模型名或窗口值。
for _c in $matrix; do
  case "$_c" in claude|opencode|cursor|gemini|codex) ;; *) continue ;; esac
  _k=$(printf '%s' "$_c" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')
  ok "context window for $_c is unverified until declared: export AGENT_GUARD_MODEL_${_k}=<model-id> AGENT_GUARD_CONTEXT_WINDOW_${_k}=<tokens> (generic AGENT_GUARD_MODEL / AGENT_GUARD_CONTEXT_WINDOW take precedence)"
done
ok ".agent-state/ is runtime state (telemetry/audit reports), NOT a governance artifact — add it to .gitignore; probe scratch .oc-xdg/ likewise (residue guard)"
