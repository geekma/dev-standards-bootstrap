#!/usr/bin/env bash
# suite-03-session.sh — domain suite module (v4.13.0, CHG-158)

section_T26() {
# ------------------------------------------------ T26 session telemetry (v3.39.0)
new_repo
SESSION_GATE_SRC="$ROOT/resources/templates/session-gate.sh"
if [[ -f "$SESSION_GATE_SRC" ]]; then
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  bash scripts/session-gate.sh start >/dev/null 2>&1
  report "T26 telemetry files reset by start" 0 "$(test -s .agent-state/session-tool-stats.json && test -s .agent-state/session-water.json; echo $?)"
  bash scripts/session-gate.sh count turn >/dev/null 2>&1
  bash scripts/session-gate.sh count turn >/dev/null 2>&1
  check_output "T26 turn count lands in water file" '"turns":2' "$(cat .agent-state/session-water.json)"
  bash scripts/session-gate.sh count tool Bash >/dev/null 2>&1
  bash scripts/session-gate.sh count tool Grep >/dev/null 2>&1
  check_output "T26 tool counts classified" '"bash":1,"grep":1' "$(cat .agent-state/session-tool-stats.json)"
  printf '{"tool_name":"Read"}\n' | bash scripts/session-gate.sh count tool - >/dev/null 2>&1
  check_output "T26 stdin tool_name parsed (PostToolUse shape)" '"other":1' "$(cat .agent-state/session-tool-stats.json)"
  out=$(AGENT_GUARD_SESSION_TURN_LIMIT=3 bash scripts/session-gate.sh count turn 2>&1)
  check_output "T26 turn-limit warning emitted" "TURN LIMIT" "$out"
  for i in $(seq 1 25); do bash scripts/session-gate.sh count tool bash >/dev/null 2>&1; done
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T26 exploration yellow light on status" "bash calls 26 > 20" "$out"
  out=$(bash scripts/session-gate.sh idle 2>&1 || true)
  check_output "T26 idle carries yellow light" "bash calls 26 > 20" "$out"
  out=$(AGENT_GUARD_SESSION_TURN_LIMIT=5 bash scripts/session-gate.sh count turn 2>&1)
  if grep -q "TURN LIMIT" <<< "$out"; then report "T26 under-limit stays silent" 1 0; else report "T26 under-limit stays silent" 0 0; fi
  # ---- v3.90.1 (CHG-123, P0-15): token / model / context metering ----------
  rm -f .agent-state/model-profile.json
  out=$(bash scripts/session-gate.sh start 2>&1)
  check_output "T26 cost: unknown model flags assumed window" "WARN — context window unverified" "$out"
  check_output "T26 cost: assumed window is conservative 128000" '"context_window":128000,"source":"assumed"' "$(cat .agent-state/model-profile.json)"
  AGENT_GUARD_MODEL=m1 AGENT_GUARD_CONTEXT_WINDOW=64000 bash scripts/session-gate.sh start >/dev/null 2>&1
  check_output "T26 cost: env declares model+window" '"context_window":64000,"source":"declared"' "$(cat .agent-state/model-profile.json)"
  check_output "T26 cost: stats carries model+window keys" '"model_id":"m1","ctx_window":64000' "$(cat .agent-state/session-tool-stats.json)"
  # v3.91.6: v3.91.2's honesty rule requires BOTH in/out to claim "measured";
  # the fixture used to set only TOKENS_IN and now lands in "不可测".
  out=$(AGENT_GUARD_MODEL=m2 AGENT_GUARD_CONTEXT_WINDOW=32000 AGENT_GUARD_TOKENS_IN=25600 AGENT_GUARD_TOKENS_OUT=1 bash scripts/session-gate.sh count tool Bash "echo x" 2>&1)
  check_output "T26 cost: model switch recomputes (80% => H2)" "used≈80%, H2" "$out"
  check_output "T26 cost: transition row appended" "m1	m2	64000	32000" "$(cat .agent-state/model-transitions.tsv)"
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T26 cost: status prints cost line" "- 成本：model=m2 窗口=32000（source=declared）已用≈80%（H2）" "$out"
  printf '{"turns":3,"bash":1,"grep":0,"other":2,"total":3,"updated_at":"2020-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  bash scripts/session-gate.sh count tool Bash "ls" >/dev/null 2>&1
  check_output "T26 cost: old-schema stats stay readable" '"turns":3' "$(cat .agent-state/session-tool-stats.json)"
  check_output "T26 cost: old-schema gains ctx_window key" '"ctx_window":' "$(cat .agent-state/session-tool-stats.json)"
  # ---- v3.90.1 (CHG-123, P0-11): full_suite counts BUSINESS regressions only
  printf 'full_test_patterns: mvn test,tests/run-tests.sh\n' > .agent-governance.yml
  printf '{"turns":0,"bash":0,"grep":0,"other":0,"sleep_polls":0,"full_suite":0,"total":0,"edits":0,"updated_at":"2020-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  bash scripts/session-gate.sh count tool Bash "bash tests/run-tests.sh" >/dev/null 2>&1
  check_output "T26 full_suite ignores governance self-test" '"full_suite":0' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh count tool Bash "mvn test" >/dev/null 2>&1
  check_output "T26 full_suite counts business regression" '"full_suite":1' "$(cat .agent-state/session-tool-stats.json)"
  # ---- v4.5.0 (CHG-149, REQ-1391): missing updated_at must not overflow to ~29M minutes
  printf '{"full_suite":2}\n' > .agent-state/session-tool-stats.json
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T26 TC-10019 empty updated_at reports uninitialized (no epoch overflow)" "telemetry uninitialized" "$out"
  # ---- v4.5.0 (CHG-149, REQ-1389): dynamic adapter contract & verify-wiring
  if [[ -s "$ROOT/resources/templates/install-hook-adapter.sh" ]]; then
    out=$(bash "$ROOT/resources/templates/install-hook-adapter.sh" --print-contract 2>&1)
    check_output "T26 TC-10016 --print-contract emits 3-event contract" '"PreToolUse"' "$out"
    mkdir -p .agents
    printf '{"dev-standards":{"PreToolUse":[{"matcher":"write_file","hooks":[{"type":"command","command":"bash scripts/agent-gate --stage pre-write"}]}]}}\n' > .agents/hooks.json
    out=$(bash "$ROOT/resources/templates/install-hook-adapter.sh" --verify-wiring .agents/hooks.json 2>&1)
    check_output "T26 TC-10017 --verify-wiring accepts valid .agents/hooks.json" "dynamic wiring verified" "$out"
    out=$(bash "$ROOT/resources/templates/install-hook-adapter.sh" --print-global-contract 2>&1)
    check_output "T26 TC-10032 --print-global-contract emits user-global-cross-workspace" '"user-global-cross-workspace"' "$out"
    check_output "T26 TC-10042 --print-global-contract resolves paths.scripts" 'paths:' "$out"
    _t26_gc_repo=$(mktemp -d)
    (
      cd "$_t26_gc_repo" && git init -q && mkdir -p tools src
      printf 'paths:\n  scripts: tools\n' > .agent-governance.yml
      printf '#!/usr/bin/env bash\necho "ROUTED_TOOLS:$*"\n' > tools/agent-gate
      chmod +x tools/agent-gate
      touch src/app.sh
    )
    _t26_gc_sh=$(mktemp)
    printf '%s\n' "$out" | awk '
      /"router_script": \[/ { in_rs=1; next }
      in_rs && /^[[:space:]]*\]/ { exit }
      in_rs {
        s=$0
        sub(/^[[:space:]]*"/, "", s)
        sub(/",?[[:space:]]*$/, "", s)
        gsub(/\\\\/, "\001", s)
        gsub(/\\"/, "\"", s)
        gsub(/\001/, "\\", s)
        print s
      }
    ' > "$_t26_gc_sh"
    _t26_gc_out=$(bash "$_t26_gc_sh" "$_t26_gc_repo/src/app.sh" 2>&1)
    check_output "T26 TC-10042 global router script executes custom tools/agent-gate" "ROUTED_TOOLS:--stage pre-write --file $_t26_gc_repo/src/app.sh" "$_t26_gc_out"
    rm -rf "$_t26_gc_repo" "$_t26_gc_sh"
    # TC-10036 (v4.6.0 CHG-151, REQ-1411): session-gate start defaults to --incremental audit, --full restores full
    t26_inc=$(mktemp -d)
    mkdir -p "$t26_inc/scripts" "$t26_inc/tests" "$t26_inc/docs/changes/CHG-1" "$t26_inc/docs/changes/CHG-2" "$t26_inc/docs/changes/CHG-3" "$t26_inc/docs/changes/CHG-4"
    cp "$ROOT/resources/templates/session-gate.sh" "$t26_inc/scripts/session-gate.sh"
    cp "$ROOT/resources/templates/audit-docs-consistency.sh" "$t26_inc/tests/audit-docs-consistency.sh"
    cp "$ROOT/resources/DEVELOPMENT_STANDARDS.md" "$t26_inc/docs/DEVELOPMENT_STANDARDS.md"
    cp "$ROOT/resources/AGENTS.md" "$t26_inc/AGENTS.md"
    _t26_inc_out=$(cd "$t26_inc" && bash scripts/session-gate.sh start 2>&1)
    check_output "T26 TC-10036 session-gate start defaults to --incremental audit" "incremental: audited" "$(cat "$t26_inc/.agent-state/session-gate-last.md" 2>/dev/null || true)"
    _t26_full_out=$(cd "$t26_inc" && bash scripts/session-gate.sh start --full 2>&1)
    report "T26 TC-10036 session-gate start --full runs without incremental narrowing" 0 "$(grep -c 'incremental: audited' "$t26_inc/.agent-state/session-gate-last.md" 2>/dev/null || true)"
    rm -rf "$t26_inc"
    t26_bin=$(mktemp -d); t26_repo=$(mktemp -d)
    for _cmd in bash awk grep sed date mkdir tr head cat dirname rm mktemp wc cut sort ls env git; do
      _cmd_path=$(command -v "$_cmd" 2>/dev/null || true)
      [[ -n "$_cmd_path" ]] && ln -sf "$_cmd_path" "$t26_bin/$_cmd"
    done
    mkdir -p "$t26_repo/scripts" "$t26_repo/.agents"
    cp "$ROOT/resources/templates/install-hook-adapter.sh" "$t26_repo/scripts/install-hook-adapter"
    copy_gate_to "$t26_repo/scripts" agent-gate
    cp .agents/hooks.json "$t26_repo/.agents/hooks.json"
    out=$(cd "$t26_repo" && PATH="$t26_bin" bash scripts/install-hook-adapter --verify-wiring .agents/hooks.json 2>&1)
    check_output "T26 TC-10026 zero-dep PATH --verify-wiring passes" "dynamic wiring verified" "$out"
    # TC-10046 (v4.7.0 CHG-152, REQ-1421): review-models zero-dep PATH discover/contract/verify
    (cd "$t26_repo" && git init -q && git commit --allow-empty -qm init) >/dev/null 2>&1
    out=$(cd "$t26_repo" && PATH="$t26_bin" bash scripts/agent-gate review-models --discover 2>&1)
    check_output "T26 TC-10046 review-models --discover emits detected_clis" '"detected_clis":' "$out"
    out=$(cd "$t26_repo" && PATH="$t26_bin" bash scripts/agent-gate review-models --print-contract 2>&1)
    check_output "T26 TC-10046 review-models --print-contract emits schema" '"deep_requires_user_approval": true' "$out"
    printf '{"models":[{"id":"opus","tier":"deep","requires_user_approval":false}]}\n' > "$t26_repo/.agent-review-models.json"
    (cd "$t26_repo" && PATH="$t26_bin" bash scripts/agent-gate review-models --verify .agent-review-models.json >/dev/null 2>&1)
    report "T26 TC-10046 zero-dep verify rejects deep model without approval" 2 $?
    printf '{"models":[{"id":"sonnet","tier":"standard"},{"id":"opus","tier":"deep","requires_user_approval":true}]}\n' > "$t26_repo/.agent-review-models.json"
    (cd "$t26_repo" && PATH="$t26_bin" bash scripts/agent-gate review-models --verify .agent-review-models.json >/dev/null 2>&1)
    report "T26 TC-10046 zero-dep verify accepts valid review-models json" 0 $?
    printf '{"broken":
' > "$t26_repo/.agents/hooks.json"
    (cd "$t26_repo" && PATH="$t26_bin" bash scripts/install-hook-adapter --verify-wiring .agents/hooks.json >/dev/null 2>&1)
    report "T26 TC-10026 zero-dep PATH rejects malformed JSON" 2 $?
    printf '{"dev-standards":{"PreToolUse":[{"matcher":"write_file","hooks":[{"type":"command","command":"bash scripts/missing-gate.sh"}]}]}}
' > "$t26_repo/.agents/hooks.json"
    (cd "$t26_repo" && PATH="$t26_bin" bash scripts/install-hook-adapter --verify-wiring .agents/hooks.json >/dev/null 2>&1)
    report "T26 TC-10026 rejects missing wired script" 2 $?
    _t26_ag_tmp=$(mktemp -d)
    mkdir -p "$_t26_ag_tmp/resources/templates"
    cp "$ROOT/resources/templates/agent-gate.sh" "$ROOT/resources/templates/lib-gate-staged.sh" "$ROOT/resources/templates/lib-gate-cold.sh" "$ROOT/resources/templates/lib-json.sh" "$_t26_ag_tmp/resources/templates/"
    ( cd "$_t26_ag_tmp" && git init -q && git config user.email t@t && git config user.name t && git commit --allow-empty -qm init ) >/dev/null 2>&1
    _t26_adv_out=$(cd "$_t26_ag_tmp" && bash resources/templates/agent-gate.sh advance CHG-999 2>&1); _t26_adv_rc=$?
    report "T26 TC-10068 advance fallback invokes agent-gate (not silent cold lib rc=0)" 1 "$([[ "$_t26_adv_rc" -ne 0 ]] && echo 1 || echo 0)"
    check_output "T26 TC-10068 advance fallback fails on begin GATE-E03" "GATE-E03" "$_t26_adv_out"
    rm -rf "$_t26_ag_tmp"
    rm -rf "$t26_bin" "$t26_repo" .agents
  else
    report "T26 TC-10016 --print-contract (skip: template absent)" 0 0
    report "T26 TC-10017 --verify-wiring (skip: template absent)" 0 0
    report "T26 TC-10032 --print-global-contract (skip: template absent)" 0 0
    report "T26 TC-10042 --print-global-contract paths.scripts (skip: template absent)" 0 0
    report "T26 TC-10042 global router script custom tools/agent-gate (skip: template absent)" 0 0
    report "T26 TC-10036 session-gate start --incremental (skip: template absent)" 0 0
    report "T26 TC-10036 session-gate start --full (skip: template absent)" 0 0
    report "T26 TC-10026 zero-dep verify-wiring ok (skip: template absent)" 0 0
    report "T26 TC-10046 review-models --discover (skip: template absent)" 0 0
    report "T26 TC-10046 review-models --print-contract (skip: template absent)" 0 0
    report "T26 TC-10046 review-models rejects unapproved deep (skip: template absent)" 0 0
    report "T26 TC-10046 review-models verifies valid json (skip: template absent)" 0 0
    report "T26 TC-10026 malformed JSON (skip: template absent)" 0 0
    report "T26 TC-10026 missing script (skip: template absent)" 0 0
  fi
  # ---- v4.8.0 (CHG-153): receipts, pre-write ledger, honesty summary, start/advance/next/fix/--json, awk obj id ----
  new_repo
  seed_artifacts CHG-1530 L1 claude/s-1
  mkdir -p src
  scripts/agent-gate begin CHG-1530 >/dev/null 2>&1
  _rf_153=$(git rev-parse --git-path "agent-governance/stage-receipts/CHG-1530.tsv" 2>/dev/null)
  report "T26 TC-10052 begin writes stage-receipts TSV" 0 "$([[ -s "$_rf_153" ]] && grep -qE $'\tbegin\t' "$_rf_153"; echo $?)"
  out=$(scripts/agent-gate next CHG-1530 --json 2>&1)
  check_output "T26 TC-10059 next --json reports spec next_command" '"next_command":"scripts/agent-gate --stage spec"' "$out"
  out=$(scripts/agent-gate status --json 2>&1)
  check_output "T26 TC-10059 status --json includes active_change" '"active_change":"CHG-1530"' "$out"
  out=$(scripts/agent-gate preflight CHG-1530 --json 2>&1)
  check_output "T26 TC-10059 preflight --json returns clean true" '"clean":true' "$out"
  # owner=geek007 deadline=2099-12-31
  out=$(AGENT_GUARD_ADAPT=1 scripts/agent-gate plan CHG-1530 --json 2>&1)
  check_output "T26 TC-10059 plan --json emits engine_version" '"engine_version":' "$out"
  scripts/agent-gate advance CHG-1530 >/dev/null 2>&1
  report "T26 TC-10058 advance progresses through spec gate" 0 "$(grep -qE $'\tspec\t' "$_rf_153"; echo $?)"
  scripts/agent-gate --stage pre-write --file src/a.js >/dev/null 2>&1
  report "T26 TC-10054 pre-write records pass in ledger" 0 "$(grep -q 'CHG-1530' .agent-state/pre-write-ledger.tsv 2>/dev/null; echo $?)"
  echo 'x' > src/a.js
  touch -t 202001010000 src/a.js 2>/dev/null || true
  out=$(scripts/agent-gate dispatch review CHG-1530 --json 2>&1)
  check_output "T26 TC-10055 dispatch review injects process honesty summary" 'pre_write_hook_observed=yes' "$out"
  printf '\n- REQ-999: extra req for fix\n' >> docs/changes/CHG-1530/01-spec.md
  printf '# 09\n- **Observation**：fix test\n' > docs/changes/CHG-1530/09-changelog.md
  scripts/agent-gate fix CHG-1530 >/dev/null 2>&1
  report "T26 TC-10060 fix backfills P00-P12 and missing REQ in 01.5" 0 "$(grep -q 'REQ-999' docs/changes/CHG-1530/01.5-rtvm-matrix.md && grep -q 'P12' docs/changes/CHG-1530/09-changelog.md; echo $?)"
  scripts/agent-gate start CHG-1531 --risk L2 >/dev/null 2>&1
  report "T26 TC-10057 start scaffolds CHG-1531 directory" 0 "$([[ -s docs/changes/CHG-1531/00-intent.md ]]; echo $?)"
  # FU-15202 review-models awk fallback checks id per object
  _rm_bin=$(mktemp -d)
  for _c in bash awk grep sed date mkdir tr head cat dirname rm mktemp wc cut sort ls env git; do
    _cp=$(command -v "$_c" 2>/dev/null || true); [[ -n "$_cp" ]] && ln -sf "$_cp" "$_rm_bin/$_c"
  done
  printf '{"models":[{"id":"ok1","tier":"fast"},{"tier":"standard"}]}\n' > .agent-review-models.json
  PATH="$_rm_bin" bash scripts/agent-gate review-models --verify .agent-review-models.json >/dev/null 2>&1
  report "T26 TC-10062 awk fallback rejects second model object missing id" 2 $?
  rm -rf "$_rm_bin" .agent-review-models.json
  # TC-10070 (ITEM-47): agent-gate doctor [--json]
  out=$(bash scripts/agent-gate doctor --json 2>&1); rc=$?
  report "T26 TC-10070 doctor --json passes on clean fixture" 0 "$rc"
  check_output "T26 TC-10070 doctor --json reports zero failures" '"failed":0' "$out"
  mkdir -p .git/agent-governance && echo "CHG-NOEXIST" > .git/agent-governance/active-change
  out=$(bash scripts/agent-gate doctor --json 2>&1); rc=$?
  report "T26 TC-10070 doctor --json exits 1 on dangling active-change" 1 "$rc"
  check_output "T26 TC-10070 doctor names failing check and fix" 'scripts/agent-gate start CHG-NOEXIST' "$out"
  rm -f .git/agent-governance/active-change
  # TC-10071 (ITEM-48): agent-gate metrics --summary [--json]
  out=$(bash scripts/agent-gate metrics --summary 2>&1); rc=$?
  report "T26 TC-10071 metrics --summary exits 0" 0 "$rc"
  check_output "T26 TC-10071 metrics --summary prints summary header" 'metrics summary:' "$out"
  out=$(bash scripts/agent-gate metrics --summary --json 2>&1); rc=$?
  report "T26 TC-10071 metrics --summary --json emits valid fields" 0 "$rc"
  check_output "T26 TC-10071 metrics --summary --json carries delivery_ready" '"delivery_ready":' "$out"
  # TC-10075 (ITEM-52): scripts/mcp-governance-server.sh --self-test & stdio tools/call
  if [[ -f "$ROOT/scripts/mcp-governance-server.sh" ]]; then
    bash "$ROOT/scripts/mcp-governance-server.sh" --self-test >/dev/null 2>&1
    report "T26 TC-10075 mcp-governance-server --self-test passes" 0 $?
    out=$(bash "$ROOT/scripts/mcp-governance-server.sh" <<< '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"governance_status","arguments":{}}}' 2>&1); rc=$?
    report "T26 TC-10075 mcp-governance-server tools/call governance_status rc0" 0 "$rc"
    check_output "T26 TC-10075 mcp response includes enforcement_mode" 'enforcement_mode' "$out"
    out=$(bash "$ROOT/scripts/mcp-governance-server.sh" --print-config 2>&1)
    check_output "T26 TC-10075 --print-config emits mcpServers JSON" '"mcpServers":' "$out"
  fi
  rm -f .agent-governance.yml
else
  echo "SKIP T26: session-gate.sh absent — 跳过会话遥测 golden cases"
fi

}

section_T26b() {
# ------------------------------------------------ T26b gate cost line (v3.90.1, CHG-123 P0-15)
new_repo
SG26B="$ROOT/resources/templates/session-gate.sh"
GT26B="$ROOT/resources/templates/agent-gate.sh"
if [[ -s "$SG26B" && -s "$GT26B" ]]; then
  cp "$SG26B" scripts/session-gate.sh
  copy_gate_to scripts agent-gate
  chmod +x scripts/session-gate.sh scripts/agent-gate
  seed_artifacts CHG-930 L1 claude/s-26b
  printf '# 09\n' > docs/changes/CHG-930/09-changelog.md
  bash scripts/session-gate.sh start >/dev/null 2>&1
  bash scripts/session-gate.sh count tool Bash "echo x" >/dev/null 2>&1
  out=$(scripts/agent-gate cost-line CHG-930 2>&1); rc=$?
  report "T26b cost-line exits 0" 0 "$rc"
  check_output "T26b cost line lands in 09" "本次执行成本" "$(cat docs/changes/CHG-930/09-changelog.md)"
  before=$(grep -c '本次执行成本' docs/changes/CHG-930/09-changelog.md || true)
  scripts/agent-gate cost-line CHG-930 >/dev/null 2>&1
  after=$(grep -c '本次执行成本' docs/changes/CHG-930/09-changelog.md || true)
  report "T26b cost line idempotent per session" 0 "$(( after - before ))"
  out=$(scripts/agent-gate cost-line 2>&1 || true)
  check_output "T26b missing change id dies E132" "GATE-E132" "$out"
  report "T26b session-gate mirror byte-identical" 0 "$(cmp -s scripts/session-gate.sh "$SG26B"; echo $?)"
  report "T26b agent-gate mirror byte-identical" 0 "$(cmp -s scripts/agent-gate "$GT26B"; echo $?)"
else
  echo "SKIP T26b: session-gate.sh/agent-gate.sh absent — 跳过成本行 golden cases"
fi

}

section_T26c() {
# ------------------------------------------------ T26c 等待纪律 + payload 边界（v3.90.1，CHG-123）
# P0-6: AGENTS 纪律 10 forbids blocking waits and names the progress file.
check_output "T26c AGENTS forbids blocking TaskOutput" 'block:true timeout>60s' "$(cat "$ROOT/resources/AGENTS.md")"
# v3.91.9 (CHG-127): count on disk instead of piping the 60KB body through
# check_output — the pipe closed early (SIGPIPE) and the second assertion read
# an empty capture in CI while the file did contain the token.
report "T26c AGENTS names the progress file" 1 "$(grep -c 'suite-progress\.json' "$ROOT/resources/AGENTS.md" 2>/dev/null || printf 0)"
# P0-16: no S-layer path may appear inside a P-layer (installed) document.
# SKILL.md is the skill's own installer guide (source side), so it is NOT scanned;
# the payload face is what a target repo receives.
S16=$(mktemp -d "${TMPDIR:-/tmp}/payload.XXXXXX")
for f in "$ROOT/resources/AGENTS.md" "$ROOT/resources/DEVELOPMENT_STANDARDS.md" "$ROOT"/resources/templates/*.md; do
  [[ -f "$f" ]] && cp "$f" "$S16/" 2>/dev/null || true
done
hits=$(grep -hoE '(scripts/(bootstrap|facts|verify-all|selfcheck|lib-source-facts)|tests/audit-standards-src)\.sh' "$S16"/*.md 2>/dev/null | wc -l | tr -d ' ')
report "T26c P-layer docs never reference S-layer paths" 0 "$hits"
rm -rf "$S16"
# ---- P0-1: runtime probe (protocol family) + unknown => exit 3 + handshake ----
R16=$(mktemp -d "${TMPDIR:-/tmp}/runtime.XXXXXX")
mkdir -p "$R16/scripts"
cp "$ROOT/resources/templates/install-hook-adapter.sh" "$R16/scripts/" 2>/dev/null || true
copy_gate_to "$R16/scripts" agent-gate 2>/dev/null || true
# Strip client CLIs from PATH so "unknown" is reachable on a dev machine that
# happens to have them installed (the probe must key on shapes, not on my laptop).
# Also drop the agent-session env markers: when the suite is launched from inside
# a Claude Code / OpenCode / Cursor / Gemini / Codex session the probe would
# otherwise hit its env branch and never reach "unknown" (CHG-158 round-2).
r16_out=$( cd "$R16" && env -u CLAUDECODE -u OPENCODE -u OPENCODE_SESSION_ID -u CURSOR_AGENT -u CURSOR_TRACE_ID -u GEMINI_CLI -u CODEX_HOME PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 ); r16_rc=$?
report "T26c unknown runtime exits 3 (never silent success)" 3 "$r16_rc"
check_output "T26c unknown runtime names the effective layers" 'Git hooks \+ CI only' "$r16_out"
mkdir -p "$R16/.claude"
r16_out=$( cd "$R16" && PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 ); r16_rc=$?
report "T26c known runtime exits 0" 0 "$r16_rc"
check_output "T26c runtime classified by family, not name" 'claude \(json-hooks\)' "$r16_out"
check_output "T26c runtime ledger written" '"family":"json-hooks"' "$(cat "$R16/.agent-state/runtime.json" 2>/dev/null)"
printf '{"runtime_id":"opencode","family":"plugin-api","clients":"opencode","generated_at":"x"}\n' > "$R16/.agent-state/runtime.json"
r16_out=$( cd "$R16" && PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 )
check_output "T26c runtime transition recorded" 'runtime changed' "$r16_out"
check_output "T26c handshake file written" '"runtime":' "$( cd "$R16" && git init -q . && bash scripts/agent-gate session-start >/dev/null 2>&1; cat "$R16"/.agent-state/runtime/*.json 2>/dev/null )"
rm -rf "$R16"
# ---- P0-7: every gate refusal carries expected / allowed / fix / ref -------
r16_out=$( cd "$R16" 2>/dev/null; printf '' )
G16="$ROOT/resources/templates/lib-gate-staged.sh"
[[ -s "$G16" ]] || G16="$ROOT/scripts/lib-gate-staged.sh"
check_output "T26c die hints carry expected" 'expected:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
check_output "T26c die hints carry allowed" 'allowed:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
check_output "T26c die hints carry fix" 'fix:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
check_output "T26c die hints carry ref" 'ref:' "$(sed -n '/^gate_hint()/,/^}/p' "$G16")"
R17=$(mktemp -d "${TMPDIR:-/tmp}/four.XXXXXX"); mkdir -p "$R17/scripts"
copy_gate_to "$R17/scripts" agent-gate
r17_out=$( cd "$R17" && git init -q . && bash scripts/agent-gate begin CHG-404 2>&1 || true )
check_output "T26c refusal prints the four elements" 'expected:.*' "$r17_out"
check_output "T26c refusal names a fix command" '^fix:' "$r17_out"
check_output "T26c refusal points at a clause" '^ref:' "$r17_out"
rm -rf "$R17"
# review CHG-123 #3/#6 pins: bad --since ref is a usage error; probe switch is a
# real single switch back to legacy detection.
"$ROOT/tests/audit-docs-consistency.sh" --since no-such-ref-xyz >/dev/null 2>&1
report "T26c --since with an unresolvable ref exits 2" 2 $?
r17_out=$( cd "$R16" 2>/dev/null; printf '' )
R18=$(mktemp -d "${TMPDIR:-/tmp}/probe0.XXXXXX"); mkdir -p "$R18/scripts"
cp "$ROOT/resources/templates/install-hook-adapter.sh" "$R18/scripts/"
( cd "$R18" && PATH=/usr/bin:/bin AGENT_GUARD_RUNTIME_PROBE=0 bash scripts/install-hook-adapter.sh --detect >/dev/null 2>&1 ); r18_rc=$?
report "T26c AGENT_GUARD_RUNTIME_PROBE=0 restores legacy exit 0" 0 "$r18_rc"
rm -rf "$R18"

}

section_T64() {
  local t64 rc out
  t64=$(mktemp -d "${TMPDIR:-/tmp}/t64.XXXXXX")
  (cd "$t64" && git init -q && git config user.email t@x.invalid && git config user.name t)
  out=$(cd "$t64" && AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash "$GATE_SRC" begin t1 --scaffold 2>&1); rc=$?
  report "T64 TC-1400 scaffold runs clean (rc=0)" 0 "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  report "T64 TC-1400 scaffold reports created 9" 1 "$(printf '%s\n' "$out" | grep -c 'created 9, member-appended 0')"
  report "T64 TC-1400 member anchors in 8 md artifacts" 8 "$(grep -l '^## t1' "$t64"/docs/changes/BATCH-*/0*.md 2>/dev/null | wc -l | tr -d ' ')"
  for tf in "$t64"/docs/changes/BATCH-*/00-intent.md "$t64"/docs/changes/BATCH-*/00.5-communication.md "$t64"/docs/changes/BATCH-*/01-spec.md "$t64"/docs/changes/BATCH-*/02-code-impact-analysis.md "$t64"/docs/changes/BATCH-*/03-modification-plan.md "$t64"/docs/changes/BATCH-*/03.5-tasks.md "$t64"/docs/changes/BATCH-*/04-test-scripts.md; do
  sed -i '' 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf" 2>/dev/null || sed -i 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf"
  done
  for tf in "$t64"/docs/changes/BATCH-*/00.5-communication.md "$t64"/docs/changes/BATCH-*/00-intent.md "$t64"/docs/changes/BATCH-*/01-spec.md "$t64"/docs/changes/BATCH-*/02-code-impact-analysis.md "$t64"/docs/changes/BATCH-*/03-modification-plan.md "$t64"/docs/changes/BATCH-*/03.5-tasks.md "$t64"/docs/changes/BATCH-*/04-test-scripts.md; do
  sed -i '' 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf" 2>/dev/null || sed -i 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf"
  done
  (cd "$t64" && AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash "$GATE_SRC" begin t1 >/dev/null 2>&1); rc=$?
  report "T64 TC-1400 filled scaffold passes begin (rc=0)" 0 "$rc"
  # TC-1400b (评审 F1/F7): same-day second member — gov.json stays bare-object
  # parseable (no markdown injection between JSON objects) and begin reads the
  # member's OWN governance record (risk_level/owners), not a sibling's.
  out=$(cd "$t64" && bash "$GATE_SRC" begin t9 --risk L1 --scaffold 2>&1); rc=$?
  report "T64 TC-1400b second member appends 9 (created 0)" 1 "$(printf '%s\n' "$out" | grep -c 'created 0, member-appended 9')"
  for tf in "$t64"/docs/changes/BATCH-*/00.5-communication.md "$t64"/docs/changes/BATCH-*/00-intent.md "$t64"/docs/changes/BATCH-*/01-spec.md "$t64"/docs/changes/BATCH-*/02-code-impact-analysis.md "$t64"/docs/changes/BATCH-*/03-modification-plan.md "$t64"/docs/changes/BATCH-*/03.5-tasks.md "$t64"/docs/changes/BATCH-*/04-test-scripts.md; do
  sed -i '' 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf" 2>/dev/null || sed -i 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf"
  done
  (cd "$t64" && AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash "$GATE_SRC" begin t9 >/dev/null 2>&1); rc=$?
  report "T64 TC-1400b second member begin passes (gov_record per-member)" 0 "$rc"
  out=$(cd "$t64" && bash "$GATE_SRC" begin t1 --scaffold 2>&1); rc=$?
  report "T64 TC-1401 re-scaffold same id refuses (E121)" 0 "$([[ $rc -ne 0 ]] && grep -q 'GATE-E121' <<< "$out" && echo 0 || echo 1)"
  mkdir -p "$t64/docs/changes/t1c" && echo x > "$t64/docs/changes/t1c/junk.md"
  out=$(cd "$t64" && bash "$GATE_SRC" begin t1c --risk L2 --scaffold 2>&1); rc=$?
  report "T64 TC-1401 non-empty dedicated dir refuses (E120)" 0 "$([[ $rc -ne 0 ]] && grep -q 'GATE-E120' <<< "$out" && echo 0 || echo 1)"
  (cd "$t64" && bash "$GATE_SRC" begin t2 --risk L2 --scaffold >/dev/null 2>&1); rc=$?
  report "T64 TC-1402 L2 lands dedicated dir (not BATCH)" 0 "$([[ $rc -eq 0 && -f "$t64/docs/changes/t2/00-intent.md" ]] && echo 0 || echo 1)"
  report "T64 TC-1403 AGENTS carries the phase read-set discipline" 1 "$(grep -c '分阶段最小读集（v3.80.0' "$ROOT/resources/AGENTS.md")"
  report "T64 TC-1403 CLAUSE_REGISTRY registers R65" 1 "$(grep -c '^| R65 ' "$ROOT/resources/CLAUSE_REGISTRY.md")"
  report "T64 TC-1403 DS carries the read-set pointer line" 1 "$(grep -c '分阶段最小读集（v3.77.0/v3.80.0，CHG-101/107，REQ-1124/1125/1153）' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
  report "T64 TC-1404 gate usage names --scaffold" 1 "$(cat "$GATE_SRC" "$(dirname "$GATE_SRC")/lib-gate-staged.sh" | grep -c 'begin <change-id> \[--risk L0|L1|L2|L3\] \[--scaffold\]')"
}

section_T27() {
# ------------------------------------------------ T27 pre-commit auto-stamp (v3.40.0)
new_repo
STAMP_SRC="$ROOT/resources/templates/stamp-provenance.sh"
HOOK_SRC="$ROOT/resources/templates/pre-commit"
if [[ -f "$STAMP_SRC" && -f "$HOOK_SRC" ]]; then
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  mkdir -p .githooks && cp "$HOOK_SRC" .githooks/pre-commit
  chmod +x .githooks/pre-commit scripts/stamp-provenance.sh scripts/agent-gate
  # TC-1070 (v3.61.2 REQ-1017): template carries the stamp-backfill logic
  bash -n "$HOOK_SRC"
  report "T27 TC-1070 template syntax" 0 $?
  report "T27 TC-1070 captures stamp file list" 2 "$(grep -cF 'stamped"||$1=="trace-derive' "$HOOK_SRC")"
  report "T27 TC-1070 strips blocks before compare" 1 "$(grep -cF 'trace-derive begin' "$HOOK_SRC")"
  report "T27 TC-1070 backfills via git add" 1 "$(grep -cF 'git add -- "$f"' "$HOOK_SRC")"
  report "T27 TC-1070 warns on beyond-stamp skip" 1 "$(grep -cF 'skip index backfill' "$HOOK_SRC")"
  seed_begin CHG-940 L1 claude/s-27
  report "T27 fixture begins clean" 0 $?
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 pre-commit exits 0 (stamp + staged)" 0 $?
  check_output "T27 hook stamped provenance block" "generated_by: stamp-provenance.sh" "$(cat docs/changes/CHG-940/00-intent.md)"
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 idempotent rerun keeps a single block" 1 "$(grep -c '^<!-- provenance$' docs/changes/CHG-940/00-intent.md | tr -d ' ')"
  scripts/agent-gate end >/dev/null 2>&1
  out=$(bash .githooks/pre-commit 2>&1 || true)
  if grep -q "stamping provenance" <<< "$out"; then report "T27 skip path prints no stamping line" 1 0; else report "T27 skip path prints no stamping line" 0 0; fi
  # bug_ref binding: the hook stamps the bound defect group too
  mkdir -p docs/bugs/BUG-940
  for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
    printf '# %s\n' "$doc" > "docs/bugs/BUG-940/$doc"
  done
  append_diag_lines docs/bugs/BUG-940/01-diagnosis.md
  sed -i '' 's/}$/,"bug_ref":"BUG-940"}/' docs/changes/CHG-940/00-governance.json 2>/dev/null \
    || sed -i 's/}$/,"bug_ref":"BUG-940"}/' docs/changes/CHG-940/00-governance.json
  scripts/agent-gate begin CHG-940 >/dev/null 2>&1
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 hook exits 0 with bug_ref bound" 0 $?
  check_output "T27 bound defect group stamped" "generated_by: stamp-provenance.sh" "$(cat docs/bugs/BUG-940/01-diagnosis.md)"
  # comma-joined batch governance (the §1.1 recommended shape): each member's
  # bug_ref must be extracted in isolation — no cross-member bleed
  mkdir -p docs/bugs/BUG-943 docs/bugs/BUG-944
  for b in 943 944; do for doc in 01-diagnosis.md 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do printf '# %s\n' "$doc" > "docs/bugs/BUG-$b/$doc"; done; append_diag_lines "docs/bugs/BUG-$b/01-diagnosis.md"; done
  mkdir -p docs/changes/BATCH-990922
  printf '{"change_id":"CHG-943","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-943"}{"change_id":"CHG-944","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-944"}\n' > docs/changes/BATCH-990922/00-governance.json
  seed_begin CHG-944 L0 claude/s-27
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 hook exits 0 on comma-joined batch member" 0 $?
  check_output "T27 member bug_ref stamped in isolation" "generated_by: stamp-provenance.sh" "$(cat docs/bugs/BUG-944/01-diagnosis.md)"
  if grep -q '^<!-- provenance$' docs/bugs/BUG-943/01-diagnosis.md; then report "T27 no cross-member bleed" 1 0; else report "T27 no cross-member bleed" 0 0; fi
  # TC-1071 (v3.61.2 REQ-1017): index backfill — tracked file's stamp is re-staged
  # so the commit itself carries the stamp (kills the post-commit residue loop).
  # Active change is CHG-944 (seed_begin switched it); --all stamps its own dir.
  git add docs/changes/CHG-944/00-intent.md
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 TC-1071 backfill: no unstaged delta after hook (stamp re-staged)" 0 "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
  # TC-1072 (v3.61.2 REQ-1017): partial staging preserved — a delta beyond the
  # stamp (e.g. git add -p leftovers) blocks the backfill and warns (fail-open)
  printf '\nunstaged-extra-line\n' >> docs/changes/CHG-944/00-intent.md
  out=$(bash .githooks/pre-commit 2>&1 || true)
  report "T27 TC-1072 skip warning emitted for beyond-stamp delta" 1 "$(printf '%s' "$out" | grep -cF 'skip index backfill')"
  report "T27 TC-1072 unstaged hunk stays unstaged (not swept into index)" 1 "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
  # TC-2363 (v3.98.1 CHG-138/REQ-1355 review L2): the POSITIVE backfill path
  # under the idempotence regime — first converge index==tree (clears the
  # TC-1072 leftover so it cannot leak into this probe), then poison the INDEX
  # with a stale generated_at while the tree stays a fixed point; the hook must
  # still `git add` (the filter now includes `unchanged`) so the index
  # converges to the tree in one sync (strip strips the timestamp — no chasing).
  git add -- docs/changes/CHG-944/00-intent.md
  _t27_blob=$(sed 's/^generated_at: .*/generated_at: 2000-01-01T00:00:00Z/' docs/changes/CHG-944/00-intent.md \
    | git hash-object -w --stdin)
  git update-index --cacheinfo "100644,$_t27_blob,docs/changes/CHG-944/00-intent.md"
  report "T27 TC-2363 stale-timestamp index delta exists before hook" 1 \
    "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
  bash .githooks/pre-commit >/dev/null 2>&1
  report "T27 TC-2363 unchanged backfill syncs a stale index timestamp" 0 \
    "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
  # TC-1082 (v3.62.1 CHG-081 REQ-1026): iteration-boundary backfill — index holds
  # stamped v1, hook re-stamps v2. Old strip compare swallowed exactly one
  # trailing blank, so any accumulated blank made strips differ and the backfill
  # never ran after the first attempt (the residue loop CHG-079 meant to kill).
  # Normalized compare must restage with no skip warning and no unstaged delta.
  git add docs/changes/CHG-944/00-intent.md
  out=$(bash .githooks/pre-commit 2>&1 || true)
  report "T27 TC-1082 no skip warning at iteration boundary" 0 "$(printf '%s' "$out" | grep -cF 'skip index backfill')"
  report "T27 TC-1082 restamp swept back into index (no unstaged delta)" 0 "$(git diff --name-only -- docs/changes/CHG-944/00-intent.md | wc -l | tr -d ' ')"
else
  echo "SKIP T27: stamp-provenance.sh/pre-commit absent (bootstrap --guard 未安装) — 跳过自动章 golden cases"
fi

}

section_T28() {
# ------------------------------------------------ T28 P3 defect lightweight channel (v3.40.0)
new_repo
seed_artifacts CHG-950 L1 claude/s-28
mkdir -p docs/bugs/BUG-950
printf '# 诊断\nseverity: P3\n现象：文案错别字\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > docs/bugs/BUG-950/01-diagnosis.md
printf '# 防回归\n| TC |\n' > docs/bugs/BUG-950/03-test-plan.md
printf '# 矩阵\n| REQ |\n' > docs/bugs/BUG-950/04-matrix.md
sed -i '' 's/}$/,"bug_ref":"BUG-950"}/' docs/changes/CHG-950/00-governance.json 2>/dev/null \
  || sed -i 's/}$/,"bug_ref":"BUG-950"}/' docs/changes/CHG-950/00-governance.json
scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T28 P3 severity waives 02/05/06 at begin" 0 $?
sed -i '' '/^severity: P3$/d' docs/bugs/BUG-950/01-diagnosis.md 2>/dev/null \
  || sed -i '/^severity: P3$/d' docs/bugs/BUG-950/01-diagnosis.md
scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T28 undeclared severity keeps full six-piece (fail-closed)" 2 $?
printf 'severity: P2\n' >> docs/bugs/BUG-950/01-diagnosis.md
scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T28 non-P3 value keeps full six-piece" 2 $?
# flat batch: severity must live inside the member's own section (same repo —
# standalone BUG-950 and the flat day batch coexist; same-day enforcement for
# the change track only fires when a CHANGE batch exists, none does here)
B9="docs/bugs/BATCH-$(date -u +%Y%m%d)"
mkdir -p "$B9"
printf '# 批次诊断\n## BUG-951\nseverity: P3\n文案\n延伸发现：未发现\n历史相似检索：未命中（x）\n## BUG-952\n无 severity 行\n' > "$B9/01-diagnosis.md"
printf '# 防回归\n## BUG-951\n## BUG-952\n' > "$B9/03-test-plan.md"
printf '# 矩阵\n## BUG-951\n## BUG-952\n' > "$B9/04-matrix.md"
seed_artifacts CHG-951 L1 claude/s-28b
sed -i '' 's/}$/,"bug_ref":"BUG-951"}/' docs/changes/CHG-951/00-governance.json 2>/dev/null \
  || sed -i 's/}$/,"bug_ref":"BUG-951"}/' docs/changes/CHG-951/00-governance.json
scripts/agent-gate begin CHG-951 >/dev/null 2>&1
report "T28 flat P3 severity read from member section" 0 $?
seed_artifacts CHG-952 L1 claude/s-28c
sed -i '' 's/}$/,"bug_ref":"BUG-952"}/' docs/changes/CHG-952/00-governance.json 2>/dev/null \
  || sed -i 's/}$/,"bug_ref":"BUG-952"}/' docs/changes/CHG-952/00-governance.json
scripts/agent-gate begin CHG-952 >/dev/null 2>&1
report "T28 flat member without severity keeps six-piece" 2 $?

}

section_T29() {
# ------------------------------------------------ T29 session RED blocks new changes (v3.40.0)
new_repo
seed_artifacts CHG-960 L1 claude/s-29
mkdir -p .agent-state
printf '# session-gate 报告\n- GATE RED — stop 未通过\n' > .agent-state/session-gate-last.md
scripts/agent-gate begin CHG-960 >/dev/null 2>&1
report "T29 no changelog baseline degrades fail-open" 0 $?
# a DELIVERED sibling change (its own 09, mtime older than the report) gives the
# comparison a baseline; CHG-960 itself stays open (no 09 of its own)
mkdir -p docs/changes/CHG-959
printf '# changelog\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t |\n' > docs/changes/CHG-959/09-changelog.md
touch -t 202001010000 docs/changes/CHG-959/09-changelog.md
out=$(scripts/agent-gate begin CHG-960 2>&1); rc=$?
report "T29 fresh RED report blocks begin" 2 "$rc"
check_output "T29 refusal names the unresolved red" "session audit RED unresolved" "$out"
check_output "T29 refusal names escape env" "AGENT_GUARD_ALLOW_OVER_RED=1" "$out"
touch -t 201901010000 .agent-state/session-gate-last.md
scripts/agent-gate begin CHG-960 >/dev/null 2>&1
report "T29 stale report passes (delivered after red)" 0 $?
touch -t 203501010000 .agent-state/session-gate-last.md
AGENT_GUARD_ALLOW_OVER_RED=1 scripts/agent-gate begin CHG-960 >/dev/null 2>&1
report "T29 explicit escape passes over red" 0 $?

}

section_T30() {
# ------------------------------------------------ T30 die error codes (v3.40.0)
total_die=$(grep -c 'die "' "$GATE_SRC" || true)
coded_die=$(grep -cE 'die "(GATE|NC|ADAPTER)-E[0-9]+: ' "$GATE_SRC" || true)
report "T30 every gate die carries an Exx code" 0 "$(( total_die - coded_die ))"
out=$(bash "$GATE_SRC" begin CHG-404 2>&1 || true)
check_output "T30 refusal output carries GATE-E" "GATE-E" "$out"
NEWCHANGE_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -f "$NEWCHANGE_SRC" ]]; then
  report "T30 new-change die count equals coded" 0 "$(( $(grep -c 'die "' "$NEWCHANGE_SRC") - $(grep -cE 'die "NC-E[0-9]+: ' "$NEWCHANGE_SRC") ))"
