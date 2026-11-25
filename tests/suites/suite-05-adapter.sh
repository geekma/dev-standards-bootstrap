#!/usr/bin/env bash
# suite-05-adapter.sh — domain suite module (v4.13.0, CHG-158)

_t49_setup_stub() {
  new_repo
  mkdir -p scripts
  cat > stub-runtime.sh <<'STUB'
#!/usr/bin/env bash
# 桩 opencode runtime：SG_STUB_VERSION / SG_STUB_REJECT / SG_STUB_MARKER 三旋钮
# （T49-04 桩设计，CHG-084 04-test-scripts；模拟 拒载/载入/功能死 三态）
case "$1" in
  --version) echo "${SG_STUB_VERSION:-9.9.9-stub}"; exit 0 ;;
  serve)
    echo "opencode server listening on http://127.0.0.1:${3:-0}"
    if [[ "${3:-}" =~ ^[0-9]+$ ]]; then
      ( while true; do printf 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}' | nc -l 127.0.0.1 "$3" >/dev/null 2>&1; done ) &
    fi
    ;;
esac
if [[ "${SG_STUB_SILENT:-0}" == "1" && "$1" != "--version" ]]; then exit 0; fi
if [[ -n "${XDG_DATA_HOME:-}" ]]; then
  mkdir -p "$XDG_DATA_HOME/opencode/log" 2>/dev/null
  if [[ "${SG_STUB_REJECT:-0}" == "1" ]]; then
    printf '%s\n' "timestamp=T level=WARN message=\"failed to load plugin\" target=$PWD/.opencode/plugins/dev-standards-gate.js cause=\"SchemaError(stub)\"" > "$XDG_DATA_HOME/opencode/log/opencode.log"
  else
    printf '%s\n' "timestamp=T level=INFO message=\"plugin loaded: $PWD/.opencode/plugins/dev-standards-gate.js (stub)\"" > "$XDG_DATA_HOME/opencode/log/opencode.log"
  fi
fi
if [[ "${SG_STUB_DESKTOP_REJECT:-0}" == "1" && "$1" != "serve" && "$1" != "--version" && "$1" != "run" && -n "${XDG_DATA_HOME:-}" ]]; then
  mkdir -p "$XDG_DATA_HOME/opencode/log" 2>/dev/null
  printf '%s\n' "timestamp=T level=WARN message=\"failed to load plugin\" target=$PWD/.opencode/plugins/dev-standards-gate.js cause=\"SchemaError(stub-desktop)\"" > "$XDG_DATA_HOME/opencode/log/opencode.log"
  exit 0
fi
if [[ "${SG_STUB_MARKER:-0}" == "1" && "${SG_STUB_REJECT:-0}" != "1" ]]; then
  mkdir -p out 2>/dev/null
  printf 'sg-call start\n' >> out/sg-runs.log
  mkdir -p .agent-state 2>/dev/null
  touch .agent-state/session-started.json
  printf 'probe-tag: %s\n' "${AGENT_GUARD_SESSION_TAG:-}" > .agent-state/session-gate-last.md
fi
sleep "${SG_STUB_SLEEP:-0.2}"
STUB
  chmod +x stub-runtime.sh
  STUB_SH="$PWD/stub-runtime.sh"
  cp "$ROOT/resources/templates/install-hook-adapter.sh" scripts/install-hook-adapter
  copy_gate_to scripts agent-gate
  cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
  chmod +x scripts/install-hook-adapter
  export AGENT_GUARD_PROBE_WINDOW=0.05
  # owner=geek007 deadline=2099-12-31 (T49 offline/reprobe test fixture, CHG-151)
  export AGENT_GUARD_OFFLINE=1
  export SG_STUB_SLEEP=0.2
  export DEV_STANDARDS_OPENCODE_BIN="$STUB_SH"
  export DEV_STANDARDS_OPENCODE_DESKTOP_BIN="$STUB_SH"
  export SG_STUB_VERSION="1.19.0-stub"
}

