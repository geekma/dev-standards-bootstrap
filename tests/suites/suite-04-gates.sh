#!/usr/bin/env bash
# suite-04-gates.sh — domain suite module (v4.13.0, CHG-158)

section_T38() {
# ------------------------------------------------ T38 断言预算制静态 pin（v3.45.0，REQ-965/967）
# audit 源层脚本 ROOT 绑定真仓——soft 行为面由交付实跑承载（对齐 T35/REQ-964 偏离先例）；
# 此处 pin 机制存在性与接线，防静默移除。
report "T38 audit soft bucket defined" 1 "$(grep -c 'report_soft()' "$ROOT/tests/audit-standards-src.sh")"
report "T38 audit soft env switch" 1 "$(grep -c 'SOFT="${AGENT_GUARD_AUDIT_SOFT:-}"' "$ROOT/tests/audit-standards-src.sh")"
# v3.86.0 (CHG-113): CI must run the source audit hard. The old pin counted any
# mention of the variable — including the ci.yml comment — so it stayed green
# even if a future edit added `AGENT_GUARD_AUDIT_SOFT: 1` back.
report "T38 CI does not set soft mode" 0 "$(grep -cE '^[[:space:]]*AGENT_GUARD_AUDIT_SOFT:' "$ROOT/.github/workflows/ci.yml")"
report "T38 CI runs the source audit hard" 1 "$(grep -cF 'bash tests/audit-standards-src.sh' "$ROOT/.github/workflows/ci.yml")"
report "T38 assertion lifecycle section" 1 "$(grep -c '^### 5.3 断言生命周期' "$ROOT/MAINTAINER.md")"
report "T38 graded ambiguity rule" 1 "$(grep -c '歧义分级裁定' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"

}

section_T39() {
# ------------------------------------------------ T39 条款注册表形态（v3.46.0，REQ-968）
REG_T39="$ROOT/resources/CLAUSE_REGISTRY.md"
if [[ -s "$REG_T39" ]]; then
  report "T39 registry schema header" 1 "$(grep -c '权威关系声明' "$REG_T39")"
  # v3.78.0 (CHG-102): 64 rows — R64（冻结树并行派发）joins the registry.
  # v3.98.0 (CHG-137): 73 rows — R72/R73（subagent 硬预算/评审修复批验证）join.
  # v3.99.1 (CHG-141): R82-R84（E104 词表/E107 自产标记/三查+判定卡）join — 84 rows.
  report "T39 registry row count" 84 "$(grep -cE '^\| R[0-9]+[[:space:]]*\|' "$REG_T39")"
  report "T39 Rxx numbering continuous" 0 "$(awk -F'|' '/^\| R[0-9]+/{gsub(/[[:space:]]/,"",$2); n=substr($2,2)+0; if(n!=prev+1)bad++; prev=n} END{print bad+0}' "$REG_T39")"
  report "T39 labels in closed vocab" 0 "$(grep -E '^\| R[0-9]+' "$REG_T39" | awk -F'|' '{gsub(/[[:space:]]/,"",$5); if($5!="L0-bugfix"&&$5!="L1-standards"&&$5!="L2-architecture"&&$5!="L3-critical"&&$5!="universal")bad++} END{print bad+0}')"
  for t39_t in "L0-bugfix:12" "L1-standards:9" "L2-architecture:6" "L3-critical:3" "universal:12"; do
    t39_lab="${t39_t%%:*}"; t39_min="${t39_t##*:}"
    t39_n=$(grep -E '^\| R[0-9]+' "$REG_T39" | awk -F'|' -v l="$t39_lab" '{gsub(/[[:space:]]/,"",$5); if($5==l)n++} END{print n+0}')
    report "T39 type minimum $t39_lab >= $t39_min" 1 "$([[ "$t39_n" -ge "$t39_min" ]] && echo 1 || echo 0)"
  done
  t39_bad=0
  while IFS= read -r loc; do
    p="${loc%%::*}"; a="${loc#*::}"
    t39_file=""
    for t39_d in "$ROOT" "$ROOT/resources" "$ROOT/docs"; do
      [[ -f "$t39_d/$p" ]] && { t39_file="$t39_d/$p"; break; }
    done
    c=$(grep -cF -- "$a" "$t39_file" 2>/dev/null || echo 0)
    [[ "$c" == "1" ]] || t39_bad=$((t39_bad+1))
  done < <(grep -E '^\| R[0-9]+' "$REG_T39" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$4); print $4}')
  report "T39 all anchors resolve uniquely" 0 "$t39_bad"
  report "T39 generator present" 1 "$(test -x "$ROOT/resources/templates/generate-reading-pack.sh" && echo 1 || echo 0)"
else
  echo "SKIP T39: CLAUSE_REGISTRY.md absent — 跳过注册表 golden cases"
fi

}