fi
ADAPTER_SRC="$ROOT/resources/templates/install-hook-adapter.sh"
if [[ -f "$ADAPTER_SRC" ]]; then
  report "T30 adapter die count equals coded" 0 "$(( $(grep -c 'die "' "$ADAPTER_SRC") - $(grep -cE 'die "ADAPTER-E[0-9]+: ' "$ADAPTER_SRC") ))"
  grep -q "add it to .gitignore" "$ADAPTER_SRC"
  report "TC-1060 adapter prints .agent-state gitignore hint" 0 $?
fi

}

section_T31() {
# ------------------------------------------------ T31 G10 deprecated-clause sweep (v3.40.0)
AUDIT_SRC="$ROOT/resources/templates/audit-docs-consistency.sh"
if [[ -f "$AUDIT_SRC" ]]; then
  new_repo
  mkdir -p tests
  cp "$AUDIT_SRC" tests/audit-docs-consistency.sh
  mkdir -p docs
  printf '# 规范\n- 旧条款（v3.22.0 废止，改由 v3.35.0 批次）\n- 坏例：旧条款废止，无版本指向\n' > docs/DEVELOPMENT_STANDARDS.md
  printf '# AGENTS\n' > docs/AGENTS.md
  out=$(bash tests/audit-docs-consistency.sh 2>&1 || true)
  check_output "T31 G10 flags pointer-less 废止 marker" "废止标记缺版本指向" "$out"
  printf '# 规范\n- 旧条款（v3.22.0 废止，改由 v3.35.0 批次）\n- 好例：旧条款废止（v3.35.0 起由批次承担）\n' > docs/DEVELOPMENT_STANDARDS.md
  out=$(bash tests/audit-docs-consistency.sh 2>&1 || true)
  if grep -q "废止标记缺版本指向" <<< "$out"; then report "T31 G10 clean spec passes" 1 0; else report "T31 G10 clean spec passes" 0 0; fi
  check_output "T31 G10 ok line present (anti-crash-false-green)" "G10 every 废止 marker carries a superseding v3.x pointer" "$out"
else
  echo "SKIP T31: audit-docs-consistency.sh absent — 跳过 G10 golden cases"
fi

}