section_T49a() {
# ---- T49a (v3.63.0, CHG-083 / v4.13.0 split CHG-158): 换挡执法 + 活性自检 + adapter 正常流 ----
new_repo
seed_artifacts CHG-950 L1 claude/s-1
mkdir -p .agent-state
# 态①：无 last-delivery → 放行
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 2>&1); rc=$?
report "T49 E89 state1: no delivery passes" 0 "$rc"
rm -rf .git/agent-governance
# 态②：同会话交付（delivered 晚于 started）无 handoff → E89 die（rc=2，有码，不静默）
printf '{"delivered_at":"%s","change":"CHG-950","stage":"stop","session":""}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/last-delivery.json
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 2>&1); rc=$?
report "T49 E89 state2: in-session delivery without handoff dies" 2 "$rc"
report "T49 E89 state2 die names the code (not silent)" 1 "$(printf '%s' "$out" | grep -c 'GATE-E89')"
rm -rf .git/agent-governance
# 态③：handoff 落在【变更自有目录】（R07-2 回归：尾斜杠路径）→ 放行
mkdir -p docs/changes/CHG-950
printf '# handoff\n' > docs/changes/CHG-950/handoff.md
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 2>&1); rc=$?
report "T49 E89 state3: handoff in own change dir passes" 0 "$rc"
rm -rf .git/agent-governance docs/changes/CHG-950/handoff.md
# 态④：豁免 env → 放行
AGENT_GUARD_ALLOW_NO_SHIFT=1 scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T49 E89 state4: escape env passes" 0 $?
rm -rf .git/agent-governance
# 态⑤（TC-1095）：陈旧交付（早于 started_at）→ 放行
printf '{"delivered_at":"2020-01-01T00:00:00Z","change":"CHG-950","stage":"stop","session":""}\n' > .agent-state/last-delivery.json
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 >/dev/null 2>&1
report "T49 E89 state5: stale delivery passes (fail-open)" 0 $?
rm -rf .git/agent-governance
# 态⑥（R07-1 回归）：last-delivery 在但 session-started.json 缺失 → 不得静默死亡
rm -f .agent-state/session-started.json
printf '{"delivered_at":"%s","change":"CHG-950","stage":"stop","session":""}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/last-delivery.json
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate begin CHG-950 >/dev/null 2>&1; rc=$?
report "T49 E89 R07-1: missing started marker is not a silent kill" 0 "$(( rc == 1 ? 1 : 0 ))"

# ② 活性自检三态（TC-1100；R07-5：坏 env 回落）
new_repo
mkdir -p .agent-state scripts
cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"turns":3,"bash":1,"grep":0,"other":2,"total":3,"updated_at":"2020-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
report "T49 liveness stale emits YELLOW" 1 "$(bash scripts/session-gate.sh status 2>&1 | grep -c 'telemetry stale')"
report "T49 liveness bad env falls back (no crash, still stale report)" 1 "$(AGENT_GUARD_SESSION_TELEMETRY_STALE_MIN=abc bash scripts/session-gate.sh status 2>&1 | grep -c 'telemetry stale')"
printf '{"turns":3,"bash":1,"grep":0,"other":2,"total":3,"updated_at":"%s"}\n' "$NOW" > .agent-state/session-tool-stats.json
report "T49 liveness fresh is quiet" 0 "$(bash scripts/session-gate.sh status 2>&1 | grep -c 'telemetry stale')"
rm -f .agent-state/session-tool-stats.json
mkdir -p .claude && printf '{}\n' > .claude/settings.json
report "T49 liveness wiring-but-no-telemetry emits YELLOW" 1 "$(AGENT_GUARD_ALLOW_NO_SHIFT=0 bash scripts/session-gate.sh status 2>&1 | grep -c 'zero telemetry')"

# ③ adapter 四段式正常流（T49-01/02/03/06/07）
_t49_setup_stub

