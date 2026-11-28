#!/usr/bin/env bash
# suite-02-install.sh — domain suite module (v4.13.0, CHG-158)

section_T14() {
# ------------------------------------------------ T14 路径根可配置（v3.15.0）
# 目录根走 .agent-governance.yml 的 paths.*，默认值即历史写死值。本段锁两条不变式：
#   ① 配了非默认根 → 门禁按配置找（落点与校验错位是静默假绿，比报错危险）；
#   ② 没配 → 逐字节回到历史行为（零回归，老仓库升级后行为不变）。
# 另锁"契约名不可配置"：换根后 AGENTS.md 仍须落仓库根（它不是路径根）。
new_repo
mkdir -p doc && mv docs/project doc/project   # v3.35.0：paths.docs=doc → begin 按配置根找总册
mkdir -p doc/changes/CFG-1
printf 'paths:\n  docs: doc\nchange_root: doc/changes\n' > .agent-governance.yml
cat > doc/changes/CFG-1/00-intent.md <<'EOF'
## 预期结果
e
## 目录落位
- **目录落位**：独立目录（t14 fixture）
## 开放问题
o
EOF
printf '{"change_id":"CFG-1","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a","test_owner":"t/x","review_owner":"r/x"}\n' > doc/changes/CFG-1/00-governance.json
printf '# CFG-1 沟通稿\n## 用户整体确认记录\n- 确认状态：已整体确认\n' > doc/changes/CFG-1/00.5-communication.md
echo "REQ-001 s" > doc/changes/CFG-1/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > doc/changes/CFG-1/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n- **既有范式关系**：未命中（纯新增无同族实现）\n' > doc/changes/CFG-1/03-modification-plan.md
printf '# tasks\n- T-001: x（依赖: 无；里程碑: M1）\n- 评审输入: 变更文件清单 + 产物路径 + 行号锚点\n' > doc/changes/CFG-1/03.5-tasks.md
printf 'TC-001 t\n## 用例矩阵\n覆盖维度: 正常流\n## 业务场景清单\nSC-001 s（覆盖: TC-001）\n' > doc/changes/CFG-1/04-test-scripts.md
out=$(scripts/agent-gate begin CFG-1 2>&1); rc=$?
report "T14 gate honors paths.docs from config" 0 "$rc"
check_output "T14 gate resolved the configured change root" "active change is CFG-1" "$out"

# 派生：只给 paths.docs，change_root 应由它派生（而非回落到 docs/changes）
new_repo
mkdir -p doc && mv docs/project doc/project   # v3.35.0：paths.docs=doc → begin 按配置根找总册
mkdir -p doc/changes/CFG-2
printf 'paths:\n  docs: doc\n' > .agent-governance.yml
cat > doc/changes/CFG-2/00-intent.md <<'EOF'
## 预期结果
e
## 目录落位
- **目录落位**：独立目录（t14 fixture）
## 开放问题
o
EOF
printf '{"change_id":"CFG-2","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"a","test_owner":"t/x","review_owner":"r/x"}\n' > doc/changes/CFG-2/00-governance.json
printf '# CFG-2 沟通稿\n## 用户整体确认记录\n- 确认状态：已整体确认\n' > doc/changes/CFG-2/00.5-communication.md
echo "REQ-001 s" > doc/changes/CFG-2/01-spec.md
printf '# impact\n## 业务影响\nb\n## 风险\nr\n## 回滚策略\nok\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > doc/changes/CFG-2/02-code-impact-analysis.md
printf 'DES-001 p\n## 技术选型\n备选方案对比: A vs B\n- **既有范式关系**：未命中（纯新增无同族实现）\n' > doc/changes/CFG-2/03-modification-plan.md
printf '# tasks\n- T-001: x（依赖: 无；里程碑: M1）\n- 评审输入: 变更文件清单 + 产物路径 + 行号锚点\n' > doc/changes/CFG-2/03.5-tasks.md
printf 'TC-001 t\n## 用例矩阵\n覆盖维度: 正常流\n## 业务场景清单\nSC-001 s（覆盖: TC-001）\n' > doc/changes/CFG-2/04-test-scripts.md
out=$(scripts/agent-gate begin CFG-2 2>&1); rc=$?
report "T14 change_root derives from paths.docs" 0 "$rc"

# 零回归：不配置任何路径 → 仍走 docs/changes（升级前行为）
new_repo
out=$(scripts/agent-gate begin CHG-X 2>&1); rc=$?
report "T14 unconfigured repo keeps the docs/changes default" 2 "$rc"
check_output "T14 default root is docs/changes" "docs/changes/CHG-X" "$out"

# 路径分类：自定义文档根下的源码后缀文件属"治理文档"，不触发变更产物要求
new_repo
printf 'paths:\n  docs: doc\n' > .agent-governance.yml
mkdir -p doc && echo x > doc/tool.js && git add doc/tool.js
out=$(scripts/agent-gate --stage staged 2>&1); rc=$?
report "T14 custom docs root is treated as non-code" 0 "$rc"

# 安装器端：非默认根落点 + 契约名不动 + 配置回写 + 无值拒绝 + live 跳过仍生效
if [[ -f "$BOOT_SRC" ]]; then
  BT4=$(mktemp -d)
  bash "$BOOT_SRC" --all --docs-dir doc "$BT4" >/dev/null 2>&1
  report "T14 bootstrap --docs-dir installs into the custom root" 0 $?
  [[ -s "$BT4/doc/DEVELOPMENT_STANDARDS.md" && ! -e "$BT4/docs/DEVELOPMENT_STANDARDS.md" ]]
  report "T14 bootstrap wrote the custom root only" 0 $?
  [[ -s "$BT4/AGENTS.md" ]]
  report "T14 contract name AGENTS.md stays at repo root" 0 $?
  grep -q '^  docs: doc' "$BT4/.agent-governance.yml"
  report "T14 bootstrap pins paths.docs into the config" 0 $?
  grep -q '^change_root: doc/changes' "$BT4/.agent-governance.yml"
  report "T14 bootstrap derives change_root from the docs root" 0 $?
  bash "$BOOT_SRC" --core --docs-dir >/dev/null 2>&1
  report "T14 --docs-dir without a value is rejected" 2 $?

  # D6：live 跳过改为按逻辑键匹配，换根后 bugfix-log 必须仍被跳过且内容不丢
  printf '# local ledger entry\n' >> "$BT4/doc/bugfix-log.md"
  ( cd "$BT4" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  out=$(bash "$BOOT_SRC" --upgrade --docs-dir doc "$BT4" 2>&1 || true)
  check_output "T14 upgrade skips the live ledger under a custom root (D6)" "live \(skip\) +doc/bugfix-log\.md" "$out"
  grep -q 'local ledger entry' "$BT4/doc/bugfix-log.md"
  report "T14 upgrade preserved the live ledger content" 0 $?
  rm -rf "$BT4"

  # 模板内部路径引用必须随根改写（hooks/adapter 按路径调门禁），且 .github 不动；
  # 重复安装必须幂等——比较的是"替换后的源"，否则每次都会误报 updated。
  BT5=$(mktemp -d)
  bash "$BOOT_SRC" --all --docs-dir doc --scripts-dir tools --tests-dir spec "$BT5" >/dev/null 2>&1
  report "T14 bootstrap honors --scripts-dir / --tests-dir" 0 $?
  [[ -x "$BT5/tools/agent-gate" && -x "$BT5/spec/run-tests.sh" && -x "$BT5/spec/audit-docs-consistency.sh" ]]
  report "T14 custom scripts/tests roots receive the files" 0 $?
  grep -q 'tools/agent-gate' "$BT5/.githooks/pre-commit"
  report "T14 hooks are rewritten to the custom gate path" 0 $?
  grep -q 'tools/agent-gate' "$BT5/tools/install-hook-adapter"
  report "T14 client adapter is rewritten to the custom gate path" 0 $?
  [[ -e "$BT5/.github/workflows/agent-governance.yml" ]]
  report "T14 .github stays at the platform-mandated location" 0 $?
  out=$(bash "$BOOT_SRC" --all --docs-dir doc --scripts-dir tools --tests-dir spec "$BT5" 2>&1); rc=$?
  report "T14 custom-root install is idempotent" 0 "$rc"
  check_output "T14 custom-root rerun reports up to date (no false drift)" "up to date" "$out"
  rm -rf "$BT5"
  BT6=$(mktemp -d)
  git -C "$BT6" init -q -b master
  bash "$BOOT_SRC" --guard --pipeline "$BT6" >/dev/null 2>&1
  report "T14 TC-10031 master-branch guard+pipeline install rc0" 0 $?
  grep -q 'branches: \[master\]' "$BT6/.github/workflows/agent-governance.yml" \
    && ! grep -q 'branches: \[main\]' "$BT6/.github/workflows/agent-governance.yml" \
    && grep -q 'branches: \[master\]' "$BT6/.github/workflows/artifact-pipeline.yml" \
    && ! grep -q 'branches: \[main\]' "$BT6/.github/workflows/artifact-pipeline.yml"
  report "T14 TC-10031 master-branch rewrites workflows without main residue" 0 $?
  out=$(bash "$BOOT_SRC" --guard --pipeline "$BT6" 2>&1 || true)
  check_output "T14 TC-10031 master-branch rerun reports up to date" "up to date" "$out"
  # TC-10040 (v4.6.0 CHG-151, REQ-1415): linked git worktree (.git is a file)
  BT7=$(mktemp -d)
  git -C "$BT6" -c user.email=t@t -c user.name=t commit --allow-empty -qm "seed master"
  git -C "$BT6" worktree add -q -b wt-branch "$BT7" HEAD
  bash "$BOOT_SRC" --guard --pipeline "$BT7" >/dev/null 2>&1
  grep -q 'branches: \[master\]' "$BT7/.github/workflows/agent-governance.yml" \
    && ! grep -q 'branches: \[main\]' "$BT7/.github/workflows/agent-governance.yml"
  report "T14 TC-10040 linked worktree detects master branch (.git file)" 0 $?
  git -C "$BT6" worktree remove --force "$BT7" 2>/dev/null || rm -rf "$BT7"
  rm -rf "$BT6"
  # TC-10043/10044/10045 (v4.7.0 CHG-152, REQ-1418~1420): CI/branch-protection adapter & profile/code_extensions
  BT8=$(mktemp -d)
  git -C "$BT8" init -q -b master
  mkdir -p "$BT8/tools" "$BT8/packages/api" "$BT8/tests"
  printf 'paths:\n  scripts: tools\ncode_extensions: proto,tf\nscopes:\n  - packages/api\n' > "$BT8/.agent-governance.yml"
  touch "$BT8/.gitlab-ci.yml" "$BT8/packages/api/svc.proto"
  copy_gate_to "$BT8/tools" agent-gate
  cp "$ROOT/resources/templates/install-ci-adapter.sh" "$BT8/tools/install-ci-adapter" && chmod +x "$BT8/tools/install-ci-adapter"
  out=$(bash "$BT8/tools/install-ci-adapter" --detect "$BT8" 2>&1)
  check_output "T14 TC-10043 install-ci-adapter detects gitlab" "platform: gitlab" "$out"
  out=$(bash "$BT8/tools/install-ci-adapter" --print-contract --repo "$BT8" 2>&1)
  check_output "T14 TC-10043 contract uses configured tools/agent-gate" "tools/agent-gate --stage ci" "$out"
  out=$(bash "$BT8/tools/install-ci-adapter" --print-branch-protection-contract gitlab --repo "$BT8" 2>&1)
  check_output "T14 TC-10045 branch protection contract names agent-governance" '"required_check": "agent-governance"' "$out"
  printf 'governance:\n  script:\n    - bash tools/agent-gate --stage ci\n    - bash tools/check-standards-compliance.sh\n' > "$BT8/.gitlab-ci.yml"
  bash "$BT8/tools/install-ci-adapter" --verify-wiring .gitlab-ci.yml --repo "$BT8" >/dev/null 2>&1
  report "T14 TC-10043 --verify-wiring passes valid .gitlab-ci.yml" 0 $?
  printf 'bad:\n\t- echo tab\n' > "$BT8/bad.yml"
  bash "$BT8/tools/install-ci-adapter" --verify-wiring bad.yml --repo "$BT8" >/dev/null 2>&1
  report "T14 TC-10043 --verify-wiring rejects tab-indented YAML" 2 $?
  out=$(bash "$BOOT_SRC" --print-profile-contract "$BT8" 2>&1)
  check_output "T14 TC-10044 profile contract detects proto and monorepo" '"monorepo_roots": \["packages"\]' "$out"
  bash "$BOOT_SRC" --verify-profile "$BT8" >/dev/null 2>&1
  report "T14 TC-10044 --verify-profile accepts valid code_extensions and scopes" 0 $?
  printf 'paths:\n  scripts: tools\ncode_extensions: .proto\n' > "$BT8/.agent-governance.yml"
  bash "$BOOT_SRC" --verify-profile "$BT8" >/dev/null 2>&1
  report "T14 TC-10044 --verify-profile rejects leading-dot code_extensions" 2 $?
  printf 'code_extensions: proto\n' > "$BT8/.agent-governance.yml"
  (cd "$BT8" && bash tools/agent-gate --stage pre-write --file api.proto >/dev/null 2>&1)
  report "T14 TC-10044 dynamic code_extensions flags api.proto as source code" 2 $?
  # TC-10062 (CHG-153 FU-15202): CI candidates, comment filter, profile freq sort
  mkdir -p "$BT8/.github/workflows"
  printf 'name: ci\non: push\njobs:\n  g:\n    steps: []\n' > "$BT8/.github/workflows/ci.yml"
  out=$(bash "$BT8/tools/install-ci-adapter" --detect --repo "$BT8" 2>&1)
  check_output "T14 TC-10062 multi-CI detect emits candidates" "candidates: gitlab,github" "$out"
  printf 'governance:\n  script:\n    # bash tools/agent-gate --stage ci\n    # bash tools/check-standards-compliance.sh\n    - echo noop\n' > "$BT8/commented.yml"
  bash "$BT8/tools/install-ci-adapter" --verify-wiring commented.yml --repo "$BT8" >/dev/null 2>&1
  report "T14 TC-10062 --verify-wiring rejects commented-out wiring" 2 $?
  _pc_dir=$(mktemp -d)
  printf 'a\n' > "$_pc_dir/f1.zzz" && printf 'b\n' > "$_pc_dir/f2.zzz" && printf 'c\n' > "$_pc_dir/f3.zzz" && printf 'd\n' > "$_pc_dir/f4.aaa"
  out=$(bash "$BOOT_SRC" --print-profile-contract "$_pc_dir" 2>&1)
  check_output "T14 TC-10062 profile contract sorts extensions by frequency" '"detected_extensions": "zzz,aaa"' "$out"
  rm -rf "$_pc_dir"
  # TC-10066 (ITEM-43): single-source wrapper check & direct execution (isolated fixture so git worktrees without gitignored mirrors also verify sync + --check + wrapped ROOT resolution)
  if [[ -f "$ROOT/scripts/dev/sync-local-wrappers.sh" ]]; then
    _sw_tmp=$(mktemp -d)
    mkdir -p "$_sw_tmp/scripts/dev" "$_sw_tmp/.githooks" "$_sw_tmp/resources/templates" "$_sw_tmp/docs/changes/CHG-T"
    cp "$ROOT/resources/DEVELOPMENT_STANDARDS.md" "$_sw_tmp/resources/"
    cp "$ROOT/resources/templates/"*.sh "$ROOT/resources/templates/pre-commit" "$_sw_tmp/resources/templates/" 2>/dev/null || true
    cp "$ROOT/scripts/dev/sync-local-wrappers.sh" "$_sw_tmp/scripts/dev/sync-local-wrappers.sh"
    bash "$_sw_tmp/scripts/dev/sync-local-wrappers.sh" >/dev/null 2>&1 && bash "$_sw_tmp/scripts/dev/sync-local-wrappers.sh" --check >/dev/null 2>&1
    _sw_rc=$?
    bash "$_sw_tmp/scripts/dev/sync-local-wrappers.sh" --badopt >/dev/null 2>&1; _sw_bad_rc=$?
    printf '{"change_id":"CHG-T","risk_level":"L1"}\n' > "$_sw_tmp/docs/changes/CHG-T/00-governance.json"
    _sw_sp_out=$(cd "$_sw_tmp" && git init -q && bash "$_sw_tmp/scripts/stamp-provenance.sh" --print CHG-T 2>/dev/null || true)
    ( cd "$_sw_tmp" && bash "$_sw_tmp/scripts/session-gate.sh" check >/dev/null 2>&1 || true )
    _sw_root_ok=0
    [[ -d "$_sw_tmp/.agent-state" && ! -d "$_sw_tmp/resources/.agent-state" ]] && _sw_root_ok=1
    if [[ -f "$ROOT/.githooks/pre-commit" ]]; then
      bash "$ROOT/scripts/dev/sync-local-wrappers.sh" --check >/dev/null 2>&1 || _sw_rc=$?
    fi
    rm -rf "$_sw_tmp"
    report "T14 TC-10066 sync-local-wrappers --check passes" 0 "$_sw_rc"
    report "T14 TC-10066 sync-local-wrappers rejects unknown option" 2 "$_sw_bad_rc"
    report "T14 TC-10066 wrapped stamp-provenance resolves skill_version (not unknown)" 1 "$(grep -qE '^skill_version: [0-9]+\.[0-9]+\.[0-9]+' <<< "$_sw_sp_out" && echo 1 || echo 0)"
    report "T14 TC-10066 wrapped session-gate resolves repo root (not resources/)" 1 "$_sw_root_ok"
  else
    report "T14 TC-10066 sync-local-wrappers --check (skip)" 0 0
  fi
  # TC-10067 (ITEM-44): lib-json.sh shared helpers preserve quoted-only json_field & escape
  if [[ -f "$ROOT/resources/templates/lib-json.sh" ]]; then
    _j_null=$(bash -c '. "$1"; json_field '\''{"bug_ref": null, "risk_level": "L2"}'\'' bug_ref' _ "$ROOT/resources/templates/lib-json.sh")
    _j_str=$(bash -c '. "$1"; json_field '\''{"bug_ref": null, "risk_level": "L2"}'\'' risk_level' _ "$ROOT/resources/templates/lib-json.sh")
    _j_esc=$(bash -c '. "$1"; json_escape "a\"b\\c"' _ "$ROOT/resources/templates/lib-json.sh")
    report "T14 TC-10067 lib-json json_field returns empty on null" "" "$_j_null"
    report "T14 TC-10067 lib-json json_field extracts string" "L2" "$_j_str"
    report "T14 TC-10067 lib-json json_escape escapes quotes and backslashes" 'a\"b\\c' "$_j_esc"
  fi
  # TC-10068 (ITEM-41): governance-smoke.sh passes on bootstrapped repo and fails on broken repo
  if [[ -f "$BT8/tests/governance-smoke.sh" ]]; then
    out=$(bash "$BT8/tests/governance-smoke.sh" --repo "$BT8" --skip-docs --json 2>&1); rc=$?
    report "T14 TC-10068 governance-smoke passes on bootstrapped repo" 0 "$rc"
    check_output "T14 TC-10068 governance-smoke emits JSON summary" '"failed":0' "$out"
    rm -f "$BT8/tools/lib-gate-cold.sh"
    bash "$BT8/tests/governance-smoke.sh" --repo "$BT8" --skip-docs --json >/dev/null 2>&1
    report "T14 TC-10068 governance-smoke fails when lib-gate-cold missing" 1 $?
  fi
  rm -rf "$BT8"
  # TC-10073 (ITEM-50): SHA256SUMS + release.sh checksums --check + install.sh --verify-sha256
  if [[ -f "$ROOT/SHA256SUMS" && -f "$ROOT/scripts/install.sh" ]]; then
    bash "$ROOT/scripts/release.sh" checksums --check >/dev/null 2>&1
    report "T14 TC-10073 release.sh checksums --check passes" 0 $?
    _sh_src=$(mktemp -d); _sh_tgt=$(mktemp -d); _sh_tgt2=$(mktemp -d)
    ( cd "$_sh_tgt" && git init -q && git config user.email t@t && git config user.name t )
    ( cd "$_sh_tgt2" && git init -q && git config user.email t@t && git config user.name t )
    cp -R "$ROOT/resources" "$ROOT/scripts" "$ROOT/tests" "$ROOT/SKILL.md" "$ROOT/SHA256SUMS" "$_sh_src/"
    out=$(bash "$_sh_src/scripts/install.sh" --from "$_sh_src" --verify-sha256 --layer core "$_sh_tgt" 2>&1); rc=$?
    report "T14 TC-10073 install.sh --verify-sha256 passes on clean checkout" 0 "$rc"
    echo "# tampered" >> "$_sh_src/scripts/bootstrap.sh"
    out=$(bash "$_sh_src/scripts/install.sh" --from "$_sh_src" --verify-sha256 --layer core "$_sh_tgt2" 2>&1); rc=$?
    report "T14 TC-10073 install.sh --verify-sha256 rejects tampered file" 2 "$rc"
    check_output "T14 TC-10073 tamper error names mismatch" "mismatch" "$out"
    rm -rf "$_sh_src" "$_sh_tgt" "$_sh_tgt2"
  else
    report "T14 TC-10073 SHA256SUMS verify (skip)" 0 0
  fi
  # TC-10074 (ITEM-51): scripts/friction-report.sh 5-col + 2-col legacy + missing file
  if [[ -x "$ROOT/scripts/friction-report.sh" ]]; then
    _fr_tmp=$(mktemp -d)
    out=$(bash "$ROOT/scripts/friction-report.sh" --file "$_fr_tmp/missing.tsv" --json 2>&1); rc=$?
    report "T14 TC-10074 friction-report handles missing file with rc0" 0 "$rc"
    check_output "T14 TC-10074 missing file reports total 0" '"total":0' "$out"
    printf 'GATE-E164\t2026-11-25T00:00:00Z\tCHG-1\tDIE\tsecret hit\nGATE-E83\t2026-11-25T00:00:01Z\tCHG-1\tADVISORY\tdowngraded\nGATE-E164\t2026-11-25T00:00:02Z\n' > "$_fr_tmp/fr.tsv"
    out=$(bash "$ROOT/scripts/friction-report.sh" --file "$_fr_tmp/fr.tsv" --json 2>&1); rc=$?
    report "T14 TC-10074 friction-report parses 5-col and legacy 2-col TSV" 0 "$rc"
    check_output "T14 TC-10074 friction-report totals 3 events" '"total":3' "$out"
    check_output "T14 TC-10074 friction-report ranks GATE-E164" '"code":"GATE-E164","count":2' "$out"
    rm -rf "$_fr_tmp"
  fi
  # TC-10076 (CHG-156, REQ-1453): sync-local-wrappers manages tests/audit-docs-consistency.sh
  if [[ -f "$ROOT/scripts/dev/sync-local-wrappers.sh" ]]; then
    _sw_a=$(mktemp -d)
    mkdir -p "$_sw_a/scripts/dev" "$_sw_a/.githooks" "$_sw_a/tests" "$_sw_a/resources/templates"
    cp "$ROOT/resources/templates/"*.sh "$ROOT/resources/templates/pre-commit" "$_sw_a/resources/templates/" 2>/dev/null || true
    cp "$ROOT/scripts/dev/sync-local-wrappers.sh" "$_sw_a/scripts/dev/sync-local-wrappers.sh"
    bash "$_sw_a/scripts/dev/sync-local-wrappers.sh" >/dev/null 2>&1 && bash "$_sw_a/scripts/dev/sync-local-wrappers.sh" --check >/dev/null 2>&1
    _swa_rc=$?
    report "T14 TC-10076 sync-local-wrappers creates audit wrapper and passes --check" 0 "$_swa_rc"
    report "T14 TC-10076 wrapped audit-docs-consistency is 3-line exec wrapper" 1 "$([[ "$(wc -l < "$_sw_a/tests/audit-docs-consistency.sh" | tr -d ' ')" -eq 3 ]] && grep -qF '# single-source wrapper -> resources/templates/audit-docs-consistency.sh' "$_sw_a/tests/audit-docs-consistency.sh" && echo 1 || echo 0)"
    bash "$_sw_a/tests/audit-docs-consistency.sh" --since no-such-ref-xyz >/dev/null 2>&1
    report "T14 TC-10076 wrapped audit-docs-consistency forwards --since exit 2" 2 $?
    rm -rf "$_sw_a"
  fi
  # TC-10077 (CHG-156, REQ-1454): release.sh checksums & update-assertion-count enforce 0644
  if [[ -f "$ROOT/scripts/release.sh" && -f "$ROOT/scripts/dev/update-assertion-count.sh" ]]; then
    _perm_d=$(mktemp -d)
    mkdir -p "$_perm_d/scripts/dev" "$_perm_d/tests/lib" "$_perm_d/tests/suites" "$_perm_d/resources/templates" "$_perm_d/resources/methodologies" "$_perm_d/.claude-plugin"
    cp "$ROOT/SKILL.md" "$ROOT/README.md" "$ROOT/README.zh-CN.md" "$_perm_d/"
    cp "$ROOT/scripts/"*.sh "$_perm_d/scripts/" 2>/dev/null || true
    cp "$ROOT/scripts/dev/"*.sh "$_perm_d/scripts/dev/" 2>/dev/null || true
    cp "$ROOT/resources/"*.md "$_perm_d/resources/" 2>/dev/null || true
    cp "$ROOT/resources/templates/"* "$_perm_d/resources/templates/" 2>/dev/null || true
    cp "$ROOT/resources/methodologies/"*.md "$_perm_d/resources/methodologies/" 2>/dev/null || true
    cp "$ROOT/tests/"*.sh "$_perm_d/tests/" 2>/dev/null || true
    cp "$ROOT/tests/lib/"*.sh "$_perm_d/tests/lib/" 2>/dev/null || true
    cp "$ROOT/tests/suites/"*.sh "$_perm_d/tests/suites/" 2>/dev/null || true
    cp "$ROOT/tests/.suite-baseline" "$ROOT/tests/.audit-baseline" "$ROOT/tests/.audit-assertions" "$_perm_d/tests/" 2>/dev/null || true
    printf '99999\n' > "$_perm_d/tests/.suite-baseline"
    chmod 0600 "$_perm_d/README.md" "$_perm_d/README.zh-CN.md"
    bash "$_perm_d/scripts/release.sh" checksums >/dev/null 2>&1
    bash "$_perm_d/scripts/dev/update-assertion-count.sh" --from-baseline >/dev/null 2>&1
    _p_sums=$(stat -c '%a' "$_perm_d/SHA256SUMS" 2>/dev/null || stat -f '%Lp' "$_perm_d/SHA256SUMS" 2>/dev/null || echo "")
    _p_rm=$(stat -c '%a' "$_perm_d/README.md" 2>/dev/null || stat -f '%Lp' "$_perm_d/README.md" 2>/dev/null || echo "")
    _p_zh=$(stat -c '%a' "$_perm_d/README.zh-CN.md" 2>/dev/null || stat -f '%Lp' "$_perm_d/README.zh-CN.md" 2>/dev/null || echo "")
    _p_bl=$(stat -c '%a' "$_perm_d/tests/.suite-baseline" 2>/dev/null || stat -f '%Lp' "$_perm_d/tests/.suite-baseline" 2>/dev/null || echo "")
    report "T14 TC-10077 release checksums enforces 0644 on SHA256SUMS" "644" "$_p_sums"
    report "T14 TC-10077 update-assertion-count enforces 0644 on README.md" "644" "$_p_rm"
    report "T14 TC-10077 update-assertion-count enforces 0644 on README.zh-CN.md" "644" "$_p_zh"
    report "T14 TC-10077 baseline retains 0644" "644" "$_p_bl"
    rm -rf "$_perm_d"
  fi
  # TC-10078 (CHG-156, REQ-1452): CAPABILITY-COMPARISON en/zh updated with 162 GATE-E & v4.5-v4.10 evolution note
  if [[ -f "$ROOT/CAPABILITY-COMPARISON.md" && -f "$ROOT/能力对比分析.md" ]]; then
    _cc_en=0; _cc_zh=0
    grep -qF '162 `GATE-E`' "$ROOT/CAPABILITY-COMPARISON.md" && grep -qF 'Evolution Note (v4.5–v4.14)' "$ROOT/CAPABILITY-COMPARISON.md" && _cc_en=1
    grep -qF '162 个 `GATE-E`' "$ROOT/能力对比分析.md" && grep -qF '演进说明（v4.5–v4.14）' "$ROOT/能力对比分析.md" && _cc_zh=1
    report "T14 TC-10078 CAPABILITY-COMPARISON.md carries v4.10 snapshot and evolution note" 1 "$_cc_en"
    report "T14 TC-10078 能力对比分析.md carries v4.10 snapshot and evolution note" 1 "$_cc_zh"
  fi
  # TC-10079 (CHG-157, REQ-1455): .gitattributes enforces LF on scripts and hooks
  if [[ -f "$ROOT/.gitattributes" ]]; then
    _ga_ok=0
    grep -qF '*.sh text eol=lf' "$ROOT/.gitattributes" && grep -qF '.githooks/* text eol=lf' "$ROOT/.gitattributes" && grep -qF 'resources/templates/*.sh text eol=lf' "$ROOT/.gitattributes" && _ga_ok=1
    report "T14 TC-10079 .gitattributes enforces LF on scripts and hooks" 1 "$_ga_ok"
  fi
  # TC-10080 (CHG-157, REQ-1456): lib-json exports MSYS protection & has_real_python3 rejects Store stub
  if [[ -f "$ROOT/resources/templates/lib-json.sh" ]]; then
    _msys_out=$(AGENT_GUARD_FORCE_OS=MINGW64_NT-10.0 bash -c '. "$1"; printf "%s:%s\n" "${MSYS_NO_PATHCONV:-}" "${MSYS2_ARG_CONV_EXCL:-}"' _ "$ROOT/resources/templates/lib-json.sh")
    report "T14 TC-10080 lib-json exports MSYS pathconv vars on MINGW" "1:*" "$_msys_out"
    _stub_d=$(mktemp -d)
    printf '#!/usr/bin/env bash\nexit 9009\n' > "$_stub_d/python3" && chmod +x "$_stub_d/python3"
    PATH="$_stub_d:/usr/bin:/bin" bash -c '. "$1"; has_real_python3' _ "$ROOT/resources/templates/lib-json.sh" >/dev/null 2>&1
    _stub_rc=$?
    report "T14 TC-10080 has_real_python3 rejects fake python3 Store stub" 1 "$([[ "$_stub_rc" -ne 0 ]] && echo 1 || echo 0)"
    rm -rf "$_stub_d"
  fi
  # TC-10081 (CHG-157, REQ-1457): install.sh --as-skill falls back to safe copy mode on Windows
  if [[ -f "$ROOT/scripts/install.sh" ]]; then
    _w_src=$(mktemp -d); _w_dst_root=$(mktemp -d)
    cp -R "$ROOT/SKILL.md" "$ROOT/resources" "$ROOT/scripts" "$ROOT/.claude-plugin" "$_w_src/"
    [[ -f "$ROOT/SHA256SUMS" ]] && cp "$ROOT/SHA256SUMS" "$_w_src/"
    mkdir -p "$_w_src/.git" && touch "$_w_src/.git/HEAD"
    _w_out=$(AGENT_GUARD_FORCE_OS=MINGW64_NT-10.0 bash "$ROOT/scripts/install.sh" --from "$_w_src" --as-skill "$_w_dst_root/my-skill" 2>&1); _w_rc=$?
    report "T14 TC-10081 --as-skill Windows copy mode exits 0" 0 "$_w_rc"
    report "T14 TC-10081 --as-skill creates real copy dir (not symlink) with marker" 1 "$([[ ! -L "$_w_dst_root/my-skill" && -f "$_w_dst_root/my-skill/SKILL.md" && -f "$_w_dst_root/my-skill/.dev-standards-skill-copy" && ! -d "$_w_dst_root/my-skill/.git" ]] && echo 1 || echo 0)"
    check_output "T14 TC-10081 --as-skill logs Windows copy fallback" "symlink skipped" "$_w_out"
    AGENT_GUARD_FORCE_OS=MINGW64_NT-10.0 bash "$ROOT/scripts/install.sh" --from "$_w_src" --as-skill "$_w_dst_root/my-skill" >/dev/null 2>&1
    report "T14 TC-10081 --as-skill copy mode refuses overwrite without --force" 2 $?
    AGENT_GUARD_FORCE_OS=MINGW64_NT-10.0 bash "$ROOT/scripts/install.sh" --from "$_w_src" --as-skill "$_w_dst_root/my-skill" --force >/dev/null 2>&1
    report "T14 TC-10081 --as-skill copy mode refreshes with --force" 0 $?
    rm -rf "$_w_src" "$_w_dst_root"
  fi
  # TC-10082 (CHG-157, REQ-1458): install-hook-adapter emits windows_note & cursor falls back to json_sanity_check
  if [[ -f "$ROOT/resources/templates/install-hook-adapter.sh" ]]; then
    _ha_c=$(bash "$ROOT/resources/templates/install-hook-adapter.sh" --print-contract 2>&1)
    _ha_g=$(bash "$ROOT/resources/templates/install-hook-adapter.sh" --print-global-contract 2>&1)
    check_output "T14 TC-10082 --print-contract includes windows_note" '"windows_note"' "$_ha_c"
    check_output "T14 TC-10082 --print-global-contract warns against System32" 'System32' "$_ha_g"
    _ha_tmp=$(mktemp -d)
    mkdir -p "$_ha_tmp/scripts" "$_ha_tmp/.stub"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$_ha_tmp/scripts/agent-gate" && chmod +x "$_ha_tmp/scripts/agent-gate"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$_ha_tmp/scripts/session-gate.sh" && chmod +x "$_ha_tmp/scripts/session-gate.sh"
    printf '#!/usr/bin/env bash\nexit 9009\n' > "$_ha_tmp/.stub/python3" && chmod +x "$_ha_tmp/.stub/python3"
    cp "$ROOT/resources/templates/install-hook-adapter.sh" "$_ha_tmp/scripts/install-hook-adapter.sh"
    ( cd "$_ha_tmp" && AGENT_GUARD_FORCE_OS=MINGW64_NT-10.0 PATH="$_ha_tmp/.stub:/usr/bin:/bin" bash scripts/install-hook-adapter.sh --client cursor >/dev/null 2>&1 )
    report "T14 TC-10082 cursor config succeeds via json_sanity_check under fake python3 stub" 0 $?
    report "T14 TC-10082 cursor Windows command avoids bare System32 bash" 1 "$(grep -qF 'MSYS_NO_PATHCONV=1' "$_ha_tmp/.cursor/hooks.json" && echo 1 || echo 0)"
    rm -rf "$_ha_tmp"
    # FU-1601 (CHG-160): execute the real resolve_hook_bash with /usr/bin/bash masked, so the PATH scan itself is
    # exercised: a System32 bash.exe must be skipped and the next real bash returned.
    _hb_d=$(mktemp -d)
    mkdir -p "$_hb_d/Windows/System32" "$_hb_d/good"
    printf '#!/bin/sh\nexit 0\n' > "$_hb_d/Windows/System32/bash.exe"; chmod +x "$_hb_d/Windows/System32/bash.exe"
    printf '#!/bin/sh\nexit 0\n' > "$_hb_d/good/bash"; chmod +x "$_hb_d/good/bash"
    _hb_src=$(sed -n '/^is_windows_shell() {/,/^}/p;/^resolve_hook_bash() {/,/^}/p' "$ROOT/resources/templates/install-hook-adapter.sh" | sed 's#/usr/bin/bash#/nonexistent-masked/bash#')
    _hb_out=$(AGENT_GUARD_FORCE_OS=MINGW64_NT-10.0 PATH="$_hb_d/Windows/System32:$_hb_d/good:/usr/bin:/bin" "${BASH:-/bin/bash}" -c "$_hb_src; resolve_hook_bash" 2>/dev/null)
    report "T14 TC-10082 resolve_hook_bash skips a System32 bash.exe and returns the next real bash" "$_hb_d/good/bash" "$_hb_out"
    rm -rf "$_hb_d"
  fi
  # TC-10083 (CHG-157, REQ-1459): ci.yml carries windows-smoke & READMEs carry Windows matrix
  if [[ -f "$ROOT/.github/workflows/ci.yml" ]]; then
    _ci_w=0
    grep -qF 'windows-smoke:' "$ROOT/.github/workflows/ci.yml" && grep -qF 'windows-latest' "$ROOT/.github/workflows/ci.yml" && grep -qF 'MSYS_NO_PATHCONV' "$ROOT/.github/workflows/ci.yml" && _ci_w=1
    report "T14 TC-10083 ci.yml carries windows-smoke job" 1 "$_ci_w"
    report "T14 TC-10083 READMEs carry Windows support matrix" 2 "$(( $(grep -cF '### Windows Support Matrix' "$ROOT/README.md" || true) + $(grep -cF '### Windows 支持矩阵' "$ROOT/README.zh-CN.md" || true) ))"
  fi
else
  echo "SKIP T14b: bootstrap.sh 为 Skill 仓库安装器（不随 --guard 分发）——跳过安装器路径用例"
fi

}

section_T15() {
# ------------------------------------------------ T15 版本自查 / 自更新 / 自进化契约（v3.16.0）
# Skill 仓库专属（bootstrap.sh 不随 --guard 分发）。
# 覆盖三件事：D3 三处版本比对（--check，只读、漂移即 exit 1）、D4 升级保留显式
# 层选择、D5 + 自进化契约（规范升级日志归属 + 派生资产保护）。派生标记必须只从
# frontmatter 解析——正文示例代码块里的 `derived_from:` 不得被当作真实声明。
if [[ -f "$BOOT_SRC" ]]; then

  # --- D3：--check 三处版本比对（只读，漂移即 exit 1，可入 CI）---
  CT=$(mktemp -d)
  out=$(bash "$BOOT_SRC" --check "$CT" 2>&1); rc=$?
  report "T15 --check exits 1 when the target is not installed (D3)" 1 "$rc"
  check_output "T15 --check names the missing install" "not installed" "$out"
  bash "$BOOT_SRC" --all "$CT" >/dev/null 2>&1
  out=$(bash "$BOOT_SRC" --check "$CT" 2>&1); rc=$?
  report "T15 --check exits 0 on an up-to-date target" 0 "$rc"
  check_output "T15 --check reports in-sync" "check: in sync" "$out"
  perl -pi -e 's/规范版本：v[0-9.]+/规范版本：v3.0.0/' "$CT/docs/DEVELOPMENT_STANDARDS.md"
  out=$(bash "$BOOT_SRC" --check "$CT" 2>&1); rc=$?
  report "T15 --check exits 1 on an older target" 1 "$rc"
  check_output "T15 --check says UPGRADE AVAILABLE" "UPGRADE AVAILABLE" "$out"
  # 只读性：--check 不得改动任何文件（比较全部文件的内容指纹）
  fingerprint() { find "$1" -type f -exec cksum {} + 2>/dev/null | sort | cksum; }
  before=$(fingerprint "$CT")
  bash "$BOOT_SRC" --check "$CT" >/dev/null 2>&1 || true
  after=$(fingerprint "$CT")
  report "T15 --check writes nothing (read-only)" "$before" "$after"
  rm -rf "$CT"

  # --- 自进化契约：派生标记只认 frontmatter ---
  SKROOT=$(mktemp -d)
  mkdir -p "$SKROOT/dev-standards-bootstrap/scripts" "$SKROOT/derived-x" "$SKROOT/plain-x"
  cp "$BOOT_SRC" "$SKROOT/dev-standards-bootstrap/scripts/bootstrap.sh"
  # 整个 resources/ 必须一起复制：--derived-report 只需要规范正文取携带版本，
  # 但同一节后面的"向非派生目录安装仍应成功"要真的跑一次安装，缺 templates/ 会
  # 触发 MISSING SOURCE（fail-closed 生效，属夹具不全而非被测行为错误）。
  cp -R "$ROOT/resources" "$SKROOT/dev-standards-bootstrap/resources"
  # 派生方：frontmatter 里声明
  printf -- '---\nname: derived-x\ndescription: x\nagent_created: true\nderived_from: dev-standards-bootstrap\nderived_at: 2026-09-01\n---\n\n# derived-x\n' > "$SKROOT/derived-x/SKILL.md"
  # 非派生：正文代码块里出现同样字样，不得被当作声明
  printf -- '---\nname: plain-x\ndescription: y\n---\n\n# plain-x\n\n```yaml\nderived_from: dev-standards-bootstrap\n```\n' > "$SKROOT/plain-x/SKILL.md"
  BOOT_X="$SKROOT/dev-standards-bootstrap/scripts/bootstrap.sh"
  out=$(bash "$BOOT_X" --derived-report 2>&1)
  check_output "T15 --derived-report lists the declared derived skill" "derived-x" "$out"
  listed_src=$(printf '%s\n' "$out" | grep -cE '^derived +[^ ]*/dev-standards-bootstrap$' || true)
  report "T15 --derived-report does not report the source skill itself" 0 "$listed_src"
  listed_plain=$(printf '%s\n' "$out" | grep -c 'plain-x' || true)
  report "T15 --derived-report ignores body-only derived_from mentions" 0 "$listed_plain"
  listed_date=$(printf '%s\n' "$out" | grep -c 'derived_at=2026-09-01' || true)
  report "T15 --derived-report surfaces derived_at" 1 "$listed_date"

  # --- 派生写入守卫：拒绝 + --force 不越过 + 不误伤非派生目录 ---
  bash "$BOOT_X" --all "$SKROOT/derived-x" >/dev/null 2>&1
  report "T15 installer refuses to write into a derived skill" 2 $?
  bash "$BOOT_X" --all --force "$SKROOT/derived-x" >/dev/null 2>&1
  report "T15 --force does not override the derived guard" 2 $?
  [[ ! -e "$SKROOT/derived-x/AGENTS.md" ]]
  report "T15 the derived skill directory was left untouched" 0 $?
  bash "$BOOT_X" --core "$SKROOT/plain-x" >/dev/null 2>&1
  report "T15 install into a non-derived directory still works" 0 $?
  rm -rf "$SKROOT"

  # --- CHG-160 FU-1601 (TC-1484a): bootstrap --all ships the 4 scripts/-sourced files, never scripts/dev or archive/ ---
  _d1=$(mktemp -d)
  ( cd "$_d1" && git init -q && git config user.email t@t && git config user.name t )
  bash "$BOOT_SRC" --all "$_d1" >/dev/null 2>&1
  report "T15 TC-1484a bootstrap --all exits 0 on a fresh repo" 0 $?
  _d1_n=0
  for _f in lib-suite-tree-fingerprint.sh lib-suite-lock.sh shard-sum.sh evidence-round.sh; do
    [[ -f "$_d1/scripts/$_f" ]] && _d1_n=$(( _d1_n + 1 ))
  done
  report "T15 TC-1484a bootstrap --all ships the 4 scripts/-sourced files" 4 "$_d1_n"
  report "T15 TC-1484a bootstrap --all does not ship scripts/dev" 0 "$([[ -e "$_d1/scripts/dev" ]] && echo 1 || echo 0)"
  report "T15 TC-1484a bootstrap --all does not ship archive/" 0 "$([[ -e "$_d1/archive" ]] && echo 1 || echo 0)"
  # CHG-160 FU-1606 (TC-1472a): on the real installed repo the smoke passes, and fails once lib-gate-staged is gone
  bash "$_d1/tests/governance-smoke.sh" --repo "$_d1" --skip-docs --json >/dev/null 2>&1
  report "T15 TC-1472a governance-smoke passes on a bootstrap --all repo" 0 $?
  rm -f "$_d1/scripts/lib-gate-staged.sh"
  _d1_out=$(bash "$_d1/tests/governance-smoke.sh" --repo "$_d1" --skip-docs 2>&1); _d1_rc=$?
  report "T15 TC-1472a governance-smoke fails when lib-gate-staged is missing" 1 "$_d1_rc"
  check_output "T15 TC-1472a the failure names lib-gate-staged" "FAIL governance-smoke: scripts/lib-gate-staged.sh present and parses" "$_d1_out"
  rm -rf "$_d1"

  # --- CHG-160 FU-1601 (TC-1483b): divergence_guard degrades when archive/ is missing, and honors it when present ---
  _dg_fn=$(sed -n '/^divergence_guard() {/,/^}/p' "$BOOT_SRC")
  _dg=$(mktemp -d)
  mkdir -p "$_dg/skill"
  printf '| v1.0.0 | a |\n' > "$_dg/src.md"
  printf '| v1.0.0 | a |\n| v0.9.0 | old |\n' > "$_dg/dest.md"
  _dg_rc=0; _dg_out=$( SKILL_ROOT="$_dg/skill"; eval "$_dg_fn"; divergence_guard "$_dg/src.md" "$_dg/dest.md" ) || _dg_rc=$?
  report "T15 TC-1483b divergence_guard without archive/ still reports the extra row (rc 0)" 0 "$_dg_rc"
  check_output "T15 TC-1483b divergence_guard without archive/ names the extra version" "v0.9.0" "$_dg_out"
  mkdir -p "$_dg/skill/archive"
  printf '| v0.9.0 | old |\n' > "$_dg/skill/archive/STANDARDS_CHANGELOG_ARCHIVE.md"
  _dg_rc=0; ( SKILL_ROOT="$_dg/skill"; eval "$_dg_fn"; divergence_guard "$_dg/src.md" "$_dg/dest.md" ) >/dev/null 2>&1 || _dg_rc=$?
  report "T15 TC-1483b divergence_guard with archive/ treats the archived row as known (rc 1)" 1 "$_dg_rc"
  rm -rf "$_dg"

  # Prewarm a fresh bootstrap --all repo once (live empty-repo install is already covered by CT and _d1 above)
  # so D4/D5/D6/D5L/DR/DR3 clone a clean pre-commit/post-commit snapshot instead of re-running bootstrap --all 6x.
  _t15_uncommitted=$(mktemp -d)
  ( cd "$_t15_uncommitted" && git init -q && git config user.email t@t && git config user.name t )
  bash "$BOOT_SRC" --all "$_t15_uncommitted" >/dev/null 2>&1
  _t15_committed=$(mktemp -d)
  cp -pR "$_t15_uncommitted/." "$_t15_committed/"
  ( cd "$_t15_committed" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )

  # --- D4：--upgrade 保留显式层选择（此前会静默扩为全量 5 层）---
  D4=$(mktemp -d)
  cp -pR "$_t15_committed/." "$D4/"
  out=$(bash "$BOOT_SRC" --core --upgrade "$D4" 2>&1)
  check_output "T15 --core --upgrade keeps the explicit layer selection (D4)" "applying layers \[core\]" "$out"
  out=$(bash "$BOOT_SRC" --upgrade "$D4" 2>&1)
  check_output "T15 a bare --upgrade still expands to all layers (D4)" "applying layers \[core,claude,ci,guard,pipeline\]" "$out"
  rm -rf "$D4"

  # --- D5：规范升级日志归 Skill 所有——本地追加行必须被检测（拒绝而非静默覆盖）---
  D5=$(mktemp -d)
  cp -pR "$_t15_uncommitted/." "$D5/"
  printf '| v9.9.9-local | 2026-09-15 | 本仓自定义条目 | 无 |\n' >> "$D5/docs/STANDARDS_CHANGELOG.md"
  # v3.17.0：全新安装后的第一次 commit 不得被门禁判为"源码变更"而拦下。
  # 踩过的坑：新增治理脚本 stamp-provenance.sh 未同步进 agent-gate 的治理工具白名单，
  # 它以 .sh 结尾 → 被判为产品代码 → 新仓库装完治理包**第一次 commit 即死锁**；
  # 而下方 D5 用例的断言只看 --upgrade 的退出码与文案，commit 静默失败后
  # 报错来自"目标仓有未提交改动"这**另一条守卫**，表现为文案不匹配——症状与根因相距很远。
  # 故此处显式断言首次 commit 成功，把根因钉在最近的位置。
  ( cd "$D5" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  report "T15 a fresh --all install commits cleanly (no governance deadlock)" 0 $?
  out=$(bash "$BOOT_SRC" --upgrade "$D5" 2>&1); rc=$?
  report "T15 upgrade refuses local rows in the skill-owned changelog (D5)" 2 "$rc"
  check_output "T15 the refusal names the local rows" "local rows this skill does not carry" "$out"
  check_output "T15 TC-1615b refusal with archive/ present still suggests --force" "pass --force to overwrite" "$out"
  grep -q 'v9.9.9-local' "$D5/docs/STANDARDS_CHANGELOG.md"
  report "T15 local changelog rows survive the refusal" 0 $?
  rm -rf "$D5"

  # --- CHG-161 (REQ-1615, TC-1615a): skill 副本缺 archive/ 时，拒绝文案指向重装而不是 --force ---
  D6=$(mktemp -d); D6S=$(mktemp -d)
  cp -pR "$_t15_uncommitted/." "$D6/"
  _c161_hist=$(grep -m1 -oE '^\| v[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/archive/STANDARDS_CHANGELOG_ARCHIVE.md")
  printf '%s | 2020-01-01 | 历史行 | 无 |\n' "$_c161_hist" >> "$D6/docs/STANDARDS_CHANGELOG.md"
  ( cd "$D6" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  cp -R "$ROOT/scripts" "$ROOT/resources" "$ROOT/SKILL.md" "$D6S/"
  out=$(bash "$D6S/scripts/bootstrap.sh" --upgrade "$D6" 2>&1); rc=$?
  report "T15 TC-1615a archive-less skill copy refuses a history-row divergence (rc2)" 2 "$rc"
  check_output "T15 TC-1615a refusal points at reinstall" "重装" "$out"
  report "T15 TC-1615a refusal does not suggest --force" 0 "$(printf '%s' "$out" | grep -c -- '--force')"
  rm -rf "$D6" "$D6S"

  # D5-archive regression (CHG-154 ITEM-40): archived skill rows (v2.9.0..v4.2.0) in an older target repo must NOT block --upgrade
  D5L=$(mktemp -d)
  cp -pR "$_t15_uncommitted/." "$D5L/"
  printf '| v4.2.0 | 2026-10-12 | archived legacy skill row | 无 |\n' >> "$D5L/docs/STANDARDS_CHANGELOG.md"
  ( cd "$D5L" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  out=$(bash "$BOOT_SRC" --upgrade "$D5L" 2>&1); rc=$?
  report "T15 upgrade allows archived skill rows in legacy changelog (ITEM-40)" 0 "$rc"
  rm -rf "$D5L"

  # TC-10072 (ITEM-49): bootstrap --upgrade --dry-run prints plan and writes ZERO bytes
  DR=$(mktemp -d)
  cp -pR "$_t15_uncommitted/." "$DR/"
  perl -pi -e 's/规范版本：v[0-9.]+/规范版本：v3.0.0/' "$DR/docs/DEVELOPMENT_STANDARDS.md"
  ( cd "$DR" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  dr_before=$(fingerprint "$DR")
  out=$(bash "$BOOT_SRC" --upgrade --dry-run "$DR" 2>&1); rc=$?
  dr_after=$(fingerprint "$DR")
  report "T15 TC-10072 --upgrade --dry-run exits 0" 0 "$rc"
  check_output "T15 TC-10072 --upgrade --dry-run prints dry-run plan" "\[dry-run\]" "$out"
  report "T15 TC-10072 --upgrade --dry-run makes zero filesystem modifications" "$dr_before" "$dr_after"
  rm -rf "$DR"
  DR2=$(mktemp -d)
  ( cd "$DR2" && git init -q && git config user.email t@t && git config user.name t )
  dr2_before=$(fingerprint "$DR2")
  out=$(bash "$BOOT_SRC" --all --dry-run "$DR2" 2>&1); rc=$?
  dr2_after=$(fingerprint "$DR2")
  report "T15 TC-10072 fresh --all --dry-run exits 0 and writes nothing" 1 "$([[ "$rc" -eq 0 && "$dr2_before" == "$dr2_after" ]] && echo 1 || echo 0)"
  rm -rf "$DR2"
  DR3=$(mktemp -d)
  cp -pR "$_t15_uncommitted/." "$DR3/"
  perl -0777 -pi -e 's/^paths:\n(?:\s+.*\n)*//m' "$DR3/.agent-governance.yml"
  ( cd "$DR3" && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 )
  dr3_before=$(fingerprint "$DR3")
  out=$(bash "$BOOT_SRC" --upgrade --dry-run "$DR3" 2>&1); rc=$?
  dr3_after=$(fingerprint "$DR3")
  report "T15 TC-10072 legacy no-paths --upgrade --dry-run writes nothing" 1 "$([[ "$rc" -eq 0 && "$dr3_before" == "$dr3_after" ]] && echo 1 || echo 0)"
  rm -rf "$DR3" "$_t15_uncommitted" "$_t15_committed"

  # --- D1：非 git 克隆的 Skill 目录，--self-update 必须显式说明不可用（不得静默成功）---
  NG=$(mktemp -d)
  mkdir -p "$NG/scripts" "$NG/resources"
  cp "$BOOT_SRC" "$NG/scripts/bootstrap.sh"
  cp "$ROOT/resources/DEVELOPMENT_STANDARDS.md" "$NG/resources/" 2>/dev/null
  out=$(bash "$NG/scripts/bootstrap.sh" --self-update 2>&1); rc=$?
  report "T15 --self-update fails clearly on a non-git skill dir (D1)" 1 "$rc"
  check_output "T15 --self-update explains why it cannot compare" "not-a-git-checkout" "$out"
  rm -rf "$NG"

else
  echo "SKIP T15: bootstrap.sh 为 Skill 仓库安装器（不随 --guard 分发）——跳过版本自查/自进化用例"
fi

}

section_T17() {
# ------------------------------------------------ T17 溯源脚本本体（v3.17.0）
# T16 验的是**门禁的校验逻辑**（内联块，与布局无关）；T17 验的是**脚本本体的产出**——
# 真值取自环境、写入幂等、隐私开关、--check、以及"真脚本产出能过真门禁"的端到端闭环。
# 脚本是 --guard 层文件：目标仓未装 guard 层时不存在 → SKIP（同 T15 的布局自适应）。
if [[ -f "$STAMP_SRC" ]]; then
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  seed_artifacts CHG-700 L1 claude/s-1
  commit_all "docs: CHG-700 artifacts"

  # ① 编码记录缺失：给出可执行的下一步，且**不**自动建空骨架
  #    （门禁对 04.5 只查"存在且非空"，自动建壳等于放行空交付）
  out=$(scripts/stamp-provenance.sh CHG-700 2>&1); rc=$?
  report "T17 stamper rejects a missing coding record" 2 "$rc"
  check_output "T17 stamper states the actionable next step" "write the coding record first" "$out"

  # ①b 点号 id 拒盖（v3.62.0，REQ-1023/FU-023 no-dot 形状）：exit 非零 + 明确报文，不写产物
  out=$(scripts/stamp-provenance.sh CHG.700 2>&1); rc=$?
  report "T17 stamper rejects a dotted change id" 2 "$rc"
  check_output "T17 dotted-change-id refusal states the no-dot rule" "dots not allowed" "$out"
  out=$(scripts/stamp-provenance.sh --bug BUG.040 2>&1); rc=$?
  report "T17 stamper rejects a dotted defect id" 2 "$rc"
  check_output "T17 dotted-defect-id refusal states the no-dot rule" "dots not allowed" "$out"
  report "T17 dotted-id rejection writes no default target" 0 "$(test ! -e docs/changes/CHG-700/04.5-coding-record.md; echo $?)"

  # ② 正常写入：块插在首个 H1 之后，真值全部取自运行环境
  printf '# CHG-700 编码记录\n\n## 改动文件清单\n' > docs/changes/CHG-700/04.5-coding-record.md
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  report "T17 stamper writes the provenance block" 0 $?
  blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md)
  check_output "T17 stamped block names the script as producer" "^generated_by: stamp-provenance[.]sh$" "$blk"
  check_output "T17 stamped block carries an ISO UTC timestamp" "^generated_at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$blk"
  check_output "T17 stamped block reads the author from git config" "^author: test$" "$blk"
  check_output "T17 stamped block records the commit hash" "^commit: [0-9a-f]{7,}$" "$blk"
  check_output "T17 stamped block records host and platform" "^platform: .+ .+$" "$blk"

  # ③ 幂等：重复运行**整块替换**而非叠加（叠加会让门禁按首块校验而误判）
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  report "T17 stamper is idempotent (one block after re-run)" 1 "$(grep -c '^<!-- provenance$' docs/changes/CHG-700/04.5-coding-record.md)"

  # ④ --check 接受自己的产出
  scripts/stamp-provenance.sh --check docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  report "T17 --check accepts the stamper's own output" 0 $?

  # ③b 同 HEAD 连续两次盖章：除 generated_at 墙钟外零 diff（v3.62.0，REQ-1024/TC-1079，
  #     last-touch commit 语义下天然成立；墙钟行归一后整块比对）
  cp docs/changes/CHG-700/04.5-coding-record.md .stamp-snapshot
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  sed -n '/^<!-- provenance$/,/^-->$/p' .stamp-snapshot | grep -v '^generated_at: ' > .stamp-a
  sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md | grep -v '^generated_at: ' > .stamp-b
  report "T17 re-stamp at the same HEAD is zero-diff (modulo generated_at)" 0 "$(diff .stamp-a .stamp-b >/dev/null 2>&1; echo $?)"
  rm -f .stamp-snapshot .stamp-a .stamp-b

  # ③c last-touch commit 随文件演进更新（REQ-1024 方案 A）：入库重盖 → commit=该提交；
  #     再改再提交再重盖 → commit=新提交（--check 的 hash 比对同口径）。
  git add docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  git commit -qm "docs: CHG-700 coding record" >/dev/null 2>&1
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk_commit=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md | sed -nE 's/^commit:[[:space:]]*//p')
  report "T17 commit field == the file's last-touch commit" 1 "$(git log -1 --format=%h -- docs/changes/CHG-700/04.5-coding-record.md | grep -cF "$blk_commit")"
  printf '\n## WHY 决策\n\n追加内容驱动 last-touch 更新。\n' >> docs/changes/CHG-700/04.5-coding-record.md
  git add docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  git commit -qm "docs: CHG-700 coding record update" >/dev/null 2>&1
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk_commit2=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md | sed -nE 's/^commit:[[:space:]]*//p')
  report "T17 commit field == the evolved last-touch commit" 1 "$(git log -1 --format=%h -- docs/changes/CHG-700/04.5-coding-record.md | grep -cF "$blk_commit2")"
  report "T17 commit field actually advanced between evolutions" 0 "$(test "$blk_commit" != "$blk_commit2"; echo $?)"
  scripts/stamp-provenance.sh --check docs/changes/CHG-700/04.5-coding-record.md >/dev/null 2>&1
  report "T17 --check commit consistency accepts a fresh stamp" 0 $?

  # ③c-2 时间戳幂等（v3.97.2，CHG-136/REQ-1351/TC-2352..2355）：新块与现存块剥
  #     generated_at 行后逐字节相等 → 跳过重写（墙钟不是内容；无条件重写=每次提交
  #     全目录秒级漂移、无限追尾，目标仓真实事故（2026-11-01 批次交付后 5 文件纯
  #     时间戳残留）实证）。
  #     commit 字段不剥：失配仍重写（v3.62.0 自愈保留）；全 unchanged 批 exit 0；
  #     无块/篡改照常全盖（回归守卫）。
  cp docs/changes/CHG-700/04.5-coding-record.md .t136-a
  sleep 1
  out=$(scripts/stamp-provenance.sh CHG-700 2>&1); rc=$?
  report "T17 TC-2352 timestamp-only re-stamp exits 0" 0 "$rc"
  check_output "T17 TC-2352 timestamp-only re-stamp reports unchanged" "^unchanged    docs/changes/CHG-700/04[.]5-coding-record[.]md$" "$out"
  report "T17 TC-2352 skipped rewrite leaves the file byte-identical (incl. generated_at)" 0 "$(cmp -s .t136-a docs/changes/CHG-700/04.5-coding-record.md; echo $?)"
  sed 's/^commit: .*/commit: deadbee/' docs/changes/CHG-700/04.5-coding-record.md > .t136-t1 && mv .t136-t1 docs/changes/CHG-700/04.5-coding-record.md
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk_commit3=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md | sed -nE 's/^commit:[[:space:]]*//p')
  report "T17 TC-2353 tampered commit is healed on re-stamp" 1 "$(git log -1 --format=%h -- docs/changes/CHG-700/04.5-coding-record.md | grep -cF "$blk_commit3")"
  report "T17 TC-2353 healed commit differs from the tampered value" 0 "$(test "$blk_commit3" != "deadbee"; echo $?)"
  scripts/stamp-provenance.sh --all CHG-700 >/dev/null 2>&1
  out=$(scripts/stamp-provenance.sh --all CHG-700 2>&1); rc=$?
  report "T17 TC-2354 all-unchanged --all re-run exits 0 (not nothing-stamped)" 0 "$rc"
  check_output "T17 TC-2354 all-unchanged --all reports unchanged lines" "^unchanged    " "$out"
  printf '# 无块夹具\n\n正文\n' > .t136-noblk
  out=$(scripts/stamp-provenance.sh CHG-700 .t136-noblk 2>&1)
  check_output "T17 TC-2355 blockless file is stamped" "^stamped      [.]t136-noblk$" "$out"
  sed 's/^generated_by: .*/generated_by: hand-written/' docs/changes/CHG-700/04.5-coding-record.md > .t136-t2 && mv .t136-t2 docs/changes/CHG-700/04.5-coding-record.md
  out=$(scripts/stamp-provenance.sh CHG-700 2>&1)
  check_output "T17 TC-2355 tampered producer is re-stamped" "^stamped      docs/changes/CHG-700/04[.]5-coding-record[.]md$" "$out"
  # TC-2357（评审 R1 硬项①）：无 H1 兜底族同样受不动点保护——判据对最终（兜底
  # 构造）输出执行；否则该族每次重盖刷新墙钟，追尾不根治。
  printf '## 非 H1 标题\n\n正文（无 H1 夹具）\n' > .t136-noh1
  scripts/stamp-provenance.sh CHG-700 .t136-noh1 >/dev/null 2>&1
  cp .t136-noh1 .t136-noh1-a
  sleep 1
  out=$(scripts/stamp-provenance.sh CHG-700 .t136-noh1 2>&1); rc=$?
  report "T17 TC-2357 no-H1 fallback second stamp exits 0" 0 "$rc"
  check_output "T17 TC-2357 no-H1 fallback reports unchanged" "^unchanged    [.]t136-noh1$" "$out"
  report "T17 TC-2357 no-H1 fallback skip is byte-identical" 0 "$(cmp -s .t136-noh1-a .t136-noh1; echo $?)"
  rm -f .t136-a .t136-noh1 .t136-noh1-a

  # ③d 整文件字节幂等（v3.62.1，CHG-081/REQ-1025/TC-1080）：旧 TC-1079 只比块内
  #     抽取——空行累积恰在块外，测试自遮蔽恒绿（CHG-080 教训）。整文件 diff +
  #     块尾空行恒 1 双断言。
  cp docs/changes/CHG-700/04.5-coding-record.md .t1080-a
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  cp docs/changes/CHG-700/04.5-coding-record.md .t1080-b
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  report "T17 TC-1080 whole-file byte-idempotent across re-stamps (mod generated_at)" 0 "$(diff <(sed 's/^generated_at: .*/generated_at: X/' .t1080-a) <(sed 's/^generated_at: .*/generated_at: X/' .t1080-b) >/dev/null 2>&1; echo $?)"
  report "T17 TC-1080 exactly one blank after block end" 0 "$(awk '/^<!-- provenance$/{b=1;next} b&&/^-->$/ {b=0;d=1;n=0;next} b{next} d&&/^[[:space:]]*$/{n++;next} d{exit} END{print (n==1)?0:1}' docs/changes/CHG-700/04.5-coding-record.md)"
  rm -f .t1080-a .t1080-b

  # ③e 历史脏形一次收敛（v3.62.1，REQ-1025/TC-1081）：块后 4 空行（目标仓实测
  #     index 4→worktree 8 形态）盖 1 次即达规范形，且与净文件盖章输出字节相等。
  printf '# 脏形夹具\n\n正文一行\n' > .t1081-clean
  scripts/stamp-provenance.sh CHG-700 .t1081-clean >/dev/null 2>&1
  cp .t1081-clean .t1081-expect
  awk '{print} /^-->$/ && !inj {for(i=0;i<4;i++) print ""; inj=1}' .t1081-expect > .t1081-dirty
  scripts/stamp-provenance.sh CHG-700 .t1081-dirty >/dev/null 2>&1
  report "T17 TC-1081 dirty shape (4 trailing blanks) converges in one stamp" 0 "$(diff <(sed 's/^generated_at: .*/generated_at: X/' .t1081-expect) <(sed 's/^generated_at: .*/generated_at: X/' .t1081-dirty) >/dev/null 2>&1; echo $?)"
  rm -f .t1081-clean .t1081-expect .t1081-dirty

  # ③f 栅栏感知（v3.62.2，CHG-082/REQ-1029/TC-1088）：正文代码栅栏内的成对
  #     provenance 示例标记与栅栏内 `# ` 示例标题不再被删块/插块逻辑消费
  #     （CHG-081 评审 B 项实证）。断言：示例原样保留、正文零丢失、恰一真块、
  #     幂等、--check 取真块（TC-1089）。
  printf '# 栅栏夹具\n\n```markdown\n<!-- provenance\nauthor: sample\n-->\n```\n\n```bash\n# 栅栏内假 H1 示例\n```\n\n正文行A\n正文行B\n' > .t1088-fence
  scripts/stamp-provenance.sh CHG-700 .t1088-fence >/dev/null 2>&1
  report "T17 TC-1088 fenced example markers survive stamping (sample kept)" 4 "$(grep -cE '^<!-- provenance$|^-->$' .t1088-fence)"
  report "T17 TC-1088 fenced sample field lines survive" 1 "$(grep -c '^author: sample$' .t1088-fence)"
  report "T17 TC-1088 in-fence fake H1 does not trigger a second block" 0 "$(test "$(grep -c '^<!-- provenance$' .t1088-fence)" = 2; echo $?)"
  report "T17 TC-1088 first-stamp body content survives (TC-1079 教训：幂等不覆盖首盖丢失)" 2 "$(grep -cE '^正文行[AB]$' .t1088-fence)"
  cp .t1088-fence .t1088-a
  scripts/stamp-provenance.sh CHG-700 .t1088-fence >/dev/null 2>&1
  report "T17 TC-1088 fence case is byte-idempotent (mod generated_at)" 0 "$(diff <(sed 's/^generated_at: .*/X/' .t1088-a) <(sed 's/^generated_at: .*/X/' .t1088-fence) >/dev/null 2>&1; echo $?)"
  scripts/stamp-provenance.sh --check .t1088-fence >/dev/null 2>&1
  report "T17 TC-1089 --check extracts the real block when a fenced example exists" 0 $?
  # ③f2 (评审 D1 回归): 无 H1 + 栅栏示例 → 兜底判据不可被示例 begin 标记骗过
  # （旧 grep 判据 → 假成功零块落盘）；现块落头部且示例/正文原样。
  printf '```markdown\n<!-- provenance\nauthor: sample\n-->\n```\n正文X\n' > .tf-noh1
  scripts/stamp-provenance.sh CHG-700 .tf-noh1 >/dev/null 2>&1
  report "T17 TC-1088b no-H1 file with fenced sample still gets the block at head" 1 "$(head -1 .tf-noh1 | grep -c '^<!-- provenance$')"
  report "T17 TC-1088b exactly one real block (not fooled by the sample)" 1 "$(grep -c '^generated_by: ' .tf-noh1)"
  report "T17 TC-1088b sample and body survive the head-block stamp" 2 "$(grep -cE '^(author: sample|正文X)$' .tf-noh1)"
  scripts/stamp-provenance.sh --check .tf-noh1 >/dev/null 2>&1
  report "T17 TC-1088b --check passes on the head-block with fenced sample" 0 $?
  # ③f3 (评审 D2 回归): 真块体内杂散 ``` 行不得翻转栅栏态（否则 --> 终止永不
  # 命中、吞块后正文至 EOF）；重盖后正文零丢失、块仍单。
  printf '# 极端块夹具\n\n正文行1\n正文行2\n' > .tf-stray
  scripts/stamp-provenance.sh CHG-700 .tf-stray >/dev/null 2>&1
  awk '{print} /^generated_by:/{print "```"}' .tf-stray > .tf-stray2 && mv .tf-stray2 .tf-stray
  scripts/stamp-provenance.sh CHG-700 .tf-stray >/dev/null 2>&1
  report "T17 TC-1088c stray fence inside block body does not eat the tail" 2 "$(grep -cE '^正文行[12]$' .tf-stray)"
  report "T17 TC-1088c block stays single after the stray-fence restamp" 1 "$(grep -c '^generated_by: ' .tf-stray)"
  rm -f .t1088-fence .t1088-a .tf-noh1 .tf-stray

  # ③g CRLF 归一（v3.62.2，CHG-082/REQ-1030/TC-1091）：\r 尾行致旧块不识别重复盖
  #     ——写入路径一次归一 LF；--check 读取侧容忍（不回写未盖文件）。
  printf '# CRLF 夹具\r\n\r\n内容行\r\n' > .t1091-crlf
  scripts/stamp-provenance.sh CHG-700 .t1091-crlf >/dev/null 2>&1
  report "T17 TC-1091 CRLF file normalized to LF on stamp" 0 "$(grep -c $'\r' .t1091-crlf)"
  report "T17 TC-1091 CRLF file gets exactly one block" 1 "$(grep -c '^<!-- provenance$' .t1091-crlf)"
  scripts/stamp-provenance.sh --check .t1091-crlf >/dev/null 2>&1
  report "T17 TC-1091 --check accepts the normalized CRLF file" 0 $?
  cp .t1091-crlf .t1091-a
  scripts/stamp-provenance.sh CHG-700 .t1091-crlf >/dev/null 2>&1
  report "T17 TC-1091 CRLF re-stamp is byte-idempotent" 0 "$(diff <(sed 's/^generated_at: .*/X/' .t1091-a) <(sed 's/^generated_at: .*/X/' .t1091-crlf) >/dev/null 2>&1; echo $?)"
  rm -f .t1091-a .t1091-crlf

  # ⑤ 隐私开关：yml 关掉邮箱，作者与主机保留
  printf 'provenance:\n  include_email: false\n' > .agent-governance.yml
  scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md)
  check_output "T17 privacy switch redacts the email" "^email: <redacted>$" "$blk"
  check_output "T17 privacy switch keeps the author" "^author: test$" "$blk"

  # ⑥ env 覆盖 yml（CLI > env > yml 的第二级）
  AGENT_GUARD_PROVENANCE_EMAIL=true scripts/stamp-provenance.sh CHG-700 >/dev/null 2>&1
  blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/CHG-700/04.5-coding-record.md)
  check_output "T17 env override beats the yml privacy switch" "^email: test@example[.]invalid$" "$blk"

  # ⑦ 端到端：**真脚本产出**过**真门禁**（T16 用的是内联块，此处闭合"脚本 ↔ 门禁"接口）
  #    注意 begin 必须在写 09-changelog.md **之前**：门禁把"09 已存在"读作"变更已闭合"
  #    （§2.15 规则 4，FU-015），先写 09 会让 begin 直接拒绝。
  scripts/agent-gate begin CHG-700 >/dev/null 2>&1
  echo y > src/c.js
  echo results > docs/changes/CHG-700/05-test-results.md
  printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | grep -c REQ- 01-spec.md -> 1 |\n' > docs/changes/CHG-700/09-changelog.md
append_masters docs/changes/CHG-700/09-changelog.md
  printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：无配置项。\n' > docs/changes/CHG-700/06.5-deployment-config.md
  printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | x | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-700/06-delivery-summary.md
  # TC-1089b (v3.62.2, CHG-082 REQ-1029)：门禁侧 provenance_block 栅栏感知——
  # stop 对"含栅栏示例标记的产物"取真块校验（旧 sed 区间会抽到示例段假红）。
  cat >> docs/changes/CHG-700/04-test-scripts.md <<'EOT17F'

```markdown
<!-- provenance
author: sample
-->
```
EOT17F
  scripts/stamp-provenance.sh --all CHG-700 >/dev/null 2>&1
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T17 gate accepts a real script-stamped record (end-to-end)" 0 $?
  scripts/stamp-provenance.sh --check docs/changes/CHG-700/04-test-scripts.md >/dev/null 2>&1
  report "T17 TC-1089b --check passes on a stamped doc carrying a fenced example block" 0 $?
else
  echo "SKIP T17: stamp-provenance.sh 为 --guard 层文件（未装 guard 层时不存在）"
fi

}

section_T17b() {
# ------------------------------------------------ T17b 溯源全量盖章 --all（v3.22.0）
# --all 把溯源块盖到解析后变更目录的每一个 *.md（批感知复用 resolve_dir）。
# 硬边界：00-governance.json 刻意不盖——JSON 注入 HTML 注释会破坏门禁/审计的
# 扁平 JSON 读取；幂等（整块替换）与"零成功即失败"语义必须同时成立。
if [[ -f "$STAMP_SRC" ]]; then
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  seed_artifacts CHG-800 L1 claude/s-1
  commit_all "docs: CHG-800 artifacts"
  printf '# CHG-800 编码记录\n\n## 改动文件清单\n' > docs/changes/CHG-800/04.5-coding-record.md
  printf '# CHG-800 测试结果\n' > docs/changes/CHG-800/05-test-results.md
  printf '# CHG-800 部署配置\n未命中，不适用：无配置项。\n' > docs/changes/CHG-800/06.5-deployment-config.md
  printf '# CHG-800 交付总结\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | x | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-800/06-delivery-summary.md
  printf '# CHG-800 评审报告\n## 评审结论\n通过\n' > docs/changes/CHG-800/07-review-report.md
  printf '# CHG-800 Changelog\n#### 执行记录（ReAct）\n' > docs/changes/CHG-800/09-changelog.md
append_masters docs/changes/CHG-800/09-changelog.md

  scripts/stamp-provenance.sh --all CHG-800 >/dev/null 2>&1
  report "T17b --all stamps the whole change directory" 0 "$?"

  md_count=$(ls docs/changes/CHG-800/*.md | wc -l | tr -d ' ')
  blk_total=$(grep -c '^<!-- provenance$' docs/changes/CHG-800/*.md | awk -F: '{s+=$2} END{print s}')
  report "T17b every md artifact carries exactly one provenance block (summed, not per-file)" "$md_count" "$blk_total"
  report "T17b 00-governance.json is deliberately NOT stamped" 0 \
    "$(grep -c '^<!-- provenance$' docs/changes/CHG-800/00-governance.json || true)"
  check_ok=0
  for f in docs/changes/CHG-800/*.md; do
    scripts/stamp-provenance.sh --check "$f" >/dev/null 2>&1 || check_ok=1
  done
  report "T17b --check accepts every stamped artifact" 0 "$check_ok"

  scripts/stamp-provenance.sh --all CHG-800 >/dev/null 2>&1
  report "T17b --all is idempotent (no block stacking)" 1 \
    "$(( $(grep -c '^<!-- provenance$' docs/changes/CHG-800/04.5-coding-record.md) == 1 ? 1 : 0 ))"

  # 空目录（无任何 md）：零成功必须失败，"nothing stamped" 不得伪装成功
  mkdir -p docs/changes/CHG-801
  scripts/stamp-provenance.sh --all CHG-801 >/dev/null 2>&1
  report "T17b --all fails on a directory with no md artifacts" 2 "$?"
else
  echo "SKIP T17b: stamp-provenance.sh 为 --guard 层文件（未装 guard 层时不存在）"
fi

}

section_T18() {
# ------------------------------------------------ T18 变更批次 / 同日合并（v3.18.0）
# 批次把"一个变更一套产物"放宽为"一套产物承载多个变更"。本组端到端验证放宽的**边界**：
# 目录放宽但文件名不变、治理记录必须逐变更成行（否则读到兄弟的风险）、风险上限不放宽、
# 闭环判定细一档（看自己的锚点而非共享文件），以及被 T17 掩盖的 `--stage staged` 路径
# （批次解析发生在 `$( )` 子壳里，与 begin 的全局变量路径不同——bash 3.2 的
# `local a="$1" b="...$a"` 缺陷正是在这里才会暴露）。
# v3.19.0 补 ④b：**权威名单**方向。批次共享产物必然含结构标题（§2.16.2 的
# `## Observation`），"把 `## <ascii 单词>` 当变更号"会让 metrics 造出幽灵变更、
new_repo
seed_batch_artifacts BATCH-20260101 CHG-800:L0 CHG-801:L1
commit_all "docs: batch artifacts"

# ① 同批两个成员都能 begin——产物名与独立目录完全同名，只有目录不同
scripts/agent-gate begin CHG-800 >/dev/null 2>&1
report "T18 batch member begins (anchor-addressed, same filenames)" 0 $?
scripts/agent-gate begin CHG-801 >/dev/null 2>&1
report "T18 a second member of the same batch begins" 0 $?

# ② metrics 按**变更**出行，不按目录——否则整批塌缩成一个 BATCH-* 行、
#    一个风险等级顶替全部成员
t18m=$(mktemp)
scripts/agent-gate metrics > "$t18m" 2>&1
report "T18 metrics emits one row per change, not per directory" 2 "$(wc -l < "$t18m" | tr -d ' ')"
report "T18 metrics row names the first member" 1 "$(grep -c '"change_id":"CHG-800"' "$t18m")"
report "T18 metrics row names the second member" 1 "$(grep -c '"change_id":"CHG-801"' "$t18m")"
rm -f "$t18m"

# ③ --stage staged：批次解析走 `$( )` 子壳（id 是局部变量，不继承全局），
#    这是 bash 3.2 `local` 多赋值缺陷唯一会现形的路径
git add -A
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18 --stage staged resolves batch dirs (no unbound variable)" 0 $?

# ④ 治理记录按行取值：删掉 CHG-800 那一行，它必须红，而兄弟仍绿。
#    反向形态最危险——"取文件里第一个 risk_level"会把兄弟的风险读成本变更的。
t18gov=docs/changes/BATCH-20260101/00-governance.json
cp "$t18gov" "$t18gov.bak"
grep -v '"change_id":"CHG-800"' "$t18gov.bak" > "$t18gov"
out=$(scripts/agent-gate begin CHG-800 2>&1); rc=$?
report "T18 a member with no governance line is refused" 2 "$rc"
check_output "T18 the refusal names the missing record" "declares no governance record for 'CHG-800'" "$out"
scripts/agent-gate begin CHG-801 >/dev/null 2>&1
report "T18 the sibling record is unaffected (line-wise read)" 0 $?
cp "$t18gov.bak" "$t18gov"; rm -f "$t18gov.bak"

# ④b v3.19.0 实测缺陷（本组曾经漏测）：批次共享产物里**必然**会出现结构标题——
#     §2.16.2 强制 09-changelog.md 含 Observation 记录，作者写成 `## Observation`
#     时，"把每个 `## <ascii 单词>` 都当变更号"的读法会同时制造两个假象：
#       ① metrics 凭空多出一行 `{"change_id":"Observation"}`（幽灵变更）；
#       ② `--stage staged` 拿 "Observation" 去查治理记录 → 整批被拒，报文还说
#          "00-governance.json declares no governance record for 'Observation'"。
#     根因：`## <标题>` 在文本层面无法区分"变更小节"与"结构小节"——所以不能
#     反向推断，必须正向读权威名单（00-governance.json 的 change_id）。
#     旧夹具用 `#### 执行记录（ReAct）` 绕开了这个形状，故一直绿——这正是"夹具
#     比真实产物规整"造成的盲区，故此处用**真实形状**（`## Observation`）钉住。
printf '# 09\n## Observation\n#### 执行记录（ReAct）\ncmd: echo ok -> ok\n\n## CHG-800\n' \
  > docs/changes/BATCH-20260101/09-changelog.md
append_masters docs/changes/BATCH-20260101/09-changelog.md
git add -A
out=$(scripts/agent-gate --stage staged 2>&1); rc=$?
report "T18 staged survives a structural '## Observation' heading in a shared artifact" 0 "$rc"
# Count-based (not check_output): the assertion is "the gate never mentions
# Observation", and check_output only asserts presence — an empty `actual`
# against `^$` does not match, so a presence-shaped helper would invert here.
report "T18 the structural heading is not read as a change id" 0 "$(printf '%s' "$out" | grep -c 'Observation' || true)"
t18m2=$(mktemp)
scripts/agent-gate metrics > "$t18m2" 2>&1
report "T18 metrics invents no phantom change for a structural heading" 0 "$(grep -c '"change_id":"Observation"' "$t18m2")"
report "T18 metrics still emits one row per declared change" 2 "$(grep -c '"change_id":' "$t18m2" | tr -d ' ')"
rm -f "$t18m2"

# ⑤ 风险上限不放宽：批次共享产物会削弱逐变更证据边界与角色独立性，
#    L2/L3 必须独立目录——门禁按**记录**拒绝，不能靠目录布局绕过
printf '{"change_id":"CHG-802","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"a","test_owner":"b","review_owner":"c"}\n' >> "$t18gov"
printf '## CHG-802\n## 问题\nx\n## 预期结果\ny\n## 开放问题\nn\n' >> docs/changes/BATCH-20260101/00-intent.md
printf '## CHG-802\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n' >> docs/changes/BATCH-20260101/00.5-communication.md
out=$(scripts/agent-gate begin CHG-802 2>&1); rc=$?
report "T18 L2 inside a batch is refused" 2 "$rc"
check_output "T18 the refusal states the L0/L1 ceiling" "batches are L0/L1 only" "$out"

# ⑥ 闭环判定细一档（FU-015 同义）：changelog 被同批共享，"文件存在"不再等于
#    "本变更已关闭"——否则兄弟的 changelog 会把后加入的变更一起判为已关闭
printf '# 09\n## CHG-800\n#### 执行记录（ReAct）\nObservation\n' > docs/changes/BATCH-20260101/09-changelog.md
append_masters docs/changes/BATCH-20260101/09-changelog.md
out=$(scripts/agent-gate begin CHG-800 2>&1); rc=$?
report "T18 a closed batch member is refused" 2 "$rc"
check_output "T18 closure is read from the member's own anchor" "carries a '## CHG-800' section" "$out"
scripts/agent-gate begin CHG-801 >/dev/null 2>&1
report "T18 a sibling absent from the shared changelog still begins" 0 $?

# ⑦ 零回归：独立 <变更号>/ 目录永远优先，L2 在独立目录照常合法
seed_begin CHG-810 L1 claude/s-1
report "T18 dedicated directory still resolves to itself (no regression)" 0 $?
seed_begin CHG-811 L2 claude/s-1 tester reviewer
report "T18 L2 in a dedicated directory is still accepted" 0 $?

# ⑧ 盖章器认批次：默认目标落在批次目录的共享编码记录上，块证明**批次**并列出成员
if [[ -f "$STAMP_SRC" ]]; then
  new_repo
  cp "$STAMP_SRC" scripts/stamp-provenance.sh
  chmod +x scripts/stamp-provenance.sh
  seed_batch_artifacts BATCH-20260102 CHG-820:L0 CHG-821:L1
  commit_all "docs: batch artifacts"
  scripts/agent-gate begin CHG-820 >/dev/null 2>&1
  printf '# 04.5 编码记录\n## CHG-820\nx\n## CHG-821\ny\n' > docs/changes/BATCH-20260102/04.5-coding-record.md
  scripts/stamp-provenance.sh CHG-821 >/dev/null 2>&1
  report "T18 stamper resolves the batch directory" 0 $?
  t18blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/BATCH-20260102/04.5-coding-record.md)
  check_output "T18 batch provenance attests the batch" "^change: BATCH-20260102$" "$t18blk"
  check_output "T18 batch provenance lists its members" "^batch_changes: CHG-820 CHG-821$" "$t18blk"
  # 共享文件的块不该因"这次是哪个成员盖的"而改写：风险取批次最高值 → 稳定
  check_output "T18 batch risk is the batch maximum (L1)" "^risk: L1$" "$t18blk"
  scripts/stamp-provenance.sh CHG-820 >/dev/null 2>&1
  t18blk2=$(sed -n '/^<!-- provenance$/,/^-->$/p' docs/changes/BATCH-20260102/04.5-coding-record.md)
  check_output "T18 re-stamping by a sibling leaves the risk line stable" "^risk: L1$" "$t18blk2"
  report "T18 batch re-stamping stays idempotent (one block)" 1 "$(grep -c '^<!-- provenance$' docs/changes/BATCH-20260102/04.5-coding-record.md)"
else
  echo "SKIP T18 stamper cases: stamp-provenance.sh 为 --guard 层文件（未装 guard 层时不存在）"
fi

}

section_T18b() {
# ------------------------------------------------ T18b 同日批次默认强制（v3.27.0，CHG-027）
# §1.1 v3.24.0 把"同日多个 L0/L1 默认共用批次"写成默认，但 begin 不拦就是纯建议
# （下游实测：同日 5 组 L0/L1 全部各开独立目录）。本组验证：当日批次已存在时，
# 独立 L0/L1 begin 必须被拦；豁免必须显式；入批与 L2 独立照常。
new_repo
seed_batch_artifacts "BATCH-$(date -u +%Y%m%d)" CHG-820:L0
commit_all "docs: today's batch exists"
seed_begin CHG-821 L1 claude/s-1
# v3.62.2 (CHG-082): E86 声明级分支先于 E73 落 die——落位主题用例撤掉夹具豁免，
# 断言口径同步改为 E86 正向措辞（E73 保留为纵深，不再是最早执法点）。
report "T18b begin rejects an independent L0/L1 when a same-day batch exists" 2 "$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate begin CHG-821 >/dev/null 2>&1; echo $?)"
out=$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate begin CHG-821 2>&1 || true)
check_output "T18b refusal names the batch and the escape hatch" "GATE-E86.*same-day L0/L1 changes must join the batch.*AGENT_GUARD_ALLOW_INDEPENDENT" "$out"
AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-821 >/dev/null 2>&1
report "T18b explicit override allows an independent L0/L1" 0 $?
seed_batch_artifacts "BATCH-$(date -u +%Y%m%d)" CHG-822:L1
scripts/agent-gate begin CHG-822 >/dev/null 2>&1
report "T18b joining the same-day batch begins" 0 $?
seed_begin CHG-823 L2 claude/s-1 tester reviewer
report "T18b L2 keeps its independent-directory right (no batch compulsion)" 0 $?

}

section_T19() {
# ------------------------------------------------ T19 治理记录的格式无关性（v3.20.0）
# 回归背景：v3.18.0 为支持批次把"读治理记录"从**整文件**（v3.14.0 的
# `json_string <file> <key>`，用 `sed -nE ... "$file"` 逐行扫全文件）改成**行式**
# （`gov_record` = `grep ... | head -1`）。行式对批次是必需的（要按 change_id 隔离
# 兄弟记录），但它**静默打破了多行格式化记录**——而多行恰恰是**随包下发的模板
# `resources/templates/governance-state.json` 的形状**，也是 SKILL.md 指示 Agent
# 生成 `00-governance.json` 时照抄的形状。后果：照着文档走一遍，`begin` 报
# `must declare risk_level L0, L1, L2, or L3`，而该字段就在 change_id 下面两行。
# 本仓自己的账本 16/16 条（CHG-001..016）全是多行，全部会被自己的门禁拒绝。
#
# 本组为什么以前测不出来：`seed_artifacts` / `seed_batch_artifacts` 都用
# `printf '{"change_id":...}\n'` 手写**单行**记录——夹具比真实产物规整，于是
# 这一整类形状从未进过用例。**夹具必须覆盖真实形状**（同 T18 ④b 的教训）。
#
# 断言方向刻意双向：既钉"多行必须被接受"，也钉"单行不得回归"。

# ① 多行独立目录记录：必须被接受（v3.18.0 起被误拒）
new_repo
seed_artifacts CHG-840 L1 claude/s-1
cat > docs/changes/CHG-840/00-governance.json <<'EOF'
{
  "change_id": "CHG-840",
  "risk_level": "L1",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1","test_owner":"t/x","review_owner":"r/x"
}
EOF
out=$(scripts/agent-gate begin CHG-840 2>&1); rc=$?
report "T19 begin accepts a pretty-printed governance record" 0 "$rc"
check_output "T19 the refusal no longer fires on a record that declares risk_level" "active change is CHG-840" "$out"

# ② metrics 必须读出多行记录的风险等级（曾经一律 null）
t19m=$(scripts/agent-gate metrics 2>&1)
check_output "T19 metrics reads risk_level from a multi-line record" '"change_id":"CHG-840","risk_level":"L1"' "$t19m"

# ③ 整条记录被解析，而不是只读到第一行：L2 缺 test_owner 必须在**所有者**上被拒
#    （若 risk_level 读不到，会先在 risk_level 上报错——报文不同，可区分）
seed_artifacts CHG-841 L2 claude/s-1
cat > docs/changes/CHG-841/00-governance.json <<'EOF'
{
  "change_id": "CHG-841",
  "risk_level": "L2",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1"
}
EOF
out=$(scripts/agent-gate begin CHG-841 2>&1); rc=$?
report "T19 a multi-line L2 record without test_owner is still refused" 2 "$rc"
check_output "T19 the refusal is about owners, not about a missing risk_level" "must declare test_owner and review_owner for L2" "$out"

# ④ 多行 + 逗号分隔（jq 风格 / JSON 数组风格）的批次：逐成员读自己的风险，
#    不得串到兄弟（这正是 v3.18.0 引入行式读取要解决的问题，不能被本修复带回）
new_repo
seed_batch_artifacts BATCH-20260103 CHG-830:L0 CHG-831:L1
cat > docs/changes/BATCH-20260103/00-governance.json <<'EOF'
{
  "change_id": "CHG-830",
  "risk_level": "L0",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1","test_owner":"t/x","review_owner":"r/x"
},
{
  "change_id": "CHG-831",
  "risk_level": "L1",
  "spec_author":"author/a-1","implementation_owner": "claude/s-1","test_owner":"t/x","review_owner":"r/x"
}
EOF
t19b=$(scripts/agent-gate metrics 2>&1)
check_output "T19 a multi-line batch member reads its OWN risk" '"change_id":"CHG-830","risk_level":"L0"' "$t19b"
check_output "T19 the sibling reads its own risk, not the first record's" '"change_id":"CHG-831","risk_level":"L1"' "$t19b"
scripts/agent-gate begin CHG-831 >/dev/null 2>&1
report "T19 a member of a multi-line batch begins" 0 $?

# ⑤ 零回归：单行记录（历史与批次推荐写法）继续可用
new_repo
seed_begin CHG-842 L1 claude/s-1
report "T19 one-line records still begin (no regression)" 0 $?

# ⑥ 结构校验（CHG-121，batch 0；CHG-123 拆码 E134）：同一行拼接的 JSON 对象必须被拒绝。
#    实测 12/12 个批次台账外部 json.load 失败，正是这个形状；内部读取器容忍它，
#    所以坏台账一直静默存在。
new_repo
seed_artifacts CHG-843 L1 claude/s-1
printf '{"change_id": "CHG-843", "risk_level": "L1", "spec_author":"a/b/c","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x"}{"change_id": "CHG-844", "risk_level": "L1"}\n' > docs/changes/CHG-843/00-governance.json
out=$(scripts/agent-gate begin CHG-843 2>&1); rc=$?
report "T19 E134 refuses same-line concatenated governance records (CHG-123)" 2 "$rc"
check_output "T19 E134 names the invalid shape (CHG-123)" "GATE-E134" "$out"

}

section_T20() {
# ------------------------------------------------ T20 审计单元识别与"空转显式声明"（v3.21.0）
# 本仓自查实测到的假绿：审计脚本用"<docs>/ 下一层子目录"取审计单元，而 `docs/changes`、
# `docs/bugs`、`docs/review` 都算"子目录"——它们一存在，"没有产物目录"的空转分支就不触发，
# G2/G3/G5/G6 **一条断言都不执行、也不打印任何行**。实测：一个
# `docs/changes/CHG-001/01-spec.md` 里带 REQ 跳号的仓库**通过**了审计。同一根因还让 G4
# 去找 `docs/changes/09-changelog.md`（不存在）而误报**假红**。
# 伴生缺陷在 `check_seq` 里：① grep 全文件的编号出现（含正文引用）② 基线写死从 1 开始
# ——本仓 16 个 01-spec.md 共误报 **695** 处"缺号"。
# v3.21.0 修法：正信号识别 + 空转**显式声明** + 定义式/自身区间；G2 覆盖两轨，
# G3/G5/G6 只覆盖活文档（冻结变更目录按 §2.15 硬性规则 4 不可回填，事后判红是时代错置）。
if [[ -f "$AUDIT_SRC" ]]; then

# ① 靶心：管线态仓库里 REQ 跳号必须判红。v3.21.0 之前 G2 一条断言都不跑 → 整个审计通过。
AC=$(mktemp -d); audit_change_fixture "$AC"
printf '## REQ-004 第四个需求\n' >> "$AC/docs/changes/CHG-001/01-spec.md"
out=$(bash "$AUDIT_SRC" "$AC" 2>&1); rc=$?
report "T20 audit reds on a REQ gap inside a change dir (was a silent pass)" 1 "$rc"
check_output "T20 the red names the gap" 'G2 REQ numbering in CHG-001 continuous 1\.\.4 .*got 1' "$out"

# ② 空转必须**显式声明**：只有变更目录时 G3/G5/G6 没跑，输出里必须有这句话。
check_output "T20 the G3/G5/G6 vacuous skip is declared, not silent" "G3/G5/G6 VACUOUS SKIP" "$out"

# ③ 变更目录的号段不始于 1 是常态（§1.2 编号空间全局）→ 不得报假缺号。
AC2=$(mktemp -d); audit_change_fixture "$AC2"
printf '# spec\n\n## REQ-080 甲\n## REQ-081 乙\n' > "$AC2/docs/changes/CHG-001/01-spec.md"
bash "$AUDIT_SRC" "$AC2" >/dev/null 2>&1
report "T20 a span not starting at 1 is not a gap (REQ-080..081)" 0 $?

# ④ 正文引用不得撑大号段（旧实现把"REQ 从 REQ-008 起（已用 REQ-001~007）"算成定义）。
AC3=$(mktemp -d); audit_change_fixture "$AC3"
printf '# spec\n\n> 编号衔接：REQ 从 REQ-080 起（CHG-001 已用 REQ-001~007）\n\n## REQ-080 甲\n## REQ-081 乙\n' \
  > "$AC3/docs/changes/CHG-001/01-spec.md"
bash "$AUDIT_SRC" "$AC3" >/dev/null 2>&1
report "T20 in-prose REQ references do not widen the definition span" 0 $?

# ⑤ G4 双登记在管线态布局下不得假红（旧实现只看 <docs>/ 下一层的 09-changelog）。
AC4=$(mktemp -d); audit_change_fixture "$AC4"
{ echo '### BUG-001：现象（严重度 P1）'; echo; echo '| 字段 | 内容 |'; echo '|---|---|'; echo '| 关联变更 | CHG-001 |'; echo '| 历史相似 | 未命中（根因关键词检索） |'; } > "$AC4/docs/bugfix-log.md"
printf '# CHG-001 Changelog\n\n## 2026-09-15\n\n- 对应缺陷：`BUG-001`（见 docs/bugfix-log.md）\n' > "$AC4/docs/changes/CHG-001/09-changelog.md"
bash "$AUDIT_SRC" "$AC4" >/dev/null 2>&1
report "T20 G4 resolves changelogs under the change root (no false orphan)" 0 $?

# ⑥ 完全没有产物目录时 G2 也要显式声明空转（而不是打一行"通过"就完事）。
AC5=$(mktemp -d); mkdir -p "$AC5/docs"
cp "$STD_SRC" "$AC5/docs/DEVELOPMENT_STANDARDS.md"; cp "$AG_SRC" "$AC5/AGENTS.md"
out=$(bash "$AUDIT_SRC" "$AC5" 2>&1)
check_output "T20 G2 vacuous skip is declared when no artifact dir exists" "G2 VACUOUS SKIP" "$out"

# ⑦ 零回归：功能目录（活文档）布局仍然全绿——G3/G5/G6 仍在此轨上执行。
AF=$(mktemp -d); audit_fixture "$AF"
out=$(bash "$AUDIT_SRC" "$AF" 2>&1); rc=$?
report "T20 a compliant feature-dir repo still passes (no regression)" 0 "$rc"
t20_ran=1
# 精确锚定 G3/G5/G6 组（v3.28.0 起 G8/A20/A21 在无 bugs/变更目录的仓库合法打印
# 自己的空转声明——泛 grep "VACUOUS SKIP" 会把"诚实声明未覆盖"误判成"G3 没跑"）。
grep -q "G3/G5/G6 VACUOUS SKIP" <<< "$out" && t20_ran=0
report "T20 G3/G5/G6 actually ran on the living-doc track (no vacuous skip)" 1 "$t20_ran"

rm -rf "$AC" "$AC2" "$AC3" "$AC4" "$AC5" "$AF"
else
  echo "SKIP T20: audit-docs-consistency.sh absent (bootstrap --core 未安装) — 跳过审计单元识别 golden cases"
fi

}

section_T21() {
# ------------------------------------------------ T21 一键安装器 install.sh（v3.22.0）
# install.sh 与 bootstrap.sh 同属源层工具（不随 --guard 分发）——目标仓布局自动 SKIP。
# 夹具用**最小 fake 源仓**（scripts/bootstrap.sh + tests/run-tests.sh + resources/，
# 无 .git）走 --from 离线路径：既覆盖"克隆之外"的全部逻辑，又保证测试零网络依赖。
if [[ -f "$ROOT/scripts/install.sh" && -f "$BOOT_SRC" ]]; then
  FAKE_SRC=$(mktemp -d "${TMPDIR:-/tmp}/install-src.XXXXXX")
  mkdir -p "$FAKE_SRC/scripts" "$FAKE_SRC/tests/lib" "$FAKE_SRC/tests/suites"
  cp "$ROOT/scripts/bootstrap.sh" "$FAKE_SRC/scripts/bootstrap.sh"
  cp "$ROOT/tests/run-tests.sh" "$FAKE_SRC/tests/run-tests.sh"
  cp "$ROOT/tests/lib/test-harness.sh" "$FAKE_SRC/tests/lib/test-harness.sh"
  cp "$ROOT/tests/suites/suite-01-core.sh" "$FAKE_SRC/tests/suites/suite-01-core.sh"
  cp "$ROOT/tests/suites/suite-02-install.sh" "$FAKE_SRC/tests/suites/suite-02-install.sh"
  cp "$ROOT/tests/suites/suite-03-session.sh" "$FAKE_SRC/tests/suites/suite-03-session.sh"
  cp "$ROOT/tests/suites/suite-04-gates.sh" "$FAKE_SRC/tests/suites/suite-04-gates.sh"
  cp "$ROOT/tests/suites/suite-05-adapter.sh" "$FAKE_SRC/tests/suites/suite-05-adapter.sh"
  cp "$ROOT/tests/suites/suite-06-runner.sh" "$FAKE_SRC/tests/suites/suite-06-runner.sh"
  cp "$ROOT/tests/suites/suite-07-adapt.sh" "$FAKE_SRC/tests/suites/suite-07-adapt.sh"
  cp "$ROOT/tests/suites/suite-08-infra.sh" "$FAKE_SRC/tests/suites/suite-08-infra.sh"
  # v3.92.3 (CHG-128 fix): guard 清单含 G-ENV 执行件——FAKE_SRC 必须同拷，
  # 否则 install 链在 install_file 缺源时整体红（安装器清单唯一权威=bootstrap）。
  cp "$ROOT/tests/fresh-clone-check.sh" "$FAKE_SRC/tests/fresh-clone-check.sh"
  # v3.79.0 (CHG-103): bootstrap guard 清单含树指纹 lib——FAKE_SRC 必须同拷，
  # 否则 install 链在 install_file 缺源时整体红（安装器清单唯一权威=bootstrap）。
  cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$FAKE_SRC/scripts/lib-suite-tree-fingerprint.sh"
  cp "$ROOT/scripts/lib-suite-lock.sh" "$FAKE_SRC/scripts/lib-suite-lock.sh"
  # v3.95.0 (CHG-132): guard 清单含 shard-sum.sh——FAKE_SRC 必须同拷（同上，
  # install_file 缺源 = 整链红）。
  cp "$ROOT/scripts/shard-sum.sh" "$FAKE_SRC/scripts/shard-sum.sh"
  # v3.96.0 (CHG-133): 同型——evidence-round.sh 入 guard 清单，夹具缺它即整链红。
  cp "$ROOT/scripts/evidence-round.sh" "$FAKE_SRC/scripts/evidence-round.sh"
  cp "$ROOT/SKILL.md" "$FAKE_SRC/SKILL.md"
  cp -R "$ROOT/resources" "$FAKE_SRC/resources"

  TGT=$(mktemp -d "${TMPDIR:-/tmp}/install-tgt.XXXXXX")
  (cd "$TGT" && git init -q && git config user.email t@x.invalid && git config user.name t \
    && echo hi > README.md && git add README.md && git commit -qm init)

  # TC-141 离线全量安装
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT" 2>&1); rc=$?
  report "T21 install.sh --from performs a full offline install" 0 "$rc"
  for f in AGENTS.md docs/DEVELOPMENT_STANDARDS.md scripts/agent-gate scripts/lib-json.sh scripts/lib-gate-staged.sh scripts/lib-gate-cold.sh scripts/lib-suite-tree-fingerprint.sh scripts/lib-suite-lock.sh .githooks/pre-commit \
           .agent-governance.yml tests/run-tests.sh tests/lib/test-harness.sh tests/suites/suite-01-core.sh tests/governance-smoke.sh tests/fresh-clone-check.sh; do
    [[ -e "$TGT/$f" ]] || { echo "T21 missing after install: $f" >&2; rc=1; }
  done
  report "T21 install lands the governance payload" 0 "$rc"
  # bootstrap --upgrade 拒绝脏树（fail-closed，git history 即备份）——升级路径用例先提交目标
  (cd "$TGT" && git add -A && git commit -qm artifacts)

  # TC-142 幂等重跑（已接入目标 → 自动探测为升级；--from 路径不进 pull 分支，
  # 也就没有自更新降级 NOTE——离线性由夹具本身保证）
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT" 2>&1); rc=$?
  report "T21 re-run against a governed target succeeds (auto-upgrade)" 0 "$rc"
  grep -q CONFLICT <<< "$out" && report "T21 re-run raises no conflict" 0 1 || report "T21 re-run raises no conflict" 0 0

  # TC-143 自动升级：fake 源版本 +0.0.1 → 重跑 → 目标规范页脚跟随（版本无关形态，
  # 与 T14 同型——不再钉死当前版本字面量，版本 bump 无须改本夹具）
  sed -i.bak 's/规范版本：v[0-9.][0-9.]*/规范版本：v9.9.9/' "$FAKE_SRC/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null \
    || sed -i '' 's/规范版本：v[0-9.][0-9.]*/规范版本：v9.9.9/' "$FAKE_SRC/resources/DEVELOPMENT_STANDARDS.md"
  rm -f "$FAKE_SRC/resources/DEVELOPMENT_STANDARDS.md.bak"
  (cd "$TGT" && git add -A && git commit -qm artifacts)
  bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT" >/dev/null 2>&1
  report "T21 version bump in source propagates via re-run" 1 \
    "$(grep -c '规范版本：v9\.9\.9' "$TGT/docs/DEVELOPMENT_STANDARDS.md" || true)"

  # TC-144（v3.50.0 CHG-062 语义升级）：目标已有用户 AGENTS.md → kept 保留原文（fail-visible），
  # 安装继续完成——不再 CONFLICT 拒绝（bootstrap agents-md 键 merge-or-keep，--force 不越）
  TGT2=$(mktemp -d "${TMPDIR:-/tmp}/install-tgt2.XXXXXX")
  printf '# my own agents file\n' > "$TGT2/AGENTS.md"
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" "$TGT2" 2>&1); rc=$?
  report "T21 user AGENTS.md kept and install completes" 0 "$rc"
  check_output "T21 kept path names AGENTS.md" "kept.*AGENTS.md" "$out"
  report "T21 conflicting target file is NOT overwritten" 1 \
    "$(grep -c 'my own agents file' "$TGT2/AGENTS.md" || true)"

  # TC-145 --as-skill：Skill 本体注册进客户端技能目录（symlink 指向 checkout，v3.23.0）
  # 全部经 --skills-root 重定向——测试零真实 HOME 写入。
  SKR=$(mktemp -d "${TMPDIR:-/tmp}/install-skills.XXXXXX")
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill claude --skills-root "$SKR" 2>&1); rc=$?
  report "T21 --as-skill links the skill into the client skills root" 0 "$rc"
  report "T21 --as-skill destination resolves SKILL.md through the link" 1 \
    "$([[ -f "$SKR/dev-standards-bootstrap/SKILL.md" ]] && echo 1 || echo 0)"

  # TC-146 幂等重跑：同落点重复 --as-skill 报 already linked，rc 0，不重复建链
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill claude --skills-root "$SKR" 2>&1); rc=$?
  report "T21 --as-skill re-run is idempotent (already linked)" 0 "$rc"
  check_output "T21 --as-skill re-run reports the existing link" "already linked" "$out"

  # TC-147 冲突 fail-closed：落点被真实目录占用 → 拒绝（rc 2）且原内容一字不动
  SKR2=$(mktemp -d "${TMPDIR:-/tmp}/install-skills2.XXXXXX")
  mkdir -p "$SKR2/dev-standards-bootstrap"
  printf 'mine' > "$SKR2/dev-standards-bootstrap/user.txt"
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill claude --skills-root "$SKR2" 2>&1); rc=$?
  report "T21 --as-skill refuses an occupied destination (fail-closed)" 2 "$rc"
  check_output "T21 --as-skill refusal names the fail-closed reason" "not a symlink" "$out"
  report "T21 --as-skill does not touch the existing directory" 1 \
    "$(grep -c mine "$SKR2/dev-standards-bootstrap/user.txt" || true)"

  # TC-148 路径形式：值含 "/" 视为落点目录本身（任意其他客户端）
  SKR3="$SKR2/custom-client"
  out=$(bash "$ROOT/scripts/install.sh" --from "$FAKE_SRC" --as-skill "$SKR3" 2>&1); rc=$?
  report "T21 --as-skill accepts a custom destination path" 0 "$rc"

  rm -rf "$FAKE_SRC" "$TGT" "$TGT2" "$SKR" "$SKR2"
else
  echo "SKIP T21: install.sh 为 Skill 仓库安装器（不随 --guard 分发）——跳过一键安装用例"
fi

# ---------------------------------------------------------------- 摘要
}