section_T32() {
# ------------------------------------------------ T32 one-step uninstall (v3.41.0)
new_repo
UNINST_SRC="$ROOT/resources/templates/uninstall-standards.sh"
if [[ -f "$UNINST_SRC" ]]; then
  cp "$UNINST_SRC" scripts/uninstall-standards
  chmod +x scripts/uninstall-standards
  seed_artifacts CHG-970 L1 claude/s-32
  # AGENTS.md is a shared asset: installer header + user-added content
  printf '# AGENTS\n## 门禁\n' > AGENTS.md
  printf '\nuser custom section\n' >> AGENTS.md
  mkdir -p .githooks
  cp "$ROOT/resources/templates/pre-commit" .githooks/pre-commit
  printf '#!/bin/sh\necho foreign\n' > .githooks/foreign-hook
  mkdir -p .github/workflows
  # PR template with BROKEN marker (custom content, no 门禁/agent-gate tokens) — Tier2 must keep it
  printf 'custom pr template, user edited\n' > .github/PULL_REQUEST_TEMPLATE.md
  # workflow template with INTACT marker — Tier2 must remove it
  cp "$ROOT/resources/templates/github-agent-governance.yml" .github/workflows/agent-governance.yml
  # Tier1 runtime file, deliberately MODIFIED — must be removed outright anyway
  cp "$ROOT/resources/templates/check-standards-compliance.sh" scripts/check-standards-compliance.sh
  printf '\n# local tampering\n' >> scripts/check-standards-compliance.sh
  git config core.hooksPath .githooks
  bash scripts/uninstall-standards --dry-run >/dev/null 2>&1
  report "T32 dry-run exits 0" 0 $?
  report "T32 dry-run removes nothing" 0 "$(test -f scripts/agent-gate && test -f .githooks/pre-commit && test -f AGENTS.md; echo $?)"
  bash scripts/uninstall-standards >/dev/null 2>&1
  report "T32 uninstall exits 0" 0 $?
  report "T32 runtime tier removed" 0 "$(test ! -e scripts/agent-gate && test ! -e scripts/uninstall-standards && test ! -d .agent-state; echo $?)"
  report "T32 marked hook removed" 0 "$(test ! -e .githooks/pre-commit; echo $?)"
  report "T32 marked workflow removed by marker" 0 "$(test ! -e .github/workflows/agent-governance.yml; echo $?)"
  report "T32 modified PR template kept (marker broken)" 0 "$(test -f .github/PULL_REQUEST_TEMPLATE.md; echo $?)"
  report "T32 modified runtime file removed outright (Tier1: check-standards-compliance.sh)" 0 "$(test ! -e scripts/check-standards-compliance.sh; echo $?)"
  report "T32 foreign hook kept" 0 "$(test -f .githooks/foreign-hook; echo $?)"
  report "T32 diverged AGENTS.md kept without --force" 0 "$(test -f AGENTS.md; echo $?)"
  report "T32 core.hooksPath unset" 0 "$(git config core.hooksPath >/dev/null 2>&1 && echo 1 || echo 0)"
  # --force round (re-seed the uninstaller: the first run self-removed it —
  # that is the designed one-step behavior; here we exercise Tier3 backup-move)
  cp "$UNINST_SRC" scripts/uninstall-standards
  bash scripts/uninstall-standards --force >/dev/null 2>&1
  report "T32 force never rm's shared assets" 0 "$(test ! -e AGENTS.md && test -f .githooks/foreign-hook; echo $?)"
  B32=$(ls -d .uninstall-backup-* 2>/dev/null | head -1)
  report "T32 backup holds the moved asset" 0 "$([[ -n "$B32" && -f "$B32/AGENTS.md" ]]; echo $?)"
else
  echo "SKIP T32: uninstall-standards.sh absent (bootstrap --guard 未安装) — 跳过卸载 golden cases"
fi

}

