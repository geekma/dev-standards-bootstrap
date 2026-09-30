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
                                           + UserPromptSubmit/PostToolUse(count) + PreToolUse(check)
                                           + PreToolUse(agent-gate pre-write) + Stop(stop)
  opencode  .opencode/plugins/dev-standards-gate.js
            .opencode/command/gate-check.md
                                            four-stage wiring (v3.64.0, CHG-084):
                                            (1) detect runtimes (PATH CLI + Desktop
                                            bundled CLI, --version each) ->
                                            (2) fetch official plugin docs live
                                            (source URL recorded) ->
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
  [[ -x scripts/agent-gate ]] || die "ADAPTER-E01: scripts/agent-gate not found or not executable — install the enforcement package first (bootstrap --guard)"
  [[ -f scripts/session-gate.sh ]] || die "ADAPTER-E02: scripts/session-gate.sh not found — upgrade the enforcement package (v3.28.0+)"
  bash -n scripts/session-gate.sh || die "ADAPTER-E03: scripts/session-gate.sh fails bash -n"
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
# v3.58.0（REQ-1008）handoff 硬拦：PreToolUse exit 2 = Claude 原生块工具（stderr 回给 Agent）
ensure("PreToolUse", {"matcher": "Bash|Edit|Write|Task|Grep|Glob|Read", "hooks": [{"type": "command", "command": "scripts/session-gate.sh check"}]})

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
for want in ("scripts/session-gate.sh start", "scripts/agent-gate --stage pre-write", "scripts/agent-gate --stage stop", "scripts/session-gate.sh count turn", "scripts/session-gate.sh count tool -", "scripts/session-gate.sh check"):
    if want not in cmds:
        sys.exit(f"missing hook after merge: {want}")
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
    sleep 1
    rm -rf "$PWD/.oc-xdg" 2>/dev/null || true
    rm -f "$PWD/probe-serve.out" "$PWD/probe.pid" "$PWD/probe-run.out" "$PWD/probe-session.json" 2>/dev/null || true
  done
}

oc_ensure_tmp

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
  sleep 1
  if kill -0 -- "-$pid" 2>/dev/null || kill -0 "$pid" 2>/dev/null; then
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    sleep 1
  fi
}