section_T40() {
# ------------------------------------------------ T40 阅读包生成器多态（v3.46.0，REQ-969/970/971）
GEN_T40="$ROOT/resources/templates/generate-reading-pack.sh"
if [[ -x "$GEN_T40" ]]; then
  new_repo
  mkdir -p resources
  cp "$GEN_T40" resources/generate-reading-pack.sh && chmod +x resources/generate-reading-pack.sh
  printf '### 阶段 6\nfake clause body\n## 2.15 文档\nfake body 2\n## 2.7 发布\nrelease body\n### 0.5.1 风险\nrisk body\n### 1.1 编号\nnumbering body\n' > resources/fake-standards.md
  printf '路由行 content here\n' > resources/agents.md
  cat > resources/CLAUSE_REGISTRY.md <<'REG40'
| Rxx | 条款标题 | 权威落点 | 类型标签 | 强制级别 | 生命周期 |
| --- | --- | --- | --- | --- | --- |
| R01 | 缺陷主线 | resources/fake-standards.md::### 阶段 6 | L0-bugfix | 硬 | 结构 |
| R02 | 防覆盖 | resources/fake-standards.md::## 2.15 文档 | universal | 软 | 行为 |
| R03 | 前置 | resources/agents.md::路由行 | L1-standards | 硬 | 结构 |
| R04 | 发布 | resources/fake-standards.md::## 2.7 发布 | L2-architecture | 硬 | 结构 |
| R05 | 风险 | resources/fake-standards.md::### 0.5.1 风险 | L3-critical | 硬 | 结构 |
| R06 | 编号 | resources/fake-standards.md::### 1.1 编号 | L1-standards | 硬 | 结构 |
REG40
  out40="$(bash resources/generate-reading-pack.sh L0-bugfix 2>/dev/null)"; rc40=$?
  report "T40 normal generation exits 0" 0 "$rc40"
  report "T40 normal pack includes universal rows" 1 "$(printf '%s' "$out40" | grep -c '条款数：2')"
  report "T40 pack resolves line numbers" 1 "$(printf '%s' "$out40" | grep -c 'fake-standards.md:1')"
  out41="$(bash resources/generate-reading-pack.sh L1-standards 2>/dev/null)"; rc41=$?
  report "T40 L1 generation exits 0" 0 "$rc41"
  report "T40 L1 pack includes type rows" 1 "$(printf '%s' "$out41" | grep -c '条款数：3')"
  out42="$(bash resources/generate-reading-pack.sh L2-architecture 2>/dev/null)"; rc42=$?
  report "T40 L2 generation exits 0" 0 "$rc42"
  report "T40 L2 pack includes type rows" 1 "$(printf '%s' "$out42" | grep -c 'R04')"
  out43="$(bash resources/generate-reading-pack.sh L3-critical 2>/dev/null)"; rc43=$?
  report "T40 L3 generation exits 0" 0 "$rc43"
  report "T40 L3 pack includes type rows" 1 "$(printf '%s' "$out43" | grep -c 'R05')"
  bash resources/generate-reading-pack.sh L9-nope >/dev/null 2>&1
  report "T40 unknown type refused" 2 $?
  printf '| R01 | 坏锚 | resources/fake-standards.md::不存在的锚 | L0-bugfix | 硬 | 结构 |\n' > resources/reg-bad-miss.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-bad-miss.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 anchor miss fail-closed" 3 $?
  printf '### 阶段 6\nfake clause body\n### 阶段 6\nduplicate anchor body\n' > resources/dup-standards.md
  printf '| R01 | 重锚 | resources/dup-standards.md::### 阶段 6 | L0-bugfix | 硬 | 结构 |\n' > resources/reg-bad-dup.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-bad-dup.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 anchor not-unique fail-closed" 3 $?
  printf '| R01 | 缺文件 | resources/nofile.md::锚 | L0-bugfix | 硬 | 结构 |\n' > resources/reg-bad-file.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-bad-file.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 anchor file missing fail-closed" 3 $?
  printf '| R01 | 无关 | resources/fake-standards.md::### 阶段 6 | L2-architecture | 硬 | 结构 |\n' > resources/reg-empty.md
  CLAUSE_REGISTRY_FILE="$PWD/resources/reg-empty.md" bash resources/generate-reading-pack.sh L0-bugfix >/dev/null 2>&1
  report "T40 empty type set refused" 4 $?
  v40="$(bash resources/generate-reading-pack.sh L0-bugfix --verify 2>/dev/null)"; rc40=$?
  report "T40 verify green silent exit 0" "0:0" "$rc40:${#v40}"
  # profile 维度（CHG-147，FU-1012）：fixture 注册表带第 9 列「栈」。
  cat > resources/CLAUSE_REGISTRY.md <<'REG47'
| Rxx | 条款标题 | 权威落点 | 类型标签 | 强制级别 | 生命周期 | 机制 | 栈 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R01 | 缺陷主线 | resources/fake-standards.md::### 阶段 6 | L0-bugfix | 硬 | 结构 | 元 | |
| R02 | 防覆盖 | resources/fake-standards.md::## 2.15 文档 | universal | 软 | 行为 | 收口 | |
| R03 | 前端范式 | resources/fake-standards.md::### 0.5.1 风险 | L1-standards | 硬 | 结构 | 参照 | frontend |
| R04 | DB 规范 | resources/fake-standards.md::### 1.1 编号 | L1-standards | 硬 | 结构 | 收口 | backend |
REG47
  out47f="$(bash resources/generate-reading-pack.sh L1-standards --profile frontend 2>/dev/null)"; rc47f=$?
  report "T40 profile filter keeps generic+matching" "1:0" "$(printf '%s' "$out47f" | grep -c '条款数：'):$rc47f"
  report "T40 profile frontend count" 1 "$(printf '%s' "$out47f" | grep -c '条款数：2')"
  report "T40 profile excludes other-stack row" 0 "$(printf '%s' "$out47f" | grep -c 'R04')"
  report "T40 profile includes frontend row" 1 "$(printf '%s' "$out47f" | grep -c 'R03')"
  report "T40 profile header line" 1 "$(printf '%s' "$out47f" | grep -c '技术栈：frontend')"
  report "T40 gen-cmd line omits --verify in normal mode" 0 "$(printf '%s' "$out47n" | grep -c '生成命令.*--verify')"
  report "T40 gen-cmd line carries profile in profile mode" 1 "$(printf '%s' "$out47f" | grep -c '生成命令.*--profile frontend')"
  out47n="$(bash resources/generate-reading-pack.sh L1-standards 2>/dev/null)"; rc47n=$?
  report "T40 no-profile includes tagged rows (backward compat)" "1:0" "$(printf '%s' "$out47n" | grep -c '条款数：3'):$rc47n"
  bash resources/generate-reading-pack.sh L1-standards --profile nosql 2>/dev/null
  report "T40 unknown profile refused" 2 $?
  bash resources/generate-reading-pack.sh L1-standards --profile frontend --verify >/dev/null 2>&1
  report "T40 profile verify silent rc0" 0 $?
  bash resources/generate-reading-pack.sh L1-standards --verify --profile frontend >/dev/null 2>&1
  report "T40 flags any order rc0" 0 $?
  # 真实注册表 profile 校验（源仓根；临时仓内 ROOT 解析会指向夹具仓）
  ( cd "$ROOT" && bash resources/templates/generate-reading-pack.sh L2-architecture --profile frontend --verify >/dev/null 2>&1 )
  report "T40 real registry profile verify rc0" 0 $?
  _t40_fail=0
  for _t40_type in L0-bugfix L1-standards L2-architecture L3-critical universal; do
    ( cd "$ROOT" && bash resources/templates/generate-reading-pack.sh "$_t40_type" --verify >/dev/null 2>&1 ) || _t40_fail=$((_t40_fail + 1))
  done
  report "T40 TC-10020 all 5 pack types pass real registry verify" 0 "$_t40_fail"
  # 接线静态 pin（源仓）
  # CHG-102：generator 计数 1→2（usage 护栏入口清单 + install 落点）。
  report "T40 bootstrap ships generator" 2 "$(grep -c 'generate-reading-pack' "$ROOT/scripts/bootstrap.sh")"
  report "T40 bootstrap ships registry" 1 "$(grep -c 'resources/CLAUSE_REGISTRY.md' "$ROOT/scripts/bootstrap.sh")"
  report "T40 uninstall lists generator" 1 "$(grep -c 'generate-reading-pack' "$ROOT/resources/templates/uninstall-standards.sh")"
  report "T40 gate exempt generator" 1 "$(grep -c 'generate-reading-pack' "$ROOT/resources/templates/agent-gate.sh")"
  report "T40 AGENTS pack route row" 1 "$(grep -c 'generate-reading-pack' "$ROOT/resources/AGENTS.md")"
  report "T40 DS registry clause" 1 "$(grep -c '2.17.2c' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
  report "T40 changelog v3.46.0 row" 1 "$(cat "$ROOT/resources/STANDARDS_CHANGELOG.md" "$ROOT/resources/STANDARDS_CHANGELOG_ARCHIVE.md" | grep -c '^| v3.46.0 ')"
  report "T40 generator profile vocab declared" 1 "$(grep -c 'PROFILE_VOCAB=' "$ROOT/resources/templates/generate-reading-pack.sh")"
else
  echo "SKIP T40: generator absent — 跳过阅读包生成器 golden cases"
fi

}

