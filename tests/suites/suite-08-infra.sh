#!/usr/bin/env bash
# suite-08-infra.sh — domain suite module (v4.13.0, CHG-158)

section_T79() {
# ------------------------------------------------ T79 audit G16 三态（v3.89.0，CHG-117，REQ-1201，DES-1959）
if [[ ! -f "$AUDIT_SRC" ]]; then echo "SKIP T79: audit-docs-consistency absent"; return 0; fi
# clean + non-git: explicit VACUOUS SKIP line (G9 anti-false-green family)
t79_fx=$(mktemp -d); audit_fixture "$t79_fx"
t79_out=$(bash "$AUDIT_SRC" "$t79_fx" 2>&1); t79_rc=$?
report "T79 TC-1490a non-git fixture passes with G16 VACUOUS SKIP declared" 0 "$t79_rc"
check_output "T79 TC-1490a the skip is explicit, not silent" "G16 VACUOUS SKIP" "$t79_out"
# dirty unaccounted: FAIL names the offending files
t79_fx2=$(mktemp -d); audit_fixture "$t79_fx2"
(cd "$t79_fx2" && git init -q && git config user.email t@e.invalid && git config user.name t \
  && git add -A && git commit -qm init && mkdir -p src && printf 'x\n' > src/leak.py)
t79_out=$(bash "$AUDIT_SRC" "$t79_fx2" 2>&1); t79_rc=$?
report "T79 TC-1489 dirty unaccounted worktree fails G16" 1 "$t79_rc"
check_output "T79 TC-1489 the FAIL names the offending file" "leak\.py" "$t79_out"
# accounted: same dirty tree + active-change pointer
t79_af=$(git -C "$t79_fx2" rev-parse --git-path agent-governance/active-change)
mkdir -p "$t79_fx2/$(dirname "$t79_af")" && printf 'CHG-1173\n' > "$t79_fx2/$t79_af"
t79_out=$(bash "$AUDIT_SRC" "$t79_fx2" 2>&1); t79_rc=$?
report "T79 TC-1490b same dirty tree with an active change passes" 0 "$t79_rc"
check_output "T79 TC-1490b the pass states the account anchor" "G16 local source changes are accounted" "$t79_out"
# --only-fail on a clean git tree: rc 0 and the skip face is suppressed (DES-1959)
t79_fx3=$(mktemp -d); audit_fixture "$t79_fx3"
(cd "$t79_fx3" && git init -q && git config user.email t@e.invalid && git config user.name t \
  && git add -A && git commit -qm init)
t79_out=$(bash "$AUDIT_SRC" --only-fail "$t79_fx3" 2>&1); t79_rc=$?
report "T79 TC-1490c clean tree passes under --only-fail" 0 "$t79_rc"
report "T79 TC-1490c --only-fail suppresses the G16 skip face" 0 "$(printf '%s\n' "$t79_out" | grep -c 'G16 VACUOUS SKIP')"
rm -rf "$t79_fx" "$t79_fx2" "$t79_fx3"
}

section_T80() {
# ------------------------------------------------ T80 阶段门红→绿 + STAGE_GATES 开关（v3.89.0，CHG-117，REQ-1202，DES-1960）
if [[ ! -f "$GATE_SRC" ]]; then echo "SKIP T80: agent-gate absent"; return 0; fi
new_repo
seed_begin CHG-1174 L1 claude/s-1
# G-规格门: missing file / numbering gap / idempotent re-entry
rm docs/changes/CHG-1174/01-spec.md
t80_rc=0; scripts/agent-gate --stage spec >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1491a spec gate dies when 01-spec is missing" 2 "$t80_rc"
printf '# spec\n> 交付触发点：spec 阶段交付；下游输入：02/03 与 04\n> 背景输入：P01 需求册 + 业务背景\n- REQ-001: a\n- REQ-003: gap\n' > docs/changes/CHG-1174/01-spec.md
t80_rc=0; scripts/agent-gate --stage spec >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1491b spec gate dies on a REQ numbering gap" 2 "$t80_rc"
# v3.91.6 (CHG-127): the PMP input contract is folded into these three existing
# assertions (red when the marker/upstream citation is missing, green after
# restore) instead of adding new ones — the suite assertion count must stay at
# the committed baseline (本机全量无法在宿主 Kill 前跑完，新增断言会让基线失真).
printf '# spec\n> 交付触发点：spec 阶段交付；下游输入：02/03 与 04\n> 背景输入：既有文档\n- REQ-001: a\n- REQ-002: b\n' > docs/changes/CHG-1174/01-spec.md
t80_bad=0; scripts/agent-gate --stage spec >/dev/null 2>&1 || t80_bad=$?
printf '# spec\n> 交付触发点：spec 阶段交付；下游输入：02/03 与 04\n> 背景输入：P01 需求册 + 业务背景\n- REQ-001: a\n- REQ-002: b\n' > docs/changes/CHG-1174/01-spec.md
t80_rc=0; scripts/agent-gate --stage spec >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1491c spec gate red without business background, green after backfill" 0 "$([[ $t80_bad -eq 2 && $t80_rc -eq 0 ]] && echo 0 || echo 1)"
# G-设计门: 02 rollback face / 03 selection+paradigm faces
sed -i '' '/回滚策略/d' docs/changes/CHG-1174/02-code-impact-analysis.md 2>/dev/null \
  || sed -i '/回滚策略/d' docs/changes/CHG-1174/02-code-impact-analysis.md
t80_rc=0; scripts/agent-gate --stage design >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1492a design gate dies when 02 lacks the rollback face" 2 "$t80_rc"
printf '## 回滚策略\nrollback: ok\n' >> docs/changes/CHG-1174/02-code-impact-analysis.md
cp docs/changes/CHG-1174/02-code-impact-analysis.md /tmp/t80-02.bak
grep -v '^> 交付触发点：' docs/changes/CHG-1174/02-code-impact-analysis.md > /tmp/t80-02.tmp \
  && mv /tmp/t80-02.tmp docs/changes/CHG-1174/02-code-impact-analysis.md
t80_bad=0; scripts/agent-gate --stage design >/dev/null 2>&1 || t80_bad=$?
cp /tmp/t80-02.bak docs/changes/CHG-1174/02-code-impact-analysis.md
t80_rc=0; scripts/agent-gate --stage design >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1492b design gate red without 交付触发点, green after restore" 0 "$([[ $t80_bad -eq 2 && $t80_rc -eq 0 ]] && echo 0 || echo 1)"
# G-测试门: 04 用例矩阵 + TC 落点清单
t80_rc=0; scripts/agent-gate --stage testplan >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493a testplan gate dies without the TC 落点清单 section" 2 "$t80_rc"
mkdir -p tests && printf 'assert "t80"\n' > tests/test_a.py
t_tc_landing docs/changes/CHG-1174/04-test-scripts.md tests/test_a.py
cp docs/changes/CHG-1174/04-test-scripts.md /tmp/t80-04.bak
sed -i '' 's/^> 背景输入：.*/> 背景输入：P12 业务背景/' docs/changes/CHG-1174/04-test-scripts.md 2>/dev/null \
  || sed -i 's/^> 背景输入：.*/> 背景输入：P12 业务背景/' docs/changes/CHG-1174/04-test-scripts.md
t80_bad=0; scripts/agent-gate --stage testplan >/dev/null 2>&1 || t80_bad=$?
cp /tmp/t80-04.bak docs/changes/CHG-1174/04-test-scripts.md
t80_rc=0; scripts/agent-gate --stage testplan >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493b testplan gate red without upstream background, green after restore" 0 "$([[ $t80_bad -eq 2 && $t80_rc -eq 0 ]] && echo 0 || echo 1)"
# 八件齐的存量习惯: every stage gate idempotent-green
t80_all=0
for t80_g in spec design testplan; do
  scripts/agent-gate --stage "$t80_g" >/dev/null 2>&1 || t80_all=1
  scripts/agent-gate --stage "$t80_g" >/dev/null 2>&1 || t80_all=1   # second pass = idempotence
done
report "T80 TC-1493c all-artifacts habit passes every stage gate twice (idempotent)" 0 "$t80_all"
# narrowed begin takes the entry three alone; STAGE_GATES=0 restores the legacy full check
mkdir -p docs/changes/CHG-1175
printf '# i\n## 问题\np\n## 预期结果\ne\n## 目录落位\n- **目录落位**：独立目录（t80 fixture）\n## 开放问题\no\n' > docs/changes/CHG-1175/00-intent.md
printf '{"change_id":"CHG-1175","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-9","test_owner":"claude/s-t","review_owner":"claude/s-r"}\n' > docs/changes/CHG-1175/00-governance.json
cp docs/changes/CHG-1174/00.5-communication.md docs/changes/CHG-1175/00.5-communication.md
t80_rc=0; scripts/agent-gate begin CHG-1175 >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493d narrowed begin passes on the entry three alone" 0 "$t80_rc"
t80_rc=0; AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1175 >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493e STAGE_GATES=0 restores the legacy full begin check (missing 01 dies)" 2 "$t80_rc"
# TC-1493f (独立评审 F3): preflight must share the narrowed begin's entry scope —
# an entry-only change is green, not a wall of missing 01-04 complaints.
t80_out=$(scripts/agent-gate preflight CHG-1175 2>&1); t80_rc=$?
report "T80 TC-1493f preflight agrees with narrowed begin on an entry-only change" 0 "$t80_rc"
# TC-1493g (独立评审 F1): a BATCH member's artifacts live in the batch dir; the
# stage gate must resolve them through change_dir (same source as session-gate).
new_repo
seed_batch_artifacts BATCH-20260101 CHG-1177:L1
mkdir -p tests && printf 'assert "batch"\n' > tests/test_a.py
t_tc_landing docs/changes/BATCH-20260101/04-test-scripts.md tests/test_a.py
t80_af=$(git rev-parse --git-path agent-governance/active-change)
mkdir -p "$(dirname "$t80_af")" && printf 'CHG-1177\n' > "$t80_af"
t80_rc=0; scripts/agent-gate --stage testplan >/dev/null 2>&1 || t80_rc=$?
report "T80 TC-1493g BATCH member testplan gate resolves the batch directory" 0 "$t80_rc"
}

section_T81() {
# ------------------------------------------------ T81 check 阶段感知四态（v3.89.0，CHG-117，REQ-1203，DES-1961）
if [[ ! -f "$SESSION_GATE_SRC" ]]; then echo "SKIP T81: session-gate absent"; return 0; fi
new_repo
t_install_session_gate
seed_begin CHG-1176 L1 claude/s-1
# TC-1494a: source edit without the G-测试门 face → exit 2 naming the gate
rm docs/changes/CHG-1176/04-test-scripts.md
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1494a source edit without G-测试门 dies" 2 "$t81_rc"
check_output "T81 TC-1494a message names the missing gate and the backfill face" "G-测试门" "$t81_out"
# TC-1494b: 04 with the TC-landing face present → release
mkdir -p tests && printf 'assert "t81"\n' > tests/test_a.py
printf '# tests\n- TC-001: sample case\n覆盖维度: 正常流\n' > docs/changes/CHG-1176/04-test-scripts.md
t_tc_landing docs/changes/CHG-1176/04-test-scripts.md tests/test_a.py
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1494b source edit passes once the testplan face is in place" 0 "$t81_rc"
# TC-1495a/b: 02 edit needs G-规格门 (01 REQ face in place)
mv docs/changes/CHG-1176/01-spec.md docs/changes/CHG-1176/01-held.md
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/02-code-impact-analysis.md"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495a editing 02 without 01 dies at G-规格门" 2 "$t81_rc"
check_output "T81 TC-1495a message says which gate and what to backfill" "G-规格门" "$t81_out"
# TC-1495a2: the same red under Claude's ABSOLUTE file_path contract (normalization)
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/docs/changes/CHG-1176/02-code-impact-analysis.md"}}' "$PWD" | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495a2 absolute hook path still dies at G-规格门 (normalized)" 2 "$t81_rc"
check_output "T81 TC-1495a2 absolute-path message names the spec gate" "G-规格门" "$t81_out"
mv docs/changes/CHG-1176/01-held.md docs/changes/CHG-1176/01-spec.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/02-code-impact-analysis.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495b 02 edit passes with 01 back in place" 0 "$t81_rc"
# TC-1495b2: editing 04 needs the whole G-设计门 face — 03.5 included
mv docs/changes/CHG-1176/03.5-tasks.md docs/changes/CHG-1176/03.5-held.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/04-test-scripts.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495b2 editing 04 without 03.5 dies at G-设计门" 2 "$t81_rc"
mv docs/changes/CHG-1176/03.5-held.md docs/changes/CHG-1176/03.5-tasks.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/04-test-scripts.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495b2b 04 edit passes with 02+03+03.5 in place" 0 "$t81_rc"
# TC-1495c: process-action faces are never blocked
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/00.5-communication.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495c 00.5 edits are process actions (never blocked)" 0 "$t81_rc"
# TC-1495d/e: bug credential channel — skeleton alone is NOT enough; the log row completes it
git rev-parse --git-path agent-governance/active-change | xargs rm -f
mkdir -p "docs/bugs/BATCH-$(date -u +%Y%m%d)"
# 独立评审 F2: the bare directory is not a defect batch (identity piece required)
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495d0 empty same-day defect-batch dir does NOT release source edits" 2 "$t81_rc"
printf '## BUG-9001\n诊断骨架\n' > "docs/bugs/BATCH-$(date -u +%Y%m%d)/01-diagnosis.md"
t81_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t81_rc=$?
report "T81 TC-1495d batch skeleton without the bugfix-log row does NOT release source edits" 2 "$t81_rc"
check_output "T81 TC-1495d message names the missing credential" "bug 凭证" "$t81_out"
printf '### BUG-9001：现象\n' >> docs/bugfix-log.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495e bug credential (skeleton + log row) releases the fix edit" 0 "$t81_rc"
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/bugs/BATCH-99990101/01-diagnosis.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495f defect-batch-dir edits are process actions (never blocked)" 0 "$t81_rc"
# STAGE_GATES=0 turns the stage predicate layer off (unaccounted layer stays on)
mv docs/changes/CHG-1176/01-spec.md docs/changes/CHG-1176/01-held.md
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"docs/changes/CHG-1176/02-code-impact-analysis.md"}}' | AGENT_GUARD_STAGE_GATES=0 bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1495g STAGE_GATES=0 skips the stage predicate layer" 0 "$t81_rc"
mv docs/changes/CHG-1176/01-held.md docs/changes/CHG-1176/01-spec.md
# TC-1494c (独立评审 F1): a BATCH member's 04 lives in docs/changes/BATCH-*/ —
# check must resolve it the same way agent-gate change_dir does (no false red).
new_repo
t_install_session_gate
seed_batch_artifacts BATCH-20260101 CHG-1177:L1
mkdir -p tests && printf 'assert "batch"\n' > tests/test_a.py
t_tc_landing docs/changes/BATCH-20260101/04-test-scripts.md tests/test_a.py
t81_af=$(git rev-parse --git-path agent-governance/active-change)
mkdir -p "$(dirname "$t81_af")" && printf 'CHG-1177\n' > "$t81_af"
t81_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t81_rc=$?
report "T81 TC-1494c BATCH member source edit resolves the batch 04" 0 "$t81_rc"
}