section_T33() {
# ------------------------------------------------ T33 trace derivation (v3.42.0)
new_repo
STAMP_SRC="$ROOT/resources/templates/stamp-provenance.sh"
[[ -f "$STAMP_SRC" ]] || STAMP_SRC="$ROOT/scripts/stamp-provenance.sh"
if [[ -f "$STAMP_SRC" ]]; then
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  mkdir -p docs/feature-f
  cat > docs/feature-f/01-spec.md <<'EOF'
# feature-f spec
REQ-955 trace derivation.
REQ-956 G5 subset.
EOF
  cat > docs/feature-f/01.5-rtvm-matrix.md <<'EOF'
# feature-f RTVM
| REQ | 简述 | DES | 方案 | TASK | 实现 | TC | 方法 | 状态 |
|---|---|---|---|---|---|---|---|---|
| `REQ-955` | derive | `DES-900` | d | T1 | i | `TC-950` | unit | ✅ |
| `REQ-956` | subset | `DES-901` | d | T2 | i | `TC-951` | unit | ✅ |
EOF
  mkdir -p docs/changes/CHG-980
  cat > docs/changes/CHG-980/09-changelog.md <<'EOF'
# 09 changelog
## CHG-980 · trace derivation
#### 追踪矩阵映射 (Traceability)
- 完整矩阵：docs/feature-f/01.5-rtvm-matrix.md（短引用，v3.23.0）
#### 现象
n/a
EOF
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 --trace derives the §4 block" 1 "$(grep -c 'trace-derive begin' docs/changes/CHG-980/09-changelog.md)"
  check_output "T33 REQ rows derived from matrix" '对应需求（派生）：`REQ-955`、`REQ-956`' "$(cat docs/changes/CHG-980/09-changelog.md)"
  check_output "T33 TC rows derived" '对应测试（派生）：`TC-950`、`TC-951`' "$(cat docs/changes/CHG-980/09-changelog.md)"
  cp docs/changes/CHG-980/09-changelog.md .t33-first
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 --trace is idempotent" 0 "$(diff -q .t33-first docs/changes/CHG-980/09-changelog.md >/dev/null; echo $?)"
  bash scripts/stamp-provenance.sh --all CHG-980 >/dev/null 2>&1
  report "T33 --all keeps the derived block" 1 "$(grep -c 'trace-derive begin' docs/changes/CHG-980/09-changelog.md)"
  report "T33 --all stamped provenance too" 1 "$(grep -c '^<!-- provenance$' docs/changes/CHG-980/09-changelog.md)"
  # TC-1090 (v3.62.2, CHG-082/REQ-1029, 评审 D3 自动化补齐): trace-derive 删块
  # 栅栏感知——09 节内栅栏示例块不被消费；自块幂等不受示例干扰。
  printf '```markdown\n<!-- trace-derive begin（示例，勿仿写）\n对应需求（派生）：`REQ-XXX`\n<!-- trace-derive end -->\n```\n' >> docs/changes/CHG-980/09-changelog.md
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 TC-1090 fenced sample trace block survives re-derive" 1 "$(grep -c 'trace-derive begin（示例' docs/changes/CHG-980/09-changelog.md)"
  report "T33 TC-1090 real derived block kept beside the sample" 2 "$(grep -c 'trace-derive begin' docs/changes/CHG-980/09-changelog.md)"
  cp docs/changes/CHG-980/09-changelog.md .t33-c1090
  bash scripts/stamp-provenance.sh --trace CHG-980 >/dev/null 2>&1
  report "T33 TC-1090 re-derive idempotent with fenced sample present" 0 "$(diff -q .t33-c1090 docs/changes/CHG-980/09-changelog.md >/dev/null; echo $?)"
  rm -f .t33-c1090 .t33-first
  # F3 (review): fail-open ladder — matrix WITH REQ rows but WITHOUT DES/TC
  # tokens (legal upstream shape) must derive a REQ-only block, not die
  # (exercises the `|| true` guards; would have caught F1).
  mkdir -p docs/feature-g
  cat > docs/feature-g/01.5-rtvm-matrix.md <<'EOF'
# feature-g RTVM
| REQ | 需求 | 状态 |
|---|---|---|
| `REQ-958` | req-only | ✅ |
EOF
  mkdir -p docs/changes/CHG-982
  cat > docs/changes/CHG-982/09-changelog.md <<'EOF'
# 09
## CHG-982 · req-only matrix
#### 追踪矩阵映射 (Traceability)
- 完整矩阵：docs/feature-g/01.5-rtvm-matrix.md
EOF
  out33=$(bash scripts/stamp-provenance.sh --trace CHG-982 2>&1); rc33=$?
  report "T33 REQ-only matrix derives without dying (F1 guard)" 0 "$rc33"
  check_output "T33 REQ-only block emits REQ row" '对应需求（派生）：`REQ-958`' "$(cat docs/changes/CHG-982/09-changelog.md)"
  report "T33 REQ-only block emits DES placeholder" 1 "$(grep -c '对应设计（派生）：—（01.5 未含 DES 编号）' docs/changes/CHG-982/09-changelog.md)"
  # F3 (review): --trace single-run block == --all derived block (equivalence)
  b1=$(sed -n '/^<!-- trace-derive begin/,/^<!-- trace-derive end/p' docs/changes/CHG-980/09-changelog.md)
  bash scripts/stamp-provenance.sh --all CHG-980 >/dev/null 2>&1
  b2=$(sed -n '/^<!-- trace-derive begin/,/^<!-- trace-derive end/p' docs/changes/CHG-980/09-changelog.md)
  report "T33 --trace block == --all block (equivalence)" 0 "$(printf '%s\n' "$b1" | diff - <(printf '%s\n' "$b2") >/dev/null; echo $?)"
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  mkdir -p docs/changes/CHG-981
  cat > docs/changes/CHG-981/09-changelog.md <<'EOF'
# 09
## CHG-981 · no matrix
#### 追踪矩阵映射 (Traceability)
- 对应需求：`REQ-970`（见 01-spec.md）
EOF
  out33=$(bash scripts/stamp-provenance.sh --trace CHG-981 2>&1); rc33=$?
  report "T33 --trace without matrix exits 0 (fail-open)" 0 "$rc33"
  check_output "T33 missing matrix announces skip" "trace skip" "$out33"
  report "T33 no marker block written on skip" 0 "$(grep -c 'trace-derive begin' docs/changes/CHG-981/09-changelog.md)"
else
  echo "SKIP T33: stamp-provenance.sh absent (bootstrap --guard 未安装) — 跳过派生 golden cases"
fi

}