section_T22b() {
# ------------------------------------------------ T22 记录级执法（独立仓，放套件尾部）
new_repo
seed_artifacts CHG-610 L0 claude/s-1
printf '{"change_id":"CHG-610","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","review_owner":"author/a-1"}\n' > docs/changes/CHG-610/00-governance.json
scripts/agent-gate begin CHG-610 >/dev/null 2>&1
report "begin rejects spec_author == review_owner at L0 (lowest bar)" 2 $?
printf '{"change_id":"CHG-610","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","review_owner":"codex/x-7"}\n' > docs/changes/CHG-610/00-governance.json
scripts/agent-gate begin CHG-610 >/dev/null 2>&1
report "begin accepts L0 with spec_author distinct from review_owner" 0 $?

new_repo
seed_artifacts CHG-611 L2 gemini/m-1 claude/c-9 codex/x-7
printf '{"change_id":"CHG-611","risk_level":"L2","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7"}\n' > docs/changes/CHG-611/00-governance.json
scripts/agent-gate begin CHG-611 >/dev/null 2>&1
out=$(scripts/agent-gate begin CHG-611 2>&1 || true)
check_output "begin names the missing spec_author (FU-041)" "must declare spec_author" "$out"
printf '{"change_id":"CHG-611","risk_level":"L2","spec_author":"gemini/m-1","implementation_owner":"gemini/m-1","test_owner":"claude/c-9","review_owner":"codex/x-7"}\n' > docs/changes/CHG-611/00-governance.json
scripts/agent-gate begin CHG-611 >/dev/null 2>&1
report "begin rejects spec_author duplicating an owner at L2" 2 $?

}