section_T41() {
# ------------------------------------------------ T41 gate 码唯一性（v3.48.1，CHG-060；E15/E16 重号复发防线）
GATE_T41="$ROOT/resources/templates/agent-gate.sh"
STAGED_T41="$ROOT/resources/templates/lib-gate-staged.sh"
COLD_T41="$ROOT/resources/templates/lib-gate-cold.sh"
if [[ ! -s "$GATE_T41" ]]; then
  GATE_T41="$ROOT/scripts/agent-gate"
  STAGED_T41="$ROOT/scripts/lib-gate-staged.sh"
  COLD_T41="$ROOT/scripts/lib-gate-cold.sh"
fi
if [[ -s "$GATE_T41" ]]; then
  _t41_files=("$GATE_T41")
  [[ -s "$STAGED_T41" ]] && _t41_files+=("$STAGED_T41")
  [[ -s "$COLD_T41" ]] && _t41_files+=("$COLD_T41")
  report "T41 gate die E-codes unique" 0 "$(grep -hoE 'die "GATE-E[0-9]+: ' "${_t41_files[@]}" | sort | uniq -d | wc -l | tr -d ' ')"
else
  echo "SKIP T41: agent-gate absent — 跳过码唯一性 golden case"
fi

}

section_T42() {
# ------------------------------------------------ T42 沟通先行门（v3.52.0，REQ-988/990/991）
new_repo
GATE42_SRC="$ROOT/resources/templates/agent-gate.sh"
NC42_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -s "$GATE42_SRC" && -s "$NC42_SRC" ]]; then
  copy_gate_to scripts agent-gate
  cp "$NC42_SRC" scripts/new-change
  chmod +x scripts/new-change
  seed_project_masters
  # TC-1035: begin 拒——00.5 缺失（presence 层 E03 点名 00.5；seed 夹具含确认标记，删除后触发）
  seed_artifacts CHG-950 L1 claude/s-42
  rm docs/changes/CHG-950/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-950 2>&1 || true)
  check_output "T42 begin refuses missing 00.5 (E03 names the artifact)" "missing required artifact: docs/changes/CHG-950/00.5-communication.md" "$out"
  # TC-1036: begin 拒——确认记录节空（无标记）
  printf '# 00.5\n## 用户整体确认记录\n' > docs/changes/CHG-950/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-950 2>&1 || true)
  check_output "T42 begin refuses empty confirmation record" "GATE-E83" "$out"
  # TC-1037: begin 过——确认标记在位
  printf '# 00.5\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n' > docs/changes/CHG-950/00.5-communication.md
  scripts/agent-gate begin CHG-950 >/dev/null 2>&1
  report "T42 begin passes with confirmation marker" 0 $?
  # TC-1039: AGENT_GUARD_ALLOW_UNCONFIRMED 显式越过
  seed_artifacts CHG-953 L1 claude/s-42
  rm docs/changes/CHG-953/00.5-communication.md
  AGENT_GUARD_ALLOW_UNCONFIRMED=1 scripts/agent-gate begin CHG-953 >/dev/null 2>&1
  report "T42 ALLOW_UNCONFIRMED is the explicit bypass" 0 $?
  # TC-1043: L0 单行声明轻量通道（无确认记录节，仅声明行）
  seed_artifacts CHG-954 L0 claude/s-42
  printf -- '- **沟通确认**：未命中，不适用（文案级变更，无行为面）\n' > docs/changes/CHG-954/00.5-communication.md
  scripts/agent-gate begin CHG-954 >/dev/null 2>&1
  report "T42 L0 single-line declaration satisfies the gate" 0 $?
  # F2 修复负例：L0-only 声明通道不外溢到 L1/L2/L3
  seed_artifacts CHG-958 L1 claude/s-42
  printf -- '- **沟通确认**：未命中，不适用（文案级变更）\n' > docs/changes/CHG-958/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-958 2>&1 || true)
  check_output "T42 L0-only declaration refused for L1 (F2)" "L0-exclusive" "$out"
  # TC-1038: 批次成员按本变更锚点小节校验——兄弟成员的确认不外溢
  # P7（CHG-071）：本块成员差异（951 缺 00.5 锚 / 952 缺历史相似检索行）是测试点，不收拢 helper，保留原形独立演进。
  mkdir -p docs/changes/BATCH-99092501
  { printf '# intent\n'; printf '\n## CHG-951\n\n## 目录落位\n- **目录落位**：BATCH-YYYYMMDD（batch member）\n\n## 预期结果\n## 开放问题\n'; printf '\n## CHG-952\n\n## 目录落位\n- **目录落位**：BATCH-YYYYMMDD（batch member）\n\n## 预期结果\n## 开放问题\n'; } > docs/changes/BATCH-99092501/00-intent.md
  printf '{"change_id":"CHG-951","risk_level":"L1","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x"}\n{"change_id":"CHG-952","risk_level":"L1","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x"}\n' > docs/changes/BATCH-99092501/00-governance.json
  { printf '# spec\n\n## CHG-951\n\n- REQ-901: x\n'; printf '\n## CHG-952\n\n- REQ-902: x\n'; } > docs/changes/BATCH-99092501/01-spec.md
  { printf '# impact\n\n## CHG-951\n\n## 业务影响\n## 技术影响\n## 风险\n## 回滚策略\n延伸发现：未发现\n历史相似检索：未命中（x）\n'; printf '\n## CHG-952\n\n## 业务影响\n## 技术影响\n## 风险\n## 回滚策略\n延伸发现：未发现\n'; } > docs/changes/BATCH-99092501/02-code-impact-analysis.md
  { printf '# plan\n\n## CHG-951\n\n- DES-901: x\n## 技术选型\n备选: A vs B\n- **既有范式关系**：未命中（纯新增无同族实现）\n'; printf '\n## CHG-952\n\n- DES-902: x\n## 技术选型\n备选: A vs B\n'; } > docs/changes/BATCH-99092501/03-modification-plan.md
  { printf '# tasks\n\n## CHG-951\n\n- T-901: x（依赖: 无；里程碑: M1）\n- 评审输入: x\n'; printf '\n## CHG-952\n\n- T-902: x（依赖: 无；里程碑: M1）\n- 评审输入: x\n'; } > docs/changes/BATCH-99092501/03.5-tasks.md
  { printf '# tests\n\n## CHG-951\n\n- TC-901: x\n覆盖维度: 正常流\n- SC-901: x\n'; printf '\n## CHG-952\n\n- TC-902: x\n覆盖维度: 正常流\n- SC-902: x\n'; } > docs/changes/BATCH-99092501/04-test-scripts.md
  { printf '# comm\n\n## CHG-952\n\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n- 确认状态：已整体确认\n'; } > docs/changes/BATCH-99092501/00.5-communication.md
  out=$(scripts/agent-gate begin CHG-951 2>&1 || true)
  check_output "T42 batch member without own 00.5 anchor refused" "GATE-E83" "$out"
  scripts/agent-gate begin CHG-952 >/dev/null 2>&1
  report "T42 batch member with own anchor passes" 0 $?
  # TC-1040/1041/1042: new-change 两段式（wave1 三件 → 确认后补齐 → 越权旗标）
  seed_entry_templates intent '' comm '<!-- 标记待追加 -->' '' '' ''
  scripts/new-change CHG-955 --risk L1 >/dev/null 2>&1
  report "T42 wave1-only three files" 3 "$(ls docs/changes/CHG-955/*.md docs/changes/CHG-955/*.json 2>/dev/null | wc -l | tr -d ' ')"
  out=$(scripts/new-change CHG-955 --risk L1 2>&1 || true)
  check_output "T42 re-entry refuses before confirmation (NC-E09)" "NC-E09" "$out"
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-955/00.5-communication.md
  scripts/new-change CHG-955 --risk L1 >/dev/null 2>&1
  report "T42 wave2 scaffolded after confirmation" 0 $?
  report "T42 full eight entry files" 8 "$(ls docs/changes/CHG-955/*.md docs/changes/CHG-955/*.json 2>/dev/null | wc -l | tr -d ' ')"
  scripts/new-change CHG-956 --risk L1 --allow-unconfirmed >/dev/null 2>&1
  report "T42 allow-unconfirmed scaffolds all eight" 8 "$(ls docs/changes/CHG-956/*.md docs/changes/CHG-956/*.json 2>/dev/null | wc -l | tr -d ' ')"
  # TC-1043（new-change 侧）：L0 声明解锁 wave2
  scripts/new-change CHG-957 --risk L0 >/dev/null 2>&1
  printf -- '- **沟通确认**：未命中，不适用（文案级变更）\n' >> docs/changes/CHG-957/00.5-communication.md
  scripts/new-change CHG-957 --risk L0 >/dev/null 2>&1
  report "T42 L0 declaration unblocks wave2" 8 "$(ls docs/changes/CHG-957/*.md docs/changes/CHG-957/*.json 2>/dev/null | wc -l | tr -d ' ')"
  # F2 镜像（new-change 侧）：L1 声明行不解锁 wave2（confirm_ok L0-exclusive）
  scripts/new-change CHG-959 --risk L1 >/dev/null 2>&1
  printf -- '- **沟通确认**：未命中，不适用（文案级变更）\n' >> docs/changes/CHG-959/00.5-communication.md
  out=$(scripts/new-change CHG-959 --risk L1 2>&1 || true)
  check_output "T42 L1 declaration does not unblock wave2 (NC-E09)" "NC-E09" "$out"
  # TC-1044 实证半边：stamp --all 给 00.5 盖溯源块
  bash "$ROOT/resources/templates/stamp-provenance.sh" --all CHG-955 >/dev/null 2>&1
  grep -q '^<!-- provenance$' docs/changes/CHG-955/00.5-communication.md
  report "T42 stamp --all covers 00.5" 0 $?
  # TC-1044: 入口模板在位 + 机校锚点串在模板中
  grep -q "用户整体确认记录" "$ROOT/resources/templates/entry/00.5-communication.md"
  report "T42 entry 00.5 template ships with confirmation anchor" 0 $?
  grep -q "00.5-communication.md" "$ROOT/scripts/bootstrap.sh"
  report "T42 bootstrap entry list carries 00.5" 0 $?