section_T34() {
# ------------------------------------------------ T34 bug-autointent (v3.43.0)
new_repo
AUTO_SRC="$ROOT/resources/templates/bug-autointent.sh"
if [[ -f "$AUTO_SRC" ]]; then
  mkdir -p scripts docs/bugs/_templates docs
  cp "$AUTO_SRC" scripts/bug-autointent
  chmod +x scripts/bug-autointent
  cp "$ROOT"/resources/templates/bug-*.md docs/bugs/_templates/
  printf '# Bug 修复记录日志\n\n## 登记格式\n\n<!-- x -->\n' > docs/bugfix-log.md
  bash scripts/bug-autointent --repo-root "$REPO" --source ci-regression --failing "TestA,TestB" --run-url "http://run/1" >/dev/null 2>&1
  report "T34 scaffold creates six-piece flat batch" 6 "$(ls docs/bugs/BATCH-*/01-diagnosis.md docs/bugs/BATCH-*/02-impact.md docs/bugs/BATCH-*/03-test-plan.md docs/bugs/BATCH-*/04-matrix.md docs/bugs/BATCH-*/05-config.md docs/bugs/BATCH-*/06-tasks.md 2>/dev/null | wc -l | tr -d ' ')"
  report "T34 one anchor per piece" 1 "$(grep -c '^## BUG-' docs/bugs/BATCH-*/01-diagnosis.md)"
  report "T34 first-registration line present" 1 "$(grep -c '首次登记' docs/bugs/BATCH-*/01-diagnosis.md)"
  report "T34 fingerprint ledger has one row" 1 "$(wc -l < docs/bugs/.autofingerprint.tsv | tr -d ' ')"
  report "T34 bugfix-log index row registered" 1 "$(grep -c '^### BUG-' docs/bugfix-log.md)"
  bash scripts/bug-autointent --repo-root "$REPO" --source ci-regression --failing "TestB, TestA" --run-url "http://run/2" >/dev/null 2>&1
  report "T34 rate-limit: no new anchor in window" 1 "$(grep -c '^## BUG-' docs/bugs/BATCH-*/01-diagnosis.md)"
  report "T34 rate-limit: reproduction appended" 1 "$(grep -c '再次复现' docs/bugs/BATCH-*/01-diagnosis.md)"
  bash scripts/bug-autointent --repo-root "$REPO" --source ci-regression --failing "TestC" --window 0 --run-url "http://run/3" >/dev/null 2>&1
  report "T34 expired window scaffolds new BUG" 2 "$(grep -c '^## BUG-' docs/bugs/BATCH-*/01-diagnosis.md)"
  bash scripts/bug-autointent --repo-root /nonexistent-xyz --source x --failing A >/dev/null 2>&1
  report "T34 no-repo degrade exits 2" 2 $?
else
  echo "SKIP T34: bug-autointent.sh absent (bootstrap --guard 未安装) — 跳过自动登记 golden cases"
fi

}