section_T18c() {
# ------------------------------------------------ T18c 缺陷六件套按天入批（v3.35.0，BUG-005）
# §1.1 v3.35.0 废止 v3.22.0"缺陷组不入批"：当日缺陷批次已存在时，同日新建的独立
# 缺陷组必须入批（provenance generated_at 判日）；豁免显式；批次嵌套组照常扫描。
new_repo
# v3.62.2 (CHG-082)：基座 CHG-900 由 L1 改 L2——staged 校验暂存树内全部变更，
# env -u 下 L1 独立目录会在 E58 之前先落 E86；E58 主题要求树内无 L0/L1 独立形态。
seed_begin CHG-900 L2 claude/s-1 tester reviewer
today=$(date -u +%Y%m%d)
mkdir -p "docs/bugs/BATCH-$today/BUG-901"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# %s\n' "$d6" > "docs/bugs/BATCH-$today/BUG-901/$d6.md"
done
append_diag_lines "docs/bugs/BATCH-$today/BUG-901/01-diagnosis.md"
seed_artifacts CHG-902 L0 claude/s-1
# v3.62.2 (CHG-082)：CHG-902 由 L0 改 L2——E86 双向化后 L0/L1 专属目录活动变更会在
# E58 之前先落 E86 die；E58 主题的载体必须是合法独立形态（L2）。bug_ref 绑定语义不变。
printf '{"change_id":"CHG-902","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-901"}\n' > docs/changes/CHG-902/00-governance.json
scripts/agent-gate begin CHG-902 >/dev/null 2>&1
report "T18c begin resolves a bug_ref bound to a batched defect group" 0 $?
git add docs/changes/CHG-902 && git commit -qm "seed CHG-902 intent"
mkdir -p docs/bugs/BUG-902
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# %s\n' "$d6" > "docs/bugs/BUG-902/$d6.md"
done
append_diag_lines docs/bugs/BUG-902/01-diagnosis.md
{ printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: %sT00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n' "$(date -u +%Y-%m-%d)"; cat docs/bugs/BUG-902/01-diagnosis.md; } > docs/bugs/BUG-902/01-diagnosis.md.tmp && mv docs/bugs/BUG-902/01-diagnosis.md.tmp docs/bugs/BUG-902/01-diagnosis.md
echo y > src/z.js   # staged/stop 只在存在代码路径改动时执法（对齐 T4/T5 夹具）
git add -A          # staged 以暂存区为准，空暂存即空转放行
# v3.62.2 (CHG-082)：E58 正反向主题用例——撤夹具豁免保持执法可见
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c defect groups join the same-day batch (standalone today is rejected)" 2 "$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate --stage staged >/dev/null 2>&1; echo $?)"
out=$(env -u AGENT_GUARD_ALLOW_INDEPENDENT scripts/agent-gate --stage staged 2>&1 || true)
check_output "T18c refusal names the batch and the escape hatch" "move it into the day batch.*AGENT_GUARD_ALLOW_INDEPENDENT" "$out"
AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c explicit override allows a standalone same-day group" 0 $?
printf '%s\n' "BUG-902 # legacy standalone, registered" > docs/bugs/.gate-allowlist
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c allowlisted legacy standalone group passes" 0 $?
rm -f docs/bugs/.gate-allowlist
sed -i '' 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-902/01-diagnosis.md 2>/dev/null \
  || sed -i 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-902/01-diagnosis.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18c pre-v3.35.0 standalone groups (old provenance date) stay legal" 0 $?

}