else
  echo "SKIP T42: agent-gate/new-change absent (bootstrap --guard 未安装) — 跳过沟通先行门 golden cases"
fi

}

section_T43() {
# ------------------------------------------------ T43 分阶段评审留痕（v3.53.0，REQ-993/994）
STD_T43="$ROOT/resources/DEVELOPMENT_STANDARDS.md"
AG_T43="$ROOT/resources/AGENTS.md"
if [[ -s "$STD_T43" ]]; then
  grep -q "分阶段评审留痕（v3.53.0，REQ-993）" "$STD_T43"
  report "T43 DS staged-review clause anchor" 0 $?
  grep -q "分阶段评审留痕核对" "$STD_T43"
  report "T43 DS stage-8 backfill-check row" 0 $?
  grep -q "缺陷轨机校点=绑定 CHG 的 begin" "$STD_T43"
  report "T43 bug-track machine checkpoint sentence (FU-902)" 0 $?
  grep -q '禁止"只做阶段 8 终审"的收敛执行' "$AG_T43"
  report "T43 AGENTS staged-review hard directive" 0 $?
  grep -q '分阶段评审\*\*：未命中，不适用' "$STD_T43"
  report "T43 L0/L1 merged-review declaration form" 0 $?
else
  echo "SKIP T43: DEVELOPMENT_STANDARDS.md absent — 跳过分阶段评审留痕 golden cases"
fi

}

