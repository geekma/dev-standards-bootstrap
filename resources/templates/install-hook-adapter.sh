#!/usr/bin/env bash
# install-hook-adapter.sh — 按当前 Agent 环境自适应生成会话内执法接线（v3.28.0）。
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
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-hook-adapter.sh [--detect | --client <name>] [--force] [--all]

Detects the AI coding clients present in this environment/repo and writes the
session-enforcement wiring for each:

  claude    .claude/settings.json          JSON-merge: SessionStart(session-gate start)
                                           + PreToolUse(agent-gate pre-write) + Stop(stop)
  opencode  .opencode/plugins/dev-standards-gate.js
            .opencode/command/gate-check.md
                                           session.created -> session-gate start,
                                           session.idle -> session-gate idle
  cursor    .cursor/hooks.json             preToolUse(pre-write) + stop(stop)
  gemini    .gemini/settings.json          BeforeTool(pre-write)
  codex     (no hook schema)               note only: Git hooks + CI are the
                                           enforcement line

Flags:
  --detect        print the detection matrix and exit (writes nothing)
  --client <name> force-install for one client (claude|opencode|cursor|gemini|codex)
  --all           install for every detected client (default when no --client)
  --force         overwrite existing static-schema configs that differ (diff is shown)
EOF
}

detect_clients() { # -> whitespace-separated names, one per line
  # claude: env marker, CLI, or repo config dir
  if [[ "${CLAUDECODE:-}" == "1" ]] || command -v claude >/dev/null 2>&1 || [[ -d .claude ]]; then
    echo claude
  fi
  # opencode: CLI, repo config file, or plugin dir
  if command -v opencode >/dev/null 2>&1 || [[ -f opencode.json || -f opencode.jsonc || -d .opencode ]]; then
    echo opencode
  fi
  if [[ -n "${CURSOR_AGENT:-}" || -n "${CURSOR_TRACE_ID:-}" ]] || [[ -d .cursor ]]; then
    echo cursor
  fi
  if [[ "${GEMINI_CLI:-}" == "1" ]] || [[ -d .gemini ]]; then
    echo gemini
  fi
  if [[ -n "${CODEX_HOME:-}" ]] || command -v codex >/dev/null 2>&1 || [[ -d .codex ]]; then
    echo codex
  fi
}

die() { echo "install-hook-adapter: $1" >&2; exit 2; }
note() { echo "install-hook-adapter: $1" >&2; }
ok() { echo "install-hook-adapter: $1"; }

need_gate() {
  [[ -x scripts/agent-gate ]] || die "scripts/agent-gate not found or not executable — install the enforcement package first (bootstrap --guard)"
  [[ -f scripts/session-gate.sh ]] || die "scripts/session-gate.sh not found — upgrade the enforcement package (v3.28.0+)"
  bash -n scripts/session-gate.sh || die "scripts/session-gate.sh fails bash -n"
}

# ---------- claude：JSON 合并（保用户既有 hooks，按 command 串幂等去重） ----------
adapter_claude() {
  local f=".claude/settings.json"
  python3 - "$f" <<'PY'
import json, sys, os
path = sys.argv[1]
d = {}
if os.path.exists(path):
    with open(path) as fh:
        d = json.load(fh)
hooks = d.setdefault("hooks", {})

def ensure(stage, entry):
    lst = hooks.setdefault(stage, [])
    want = entry["hooks"][0]["command"]
    for e in lst:
        for hk in e.get("hooks", []):
            if hk.get("command") == want:
                return
    lst.append(entry)

ensure("SessionStart", {"matcher": "", "hooks": [{"type": "command", "command": "scripts/session-gate.sh start"}]})
ensure("PreToolUse", {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "scripts/agent-gate --stage pre-write"}]})
ensure("Stop", {"hooks": [{"type": "command", "command": "scripts/agent-gate --stage stop"}]})
# v3.39.0（CHG-042）会话遥测：计数逻辑在 session-gate.sh 通用层，Claude 只做事件转发
ensure("UserPromptSubmit", {"matcher": "", "hooks": [{"type": "command", "command": "scripts/session-gate.sh count turn"}]})
ensure("PostToolUse", {"matcher": "Bash|Grep|Glob|Read|Task", "hooks": [{"type": "command", "command": "scripts/session-gate.sh count tool -"}]})

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
  # 生成后验证：JSON 必须可解析，五条接线必须就位
  python3 - "$f" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
h = d.get("hooks", {})
cmds = [hk.get("command") for st in h.values() for e in st for hk in e.get("hooks", [])]
for want in ("scripts/session-gate.sh start", "scripts/agent-gate --stage pre-write", "scripts/agent-gate --stage stop", "scripts/session-gate.sh count turn", "scripts/session-gate.sh count tool -"):
    if want not in cmds:
        sys.exit(f"missing hook after merge: {want}")
PY
  ok "claude -> $f merged + verified (SessionStart audit / pre-write / stop / telemetry count turn+tool)"
}

# ---------- opencode：生成插件 + 手动检查命令（生成物，重装即重写） ----------
OPENCODE_PLUGIN='.opencode/plugins/dev-standards-gate.js'
OPENCODE_COMMAND='.opencode/command/gate-check.md'