section_T18d() {
# ------------------------------------------------ T18d 缺陷批次扁平化（v3.36.0，BUG-006）
# §1.1 v3.36.0：同日多缺陷共落 BATCH-YYYYMMDD/ 扁平目录——六件套同名文件 + `## <BUG-id>`
# 锚点分节，当天追加落在同一套文件里（与变更批次同构）；嵌套形态历史合法；
# bug_group_dir 三形态统一解析（独立 → 嵌套 → 扁平锚点，多处命中 fail-closed）。
new_repo
seed_begin CHG-930 L1 claude/s-1
today=$(date -u +%Y%m%d)
mkdir -p "docs/bugs/BATCH-$today"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# flat batch\n\n## BUG-903 flat member\n' > "docs/bugs/BATCH-$today/$d6.md"
done
append_diag_lines "docs/bugs/BATCH-$today/01-diagnosis.md"
# 负例铺垫：BUG-904 只在诊断件锚定（其余五件缺同 id 小节 → 六件锚点不齐）
printf '\n## BUG-904 member\n' >> "docs/bugs/BATCH-$today/01-diagnosis.md"
seed_artifacts CHG-931 L0 claude/s-1
printf '{"change_id":"CHG-931","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-903"}\n' > docs/changes/CHG-931/00-governance.json
scripts/agent-gate begin CHG-931 >/dev/null 2>&1
report "T18d flat bug batch begin resolves a bug_ref via the batch anchor" 0 $?
echo y > src/z.js   # staged/stop 只在存在代码路径改动时执法（对齐 T4/T5 夹具）
git add -A          # staged 以暂存区为准，空暂存即空转放行
out=$(scripts/agent-gate --stage staged 2>&1 || true)
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d flat batch anchor missing in five pieces is rejected at staged" 2 $?
check_output "T18d refusal names the flat anchor set" "six-piece anchor set" "$out"
for d6 in 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '\n## BUG-904 member\n' >> "docs/bugs/BATCH-$today/$d6.md"
done
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d flat batch passes once every anchored id spans the six pieces" 0 $?
# TC-1069 (v3.61.1 REQ-1015): E87 roster diff — an id anchored only in sibling
# docs (missing from 01-diagnosis) escaped E57's per-gid loop entirely.
printf '\n## BUG-906 member\n' >> "docs/bugs/BATCH-$today/02-impact.md"
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T18d E87 rejects an id anchored outside 01-diagnosis (roster diff)" "GATE-E87" "$out"
sed -i '' '/^## BUG-906 member$/d' "docs/bugs/BATCH-$today/02-impact.md" 2>/dev/null || sed -i '/^## BUG-906 member$/d' "docs/bugs/BATCH-$today/02-impact.md"
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d E87 clears once the stray anchor is removed" 0 $?
cp "$ROOT/resources/templates/stamp-provenance.sh" scripts/stamp-provenance.sh
scripts/stamp-provenance.sh --bug BUG-903 >/dev/null 2>&1
report "T18d --bug resolves and stamps a flat batch member" 0 $?
check_output "T18d flat stamp attests the batch id" "^bug: BATCH-" "$(cat "docs/bugs/BATCH-$today/01-diagnosis.md")"
check_output "T18d flat stamp lists the members" "^batch_changes: BUG-90[34]" "$(cat "docs/bugs/BATCH-$today/01-diagnosis.md")"
mkdir -p "docs/bugs/BATCH-$today/BUG-905"
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# nested\n' > "docs/bugs/BATCH-$today/BUG-905/$d6.md"
done
append_diag_lines "docs/bugs/BATCH-$today/BUG-905/01-diagnosis.md"
seed_artifacts CHG-932 L0 claude/s-1
printf '{"change_id":"CHG-932","risk_level":"L0","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-905"}\n' > docs/changes/CHG-932/00-governance.json
scripts/agent-gate begin CHG-932 >/dev/null 2>&1
report "T18d nested legacy group still resolves under the three-form resolver" 0 $?

}