section_T44() {
# ------------------------------------------------ T44 历史相似检索机校（v3.54.0，REQ-998）+ 补测（REQ-999）
GATE44_SRC="$ROOT/resources/templates/agent-gate.sh"
NC44_SRC="$ROOT/resources/templates/new-change.sh"
if [[ -s "$GATE44_SRC" ]]; then
  new_repo
  copy_gate_to scripts agent-gate
  cp "$NC44_SRC" scripts/new-change
  chmod +x scripts/new-change
  seed_entry_templates intent '' comm '' '' '' ''
  seed_project_masters
  # TC-1052: CHG 轨——02 无历史相似检索节且无未命中声明 → E84；有声明 → 过
  seed_artifacts CHG-970 L1 claude/s-44
  sed -i '' '/历史相似检索/d' docs/changes/CHG-970/02-code-impact-analysis.md 2>/dev/null || sed -i '/历史相似检索/d' docs/changes/CHG-970/02-code-impact-analysis.md
  # CHG-117: begin narrowed to the entry gate; E84 lives on the legacy full
  # check and the staged/stop delivery face. Pin it through the documented
  # compatibility switch (default-on narrowing is covered by T80).
  out=$(AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-970 2>&1 || true)
  check_output "T44 CHG track refuses 02 missing 历史相似检索 (E84)" "GATE-E84" "$out"
  printf '历史相似检索：未命中（根因关键词检索）\n' >> docs/changes/CHG-970/02-code-impact-analysis.md
  AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-970 >/dev/null 2>&1
  report "T44 CHG track passes with declaration line" 0 $?
  # TC-1053: BUG 轨——01-diagnosis 缺历史相似检索 → E81
  mkdir -p docs/bugs/BUG-970
  for d6 in 01-diagnosis 02-impact 03-test-plan 04-matrix 05-config 06-tasks; do printf '# %s\n' "$d6" > "docs/bugs/BUG-970/$d6.md"; done
  printf '延伸发现：未发现\n' >> docs/bugs/BUG-970/01-diagnosis.md
  seed_artifacts CHG-971 L0 claude/s-44
  printf '{"change_id":"CHG-971","risk_level":"L0","spec_author":"a/x","implementation_owner":"i/x","test_owner":"t/x","review_owner":"r/x","bug_ref":"BUG-970"}\n' > docs/changes/CHG-971/00-governance.json
  out=$(scripts/agent-gate begin CHG-971 2>&1 || true)
  check_output "T44 BUG track refuses 01-diagnosis missing 历史相似检索 (E81)" "GATE-E81.*延伸发现" "$out"
  printf '历史相似检索：未命中（根因关键词检索）\n' >> docs/bugs/BUG-970/01-diagnosis.md
  scripts/agent-gate begin CHG-971 >/dev/null 2>&1
  report "T44 BUG track passes with declaration line" 0 $?
  # TC-1050: staged 豁免态——ALLOW_UNCONFIRMED 下 00.5 缺省不阻 complete 判定
  seed_artifacts CHG-972 L1 claude/s-44
  rm -rf docs/changes/CHG-970 docs/changes/CHG-971 docs/bugs   # staged 判 complete-any：清掉其他完整目录隔离本例
  rm docs/changes/CHG-972/00.5-communication.md   # 工作树缺（complete 检查扫工作树）
  printf '#!/usr/bin/env bash\n' > scripts/probe-972.sh   # staged 的 complete 检查只对 code 文件触发（code without docs）
  git add scripts/probe-972.sh >/dev/null 2>&1   # 只 staged code——seed 的 md 不入 index（否则 docs_changed=true 绕过 complete 分支）
  scripts/agent-gate --stage staged >/dev/null 2>&1
  report "T44 staged code-only with worktree-missing 00.5 is refused (no bypass)" 2 $?
  out=$(AGENT_GUARD_ALLOW_UNCONFIRMED=1 scripts/agent-gate --stage staged 2>&1 || true)
  report "T44 staged passes under ALLOW_UNCONFIRMED" 0 $?
  # TC-1051: 批次成员自锚点在、节内确认记录空 → E83
  rm -rf docs/changes/CHG-973 docs/changes/CHG-974   # seed 专用目录会抢 change_dir 解析（独立目录永远优先）——只留批次形态
  mkdir -p docs/changes/BATCH-990944
  for f in 00-intent.md 00-governance.json 00.5-communication.md 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md; do : > "docs/changes/BATCH-990944/$f"; done
  for id in CHG-973 CHG-974; do seed_batch_member docs/changes/BATCH-990944 "$id"; done
  out=$(scripts/agent-gate begin CHG-973 2>&1 || true)
  check_output "T44 own anchor with empty confirmation refused (E83)" "GATE-E83" "$out"
  # TC-1055: confirm_ok 兄弟名单外溢负例（v3.54 收口）——兄弟有确认、本成员无 → wave2 仍拒
  scripts/new-change CHG-975 --risk L1 >/dev/null 2>&1
  printf -- '- 确认状态：已整体确认\n' >> docs/changes/CHG-975/00.5-communication.md
  scripts/new-change CHG-975 --risk L1 >/dev/null 2>&1
  report "T44 sibling-confirmed member scaffolds wave2" 8 "$(ls docs/changes/CHG-975/*.md docs/changes/CHG-975/*.json 2>/dev/null | wc -l | tr -d ' ')"
  scripts/new-change CHG-976 --risk L1 >/dev/null 2>&1
  out=$(scripts/new-change CHG-976 --risk L1 2>&1 || true)
  check_output "T44 no cross-member confirmation bleed (NC-E09)" "NC-E09" "$out"
  # TC-1056/1057: check-confirm 子命令 exit 协议（0/1/2）
  scripts/agent-gate check-confirm CHG-975 >/dev/null 2>&1
  report "T44 check-confirm exits 0 when confirmed" 0 $?
  scripts/agent-gate check-confirm CHG-976 >/dev/null 2>&1
  report "T44 check-confirm exits 1 when unconfirmed" 1 $?
  scripts/agent-gate check-confirm 2>/dev/null
  report "T44 check-confirm missing id exits 2 (non-die shape)" 2 $?
else
  echo "SKIP T44: agent-gate absent — 跳过历史相似检索机校 golden cases"
fi

}