section_T82() {
# ------------------------------------------------ T82 判定引擎 v0（v3.90.2，CHG-124 P1）
new_repo
export AGENT_GUARD_ADAPT=1
GT82="$ROOT/resources/templates/agent-gate.sh"
GST82="$ROOT/resources/templates/lib-gate-staged.sh"
[[ -s "$GST82" ]] || GST82="$GT82"
BS82="$ROOT/scripts/bootstrap.sh"
if [[ -s "$GT82" ]]; then
  copy_gate_to scripts agent-gate
  seed_artifacts CHG-960 L1 claude/s-82
  mkdir -p tests
  cp "$ROOT/tests/run-tests.sh" tests/run-tests.sh 2>/dev/null || true
  # tracked governance-face change so the resolver has something to map
  printf 'x\n' > scripts/session-gate.sh
  git add scripts/session-gate.sh tests/run-tests.sh >/dev/null 2>&1
  git commit -qm seed >/dev/null 2>&1
  printf 'y\n' >> scripts/session-gate.sh
  # wall-clock is integer seconds and load-sensitive: take the best of 3 runs
  # (the target is still <=1 s; a single loaded run must not fail the assertion).
  t82_best=99
  for _t82_i in 1 2 3; do
    t82a=$(date +%s)
    out=$(scripts/agent-gate plan CHG-960 --dry-run 2>&1); rc=$?
    t82b=$(date +%s)
    _t82_d=$(( t82b - t82a ))
    [[ "$_t82_d" -lt "$t82_best" ]] && t82_best="$_t82_d"
  done
  report "T82 plan --dry-run exits 0" 0 "$rc"
  report "T82 plan --dry-run writes nothing" 0 "$(grep -c '\"decision\"' docs/changes/CHG-960/00-governance.json || true)"
  # v3.91.9 (CHG-127): wall-clock latency is only meaningful on a quiet host.
  # Under -j N the same invocation contends with N-1 other sections, so the
  # ≤1s claim is asserted in serial dispatch (local guardrail) and recorded as
  # "not asserted" under parallel dispatch (CI) — same assertion count, no
  # load-induced red, and the latency claim never silently disappears.
  # v3.96.0 (CHG-133): 证据轮 SOP 让 5 个快照分片进程并发——分片内 JOBS 仍为 1，
  # 但宿主被兄弟分片压满，同属"非静默主机"，墙体预算同样不成立。分片档一律不判
  # （含 live 片：它也与五个快照并发）；≤1 s 由 `-T T82` 这类独占运行承担。
  if [[ "${JOBS:-1}" -ge 2 || -n "${SHARD:-}" || "${AGENT_GUARD_SUITE_IN_WT:-0}" == "1" ]]; then
    report "T82 plan latency measured (parallel/shard/snapshot dispatch: wall-clock budget not asserted)" 0 0
  else
    report "T82 plan runs under 1s (best of 3)" 0 "$(( t82_best > 1 ? 1 : 0 ))"
  fi
  out=$(scripts/agent-gate plan CHG-960 >/dev/null 2>&1); rc=$?
  report "T82 plan writes a decision" 0 "$rc"
  # review #1: a SECOND write must not corrupt the JSON (key stripped fully)
  scripts/agent-gate plan CHG-960 >/dev/null 2>&1
  report "T82 second plan keeps exactly one decision key" 0 "$(( $(grep -o '\"decision\"' docs/changes/CHG-960/00-governance.json | wc -l | tr -d ' ') - 1 ))"
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' docs/changes/CHG-960/00-governance.json >/dev/null 2>&1
    report "T82 governance JSON stays valid after re-plan" 0 $?
  else
    echo "SKIP T82 JSON validity: python3 absent"
  fi
  report "T82 intent block appended once" 0 "$(( $(grep -c '^## 自适应判定' docs/changes/CHG-960/00-intent.md || true) - 1 ))"
  check_output "T82 decision carries engine+chosen+budget" '"engine_version":"adapt/v0"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 decision keeps change_id" '"change_id":"CHG-960"' "$(cat docs/changes/CHG-960/00-governance.json)"
  out=$(scripts/agent-gate plan CHG-960 --explain 2>&1)
  check_output "T82 explain prints resolution rate" 'resolution_rate=' "$out"
  out=$(AGENT_GUARD_ADAPT=0 scripts/agent-gate plan CHG-960 2>&1)
  check_output "T82 ADAPT=0 disables plan" 'plan disabled' "$out"
  out=$(scripts/agent-gate plan CHG-999 2>&1 || true)
  check_output "T82 bad change id dies E136" 'GATE-E136' "$out"
  # E131 pins: warn-only wording + both markers
  report "T82 E131 is a hard die (R3)" 0 "$(( $(grep -c 'GATE-E131:' "$GST82" || true) >= 1 ? 0 : 1 ))"
  check_output "T82 E131 checks dogfood-next" 'dogfood-next' "$(sed -n '/^e131_dogfood_check()/,/^}/p' "$GST82")"
  check_output "T82 suite mode writes to 05" 'suite_mode=' "$(sed -n '/^record_suite_suggestion()/,/^}/p' "$GST82")"
  check_output "T82 down without reason falls back" 'falling back to adopt' "$(sed -n '/^record_suite_suggestion()/,/^}/p' "$GST82")"
  # v3.90.5 (CHG-126): P0-0 baseline + P1-2 tc-index + P2-1 four judges
  printf '# 09\n' > docs/changes/CHG-960/09-changelog.md
  out=$(scripts/agent-gate baseline CHG-960 --write 2>&1); report "T82 baseline --write exits 0" 0 "$?"
  report "T82 baseline writes five numbers" 5 "$(grep -oE '"(stop_p50_s|full_runs|audit_p50_s|full_assertions|full_wall_s)"' docs/changes/CHG-960/baseline.json | wc -l | tr -d ' ')"
  out=$(scripts/agent-gate baseline CHG-960 --write 2>&1)
  report "T82 baseline 09 line stays single" 1 "$(grep -c '^- \[baseline\]' docs/changes/CHG-960/09-changelog.md 2>/dev/null || true)"
  printf '| TC-9999 | fixture | tests/missing.sh |\n' >> docs/changes/CHG-960/04-test-scripts.md
  out=$(scripts/agent-gate tc-index CHG-960 2>&1)
  check_output "T82 tc-index marks a dangling landing" 'dangling=TC-9999' "$out"
  check_output "T82 tc-index reports the union rate" 'rate=' "$out"
  scripts/agent-gate tc-index CHG-960 --write >/dev/null 2>&1
  report "T82 tc-index --write persists the cache" 0 "$([[ -s tests/tc-index.tsv ]] && echo 0 || echo 1)"
  report "T82 tc-index names its source" 1 "$(grep -c '^TC-9999' tests/tc-index.tsv 2>/dev/null || true)"
  # v3.91.2: ledger retention — header + at most 500 data rows.
  # v3.97.1 (CHG-135): hysteresis — rotation starts above 600 lines, so a ledger
  # inside the 501..600 band is left alone instead of rewritten on every append.
  { printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n'
    _ri=0; while [[ "$_ri" -lt 605 ]]; do _ri=$(( _ri + 1 )); printf '2026-01-01T00:00:00Z\tsec\tT1\tx\t1\t0\tnone\t0\t1\t0\tgreen\tr\tm\t128\n'; done; } > .ledger-rot.tsv
  AGENT_GUARD_COST_LEDGER="$PWD/.ledger-rot.tsv" bash "$ROOT/tests/run-tests.sh" -T T41 >/dev/null 2>&1 || true
  report "T82 ledger rotation bounds the file at the hysteresis cap" 1 \
    "$([[ "$(wc -l < .ledger-rot.tsv 2>/dev/null | tr -d ' ')" -gt 500 && "$(wc -l < .ledger-rot.tsv 2>/dev/null | tr -d ' ')" -le 600 ]] && echo 1 || echo 0)"
  report "T82 ledger rotation keeps the header" 1 "$(grep -c '^ts' .ledger-rot.tsv 2>/dev/null || true)"
  rm -f .ledger-rot.tsv
  { printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n'
    _ri=0; while [[ "$_ri" -lt 505 ]]; do _ri=$(( _ri + 1 )); printf '2026-01-01T00:00:00Z\tsec\tT1\tx\t1\t0\tnone\t0\t1\t0\tgreen\tr\tm\t128\n'; done; } > .ledger-rot.tsv
  AGENT_GUARD_COST_LEDGER="$PWD/.ledger-rot.tsv" bash "$ROOT/tests/run-tests.sh" -T T41 >/dev/null 2>&1 || true
  report "T82 ledger inside the hysteresis band is not rewritten" 505 \
    "$(awk -F'\t' '$2 == "sec" && $3 == "T1" {c++} END {print c+0}' .ledger-rot.tsv 2>/dev/null)"
  rm -f .ledger-rot.tsv
  # v3.93.0 (CHG-130, REQ-1290): the audit ledger writer is a 14-column contract.
  # Execute the real derivation + header + writer with fail=1 so rc/outcome are
  # derived by the writer (a fixture that pre-sets _rc=green proves nothing).
  _t82l=$(mktemp "${TMPDIR:-/tmp}/t82ledger.XXXXXX")
  ( _lg="$_t82l"; ROOT="$PWD"; since_ref=probe; SECONDS=1; pass=2; fail=1
    _rk="fixture@host/repo"
    eval "$(awk '/^  _out="green"; _rc=0;/ {f=1} f {print} f && />> "\$_lg"/ {exit}' "$AUDIT_SRC")" ) >/dev/null 2>&1
  report "T82 audit ledger header has 14 columns (CHG-130 REQ-1290)" 14 "$(awk -F'\t' 'NR==1{print NF; exit}' "$_t82l" 2>/dev/null)"
  report "T82 audit ledger row has 14 columns (CHG-130 REQ-1290)" 14 "$(awk -F'\t' 'END{print NF}' "$_t82l" 2>/dev/null)"
  report "T82 audit ledger exit column stays 0 (CHG-130 REQ-1290)" 0 "$(awk -F'\t' 'END{print $8}' "$_t82l" 2>/dev/null)"
  report "T82 audit ledger rc is derived from fail (CHG-130)" 1 "$(awk -F'\t' 'END{print $10}' "$_t82l" 2>/dev/null)"
  report "T82 audit ledger outcome red when fail>0 (CHG-130)" "red" "$(awk -F'\t' 'END{print $11}' "$_t82l" 2>/dev/null)"
  report "T82 audit ledger repo_key is populated (CHG-130)" 1 "$([[ -n "$(awk -F'\t' 'END{print $12}' "$_t82l" 2>/dev/null)" ]] && echo 1 || echo 0)"
  rm -f "$_t82l"
  # v3.93.0 (CHG-130, REQ-1293/REQ-1301): read-only baseline returns 0; a
  # name-less --stage is a usage error (rc 2), not a silent shift overrun.
  scripts/agent-gate baseline CHG-960 >/dev/null 2>&1; _t82brc=$?
  report "T82 baseline read-only exits 0 (CHG-130 REQ-1293)" 0 "$_t82brc"
  scripts/agent-gate --stage >/dev/null 2>&1; _t82src=$?
  report "T82 --stage without a name exits 2 (CHG-130 REQ-1301)" 2 "$_t82src"
  check_output "T82 decision carries the four judges" '"artifacts".*"reviews".*"stages".*"masters"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 L1 judges are lean" '"stage_list":"intent,test,delivery"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G5 stages carry the skipped set" '"skipped":\["' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G11 artifacts carry universe/depth/conditional" '"artifacts":{"universe":15,"depth":{.*},"conditional":{' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G11 project masters carry fill/na" '"project_masters":{"rows":"P00..P12","fill":\["P10"\],"na":\["P00"' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G12 must is present (empty is legal)" '"must":\[' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G6 wasted list is present" '"wasted":\[' "$(cat docs/changes/CHG-960/00-governance.json)"
  # G13: a `fix` change routes around spec/design (structural table, not keywords)
  sed 's/"risk_level":"L1"/"risk_level":"L2","change_type":"fix"/' docs/changes/CHG-960/00-governance.json > .gov.tmp && mv .gov.tmp docs/changes/CHG-960/00-governance.json
  scripts/agent-gate plan CHG-960 >/dev/null 2>&1
  check_output "T82 G13 fix skips spec/design" '"skipped":\["spec","design"\]' "$(cat docs/changes/CHG-960/00-governance.json)"
  check_output "T82 G13 fix keeps diagnosis" '"path":\["intent","diagnosis"' "$(cat docs/changes/CHG-960/00-governance.json)"
  sed 's/"risk_level":"L2","change_type":"fix"/"risk_level":"L2"/' docs/changes/CHG-960/00-governance.json > .gov.tmp && mv .gov.tmp docs/changes/CHG-960/00-governance.json
  scripts/agent-gate plan CHG-960 >/dev/null 2>&1
  check_output "T82 L2 judges require the full stages" '"stage_list":"intent,spec,design,testplan,code,test,review,delivery"' "$(cat docs/changes/CHG-960/00-governance.json)"
  # G2: an impossible budget defers sections instead of silently overrunning.
  # Freeze the fixture first: leftover temp/docs files would make `-T auto`
  # fall back to FULL and the CAB face would never be exercised.
  git add -A >/dev/null 2>&1; git commit -qm t82cab >/dev/null 2>&1 || true
  printf 'z\n' >> scripts/session-gate.sh
  out=$(AGENT_GUARD_BUDGET_CLOSE_S=1 scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 G2 tight budget defers sections" '"deferred":\[\{"id":"T' "$out"
  # G6: three consecutive wasted rows remove a section from the recommendation
  mkdir -p .agent-state
  { printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n'
    for i in 1 2 3; do
      printf '2026-01-0%sT00:00:00Z\tsec\tT26\t-\t20\t0\tnone\t0\t0\t0\twasted\tfixture@host/repo\t\t\n' "$i"
    done; } > .agent-state/cost-ledger.tsv
  out=$(scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 G6 three wasted rows drop the section" '"wasted":\["T26"\]' "$out"
  # G1: all three ledger writers carry the same in-place 8 -> 13 migration.
  check_output "T82 G1 runner migrates old ledger rows" '"asserts","rc","outcome","repo_key","model_id","ctx_window"; next' "$(sed -n '/^ledger_append()/,/^}/p' tests/run-tests.sh)"
  check_output "T82 G1 audit migrates old ledger rows" '"asserts","rc","outcome","repo_key","model_id","ctx_window"; next' "$(cat "$ROOT/resources/templates/audit-docs-consistency.sh")"
  check_output "T82 G1 gate migrates old ledger rows" '"asserts","rc","outcome","repo_key","model_id","ctx_window"; next' "$(cat "$ROOT/resources/templates/agent-gate.sh" "$ROOT/resources/templates/lib-gate-staged.sh" 2>/dev/null)"
  out=$(AGENT_GUARD_PLAN_AI_MASTERS="P10" \
    AGENT_GUARD_PLAN_AI_BASIS="fixture change is documented and risks no runtime surface" \
    AGENT_GUARD_PLAN_AI_REVIEWER="WorkBuddy / test-model / ses-t82-ai" \
    scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 AI judges override is recorded" '"judges_source":"ai"' "$out"
  out=$(AGENT_GUARD_PLAN_AI_MASTERS="P10" AGENT_GUARD_PLAN_AI_BASIS="short" \
    AGENT_GUARD_PLAN_AI_REVIEWER="WorkBuddy / test-model / ses-t82-ai" \
    scripts/agent-gate plan CHG-960 --dry-run 2>&1)
  check_output "T82 short AI basis falls back to engine" '"judges_source":"engine"' "$out"
  out=$(scripts/agent-gate baseline NOPE 2>&1 || true)
  check_output "T82 baseline bad id dies E140" 'GATE-E140' "$out"
  out=$(scripts/agent-gate tc-index NOPE 2>&1 || true)
  check_output "T82 tc-index bad id dies E141" 'GATE-E141' "$out"
else
  echo "SKIP T82: agent-gate absent — 跳过判定引擎 golden cases"
fi
if [[ -s "$BS82" ]]; then
  P82=$(mktemp -d "${TMPDIR:-/tmp}/prof.XXXXXX")
  # let bootstrap create the yml itself (the previous fixture pre-seeded a
  # partial yml, which made it abort before the writer — vacuous assertion).
  ( cd "$P82" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && echo x > README.md && git add README.md && git commit -qm i \
    && bash "$ROOT/scripts/bootstrap.sh" --guard . >/dev/null 2>&1 ); p82_rc=$?
  report "T82 bootstrap guard exits 0" 0 "$p82_rc"
  report "T82 profile section written once" 0 "$(( $(grep -c '^profile:' "$P82/.agent-governance.yml" 2>/dev/null || true) - 1 ))"
  check_output "T82 G9 profile carries schema_version" '^  schema_version: 1$' "$(cat "$P82/.agent-governance.yml")"
  check_output "T82 G7 profile carries ai_project" '^  ai_project: false$' "$(cat "$P82/.agent-governance.yml")"
  report "T82 G8 profile carries the nine detected dimensions" 9 \
    "$(awk '/^profile:/{p=1;next} p && /^[^ ]/{exit} p && /^  (ai_project|architecture|ui|runtime_env|repo_topology|assets|size|language|tests):/{n++} END{print n+0}' "$P82/.agent-governance.yml")"
  check_output "T82 G8 declared dimensions default to unknown" '^  business_complexity: unknown$' "$(cat "$P82/.agent-governance.yml")"
  ( cd "$P82" && bash "$ROOT/scripts/bootstrap.sh" --guard . >/dev/null 2>&1 )
  report "T82 profile not duplicated on re-run" 0 "$(( $(grep -c '^profile:' "$P82/.agent-governance.yml" || true) - 1 ))"
  check_output "T82 upgrade report names the switch" 'AGENT_GUARD_ADAPT=0' "$(sed -n '/upgrade-behavior/p' "$ROOT/scripts/bootstrap.sh")"
  rm -rf "$P82"
  # v3.90.5 P0-9/U-6: an older profile block gains missing keys, user values kept.
  P82b=$(mktemp -d "${TMPDIR:-/tmp}/prof-old.XXXXXX")
  ( cd "$P82b" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && echo x > README.md && git add README.md && git commit -qm i \
    && bash "$ROOT/scripts/bootstrap.sh" --guard . >/dev/null 2>&1 \
    && git add -A && git commit -qm install >/dev/null 2>&1 )
  # Shrink the fresh profile to the pre-U-6 shape, commit, then upgrade in place.
  perl -0777 -pi -e 's/^profile:\n(?:  .*\n)+/profile:\n  language: python\n  size: small\n/m' "$P82b/.agent-governance.yml"
  ( cd "$P82b" && git add .agent-governance.yml && git commit -qm shrink >/dev/null 2>&1 \
    && bash "$ROOT/scripts/bootstrap.sh" --upgrade . >/dev/null 2>&1 )
  check_output "T82 old profile keeps the user language" '^  language: python$' "$(cat "$P82b/.agent-governance.yml")"
  report "T82 old profile gains files" 1 "$(grep -c '^  files:' "$P82b/.agent-governance.yml" 2>/dev/null || true)"
  report "T82 old profile gains budgets" 1 "$(grep -c '^  budgets:' "$P82b/.agent-governance.yml" 2>/dev/null || true)"
  report "T82 G9 old profile gains schema_version" 1 "$(grep -c '^  schema_version:' "$P82b/.agent-governance.yml" 2>/dev/null || true)"
  rm -rf "$P82b"
fi

}

section_T83() {
# ------------------------------------------------ T83 R3 硬门 + 自举（v3.90.3，CHG-125）
new_repo
export AGENT_GUARD_ADAPT=1
GT83="$ROOT/resources/templates/agent-gate.sh"
GST83="$ROOT/resources/templates/lib-gate-staged.sh"
[[ -s "$GST83" ]] || GST83="$GT83"
if [[ ! -s "$GT83" ]]; then echo "SKIP T83: agent-gate absent — 跳过 R3 硬门 golden cases"; return 0; fi
copy_gate_to scripts agent-gate
seed_artifacts CHG-970 L2 claude/s-83
printf '# c\n\n### 用户整体确认记录\n\n- 待确认\n' > docs/changes/CHG-970/00.5-communication.md
printf '# 09\n' > docs/changes/CHG-970/09-changelog.md
af=$(git rev-parse --git-path agent-governance/active-change); mkdir -p "$(dirname "$af")"; printf 'CHG-970\n' > "$af"
out=$(scripts/agent-gate --stage staged 2>&1); report "T83 E129 L2 staged without confirmation" 2 "$?"
check_output "T83 E129 names the code" 'GATE-E129' "$out"
out=$(scripts/agent-gate preflight CHG-970 2>&1); report "T83 E130 preflight collects it" 1 "$?"
check_output "T83 E130 names the code" 'GATE-E130' "$out"
out=$(scripts/agent-gate --stage close 2>&1); report "T83 E127 close without confirmation" 2 "$?"
check_output "T83 E127 names the confirmation gap" 'no user-overall-confirmation' "$out"
printf '# c\n\n### 用户整体确认记录\n\n- 确认状态：已整体确认\n' > docs/changes/CHG-970/00.5-communication.md
out=$(scripts/agent-gate --stage close 2>&1); report "T83 E127 close without child-agent release" 2 "$?"
check_output "T83 E127 names the release gap" 'completed 子 Agent 放行' "$out"
printf '子 Agent 放行：待 07\n' >> docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 2>&1); report "T83 E127 rejects a placeholder release" 2 "$?"
printf '子 Agent 放行：sub-83 放行 00-04\n' >> docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 2>&1); report "T83 close green with prerequisites" 0 "$?"
test -s .agent-state/stage-close.json; report "T83 stage-close.json written" 0 "$?"
out=$(AGENT_GUARD_STAGE_CLOSE=0 scripts/agent-gate --stage close 2>&1); report "T83 STAGE_CLOSE=0 disables the gate" 0 "$?"
report "T83 E128 wired into delivery" 0 "$(( $(grep -h -c 'reviews_pair_check' "$GT83" "$ROOT/resources/templates/lib-gate-staged.sh" "$ROOT/scripts/lib-gate-staged.sh" 2>/dev/null | awk '{s+=$1} END{print s+0}') >= 1 ? 0 : 1 ))"
printf '#### 阶段复核\n' >> docs/changes/CHG-970/09-changelog.md
printf '# 05\n' > docs/changes/CHG-970/05-test-results.md
printf '# 04.5\n' > docs/changes/CHG-970/04.5-coding-record.md
out=$(scripts/agent-gate preflight CHG-970 2>&1); report "T83 E128 preflight negative" 1 "$?"
check_output "T83 E128 names the missing review file" 'GATE-E128' "$out"
mkdir -p docs/changes/CHG-970/reviews; printf 'ok\n' > docs/changes/CHG-970/reviews/P01.review.md
out=$(scripts/agent-gate preflight CHG-970 2>&1 || true)
report "T83 E128 quiet once the review file exists" 0 "$(printf '%s' "$out" | grep -c 'GATE-E128' || true)"
report "T83 E131 is a hard die (R3)" 0 "$(( $(grep -c 'GATE-E131:' "$GST83" || true) >= 1 ? 0 : 1 ))"
check_output "T83 bootstrap engine self-check" 'engine self-check' "$(cat "$ROOT/scripts/bootstrap.sh")"
check_output "T83 bootstrap runtime re-probe" 'runtime re-probe' "$(cat "$ROOT/scripts/bootstrap.sh")"
check_output "T83 audit writes a ledger row" 'audit' "$(sed -n '/FU-959/,+6p' "$ROOT/resources/templates/audit-docs-consistency.sh")"
report "T83 plan resolution is TC-level" 0 "$(( $(grep -c 'tc=%s' "$GST83" || true) >= 1 ? 0 : 1 ))"
check_output "T83 run p50 is full-only" 'run-full' "$(sed -n '/^plan_run_cost()/,/^}/p' "$GST83")"
# v3.90.4: review intelligence + runtime-aware model consent
report "T83 E137 consent gate is wired into delivery" 0 "$(( $(grep -c 'GATE-E137' "$GST83" || true) >= 1 ? 0 : 1 ))"
report "T83 E138 review-plan usage code present" 0 "$(( $(grep -c 'GATE-E138' "$GST83" || true) >= 1 ? 0 : 1 ))"
report "T83 begin seeds the review plan" 0 "$(( $(grep -c 'review_plan_seed' "$GST83" || true) >= 1 ? 0 : 1 ))"
check_output "T83 07 carries the input/professional contract" '评审输入契约与专业能力' "$(cat "$ROOT/resources/templates/entry/07-review-report.md")"
check_output "T83 07 carries model-cost consent" '模型选择与成本确认' "$(cat "$ROOT/resources/templates/entry/07-review-report.md")"
check_output "T83 07 carries producer-vs-reviewer independence" '独立性声明（生产 vs 评审' "$(cat "$ROOT/resources/templates/entry/07-review-report.md")"
check_output "T83 review intelligence contract ships runtime adaptation" '运行时适配' "$(cat "$ROOT/resources/methodologies/review-intelligence.md")"
# FU-126-1: AI judgment may override the runner-self-edit FULL fallback only with evidence.
out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
  AGENT_GUARD_SUITE_AI_SECTIONS="T83" \
  AGENT_GUARD_SUITE_AI_BASIS="diff only touches T83 assertions and review-plan; no shared gate state" \
  AGENT_GUARD_SUITE_AI_REVIEWER="WorkBuddy / test-model / ses-t83-ai" \
  bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
check_output "T83 AI judgment overrides runner-self-edit FULL" 'auto-resolve-only: T50 T83' "$out"
check_output "T83 AI judgment is announced with its basis" 'auto: AI judgment accepted' "$out"
out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
  AGENT_GUARD_SUITE_AI_SECTIONS="T83" AGENT_GUARD_SUITE_AI_BASIS="too short" \
  AGENT_GUARD_SUITE_AI_REVIEWER="WorkBuddy / test-model / ses-t83-ai" \
  bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
check_output "T83 AI judgment without evidence falls back to FULL" 'auto-resolve-only: FULL' "$out"
out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
  AGENT_GUARD_SUITE_AI_SECTIONS="T999" \
  AGENT_GUARD_SUITE_AI_BASIS="diff only touches T83 assertions and review-plan; no shared gate state" \
  AGENT_GUARD_SUITE_AI_REVIEWER="WorkBuddy / test-model / ses-t83-ai" \
  bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
check_output "T83 AI judgment with an unknown section falls back to FULL" 'auto-resolve-only: FULL' "$out"
# --dual-run scan + targeted run stays `run` (not run-full)
out=$(AGENT_GUARD_COST_LEDGER=/tmp/t83-ledger.tsv bash "$ROOT/tests/run-tests.sh" --dual-run -T T76 2>&1 | grep 'dual-run:' || true)
check_output "T83 dual-run prints the scan" 'unwhitelisted=' "$out"
check_output "T83 targeted run is not run-full" '0' "$(grep -c '^.*	run-full	' /tmp/t83-ledger.tsv 2>/dev/null || true)"
rm -f /tmp/t83-ledger.tsv
# v3.90.5 (CHG-126): P2-2 decision consume + P2-3 coverage + P2-5 backfill order
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 E142 strict requires a decision" 1 "$?"
check_output "T83 E142 names the code" 'GATE-E142' "$out"
scripts/agent-gate plan CHG-970 >/dev/null 2>&1
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 E143 missing hard artifact" 1 "$?"
check_output "T83 E143 names the code" 'GATE-E143' "$out"
cat > docs/changes/CHG-970/00-governance.json <<'EOF'
{"change_id":"CHG-970","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-83","test_owner":"claude/s-t","review_owner":"claude/s-r","decision":{"engine_version":"adapt/v0","chosen":"T83","artifacts":"05-test-results.md,09-changelog.md","reviews":"min=1;independent=true","stages":"staged,stop","masters":"","judges_source":"engine"}}
EOF
out=$(scripts/agent-gate preflight CHG-970 2>&1)
report "T83 coverage gap only WARNs" 0 "$(printf '%s' "$out" | grep -c 'GATE-E144' || true)"
report "T83 coverage gap is recorded in the decision log" 1 "$(grep -c 'no$' .agent-state/adapt-decisions.tsv 2>/dev/null || true)"
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 E144 strict coverage gap" 1 "$?"
check_output "T83 E144 names the code" 'GATE-E144' "$out"
printf -- '- decision-gap: coverage T83 — fixture gap\n' >> docs/changes/CHG-970/09-changelog.md
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1)
report "T83 declared coverage gap is accepted" 0 "$(printf '%s' "$out" | grep -c 'GATE-E144' || true)"
# G4: the final-plan `[adapt]` line is an accepted alias for the gap declaration.
sed 's/^- decision-gap: coverage T83 — fixture gap$/- [adapt] coverage T83 :: fixture gap :: T83 evidence/' \
  docs/changes/CHG-970/09-changelog.md > .adapt83.tmp && mv .adapt83.tmp docs/changes/CHG-970/09-changelog.md
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1)
report "T83 G4 [adapt] line clears E144" 0 "$(printf '%s' "$out" | grep -c 'GATE-E144' || true)"
printf '<!-- filled-at stage=3 chg=CHG-970 by=impl -->\n' >> docs/project/P05-task-plan.md
out=$(scripts/agent-gate --stage close 2 2>&1); report "T83 E145 P05 filled ahead of close 2" 2 "$?"
check_output "T83 E145 names the code" 'GATE-E145' "$out"
sed '/filled-at stage=3/d' docs/project/P05-task-plan.md > .p05.tmp && mv .p05.tmp docs/project/P05-task-plan.md
printf '<!-- filled-at stage=2 chg=CHG-970 by=impl -->\n' >> docs/project/P01-requirements-master.md
out=$(scripts/agent-gate --stage close 2 2>&1); report "T83 close stage 2 records P01" 0 "$?"
printf -- 'Observation: 已核对 00-04（未读回填）\n' >> docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 3 2>&1); report "T83 E146 unread backfill" 2 "$?"
check_output "T83 E146 names the code" 'GATE-E146' "$out"
sed 's/Observation: 已核对 00-04（未读回填）/Observation: 已读 P01 增量并继续/' docs/changes/CHG-970/09-changelog.md > .o83.tmp && mv .o83.tmp docs/changes/CHG-970/09-changelog.md
out=$(scripts/agent-gate --stage close 3 2>&1); report "T83 read-back Observation clears E146" 0 "$?"
# v3.91.5 (user directive): no stage may open before the previous stage's RTVM row
# exists — verified live, not just by reading the checker source.
mv docs/changes/CHG-970/01.5-rtvm-matrix.md .t83-rtvm.bak
out=$(scripts/agent-gate --stage design 2>&1); report "T83 G-RTVM design blocks without the RTVM REQ row" 2 "$?"
check_output "T83 G-RTVM names E126" 'GATE-E126' "$out"
mv .t83-rtvm.bak docs/changes/CHG-970/01.5-rtvm-matrix.md
mv docs/changes/CHG-970/01.5-rtvm-matrix.md .t83-rtvm.bak
out=$(scripts/agent-gate --stage close 2 2>&1); report "T83 G-RTVM close 2 blocks without the RTVM REQ row" 2 "$?"
mv .t83-rtvm.bak docs/changes/CHG-970/01.5-rtvm-matrix.md
# v3.91.0 (CHG-127): G3 stale / G10 status+canary / G12 must / G15–G19 observability
out=$(scripts/agent-gate status 2>&1); report "T83 G10 status exits 0" 0 "$?"
check_output "T83 G10 status names enforcement" 'enforcement=' "$out"
cp "$ROOT/resources/templates/install-hook-adapter.sh" scripts/install-hook-adapter 2>/dev/null || true
out=$(bash scripts/install-hook-adapter --canary 2>&1); report "T83 G10 canary exits 0" 0 "$?"
check_output "T83 G10 canary writes a receipt" 'canary: ok' "$out"
out=$(scripts/agent-gate resume CHG-970 2>&1); report "T83 G17 resume exits 0" 0 "$?"
check_output "T83 G17 resume prints next steps" 'resume: next:' "$out"
out=$(scripts/agent-gate resume 2>&1 || true); check_output "T83 G17 resume usage dies E149" 'GATE-E149' "$out"
out=$(scripts/agent-gate metrics 2>&1)
check_output "T83 G15 metrics carry adoption" '"adoption_rate":' "$out"
check_output "T83 G16 metrics carry wasted/stale/handshake/independence" '"wasted_rate":.*"stale_decisions":.*"handshake":.*"review_independent":' "$out"
report "T83 G18 retro line carries CPI" 1 "$(grep -c 'CPI=' "$GST83" || true)"
report "T83 G19 session-gate prints the handoff action" 2 "$(grep -c 'handoff：水位' "$ROOT/resources/templates/session-gate.sh" || true)"
report "T83 G19 token metering never fabricates 0/0" 1 "$(grep -c "printf 'unavailable'" "$ROOT/resources/templates/session-gate.sh" || true)"
# G3: a decision whose diff_hash no longer matches the live diff is stale (strict).
git add -A >/dev/null 2>&1; git commit -qm t83base >/dev/null 2>&1
scripts/agent-gate plan CHG-970 >/dev/null 2>&1
printf 'x\n' >> docs/changes/CHG-970/01-spec.md
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 G3 stale decision dies E147" 1 "$?"
check_output "T83 G3 names the code" 'GATE-E147' "$out"
git checkout -- docs/changes/CHG-970/01-spec.md >/dev/null 2>&1 || true
# v3.91.2: a NEW untracked file after `plan` invalidates the decision too —
# `git diff HEAD` alone used to miss it (silent stale).
scripts/agent-gate plan CHG-970 >/dev/null 2>&1
printf 'z\n' > .t83-untracked.zzz
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 G3 stale covers a new untracked file" 1 "$?"
check_output "T83 G3 untracked names the code" 'GATE-E147' "$out"
rm -f .t83-untracked.zzz
scripts/agent-gate plan CHG-970 >/dev/null 2>&1
# v3.91.4 (2026-10-27 二次裁定): AI proposes, the USER confirms. The confirmation
# is a recorded field, not a post-hoc label.
AGENT_GUARD_SUITE_AI_SECTIONS="T83" \
AGENT_GUARD_SUITE_AI_BASIS="T83 fixture diff touches only assertions and fixtures; no product runtime path" \
AGENT_GUARD_SUITE_AI_REVIEWER="WorkBuddy / test-model / ses-t83-ai" \
AGENT_GUARD_SCOPE_CONFIRM="user:t83@2026-10-27T00:00:00Z" \
scripts/agent-gate plan CHG-970 >/dev/null 2>&1
check_output "T83 G12 plan records the user scope confirmation" '"scope_confirmed":"user:t83@' "$(cat docs/changes/CHG-970/00-governance.json)"
# G12: a declared hard rule with a narrowed chosen is a contract violation (strict).
cat > docs/changes/CHG-970/00-governance.json <<'EOF'
{"change_id":"CHG-970","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-83","test_owner":"claude/s-t","review_owner":"claude/s-r","decision":{"engine_version":"adapt/v0","chosen":"T83","stage_list":"test,delivery","artifact_list":"05-test-results.md,09-changelog.md","must":["H7"],"reviews":"min=1;independent=true","masters":""}}
EOF
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 G12 must rule without FULL dies E148" 1 "$?"
check_output "T83 G12 names the code" 'GATE-E148' "$out"
# 2026-10-27 ruling: the AI may PROPOSE narrowing a must rule, but only WITH
# evidence AND the user's recorded confirmation.
cat > docs/changes/CHG-970/00-governance.json <<'EOF'
{"change_id":"CHG-970","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-83","test_owner":"claude/s-t","review_owner":"claude/s-r","decision":{"engine_version":"adapt/v0","chosen":"T83","judgment":"ai","scope_confirmed":"user:t83@2026-10-27T00:00:00Z","stage_list":"test,delivery","artifact_list":"05-test-results.md,09-changelog.md","must":["H7"],"reviews":"min=1;independent=true","masters":""}}
EOF
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1)
report "T83 G12 AI judgment with user confirmation narrows a must rule" 0 "$(printf '%s' "$out" | grep -c 'GATE-E148' || true)"
# Same AI decision WITHOUT the user confirmation is incomplete (strict).
cat > docs/changes/CHG-970/00-governance.json <<'EOF'
{"change_id":"CHG-970","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-83","test_owner":"claude/s-t","review_owner":"claude/s-r","decision":{"engine_version":"adapt/v0","chosen":"T83","judgment":"ai","stage_list":"test,delivery","artifact_list":"05-test-results.md,09-changelog.md","must":["H7"],"reviews":"min=1;independent=true","masters":""}}
EOF
out=$(AGENT_GUARD_PLAN_STRICT=1 scripts/agent-gate preflight CHG-970 2>&1); report "T83 G12 AI judgment without user confirmation dies E148" 1 "$?"
check_output "T83 G12 missing confirmation names the code" 'GATE-E148' "$out"
# ---- TC-1555: self-bootstrap VERIFIED WITH CHG-124's real artifacts (copy only) ----
S83=$(mktemp -d "${TMPDIR:-/tmp}/selfboot.XXXXXX")
mkdir -p "$S83/scripts" "$S83/docs/changes"
copy_gate_to "$S83/scripts" agent-gate
cp "$ROOT/resources/templates/session-gate.sh" "$S83/scripts/session-gate.sh"
cp "$ROOT/resources/templates/install-hook-adapter.sh" "$S83/scripts/install-hook-adapter.sh"
cp "$ROOT/resources/templates/audit-docs-consistency.sh" "$S83/scripts/audit-docs-consistency.sh"
# v3.91.9 (CHG-127): seed the fixture instead of copying docs/changes/CHG-124 —
# the private docs face is gitignored (CHG-017), so a fresh checkout has nothing
# to copy and 9 self-boot assertions died. A seeded fixture proves self-boot on
# any clone, CI or not.
( cd "$S83" && seed_artifacts CHG-124 L2 claude/s-83 )
( cd "$S83" && git init -q . && git config user.email t@e.invalid && git config user.name t && git add -A >/dev/null 2>&1 && git commit -qm seed >/dev/null 2>&1 )
out=$( cd "$S83" && bash scripts/agent-gate plan CHG-124 2>&1 ); report "T83 self-boot plan on CHG-124 copy" 0 "$?"
( cd "$S83" && bash scripts/agent-gate plan CHG-124 >/dev/null 2>&1 )
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$S83/docs/changes/CHG-124/00-governance.json" >/dev/null 2>&1
  report "T83 self-boot CHG-124 JSON valid after re-plan" 0 "$?"
fi
report "T83 self-boot decision stays unique" 0 "$(( $(grep -o '"decision"' "$S83/docs/changes/CHG-124/00-governance.json" | wc -l | tr -d ' ') - 1 ))"
out=$( cd "$S83" && bash scripts/session-gate.sh start >/dev/null 2>&1; bash scripts/session-gate.sh count tool Bash x >/dev/null 2>&1; bash scripts/session-gate.sh status 2>&1 )
check_output "T83 self-boot CHG-123 cost line still prints" '成本：' "$out"
r83=$( cd "$S83" && env -u CLAUDECODE -u OPENCODE -u OPENCODE_SESSION_ID -u CURSOR_AGENT -u CURSOR_TRACE_ID -u GEMINI_CLI -u CODEX_HOME PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect >/dev/null 2>&1; echo $? )
report "T83 self-boot unknown runtime exits 3" 3 "$r83"
mkdir -p "$S83/.claude"
out=$( cd "$S83" && env -u CLAUDECODE -u OPENCODE -u OPENCODE_SESSION_ID -u CURSOR_AGENT -u CURSOR_TRACE_ID -u GEMINI_CLI -u CODEX_HOME PATH=/usr/bin:/bin bash scripts/install-hook-adapter.sh --detect 2>&1 )
check_output "T83 self-boot family classification still works" 'claude \(json-hooks\)' "$out"
out=$( cd "$S83" && bash scripts/audit-docs-consistency.sh --since HEAD 2>&1 | head -1 )
check_output "T83 CHG-123 audit --since no-op path" 'declared no-op' "$out"
# v3.90.4: runtime-aware review plan + user-only consent on the CHG-124 copy
out=$( cd "$S83" && bash scripts/agent-gate review-plan CHG-124 2>&1 )
check_output "T83 review-plan detects the runtime" 'runtime=claude' "$out"
check_output "T83 review-plan names the family" 'family=json-hooks' "$out"
check_output "T83 review-plan names a viable execution scheme" 'scheme=(in-session-independent-subagent|multi-runtime-choose-one)' "$out"
printf '%s\n' '{"models":[{"id":"deep-test","provider":"v","tier":"deep","approval":true,"strengths":["code","handoff","architecture","business","bug"]}]}' > "$S83/deep-models.json"
out=$( cd "$S83" && AGENT_GUARD_REVIEW_MODELS="$S83/deep-models.json" bash scripts/agent-gate review-plan CHG-124 2>&1 )
check_output "T83 review-plan flags high-cost consent" 'approval_required=true' "$out"
r83=$( cd "$S83" && AGENT_GUARD_REVIEW_MODELS="$S83/deep-models.json" bash scripts/agent-gate review-plan CHG-124 --approve deep-test >/dev/null 2>&1; echo $? )
report "T83 review-plan refuses AI self-approval" 3 "$r83"
out=$( cd "$S83" && AGENT_REVIEW_USER_APPROVED=1 AGENT_GUARD_REVIEW_MODELS="$S83/deep-models.json" bash scripts/agent-gate review-plan CHG-124 --approve deep-test 2>&1 )
check_output "T83 user approval is recorded" '"approved":true' "$out"
rm -rf "$S83"

}

section_T84() {
# ------------------------------------------------ T84 交付门：环境/证据/独立/范围/反馈（v3.92.0，CHG-128）
# TC↔REQ：TC-10000/10001→REQ-1278（fresh-clone receipt），TC-10002→REQ-1279（red→green），
# TC-10003→REQ-1280（verification_owner），TC-10004→REQ-1281（scope budget），
# TC-10005→REQ-1282（pre-push G-FEED hint）。
export AGENT_GUARD_CORE_PATHS='^core\.txt$'
new_repo
# v3.92.3 fix: pin the fixture roots after new_repo cleared host overrides. The
# fixture writes docs/changes; host config (e.g. doc/changes) must not retarget it.
export AGENT_GUARD_DOCS_DIR=docs
export AGENT_GUARD_CHANGE_ROOT=docs/changes
# v3.92.3 fix: target repos do not ship resources/templates/pre-push; use the
# installed <githooks>/pre-push there. Source repos keep the template as canonical.
t84_prepush=""
for _t84_p in "$ROOT/resources/templates/pre-push" "$ROOT/.githooks/pre-push"; do
  [[ -f "$_t84_p" ]] && { t84_prepush="$_t84_p"; break; }
done
mkdir -p docs/changes/CHG-1200 .agent-state
printf '.agent-state/\n' > .gitignore   # 收据不进 tracked 树（否则写入即自指，tree_sha 永不匹配）
printf '{"change_id":"CHG-1200","risk_level":"L2","spec_author":"s","implementation_owner":"a","test_owner":"t","review_owner":"r"}\n' > docs/changes/CHG-1200/00-governance.json
printf '# 05\n' > docs/changes/CHG-1200/05-test-results.md
mkdir -p "$(dirname "$(git rev-parse --git-path agent-governance/active-change)")"
printf 'CHG-1200\n' > "$(git rev-parse --git-path agent-governance/active-change)"
echo core > core.txt
git add -A >/dev/null 2>&1 && git commit -qm t84-core >/dev/null 2>&1
echo dirty >> core.txt   # live core change (worktree)
# receipt 必须绑定当前 tracked 树（head + tree_sha），与 gate 的 E153 判定同口径
t84_receipt() {
  printf '{"head":"%s","tree_sha":"%s","audit_rc":0,"suite_rc":0}\n' \
    "$(git rev-parse HEAD)" "$(git ls-files -z | xargs -0 cksum 2>/dev/null | cksum | awk '{print $1}')" \
    > .agent-state/fresh-clone-receipt.json
}

# ① E149 缺 receipt
out=$(scripts/agent-gate --stage core 2>&1); report "T84 E153 missing fresh-clone receipt is refused" 2 "$?"
check_output "T84 E153 names the code" 'GATE-E153' "$out"
# ② 绿 receipt → E150（缺 red→green）
t84_receipt
out=$(scripts/agent-gate --stage core 2>&1); report "T84 E153 green receipt passes, E150 then refuses" 2 "$?"
check_output "T84 E150 names the code" 'GATE-E150' "$out"
# ③ placeholder 也算缺
printf 'red_repro: FILL\n' >> docs/changes/CHG-1200/05-test-results.md
t84_receipt
out=$(scripts/agent-gate --stage core 2>&1)
check_output "T84 E150 placeholder alone is refused" 'GATE-E150' "$out"
# ④ 真两行（覆盖占位）→ E151（无 verification_owner）
printf '# 05\nred_repro: cmd -> FAIL rc1\ngreen_after: cmd -> 0\n' > docs/changes/CHG-1200/05-test-results.md
t84_receipt
out=$(scripts/agent-gate --stage core 2>&1); report "T84 E150 complete evidence passes, E151 then refuses" 2 "$?"
check_output "T84 E151 names the code" 'GATE-E151' "$out"
# ⑤ 同主体仍拒
printf '{"change_id":"CHG-1200","risk_level":"L2","spec_author":"s","implementation_owner":"a","test_owner":"t","review_owner":"r","verification_owner":"a"}\n' > docs/changes/CHG-1200/00-governance.json
t84_receipt
out=$(scripts/agent-gate --stage core 2>&1)
check_output "T84 E151 same owner is refused" 'GATE-E151' "$out"
# ⑥ 独立主体 → 绿
printf '{"change_id":"CHG-1200","risk_level":"L2","spec_author":"s","implementation_owner":"a","test_owner":"t","review_owner":"r","verification_owner":"v"}\n' > docs/changes/CHG-1200/00-governance.json
t84_receipt
out=$(scripts/agent-gate --stage core 2>&1); report "T84 core gate green with receipt + evidence + independent owner" 0 "$?"
# ⑦ 豁免：自验证开关（无 verification_owner）→ 绿 + WARN
printf '{"change_id":"CHG-1200","risk_level":"L2","spec_author":"s","implementation_owner":"a","test_owner":"t","review_owner":"r"}\n' > docs/changes/CHG-1200/00-governance.json
t84_receipt
out=$(AGENT_GUARD_ALLOW_SELF_VERIFY=1 scripts/agent-gate --stage core 2>&1); report "T84 E151 self-verify exemption passes" 0 "$?"
check_output "T84 exemption is announced" 'ALLOW_SELF_VERIFY' "$out"
# ⑧ 树变化（tracked 内容改动）→ E153（tree_sha 为唯一绑定：盖章只动未跟踪 docs）
printf '{"change_id":"CHG-1200","risk_level":"L2","spec_author":"s","implementation_owner":"a","test_owner":"t","review_owner":"r","verification_owner":"v"}\n' > docs/changes/CHG-1200/00-governance.json
git add -A >/dev/null 2>&1 && git commit -qm t84-next >/dev/null 2>&1
echo more >> core.txt
out=$(scripts/agent-gate --stage core 2>&1)
check_output "T84 E153 stale receipt is refused" 'GATE-E153' "$out"
# ⑨ 关闭开关 → 降级 WARN 且放行
out=$(AGENT_GUARD_FRESH_CLONE=0 scripts/agent-gate --stage core 2>&1); report "T84 E153 fresh-clone switch degrades to WARN" 0 "$?"
check_output "T84 degradation is announced" 'AGENT_GUARD_FRESH_CLONE=0' "$out"

# ⑩ E152：超预算且无用户确认 → 拒；有确认/未超预算 → 绿
printf '{"change_id":"CHG-1200","risk_level":"L2","spec_author":"s","implementation_owner":"a","test_owner":"t","review_owner":"r","verification_owner":"v","decision":{"chosen":"FULL","scope_confirmed":"","scope_overrun":{"batches":9,"core_files":2,"threshold_batches":5,"threshold_core_files":10,"verdict":"over"}}}\n' > docs/changes/CHG-1200/00-governance.json
out=$(scripts/agent-gate --stage scope 2>&1); report "T84 E152 over-budget without confirmation is refused" 2 "$?"
check_output "T84 E152 names the code" 'GATE-E152' "$out"
sed -i '' 's/"scope_confirmed":""/"scope_confirmed":"user@2026-10-27T00:00:00Z"/' docs/changes/CHG-1200/00-governance.json 2>/dev/null \
  || sed -i 's/"scope_confirmed":""/"scope_confirmed":"user@2026-10-27T00:00:00Z"/' docs/changes/CHG-1200/00-governance.json
out=$(scripts/agent-gate --stage scope 2>&1); report "T84 E152 user-confirmed scope passes" 0 "$?"
sed -i '' 's/"verdict":"over"/"verdict":"ok"/' docs/changes/CHG-1200/00-governance.json 2>/dev/null \
  || sed -i 's/"verdict":"over"/"verdict":"ok"/' docs/changes/CHG-1200/00-governance.json
out=$(AGENT_GUARD_SCOPE_OVERRUN=0 scripts/agent-gate --stage scope 2>&1); report "T84 E152 not-over verdict stays green" 0 "$?"
# ⑪ plan 把批次事实写进 decision（new_repo 默认 ADAPT=0，plan 用例须显式开启，同 T82）
export AGENT_GUARD_ADAPT=1
printf '#### 第一批：a\n#### 第二批：b\n#### 第三批：c\n#### 第四批：d\n#### 第五批：e\n#### 第六批：f\n' > docs/changes/CHG-1200/09-changelog.md
out=$(AGENT_GUARD_SCOPE_MAX_BATCHES=5 scripts/agent-gate plan CHG-1200 --dry-run 2>&1)
check_output "T84 plan records the batch count as a fact" '"scope_overrun":{"batches":6,"core_files":' "$out"
check_output "T84 plan marks the overrun verdict" '"verdict":"over"' "$out"

# ⑫ G-FEED：非 main + GitHub 远端 → 提示；main / 无远端 → 静默
if [[ -n "$t84_prepush" ]]; then
  git remote add origin https://github.com/example/t84.git
  git checkout -q -b feature/t84 2>/dev/null || true
  out=$(bash "$t84_prepush" 2>&1 || true)
  check_output "T84 G-FEED hints a draft PR on a non-main GitHub branch" 'G-FEED tip' "$out"
  git checkout -q main 2>/dev/null || git checkout -q -b main
  out=$(bash "$t84_prepush" 2>&1 || true)
  report "T84 G-FEED stays silent on main" 0 "$(printf '%s' "$out" | grep -c 'G-FEED tip')"
  git checkout -q feature/t84 2>/dev/null || true
  git remote remove origin
  out=$(bash "$t84_prepush" 2>&1 || true)
  report "T84 G-FEED stays silent without a GitHub remote" 0 "$(printf '%s' "$out" | grep -c 'G-FEED tip')"
else
  echo "SKIP T84 G-FEED: pre-push absent (source template and <githooks>/pre-push both missing)"
fi

# ⑬ fresh-clone-check --check：绿/陈旧/FULL 拒绝
t84_receipt
out=$(bash "$ROOT/tests/fresh-clone-check.sh" --root "$PWD" --check 2>&1); report "T84 fresh-clone --check accepts a green receipt" 0 "$?"
check_output "T84 fresh-clone --check names the head" 'receipt green for' "$out"
printf '{"head":"%s","tree_sha":"deadbeef","audit_rc":0,"suite_rc":0}\n' "$(git rev-parse HEAD)" > .agent-state/fresh-clone-receipt.json
out=$(bash "$ROOT/tests/fresh-clone-check.sh" --root "$PWD" --check 2>&1); report "T84 fresh-clone --check rejects a stale receipt" 1 "$?"
out=$(bash "$ROOT/tests/fresh-clone-check.sh" --sections FULL 2>&1); report "T84 fresh-clone refuses an auto-resolved FULL" 2 "$?"
check_output "T84 fresh-clone FULL refusal points at sections" 'full runs belong to CI' "$out"

# ⑭ 收据台账（v3.92.1）：同变更多次生成且无理由 → WARN；登记理由 → 干净
printf '%s\tCHG-1200\thead1\tt1\tT1\t1\t0\n%s\tCHG-1200\thead2\tt2\tT1\t1\t0\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/fresh-clone-history.tsv
out=$(AGENT_GUARD_FRESH_CLONE_HISTORY="$PWD/.agent-state/fresh-clone-history.tsv" bash "$ROOT/tests/fresh-clone-check.sh" --root "$PWD" --ledger-check 2>&1); t84_rc=$?
report "T84 ledger warns on repeated receipts without a reason" 1 "$t84_rc"
check_output "T84 ledger points at the reason line" 'fresh-clone re-run' "$out"
printf -- '- fresh-clone re-run: verified after the T50 tail fix\n' >> docs/changes/CHG-1200/09-changelog.md
out=$(AGENT_GUARD_FRESH_CLONE_HISTORY="$PWD/.agent-state/fresh-clone-history.tsv" bash "$ROOT/tests/fresh-clone-check.sh" --root "$PWD" --ledger-check 2>&1); report "T84 ledger accepts a recorded reason" 0 "$?"
# ⑭b repeat guard (v3.92.4, CHG-129): the history above already holds 2 receipts
t84_rc=0
out=$(AGENT_GUARD_REPEAT_LIMIT=2 bash "$ROOT/tests/fresh-clone-check.sh" --root "$PWD" --sections FULL 2>&1) || t84_rc=$?
report "T84 repeat guard keeps the FULL refusal (rc 2)" 2 "$t84_rc"
report "T84 fresh-clone repeat guard warns at the limit" 1 "$(printf '%s\n' "$out" | grep -c 'repeat guard')"
check_output "T84 repeat guard names the receipt count" 'already has 2 receipt' "$out"
out=$(AGENT_GUARD_REPEAT_LIMIT=0 bash "$ROOT/tests/fresh-clone-check.sh" --root "$PWD" --sections FULL 2>&1) || true
report "T84 repeat guard stays silent at limit 0" 0 "$(printf '%s\n' "$out" | grep -c 'repeat guard')"

# ⑮ E154 未验证 REQ 清单（v3.92.2）：⬜ REQ 必须被 09 逐条声明，否则拒
printf '# spec\n- REQ-001: x\n- REQ-002: y\n' > docs/changes/CHG-1200/01-spec.md
printf '# RTVM\n| REQ | 简述 | DES | 方案 | TASK | CHG | TC | 方法 | 验证状态 |\n|---|---|---|---|---|---|---|---|---|\n| REQ-001 | x | DES-001 | d | T-001 | c | TC-001 | m | ✅ PASS |\n| REQ-002 | y | DES-002 | d | T-002 | c | TC-002 | m | ⬜ |\n' > docs/changes/CHG-1200/01.5-rtvm-matrix.md
out=$(scripts/agent-gate --stage rtvm 2>&1); report "T84 E154 missing 未验证 REQ 清单 is refused" 2 "$?"
check_output "T84 E154 names the code" 'GATE-E154' "$out"
printf '\n#### 未验证 REQ 清单\n- 无\n' >> docs/changes/CHG-1200/09-changelog.md
out=$(scripts/agent-gate --stage rtvm 2>&1)
check_output "T84 E154 undeclared unverified REQ is refused" 'GATE-E154' "$out"
printf -- '- REQ-002：本期仅落 action 字段；样本/六类枚举/溯源待到 FU-128-1\n' >> docs/changes/CHG-1200/09-changelog.md
out=$(scripts/agent-gate --stage rtvm 2>&1); report "T84 E154 declared unverified REQ passes" 0 "$?"
# ⑯ FU-130-9 counterexample (v3.94.0, CHG-131 REQ-1316): a REQ cited in 01-spec
# with NO 01.5 row is the defect's hiding place. The old `grep … | head -1` under
# pipefail returned rc=1 for it and set -e killed the WHOLE gate with no output —
# invisible to ⑮ because ⑮ only covered "row present, ⬜ undeclared".
printf '# spec\n- REQ-001: x\n- REQ-002: y\n- REQ-003: cited from an older change, no 01.5 row\n' > docs/changes/CHG-1200/01-spec.md
out=$(scripts/agent-gate --stage rtvm 2>&1); t84_rc=$?
report "T84 FU-130-9 cited-but-unrowed REQ passes rtvm (rc 0, no silent abort)" 0 "$t84_rc"
report "T84 FU-130-9 no GATE-E154 for an unrowed REQ" 0 "$(printf '%s\n' "$out" | grep -c 'GATE-E154')"
# the same run must still die LOUDLY (rc 2 + code) when a rowed REQ is undeclared
printf '# 09\n#### 未验证 REQ 清单\n- 无\n' > docs/changes/CHG-1200/09-changelog.md
out=$(scripts/agent-gate --stage rtvm 2>&1); t84_rc=$?
report "T84 FU-130-9 rowed undeclared REQ still refused (rc 2, not 1)" 2 "$t84_rc"
check_output "T84 FU-130-9 refusal names the code" 'GATE-E154' "$out"
printf '# 09\n#### 未验证 REQ 清单\n- REQ-002：本期仅落 action 字段；样本待到 FU-128-1\n' > docs/changes/CHG-1200/09-changelog.md
out=$(scripts/agent-gate --stage rtvm 2>&1); report "T84 FU-130-9 fixed gate stays green with unrowed REQ + declaration" 0 "$?"
# F3 (review, refined by shard evidence): 01.5 missing while 01-spec exists
# must be judged CANNOT-PASS — never a silent "rtvm gate green". 09 missing
# mid-change stays SILENT by design: 09 is the closure marker (begin refuses
# when it exists), so staged/pre-commit legitimately run without it; the E154
# declaration contract bites at stop, where the changelog is mandatory.
rm docs/changes/CHG-1200/09-changelog.md
out=$(scripts/agent-gate --stage rtvm 2>&1); t84_rc=$?
report "T84 missing 09 mid-change stays silent (closure marker; E154 bites at stop)" 0 "$t84_rc"
report "T84 missing-09 run prints no GATE-E154" 0 "$(printf '%s\n' "$out" | grep -c 'GATE-E154')"
mv docs/changes/CHG-1200/01.5-rtvm-matrix.md docs/changes/CHG-1200/01.5.hold
out=$(scripts/agent-gate --stage rtvm 2>&1); t84_rc=$?
report "T84 E154 missing 01.5 while 01-spec exists is refused" 2 "$t84_rc"
check_output "T84 E154 missing-01.5 refusal names the code" 'GATE-E154.*01.5' "$out"
mv docs/changes/CHG-1200/01.5.hold docs/changes/CHG-1200/01.5-rtvm-matrix.md
# v3.92.3 fix: do not leak the fixture's pinned roots into a later section
# (canonical order puts T84 last, but -T subsets / shards must stay hermetic).
t84_cf=$(mktemp -d)
(
  cd "$t84_cf"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  mkdir -p scripts doc/changes/CHG-1201 .agent-state .git/agent-governance
  copy_gate_to "$t84_cf/scripts" agent-gate
  cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" scripts/lib-suite-tree-fingerprint.sh
  printf 'docs_dir: doc\nchange_root: doc/changes\ncore_paths: core_v1.sh\n' > .agent-governance.yml
  printf '#!/usr/bin/env bash\necho v1\n' > core_v1.sh
  printf '# Intent\n' > doc/changes/CHG-1201/00-intent.md
  printf '{"change_id":"CHG-1201","risk_level":"L2","verification_owner":"qa"}\n' > doc/changes/CHG-1201/00-governance.json
  printf 'red_repro: err\ngreen_after: ok\n## 还原度断言\n不适用\n' > doc/changes/CHG-1201/05-test-results.md
  printf '独立复核: subagent task-1201\n' > doc/changes/CHG-1201/07-review-report.md
  git add -A && git commit -q -m "init"
  printf 'CHG-1201\n' > .git/agent-governance/active-change
  . scripts/lib-suite-tree-fingerprint.sh
  cface=$(suite_tree_fingerprint "$t84_cf" "doc/changes" "doc/bugs" "doc/project" 2>/dev/null)
  head_sha=$(git rev-parse HEAD)
  printf '{"head":"%s","tree_sha":"doc-only-drift","code_face_sha":"%s","audit_rc":0,"suite_rc":0}\n' "$head_sha" "$cface" > .agent-state/fresh-clone-receipt.json
  printf '\n<!-- doc-only update -->\n' >> doc/changes/CHG-1201/00-intent.md
  env -u AGENT_GUARD_FRESH_CLONE AGENT_GUARD_DOCS_DIR=doc AGENT_GUARD_CHANGE_ROOT=doc/changes AGENT_GUARD_CORE_PATHS=core_v1.sh bash scripts/agent-gate --stage core >/dev/null 2>&1
)
report "T84 TC-10023 custom --docs-dir doc reuses green code_face_sha on doc drift" 0 $?
out=$(
  cd "$t84_cf"
  printf 'echo v2_unstaged\n' >> core_v1.sh
  env -u AGENT_GUARD_FRESH_CLONE AGENT_GUARD_DOCS_DIR=doc AGENT_GUARD_CHANGE_ROOT=doc/changes AGENT_GUARD_CORE_PATHS=core_v1.sh bash scripts/agent-gate --stage core 2>&1 || true
)
check_output "T84 TC-10022 E153 rejects unstaged code edit despite matching index" "GATE-E153" "$out"
rm -rf "$t84_cf"
unset AGENT_GUARD_DOCS_DIR AGENT_GUARD_CHANGE_ROOT AGENT_GUARD_CORE_PATHS
}

section_T85() {
# ------------------------------------------------ T85 repeat-run guard（v3.92.4，CHG-129）
# TC↔REQ：TC-1560/1571→REQ-1285，TC-1561/1562/1563/1565→REQ-1286，TC-1564/1566→REQ-1287。
# Every case drives a CHILD runner: the parent already exported
# AGENT_GUARD_SUITE_NESTED=1, so the child gets it forced back to 0 and an
# isolated state file. T41 is the cheapest section (one grep).
t85_dir=$(mktemp -d "${TMPDIR:-/tmp}/t85-repeat.XXXXXX") || t85_dir=""
t85_state="$t85_dir/repeats.tsv"
t85_err="$t85_dir/err.log"
t85_key="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)|T41"
t85_seed() { # <ts> <n>
  : > "$t85_state"
  local i=0
  while [[ "$i" -lt "$2" ]]; do
    printf '%s\t%s\tT41\t1\t1\n' "$1" "$t85_key" >> "$t85_state"
    i=$(( i + 1 ))
  done
}
t85_run() { # <limit> <nested>
  t85_out=$(AGENT_GUARD_SUITE_NESTED="$2" AGENT_GUARD_REPEAT_LIMIT="$1" \
    AGENT_GUARD_REPEAT_STATE_PATH="$t85_state" \
    AGENT_GUARD_COST_LEDGER="$t85_dir/ledger.tsv" \
    AGENT_GUARD_SUITE_PROGRESS_PATH="$t85_dir/progress.json" \
    bash "$ROOT/tests/run-tests.sh" -T T41 2>"$t85_err"); t85_rc=$?
}
report "T85 repeat guard is wired at the dispatcher" 1 "$(grep -c '^_repeat_limit=' "$ROOT/tests/run-tests.sh")"
t85_now=$(date +%s)
t85_seed "$t85_now" 3
t85_run 3 0
report "T85 over-limit run warns on stderr" 1 "$(grep -c 'repeat guard' "$t85_err")"
report "T85 warning names the prior count and limit" 1 "$(grep -c 'already ran 3 time(s).*limit 3' "$t85_err")"
report "T85 over-limit run is non-blocking" 0 "$t85_rc"
report "T85 warning never reaches stdout" 0 "$(printf '%s\n' "$t85_out" | grep -c 'repeat guard')"
report "T85 run appends exactly one fingerprint row" 4 "$(wc -l < "$t85_state" | tr -d ' ')"
t85_seed "$t85_now" 3
t85_run 0 0
report "T85 limit 0 stays silent" 0 "$(grep -c 'repeat guard' "$t85_err")"
report "T85 limit 0 leaves the state untouched" 3 "$(wc -l < "$t85_state" | tr -d ' ')"
t85_seed "$(( t85_now - 7200 ))" 3
t85_run 3 0
report "T85 stale rows do not warn" 0 "$(grep -c 'repeat guard' "$t85_err")"
report "T85 stale rows are pruned before appending" 1 "$(wc -l < "$t85_state" | tr -d ' ')"
t85_seed "$t85_now" 3
t85_run 3 1
report "T85 nested child stays silent" 0 "$(grep -c 'repeat guard' "$t85_err")"
report "T85 nested child does not append" 3 "$(wc -l < "$t85_state" | tr -d ' ')"
mkdir -p "$t85_dir/ro" && chmod 500 "$t85_dir/ro"
t85_out=$(AGENT_GUARD_SUITE_NESTED=0 AGENT_GUARD_REPEAT_LIMIT=3 \
  AGENT_GUARD_REPEAT_STATE_PATH="$t85_dir/ro/repeats.tsv" \
  AGENT_GUARD_COST_LEDGER="$t85_dir/ledger.tsv" \
  AGENT_GUARD_SUITE_PROGRESS_PATH="$t85_dir/progress.json" \
  bash "$ROOT/tests/run-tests.sh" -T T41 2>"$t85_dir/ro.err"); t85_rc=$?
chmod 700 "$t85_dir/ro" 2>/dev/null || true
report "T85 unwritable state degrades silently (rc unchanged)" 0 "$t85_rc"
report "T85 unwritable state prints no guard noise" 0 "$(grep -c 'repeat guard' "$t85_dir/ro.err")"
# CHG-129 review fix: "08" is octal syntax in $(( )) — the limit must parse.
t85_seed "$t85_now" 3
t85_run 08 0
report "T85 leading-zero limit parses without arithmetic noise" 0 "$(grep -c 'value too great\|syntax error' "$t85_err")"
report "T85 limit 08 counts as 8 (3 prior rows stay silent)" 0 "$(grep -c 'repeat guard' "$t85_err")"
rm -rf "$t85_dir"
}

section_T86() {
# ------------------------------------------------ T86 dispatch contract v2（v3.94.0，CHG-131）
# TC↔REQ：TC-2310→REQ-1310/1311（契约与三入口），TC-2311→REQ-1312（五标签模板），
# TC-2312→REQ-1313/1314（版本化 + E17 v2 三分支），TC-2313→REQ-1315（生成器），
# TC-2314→REQ-1316（FU-130-9 反例，见 T84 ⑯）。
export AGENT_GUARD_STAGE_GATES=0
new_repo
local t86_rc out
out=$(AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 --scaffold --risk L2 2>&1); t86_rc=$?
report "T86 scaffold exits 0" 0 "$([[ $t86_rc -eq 0 ]] && echo 0 || echo 1)"
t86_d=docs/changes/t86
report "T86 scaffold carries dispatch_contract v2" 1 "$(grep -c '"dispatch_contract": "v2"' "$t86_d/00-governance.json")"
report "T86 scaffold 03.5 carries the five dispatch labels" 5 "$(grep -cE '^- (项目背景|变更上下文|证据包|专业与历史|独立与成本)：' "$t86_d/03.5-tasks.md")"
# fill the scaffold the way T64 does, then the same gate must go green
for tf in "$t86_d"/00-intent.md "$t86_d"/00.5-communication.md "$t86_d"/01-spec.md "$t86_d"/02-code-impact-analysis.md "$t86_d"/03-modification-plan.md "$t86_d"/03.5-tasks.md "$t86_d"/04-test-scripts.md; do
  sed -i '' 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf" 2>/dev/null \
    || sed -i 's/确认状态：待确认/确认状态：已整体确认/; s/<!-- FILL[^>]* -->/已填/g; s/<标题：一句话>/已填/' "$tf"
done
AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 >/dev/null 2>&1
report "T86 filled v2 03.5 passes begin (E17 v2 green)" 0 $?
cp "$t86_d/03.5-tasks.md" t86.35.bak
# missing / empty / placeholder: each is an E17 die, never a silent pass
grep -v '^- 项目背景：' t86.35.bak > "$t86_d/03.5-tasks.md"
out=$(AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 2>&1)
check_output "T86 E17 v2 refuses a missing label" 'GATE-E17.*项目背景' "$out"
sed 's/^- 变更上下文：.*/- 变更上下文：/' t86.35.bak > "$t86_d/03.5-tasks.md"
out=$(AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 2>&1)
check_output "T86 E17 v2 refuses an empty value (byte-safe strip)" 'GATE-E17.*变更上下文.*is empty' "$out"
sed 's/^- 证据包：.*/- 证据包：<!-- FILL: x -->/' t86.35.bak > "$t86_d/03.5-tasks.md"
out=$(AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 2>&1)
check_output "T86 E17 v2 refuses a placeholder value" 'still holds a placeholder' "$out"
sed 's/^- 证据包：.*/- 证据包: 已填（ascii colon）/' t86.35.bak > "$t86_d/03.5-tasks.md"
AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 >/dev/null 2>&1
report "T86 E17 v2 accepts an ascii colon" 0 $?
# F1 恒检 (review): the v2 lane sits OUTSIDE the 直接实施 exemption — an
# exemption marker must not buy a silent pass on a missing label.
grep -v '^- 项目背景：' t86.35.bak > "$t86_d/03.5-tasks.md"
printf -- '- 直接实施（豁免）：恒检夹具——豁免不豁免派发契约\n' >> "$t86_d/03.5-tasks.md"
out=$(AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 2>&1)
check_output "T86 E17 v2 fires even under the 直接实施 exemption" 'GATE-E17.*项目背景' "$out"
cp t86.35.bak "$t86_d/03.5-tasks.md"
# legacy change (no version field) keeps the v3.39.0 substring judgement
cp "$t86_d/00-governance.json" t86.gov.bak
printf '# tasks\n\n依赖：单链。\n里程碑：M1=now。\n\n- 评审输入: x\n' > "$t86_d/03.5-tasks.md"
sed 's/, "dispatch_contract": "v2"//' t86.gov.bak > "$t86_d/00-governance.json"
AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 >/dev/null 2>&1
report "T86 legacy change without the field keeps the 评审输入 judgement" 0 $?
# explicit downgrade is visible, never silent — and it must stay green on a
# V2-SHAPED 03.5 (five labels present), not just on legacy text (review F2)
cp t86.gov.bak "$t86_d/00-governance.json"
cp t86.35.bak "$t86_d/03.5-tasks.md"
out=$(AGENT_GUARD_DISPATCH_CONTRACT=v1 AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 2>&1)
check_output "T86 AGENT_GUARD_DISPATCH_CONTRACT=v1 warns" 'downgraded to v1' "$out"
AGENT_GUARD_DISPATCH_CONTRACT=v1 AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS=1 bash scripts/agent-gate begin t86 >/dev/null 2>&1
report "T86 downgrade keeps a v2-shaped 03.5 green (escape hatch, not a block)" 0 $?
# dispatch generator: text, json, gaps, active-change default, read-only, usage
out=$(bash scripts/agent-gate dispatch design t86 2>&1); t86_rc=$?
report "T86 dispatch design exits 0" 0 "$t86_rc"
report "T86 dispatch prints all nine P sections" 9 "$(printf '%s\n' "$out" | grep -c '^## P[0-8]')"
check_output "T86 dispatch names contract v2" 'contract=v2' "$out"
check_output "T86 dispatch carries the risk level" '风险 L2' "$out"
report "T86 dispatch reports a missing input as [gap]" 1 "$(printf '%s\n' "$out" | grep -c '^- \[gap\] P4 缺 .*bugfix-log')"
out=$(bash scripts/agent-gate dispatch review --json 2>&1); t86_rc=$?
report "T86 dispatch --json resolves the ACTIVE change" 0 "$t86_rc"
check_output "T86 dispatch --json declares contract v2" '"contract":"v2"' "$out"
report "T86 dispatch --json carries p0..p8" 9 "$(printf '%s\n' "$out" | grep -o '"p[0-8]":' | sort -u | wc -l | tr -d ' ')"
t86_before=$(git status --porcelain; ls .agent-state)
bash scripts/agent-gate dispatch review t86 >/dev/null 2>&1
t86_after=$(git status --porcelain; ls .agent-state)
report "T86 dispatch writes nothing (read-only)" 0 "$([[ "$t86_before" == "$t86_after" ]] && echo 0 || echo 1)"
out=$(bash scripts/agent-gate dispatch 2>&1); t86_rc=$?
report "T86 dispatch without a stage is E155 (rc 2)" 2 "$t86_rc"
check_output "T86 dispatch usage error names E155" 'GATE-E155' "$out"
bash scripts/agent-gate dispatch bogus t86 >/dev/null 2>&1
report "T86 dispatch unknown stage is E155 (rc 2)" 2 "$?"
bash scripts/agent-gate dispatch design CHG-9999 >/dev/null 2>&1
report "T86 dispatch unknown change is E155 (rc 2)" 2 "$?"
rm -f t86.35.bak t86.gov.bak
unset AGENT_GUARD_STAGE_GATES
}

section_T87() {
# ------------------------------------------------ T87 套件基建并行与缓存（v3.95.0，CHG-132）
# REQ-1321 --worktree 快照、REQ-1322 shard-sum、REQ-1324 分节缓存的 golden 节。
# 快照携带未提交代码是结构性的：本节只存在于未提交树，HEAD 快照跑不出这一节
# （-T T87 自证）。审计分块并行（REQ-1323）的行为等价在证据轮一次性证毕，本节
# 只做结构 pin（见 tests/audit-standards-src.sh A63）。
  cd "$ROOT"
  if [[ "${AGENT_GUARD_SUITE_IN_WT:-0}" == "1" ]]; then
    report "T87 executes inside the worktree snapshot (carry proven)" 0 0
    return 0
  fi
  # REQ-1321: snapshot carry — the inner run must find T87 in the snapshot.
  # v3.97.1 (CHG-135): the nested run gets its own ledger so its rows cannot
  # disturb the real one, and so the two rows below can prove _sec_row_wanted.
  _t87_wtl=$(mktemp "${TMPDIR:-/tmp}/t87-ledger.XXXXXX")
  _t87_wt=$(AGENT_GUARD_COST_LEDGER="$_t87_wtl" bash tests/run-tests.sh -T T87 --worktree 2>&1); _t87_rc=$?
  report "T87 -T T87 --worktree exits 0 (uncommitted-code carry)" 0 "$_t87_rc"
  grep -Fq 'T87 executes inside the worktree snapshot' <<< "$_t87_wt"
  report "T87 snapshot output contains the in-worktree self-report" 0 "$?"
  grep -Fq '1 passed, 0 failed' <<< "$_t87_wt"
  report "T87 snapshot run summary matches the single self-report" 0 "$?"
  report "T87 the snapshot run wrote its aggregate run row" 1 \
    "$(awk -F'\t' '$2 ~ /^run/ {c++} END {print c+0}' "$_t87_wtl")"
  report "T87 TC-2350 a stubbed snapshot section leaves no sec row for the planner" 0 \
    "$(awk -F'\t' '$2 == "sec" && $3 == "T87" {c++} END {print c+0}' "$_t87_wtl")"
  rm -f "$_t87_wtl"
  # recursion + environment guards
  _t87_rg=$(AGENT_GUARD_SUITE_IN_WT=1 bash tests/run-tests.sh -T T1 --worktree 2>&1); _t87_rgrc=$?
  report "T87 --worktree recursion guard exits 2" 2 "$_t87_rgrc"
  grep -Fq 'already inside a suite worktree' <<< "$_t87_rg"
  report "T87 recursion guard names the reason" 0 "$?"
  _t87_ng=$(mktemp -d "${TMPDIR:-/tmp}/t87-ng.XXXXXX"); mkdir -p "$_t87_ng/tests"
  cp "$ROOT/tests/run-tests.sh" "$_t87_ng/tests/run-tests.sh"
  _t87_ngout=$(cd "$_t87_ng" && bash tests/run-tests.sh -T T1 --worktree 2>&1); _t87_ngrc=$?
  report "T87 --worktree outside a git repo exits 2" 2 "$_t87_ngrc"
  grep -Fq 'requires a git repository' <<< "$_t87_ngout"
  report "T87 non-git refusal names the reason" 0 "$?"
  rm -rf "$_t87_ng"
  # two concurrent worktree invocations stay isolated and both green
  _t87_c1=$(mktemp -d "${TMPDIR:-/tmp}/t87-c1.XXXXXX"); _t87_c2=$(mktemp -d "${TMPDIR:-/tmp}/t87-c2.XXXXXX")
  ( cd "$ROOT" && bash tests/run-tests.sh -T T1 --worktree >"$_t87_c1/out" 2>&1; echo $? >"$_t87_c1/rc" ) &
  ( cd "$ROOT" && bash tests/run-tests.sh -T T1 --worktree >"$_t87_c2/out" 2>&1; echo $? >"$_t87_c2/rc" ) &
  wait
  report "T87 two concurrent worktree runs both exit 0" 0 "$([[ "$(cat "$_t87_c1/rc")" == "0" && "$(cat "$_t87_c2/rc")" == "0" ]] && echo 0 || echo 1)"
  rm -rf "$_t87_c1" "$_t87_c2"
  # idempotent second snapshot run at the same tree
  _t87_w2rc=0
  bash tests/run-tests.sh -T T87 --worktree >/dev/null 2>&1 || _t87_w2rc=$?
  report "T87 second --worktree run is idempotent (exit 0)" 0 "$_t87_w2rc"
  # cleanup hygiene: the nested run's OWN snapshot worktree must be removed and
  # deregistered. v3.96.0 (CHG-133): a global `grep -c wt-shard` registry count is
  # not concurrency-safe — an evidence round runs 5 snapshot shards in parallel
  # with this live shard, so sibling registrations are legitimate at this instant.
  # Scope the check to the path the nested run printed.
  _t87_wtpath=$(sed -n 's/^worktree: snapshot .* at \(.*\)$/\1/p' <<< "$_t87_wt" | tail -1)
  report "T87 nested --worktree run removes its own snapshot dir" 0 \
    "$([[ -n "$_t87_wtpath" && ! -e "$_t87_wtpath" ]] && echo 0 || echo 1)"
  report "T87 nested snapshot is deregistered from the worktree list" 0 \
    "$(if [[ -n "$_t87_wtpath" ]]; then git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -cF "$_t87_wtpath"; else echo 1; fi)"
  # snapshot creation is lock-serialized + retried; a dirty tree with a failing
  # stash refuses BY NAME (first 6-way round: 5/6 concurrent stash creates
  # silently lost and fell back to HEAD, testing stale code)
  grep -Fq 'wt-snapshot.lock' "$ROOT/tests/run-tests.sh"
  report "T87 snapshot creation is lock-serialized" 0 "$?"
  grep -Fq 'refusing to snapshot a stale HEAD' "$ROOT/tests/run-tests.sh"
  report "T87 dirty-tree stash failure refuses by name (no silent HEAD fallback)" 0 "$?"
  grep -Fq -- '--untracked-files=no' "$ROOT/tests/run-tests.sh"
  report "T87 dirty check targets tracked changes only" 0 "$?"
  # REQ-1322: shard-sum sums per-shard summaries; zero success is failure.
  report "T87 shard-sum.sh is executable" 0 "$([[ -x "$ROOT/scripts/shard-sum.sh" ]] && echo 0 || echo 1)"
  _t87_ss=$(mktemp -d "${TMPDIR:-/tmp}/t87-ss.XXXXXX")
  printf '2 passed, 0 failed\n' > "$_t87_ss/a.log"
  printf '3 passed, 0 failed\n' > "$_t87_ss/b.log"
  _t87_sum=$(bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_ss" 2>&1); _t87_sumrc=$?
  report "T87 shard-sum green sum exits 0" 0 "$_t87_sumrc"
  grep -Fq 'total: 5 passed, 0 failed' <<< "$_t87_sum"
  report "T87 shard-sum totals the shards" 0 "$?"
  printf '9 passed, 1 failed\n' > "$_t87_ss/a.log"
  bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_ss" >/dev/null 2>&1
  report "T87 shard-sum red sum exits 1" 1 "$?"
  printf 'noise only\n' > "$_t87_ss/a.log"; rm -f "$_t87_ss/b.log"
  bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_ss" >/dev/null 2>&1
  report "T87 shard-sum with no shard summary exits 2" 2 "$?"
  rm -f "$_t87_ss"/*.log
  bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_ss" >/dev/null 2>&1
  report "T87 shard-sum with zero logs exits 2" 2 "$?"
  _t87_wr=$(mktemp -d "${TMPDIR:-/tmp}/t87-wr.XXXXXX"); mkdir -p "$_t87_wr/tests" "$_t87_wr/scripts"
  printf '#!/usr/bin/env bash\necho "stub-gen $*" >> stub-gen.log\n' > "$_t87_wr/scripts/update-assertion-count.sh"
  chmod +x "$_t87_wr/scripts/update-assertion-count.sh"
  printf '2 passed, 0 failed\n' > "$_t87_ss/a.log"; printf '3 passed, 0 failed\n' > "$_t87_ss/b.log"
  bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_ss" --write --root "$_t87_wr" >/dev/null 2>&1
  report "T87 shard-sum --write exits 0 with a stub generator" 0 "$?"
  report "T87 --write lands the sum in tests/.suite-baseline" 0 "$([[ "$(cat "$_t87_wr/tests/.suite-baseline" 2>/dev/null)" == "5" ]] && echo 0 || echo 1)"
  report "T87 --write invokes the generator with --from-baseline" 0 "$([[ "$(cat "$_t87_wr/stub-gen.log" 2>/dev/null)" == "stub-gen --from-baseline" ]] && echo 0 || echo 1)"
  rm -rf "$_t87_ss" "$_t87_wr"
  # REQ-1324: opt-in cache — default off; hit path; chain exclusion; seam bypass.
  _t87_cache="$ROOT/.agent-state/section-cache.tsv"
  rm -f "$_t87_cache"
  _t87_off=$(bash tests/run-tests.sh -T T1 2>&1)
  report "T87 cache stays off by default (no [cached] marker)" 0 "$(printf '%s\n' "$_t87_off" | grep -cF '[cached]')"
  _t87_c1out=$(AGENT_GUARD_SECTION_CACHE=1 bash tests/run-tests.sh -T T1 2>&1); _t87_c1rc=$?
  report "T87 first cache-populated run exits 0" 0 "$_t87_c1rc"
  report "T87 first run prints no [cached] marker" 0 "$(printf '%s\n' "$_t87_c1out" | grep -cF '[cached]')"
  report "T87 cache row lands in section-cache.tsv" 0 "$([[ -f "$_t87_cache" && "$(wc -l < "$_t87_cache" | tr -d ' ')" -ge 1 ]] && echo 0 || echo 1)"
  _t87_c2out=$(AGENT_GUARD_SECTION_CACHE=1 bash tests/run-tests.sh -T T1 2>&1); _t87_c2rc=$?
  report "T87 second cache run exits 0 (hit)" 0 "$_t87_c2rc"
  grep -Fq '[cached] T1 (2 passed, 0 failed)' <<< "$_t87_c2out"
  report "T87 hit prints the [cached] marker with counts" 0 "$?"
  grep -Fq 'section-cache: 1 hit(s)' <<< "$_t87_c2out"
  report "T87 hit prints the cache tally" 0 "$?"
  grep -Fq '2 passed, 0 failed' <<< "$_t87_c2out"
  report "T87 cached run keeps the summary truthful" 0 "$?"
  AGENT_GUARD_SECTION_CACHE=1 bash tests/run-tests.sh -T T5 >/dev/null 2>&1; _t87_chrc=$?
  report "T87 SERIAL_CHAIN head T5 exits 0 under cache" 0 "$_t87_chrc"
  _t87_t5rows=0
  [[ -f "$_t87_cache" ]] && _t87_t5rows=$(grep -cF 'T5' "$_t87_cache" || true)
  report "T87 SERIAL_CHAIN member is never stored" 0 "$_t87_t5rows"
  _t87_fr=$(AGENT_GUARD_SECTION_CACHE=1 AGENT_GUARD_SUITE_FORCE_RED=1 bash tests/run-tests.sh -T T1 2>&1); _t87_frrc=$?
  report "T87 FORCE_RED run exits 1 (T0 seam fires)" 1 "$_t87_frrc"
  report "T87 FORCE_RED bypasses the cache (no [cached] marker)" 0 "$(printf '%s\n' "$_t87_fr" | grep -cF '[cached]')"
  # -T auto registry: shard-sum.sh maps to its own section.
  _t87_am=$(AGENT_GUARD_SUITE_AUTO_DIFF=scripts/shard-sum.sh AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash tests/run-tests.sh -T auto 2>&1); _t87_amrc=$?
  report "T87 auto-resolve for shard-sum.sh exits 0" 0 "$_t87_amrc"
  grep -Fq 'auto-resolve-only: T50 T87' <<< "$_t87_am"
  report "T87 auto-resolve maps shard-sum.sh to T87 (tail pin keeps T50)" 0 "$?"
  # REQ-1331 (CHG-133): no `printf ... | grep -q` predicate may survive. Under
  # pipefail the early-exiting grep can hand printf a SIGPIPE and turn a HIT into
  # a failure (3 of the 6-way round's reds had this shape). The pattern is built
  # from pieces so the pin cannot match itself.
  # Multi-stage pipelines count too: any `printf … | … | grep -q` has the same
  # early-exit SIGPIPE exposure at the final stage (CHG-133 复核轮发现 A56 一处
  # 三段落管道躲过了单段钉).
  _t87_pat='printf[^|]*(\|[^|]*)*\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q'
  _t87_pipe=$(
    { grep -nE "$_t87_pat" "$ROOT/resources/templates/"*.sh "$ROOT/scripts/agent-gate" \
        "$ROOT/scripts/eval-cases" "$ROOT/scripts/"*.sh "$ROOT/tests/"*.sh \
        "$ROOT/tests/lib/"*.sh "$ROOT/tests/suites/"*.sh 2>/dev/null || true; } \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -c . || true
  )
  report "T87 no piped printf/grep -q predicate remains in the governance face" 0 "$_t87_pipe"
  # REQ-1332 (CHG-133): the N=6 plan is a partition, keeps the chain groups
  # whole, and N!=6 still falls back to the contiguous split.
  _t87_plan=$(for _i in 1 2 3 4 5 6; do
      AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY=1 bash tests/run-tests.sh --shard "$_i/6" 2>/dev/null \
        | sed -n 's/^shard-resolve-only: //p'
    done)
  report "T87 cost plan covers every section exactly once" \
    "$(printf '%s\n' "${SECTIONS[@]}" | sort | tr '\n' ' ')" \
    "$(printf '%s\n' "$_t87_plan" | tr ' ' '\n' | grep . | sort | tr '\n' ' ')"
  report "T87 cost plan keeps T5/T22a/T16 in one shard" 1 \
    "$(printf '%s\n' "$_t87_plan" | grep -cE '(^| )T5 T22a T16( |$)')"
  report "T87 cost plan keeps T50/T51 in one shard" 1 \
    "$(printf '%s\n' "$_t87_plan" | grep -cE '(^| )T50 T51( |$)')"
  report "T87 N!=6 keeps the contiguous fallback (5 shards cover all sections)" "${#SECTIONS[@]}" \
    "$(for _i in 1 2 3 4 5; do
        AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY=1 bash tests/run-tests.sh --shard "$_i/5" 2>/dev/null \
          | sed -n 's/^shard-resolve-only: //p'
      done | tr ' ' '\n' | grep -c .)"
  # An empty plan group must be a named refusal, not an unbound-variable crash
  # under `set -u` (recheck round: ${WANTED[0]} died rc1 with no message, so a
  # typo'd plan looked like an unrelated suite failure).
  _t87_dp=$(mktemp -d "$ROOT/.agent-state/t87-drift.XXXXXX")
  awk '{ if (!done && $0=="SHARD_PLAN_6=(") { print "SHARD_PLAN_6=( \"\""; done=1 } else print }' \
    "$ROOT/tests/run-tests.sh" > "$_t87_dp/run-tests.sh"
  _t87_dout=$(AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY=1 bash "$_t87_dp/run-tests.sh" --shard 1/6 2>&1); _t87_drc=$?
  report "T87 an empty plan group is refused with rc2" 2 "$_t87_drc"
  report "T87 the empty-group refusal names the shard" 1 \
    "$(printf '%s\n' "$_t87_dout" | grep -c 'shard 1/6 is empty in SHARD_PLAN_6')"
  rm -rf "$_t87_dp"
  # REQ-1332: an all-snapshot round is not the full-suite truth (1658 vs 1694).
  _t87_sd=$(mktemp -d "${TMPDIR:-/tmp}/t87-sum.XXXXXX")
  printf 'worktree: snapshot abc at /tmp/x\n3 passed, 0 failed\n' > "$_t87_sd/1.log"
  printf 'worktree: snapshot abc at /tmp/y\n2 passed, 0 failed\n' > "$_t87_sd/2.log"
  _t87_sw=$(bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_sd" 2>&1); _t87_swrc=$?
  report "T87 shard-sum sums snapshot logs" 0 "$_t87_swrc"
  report "T87 shard-sum warns when every log is a snapshot" 1 \
    "$(printf '%s\n' "$_t87_sw" | grep -c 'T87 early-exits inside a snapshot')"
  # --write is the authoritative face: a short all-snapshot total must never land
  # in .suite-baseline. rc alone is not enough (a missing generator also exits 2),
  # so the refusal is identified by its own sentence.
  _t87_ww=$(bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_sd" --write --root "$_t87_sd" 2>&1)
  report "T87 shard-sum refuses --write on an all-snapshot round" 1 \
    "$(printf '%s\n' "$_t87_ww" | grep -c 'refusing --write on an all-snapshot round')"
  # --write is the authoritative face: a short all-snapshot total must never land
  # in .suite-baseline, so the warning escalates to a refusal when writing.
  printf 'shard 2/2: 1 sections (T2 .. T2)\n2 passed, 0 failed\n' > "$_t87_sd/2.log"
  _t87_sw=$(bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_sd" 2>&1)
  report "T87 shard-sum stays quiet with one live shard" 0 \
    "$(printf '%s\n' "$_t87_sw" | grep -c 'T87 early-exits inside a snapshot')"
  # The banner is not always there (a snapshot can die before printing it) and a
  # live shard can echo a nested banner. When evidence-round's .mode file is
  # present it wins; the banner stays as the fallback for ad-hoc log dirs.
  _t87_md=$(mktemp -d "${TMPDIR:-/tmp}/t87-mode.XXXXXX")
  printf '1 passed, 0 failed\n' > "$_t87_md/1.log"; printf 'worktree\n' > "$_t87_md/1.mode"
  _t87_mw=$(bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_md" 2>&1)
  report "T87 shard-sum trusts shard-*.mode over a missing banner" 1 \
    "$(printf '%s\n' "$_t87_mw" | grep -c 'T87 early-exits inside a snapshot')"
  printf 'worktree: snapshot zzz at /tmp/z\n1 passed, 0 failed\n' > "$_t87_md/2.log"
  printf 'live\n' > "$_t87_md/2.mode"
  _t87_mw=$(bash "$ROOT/scripts/shard-sum.sh" --logs "$_t87_md" 2>&1)
  report "T87 shard-sum trusts shard-*.mode over a live shard's banner" 0 \
    "$(printf '%s\n' "$_t87_mw" | grep -c 'T87 early-exits inside a snapshot')"
  rm -rf "$_t87_md"
  rm -rf "$_t87_sd"
  # REQ-1330 (CHG-133): evidence rounds are append-only directories driven by a
  # stub suite; the real runner would cost a full sharded round.
  _t87_er=$(mktemp -d "${TMPDIR:-/tmp}/t87-er.XXXXXX")
  cat > "$_t87_er/stub.sh" <<'EOS'
#!/usr/bin/env bash
case " $* " in *" --worktree "*) echo "worktree: snapshot stub at /tmp/stub" ;; esac
if [[ "${STUB_RED:-0}" == "1" ]]; then echo "FAIL T0 stub"; echo "1 passed, 1 failed"; exit 1; fi
echo "2 passed, 0 failed"
EOS
  _t87_dry=$(bash scripts/evidence-round.sh --chg CHG-133 --round 1 --shards 2 --live-shard 2 \
    --dry-run --state-dir "$_t87_er/state" 2>&1)
  report "T87 evidence-round dry-run prints the shard plan" 2 \
    "$(printf '%s\n' "$_t87_dry" | grep -cE '^  shard [12]/2 ')"
  report "T87 evidence-round dry-run marks the live shard" 1 \
    "$(printf '%s\n' "$_t87_dry" | grep -c 'shard 2/2 live')"
  report "T87 evidence-round dry-run creates nothing" 0 \
    "$([[ -d "$_t87_er/state" ]] && echo 1 || echo 0)"
  # v3.97.1 (CHG-135): this fixture runs from $ROOT, so without the override the
  # round lock of an outer live round would (correctly) refuse it. The override is
  # a self-test seam only.
  AGENT_GUARD_EVIDENCE_LOCK_DIR="$_t87_er/lock" \
    AGENT_GUARD_EVIDENCE_SUITE="$_t87_er/stub.sh" bash scripts/evidence-round.sh \
    --chg CHG-133 --round 1 --shards 2 --live-shard 2 --state-dir "$_t87_er/state" \
    >"$_t87_er/run1.txt" 2>&1; _t87_errc=$?
  report "T87 evidence-round green stub exits 0" 0 "$_t87_errc"
  report "T87 evidence-round keeps logs, rc and mode per shard" 6 \
    "$(ls "$_t87_er/state/CHG-133/round-1" | grep -cE '^shard-[12]\.(log|rc|mode)$')"
  report "T87 evidence-round live shard runs without --worktree" 0 \
    "$(grep -c 'worktree: snapshot' "$_t87_er/state/CHG-133/round-1/shard-2.log")"
  report "T87 evidence-round snapshot shard carries the banner" 1 \
    "$(grep -c 'worktree: snapshot' "$_t87_er/state/CHG-133/round-1/shard-1.log")"
  report "T87 evidence-round appends one ledger row with the tree fingerprint" 1 \
    "$(awk -F'\t' '$2=="CHG-133" && $3=="1" && $5!="" && $6=="2" && $7=="2" {n++} END{print n+0}' "$_t87_er/state/ledger.tsv")"
  AGENT_GUARD_EVIDENCE_LOCK_DIR="$_t87_er/lock" \
    AGENT_GUARD_EVIDENCE_SUITE="$_t87_er/stub.sh" bash scripts/evidence-round.sh \
    --chg CHG-133 --round 1 --shards 2 --live-shard 2 --state-dir "$_t87_er/state" \
    >/dev/null 2>&1; _t87_errc2=$?
  report "T87 evidence-round refuses to overwrite an existing round" 2 "$_t87_errc2"
  STUB_RED=1 AGENT_GUARD_EVIDENCE_LOCK_DIR="$_t87_er/lock" \
    AGENT_GUARD_EVIDENCE_SUITE="$_t87_er/stub.sh" bash scripts/evidence-round.sh \
    --chg CHG-133 --round 2 --shards 2 --live-shard 2 --state-dir "$_t87_er/state" \
    >/dev/null 2>&1; _t87_errc3=$?
  report "T87 evidence-round red stub exits 1" 1 "$_t87_errc3"
  report "T87 evidence-round keeps the failing shard log" 1 \
    "$(grep -c 'FAIL T0 stub' "$_t87_er/state/CHG-133/round-2/shard-1.log")"
  report "T87 evidence-round keeps the failing shard rc" 1 \
    "$(cat "$_t87_er/state/CHG-133/round-2/shard-1.rc")"
  _t87_next=$(bash scripts/evidence-round.sh --chg CHG-133 --shards 2 --live-shard 2 \
    --dry-run --state-dir "$_t87_er/state" 2>&1)
  report "T87 evidence-round auto-selects the next free round" 1 \
    "$(printf '%s\n' "$_t87_next" | grep -c 'round 3 ->')"
  # A stub round must be identifiable after the fact: meta records the suite path
  # and each shard's rc, so "which suite produced this" is answerable from disk.
  report "T87 evidence-round meta records the suite path and per-shard rc" 1 \
    "$(awk -F'\t' '$1=="suite" && $2 ~ /stub\.sh$/ {s=1} $1=="shard_1_rc" {r1=$2} $1=="shard_2_rc" {r2=$2} END{print (s==1 && r1!="-" && r2!="-") ? 1 : 0}' \
        "$_t87_er/state/CHG-133/round-1/meta.tsv")"
  rm -rf "$_t87_er"
  # REQ-1334 (CHG-133): the receipt defaults the audit to parallel; explicit 0 wins.
  report "T87 fresh-clone defaults the audit to parallel" 1 \
    "$(grep -cF 'AGENT_GUARD_AUDIT_PARALLEL="${AGENT_GUARD_AUDIT_PARALLEL:-1}"' "$ROOT/tests/fresh-clone-check.sh")"
  # ── v3.97.0 (CHG-134, REQ-1340): static preflight (TC-2340) ───────────────
  # The fixture is a miniature source layout where every registry is ONE line:
  # "forgot to register" is exactly "delete that line", so each case below is a
  # named regression for a class that cost CHG-133 520 s of round time.
  _t87_pcd=$(mktemp -d "${TMPDIR:-/tmp}/t87-pc.XXXXXX")
  _t87_pc_make() {
    rm -rf "$_t87_pcd/tree"
    mkdir -p "$_t87_pcd/tree/scripts" "$_t87_pcd/tree/tests" "$_t87_pcd/tree/resources/templates"
    # Manifest shape mirrors scripts/bootstrap.sh: <logical-key> <dest> <src>.
    cat > "$_t87_pcd/tree/scripts/bootstrap.sh" <<'EOB'
install_file foo "$SCRIPTS_DIR/foo.sh" "scripts/foo.sh"
install_file bar "$TESTS_DIR/bar.sh" "tests/bar.sh"
install_file tpl "$SCRIPTS_DIR/tpl.sh" "resources/templates/tpl.sh"
install_file gate "$SCRIPTS_DIR/agent-gate" "resources/templates/agent-gate.sh"
EOB
    printf '#!/usr/bin/env bash\ntrue\n' > "$_t87_pcd/tree/scripts/foo.sh"
    printf '#!/usr/bin/env bash\ntrue\n' > "$_t87_pcd/tree/tests/bar.sh"
    printf '#!/usr/bin/env bash\ntrue\n' > "$_t87_pcd/tree/resources/templates/tpl.sh"
    cat > "$_t87_pcd/tree/resources/templates/agent-gate.sh" <<'EOG'
is_code_path() {
  case "$1" in
    ${scripts_re}/foo\.sh) return 0 ;;
    ${scripts_re}/tpl\.sh) return 0 ;;
    ${tests_re}/bar\.sh) return 0 ;;
  esac
  return 1
}
EOG
    # The fixture suite is emitted with printf, not a heredoc: a literal
    # `SECTIONS=(...)` line at column 0 in THIS file would be picked up by every
    # sed-based reader (precheck R5, shard-plan) as the real registry.
    {
      printf '#!/usr/bin/env bash\n'
      printf 'SECTIONS=(T1 T2 T3 T4 T6 T7 T8 T9 T50 T51 T5 T22a T16)\n'
      printf 'SERIAL_CHAIN=(T50 T51 T5 T22a T16)\n'
      printf 'SHARD_PLAN_6=(\n'
      printf '  # SHARD_PLAN_6_BEGIN\n'
      printf '  "T5 T22a T16"\n'
      printf '  "T1 T6"\n'
      printf '  "T2 T7"\n'
      printf '  "T3 T8"\n'
      printf '  "T4 T9"\n'
      printf '  "T50 T51"\n'
      printf '  # SHARD_PLAN_6_END\n'
      printf ')\n'
      printf '_fake_src() { cp "$ROOT/scripts/foo.sh" "$FAKE_SRC/scripts/foo.sh"; }\n'
      printf '_fake_src_bar() { cp "$ROOT/tests/bar.sh" "$FAKE_SRC/tests/bar.sh"; }\n'
    } > "$_t87_pcd/tree/tests/run-tests.sh"
    cat >> "$_t87_pcd/tree/tests/run-tests.sh" <<'EOS'
_i=${2%%/*}
_mem=${SHARD_PLAN_6[$((_i-1))]}
printf 'shard %s: %s\n' "$2" "$_mem"
printf 'shard-resolve-only: %s\n' "$_mem"
EOS
    cp "$ROOT/scripts/shard-plan.sh" "$_t87_pcd/tree/scripts/shard-plan.sh"
  }
  _t87_pc_mut() { rm -rf "$_t87_pcd/$1"; cp -R "$_t87_pcd/tree" "$_t87_pcd/$1"; }
  _t87_pc_make
  _t87_o=$(bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/tree" 2>&1); _t87_rc=$?
  report "T87 TC-2340 precheck clean fixture exits 0" 0 "$_t87_rc"
  report "T87 precheck clean fixture reports R1..R5 ok" 5 \
    "$(printf '%s\n' "$_t87_o" | grep -cE '^ok R[1-5] ')"
  report "T87 precheck clean fixture reports no failure" 0 \
    "$(printf '%s\n' "$_t87_o" | grep -cE '^(fail|warn) ')"
  # R1: a manifest source that is not on disk (the file was renamed/never shipped)
  _t87_pc_mut r1; rm -f "$_t87_pcd/r1/resources/templates/tpl.sh"
  _t87_o=$(bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/r1" 2>&1)
  report "T87 precheck R1 misses a vanished source by name" 1 \
    "$(printf '%s\n' "$_t87_o" | grep -cE '^fail R1 .*resources/templates/tpl\.sh')"
  # R2: the install fixture (T21 FAKE_SRC) stopped copying the new script
  _t87_pc_mut r2
  grep -vF 'cp "$ROOT/scripts/foo.sh"' "$_t87_pcd/r2/tests/run-tests.sh" > "$_t87_pcd/r2/t.tmp" \
    && mv "$_t87_pcd/r2/t.tmp" "$_t87_pcd/r2/tests/run-tests.sh"
  _t87_o=$(bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/r2" 2>&1)
  report "T87 precheck R2 misses an uncopied fixture script by name" 1 \
    "$(printf '%s\n' "$_t87_o" | grep -cE '^fail R2 .*scripts/foo\.sh')"
  # R3: the gate whitelist does not know the new code file (E125 on first commit)
  _t87_pc_mut r3
  grep -vF 'scripts_re}/foo' "$_t87_pcd/r3/resources/templates/agent-gate.sh" > "$_t87_pcd/r3/t.tmp" \
    && mv "$_t87_pcd/r3/t.tmp" "$_t87_pcd/r3/resources/templates/agent-gate.sh"
  _t87_o=$(bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/r3" 2>&1)
  report "T87 precheck R3 misses a whitelist entry by name" 1 \
    "$(printf '%s\n' "$_t87_o" | grep -cE '^fail R3 .*scripts/foo\.sh')"
  # R4: a template shell script that is installed nowhere
  _t87_pc_mut r4
  grep -vF '"resources/templates/tpl.sh"' "$_t87_pcd/r4/scripts/bootstrap.sh" > "$_t87_pcd/r4/t.tmp" \
    && mv "$_t87_pcd/r4/t.tmp" "$_t87_pcd/r4/scripts/bootstrap.sh"
  _t87_o=$(bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/r4" 2>&1)
  report "T87 precheck R4 misses an uninstalled template by name" 1 \
    "$(printf '%s\n' "$_t87_o" | grep -cE '^fail R4 .*resources/templates/tpl\.sh')"
  # R6 is an observation: LPT packs 10 atoms of ~50 s onto 6 shards as 100 s
  # max against an 85 s floor, past the 1.15x tolerance. A fixture with fewer
  # atoms cannot warn: the heaviest atom then *is* the floor, so max <= floor.
  _t87_pc_mut r6
  cp "$ROOT/scripts/shard-plan.sh" "$_t87_pcd/r6/scripts/shard-plan.sh"
  mkdir -p "$_t87_pcd/r6/.agent-state"
  { printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n'
    for _id in T1 T2 T3 T4 T6 T7 T8 T9; do
      printf '2026-10-29T00:00:00Z\tsec\t%s\tsuite\t50\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n' "$_id"
    done
    printf '2026-10-29T00:00:00Z\tsec\tT50\tsuite\t25\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    printf '2026-10-29T00:00:00Z\tsec\tT51\tsuite\t25\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    for _id in T5 T22a T16; do
      printf '2026-10-29T00:00:00Z\tsec\t%s\tsuite\t20\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n' "$_id"
    done
  } > "$_t87_pcd/r6/.agent-state/cost-ledger.tsv"
  # R6 compares the table with the planner's pinned model, so the fixture needs
  # that pin: --write derives both from the ledger above.
  bash "$_t87_pcd/r6/scripts/shard-plan.sh" --root "$_t87_pcd/r6" --write >/dev/null 2>&1
  report "T87 precheck fixture pinned its own plan for R6" 0 "$?"
  _t87_o=$(bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/r6" 2>&1); _t87_rc=$?
  report "T87 precheck treats cost imbalance as a WARN, not a failure" 0 "$_t87_rc"
  report "T87 precheck names the predicted load gap" 1 \
    "$(printf '%s\n' "$_t87_o" | grep -c '^warn R6 ')"
  bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/r6" --strict >/dev/null 2>&1
  report "T87 precheck --strict escalates the WARN to rc1" 1 "$?"
  bash "$ROOT/scripts/pre-round-check.sh" --root "$_t87_pcd/tree" --strict >/dev/null 2>&1
  report "T87 precheck --strict leaves a clean fixture at rc0" 0 "$?"
  bash "$ROOT/scripts/pre-round-check.sh" --wat >/dev/null 2>&1
  report "T87 precheck rejects an unknown option with rc2" 2 "$?"
  # Integration: a red preflight refuses to start a round and creates nothing.
  _t87_pc_mut g
  _t87_pcg="$_t87_pcd/g"
  cp "$ROOT/scripts/pre-round-check.sh" "$ROOT/scripts/evidence-round.sh" \
     "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$ROOT/scripts/shard-sum.sh" "$_t87_pcg/scripts/"
  printf '#!/usr/bin/env bash\necho "2 passed, 0 failed"\n' > "$_t87_pcg/tests/green-stub.sh"
  ( cd "$_t87_pcg" && git init -q && git add -A \
      && git -c user.name=t -c user.email=t@example.com commit -qm base ) >/dev/null 2>&1
  rm -f "$_t87_pcg/resources/templates/tpl.sh"
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --chg CHG-FX --round 1 --shards 2 --live-shard 2 \
      --state-dir "$_t87_pcd/st" ) > "$_t87_pcd/out" 2>&1; _t87_rc=$?
  report "T87 evidence-round refuses to start on a red preflight" 2 "$_t87_rc"
  report "T87 the refusal names the preflight" 1 "$(grep -c 'pre-round-check failed' "$_t87_pcd/out")"
  report "T87 a refused round leaves no round directory" 0 \
    "$([[ -d "$_t87_pcd/st/CHG-FX/round-1" ]] && echo 1 || echo 0)"
  ( cd "$_t87_pcg" && git checkout -- resources/templates/tpl.sh ) >/dev/null 2>&1
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --chg CHG-FX --round 1 --shards 2 --live-shard 2 \
      --skip-precheck --state-dir "$_t87_pcd/st" ) >/dev/null 2>&1; _t87_rc=$?
  report "T87 --skip-precheck starts the round anyway" 0 "$_t87_rc"
  report "T87 --skip-precheck round keeps its artifacts" 0 \
    "$([[ -f "$_t87_pcd/st/CHG-FX/round-1/meta.tsv" ]] && echo 0 || echo 1)"
  # ── REQ-1342: code-face fingerprint + explicit carry (TC-2342) ────────────
  report "T87 TC-2342 a plain round records the code-face fingerprint" 1 \
    "$(awk -F'\t' '$1=="code_face_sha" && $2!="-" && $2!=""{n++} END{print n+0}' "$_t87_pcd/st/CHG-FX/round-1/meta.tsv")"
  report "T87 a plain round is never carried" 1 \
    "$(awk -F'\t' '$1=="carried_from" && $2=="-"{n++} END{print n+0}' "$_t87_pcd/st/CHG-FX/round-1/meta.tsv")"
  # A tracked file inside the claim face (docs/changes) moves the tree but not
  # the code face — the "green round, docs-only edit" case that cost 342 s.
  mkdir -p "$_t87_pcg/docs/changes/CHG-FX"
  printf 'v1\n' > "$_t87_pcg/docs/changes/CHG-FX/00-intent.md"
  ( cd "$_t87_pcg" && git add -A ) >/dev/null 2>&1
  # Read-only means read-only: the candidate lookup must not migrate the ledger
  # (a schema migration on this path rewrote the file during a "check").
  _t87_ledger_before=$(cksum "$_t87_pcd/st/ledger.tsv")
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --carry-check --state-dir "$_t87_pcd/st" ) \
    > "$_t87_pcd/out" 2>&1; _t87_rc=$?
  report "T87 --carry-check finds the green round after a docs-only edit" 0 "$_t87_rc"
  report "T87 --carry-check names the candidate round" 1 \
    "$(grep -c '^carryable: round 1 ' "$_t87_pcd/out")"
  report "T87 --carry-check leaves the ledger byte-identical" 1 \
    "$([[ "$(cksum "$_t87_pcd/st/ledger.tsv")" == "$_t87_ledger_before" ]] && echo 1 || echo 0)"
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --carry --chg CHG-FX --state-dir "$_t87_pcd/st" ) \
    >/dev/null 2>&1; _t87_rc=$?
  report "T87 --carry creates the inherited round" 0 "$_t87_rc"
  report "T87 the carried round records carried_from=1" 1 \
    "$(awk -F'\t' '$1=="carried_from" && $2=="1"{n++} END{print n+0}' "$_t87_pcd/st/CHG-FX/round-2/meta.tsv")"
  report "T87 the carried round keeps the source total" 4 \
    "$(awk -F'\t' '$1=="total_passed"{print $2}' "$_t87_pcd/st/CHG-FX/round-2/meta.tsv")"
  report "T87 the carried round costs zero wall time" 1 \
    "$(awk -F'\t' '$1=="wall_s" && $2=="0"{n++} END{print n+0}' "$_t87_pcd/st/CHG-FX/round-2/meta.tsv")"
  report "T87 the carried round copies the shard logs instead of running them" 0 \
    "$(diff -q "$_t87_pcd/st/CHG-FX/round-1/shard-1.log" "$_t87_pcd/st/CHG-FX/round-2/shard-1.log" >/dev/null 2>&1 && echo 0 || echo 1)"
  # Carry copies a *result*: a green row from another suite, one with failures, or
  # one shorter than the pinned baseline is not a result of this suite at all.
  _t87_meta_edit() { # <meta> <key> <value>
    awk -F'\t' -v OFS='\t' -v k="$2" -v v="$3" '$1==k{$2=v} {print}' "$1" > "$1.tmp" \
      && mv "$1.tmp" "$1"
  }
  cp "$_t87_pcd/st/CHG-FX/round-1/meta.tsv" "$_t87_pcd/m1.bak"
  _t87_meta_edit "$_t87_pcd/st/CHG-FX/round-1/meta.tsv" suite /tmp/other-suite.sh
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --carry --chg CHG-FX --state-dir "$_t87_pcd/st" ) \
    > "$_t87_pcd/out" 2>&1; _t87_rc=$?
  report "T87 --carry refuses a round that another suite produced" 2 "$_t87_rc"
  report "T87 the suite-mismatch refusal names both suites" 1 \
    "$(grep -c 'ran /tmp/other-suite.sh, not' "$_t87_pcd/out")"
  cp "$_t87_pcd/m1.bak" "$_t87_pcd/st/CHG-FX/round-1/meta.tsv"
  _t87_meta_edit "$_t87_pcd/st/CHG-FX/round-1/meta.tsv" total_failed 1
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --carry --chg CHG-FX --state-dir "$_t87_pcd/st" ) \
    > "$_t87_pcd/out" 2>&1; _t87_rc=$?
  report "T87 --carry refuses a source round with failures" 2 "$_t87_rc"
  report "T87 the failure-count refusal quotes the count" 1 \
    "$(grep -c "has total_failed='1'" "$_t87_pcd/out")"
  cp "$_t87_pcd/m1.bak" "$_t87_pcd/st/CHG-FX/round-1/meta.tsv"
  printf '100\n' > "$_t87_pcg/tests/.suite-baseline"
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --carry --chg CHG-FX --state-dir "$_t87_pcd/st" ) \
    > "$_t87_pcd/out" 2>&1; _t87_rc=$?
  report "T87 --carry refuses a total below the pinned baseline" 2 "$_t87_rc"
  report "T87 the baseline refusal names the baseline gap" 1 \
    "$(grep -c 'below tests/.suite-baseline (100)' "$_t87_pcd/out")"
  rm -f "$_t87_pcg/tests/.suite-baseline"
  # "Green and same face" is not enough: with every green row at the current
  # tree, a carry would be a copy of the tree it claims to re-verify.
  cp "$_t87_pcd/st/ledger.tsv" "$_t87_pcd/ledger.bak"
  _t87_curtree=$(awk -F'\t' '$1=="tree_sha"{print $2}' "$_t87_pcd/st/CHG-FX/round-2/meta.tsv")
  awk -F'\t' -v OFS='\t' -v t="$_t87_curtree" \
    '$2=="CHG-FX" && $3=="1"{$5=t} {print}' "$_t87_pcd/st/ledger.tsv" > "$_t87_pcd/st/ledger.tmp" \
    && mv "$_t87_pcd/st/ledger.tmp" "$_t87_pcd/st/ledger.tsv"
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --carry-check --state-dir "$_t87_pcd/st" ) \
    > "$_t87_pcd/out" 2>&1; _t87_rc=$?
  report "T87 --carry-check refuses a round of the current tree" 1 "$_t87_rc"
  report "T87 the same-tree refusal says a different tree is required" 1 \
    "$(grep -c 'code face and a different tree' "$_t87_pcd/out")"
  cp "$_t87_pcd/ledger.bak" "$_t87_pcd/st/ledger.tsv"
  printf '#!/usr/bin/env bash\ntrue # code touched\n' > "$_t87_pcg/scripts/foo.sh"
  ( cd "$_t87_pcg" && git add -A && bash scripts/evidence-round.sh --carry-check --state-dir "$_t87_pcd/st" ) \
    >/dev/null 2>&1
  report "T87 --carry-check refuses after a tracked code change" 1 "$?"
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/green-stub.sh" \
      bash scripts/evidence-round.sh --carry --chg CHG-FX --state-dir "$_t87_pcd/st" ) \
    >/dev/null 2>&1
  report "T87 --carry without a candidate is a named refusal (rc2)" 2 "$?"
  # A carry that copies while the tree moves must be INVALID — and its ledger
  # row must say so. A stub lib forces the two fingerprint reads apart, so the
  # rc / wall_s columns are asserted on the drift path (the green path writes
  # 0/0 either way and cannot catch a shifted column).
  _t87_cd=$(mktemp -d "${TMPDIR:-/tmp}/t87-carrydrift.XXXXXX")
  ( cd "$_t87_cd" && git init -q . && git config user.email t@t && git config user.name t \
      && mkdir -p scripts tests && echo keep > keep.txt \
      && printf '#!/bin/bash\nexit 0\n' > tests/run-tests.sh && chmod +x tests/run-tests.sh \
      && cp "$ROOT/scripts/evidence-round.sh" scripts/ \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  cat > "$_t87_cd/scripts/lib-suite-tree-fingerprint.sh" <<'EOF'
#!/bin/bash
suite_tree_fingerprint() {
  case "$*" in
    *docs/changes*) echo face-fixed; return 0 ;;
  esac
  local f n
  f="$ROOT/scripts/.tree-calls"
  n=$(cat "$f" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s\n' "$n" > "$f"
  if (( n <= 2 )); then echo treeA; else echo treeB; fi
}
EOF
  _t87_cdsrc="$_t87_cd/st/CHG-CR/round-1"
  # ROOT is physical (`git rev-parse --show-toplevel`): macOS /tmp -> /private/tmp.
  _t87_cdp=$( cd "$_t87_cd" && pwd -P )
  mkdir -p "$_t87_cdsrc"
  printf 'key\tvalue\nchg\tCHG-CR\nround\t1\ntree_sha\ttreeOLD\ntree_drift\t0\ntotal_passed\t4\ntotal_failed\t0\nshards\t2\nlive_shard\t1\nsuite\t%s\n' \
    "$_t87_cdp/tests/run-tests.sh" > "$_t87_cdsrc/meta.tsv"
  printf 'ok\n' > "$_t87_cdsrc/shard-1.log"
  printf '0\n' > "$_t87_cdsrc/shard-1.rc"
  printf 'ts\tchg\tround\thead\ttree_sha\tshards\tlive_shard\ttotal\tfailed\trc\twall_s\tdir\tcode_face_sha\tcarried_from\n' \
    > "$_t87_cd/st/ledger.tsv"
  printf 't\tCHG-CR\t1\th\ttreeOLD\t2\t1\t4\t0\t0\t0\t%s\tface-fixed\t-\n' "$_t87_cdsrc" >> "$_t87_cd/st/ledger.tsv"
  ( cd "$_t87_cd" && \
      bash scripts/evidence-round.sh --carry --chg CHG-CR --state-dir "$_t87_cd/st" ) \
    > "$_t87_cd/out" 2>&1; _t87_cdrc=$?
  report "T87 a carry whose tree moves mid-copy is INVALID (rc2)" 2 "$_t87_cdrc"
  report "T87 the invalid carry records tree_drift=1 in its meta" 1 \
    "$(awk -F'\t' '$1=="tree_drift"{print $2}' "$_t87_cd/st/CHG-CR/round-2/meta.tsv" 2>/dev/null)"
  report "T87 the invalid carry's ledger row keeps rc=2 in the rc column" 2 \
    "$(awk -F'\t' 'END{print $10}' "$_t87_cd/st/ledger.tsv")"
  report "T87 the invalid carry's ledger row keeps wall_s=0 in the wall column" 0 \
    "$(awk -F'\t' 'END{print $11}' "$_t87_cd/st/ledger.tsv")"
  rm -rf "$_t87_cd"
  # ── REQ-1341: --fail-fast stops the siblings (TC-2341) ────────────────────
  cat > "$_t87_pcg/tests/ff-stub.sh" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" --shard 1/"*) echo "FAIL T0 fast-red"; echo "0 passed, 1 failed"; exit 1 ;;
  *" --shard 2/"*) echo "sleeper start"; sleep "${STUB_SLEEP:-8}"; echo "5 passed, 0 failed"; exit 0 ;;
esac
echo "0 passed, 0 failed"
EOF
  _t87_t0=$(date +%s)
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/ff-stub.sh" \
      bash scripts/evidence-round.sh --chg CHG-FF --round 1 --shards 2 --live-shard 2 \
      --fail-fast --skip-precheck --state-dir "$_t87_pcd/st" ) >/dev/null 2>&1; _t87_rc=$?
  _t87_dt=$(( $(date +%s) - _t87_t0 ))
  report "T87 TC-2341 --fail-fast round exits 1 on the fast red" 1 "$_t87_rc"
  report "T87 --fail-fast does not wait out the slow sibling" 1 \
    "$([[ "$_t87_dt" -lt 6 ]] && echo 1 || echo 0)"
  report "T87 --fail-fast records the terminated sibling as 143" 143 \
    "$(cat "$_t87_pcd/st/CHG-FF/round-1/shard-2.rc" 2>/dev/null)"
  report "T87 --fail-fast meta records the switch" 1 \
    "$(awk -F'\t' '$1=="fail-fast" && $2=="1"{n++} END{print n+0}' "$_t87_pcd/st/CHG-FF/round-1/meta.tsv")"
  report "T87 --fail-fast meta names the killed shard" 1 \
    "$(awk -F'\t' '$1=="killed" && $2=="2"{n++} END{print n+0}' "$_t87_pcd/st/CHG-FF/round-1/meta.tsv")"
  report "T87 --fail-fast writes the not-summed note" 1 \
    "$(grep -c 'fail-fast: sum not computed' "$_t87_pcd/st/CHG-FF/round-1/sum.txt")"
  report "T87 --fail-fast still appends a ledger row" 1 \
    "$(awk -F'\t' '$2=="CHG-FF" && $3=="1"{n++} END{print n+0}' "$_t87_pcd/st/ledger.tsv")"
  ( cd "$_t87_pcg" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_pcg/tests/ff-stub.sh" STUB_SLEEP=4 \
      bash scripts/evidence-round.sh --chg CHG-FF --round 2 --shards 2 --live-shard 2 \
      --skip-precheck --state-dir "$_t87_pcd/st" ) >/dev/null 2>&1; _t87_rc=$?
  report "T87 without --fail-fast the round waits for every shard" 0 \
    "$([[ "$_t87_rc" -eq 1 && "$(cat "$_t87_pcd/st/CHG-FF/round-2/shard-2.rc")" == "0" ]] && echo 0 || echo 1)"
  report "T87 the default round still sums the live shard" 1 \
    "$(grep -c 'total: 5 passed, 1 failed' "$_t87_pcd/st/CHG-FF/round-2/sum.txt")"
  # ── REQ-1343: cache retention across fingerprints (TC-2343) ──────────────
  _t87_cc=$(mktemp -d "${TMPDIR:-/tmp}/t87-cc.XXXXXX")
  _t87_fp=$(bash -c 'source "$1"; suite_tree_fingerprint "$2"' _ \
      "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$ROOT")
  { printf 'AAAA\tT9\t1\t0\t100\n'
    printf 'BBBB\tT9\t1\t0\t200\n'
    printf 'CCCC\tT9\t1\t0\t300\n'
  } > "$_t87_cc/c.tsv"
  AGENT_GUARD_SECTION_CACHE=1 AGENT_GUARD_SECTION_CACHE_PATH="$_t87_cc/c.tsv" \
    bash tests/run-tests.sh -T T1 >/dev/null 2>&1
  report "T87 TC-2343 cache keeps the current fingerprint's row" 1 \
    "$(grep -c "^${_t87_fp}	" "$_t87_cc/c.tsv")"
  report "T87 cache keeps the two most recent historical fingerprints" 2 \
    "$(grep -cE '^(BBBB|CCCC)	' "$_t87_cc/c.tsv")"
  report "T87 cache prunes the oldest historical fingerprint" 0 \
    "$(grep -c '^AAAA	' "$_t87_cc/c.tsv")"
  _t87_o=$(AGENT_GUARD_SECTION_CACHE=1 AGENT_GUARD_SECTION_CACHE_PATH="$_t87_cc/c.tsv" \
    bash tests/run-tests.sh -T T1 2>&1)
  report "T87 the retained row serves an exact-fingerprint hit" 1 \
    "$(printf '%s\n' "$_t87_o" | grep -c '^\[cached\] T1 ')"
  rm -rf "$_t87_cc"
  rm -rf "$_t87_pcd"
  # REQ-1344 (CHG-134): the planner is deterministic, balances, and its marked
  # block is the committed plan (TC-2344).
  report "T87 TC-2344 shard-plan.sh is executable" 0 "$([[ -x "$ROOT/scripts/shard-plan.sh" ]] && echo 0 || echo 1)"
  _t87_spd=$(mktemp -d "${TMPDIR:-/tmp}/t87-sp.XXXXXX")
  { printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\tasserts\trc\toutcome\trepo_key\tmodel_id\tctx_window\n'
    printf '2026-10-29T00:00:00Z\tsec\tT49a\tsuite\t45\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    printf '2026-10-29T00:00:00Z\tsec\tT57\tsuite\t52\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    printf '2026-10-29T00:00:00Z\tsec\tT16\tsuite\t35.5\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    printf '2026-10-29T00:00:00Z\tsec\tT14\tsuite\t25\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    printf '2026-10-29T00:00:00Z\tsec\tT55\tsuite\t25\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    printf '2026-10-29T00:00:00Z\tsec\tT83\tsuite\t24\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
    printf '2026-10-29T00:00:00Z\tsec\tT53\tsuite\t23\t0\t0\t0\t1\t0\tpass\tr\tm\t0\n'
  } > "$_t87_spd/l.tsv"
  _t87_p1=$(bash "$ROOT/scripts/shard-plan.sh" --root "$ROOT" --ledger "$_t87_spd/l.tsv" 2>&1)
  _t87_p2=$(bash "$ROOT/scripts/shard-plan.sh" --root "$ROOT" --ledger "$_t87_spd/l.tsv" 2>&1)
  report "T87 planner is deterministic for the same ledger" 1 \
    "$([[ "$_t87_p1" == "$_t87_p2" ]] && echo 1 || echo 0)"
  report "T87 planner covers every section exactly once" \
    "$(printf '%s\n' "${SECTIONS[@]}" | sort | tr '\n' ' ')" \
    "$(printf '%s\n' "$_t87_p1" | sed -n 's/^shard [0-9]: //p' | tr ' ' '\n' | grep . | sort | tr '\n' ' ')"
  report "T87 planner keeps the T5/T22a/T16 atom in one shard" 1 \
    "$(printf '%s\n' "$_t87_p1" | grep -cE '^shard [0-9]:.*(^| )T5 T22a T16( |$)')"
  report "T87 planner keeps the T50/T51 atom in one shard" 1 \
    "$(printf '%s\n' "$_t87_p1" | grep -cE '^shard [0-9]:.*(^| )T50 T51( |$)')"
  _t87_pj=$(bash "$ROOT/scripts/shard-plan.sh" --root "$ROOT" --ledger "$_t87_spd/l.tsv" --json 2>&1)
  report "T87 planner predicts a load within 1.15x the packing floor" 1 \
    "$(sed -n 's/.*"max":\([0-9.]*\).*"floor":\([0-9.]*\).*/\1 \2/p' <<< "$_t87_pj" \
       | awk '{ if (NF==2 && $1 <= $2 * 1.15) print 1; else print 0 }')"
  # --check / --write round-trip on a copy, so the real suite is never touched.
  mkdir -p "$_t87_spd/r/tests"
  cp "$ROOT/tests/run-tests.sh" "$_t87_spd/r/tests/run-tests.sh"
  cp "$ROOT/scripts/shard-plan.sh" "$_t87_spd/r/scripts.sh"
  chmod 755 "$_t87_spd/r/tests/run-tests.sh"
  bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --ledger "$_t87_spd/l.tsv" --write >/dev/null 2>&1
  report "T87 planner --write exits 0 on a marked copy" 0 "$?"
  report "T87 planner --write keeps the suite's permission bits" 0 \
    "$([[ -x "$_t87_spd/r/tests/run-tests.sh" ]] && echo 0 || echo 1)"
  # TC-2364 (v3.98.1 CHG-138/REQ-1356 review L3): the whitelist branch itself,
  # via PATH injection — a hostile `stat` that always emits garbage must not
  # crash --write (rc0, chmod skipped fail-open), and a GNU-shaped `stat` must
  # feed chmod a numeric mode so the copy stays executable.
  mkdir -p "$_t87_spd/r/bin"
  printf '#!/bin/sh\necho "not-a-mode"\n' > "$_t87_spd/r/bin/stat"
  chmod 755 "$_t87_spd/r/bin/stat"
  PATH="$_t87_spd/r/bin:$PATH" bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --ledger "$_t87_spd/l.tsv" --write >/dev/null 2>&1
  report "T87 TC-2364 garbage-stat write survives (whitelist fail-open rc0)" 0 "$?"
  printf '#!/bin/sh\ncase "$*" in -c*) echo 755 ;; *) echo garbage ;; esac\n' > "$_t87_spd/r/bin/stat"
  PATH="$_t87_spd/r/bin:$PATH" bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --ledger "$_t87_spd/l.tsv" --write >/dev/null 2>&1
  report "T87 TC-2364 numeric-stat write keeps the copy executable" 0 \
    "$([[ -x "$_t87_spd/r/tests/run-tests.sh" ]] && echo 0 || echo 1)"
  report "T87 planner --write pins one cost per section" "${#SECTIONS[@]}" \
    "$(( $(wc -l < "$_t87_spd/r/tests/.shard-plan-costs.tsv" | tr -d ' ') - 1 ))"
  # --check reads the pin, not the ledger: the suite appends its own `sec` rows,
  # so a live-ledger check would red the plan as a side effect of running it.
  bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --check >/dev/null 2>&1
  report "T87 planner --check verifies its own written block from the pin" 0 "$?"
  report "T87 planner --write emits one member line per shard" 6 \
    "$(sed -n '/# SHARD_PLAN_6_BEGIN/,/# SHARD_PLAN_6_END/p' "$_t87_spd/r/tests/run-tests.sh" | grep -cE '^  "T')"
  # --write must be surgical: everything outside the marked block stays byte-
  # identical, or the tool could silently rewrite prose it does not own.
  _t87_outside() { awk '/^  # SHARD_PLAN_6_BEGIN$/{f=1;next} /^  # SHARD_PLAN_6_END$/{f=0;next} !f' "$1"; }
  report "T87 planner --write leaves every line outside the block alone" 0 \
    "$(diff <(_t87_outside "$ROOT/tests/run-tests.sh") <(_t87_outside "$_t87_spd/r/tests/run-tests.sh") >/dev/null 2>&1 && echo 0 || echo 1)"
  # Drift from the live ledger is a named WARN, never an rc: the pinned model is
  # the contract, so a heavier machine cannot red the gate by itself. (T49 at 17 s
  # is no longer the heaviest atom, so LPT re-plans; the table stays put.)
  mkdir -p "$_t87_spd/r/.agent-state"
  awk -F'\t' 'BEGIN{OFS="\t"} $3=="T49a"{$5=17} {print}' "$_t87_spd/l.tsv" \
    > "$_t87_spd/r/.agent-state/cost-ledger.tsv"
  _t87_drift=$(bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --check 2>&1); _t87_drc=$?
  report "T87 planner --check stays rc0 when the live ledger has drifted" 0 "$_t87_drc"
  report "T87 planner names the drift without failing" 1 \
    "$(printf '%s\n' "$_t87_drift" | grep -c 'WARN cost drift')"
  # A tampered block must be caught: --check recomputes, it does not trust.
  awk 'BEGIN{done=0} { print; if (!done && $0 ~ /^  "T/) { print "  \"T1\""; done=1 } }' \
    "$_t87_spd/r/tests/run-tests.sh" > "$_t87_spd/r/t2"
  cp "$_t87_spd/r/t2" "$_t87_spd/r/tests/run-tests.sh"
  bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --check >/dev/null 2>&1
  report "T87 planner --check rejects a tampered block (rc1)" 1 "$?"
  # An extra group inside the markers is a plan change too, even though the first
  # six lines still match — the suite would then shard one section twice.
  awk 'BEGIN{done=0} { if (!done && $0 == "  # SHARD_PLAN_6_END") { print "  \"T82\""; done=1 } print }' \
    "$ROOT/tests/run-tests.sh" > "$_t87_spd/r/tests/run-tests.sh"
  _t87_xg=$(bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --check 2>&1)
  report "T87 planner --check rejects a seventh group (rc1)" 1 "$?"
  report "T87 planner names the group-count mismatch" 1 \
    "$(printf '%s\n' "$_t87_xg" | grep -c 'the block has 7 group(s)')"
  # A malformed pin is an environment error, not a silent fall-back to the ledger.
  printf 'cost\tid\n50\tT49a\n' > "$_t87_spd/r/tests/.shard-plan-costs.tsv"
  bash "$_t87_spd/r/scripts.sh" --root "$_t87_spd/r" --check >/dev/null 2>&1
  report "T87 planner refuses a malformed pin (rc2)" 2 "$?"
  bash "$ROOT/scripts/shard-plan.sh" --shards 5 --root "$ROOT" --ledger "$_t87_spd/l.tsv" >/dev/null 2>&1
  report "T87 planner keeps the contiguous fallback for N!=6" 0 "$?"
  bash "$ROOT/scripts/shard-plan.sh" --shards 5 --check --root "$ROOT" --ledger "$_t87_spd/l.tsv" >/dev/null 2>&1
  report "T87 planner refuses --check for N!=6 (rc2)" 2 "$?"
  bash "$ROOT/scripts/shard-plan.sh" --shards 5 --json --root "$ROOT" --ledger "$_t87_spd/l.tsv" >/dev/null 2>&1
  report "T87 planner refuses --json for N!=6 (rc2)" 2 "$?"
  _t87_nl=$(mktemp -d "${TMPDIR:-/tmp}/t87-nl.XXXXXX"); mkdir -p "$_t87_nl/tests"
  cp "$ROOT/tests/run-tests.sh" "$_t87_nl/tests/run-tests.sh"
  bash "$ROOT/scripts/shard-plan.sh" --root "$_t87_nl" --write >/dev/null 2>&1
  report "T87 planner --write without a ledger is rc2 (never a silent default)" 2 "$?"
  rm -rf "$_t87_nl"
  # The real repo's --check compares the shipped table against the committed pin
  # (tests/.shard-plan-costs.tsv), so it is a stable verdict: rc0 means the table
  # is exactly what the model produces. rc2 would mean the tool is broken.
  bash "$ROOT/scripts/shard-plan.sh" --check >/dev/null 2>&1; _t87_spc=$?
  report "T87 planner --check matches the pinned model on the real plan (rc0)" 0 "$_t87_spc"
  # TC-2345/2346: the two carriers of the rework-split rule, and the falsified
  # seventh lever. A65 covers the same carriers from the audit side; this pair
  # keeps the claims chain (pre-review-check) able to see the TC ids in the
  # machine face, and pins the decision not to rewrite new_repo.
  _t87_carriers=0
  for _t87_c in "resources/AGENTS.md|返工分治（v3.97.0，CHG-134）" \
                "resources/DEVELOPMENT_STANDARDS.md|返工分治（v3.97.0，CHG-134）" \
                "resources/templates/entry/05-test-results.md|## 延后补钉登记"; do
    grep -qF -- "${_t87_c#*|}" "$ROOT/${_t87_c%%|*}" 2>/dev/null && _t87_carriers=$(( _t87_carriers + 1 ))
  done
  report "T87 TC-2345 the rework-split rule lands on AGENTS, DS and the 05 template" 3 "$_t87_carriers"
  report "T87 TC-2346 the setup lever stays falsified (new_repo keeps its one body)" 1 \
    "$(grep -c '^new_repo()' "$ROOT/tests/run-tests.sh")"
  # TC-2348..2350 (v3.97.1, CHG-135): the cost ledger is one file with several
  # writers — the lock must cover migration, append AND retention, and an
  # evidence round must hand every shard the same absolute path.
  _t87_lkf=$(sed -n '/^ledger_append() {/,/^}/p' "$ROOT/tests/run-tests.sh")
  # Split, not summed: 2 acquires + 2 releases must not look like 1 + 3.
  report "T87 TC-2350 ledger_append acquires the lock exactly once" 1 \
    "$(printf '%s\n' "$_t87_lkf" | grep -c '_ledger_lock_acquire && lk=1')"
  report "T87 TC-2350 ledger_append releases on every exit path" 3 \
    "$(printf '%s\n' "$_t87_lkf" | grep -c '_ledger_lock_release')"
  report "T87 TC-2350 the stub sec row is skipped inside a snapshot" 1 \
    "$(grep -c '^_sec_row_wanted() {' "$ROOT/tests/run-tests.sh")"
  _t87_lgd=$(mktemp -d "${TMPDIR:-/tmp}/t87-ledger.XXXXXX")
  # v3.98.1 (CHG-138/REQ-1357): CI-only concurrency probes (TC-2348 legacy
  # migration, TC-2351 aborted-round writers) have red without a proven root
  # cause — dump the live scene on failure so the next red run carries its own
  # evidence. Best effort: forensics must never turn a red case green or mask
  # a green one (no assertion reads anything it writes).
  _t87_forensic() { # <tag> [extra summary text via stdin]
    local _fd="$ROOT/.agent-state/t87-forensics"
    mkdir -p "$_fd" 2>/dev/null || return 0
    {
      echo "tag: $1"
      echo "utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "cores: $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"
      echo "suite_jobs: ${AGENT_GUARD_SUITE_JOBS:-unset}"
      for _fl in 1 2 3; do
        [[ -f "$_t87_lgd/ledger-$_fl.tsv" ]] || continue
        echo "ledger-$_fl: lines=$(wc -l < "$_t87_lgd/ledger-$_fl.tsv" | tr -d ' ') nf_hist=($(awk -F'\t' '{n[NF]++} END {for (f in n) printf "NF%s=%s ", f, n[f]}' "$_t87_lgd/ledger-$_fl.tsv"))"
        cp "$_t87_lgd/ledger-$_fl.tsv" "$_fd/ledger-$_fl-$1.tsv" 2>/dev/null
      done
      [[ -f "$_t87_lgd/writers.err" ]] && cp "$_t87_lgd/writers.err" "$_fd/writers-$1.err" 2>/dev/null
      # ps snapshot targets the kids explicitly (and keeps a full tail as
      # context): the old `ps -eo ... | head -120` sorts by pid, so on a busy
      # runner the suite's own (high) pids were cut and the snapshot carried
      # zero evidence (CHG-139).
      {
        _t87_fkids="${_t87_fzkids:-}"
        # CHG-139 review #1: filter to LIVE pids first — macOS `ps -p` fails
        # wholesale (rc1, zero lines) when the list contains one reaped pid,
        # which is exactly the red-scene case.
        _t87_flive=""
        for _k in $_t87_fkids; do
          kill -0 "$_k" 2>/dev/null && _t87_flive="$_t87_flive $_k"
        done
        _t87_flive="${_t87_flive# }"
        if [[ -n "$_t87_flive" ]]; then
          ps -o pid,ppid,stat,etime,args -p "${_t87_flive// /,}" 2>/dev/null
        fi
        echo "dead kids: $(for _k in $_t87_fkids; do kill -0 "$_k" 2>/dev/null || printf '%s ' "$_k"; done)"
        echo "--- full table tail ---"
        ps -eo pid,ppid,stat,args 2>/dev/null | tail -40
      } > "$_fd/ps-$1.txt" 2>/dev/null
      # stdin echo only when redirected (heredoc/pipe): an interactive caller
      # would otherwise block on the tty (CHG-138 review L1).
      [[ ! -t 0 ]] && cat
    } > "$_fd/summary-$1.txt" 2>/dev/null
    return 0
  }
  _t87_fixture() { # <path>: legacy 8-column ledger above the rotation trigger
    # 605 legacy rows + an 8-column header: a first locked append then MIGRATES
    # the schema and ROTATES (>600) — two rewrites inside the critical section.
    # A fixture below the trigger never enters the window the lock exists for,
    # and an unlocked ledger_append would score 30/30 too (review #2 finding).
    { printf 'ts\tkind\tid\tsuite_key\tcost_s\tsetup_s\tcache\texit\n'
      _fi=1
      while [[ "$_fi" -le 605 ]]; do
        printf '2026-08-01T00:00:00Z\trun\tF%s\tprobe\t1\t0\tnone\t0\n' "$_fi"
        _fi=$(( _fi + 1 ))
      done
    } > "$1"
  }
  { # BSD sed has no address-range-with-command form; drop the duplicated last line.
    sed -n '/^_LEDGER_LOCK_MINE=0$/,/^ledger_append() {/p' "$ROOT/tests/run-tests.sh" | sed '$d'
    sed -n '/^ledger_append() {/,/^}/p' "$ROOT/tests/run-tests.sh"; } > "$_t87_lgd/fn.sh"
  { printf 'ROOT="$1"; LEDGER_FILE="$2"; SUITE_KEY=probe; source "$3"\n'
    printf 'i=1; while [ "$i" -le 5 ]; do ledger_append sec "S$4-$i" 1 0 none 0 1; i=$((i+1)); done\n'
  } > "$_t87_lgd/w.sh"
  # Three repetitions: one run passes the unlocked writer ~1 time in 3 (measured
  # 30/18/12 on HEAD), so a single probe would be a coin flip.
  _t87_kept=0; _t87_lkleft=0; _rep=1
  while [[ "$_rep" -le 3 ]]; do
    _t87_fixture "$_t87_lgd/ledger-$_rep.tsv"
    _t87_lgp=""; _p=1
    while [[ "$_p" -le 6 ]]; do
      bash "$_t87_lgd/w.sh" "$_t87_lgd" "$_t87_lgd/ledger-$_rep.tsv" "$_t87_lgd/fn.sh" "$_p" \
        2>> "$_t87_lgd/writers.err" & _t87_lgp="$_t87_lgp $!"
      _p=$(( _p + 1 ))
    done
    for _w in $_t87_lgp; do wait "$_w"; done
    _t87_one=$(awk -F'\t' '$3 ~ /^S[1-6]-/ {c++} END {print c+0}' "$_t87_lgd/ledger-$_rep.tsv")
    _t87_kept=$(( _t87_kept + _t87_one ))
    [[ -d "$_t87_lgd/ledger-$_rep.tsv.lock" ]] && _t87_lkleft=$(( _t87_lkleft + 1 ))
    _rep=$(( _rep + 1 ))
  done
  report "T87 TC-2348 six concurrent writers keep every appended row (3x 30/30)" 90 "$_t87_kept"
  _t87_bad14=$(awk -F'\t' 'NF != 14 {c++} END {print c+0}' "$_t87_lgd/ledger-3.tsv")
  (( _t87_bad14 > 0 )) && _t87_forensic tc2348 <<EOT
tc2348: ledger-3.tsv has $_t87_bad14 row(s) with NF != 14 (expected 0)
EOT
  report "T87 TC-2348 the legacy ledger was migrated to the 14-column schema" 0 "$_t87_bad14"
  report "T87 TC-2348 retention ran inside the critical section" 1 \
    "$([[ "$(wc -l < "$_t87_lgd/ledger-3.tsv" 2>/dev/null | tr -d ' ')" -le 600 ]] && echo 1 || echo 0)"
  report "T87 TC-2348 no writer falls back to an unlocked append" 0 \
    "$(grep -c 'appended without rotation' "$_t87_lgd/writers.err" 2>/dev/null || true)"
  report "T87 TC-2348 no writer leaves the ledger lock behind" 0 "$_t87_lkleft"
  # A DEAD owner is the reclaim race review #2 (N1/N1-pin) found: every waiter
  # sees the same corpse and, without a serialized takeover, more than one
  # re-creates the dir. The fixture must sit ABOVE the rotation trigger, because
  # row loss needs a rewrite (migration/rotation) — a 530-line ledger would score
  # 30/30 even with the unserialized reclaim (review #2 round 3).
  bash -c 'exit 0' & _t87_dead=$!
  wait "$_t87_dead" 2>/dev/null || true
  _t87_fixture "$_t87_lgd/ledger-dead.tsv"
  mkdir "$_t87_lgd/ledger-dead.tsv.lock"
  printf '%s\n' "$_t87_dead" > "$_t87_lgd/ledger-dead.tsv.lock/pid"
  _t87_gp=""; _p=1
  while [[ "$_p" -le 6 ]]; do
    bash "$_t87_lgd/w.sh" "$_t87_lgd" "$_t87_lgd/ledger-dead.tsv" "$_t87_lgd/fn.sh" "G$_p" \
      2>> "$_t87_lgd/dead.err" & _t87_gp="$_t87_gp $!"
    _p=$(( _p + 1 ))
  done
  for _w in $_t87_gp; do wait "$_w"; done
  report "T87 TC-2348 six writers reclaim a dead owner exactly once (30/30)" 30 \
    "$(awk -F'\t' '$3 ~ /^SG[1-6]-/ {c++} END {print c+0}' "$_t87_lgd/ledger-dead.tsv")"
  report "T87 TC-2348 the reclaimed ledger also crossed the rotation trigger" 1 \
    "$([[ "$(awk -F'\t' '$3 ~ /^SG[1-6]-/ {c++} END {print c+0}' "$_t87_lgd/ledger-dead.tsv")" == "30" ]] && [[ "$(wc -l < "$_t87_lgd/ledger-dead.tsv" | tr -d ' ')" -le 600 ]] && echo 1 || echo 0)"
  # v3.97.1 (CHG-135): "exactly once" was over-specified — round-8 caught a
  # second takeover whose re-verify found the dir's owner genuinely gone (ps
  # reports no such pid), i.e. a leaked lock being recovered again, not two
  # live holders: rows stayed 30/30 in every observed run (40 loaded + 60
  # instrumented reps). The safety property is "the takeover ran" + rows +
  # no residue; the count itself is incidental.
  report "T87 TC-2348 the dead owner was reclaimed (takeover ran)" 1 \
    "$([[ "$(grep -c 'reclaimed a stale owner' "$_t87_lgd/dead.err" 2>/dev/null || true)" -ge 1 ]] && echo 1 || echo 0)"
  _t87_resid=0
  [[ -d "$_t87_lgd/ledger-dead.tsv.lock" ]] && _t87_resid=$(( _t87_resid + 1 ))
  [[ -d "$_t87_lgd/ledger-dead.tsv.lock.reclaim" ]] && _t87_resid=$(( _t87_resid + 1 ))
  report "T87 TC-2348 the dead-owner lock is gone and no takeover mutex is left" 0 "$_t87_resid"
  report "T87 TC-2348 no dead-owner writer falls back to an unlocked append" 0 \
    "$(grep -c 'appended without rotation' "$_t87_lgd/dead.err" 2>/dev/null || true)"
  # An owner-less lock (mkdir landed, the pid write never did) must not disable
  # retention forever: an aged empty lock is reclaimed, not waited out.
  mkdir "$_t87_lgd/ledger-3.tsv.lock"
  touch -t 202001010000 "$_t87_lgd/ledger-3.tsv.lock"
  bash "$_t87_lgd/w.sh" "$_t87_lgd" "$_t87_lgd/ledger-3.tsv" "$_t87_lgd/fn.sh" 7 2>> "$_t87_lgd/s7.err"
  report "T87 TC-2348 an owner-less lock is reclaimed and the row still lands" 5 \
    "$(awk -F'\t' '$3 ~ /^S7-/ {c++} END {print c+0}' "$_t87_lgd/ledger-3.tsv")"
  report "T87 TC-2348 the reclaimed lock is gone" 0 \
    "$([[ -d "$_t87_lgd/ledger-3.tsv.lock" ]] && echo 1 || echo 0)"
  report "T87 TC-2348 the owner-less probe also kept the lock (no silent fallback)" 0 \
    "$(grep -c 'appended without rotation' "$_t87_lgd/s7.err" 2>/dev/null || true)"
  # v3.97.1 (CHG-135): evidence-round resolves ROOT physically (`pwd -P`), so a
  # repo reached through a symlink (macOS /tmp -> /private/tmp, and the fresh-clone
  # receipt's mktemp dir) prints the physical path. Compare against that, or the
  # assertion only holds on un-symlinked checkouts.
  _t87_rootp=$(cd "$ROOT" && pwd -P)
  _t87_erlg=$(env -u AGENT_GUARD_COST_LEDGER bash "$ROOT/scripts/evidence-round.sh" --chg CHG-ER --shards 2 \
      --state-dir "$_t87_lgd/state" --dry-run 2>/dev/null \
      | grep -c "AGENT_GUARD_COST_LEDGER=\"$_t87_rootp/.agent-state/cost-ledger.tsv\"")
  report "T87 TC-2349 evidence-round hands every shard the same absolute ledger path" 2 "$_t87_erlg"
  _t87_erlo=$(AGENT_GUARD_COST_LEDGER=rel/l.tsv bash "$ROOT/scripts/evidence-round.sh" --chg CHG-ER --shards 2 \
      --state-dir "$_t87_lgd/state" --dry-run 2>/dev/null \
      | grep -c "AGENT_GUARD_COST_LEDGER=\"$_t87_rootp/rel/l.tsv\"")
  report "T87 TC-2349 a relative override is absolutized for snapshot shards" 2 "$_t87_erlo"
  report "T87 TC-2349 the shard launch actually exports the shared path" 1 \
    "$(grep -c 'AGENT_GUARD_COST_LEDGER="$_shared_ledger" bash "$SUITE"' "$ROOT/scripts/evidence-round.sh")"
  # v3.97.1 (CHG-135, REQ-1350): freeze window — a round testifies for exactly
  # one tracked tree. (a) a live round's lock refuses fingerprint-counted writes
  # at pre-write, (b) the lock's own directory and gitignored paths stay
  # writable, (c) a leaked dead-owner lock never blocks, (d) a write that still
  # lands (raw sed, no hook) marks the round INVALID instead of leaving a
  # clean-looking meta.tsv behind.
  _t87_fz=$(mktemp -d "${TMPDIR:-/tmp}/t87-freeze.XXXXXX")
  ( cd "$_t87_fz" && git init -q . && git config user.email t@t && git config user.name t \
      && printf '.agent-state/\n' > .gitignore && mkdir -p scripts \
      && echo keep > keep.txt && cp "$ROOT/scripts/evidence-round.sh" scripts/ \
      && cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" scripts/ \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  printf '#!/bin/bash\n[ "${PWD}" = "${DRIFT_ROOT:-}" ] && echo drift >> keep.txt\nexit 0\n' > "$_t87_fz/stub.sh"
  chmod +x "$_t87_fz/stub.sh"
  # The round's lock is one stamped file (link(2) publish); the gate reads it.
  _t87_lock() { # <pid> [lock path]
    local lk="${2:-$_t87_fz/.agent-state/evidence-round.lock}"
    mkdir -p "$(dirname "$lk")"
    { printf 'pid=%s\n' "$1"
      printf 'lstart=%s\n' "$(LC_ALL=C ps -p $$ -o lstart= 2>/dev/null || true)"
      printf 'chg=CHG-FZ\nround=1\ntree_sha=-\n'; } > "$lk"
  }
  _t87_lock "$$"
  _t87_fzo=$( cd "$_t87_fz" && bash "$GATE_SRC" --stage pre-write --file keep.txt 2>&1 )
  report "T87 TC-2351 a live round's lock refuses a counted-file write (E156)" 1 \
    "$(grep -c 'GATE-E156' <<< "$_t87_fzo")"
  _t87_fzo2=$( cd "$_t87_fz" && bash "$GATE_SRC" --stage pre-write --file .agent-state/evidence-round.lock 2>&1 )
  report "T87 TC-2351 the lock path and gitignored paths stay writable" 0 \
    "$(grep -c 'GATE-E156' <<< "$_t87_fzo2")"
  _t87_lock 999999
  _t87_fzo3=$( cd "$_t87_fz" && bash "$GATE_SRC" --stage pre-write --file keep.txt 2>&1 )
  report "T87 TC-2351 a leaked dead-owner lock never blocks" 0 \
    "$(grep -c 'GATE-E156' <<< "$_t87_fzo3")"
  rm -f "$_t87_fz/.agent-state/evidence-round.lock"
  # The round resolves ROOT physically (pwd -P), so the stub must compare against
  # the physical path or macOS /tmp -> /private/tmp silently defeats the drift.
  _t87_fzp=$( cd "$_t87_fz" && pwd -P )
  ( cd "$_t87_fz" && DRIFT_ROOT="$_t87_fzp" AGENT_GUARD_EVIDENCE_SUITE="$_t87_fz/stub.sh" \
      bash scripts/evidence-round.sh --chg CHG-FZ --shards 2 --skip-precheck --no-sum >/dev/null 2>&1 ); _t87_fzrc=$?
  report "T87 TC-2351 a mid-round tracked edit makes the round INVALID (rc2)" 2 "$_t87_fzrc"
  report "T87 TC-2351 the invalid round says so in meta (tree_drift=1)" 1 \
    "$(awk -F'\t' '$1=="tree_drift"{print $2}' "$_t87_fz/.agent-state/evidence/CHG-FZ/round-1/meta.tsv" 2>/dev/null)"
  # A second round must not start while the first one's owner is alive.
  _t87_lock "$$"
  ( cd "$_t87_fz" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_fz/stub.sh" \
      bash scripts/evidence-round.sh --chg CHG-FZ3 --shards 2 --skip-precheck --no-sum \
      > "$_t87_fz/live.out" 2>&1 ); _t87_fzlrc=$?
  report "T87 TC-2351 a live owner refuses a second round (rc2)" 2 "$_t87_fzlrc"
  report "T87 TC-2351 the refusal names the live owner" 1 \
    "$(grep -c 'held by a live round' "$_t87_fz/live.out" 2>/dev/null || true)"
  # A dead owner must not brick the tree: the next round reclaims and runs.
  _t87_lock 999999
  ( cd "$_t87_fz" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_fz/stub.sh" \
      bash scripts/evidence-round.sh --chg CHG-FZ4 --shards 2 --skip-precheck --no-sum \
      >/dev/null 2>&1 ); _t87_fzsrc=$?
  report "T87 TC-2351 a dead owner's lock is reclaimed and the round runs" 0 "$_t87_fzsrc"
  report "T87 TC-2351 the reclaimed round releases the lock" 0 \
    "$([[ -e "$_t87_fz/.agent-state/evidence-round.lock" ]] && echo 1 || echo 0)"
  # SIGTERM must abort the round (no evidence), not just drop the lock and keep
  # going. The stub ignores TERM: a shard that survives the signal would keep
  # writing into the tree after the freeze window closed.
  printf '#!/bin/bash\ntrap "" TERM\nsleep 8\nexit 0\n' > "$_t87_fz/slow.sh"
  chmod +x "$_t87_fz/slow.sh"
  # --live-shard 1: skip the 6-way resolution loop so the lock appears at once.
  ( cd "$_t87_fz" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_fz/slow.sh" \
      exec bash scripts/evidence-round.sh --chg CHG-FZ5 --shards 2 --live-shard 1 \
      --skip-precheck --no-sum >/dev/null 2>&1 ) &
  _t87_fzsigpid=$!
  _t87_fzgotlock=1
  for _i in $(seq 1 60); do
    [[ -e "$_t87_fz/.agent-state/evidence-round.lock" ]] && { _t87_fzgotlock=0; break; }
    sleep 0.1
  done
  report "T87 TC-2351 the round held the lock before the signal" 0 "$_t87_fzgotlock"
  # Every descendant, not just the direct children: the real writer is the
  # suite process below the wrapper, and an orphaned grandchild would survive a
  # check that only looks at `pgrep -P <round>`.
  _t87_desc() { # <pid>
    local _c
    for _c in $(pgrep -P "$1" 2>/dev/null); do
      printf '%s\n' "$_c"
      _t87_desc "$_c"
    done
  }
  _t87_fzkids=$(_t87_desc "$_t87_fzsigpid" | tr '\n' ' ')
  sleep 0.2
  kill -TERM "$_t87_fzsigpid" 2>/dev/null || true
  wait "$_t87_fzsigpid" 2>/dev/null; _t87_fzsigrc=$?
  report "T87 TC-2351 SIGTERM aborts the round (rc143)" 143 "$_t87_fzsigrc"
  report "T87 TC-2351 the aborted round releases the lock" 0 \
    "$([[ -e "$_t87_fz/.agent-state/evidence-round.lock" ]] && echo 1 || echo 0)"
  # A just-killed child can still answer kill -0 as a zombie until it is reaped;
  # only a live (non-Z) process counts as a surviving writer.
  # v3.98.1 (CHG-138/REQ-1357): grace floor scales with core count — CI runners
  # (2 vCPU, AGENT_GUARD_SUITE_JOBS=4) need more than the fixed 5x0.2s for a
  # SIGTERM'd round to reap its shard writers; a healthy local run still breaks
  # out on the first green pass, so the common path pays nothing.
  _t87_fztries=$(( 5 + $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2) * 5 ))
  _t87_fzalive=0
  # C-style loop, not `seq`: pure bash builtin, no external dependency (CHG-138 review L4).
  for ((_i = 1; _i <= _t87_fztries; _i++)); do
    _t87_fzalive=0
    for _p in $_t87_fzkids; do
      _st=$(ps -p "$_p" -o stat= 2>/dev/null | tr -d ' ')
      [[ -n "$_st" && "$_st" != Z* ]] && _t87_fzalive=1
    done
    (( _t87_fzalive )) || break
    sleep 0.2
  done
  (( _t87_fzalive )) && _t87_forensic tc2351 <<EOT
tc2351: surviving writer(s) after SIGTERM + ${_t87_fztries}x0.2s grace: kids=[$_t87_fzkids]
EOT
  report "T87 TC-2351 the aborted round leaves no shard writer behind" 0 "$_t87_fzalive"
  # TC-2366 (v3.98.1 CHG-139/REQ-1358 review #2): a DETERMINISTIC orphan probe —
  # the shard process dies on TERM while its TERM-immune grandchild (SIG_IGN
  # inherited by `bash -c`) survives and is reparented. The old re-walk lost it
  # (pgrep -P of a dead pid is empty); the recorded roster must KILL it. This
  # is structure, not timing, so it discriminates locally too — the slow.sh
  # probe above only discriminated under CI load.
  printf '#!/bin/bash\ntrap "exit 0" TERM\nbash -c '"'"'trap "" TERM; sleep 8'"'"' &\nwait $!\nexit 0\n' > "$_t87_fz/wrap.sh"
  chmod +x "$_t87_fz/wrap.sh"
  ( cd "$_t87_fz" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_fz/wrap.sh" \
      exec bash scripts/evidence-round.sh --chg CHG-FZ8 --shards 1 --live-shard 1 \
      --skip-precheck --no-sum >/dev/null 2>&1 ) &
  _t87_fzwpid=$!
  for _i in $(seq 1 60); do
    [[ -e "$_t87_fz/.agent-state/evidence-round.lock" ]] && break
    sleep 0.1
  done
  _t87_fzwkids=$(_t87_desc "$_t87_fzwpid" | tr '\n' ' ')
  sleep 0.2
  kill -TERM "$_t87_fzwpid" 2>/dev/null || true
  wait "$_t87_fzwpid" 2>/dev/null
  _t87_fzwalive=0
  for _i in 1 2 3 4 5; do
    _t87_fzwalive=0
    for _p in $_t87_fzwkids; do
      _st=$(ps -p "$_p" -o stat= 2>/dev/null | tr -d ' ')
      [[ -n "$_st" && "$_st" != Z* ]] && _t87_fzwalive=1
    done
    (( _t87_fzwalive )) || break
    sleep 0.2
  done
  (( _t87_fzwalive )) && _t87_forensic tc2366 <<EOT
tc2366: orphaned TERM-immune sleeper survived roster KILL: kids=[$_t87_fzwkids]
EOT
  report "T87 TC-2366 an orphaned TERM-immune sleeper dies via the roster" 0 "$_t87_fzwalive"
  # Without a fingerprint there is no drift check: refusing beats a blind green.
  mv "$_t87_fz/scripts/lib-suite-tree-fingerprint.sh" "$_t87_fz/scripts/lib.hold"
  ( cd "$_t87_fz" && AGENT_GUARD_EVIDENCE_SUITE="$_t87_fz/stub.sh" \
      bash scripts/evidence-round.sh --chg CHG-FZ6 --shards 2 --skip-precheck --no-sum \
      >/dev/null 2>&1 ); _t87_fznorc=$?
  mv "$_t87_fz/scripts/lib.hold" "$_t87_fz/scripts/lib-suite-tree-fingerprint.sh"
  report "T87 TC-2351 no start fingerprint refuses the round (rc2)" 2 "$_t87_fznorc"
  # Runtime state stays writable even where .agent-state is not gitignored: the
  # exemption must mirror the fingerprint recipe, not depend on ignore rules.
  _t87_fz2=$(mktemp -d "${TMPDIR:-/tmp}/t87-freeze2.XXXXXX")
  ( cd "$_t87_fz2" && git init -q . && git config user.email t@t && git config user.name t \
      && mkdir -p .agent-state && echo keep > keep.txt && echo rt > .agent-state/tracked.txt \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  _t87_lock "$$" "$_t87_fz2/.agent-state/evidence-round.lock"
  _t87_fzo5=$( cd "$_t87_fz2" && bash "$GATE_SRC" --stage pre-write --file .agent-state/tracked.txt 2>&1 )
  report "T87 TC-2351 runtime state stays writable without an ignore rule" 0 \
    "$(grep -c 'GATE-E156' <<< "$_t87_fzo5")"
  _t87_fzo6=$( cd "$_t87_fz2" && bash "$GATE_SRC" --stage pre-write --file keep.txt 2>&1 )
  report "T87 TC-2351 the same repo still refuses a counted write" 1 \
    "$(grep -c 'GATE-E156' <<< "$_t87_fzo6")"
  rm -rf "$_t87_fz2"
  rm -rf "$_t87_fz"
  rm -rf "$_t87_lgd"
  rm -rf "$_t87_spd"
  rm -f "$_t87_cache"

  # ── CHG-158 (v4.13.0, REQ-1460~1463): TC-10084..10088 三大拆分与提速回归 ──
  local _t87_hot _t87_hot_out _t87_hot_rc
  _t87_hot=$(mktemp -d "${TMPDIR:-/tmp}/t87-hot.XXXXXX")
  ( cd "$_t87_hot" && git init -q . && git config user.email t@t && git config user.name t \
      && mkdir -p scripts src && printf 'hi\n' > README.md && printf 'x\n' > src/a.ts \
      && cp "$GATE_SRC" scripts/agent-gate && chmod +x scripts/agent-gate \
      && cp "$ROOT/resources/templates/lib-json.sh" scripts/lib-json.sh \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  # TC-10084: 热入口无温/冷库独立工作
  ( cd "$_t87_hot" && bash scripts/agent-gate --stage pre-write --file README.md >/dev/null 2>&1 )
  report "T87 TC-10084 hot pre-write non-code passes without warm/cold libs" 0 $?
  ( cd "$_t87_hot" && bash scripts/agent-gate status >/dev/null 2>&1 )
  report "T87 TC-10084 hot status passes without warm/cold libs" 0 $?
  ( cd "$_t87_hot" && bash scripts/agent-gate end >/dev/null 2>&1 )
  report "T87 TC-10084 hot end passes without warm/cold libs" 0 $?
  _t87_hot_out=$( cd "$_t87_hot" && bash scripts/agent-gate --stage pre-write --file src/a.ts 2>&1 ); _t87_hot_rc=$?
  report "T87 TC-10084 hot pre-write code without active change exits 2 (E43)" 2 "$_t87_hot_rc"
  report "T87 TC-10084 hot E43 fires cleanly without missing-warm error" 1 \
    "$([[ "$_t87_hot_out" == *GATE-E43* && "$_t87_hot_out" != *cannot\ locate\ lib-gate-staged* ]] && echo 1 || echo 0)"
  # TC-10085: 热路径锁文件短路不绕过 GATE-E156，补齐温库与活跃变更后记心跳
  _t87_lock "$$" "$_t87_hot/.agent-state/evidence-round.lock"
  _t87_hot_out=$( cd "$_t87_hot" && bash scripts/agent-gate --stage pre-write --file src/a.ts 2>&1 ); _t87_hot_rc=$?
  report "T87 TC-10085 hot pre-write enforces GATE-E156 under lock without warm lib" "2:1" \
    "${_t87_hot_rc}:$(grep -c 'GATE-E156' <<< "$_t87_hot_out")"
  rm -f "$_t87_hot/.agent-state/evidence-round.lock"
  cp "$ROOT/resources/templates/lib-gate-staged.sh" "$_t87_hot/scripts/lib-gate-staged.sh"
  ( cd "$_t87_hot" && seed_project_masters && seed_artifacts CHG-999 L1 claude/s-hot \
      && mkdir -p "$(dirname "$(git rev-parse --git-path agent-governance/active-change)")" \
      && printf 'CHG-999\n' > "$(git rev-parse --git-path agent-governance/active-change)" \
      && AGENT_GUARD_ALLOW_INDEPENDENT=1 bash scripts/agent-gate --stage pre-write --file src/a.ts >/dev/null 2>&1 )
  report "T87 TC-10085 warm-backed pre-write code passes and logs heartbeat" "0:1" \
    "$?:$(grep -c 'CHG-999' "$_t87_hot/.agent-state/pre-write-ledger.tsv" 2>/dev/null || echo 0)"
  rm -rf "$_t87_hot"
  # TC-10086: 模块化测试套件语法与薄调度器按需加载
  bash -n "$ROOT/tests/lib/test-harness.sh" "$ROOT/tests/suites/"*.sh >/dev/null 2>&1
  report "T87 TC-10086 modular test-harness and 8 suites pass bash -n" 0 $?
  report "T87 TC-10086 run-tests dispatcher <= 1300 lines" 1 \
    "$([[ "$(wc -l < "$ROOT/tests/run-tests.sh" | tr -d ' ')" -le 1300 ]] && echo 1 || echo 0)"
  # TC-10087: T49a/T49b/T49c 与 new_repo CoW
  report "T87 TC-10087 SECTIONS includes T49a/T49b/T49c and drops T49" 1 \
    "$(grep -E '^SECTIONS=.*T49a T49b T49c' "$ROOT/tests/run-tests.sh" | grep -cv ' T49 ')"
  report "T87 TC-10087 new_repo supports CoW cp fallback" 1 \
    "$([[ $(grep -cE 'cp -c -pR|cp --reflink=auto' "$ROOT/tests/run-tests.sh") -ge 1 ]] && echo 1 || echo 0)"
  # TC-10088: audit-standards-src 单趟 awk run_audit_rules 引擎
  report "T87 TC-10088 audit-standards-src defines run_audit_rules engine" 1 \
    "$(grep -c '^run_audit_rules()' "$ROOT/tests/audit-standards-src.sh")"
}

section_T88() {
# ------------------------------------------------ T88 E160 测试弱化五类 diff-watch golden（v4.1.0，CHG-145/FU-1011）
# 五类阳性必抓（E160 置于 staged 链首位，先于 E125/unaccounted die）+ 阴性 3 零误报 +
# 逃生口 WARN。断言面=输出含/不含 GATE-E160 与类目词；阴性不锁全链 rc（后置检查
# 面——receipt/unaccounted 等——不属本变更断言域）。
  cd "$ROOT"
  local _t88_out _t88_rc
  _t88_case() { # <tag> <content> <hit|no|warn> [类目词]
    new_repo
    mkdir -p tests
    printf 'expect("a")\ncoverage = 90\n' > tests/t1.sh
    git add -A
    git commit -qm base
    printf '%s\n' "$2" > tests/t1.sh
    git add -A
    _t88_out=$(scripts/agent-gate --stage staged 2>&1); _t88_rc=$?
    if [[ "$3" == "hit" ]]; then
      report "T88 E160 blocks [$1] (staged rc)" 2 "$_t88_rc"
      grep -Fq 'GATE-E160' <<< "$_t88_out"
      report "T88 [$1] output names GATE-E160" 0 $?
      grep -Fq "$4" <<< "$_t88_out"
      report "T88 [$1] output names the class word ($4)" 0 $?
    else
      grep -F 'GATE-E160' <<< "$_t88_out"
      report "T88 [$1] emits no E160 (no false kill)" 1 $?
      if [[ "$3" == "warn" ]]; then
        grep -Fq 'owner+期限标注在位' <<< "$_t88_out"
        report "T88 [$1] escape emits the WARN line" 0 $?
      fi
    fi
  }
  _t88_case '①断言删除'    'log("hi")'                            hit '①断言删除/弱化'
  # 夹具 payload 拼片构造（'describe.'"skip" 等）：文件文本不得含活性 token，
  # 否则全新安装整文件 add 本套件时 ②④⑤ 自指误伤（T15 D5 死锁教训，同 _t87_pat 手法）。
  _t88_case '②skip'         $'expect("a")\ndescribe.'"skip"'("s")'     hit '②skip/only 跳测'
  _t88_case '③阈值下调'     $'expect("a")\ncoverage = 50'          hit '③阈值下调'
  _t88_case '④检查器静默'   $'expect("a")\n# n'"oqa"               hit '④检查器静默'
  _t88_case '⑤例外无标注'   $'expect("a")\nAGENT_GUARD_ALLOW_'"X"'=1'  hit '⑤例外无 owner+期限'
  _t88_case '⑤逃生口'       $'expect("a")\nAGENT_GUARD_ALLOW_'"X"'=1  # owner: t1 期限: 2026-12-31' warn
  _t88_case '阴性-阈值上调'  $'expect("a")\ncoverage = 95'          no
  _t88_case '阴性-新增测试'  $'expect("a")\nexpect("b")'            no
  _t88_case '阴性-重构重排'  $'coverage = 90\nexpect("a")'          no
  cd "$ROOT"
}