section_T18d_E58R() {
# ---- T18d-E58R E58 反向（v3.62.2，CHG-082 REQ-1028/TC-1087）：无批 + 当日首个独立缺陷组 ----
# 活动变更用 L2（L0/L1 独立已被 E86 拒，不能作载体）；缺陷组 E57 六件锚点齐备，
# provenance 今日章（正向同键控）；未章/非今日 fail-open 跳过与正向一致。
new_repo
seed_begin CHG-933 L2 claude/s-47 tester reviewer
git add docs/changes/CHG-933 && git commit -qm "seed CHG-933 intent"
unset AGENT_GUARD_ALLOW_INDEPENDENT
mkdir -p docs/bugs/BUG-907
for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do
  printf '# t\n\n## BUG-907 member\n' > "docs/bugs/BUG-907/$d6.md"
done
append_diag_lines docs/bugs/BUG-907/01-diagnosis.md
cp "$ROOT/resources/templates/stamp-provenance.sh" scripts/stamp-provenance.sh 2>/dev/null || cp "$ROOT/scripts/stamp-provenance.sh" scripts/stamp-provenance.sh
chmod +x scripts/stamp-provenance.sh
scripts/stamp-provenance.sh --bug BUG-907 >/dev/null 2>&1
echo y > src/z.js
git add -A
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T18d E58 reverse: first-of-day standalone defect group with no batch is rejected" "GATE-E58.*first L0/L1 defect of the day creates the day batch" "$out"
AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d E58 reverse admits with explicit escape" 0 $?
sed -i '' 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-907/01-diagnosis.md 2>/dev/null || sed -i 's/generated_at: [0-9-]*/generated_at: 2020-01-01/' docs/bugs/BUG-907/01-diagnosis.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T18d E58 reverse skips non-today groups (fail-open, same keying as forward)" 0 $?
export AGENT_GUARD_ALLOW_INDEPENDENT=1

}