section_T46() {
# ------------------------------------------------ T46 07 署名/溯源机校（v3.56.0，REQ-1005）
GATE46_SRC="$ROOT/resources/templates/agent-gate.sh"
if [[ -s "$GATE46_SRC" ]]; then
  new_repo
  copy_gate_to scripts agent-gate
  seed_project_masters
  # TC-1061: 07 含签名行+task- id → stop 过（顺序：先 begin——09 落盘即闭合 E72）
  seed_begin CHG-980 L1 claude/s-46
  report "T46 fixture begins clean" 0 $?
  printf '## CHG-980 评审\n\n- 评审主体：agent-platform / llm-model / task-ses_0000000000fixture00000000\n- 结论：APPROVE\n- **发现处置**：未命中，不适用（T46 署名夹具，无发现）\n' > docs/changes/CHG-980/07-review-report.md
  printf '# coding\n实现记录\n' > docs/changes/CHG-980/04.5-coding-record.md
  printf '# results\nTests run: 1, Failures: 0\n' > docs/changes/CHG-980/05-test-results.md
  printf '# deploy\n未命中，不适用\n' > docs/changes/CHG-980/06.5-deployment-config.md
  printf '# delivery\n\n### 遗留\n- FU-980：T46 夹具（无实际遗留项，占位满足 E46 形态）\n' > docs/changes/CHG-980/06-delivery-summary.md
  printf '# changelog\n\n## CHG-980\n#### 项目总册回填清单\n- [x] P00 未命中（T46 夹具）\n- [x] P01 未命中（T46 夹具）\n- [x] P02 未命中（T46 夹具）\n- [x] P03 未命中（T46 夹具）\n- [x] P04 未命中（T46 夹具）\n- [x] P05 未命中（T46 夹具）\n- [x] P06 未命中（T46 夹具）\n- [x] P07 未命中（T46 夹具）\n- [x] P08 未命中（T46 夹具）\n- [x] P09 未命中（T46 夹具）\n- [x] P10 已回填（T46 夹具行）\n- [x] P11 已回填（T46 夹具行）\n- [x] P12 已回填（T46 夹具行）\n#### 执行记录（ReAct）\nObservation\n' > docs/changes/CHG-980/09-changelog.md
  printf '#!/usr/bin/env bash\n' > scripts/probe-980.sh   # stop 的 working_code_changed 前提
  bash "$ROOT/resources/templates/stamp-provenance.sh" --all CHG-980 >/dev/null 2>&1   # E19 溯源章
  scripts/agent-gate --stage stop >/dev/null 2>&1
  report "T46 stop passes with signature+task id" 0 $?
  # TC-1062: 签名缺 task- id → E85 拒
  sed -i '' 's|task-ses_0000000000fixture00000000|self-reviewed|' docs/changes/CHG-980/07-review-report.md 2>/dev/null || sed -i 's|task-ses_0000000000fixture00000000|self-reviewed|' docs/changes/CHG-980/07-review-report.md
  out=$(scripts/agent-gate --stage stop 2>&1 || true)
  check_output "T46 stop refuses 07 without traceable task id (E85)" "GATE-E85" "$out"
else
  echo "SKIP T46: agent-gate absent — 跳过 07 署名机校 golden cases"
fi

}