section_T36() {
# ------------------------------------------------ T36 gate friction metrics (v3.43.0)
new_repo
GATE_T36="$ROOT/resources/templates/agent-gate.sh"
[[ -f "$GATE_T36" ]] || GATE_T36="$ROOT/scripts/agent-gate"
if [[ -f "$GATE_T36" ]]; then
  mkdir -p scripts .agent-state
  copy_gate_to scripts agent-gate
  git config user.name t36; git config user.email t36@x
  git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1
  bash scripts/agent-gate begin CHG-990 >/dev/null 2>&1
  report "T36 die event appended to friction ledger" 1 "$(wc -l < .agent-state/gate-friction.tsv | tr -d ' ')"
  report "T36 friction code is GATE-E format" 1 "$(grep -cE '^GATE-E[0-9]+' .agent-state/gate-friction.tsv)"
  out36=$(bash scripts/agent-gate metrics 2>/dev/null | grep -c 'friction_code' || true)
  report "T36 metrics aggregates friction" 1 "$out36"
  # CHG-121 (batch 0): attribution columns — a 2-column ledger could not say
  # which change caused the friction.
  report "T36 friction row carries 5 columns (CHG-121)" 5 "$(awk -F'\t' 'NR==1{print NF}' .agent-state/gate-friction.tsv)"
  report "T36 friction row records the event kind (CHG-121)" 1 "$(awk -F'\t' 'NR==1 && $4=="DIE"{c++} END{print c+0}' .agent-state/gate-friction.tsv)"
else
  echo "SKIP T36: agent-gate absent — 跳过摩擦 metrics golden cases"
fi

}