section_T23() {
# ------------------------------------------------ T23 项目总册机校（v3.35.0，§1.3/CHG-035）
new_repo
seed_artifacts CHG-910 L1 claude/s-1
rm -rf docs/project
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
report "T23 begin refuses to start without project masters" 2 $?
out=$(scripts/agent-gate begin CHG-910 2>&1 || true)
check_output "T23 refusal names the masters and the escape hatch" "project masters not initialized.*AGENT_GUARD_ALLOW_NO_PROJECT_MASTERS" "$out"
seed_project_masters
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
report "T23 begin passes once the thirteen masters exist" 0 $?
rm docs/project/P12-product-context.md
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
report "T23 begin refuses with an incomplete master set" 2 $?
seed_project_masters
scripts/agent-gate begin CHG-910 >/dev/null 2>&1
# 交付侧：09 缺回填清单 → stop 拒；行不完整 → 拒；补齐后（stub 溯源块）放行
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-910/09-changelog.md
printf 'cr\n' > docs/changes/CHG-910/04.5-coding-record.md
printf 'tr\n' > docs/changes/CHG-910/05-test-results.md
printf '未命中，不适用（无配置变更）\n' > docs/changes/CHG-910/06.5-deployment-config.md
printf '# 交付总结\n#### 遗留\n- FU-001 演示\n' > docs/changes/CHG-910/06-delivery-summary.md
for pf9 in docs/changes/CHG-910/*.md; do
  { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "$pf9"; } > "$pf9.tmp" && mv "$pf9.tmp" "$pf9"
done
echo y > src/t23.js   # stop 只在存在代码路径改动时执法（对齐 T5 夹具）
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T23 project-master backfill checklist is enforced at stop" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T23 refusal names the missing checklist" "项目总册回填清单" "$out"
append_masters docs/changes/CHG-910/09-changelog.md
sed -i '' 's/^- \[x\] P03/- [ ] P03/' docs/changes/CHG-910/09-changelog.md 2>/dev/null \
  || sed -i 's/^- \[x\] P03/- [ ] P03/' docs/changes/CHG-910/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T23 an unchecked row without a reason keeps stop red" 2 $?
sed -i '' 's/^- \[ \] P03/- [ ] P03 未命中（理由：无接口变化）/' docs/changes/CHG-910/09-changelog.md 2>/dev/null \
  || sed -i 's/^- \[ \] P03/- [ ] P03 未命中（理由：无接口变化）/' docs/changes/CHG-910/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T23 an explicit 未命中 row with a reason passes" 0 $?
  # v3.66.0 (CHG-089): a WHOLE missing P row (grep no-match) must surface as
  # GATE-E60 — pre-fix, pipefail killed the script before die() (silent exit 1).
  grep -v '^- \[x\] P05' docs/changes/CHG-910/09-changelog.md > docs/changes/CHG-910/09-changelog.md.tmp \
    && mv docs/changes/CHG-910/09-changelog.md.tmp docs/changes/CHG-910/09-changelog.md
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "T23 a wholly missing P row dies with GATE-E60 (not silent)" "GATE-E60" "$out"

}

section_T24() {
# ------------------------------------------------ T24 session water level (v3.38.0)
new_repo
seed_artifacts CHG-920 L1 claude/s-1
mkdir -p .agent-state
printf '{"turns":80,"session":"s-1","updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-water.json
out=$(scripts/agent-gate begin CHG-920 2>&1); rc=$?
check_output "T24 begin names the water level and both escapes" "session water level 80 turns reaches the 50-turn limit" "$out"
check_output "T24 refusal names handoff path" "handoff to a fresh session" "$out"
check_output "T24 refusal names escape env" "AGENT_GUARD_ALLOW_OVER_WATER=1" "$out"
report "T24 begin exit 2 over water" 2 "$rc"
AGENT_GUARD_ALLOW_OVER_WATER=1 scripts/agent-gate begin CHG-920 >/dev/null 2>&1
report "T24 explicit escape passes over water" 0 $?
printf '{"turns":10,"session":"s-2","updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-water.json
AGENT_GUARD_SESSION_TURN_LIMIT=5 scripts/agent-gate begin CHG-920 >/dev/null 2>&1
report "T24 tuned limit below turns refuses (exit 2)" 2 $?
rm -f .agent-state/session-water.json
AGENT_GUARD_SESSION_TURN_LIMIT=5 scripts/agent-gate begin CHG-920 >/dev/null 2>&1
report "T24 no water file degrades fail-open" 0 $?

}

section_T25() {
# ------------------------------------------------ T25 new-change scaffolder (v3.38.0)
new_repo
NEWCHANGE_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -f "$NEWCHANGE_SRC" ]]; then
  cp "$NEWCHANGE_SRC" scripts/new-change
  copy_gate_to scripts agent-gate   # v3.55.0: wave-2 确认门下沉 gate（check-confirm）
  chmod +x scripts/new-change
  # CHG-085/REQ-1042（TC-1109，v3.64.0⑥）：CHG-078 AC-1 一次性 grep 常驻化——
  # 判日/日期字段全形态（%Y%m%d/%Y-%m-%d）必须带 -u，防第三处漏网（FU-929）。
  _bare_date=$(grep -E 'date \+%Y' "$NEWCHANGE_SRC" | grep -vcE 'date -u \+%Y' || true)
  report "T25 TC-1109 no bare date +%Y in new-change.sh (all -u)" 0 "$_bare_date"
  # v3.62.2 (CHG-082)：本节后半主题=批次入批默认——撤夹具豁免（new-change 的
  # 批/独立分流同样读该开关）；CHG-930 专属目录 begin 属脚手架流主题，临时前缀豁免。
  unset AGENT_GUARD_ALLOW_INDEPENDENT
  # 夹具内联最小入口模板（内容契约由 audit-standards-src pin 覆盖；此处测脚手架逻辑）
  seed_entry_templates 意图 '__RISK__' 'open' '沟通稿（§2.17.2d 骨架）' '<!-- 机校标记：确认达成后追加 确认状态 行 -->' ' (__RISK__)' '（§2.2 输入契约）'

  scripts/new-change CHG-930 --risk L1 >/dev/null 2>&1
  report "T25 dedicated scaffold exits 0" 0 $?
  report "T25 wave1 creates three entry files" 3 "$(ls docs/changes/CHG-930/*.md docs/changes/CHG-930/*.json 2>/dev/null | wc -l | tr -d ' ')"
  check_output "T25 id substituted in governance" '"change_id": "CHG-930"' "$(cat docs/changes/CHG-930/00-governance.json)"
  out=$(scripts/new-change CHG-930 --risk L1 2>&1 || true)
  check_output "T25 wave2 withheld before confirmation (NC-E09)" "NC-E09" "$out"
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-930/00.5-communication.md
  scripts/new-change CHG-930 --risk L1 >/dev/null 2>&1
  report "T25 wave2 scaffolded after confirmation" 0 $?
  report "T25 full eight entry files" 8 "$(ls docs/changes/CHG-930/*.md docs/changes/CHG-930/*.json 2>/dev/null | wc -l | tr -d ' ')"
  check_output "T25 risk substituted in spec" "L1" "$(cat docs/changes/CHG-930/01-spec.md)"
  # v3.62.2: owner 校验主题（非落位）——临时前缀豁免使 owner 检查成为决定性失败
  out=$(AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-930 2>&1 || true)
  check_output "T25 PENDING owners rejected by begin" "must name a concrete owner" "$out"
  sed -i '' 's/PENDING/op\/s-930/g; s/"review_owner": "op\/s-930"/"review_owner": "op\/s-r"/' docs/changes/CHG-930/00-governance.json 2>/dev/null \
    || sed -i 's/PENDING/op\/s-930/g; s/"review_owner": "op\/s-930"/"review_owner": "op\/s-r"/' docs/changes/CHG-930/00-governance.json
  # v3.62.2: 脚手架流主题（非落位）——CHG-930 为专属目录 L1，临时前缀豁免过 E86
  AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-930 >/dev/null 2>&1
  report "T25 filled scaffold passes begin (A-layer satisfied by skeleton)" 0 $?

  mkdir -p "docs/changes/BATCH-$(date -u +%Y%m%d)"
  printf '# intent\n## CHG-931\n## 预期结果\n## 开放问题\n' > "docs/changes/BATCH-$(date -u +%Y%m%d)/00-intent.md"
  printf '{"change_id": "CHG-931", "risk_level": "L0", "spec_author": "op/s-x", "implementation_owner": "op/s-x", "test_owner": "t/x", "review_owner": "r/x"}\n' > "docs/changes/BATCH-$(date -u +%Y%m%d)/00-governance.json"
  scripts/new-change CHG-932 --risk L0 >/dev/null 2>&1
  report "T25 batch-join exits 0" 0 $?
  report "T25 no dedicated dir for batch member" 0 "$(test ! -e docs/changes/CHG-932; echo $?)"
  grep -q '^## CHG-932' "docs/changes/BATCH-$(date -u +%Y%m%d)/00.5-communication.md"
  report "T25 batch wave1 carries ## CHG-932 anchor in 00.5" 0 $?
  out=$(scripts/new-change CHG-932 --risk L0 2>&1 || true)
  check_output "T25 wave2 withheld in batch before confirmation" "NC-E09" "$out"
  printf '\n- 确认状态：已整体确认\n' >> "docs/changes/BATCH-$(date -u +%Y%m%d)/00.5-communication.md"
  scripts/new-change CHG-932 --risk L0 >/dev/null 2>&1
  report "T25 batch wave2 after confirmation" 0 $?
  grep -q '^## CHG-932' "docs/changes/BATCH-$(date -u +%Y%m%d)/01-spec.md"
  report "T25 batch shared file carries ## CHG-932 anchor" 0 $?
  report "T25 governance.json gains one line per member" 2 "$(wc -l < "docs/changes/BATCH-$(date -u +%Y%m%d)/00-governance.json" | tr -d ' ')"
  out=$(scripts/new-change CHG-932 --risk L0 2>&1 || true)
  check_output "T25 duplicate id in batch refused" "fully scaffolded" "$out"
  out=$(scripts/new-change CHG-933 --risk L2 2>&1 || true)
  report "T25 L2 on a batch day goes dedicated (exit 0)" 0 $?
  report "T25 L2 dir is dedicated" 0 "$(test -d docs/changes/CHG-933; echo $?)"
  AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/new-change CHG-934 --risk L0 >/dev/null 2>&1
  report "T25 ALLOW_INDEPENDENT escapes to dedicated dir" 0 "$(test -d docs/changes/CHG-934; echo $?)"
  out=$(scripts/new-change CHG-935 2>&1 || true)
  check_output "T25 missing --risk refused" "--risk L0|L1|L2|L3 required" "$out"
  out=$(scripts/new-change CHG-936 --risk L9 2>&1 || true)
  check_output "T25 invalid risk refused" "--risk L0|L1|L2|L3 required" "$out"

  # v3.62.0（CHG-080/REQ-1022）：NC-E10 拆分——gate 缺失=NC-E10，check-confirm 执行失败（rc 非 0/1）=NC-E11；
  # 批/独立两分支共用 confirm_gate_run/die_check_confirm_failed（文案单源，逐字一致）。
  # 独立分支取 L2（批次日 L2 恒走 dedicated，T25 早前已断言）；批分支取 L0 入同日批。
  mv scripts/agent-gate scripts/agent-gate.away
  scripts/new-change CHG-937 --risk L2 >/dev/null 2>&1   # wave1 落盘，wave2 在确认门处停
  out=$(scripts/new-change CHG-937 --risk L2 2>&1 || true)
  check_output "T25 dedicated branch: missing gate dies NC-E10" "NC-E10: scripts/agent-gate not found" "$out"
  printf '#!/usr/bin/env bash\necho "stub check-confirm failure"\nexit 2\n' > scripts/agent-gate
  chmod +x scripts/agent-gate
  out=$(scripts/new-change CHG-937 --risk L2 2>&1 || true)
  check_output "T25 dedicated branch: check-confirm rc=2 dies NC-E11" "NC-E11: check-confirm failed .rc=2." "$out"
  mv scripts/agent-gate.away scripts/agent-gate
  mv scripts/agent-gate scripts/agent-gate.away
  scripts/new-change CHG-938 --risk L0 >/dev/null 2>&1   # 批分支 wave1 锚段落盘
  out=$(scripts/new-change CHG-938 --risk L0 2>&1 || true)
  check_output "T25 batch branch: missing gate dies NC-E10" "NC-E10: scripts/agent-gate not found" "$out"
  printf '#!/usr/bin/env bash\nexit 2\n' > scripts/agent-gate
  chmod +x scripts/agent-gate
  out=$(scripts/new-change CHG-938 --risk L0 2>&1 || true)
  check_output "T25 batch branch: check-confirm rc=2 dies NC-E11" "NC-E11: check-confirm failed .rc=2." "$out"
  mv scripts/agent-gate.away scripts/agent-gate
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-937/00.5-communication.md
  scripts/new-change CHG-937 --risk L2 >/dev/null 2>&1
  report "T25 dedicated wave2 completes once the gate is restored" 0 $?
  # v3.64.0⑦（CHG-086/REQ-1043~1045，TC-1112~1114）：docs 根解析链对齐五兄弟——
  # yml pin 命中 / env 优先 / fail-closed 三态；夹具自清理，不污染本节后续断言。
  printf 'paths:\n  docs: doc\n' > .agent-governance.yml
  out=$(scripts/new-change CHG-945 --risk L1 2>&1 || true)
  check_output "T25 TC-1114 yml pin to missing templates dies NC-E06" "NC-E06" "$out"
  check_output "T25 TC-1114 NC-E06 self-help names AGENT_GUARD_DOCS_DIR" "AGENT_GUARD_DOCS_DIR" "$out"
  check_output "T25 TC-1114 NC-E06 self-help names .agent-governance.yml" "agent-governance.yml" "$out"
  mkdir -p doc/templates/entry
  printf '# <__CHANGE_ID__> 意图\n## 预期结果\n## 开放问题\n## 目录落位\n- **目录落位**：独立目录（t）\n' > doc/templates/entry/00-intent.md
  printf '{"change_id": "__CHANGE_ID__", "risk_level": "__RISK__", "spec_author": "PENDING", "implementation_owner": "PENDING", "test_owner": "PENDING", "review_owner": "PENDING"}\n' > doc/templates/entry/00-governance.json
  printf '# <__CHANGE_ID__> 沟通稿\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n' > doc/templates/entry/00.5-communication.md
  scripts/new-change CHG-946 --risk L1 >/dev/null 2>&1
  report "T25 TC-1112 bare run honors yml pin paths.docs=doc" 0 $?
  report "T25 TC-1112 wave1 lands under doc/changes" 3 "$(ls doc/changes/CHG-946/*.md doc/changes/CHG-946/*.json 2>/dev/null | wc -l | tr -d ' ')"
  mkdir -p docs2/templates/entry && cp doc/templates/entry/* docs2/templates/entry/
  AGENT_GUARD_DOCS_DIR=docs2 scripts/new-change CHG-947 --risk L1 >/dev/null 2>&1
  report "T25 TC-1113 env AGENT_GUARD_DOCS_DIR overrides yml pin" 3 "$(ls docs2/changes/CHG-947/*.md docs2/changes/CHG-947/*.json 2>/dev/null | wc -l | tr -d ' ')"
  rm -rf doc docs2 .agent-governance.yml
else
  echo "SKIP T25: new-change.sh absent (bootstrap --guard 未安装) — 跳过脚手架 golden cases"
fi

}