# 版本探测统一走 XDG 重定向（绝不触碰用户真实 opencode 状态；沙箱/CI 亦不因日志写失败而误判缺版本）
oc_ver_of() { # <bin> -> version string
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
      for ((i = 0; i < OC_PROBE_WINDOW; i++)); do
        grep -q "server listening" "$workdir/probe-serve.out" 2>/dev/null && { listened=true; break; }
        sleep 1
      done
      if [[ "$listened" == true ]]; then
        # 免凭据触发 session.created（实证：POST /session 不调用模型）
        curl -s -m 5 -X POST "http://127.0.0.1:$port/session" -H 'content-type: application/json' \
          -d '{}' -o "$workdir/probe-session.json" 2>/dev/null
        [[ -s "$workdir/probe-session.json" ]] || sleep 2
        [[ -s "$workdir/probe-session.json" ]] || { curl -s -m 5 -X POST "http://127.0.0.1:$port/session" \
          -H 'content-type: application/json' -d '{}' -o "$workdir/probe-session.json" 2>/dev/null || true; }
        sleep 3
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
  sleep 1
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
        win="$OC_PROBE_WINDOW"; [[ "$attempt" != 1 ]] && win=$((win * attempt))
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
  for u in $OC_DOCS_URLS; do
    if curl -fsSL -m 8 "$u" -o "$OC_TMP/docs.html" 2>/dev/null && [[ -s "$OC_TMP/docs.html" ]]; then
      contract_source="$u (fetched live at install time; shape cross-checked by runtime probes)"
      break
    fi
  done
  # 候选集：AI 安装会话可经 DEV_STANDARDS_OPENCODE_CONTRACT（JSON）注入候选序与来源；
  # 缺省用内置候选序。无论来源，最终形状一律由真加载探测裁决——候选不是真理，探针才是。
  local candidates="dual-active server-only setup-v2"
  if [[ -n "${DEV_STANDARDS_OPENCODE_CONTRACT:-}" ]] && command -v python3 >/dev/null 2>&1; then
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
//   message.part.updated -> session-gate.sh count tool <name>   (exploration budget)
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
  const countTool = async (tool) => {
    try {
      const res = await $`bash scripts/session-gate.sh count tool ${tool}`.cwd(directory).nothrow().quiet()
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
          if (p && p.type === "tool" && p.tool) await countTool(p.tool)
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
const _ocRun = (dir, args) => new Promise((resolve) => {
  _ocExecFile("bash", ["scripts/session-gate.sh", ...args], { cwd: dir, timeout: 15000 }, (err, stdout) => {
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
            try {
              const p = ev.properties && ev.properties.part
              if (p && p.type === "tool" && p.tool) tool = p.tool
            } catch {}
            if (tool) _ocRun(dir, ["count", "tool", tool]).then((r) => _ocRelay(ctx, r.out)).catch(() => {})
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

  # ④ 逐 runtime 真加载仲裁（REQ-1039 / DES-1827）
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
  while IFS='|' read -r fkind fver fbin; do
    [[ -z "$fkind" ]] && continue
    fv=""; fdetail=""
    pv="$(oc_probe "$fkind" "$fbin" "$PWD")"
    fv="${pv%%|*}"; fdetail="${pv#*|}"
    sleep 2
    if [[ "$tag_supported" == true ]]; then
      advanced="$(grep -F "probe-tag: $oc_session_tag" .agent-state/session-gate-last.md 2>/dev/null | head -1 || true)"
    else
      advanced="$(find .agent-state -maxdepth 1 \( -name 'session-gate-last.md' -o -name 'session-started.json' \) -newer "$OC_TMP/final-marker" 2>/dev/null | head -1 || true)"
    fi
    if [[ "$fv" == "PASS" && -n "$advanced" ]]; then
      final_results="$final_results $fkind=$fver:PASS(function)"
    else
      # 一次加窗重试（真实 start 可能慢于探测窗：audit --only-fail 耗时随仓大小浮动）
      pv="$(OC_PROBE_WINDOW=$((OC_PROBE_WINDOW * 2)) oc_probe "$fkind" "$fbin" "$PWD")"
      fv="${pv%%|*}"; fdetail="${pv#*|}"
      sleep 3
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
  # 清扫终验探针在真实仓根留下的临时痕（.oc-xdg/probe-*）——成功与失败路径共用
  oc_clean_repo_litter
  OC_WROTE=true
  oc_cleanup
  ok "opencode -> $OPENCODE_PLUGIN + $OPENCODE_COMMAND written + runtime-verified:$final_results (shape=$OC_WINNER; source=$contract_source)"
}

# ---------- cursor / gemini：静态 schema（保守保留 v3.17 行为，diff + --force） ----------
static_schema() { # name path
  local tool="$1" path="$2" content=""
  case "$tool" in
    cursor) content='{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "command": "scripts/session-gate.sh start" }
    ],
    "beforeSubmitPrompt": [
      { "command": "scripts/session-gate.sh count turn" }
    ],
    "postToolUse": [
      { "matcher": "Shell|Read|Grep|Task", "command": "scripts/session-gate.sh count tool -" }
    ],
    "preToolUse": [
      { "matcher": "Write", "command": "scripts/agent-gate --stage pre-write" },
      { "matcher": "Shell|Write|Task|Grep|Read", "command": "scripts/session-gate.sh check" }
    ],
    "stop": [
      { "command": "scripts/agent-gate --stage stop" }
    ]
  }
}'
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
  python3 -m json.tool "$path" >/dev/null 2>&1 || die "ADAPTER-E06: $tool -> $path is not valid JSON after write"
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detect) mode_install=false ;;
    --client) client="${2:-}"; [[ -n "$client" ]] || die "ADAPTER-E07: --client requires a name"; shift ;;
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
    *) die "ADAPTER-E08: unsupported client '$client' (supported: claude opencode cursor gemini codex)" ;;
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
    opencode)
      OC_WROTE=false
      if adapter_opencode; then
        [[ "$OC_WROTE" == true ]] && installed=$((installed+1))
      else
        note "opencode wiring failed"
      fi ;;
    cursor)   static_schema cursor .cursor/hooks.json   && installed=$((installed+1)) || true ;;
    gemini)   no_hook_surface gemini ;;
    codex)    adapter_codex ;;
  esac
done

if [[ "$installed" -eq 0 ]]; then
  note "no config was written (static-schema conflicts need --force; see notes above)"
  exit 2
fi
ok "$installed client(s) wired; session enforcement active for supported clients"
ok ".agent-state/ is runtime state (telemetry/audit reports), NOT a governance artifact — add it to .gitignore; probe scratch .oc-xdg/ likewise (residue guard)"