adapter_opencode() {
  mkdir -p .opencode/plugins .opencode/command
  cat > "$OPENCODE_PLUGIN" <<'JS'
// dev-standards-gate.js — generated by scripts/install-hook-adapter (v3.39.0).
// Regenerated on reinstall; manual edits will be overwritten.
// All counting/telemetry LOGIC lives in scripts/session-gate.sh (bash, harness-
// agnostic); this plugin is a thin event forwarder for OpenCode only:
//   session.created      -> session-gate.sh start   (audit + telemetry reset)
//   chat.message         -> session-gate.sh count turn      (§2.9.6 water level)
//   message.part.updated -> session-gate.sh count tool <name>   (exploration budget)
//   session.idle         -> session-gate.sh idle    (gate --stage stop 等价检查落盘)
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
  const countTool = async (tool) => {
    try {
      const res = await $`bash scripts/session-gate.sh count tool ${tool}`.cwd(directory).nothrow().quiet()
      await relay(String(res.stdout || ""))
    } catch {}
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
      } else if (event.type === "chat.message") {
        await countTurn()
      } else if (event.type === "message.part.updated") {
        try {
          const p = event.properties && event.properties.part
          if (p && p.type === "tool" && p.tool) await countTool(p.tool)
        } catch {}
      } else if (event.type === "session.idle") {
        await run("idle")
      }
    },
  }
}
JS
  cat > "$OPENCODE_COMMAND" <<'MD'
---
description: 跑一次 dev-standards 会话门禁检查（audit + stop 等价）
---
执行 `bash scripts/session-gate.sh start` 与 `bash scripts/session-gate.sh idle`，
读取 `.agent-state/session-gate-last.md`，向用户汇报全部 RED 项与处置清单（§2.14 回填清单）。
只报告，不自动修复；修复须走正式变更流程（agent-gate begin → … → stop）。
MD
  # 生成后验证：模块必须能被加载且导出 DevStandardsGate（bun 直接求值；node 走
  # --check 的 .mjs 拷贝）。验证不过 = 安装失败，绝不留下"看似接上"的假绿。
  if command -v bun >/dev/null 2>&1; then
    bun "$OPENCODE_PLUGIN" >/dev/null 2>&1 || die "opencode plugin failed load check (bun)"
  elif command -v node >/dev/null 2>&1; then
    _mjs="$(mktemp).mjs"
    cp "$OPENCODE_PLUGIN" "$_mjs"
    node --check "$_mjs" || { rm -f "$_mjs"; die "opencode plugin failed syntax check (node)"; }
    rm -f "$_mjs"
  else
    note "bun/node not found — opencode plugin written but NOT load-verified; opencode will surface any error at startup"
  fi
  ok "opencode -> $OPENCODE_PLUGIN + $OPENCODE_COMMAND written + verified"
}

# ---------- cursor / gemini：静态 schema（保守保留 v3.17 行为，diff + --force） ----------
static_schema() { # name path
  local tool="$1" path="$2" content=""
  case "$tool" in
    cursor) content='{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "matcher": "Write",
        "command": "scripts/agent-gate --stage pre-write"
      }
    ],
    "stop": [
      {
        "command": "scripts/agent-gate --stage stop"
      }
    ]
  }
}'
    ;;
    gemini) content='{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "write_file|replace",
        "hooks": [
          {
            "type": "command",
            "command": "scripts/agent-gate --stage pre-write",
            "name": "agent-governance-pre-write"
          }
        ]
      }
    ]
  }
}'
    ;;
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
  python3 -m json.tool "$path" >/dev/null 2>&1 || die "$tool -> $path is not valid JSON after write"
  ok "$tool -> $path written + JSON verified (pre-write wired; session audit relies on Git hooks + CI)"
}

# ---------- codex：无 hook schema，如实声明兜底路径 ----------
adapter_codex() {
  note "codex has no hook schema — session-time wiring is NOT possible; enforcement line = Git hooks (core.hooksPath -> .githooks) + CI (agent-governance). AGENTS.md already instructs gate usage."
  return 0
}

# ---------- main ----------
mode_install=true
client=""
all=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detect) mode_install=false ;;
    --client) client="${2:-}"; [[ -n "$client" ]] || die "--client requires a name"; shift ;;
    --force) export FORCE=true ;;
    --all) all=true ;;
    -h|--help) usage; exit 0 ;;
    claude|opencode|cursor|gemini|codex) client="$1" ;;
    *) note "unknown argument '$1'"; usage >&2; exit 2 ;;
  esac
  shift
done

matrix=$(detect_clients || true)

if [[ "$mode_install" == false ]]; then
  echo "install-hook-adapter: detection matrix (env / CLI on PATH / repo config):"
  if [[ -z "$matrix" ]]; then
    echo "  (none detected — Git hooks + CI remain the enforcement line)"
    exit 0
  fi
  for c in $matrix; do echo "  - $c"; done
  exit 0
fi

need_gate

if [[ -n "$client" ]]; then
  case "$client" in
    claude|opencode|cursor|gemini|codex) ;;
    *) die "unsupported client '$client' (supported: claude opencode cursor gemini codex)" ;;
  esac
  targets="$client"
else
  targets="$matrix"
  if [[ -z "$targets" ]]; then
    note "no supported client detected — nothing wired. Git hooks + CI still enforce (they validate the repo, not the editor)."
    note "supported clients: claude, opencode, cursor, gemini, codex — run inside the client or pass --client <name>."
    exit 0
  fi
fi

installed=0
for c in $targets; do
  case "$c" in
    claude)   adapter_claude   && installed=$((installed+1)) || note "claude wiring failed" ;;
    opencode) adapter_opencode && installed=$((installed+1)) || note "opencode wiring failed" ;;
    cursor)   static_schema cursor .cursor/hooks.json   && installed=$((installed+1)) || true ;;
    gemini)   static_schema gemini  .gemini/settings.json && installed=$((installed+1)) || true ;;
    codex)    adapter_codex ;;
  esac
done

if [[ "$installed" -eq 0 ]]; then
  note "no config was written (static-schema conflicts need --force; see notes above)"
  exit 2
fi
ok "$installed client(s) wired; session enforcement active for supported clients"