section_T37() {
# ------------------------------------------------ T37 L0 最小集三态（v3.44.0，REQ-962）
# v3.91.9 (CHG-127): resolve through GATE_SRC (templates), not the untracked
# installed copy — a fresh checkout skipped this whole block (7 assertions),
# which made the CI run 1552 vs the committed 1559 baseline.
if [[ -s "$GATE_SRC" ]]; then
  t37_stamp() { for pf in docs/changes/$1/*.md; do
    { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf"; } > "$pf.tmp" && mv "$pf.tmp" "$pf"; done; }
  t37_fill() { # id -> declaration-only 04.5/05 + minimal delivery set
    printf -- '- **编码记录**：未命中，不适用（L0 纯文档变更，无源码改动）\n' > docs/changes/$1/04.5-coding-record.md
    printf -- '- **测试结果**：未命中，不适用（L0 纯文档变更，无行为面）\n' > docs/changes/$1/05-test-results.md
    printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/$1/09-changelog.md
    printf '未命中，不适用（无配置变更）\n' > docs/changes/$1/06.5-deployment-config.md
    printf '# 交付总结\n#### 遗留\n- FU-001 演示\n' > docs/changes/$1/06-delivery-summary.md
    append_masters docs/changes/$1/09-changelog.md
    t37_stamp "$1"
  }
  # ① L0 + 04.5/05 单行声明 → stop PASS
  new_repo
  seed_begin CHG-991 L0 claude/s-1
  t37_fill CHG-991
  echo y > src/t37.js   # stop 只在存在代码路径改动时执法（对齐 T5/T23 夹具）
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L0 minimal-set: declaration satisfies 04.5/05" 0 $?
  # ⑤ v3.48.0（CHG-058）：02 缺延伸发现节 → E80（自愈还原；v3.48.1 CHG-060 自 E15 重编）
  sed -i '' '/延伸发现/d' docs/changes/CHG-991/02-code-impact-analysis.md 2>/dev/null || sed -i '/延伸发现/d' docs/changes/CHG-991/02-code-impact-analysis.md
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "stop refuses 02 missing 延伸发现 (E80)" "GATE-E80.*延伸发现" "$out"
  append_diag_lines docs/changes/CHG-991/02-code-impact-analysis.md
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 stop green again after 延伸发现 restored" 0 $?
  # ② L0 + 04.5/05 缺失 → 拒绝（E47 先于 E48）
  rm docs/changes/CHG-991/04.5-coding-record.md docs/changes/CHG-991/05-test-results.md
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L0 minimal-set: missing 04.5/05 still refused" 2 $?
  # ③ L1 + 仅声明行空壳 → GATE-E52（轻量通道越道拦截；盖章注释不计内容行）
  new_repo
  seed_begin CHG-992 L1 claude/s-1
  t37_fill CHG-992
  echo y > src/t37.js
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L1 declaration-only stub escapes its lane: stop refused" 2 $?
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "T37 refusal names the stub rule" "GATE-E52.*declaration-only stub" "$out"
  # ④ L1 + 半角括号/变体声明行 → E52 仍拦（评审 P1 修复：判定与形状解耦）
  { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'
    printf -- '- **编码记录**: 未命中, 不适用(纯文档)\n'; } > docs/changes/CHG-992/04.5-coding-record.md
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T37 L1 bracket-variant stub still refused (P1 fix)" 2 $?
else
  echo "SKIP T37: agent-gate absent — 跳过 L0 最小集 golden cases"
fi

# CHG-160 FU-1606 (TC-1472c): the three is_code_path copies classify the split test files identically.
# agent-gate / session-gate are evaluated for real (function bodies extracted); the audit copy is a grep
# pipeline, so its exclusion list is pinned by literal.
_t1472_ag=$(sed -n '/^is_code_path() {/,/^}/p' "$ROOT/resources/templates/agent-gate.sh")
_t1472_sg=$(sed -n '/^sg_is_code_path() {/,/^}/p' "$ROOT/resources/templates/session-gate.sh")
for _t1472_p in tests/suites/suite-03-session.sh tests/lib/test-harness.sh tests/suites/suite-08-infra.sh; do
  _t1472_a=$( docs_re=docs scripts_re=scripts tests_re=tests githooks_re='\.githooks'; eval "$_t1472_ag"; is_code_path "$_t1472_p" && echo 0 || echo 1 )
  _t1472_s=$( DOCS_RE=docs SCRIPTS_RE=scripts TESTS_RE=tests GITHOOKS_RE='\.githooks'; eval "$_t1472_sg"; sg_is_code_path "$_t1472_p" && echo 0 || echo 1 )
  report "T37 TC-1472c is_code_path agrees on $_t1472_p (agent-gate vs session-gate, both non-code)" "1 1" "$_t1472_a $_t1472_s"
done
_t1472_ac=$( docs_re=docs scripts_re=scripts tests_re=tests githooks_re='\.githooks'; eval "$_t1472_ag"; is_code_path tests/suites/zzz-new.sh && echo 0 || echo 1 )
_t1472_sc=$( DOCS_RE=docs SCRIPTS_RE=scripts TESTS_RE=tests GITHOOKS_RE='\.githooks'; eval "$_t1472_sg"; sg_is_code_path tests/suites/zzz-new.sh && echo 0 || echo 1 )
report "T37 TC-1472c control: an unlisted tests/suites file is code in both copies" "0 0" "$_t1472_ac $_t1472_sc"
report "T37 TC-1472c audit-docs-consistency G16 copy lists suite-03-session.sh and lib/test-harness.sh" "1 1" "$(grep -cF 'suites/suite-03-session\.sh$' "$ROOT/resources/templates/audit-docs-consistency.sh" | tr -d ' ') $(grep -cF 'lib/test-harness\.sh$' "$ROOT/resources/templates/audit-docs-consistency.sh" | tr -d ' ')"

}