# T49-01 (TC-1103): runtime 全抑制（路径不可执行=未检出）→ 显式 skip（非静默），不落盘
out=$(DEV_STANDARDS_OPENCODE_BIN=/nonexistent DEV_STANDARDS_OPENCODE_DESKTOP_BIN=/nonexistent \
  bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-01 no-runtime exits 2 (explicit no-op)" 2 "$rc"
report "T49-01 skip names the reason (not silent)" 1 "$(printf '%s' "$out" | grep -c 'no opencode runtime detected')"
report "T49-01 nothing written" 0 "$(test -f .opencode/plugins/dev-standards-gate.js && echo 1 || echo 0)"

# T49-02/03 (TC-1104/1105 + TC-10033/10039): 桩双 runtime 全过 → dual-active 胜出 + 离线契约 + 仲裁缓存
out=$(SG_STUB_MARKER=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-02 stub-all-pass installs (rc0)" 0 "$rc"
report "T49 TC-10033 offline mode skips remote docs fetch" 1 "$(printf '%s' "$out" | grep -c 'offline mode active')"
report "T49 TC-10039 arbitration cache populated on green install" 0 "$(test -s .agent-state/opencode-arbitration-cache.tsv; echo $?)"
out=$(SG_STUB_MARKER=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49 TC-10039 second run hits arbitration cache (rc0)" "0:1" "${rc}:$(printf '%s' "$out" | grep -c 'arbitration cache hit')"
out=$(SG_STUB_MARKER=1 bash scripts/install-hook-adapter --client opencode --reprobe 2>&1); rc=$?
report "T49 TC-10039 --reprobe bypasses arbitration cache (rc0)" "0:0" "${rc}:$(printf '%s' "$out" | grep -c 'arbitration cache hit')"
# owner=geek007 deadline=2099-12-31 (T49 offline/reprobe test fixture, CHG-151)
export AGENT_GUARD_REPROBE=1
report "T49-02 contract-runtime lists both runtimes" 1 "$(grep -c 'contract-runtime: cli=1.19.0-stub desktop=1.19.0-stub' .opencode/plugins/dev-standards-gate.js)"
report "T49-02 contract-shape=dual-active" 1 "$(grep -c 'contract-shape: dual-active' .opencode/plugins/dev-standards-gate.js)"
report "T49-02 contract-source field present" 1 "$(grep -c 'contract-source:' .opencode/plugins/dev-standards-gate.js)"
report "T49-02 verified evidence carries function marker" 1 "$(grep -cF 'final-file probes: cli=1.19.0-stub:PASS(function) desktop=1.19.0-stub:PASS(function)' .opencode/plugins/dev-standards-gate.js)"
report "T49-03 emitted default export is dual-active" 1 "$(grep -c 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2, server: DevStandardsGate }' .opencode/plugins/dev-standards-gate.js)"
report "T49-03 named v1 export present" 1 "$(grep -c 'export const DevStandardsGate = async' .opencode/plugins/dev-standards-gate.js)"
report "T49-03 v2 setup export present" 1 "$(grep -c 'export const DevStandardsGateV2 = async' .opencode/plugins/dev-standards-gate.js)"
report "T49-05 arbitration attempts recorded (evidence not clobbered)" 1 "$(grep -cF 'attempt[all-runtimes] candidate[dual-active]' .opencode/plugins/dev-standards-gate.js)"

# T49-06 (TC-1107): 真实 runtime 探测——默认 SKIP 并显式报告；AGENT_GUARD_T49_REAL_PROBE=1 才跑
unset AGENT_GUARD_PROBE_WINDOW AGENT_GUARD_OFFLINE AGENT_GUARD_REPROBE SG_STUB_SLEEP DEV_STANDARDS_OPENCODE_BIN DEV_STANDARDS_OPENCODE_DESKTOP_BIN SG_STUB_VERSION
if [[ "${AGENT_GUARD_T49_REAL_PROBE:-0}" == "1" ]]; then
  out=$(bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
  report "T49-06 real-runtime install rc0" 0 "$rc"
  report "T49-06 no failed-to-load in verdict" 1 "$(printf '%s' "$out" | grep -c 'runtime-verified')"
else
  report "T49-06 real-runtime probe skipped by default (explicit, not silent)" 1 "1"
fi

# T49-07 (TC-1108): 套件不再包含 v3.63.0 自指形状断言（断言对象=行为证据，非模板字面量）
_t49_legacy_head='export default { id: "dev-standards-gate", server: '
report "T49-07 legacy self-referential shape assertion removed" 0 "$(grep -h -cF "${_t49_legacy_head}DevStandardsGate }" "$ROOT/tests/run-tests.sh" "$ROOT/tests/suites/"*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')"
}

section_T49b() {
# ---- T49b (v4.13.0 split CHG-158): adapter E12 拒载与还原测试 ----
_t49_setup_stub

# T49-04 (TC-1106, SC-997): 客户端拒载桩 → ADAPTER-E12 die，不落盘
rm -f .opencode/plugins/dev-standards-gate.js
out=$(SG_STUB_MARKER=1 SG_STUB_REJECT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-04 client-rejected dies (rc2)" 2 "$rc"
report "T49-04 die names ADAPTER-E12" 1 "$(printf '%s' "$out" | grep -c 'ADAPTER-E12')"
report "T49-04 no plugin left behind" 0 "$(test -f .opencode/plugins/dev-standards-gate.js && echo 1 || echo 0)"

# T49-04b (SC-998): 载入但零功能标记（schema-过-功能-死）→ E12 —— 假绿防线
out=$(SG_STUB_MARKER=0 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-04b loaded-but-no-function dies (rc2)" 2 "$rc"
report "T49-04b names the functional-marker failure" 1 "$(grep -q 'loaded-but-no-functional-marker' <<< "$out" && echo 1 || echo 0)"

# T49-04c (E12 restore-with-backup)：已装好 → 拒载重装 → E12 + 还原旧生成物
SG_STUB_MARKER=1 bash scripts/install-hook-adapter --client opencode >/dev/null 2>&1
out=$(SG_STUB_MARKER=1 SG_STUB_REJECT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-04c reinstall-reject dies (rc2)" 2 "$rc"
report "T49-04c previous adapter restored intact" 1 "$(grep -cF 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2, server: DevStandardsGate }' .opencode/plugins/dev-standards-gate.js 2>/dev/null)"
}

section_T49c() {
# ---- T49c (v4.13.0 split CHG-158): adapter E13/E11 回退与 bootstrap 目录接线 ----
_t49_setup_stub
export AGENT_GUARD_REPROBE=1

# T49-05a (E13 primary-only fallback)：desktop 形态单独拒载 → 主用 runtime 择形 + 显式告警
out=$(SG_STUB_MARKER=1 SG_STUB_DESKTOP_REJECT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-05a E13 fallback attempted but desktop-final-fail dies (rc2)" 2 "$rc"
report "T49-05a E13 warn names primary-only arbitration" 1 "$(printf '%s' "$out" | grep -c 'ADAPTER-E13 (warn)')"
report "T49-05a primary-only round recorded in matrix" 2 "$(printf '%s' "$out" | grep -c 'attempt\[primary-only\]')"

# T49-05b (E11 all-INCONCLUSIVE)：除版本应答外零痕迹 → 探测无判决 → E11 拒装
rm -f .opencode/plugins/dev-standards-gate.js
out=$(SG_STUB_MARKER=1 SG_STUB_SILENT=1 bash scripts/install-hook-adapter --client opencode 2>&1); rc=$?
report "T49-05b silent runtime dies E11 (rc2)" 2 "$rc"
report "T49-05b die names ADAPTER-E11" 1 "$(printf '%s' "$out" | grep -c 'ADAPTER-E11')"
report "T49-05b nothing written" 0 "$(test -f .opencode/plugins/dev-standards-gate.js && echo 1 || echo 0)"

# ④ bootstrap 目录证据接线（TC-1096）——桩注入 + 离线模式，不跑真探测
new_repo
mkdir -p .opencode
AGENT_GUARD_OFFLINE=1 AGENT_GUARD_PROBE_WINDOW=0.05 SG_STUB_MARKER=1 SG_STUB_VERSION="1.19.0-stub" \
  DEV_STANDARDS_OPENCODE_BIN="$STUB_SH" DEV_STANDARDS_OPENCODE_DESKTOP_BIN="$STUB_SH" \
  bash "$ROOT/scripts/bootstrap.sh" --guard "$REPO" >/dev/null 2>&1
report "T49 bootstrap dir-evidence wires dual-active adapter" 1 "$(grep -c 'export default { id: "dev-standards-gate", setup: DevStandardsGateV2, server: DevStandardsGate }' .opencode/plugins/dev-standards-gate.js 2>/dev/null)"
}