section_T47() {
# ------------------------------------------------ T47 目录落位声明+E83 五要素（v3.60.0，REQ-1009）
GATE47_SRC="$ROOT/resources/templates/agent-gate.sh"
if [[ -s "$GATE47_SRC" ]]; then
  new_repo
  copy_gate_to scripts agent-gate
  seed_project_masters
  # v3.62.2 (CHG-082): 本节主题=目录落位执法——显式撤掉 new_repo 的夹具豁免，
  # 让 E86 正反向新分支可见；个别非落位用例按需临时前缀豁免。
  unset AGENT_GUARD_ALLOW_INDEPENDENT
  # TC-1063: begin 拒——00-intent 缺落位声明（E86）
  seed_artifacts CHG-990 L1 claude/s-47
  sed -i '' '/目录落位/d' docs/changes/CHG-990/00-intent.md 2>/dev/null || sed -i '/目录落位/d' docs/changes/CHG-990/00-intent.md
  out=$(scripts/agent-gate begin CHG-990 2>&1 || true)
  check_output "T47 begin refuses missing placement declaration (E86)" "GATE-E86" "$out"
  # TC-1064: begin 拒——L2 声明 BATCH（风险级一致性）
  seed_begin CHG-991 L2 claude/s-47 tester reviewer
  sed -i '' 's/独立目录（single low-risk fixture）/BATCH-YYYYMMDD（wrong for L2）/' docs/changes/CHG-991/00-intent.md 2>/dev/null || sed -i 's/独立目录（single low-risk fixture）/BATCH-YYYYMMDD（wrong for L2）/' docs/changes/CHG-991/00-intent.md
  out=$(scripts/agent-gate begin CHG-991 2>&1 || true)
  check_output "T47 begin refuses L2 declaring BATCH placement (E86)" "GATE-E86" "$out"
  # TC-1065: begin 拒——非 L0 00.5 缺「风险」锚点（E83 五要素扩展）
  # v3.62.2: E86 先于 E83 落 die（声明级反向分支），为保 E83 为决定性失败，
  # 该用例临时前缀豁免（主题=E83，非落位）。
  seed_artifacts CHG-992 L1 claude/s-47
  sed -i '' '/^## 风险$/,/^risk: r$/d' docs/changes/CHG-992/00.5-communication.md 2>/dev/null || sed -i '/^## 风险$/,/^risk: r$/d' docs/changes/CHG-992/00.5-communication.md
  out=$(AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-992 2>&1 || true)
  check_output "T47 begin refuses 00.5 missing risk anchor (E83 five-element)" "GATE-E83.*风险" "$out"
  # TC-1066: 正例回归——L2 声明独立 + 五锚点齐 → begin 绿
  seed_begin CHG-993 L2 claude/s-47 tester reviewer
  scripts/agent-gate begin CHG-993 >/dev/null 2>&1
  report "T47 L2 declaring independent placement with full anchors begins" 0 $?
  # TC-1067 (v3.61.0 FU-912): begin 拒——批成员缺自锚段回落整文件=兄弟声明可替过（fail-open），
  # 现收紧 fail-closed；00.5 锚段在位使 E83 放行，E86 成唯一决定性失败
  seed_batch_artifacts BATCH-20260101 CHG-994:L0 CHG-995:L0
  sed -i '' '/^## CHG-995$/d' docs/changes/BATCH-20260101/00-intent.md 2>/dev/null || sed -i '/^## CHG-995$/d' docs/changes/BATCH-20260101/00-intent.md
  out=$(scripts/agent-gate begin CHG-995 2>&1 || true)
  check_output "T47 begin refuses batch member without own anchor section (E86 fail-closed)" "GATE-E86.*missing anchor section" "$out"
  report "T47 batch member with own anchor still begins (no spillover to sibling)" 0 $?
  scripts/agent-gate begin CHG-994 >/dev/null 2>&1
  # TC-1068 (v3.61.0): 正例回归——独立目录单成员无自锚段 → 整文件回落保留（防过收紧）
  # v3.62.2 (CHG-082): L0/L1 独立目录已非法（首个即建），回落语义的载体改用
  # L2 独立目录——E86 不涉 L2，回落正例语义原样保留。
  seed_begin CHG-996 L2 claude/s-47 tester reviewer
  scripts/agent-gate begin CHG-996 >/dev/null 2>&1
  report "T47 independent single-member change without anchor section falls back (v3.61.0 keeps fallback)" 0 $?
  # TC-1084 (v3.62.2, CHG-082 REQ-1028): E86 反向——无批 + 当日首个 L0/L1 声明独立 → begin 拒
  seed_artifacts CHG-997 L1 claude/s-47
  out=$(scripts/agent-gate begin CHG-997 2>&1 || true)
  check_output "T47 begin refuses first-of-day L0/L1 declaring independent placement (E86 reverse)" "GATE-E86.*first L0/L1 change of the day creates the day batch" "$out"
  # TC-1086 (v3.62.2): escape 两向通用——反向显式豁免后 begin 绿
  AGENT_GUARD_ALLOW_INDEPENDENT=1 scripts/agent-gate begin CHG-997 >/dev/null 2>&1
  report "T47 escape admits a first-of-day L0/L1 independent change (explicit bypass)" 0 $?
  # TC-1085 (v3.62.2): E86 正向声明级——同日批目录已存在 + L1 声明独立 → begin 拒
  # （E86 措辞而非 E73：声明级校验在 validate_governance_state，先于 E73 的目录实况拦截）
  mkdir -p "docs/changes/BATCH-$(date -u +%Y%m%d)"
  seed_artifacts CHG-998 L1 claude/s-47
  out=$(scripts/agent-gate begin CHG-998 2>&1 || true)
  check_output "T47 begin refuses L0/L1 declaring independent while same-day batch exists (E86 forward)" "GATE-E86.*same-day L0/L1 changes must join the batch" "$out"
else
  echo "SKIP T47: agent-gate absent — 跳过落位声明 golden cases"
fi

}

section_T48() {
# ------------------------------------------------ T48 版本链同源 + 批次时序措辞（v3.62.0，REQ-1018/1020）
# TC-1073: four-chain version sameness (SKILL/AGENTS/DS/CHANGELOG) + wording
# "first-of-day creates the batch" present, old "same-day-many" trigger gone
# CHG-096: TC-1073 version pins recalibrated v3.72.0→v3.73.0 (four-chain bump).
# CHG-098: TC-1073 pins recalibrated v3.73.0→v3.74.0 (four-chain bump).
# CHG-100: TC-1073 pins recalibrated v3.75.0→v3.76.0 (four-chain bump).
# CHG-101: TC-1073 pins recalibrated v3.76.0→v3.77.0 (four-chain bump).
# CHG-102: TC-1073 pins recalibrated v3.77.0→v3.78.0 (four-chain bump). The two
# footer labels no longer spell a version literal — a label carrying a stale
# number was itself a drift source (renamed to "carries the current version").
report "T48 TC-1073 SKILL version line bumped" 1 "$(grep -cF "version: $CURRENT_VERSION" "$ROOT/SKILL.md")"
report "T48 TC-1073 SKILL carries v3.67.0 in prose (previous-version historical mentions preserved)" 3 "$(grep -cF 'v3.67.0' "$ROOT/SKILL.md")"
report "T48 TC-1073 DS footer carries the current version" 1 "$(grep -cF "规范版本：v$CURRENT_VERSION" "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 AGENTS footer carries the current version" 1 "$(grep -cF "当前对应规范版本：v$CURRENT_VERSION" "$ROOT/resources/AGENTS.md")"
# v3.72.0 erratum (CHG-095, TC-1275): v3.70.0 is no longer the top row (v3.72.0
# is), but its history row must stay present — grep pattern unchanged, label now
# states the superseded-row semantics.
report "T48 TC-1073 CHANGELOG v3.70.0 row exists (superseded by current top)" 1 "$(cat "$ROOT/resources/STANDARDS_CHANGELOG.md" "$ROOT/resources/STANDARDS_CHANGELOG_ARCHIVE.md" | grep -c '^| v3.70.0 ')"
report "T48 TC-1073 DS §1.1 first-of-day creates batch" 2 "$(grep -cF '当天 L0/L1 变更/缺陷首个即建' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 DS wording spots updated" 3 "$(grep -cF '首个即建' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 AGENTS gate section wording updated" 1 "$(grep -cF '当天 L0/L1 变更/缺陷首个即建' "$ROOT/resources/AGENTS.md")"
report "T48 TC-1073 README (en) wording updated" 1 "$(grep -cF 'first L0/L1** change (or defect) of the day creates' "$ROOT/README.md")"
report "T48 TC-1073 README (zh) wording updated" 1 "$(grep -cF '当天**首个 L0/L1** 变更/缺陷**即建**' "$ROOT/README.zh-CN.md")"
report "T48 TC-1073 entry template wording updated" 1 "$(grep -cF '当天首个 L0/L1 即入批' "$ROOT/resources/templates/entry/00-intent.md")"
report "T48 TC-1073 old same-day-many trigger gone from DS" 0 "$(grep -c '同一天\*\*多个\*\*.*默认共用' "$ROOT/resources/DEVELOPMENT_STANDARDS.md")"
report "T48 TC-1073 old same-day-many trigger gone from AGENTS" 0 "$(grep -c '同一天多个 L0/L1 默认共落' "$ROOT/resources/AGENTS.md")"
report "T48 TC-1073 README version strings bumped" 8 "$(grep -c 'v3.67.0' "$ROOT/README.md" "$ROOT/README.zh-CN.md" | awk -F: '{s+=$NF}END{print s}')"

}

