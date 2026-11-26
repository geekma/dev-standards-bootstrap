#!/usr/bin/env bash
# suite-07-adapt.sh — domain suite module (v4.13.0, CHG-158)

section_T63() {
# ------------------------------------------------ T63 CHG-102 新面 golden（v3.78.0，REQ-1129~1139）
# 四个面合并成节的原因：都属"本变更新增的断言面"，且各自小而独立（hook 是下发面、
# 评测面口径是行为面、UAC 形态是收口面、台账是回填面），单开四节只会摊薄 SECTIONS 可读性。
#   ①下发 hook golden（TC-1372）：教训 = `<githooks>/` 两个 hook 是**下发面**（bootstrap
#     --guard 复制），却长期没有 golden——模板被改动只靠安装清单行数旁证。而 hook 里的
#     调用串正是门禁的本地入口（`--stage ci --base` 分支门、`--stage commit-msg "$1"`
#     归属门）：漂移 = 本地静默放过，CI 才发现。锁四件事：落点 + 可执行 + 关键调用串 +
#     与源模板逐字节一致；另加非默认根用例（安装期路径改写必须进 hook 本体）。
#   ②评测面取样口径（TC-1358~1360）：原按源仓 `resources/**` 取样 → 目标仓面清单为空，
#     漂移告警**恒不触发**（fail-open）。三条用例 = 装点面可漂移 / `paths.docs` 真生效
#     （差分：改默认 docs 不翻、改 specs 才翻） / 源仓回落不回归。
#   ③UAC 并行形态（TC-1368/1369）：`-j` 只在**收口脚本内嵌全跑**打通，套件自身默认仍
#     串行（receipt 语义零触碰）；此处钉静态形态，行为等价由 T9 三连跑实证承载（05 证据）。
#   ④源层台账回填（TC-1374）：P10 缺口说明 + 回填行、P09 FU-902~945 块与 FU-943 承接行。
if [[ -f "$BOOT_SRC" ]]; then
  t63_tpl="$ROOT/resources/templates"
  t63_bt=$(mktemp -d)
  bash "$BOOT_SRC" --guard "$t63_bt" >/dev/null 2>&1
  report "T63 TC-1372 guard lands pre-push at <githooks>/ (executable)" 0 "$([[ -x "$t63_bt/.githooks/pre-push" ]] && echo 0 || echo 1)"
  report "T63 TC-1372 guard lands commit-msg at <githooks>/ (executable)" 0 "$([[ -x "$t63_bt/.githooks/commit-msg" ]] && echo 0 || echo 1)"
  report "T63 TC-1372 pre-push calls the strict branch gate" 1 "$(grep -cF 'agent-gate --stage ci --base' "$t63_bt/.githooks/pre-push")"
  report "T63 TC-1372 commit-msg forwards the message file to the gate" 1 "$(grep -cF 'agent-gate --stage commit-msg "$1"' "$t63_bt/.githooks/commit-msg")"
  report "T63 TC-1372 both hooks fail fast (set -euo pipefail)" 2 "$(grep -hcF 'set -euo pipefail' "$t63_bt/.githooks/pre-push" "$t63_bt/.githooks/commit-msg" | awk '{s+=$1} END{print s+0}')"
  cmp -s "$t63_tpl/pre-push" "$t63_bt/.githooks/pre-push"
  report "T63 TC-1372 installed pre-push is byte-identical to the shipped template" 0 $?
  cmp -s "$t63_tpl/commit-msg" "$t63_bt/.githooks/commit-msg"
  report "T63 TC-1372 installed commit-msg is byte-identical to the shipped template" 0 $?
  # v3.79.0 (CHG-103, REQ-1144): the fingerprint lib ships WITH run-tests.sh —
  # without it the target repo's receipt emitter degrades to empty fingerprints
  # (fast path dead on arrival). Pin: landed at <scripts>/, executable, and
  # byte-identical to the source-of-truth copy.
  report "T63 TC-1388 guard lands the fingerprint lib at <scripts>/ (executable)" 0 "$([[ -x "$t63_bt/scripts/lib-suite-tree-fingerprint.sh" ]] && echo 0 || echo 1)"
  cmp -s "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$t63_bt/scripts/lib-suite-tree-fingerprint.sh"
  report "T63 TC-1388 installed fingerprint lib is byte-identical to the source" 0 $?
  # 非默认 scripts 根：hook 本体必须按新根调门禁（安装期 transform，非运行期解析）
  t63_bt2=$(mktemp -d)
  bash "$BOOT_SRC" --guard --scripts-dir gov "$t63_bt2" >/dev/null 2>&1
  report "T63 TC-1372 custom scripts root follows into pre-push body" 1 "$(grep -cF 'gov/agent-gate --stage ci --base' "$t63_bt2/.githooks/pre-push")"
  report "T63 TC-1372 custom scripts root leaves no default-root call behind" 0 "$(grep -cF 'scripts/agent-gate' "$t63_bt2/.githooks/pre-push")"
  rm -rf "$t63_bt" "$t63_bt2"
else
  echo "SKIP T63 hook cases: bootstrap.sh 为 Skill 仓库安装器（不随 --guard 分发）"
fi

# ---- ② 评测面取样口径（TC-1358~1360，含 1359b 引号化取值）--------------------
t63_score="$ROOT/resources/templates/eval-rescore.sh"
[[ -f "$t63_score" ]] || t63_score="$ROOT/scripts/eval-rescore"
if [[ -f "$t63_score" ]]; then
  # 最小目标仓布局：装点治理文本 + 评测集（case 引用存在性由 eval-cases 派生，此处直接给）
  t63_seed() { # <dir> <docs_dir>
    mkdir -p "$1/.agent-state" "$1/$2"
    printf 'AGENTS.md\n' > "$1/AGENTS.md"
    printf 'standards-v1\n' > "$1/$2/DEVELOPMENT_STANDARDS.md"
    printf 'case_id\tsrc\tbug\tlayer\tlanding\tregression_ref\nC1\ta\tb\tc\td\tTC-1\n' > "$1/.agent-state/eval-cases.tsv"
  }
  t63_sha() { # <dir> <docs_dir>
    bash "$t63_score" --cases "$1/.agent-state/eval-cases.tsv" --face "$1" --dry-run 2>/dev/null \
      | grep -oE '"config_sha":"[^"]*"'
  }
  # TC-1358：装点面被改 → 漂移告警真的翻（改前这里恒不触发）
  t63r=$(mktemp -d); t63_seed "$t63r" docs
  bash "$t63_score" --cases "$t63r/.agent-state/eval-cases.tsv" --face "$t63r" --update-baseline >/dev/null 2>&1
  t63_sha_a=$(t63_sha "$t63r" docs)
  printf 'standards-v2\n' >> "$t63r/docs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r/.agent-state/eval-cases.tsv" --face "$t63r" >/dev/null 2>&1
  t63_stale_rc=$?
  report "T63 TC-1358 editing an installed docs face flips stale (rc 1)" 1 "$t63_stale_rc"
  report "T63 TC-1358 config_sha tracks the installed face content" 1 "$([[ -n "$t63_sha_a" && "$(t63_sha "$t63r" docs)" != "$t63_sha_a" ]] && echo 1 || echo 0)"
  rm -rf "$t63r"
  # TC-1359：`paths.docs: specs` 必须真生效——改默认 docs 不翻，改 specs 才翻（差分断言）
  t63r2=$(mktemp -d)
  t63_seed "$t63r2" specs
  mkdir -p "$t63r2/docs" && printf 'defaults-v1\n' > "$t63r2/docs/DEVELOPMENT_STANDARDS.md"
  printf 'paths:\n  docs: specs\n' > "$t63r2/.agent-governance.yml"
  bash "$t63_score" --cases "$t63r2/.agent-state/eval-cases.tsv" --face "$t63r2" --update-baseline >/dev/null 2>&1
  printf 'defaults-v2\n' >> "$t63r2/docs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2/.agent-state/eval-cases.tsv" --face "$t63r2" >/dev/null 2>&1
  report "T63 TC-1359 untouched default docs root does not flip stale" 0 $?
  printf 'specs-v2\n' >> "$t63r2/specs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2/.agent-state/eval-cases.tsv" --face "$t63r2" >/dev/null 2>&1
  report "T63 TC-1359 editing the yml-declared specs root flips stale" 1 $?
  rm -rf "$t63r2"
  # TC-1359b：yml 取值带引号（`docs: "specs"`）必须与裸值等价——留引号会让装点面全部落空
  # 并静默回落源仓路径（漂移告警仍恒不触发，与 REQ-1129 修的是同一失效类）。
  t63r2q=$(mktemp -d)
  t63_seed "$t63r2q" specs
  mkdir -p "$t63r2q/docs" && printf 'defaults-v1\n' > "$t63r2q/docs/DEVELOPMENT_STANDARDS.md"
  printf 'paths:\n  docs: "specs"\n' > "$t63r2q/.agent-governance.yml"
  bash "$t63_score" --cases "$t63r2q/.agent-state/eval-cases.tsv" --face "$t63r2q" --update-baseline >/dev/null 2>&1
  printf 'defaults-v2\n' >> "$t63r2q/docs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2q/.agent-state/eval-cases.tsv" --face "$t63r2q" >/dev/null 2>&1
  report "T63 TC-1359b quoted docs root ignores the default docs tree" 0 $?
  printf 'specs-v2\n' >> "$t63r2q/specs/DEVELOPMENT_STANDARDS.md"
  bash "$t63_score" --cases "$t63r2q/.agent-state/eval-cases.tsv" --face "$t63r2q" >/dev/null 2>&1
  report "T63 TC-1359b quoted docs root still flips stale" 1 $?
  rm -rf "$t63r2q"
  # TC-1360：源仓形态（只有 resources/**、无安装落点）→ 回落同名源路径，行为与变更前等价
  t63r3=$(mktemp -d)
  mkdir -p "$t63r3/.agent-state" "$t63r3/resources"
  printf 'src-agents\n' > "$t63r3/resources/AGENTS.md"
  printf 'src-standards\n' > "$t63r3/resources/DEVELOPMENT_STANDARDS.md"
  printf 'case_id\tsrc\tbug\tlayer\tlanding\tregression_ref\nC1\ta\tb\tc\td\tTC-1\n' > "$t63r3/.agent-state/eval-cases.tsv"
  t63_src_sha1=$(t63_sha "$t63r3" docs)
  t63_src_sha2=$(t63_sha "$t63r3" docs)
  report "T63 TC-1360 source-repo layout still yields a non-empty config_sha" 1 "$([[ -n "$t63_src_sha1" ]] && echo 1 || echo 0)"
  report "T63 TC-1360 source-repo fallback is stable across runs" 1 "$([[ -n "$t63_src_sha1" && "$t63_src_sha1" == "$t63_src_sha2" ]] && echo 1 || echo 0)"
  rm -rf "$t63r3"
else
  echo "SKIP T63 eval-rescore cases: eval-rescore 未安装"
fi

# ---- ③ UAC 并行形态（TC-1368/1369；静态形态，行为等价见 05 的 T9 三连跑证据）----
t63_uac="$ROOT/scripts/dev/update-assertion-count.sh"
if [[ -f "$t63_uac" ]]; then
  report "T63 TC-1368 UAC embeds the parallel suite invocation" 1 "$(grep -cF 'tests/run-tests.sh" -j "$suite_jobs"' "$t63_uac")"
  report "T63 TC-1368 UAC defaults the pool to 4 jobs" 1 "$(grep -cF 'suite_jobs="${AGENT_GUARD_SUITE_JOBS:-4}"' "$t63_uac")"
  report "T63 TC-1369 UAC falls back for non-numeric and <1 (pool stays sane)" 2 "$(grep -cE '"\$suite_jobs" in|"\$suite_jobs" -ge 1' "$t63_uac")"
  report "T63 TC-1369 suite default stays serial (receipt semantics untouched)" 1 "$(grep -cE '^JOBS=1' "$ROOT/tests/run-tests.sh")"
else
  echo "SKIP T63 UAC cases: update-assertion-count.sh absent"
fi

# ---- ④ 源层台账回填（TC-1374）------------------------------------------------
t63_p10="$ROOT/docs/project/P10-change-ledger.md"
t63_p09="$ROOT/docs/project/P09-risk-register.md"
# v3.91.2 (CHG-127 self-audit): these assertions read the repo's PRIVATE masters
# (docs/ is gitignored and was reset once by the fixture write-through incident).
# A fresh clone legitimately has no such files; a reset workspace has stubs. Judge
# them only when the historical blocks are actually present — otherwise SKIP with
# the reason, never fail on absent private data.
if [[ -f "$t63_p10" && -f "$t63_p09" ]] \
   && grep -q '缺口说明' "$t63_p10" \
   && grep -q 'FU-902~945 回溯回填' "$t63_p09"; then
  report "T63 TC-1374 P10 states the index gap explicitly" 2 "$(grep -c '缺口说明' "$t63_p10")"
  report "T63 TC-1374 P10 backfills CHG rows for the gap region" 1 "$([[ "$(grep -cE '^\| (BATCH-[0-9]+|—（独立目录）) \| CHG-0(7[1-9]|8[0-9]|9[1-7]) ' "$t63_p10")" -ge 10 ]] && echo 1 || echo 0)"
  report "T63 TC-1374 P09 registers the FU-902~945 retrospective block" 1 "$(grep -c 'FU-902~945 回溯回填' "$t63_p09")"
  report "T63 TC-1374 P09 carries the FU-943 carry-over row" 1 "$(grep -c '^| FU-943 ' "$t63_p09")"
  report "T63 TC-1374 P09 gap rows are labelled 未登记，非内容缺失" 3 "$(grep -c '未登记，非内容缺失' "$t63_p09")"
else
  echo "SKIP T63 ledger cases: private masters are absent or reset (docs/ is gitignored; the historical backfill block is not reproducible data)"
fi

}

section_T65() {
# ------------------------------------------------ T65 preflight 交付形状探针 + verify 睡眠防护 + 遥测失联兜底（v3.82.0，CHG-109/REQ-1160）
# v3.92.1: this section asserts the caffeinate WRAPPER itself, so an ambient
# AGENT_GUARD_CAFFEINATE=0 (used on hosts where the real binary aborts) must not
# suppress it — the fixture stub is the thing under test.
unset AGENT_GUARD_CAFFEINATE
# TC↔REQ 映射：TC-1411→REQ-1160（preflight 收齐 stop 侧交付形状锚、零副作用），
# TC-1412→REQ-1160（verify 通道 caffeinate 包裹），TC-1413→REQ-1160（begin 遥测失联黄灯）。
# 实证驱动：目标会话 5 轮格式返工 ×16min verify（4 轮可避免）——形状反馈必须秒级；
# 睡眠假红（clock leap）与 hook 失联（stats 全 0 无人核查）同批闭环（no-leftover）。
# 设计约束：validate_delivery 拆 front/back 纯函数，die 站点逐字搬运（T30/T41 钉不动）；
# 探针零副作用 = track_review_round 留在 stop lane（E116 不进探针面，用户裁定）。
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99 AGENT_GUARD_ALLOW_NO_SHIFT=1 AGENT_GUARD_ALLOW_OVER_RED=1 AGENT_GUARD_ALLOW_OVER_WATER=1
new_repo
seed_artifacts CHG-1092 L0 claude/s-1
scripts/agent-gate begin CHG-1092 >/dev/null 2>&1
seed_t53_delivery CHG-1092
t65_07() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat; } > docs/changes/CHG-1092/07-review-report.md; }
# TC-1411 负面：畸形 07（无独立署名 + 无发现处置节）→ 探针单跑收齐 E85+E115
t65_07 <<'EOF'
# review
## 评审结论
通过
EOF
t65_out=$(scripts/agent-gate preflight CHG-1092 2>&1)
report "T65 TC-1411 probe reds on malformed 07" 1 "$(grep -q 'GATE-E' <<< "$t65_out" && echo 1 || echo 0)"
report "T65 TC-1411 E85 collected" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E85')"
report "T65 TC-1411 E115 collected" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E115')"
report "T65 TC-1411 E116 absent from probe (round ledger excluded)" 0 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E116')"
# 零副作用：探针不写轮次台账
t65_r1=$([[ -f .agent-state/review-rounds.tsv ]] && wc -c < .agent-state/review-rounds.tsv || printf 0)
scripts/agent-gate preflight CHG-1092 >/dev/null 2>&1
t65_r2=$([[ -f .agent-state/review-rounds.tsv ]] && wc -c < .agent-state/review-rounds.tsv || printf 0)
report "T65 TC-1411 probe writes no round ledger" 0 "$([[ "$t65_r1" == "$t65_r2" ]] && echo 0 || echo 1)"
# E117（来源列乱值）与 E114（严重行未处置）同跑收齐
t65_07 <<'EOF'
# review
- 评审主体：claude / s-1 / ses-t65
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界缺失 | 严重 | | 补测 | 乱值 |
- **评审轮次**：1
## 评审结论
通过
EOF
t65_out=$(scripts/agent-gate preflight CHG-1092 2>&1)
report "T65 TC-1411 E117 collected on unlawful provenance value" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E117')"
report "T65 TC-1411 E114 collected on undisposed severe row" 1 "$(printf '%s\n' "$t65_out" | grep -c 'GATE-E114')"
# 正面：干净 07 与缺 07 均全绿（缺 07 = no-op，begin 期探针不受扰）
t65_07 <<'EOF'
# review
- 评审主体：claude / s-1 / ses-t65
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界缺失 | 严重 | 已修复 | 补测并复跑全绿 | 本次引入 |
- **评审轮次**：1
## 评审结论
通过
EOF
report "T65 TC-1411 clean 07 probes green" 0 "$(scripts/agent-gate preflight CHG-1092 >/dev/null 2>&1; echo $?)"
rm docs/changes/CHG-1092/07-review-report.md
report "T65 TC-1411 absent 07 probes green (no-op)" 0 "$(scripts/agent-gate preflight CHG-1092 >/dev/null 2>&1; echo $?)"
# TC-1412：verify 通道经 caffeinate 包裹（stub 调用标记证明 wrap 路径真实发生——
# 评审 F2：仅断言 marker 存在证明不了 wrap，直跑同样建文件）
mkdir -p .oc-t65bin
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> .agent-state/t65-caf-calls\nwhile [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' > .oc-t65bin/caffeinate
chmod +x .oc-t65bin/caffeinate
rm -f .agent-state/t65-ran .agent-state/t65-caf-calls
# stop 的深检门 working_code_changed 需要一个 code face（T60 同款 src 夹具）；
# 纯 docs 夹具会静默短路 verify 通道（REQ-1160 探针语义不受此影响——探针不查会话态）
mkdir -p src && echo y > src/t65.js
t65_stop_out=$(PATH="$PWD/.oc-t65bin:$PATH" AGENT_GUARD_VERIFY_COMMAND='touch .agent-state/t65-ran' scripts/agent-gate --stage stop 2>&1)
report "T65 TC-1412 verify runs wrapped via caffeinate stub" 1 "$([[ -e .agent-state/t65-ran ]] && echo 1 || echo 0)"
# v3.92.1: the probe (`caffeinate -dims true`) adds one call before the wrapped
# verify, so the proof is "at least one -dims call", not an exact count.
report "T65 TC-1412 stub call log carries -dims (wrap proof)" 1 "$([[ "$(grep -c -- '-dims' .agent-state/t65-caf-calls 2>/dev/null || printf 0)" -ge 1 ]] && echo 1 || echo 0)"
rm -rf .oc-t65bin .agent-state/t65-caf-calls
# TC-1413：begin 遥测失联黄灯（软）——water 新鲜 + stats 缺失 → 黄灯；stats 新鲜 → 静默。
# 新 id 走完整 begin（E86 已由夹具豁免放行；E72 不触发——八件套无 09）。
seed_artifacts CHG-1093 L0 claude/s-1
seed_artifacts CHG-1094 L0 claude/s-1
printf '{"turns":1,"bash":0,"grep":0,"other":0,"total":1,"updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-water.json
rm -f .agent-state/session-tool-stats.json
t65_out=$(scripts/agent-gate begin CHG-1093 2>&1)
report "T65 TC-1413 begin warns YELLOW when stats missing" 1 "$(printf '%s\n' "$t65_out" | grep -c 'YELLOW liveness')"
printf '{"turns":1,"bash":0,"grep":0,"other":0,"total":1,"updated_at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/session-tool-stats.json
t65_out=$(scripts/agent-gate begin CHG-1094 2>&1)
report "T65 TC-1413 fresh stats stays silent" 0 "$(printf '%s\n' "$t65_out" | grep -c 'YELLOW liveness')"
# 评审 F3：mtime 过期分支——stats 内容在但 mtime 老于 10min → 黄灯
touch -t 202001010000 .agent-state/session-tool-stats.json
t65_out=$(scripts/agent-gate begin CHG-1093 2>&1)
report "T65 TC-1413 stale-mtime stats warns YELLOW" 1 "$(printf '%s\n' "$t65_out" | grep -c 'YELLOW liveness')"
rm -f .agent-state/session-water.json .agent-state/session-tool-stats.json
}

section_T66() {
# ------------------------------------------------ T66 verify 结果缓存（v3.83.0，CHG-110/REQ-1161，DES-1923）
# TC↔REQ：TC-1414→REQ-1161（缓存命中/失效矩阵）。实证驱动：格式返工期间代码零变化
# 仍 4 次重跑 16min 全量（≈66min 可避免）。保守档（用户裁定）：只缓存 rc=0、键含
# gate 版本+vcmd sha+树指纹（docs/changes claim 排除）+变更号、TTL 30min、env 退出。
# 边界：外部状态依赖测试仓须 opt-out（CHANGELOG/usage 明示）；非 git 仓指纹空=降级直跑。
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99 AGENT_GUARD_ALLOW_NO_SHIFT=1 AGENT_GUARD_ALLOW_OVER_RED=1 AGENT_GUARD_ALLOW_OVER_WATER=1
new_repo
seed_artifacts CHG-1095 L0 claude/s-1
scripts/agent-gate begin CHG-1095 >/dev/null 2>&1
seed_t53_delivery CHG-1095
# v4.4.0 (CHG-148, FU-1012): the fixture carries a versioned DS footer so the
# gate receipt version derives from it (TC-2321: receipt == fixture DS footer).
# Created before the initial commit so the tree fingerprint stays stable.
t66_ver=$(sed -nE 's/.*规范版本：v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$ROOT/resources/DEVELOPMENT_STANDARDS.md" | head -1)
[[ -n "$t66_ver" ]] || t66_ver="0.0.0"
mkdir -p docs && printf '*规范版本：v%s | 更新时间：2026-11-15 | 全局维护责任人：T66 fixture*\n' "$t66_ver" > docs/DEVELOPMENT_STANDARDS.md
mkdir -p src && echo hi > src/t66.js
git add -A >/dev/null 2>&1 && git commit -qm init   # 树指纹需 HEAD；纯 docs 夹具仍缺 code face
echo y > src/t66b.js
t66_stop() { AGENT_GUARD_VERIFY_COMMAND="$1" scripts/agent-gate --stage stop 2>&1; }
# 命中基线：首跑执行并写 rc=0 收据
# v3.93.0 (CHG-130, REQ-1302): the gate cache owns .agent-state/gate-verify-cache.json;
# verify-all's .agent-state/verify-receipt.json is a different schema and must stay
# untouched by the gate (each writer used to clobber the other).
rm -f .agent-state/t66-m .agent-state/gate-verify-cache.json
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 first run executes and writes rc0 receipt" 1 "$([[ -e .agent-state/t66-m && -e .agent-state/gate-verify-cache.json ]] && echo 1 || echo 0)"
report "T66 TC-1414 receipt binds change id" 1 "$(grep -c '"change_id":"CHG-1095"' .agent-state/gate-verify-cache.json)"
report "T66 TC-1414 receipt carries gate version" 1 "$(grep -cE '"gate_version":"[0-9][0-9.]*"' .agent-state/gate-verify-cache.json)"
report "T66 TC-2321 receipt version equals the fixture DS footer (CHG-148)" 1 "$([[ "$(sed -n 's/.*"gate_version":"\([^"]*\)".*/\1/p' .agent-state/gate-verify-cache.json | head -1)" == "$t66_ver" ]] && echo 1 || echo 0)"
# REQ-1302: verify-all.sh owns .agent-state/verify-receipt.json (status schema read
# by sf_verify_status). The gate writing its cache there used to destroy that file.
report "T66 TC-1414 gate cache leaves verify-all receipt path alone" 0 "$([[ -e .agent-state/verify-receipt.json ]] && echo 1 || echo 0)"
# 命中：同键二跑不执行 vcmd
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 same-key second run skips execution (cached)" 0 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
report "T66 TC-1414 cached line surfaces" 1 "$(printf '%s\n' "$t66_out" | grep -c 'CACHED (receipt match')"
# docs/changes 改动不失效（claim 排除面）
printf 'x\n' >> docs/changes/CHG-1095/06-delivery-summary.md
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 docs/changes edit does not invalidate" 0 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# src 改动即失效
echo z >> src/t66b.js
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 src edit invalidates (re-runs)" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# rc≠0 不写收据：评审 M1——失败跑前记录收据 vcmd_sha，失败跑后断言 sha 未变
# （对「只缓存 rc=0」不变式有区分力；原 grep 't66-f' 恒 0 无失败区分力）
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
t66_sha_before=$(sed -n 's/.*"vcmd_sha":"\([^"]*\)".*/\1/p' .agent-state/gate-verify-cache.json | head -1)
rm -f .agent-state/t66-f
t66_out=$(t66_stop 'touch .agent-state/t66-f; false')
report "T66 TC-1414 failing verify dies E64" 1 "$(printf '%s\n' "$t66_out" | grep -c 'GATE-E64')"
t66_sha_after=$(sed -n 's/.*"vcmd_sha":"\([^"]*\)".*/\1/p' .agent-state/gate-verify-cache.json | head -1)
report "T66 TC-1414 receipt unchanged by failing run (rc0-only)" 1 "$([[ -n $t66_sha_before && $t66_sha_before == $t66_sha_after ]] && echo 1 || echo 0)"
# gate 版本失配失效：篡改收据版本字面
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
sed -E -i '' 's/"gate_version":"[0-9][0-9.]*"/"gate_version":"0.0.0"/' .agent-state/gate-verify-cache.json 2>/dev/null || sed -E -i 's/"gate_version":"[0-9][0-9.]*"/"gate_version":"0.0.0"/' .agent-state/gate-verify-cache.json
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 gate-version mismatch invalidates" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# TTL 失效：篡改 finished_at 为远古
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
sed -i '' 's/"finished_at":[0-9]*/"finished_at":1000/' .agent-state/gate-verify-cache.json 2>/dev/null || sed -i 's/"finished_at":[0-9]*/"finished_at":1000/' .agent-state/gate-verify-cache.json
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 TTL expiry invalidates" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# 变更号失配失效
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
sed -i '' 's/"change_id":"CHG-1095"/"change_id":"CHG-OTHER"/' .agent-state/gate-verify-cache.json 2>/dev/null || sed -i 's/"change_id":"CHG-1095"/"change_id":"CHG-OTHER"/' .agent-state/gate-verify-cache.json
rm -f .agent-state/t66-m
t66_out=$(t66_stop 'touch .agent-state/t66-m')
report "T66 TC-1414 change-id mismatch invalidates" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# opt-out：AGENT_GUARD_VERIFY_CACHE=0 恒真跑
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
rm -f .agent-state/t66-m
t66_out=$(AGENT_GUARD_VERIFY_CACHE=0 AGENT_GUARD_VERIFY_COMMAND='touch .agent-state/t66-m' scripts/agent-gate --stage stop 2>&1)
report "T66 TC-1414 opt-out always runs" 1 "$([[ -e .agent-state/t66-m ]] && echo 1 || echo 0)"
# v4.4.0 (CHG-148, 评审批 F-1)：无 DS 夹具 → 收据落 unknown（fail-soft 分支覆盖）；
# DS 恢复后重新派生回页脚版本。树指纹随 docs/DS 移动同步变化，故不断言缓存命中
# 隔离（指纹失配本就失效），只断言收据版本内容两态。
mv docs/DEVELOPMENT_STANDARDS.md docs/DEVELOPMENT_STANDARDS.md.t66hold
rm -f .agent-state/t66-m
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
report "T66 TC-2322 no-DS receipt falls back to unknown (CHG-148)" 1 "$(grep -c '"gate_version":"unknown"' .agent-state/gate-verify-cache.json)"
mv docs/DEVELOPMENT_STANDARDS.md.t66hold docs/DEVELOPMENT_STANDARDS.md
rm -f .agent-state/t66-m
t66_stop 'touch .agent-state/t66-m' >/dev/null 2>&1
report "T66 TC-2322 DS restore re-derives footer version (CHG-148)" 1 "$(grep -c "\"gate_version\":\"$t66_ver\"" .agent-state/gate-verify-cache.json)"
}

section_T67() {
# ------------------------------------------------ T67 六不变量机校（v3.84.0，CHG-111/REQ-1162~1170）
# TC-1424 E122：03 缺「既有范式关系」节/声明 → begin 拒；声明行在 → 过
new_repo
seed_begin CHG-1110 L1 claude/s-1
printf '# plan\n- DES-001: d\n' > docs/changes/CHG-1110/03-modification-plan.md
# CHG-117: E122 is a full-lane anchor (legacy begin + delivery); the design
# stage gate reports it as G-设计门/E126. Pin the E122 code via the documented
# compatibility switch.
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1110 >/dev/null 2>&1
rc=$?
out=$(AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1110 2>&1 || true)
report "T67 TC-1424 E122 rejects 03 without 既有范式关系" 2 "$rc"
check_output "T67 TC-1424 refusal names GATE-E122" "GATE-E122" "$out"
seed_begin CHG-1110 L1 claude/s-1
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1110 >/dev/null 2>&1
report "T67 TC-1424 begin passes with 既有范式关系 declaration" 0 $?
# TC-1425/1426：E123（来源物映射）/E124（业务合理性终审）三态
new_repo
seed_begin CHG-1111 L1 claude/s-1
printf '# spec\n- **ui_change**：true\n- **外部来源物**：docs/proto.md\n## 用户任务\n### UJ-001\n- **入口**：记录列表\n### REQ-001\n**描述**：r\n**挂靠 UJ**：UJ-001\n' > docs/changes/CHG-1111/01-spec.md
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n' > docs/changes/CHG-1111/03.6-ui-spec.md
printf '# tasks\n| 任务 | 类型 | 依赖 | 里程碑 | 说明 |\n|---|---|---|---|---|\n| T1 | UX | 无 | M1 | 设计 |\n- 评审输入: x\n' > docs/changes/CHG-1111/03.5-tasks.md
printf '# tests\n- TC-001 用户旅程 E2E（真人入口）\n覆盖维度: 正常流\n- SC-001 用户旅程 E2E（覆盖: TC-001）\n' > docs/changes/CHG-1111/04-test-scripts.md
git add -A
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T67 TC-1425 E123 red: declared source but 03.6 lacks 来源物映射" 1 "$(printf '%s\n' "$out" | grep -c 'GATE-E123')"
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n## 来源物映射\n| 来源物条目（文件+锚点） | 实现文件:行 | 实测证据（05 运行痕迹引用） | 一致性结论 |\n|---|---|---|---|\n| proto.md#list | src/a.go:10 | 05 UJ-001 快照 @2026-10-21T00:00:00Z | 一致 |\n' > docs/changes/CHG-1111/03.6-ui-spec.md
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T67 TC-1425 E123 green once mapping section exists" 0 "$(printf '%s\n' "$out" | grep -c 'GATE-E123')"
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 评审结论\n通过\n' > docs/changes/CHG-1111/07-review-report.md
git add -A
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T67 TC-1426 E124 red: 07 lacks 业务合理性终审" 1 "$(printf '%s\n' "$out" | grep -c 'GATE-E124')"
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 业务合理性终审\n- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）\n- **业务终审主体**：platform / glm / ses-t67a\n## 评审结论\n通过\n' > docs/changes/CHG-1111/07-review-report.md
git add -A
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T67 TC-1426 staged passes with 终审 section + subject signature" 0 $?
# TC-1427 G15：来源物映射闭合（runtime；沙箱无 STD 时 audit 秒退，落最小规范桩）
printf '# t\n规范版本：v%s\n' "$CURRENT_VERSION" > docs/DEVELOPMENT_STANDARDS.md
bash "$ROOT/tests/audit-docs-consistency.sh" > t67_audit.txt 2>&1 || true
report "T67 TC-1427 G15 green on closed mapping rows" 0 "$(grep -c 'G15 CHG-1111' t67_audit.txt)"
grep -vF 'proto.md#list' docs/changes/CHG-1111/03.6-ui-spec.md > t67_tmp.md && mv t67_tmp.md docs/changes/CHG-1111/03.6-ui-spec.md
bash "$ROOT/tests/audit-docs-consistency.sh" > t67_audit2.txt 2>&1 || true
report "T67 TC-1427 G15 red on emptied mapping row" 1 "$(grep -cE 'G15 CHG-1111 映射行缺实现位或证据位|G15 CHG-1111 来源物映射节零数据行' t67_audit2.txt)"
rm -f t67_audit.txt t67_audit2.txt
# TC-1428/1432：独立缺陷批 pre-commit 自动盖章 + E56/E57 一次报全
new_repo
cp "$STAMP_SRC" scripts/stamp-provenance.sh
mkdir -p .githooks && cp "$ROOT/resources/templates/pre-commit" .githooks/pre-commit && chmod +x .githooks/pre-commit
mkdir -p docs/bugs/BATCH-20260101
printf '## BUG-900\n诊断：d\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > docs/bugs/BATCH-20260101/01-diagnosis.md
printf '## BUG-901\n诊断：d\n延伸发现：未发现\n历史相似检索：未命中（x）\n' >> docs/bugs/BATCH-20260101/01-diagnosis.md
git add -A
out=$(bash .githooks/pre-commit 2>&1 || true)
report "T67 TC-1428 pre-commit stamps standalone bug batch anchors" 1 "$(grep -c '<!-- provenance' docs/bugs/BATCH-20260101/01-diagnosis.md)"
report "T67 TC-1432 E56/E57 report BOTH incomplete groups in one shot" 2 "$(printf '%s\n' "$out" | grep -cE 'defect group BUG-9[0-9]+ is missing')"
# TC-1429：同族推演行名存续（N3 不改行名防机校断链）
report "T67 TC-1429 同族推演 row name survives in bug-diagnosis template" 1 "$(grep -c '同族推演' "$ROOT/resources/templates/bug-diagnosis.md" | awk '{print ($1>=2)?1:0}')"
# TC-1430：A11 体积上界
report "T67 TC-1430 DS body within A11 bound (<=184320B)" 1 "$([[ $(wc -c < "$ROOT/resources/DEVELOPMENT_STANDARDS.md" | tr -d ' ') -le 184320 ]] && echo 1 || echo 0)"
# TC-1431：版本链字面
report "T67 TC-1431 SKILL version literals resolve to the DS footer" 4 "$(grep -cF "$CURRENT_VERSION" "$ROOT/SKILL.md")"
# TC-1433：多字节方括号类在 C locale 下不匹配全角冒号（本环境实测）——发布面
# 必须用 (：|:) 交替；[：:] 会让 UX/G13 开关在 LANG=C 的 CI 上静默失效。
t67_br='['; t67_br="$t67_br：:]"
report "T67 TC-1433 shipped gate avoids multibyte bracket classes" 0 "$(grep -cF "$t67_br" "$GATE_SRC")"
}

section_T68() {
# ------------------------------------------------ T68 工作区锁与收据路径隔离（v3.86.0，CHG-113）
  local t68_d t68_rc t68_out t68_lib t68_dead
  t68_lib="$ROOT/scripts/lib-suite-lock.sh"
  t68_d=$(mktemp -d "${TMPDIR:-/tmp}/suite-lock.XXXXXX")
  report "T68 lock lib ships the three entry points" 3 "$(grep -cE '^suite_lock_(dir|release|acquire)\(\)' "$t68_lib")"
  t68_out=$(ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/lock" bash -c 'source "$1"; suite_lock_acquire; echo "first=$?"; suite_lock_acquire 2>/dev/null; echo "second=$?"; suite_lock_release; [[ -d "$AGENT_GUARD_SUITE_LOCK_DIR" ]] && echo present || echo released; suite_lock_acquire; echo "third=$?"; suite_lock_release' _ "$t68_lib" 2>&1)
  report "T68 first acquisition succeeds" 1 "$(printf '%s\n' "$t68_out" | grep -c '^first=0$')"
  report "T68 live owner is rejected" 1 "$(printf '%s\n' "$t68_out" | grep -c '^second=1$')"
  report "T68 release removes the lock" 1 "$(printf '%s\n' "$t68_out" | grep -c '^released$')"
  report "T68 reacquisition after release succeeds" 1 "$(printf '%s\n' "$t68_out" | grep -c '^third=0$')"
  mkdir -p "$t68_d/dead"
  # A just-reaped PID cannot be alive; a fixed 999999 is only dead on hosts whose
  # pid_max is below it (Linux can exceed 1e6), which made this assertion flaky.
  ( : ) & t68_dead=$!; wait "$t68_dead" 2>/dev/null || true
  printf '%s\n' "$t68_dead" > "$t68_d/dead/pid"
  ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/dead" bash -c 'source "$1"; suite_lock_acquire; echo "rc=$?"; suite_lock_release' _ "$t68_lib" > "$t68_d/out" 2>&1
  report "T68 dead-owner lock is reclaimed" 1 "$(grep -c '^rc=0$' "$t68_d/out")"
  mkdir -p "$t68_d/young"
  ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/young" bash -c 'source "$1"; suite_lock_acquire 2>/dev/null; echo "rc=$?"' _ "$t68_lib" > "$t68_d/out2" 2>&1
  report "T68 empty-pid lock inside grace is not stolen" 1 "$(grep -c '^rc=1$' "$t68_d/out2")"
  touch -t "$(date -v-2M +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 minutes ago' +%Y%m%d%H%M.%S)" "$t68_d/young"
  ROOT="$t68_d" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/young" bash -c 'source "$1"; suite_lock_acquire; echo "rc=$?"; suite_lock_release' _ "$t68_lib" > "$t68_d/out3" 2>&1
  report "T68 empty-pid lock past grace is reclaimed" 1 "$(grep -c '^rc=0$' "$t68_d/out3")"
  report "T68 suite sources the lock lib" 1 "$(grep -cF "source \"\$_lock_lib\"" "$ROOT/tests/run-tests.sh")"
  report "T68 lock is gated to full runs" 1 "$(grep -cF "LOCK_HELD:-0}\" != \"1\"" "$ROOT/tests/run-tests.sh")"
  # -ge 1, not ==1: the same phrase is also printed by the lock-refusal message
  # asserted below, so an exact count would make this a line-budget pin.
  report "T68 lock conflict exits 2 with a message" 1 \
    "$([[ $(grep -cF "another full sui""te owns this workspace" "$ROOT/tests/run-tests.sh") -ge 1 ]] && echo 1 || echo 0)"
  report "T68 full run trap releases the lock" 1 "$(grep -cF "trap 'suite_lock_""release' EXIT" "$ROOT/tests/run-tests.sh")"
  report "T68 interrupt traps exit after releasing" 2 "$(grep -cE "trap 'exit 1(30|43)' (INT|TERM)" "$ROOT/tests/run-tests.sh")"
  mkdir -p "$t68_d/held"; printf '%s\n' "$$" > "$t68_d/held/pid"
  t68_rc=0; AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/held" bash "$ROOT/tests/run-tests.sh" -T T39 >/dev/null 2>&1 || t68_rc=$?
  # v3.91.7 (CHG-127): --shard is a filtered run too (never takes the lock). The
  # v3.96.0 plan is only a valid partition if every section appears exactly once
  # and the SERIAL_CHAIN groups stay inside one shard (cwd continuity).
  t68_shard_rc=0; t68_shard=$(
    for _i in 1 2 3 4 5 6; do
      AGENT_GUARD_SUITE_SHARD_RESOLVE_ONLY=1 AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/held" \
        bash "$ROOT/tests/run-tests.sh" --shard "$_i/6" 2>&1 || exit 1
    done
  ) || t68_shard_rc=$?
  report "T68 filtered/sharded run ignores the workspace lock (no deadlock)" 0 \
    "$([[ $t68_rc -eq 0 && $t68_shard_rc -eq 0 ]] && echo 0 || echo 1)"
  report "T68 N=6 plan keeps the T5/T22a/T16 chain in one shard" 1 \
    "$(printf '%s\n' "$t68_shard" | grep -cE '^shard-resolve-only:.* T5 T22a T16( |$)')"
  report "T68 N=6 plan covers every section exactly once" 100 \
    "$(printf '%s\n' "$t68_shard" | sed -n 's/^shard-resolve-only: //p' | tr ' ' '\n' | grep -c .)"
  # v3.97.0 (CHG-134, REQ-1344): the plan is machine-written — the BEGIN/END
  # markers must appear exactly once so `scripts/dev/shard-plan.sh --write` can never
  # rewrite the wrong block, and both new source tools must route to T87 under
  # `-T auto` (an unmapped governance tool silently falls back to a wider run).
  # Anchored to the block's own indentation: the marker strings also appear as
  # literals in the planner's pins, so an unanchored count would drift.
  report "T68 the shard plan block carries one BEGIN marker" 1 \
    "$(grep -c '^  # SHARD_PLAN_6_BEGIN$' "$ROOT/tests/run-tests.sh")"
  report "T68 the shard plan block carries one END marker" 1 \
    "$(grep -c '^  # SHARD_PLAN_6_END$' "$ROOT/tests/run-tests.sh")"
  report "T68 auto-resolve routes the two new source tools and their cost pin to T87" 3 \
    "$(for _f in scripts/dev/shard-plan.sh scripts/dev/pre-round-check.sh tests/.shard-plan-costs.tsv; do
        AGENT_GUARD_SUITE_AUTO_DIFF="$_f" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
          bash "$ROOT/tests/run-tests.sh" -T auto 2>/dev/null | grep -c 'auto-resolve-only: .*T87'
      done | grep -c 1)"
  t68_rc=0; t68_out=$(AGENT_GUARD_SUITE_LOCK_HELD=0 AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/held" bash "$ROOT/tests/run-tests.sh" -T "" 2>&1 >/dev/null) || t68_rc=$?
  # v3.91.7: a host with the kill marker refuses a full run (rc3) and names the
  # shard escape hatch — the mechanical stop for repeated 10-minute kills.
  mkdir -p "$t68_d/kill"
  printf 'Killed: 9 (test marker)\n' > "$t68_d/kill/full-suite-kill.$(hostname -s 2>/dev/null || echo host)"
  t68_kill_rc=0; t68_kill_out=$(AGENT_GUARD_SUITE_KILL_STATE_DIR="$t68_d/kill" AGENT_GUARD_SUITE_LOCK_DIR="$t68_d/nolock" bash "$ROOT/tests/run-tests.sh" -T "" 2>&1 >/dev/null) || t68_kill_rc=$?
  report "T68 full run refuses a held lock with rc2" 2 \
    "$([[ $t68_rc -eq 2 && $t68_kill_rc -eq 3 ]] && grep -q -- '--shard' <<< "$t68_kill_out" && echo 2 || echo 0)"
  # The rc2 above must come from the LOCK refusal, not from argument parsing:
  # `-T ""` is a full run, and a parser that rejects the empty operand would make
  # this assertion pass for the wrong reason (v3.87.0 R4, review finding #1).
  report "T68 the lock refusal is named in the message (not a usage error)" 1 \
    "$(printf '%s\n' "$t68_out" | grep -c 'another full suite owns this workspace')"
  report "T68 an empty -T operand is not reported as a usage error" 0 \
    "$(printf '%s\n' "$t68_out" | grep -c 'invalid -T value')"
  report "T68 refused full run leaves the lock intact" 1 "$([[ -d "$t68_d/held" ]] && echo 1 || echo 0)"
  rm -rf "$t68_d"
}

section_T69() {
# ------------------------------------------------ T69 套件基线 = 提交式证据（v3.87.0，CHG-115，REQ-1184/1185）
# 教训：源审计 A3 用裸 --check 时把 0.17s 的读表活付成了 300s 的整套套件——收据一陈旧
# 就隐式重跑。快路径的语义必须能回归：基线纯数字且受跟踪；--from-baseline 纯读、
# 永不触发内嵌套件；README 声称漂移显式 rc1 且不改文件；基线缺失/非数字 fail-closed rc2；
# --require-receipt 无新鲜收据即 rc2（绝不隐式重跑）；写模式把基线与双 README 一起回填。
  local r69 r69_rc r69_out r69_a r69_b r69_head r69_tree r69_snap r69_ts f
  if [[ ! -f "$ROOT/scripts/dev/update-assertion-count.sh" || ! -f "$ROOT/scripts/lib-suite-tree-fingerprint.sh" || ! -f "$ROOT/tests/.suite-baseline" ]]; then
    echo "SKIP T69: the committed baseline or the generator/fingerprint lib is absent (source-layer only)"
  else
    r69_a=0
    if [[ -f "$ROOT/tests/.suite-baseline" ]]; then
      r69_b=$(tr -d '[:space:]' < "$ROOT/tests/.suite-baseline")
      case "$r69_b" in ''|*[!0-9]*) ;; *) r69_a=1 ;; esac
      git -C "$ROOT" check-ignore -q tests/.suite-baseline 2>/dev/null && r69_a=0
    fi
    report "T69 TC-1439 the committed suite baseline is numeric and never git-ignored" 1 "$r69_a"
    report "T69 TC-1439 A3 consumes the baseline and keeps no bare generator call" 1 \
      "$([[ $(grep -cF -- '--check --from-baseline' "$ROOT/tests/audit-standards-src.sh" 2>/dev/null) -ge 1 && $(grep -cF '"$GEN" --check 2>&1' "$ROOT/tests/audit-standards-src.sh" 2>/dev/null) -eq 0 ]] && echo 1 || echo 0)"
    r69=$(mktemp -d "${TMPDIR:-/tmp}/suite-baseline.XXXXXX")
    mkdir -p "$r69/scripts" "$r69/tests" "$r69/.agent-state" "$r69/.tmp"
    mkdir -p "$r69/scripts/dev" && cp "$ROOT/scripts/dev/update-assertion-count.sh" "$r69/scripts/dev/"
    mkdir -p "$r69/scripts/dev" && cp "$ROOT/scripts/dev/lib-source-facts.sh" "$r69/scripts/dev/"
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r69/scripts/"
    printf '.agent-state/\n.tmp/\n' > "$r69/.gitignore"
    # 哨兵写在 gitignored 的 .agent-state 下：放进 tests/ 会留 untracked 文件、
    # 把树指纹搞脏，收据类用例就会因为错误的原因变红（T51 实测教训）。
    cat > "$r69/tests/run-tests.sh" <<'R69FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/../.agent-state/embedded-ran"
printf '777 passed, 0 failed\n'
printf 'wall-time: 1s\n'
R69FAKE
    printf 'README claims (100 golden-case assertions) here.\n' > "$r69/README.md"
    printf '这里声称 100 项 golden-case 断言。\n' > "$r69/README.zh-CN.md"
    printf '100\n' > "$r69/tests/.suite-baseline"
    ( cd "$r69" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    r69_head=$(git -C "$r69" rev-parse HEAD 2>/dev/null || true)
    r69_tree=$(git -C "$r69" rev-parse 'HEAD^{tree}' 2>/dev/null || true)
    # TMPDIR 隔离：真实审计留下的 $TMPDIR/audit-executed-count 一旦漂进 fixture，
    # .audit-baseline 同步分支会把 rc 判定污染成假红。
    _r69_run() { ( cd "$r69" && TMPDIR="$r69/.tmp" AGENT_GUARD_SUITE_RECEIPT_PATH="$r69/.agent-state/last-suite-receipt.json" AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=30 bash scripts/dev/update-assertion-count.sh "$@" 2>&1 ); }
    _r69_sent() { [[ -f "$r69/.agent-state/embedded-ran" ]] && echo 1 || echo 0; }
    _r69_seed() { printf '{"head":"%s","tree_fingerprint":"%s","passed":%s,"failed":%s,"wall_time_s":1,"generated_at":"%s"}\n' "$1" "$2" "$3" "$4" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$r69/.agent-state/last-suite-receipt.json"; }
    rm -f "$r69/.agent-state/embedded-ran"

    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1440 --from-baseline is green on an in-sync repo" 0 "$r69_rc"
    report "T69 TC-1440 --from-baseline never executes the embedded suite" 0 "$(_r69_sent)"
    report "T69 TC-1440 the baseline is named as the evidence source" 1 \
      "$(printf '%s\n' "$r69_out" | grep -c 'in sync with run-tests (100)')"

    sed -e 's/(100 golden-case assertions)/(999 golden-case assertions)/' "$r69/README.md" > "$r69/.tmp/r" && mv "$r69/.tmp/r" "$r69/README.md"
    r69_snap="$r69/.tmp/snap-README.md"; cp "$r69/README.md" "$r69_snap"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1441 a stale README claim is rc1" 1 "$r69_rc"
    report "T69 TC-1441 the drift message names README.md and the baseline number" 1 \
      "$(printf '%s\n' "$r69_out" | grep -cE 'drift: .*README.md.*expected 100')"
    report "T69 TC-1441 --check leaves the claim file byte-identical" 0 "$(cmp -s "$r69_snap" "$r69/README.md" && echo 0 || echo 1)"
    git -C "$r69" checkout -q -- README.md 2>/dev/null || true

    mv "$r69/tests/.suite-baseline" "$r69/.tmp/hold"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1442 a missing baseline fails closed rc2 (no suite rerun)" 2 "$r69_rc"
    report "T69 TC-1442 the missing-baseline message names the file" 1 \
      "$(printf '%s\n' "$r69_out" | grep -c 'from-baseline requires')"
    printf 'not-a-number\n' > "$r69/tests/.suite-baseline"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1442 a non-numeric baseline fails closed rc2" 2 "$r69_rc"
    report "T69 TC-1442 a non-numeric baseline never touches the suite" 0 "$(_r69_sent)"
    mv "$r69/.tmp/hold" "$r69/tests/.suite-baseline"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline --require-receipt) || r69_rc=$?
    report "T69 TC-1442 the two evidence sources are mutually exclusive rc2" 2 "$r69_rc"

    rm -f "$r69/.agent-state/last-suite-receipt.json"
    r69_rc=0; r69_out=$(_r69_run --check --require-receipt) || r69_rc=$?
    report "T69 TC-1443 --require-receipt without a receipt fails closed rc2" 2 "$r69_rc"
    report "T69 TC-1443 fail-closed does not fall through to an implicit rerun" 0 "$(_r69_sent)"
    _r69_seed "$r69_head" "$r69_tree" 100 0
    r69_rc=0; r69_out=$(_r69_run --check --require-receipt) || r69_rc=$?
    report "T69 TC-1443 a fresh same-tree receipt satisfies --require-receipt" 0 "$r69_rc"
    r69_ts=$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)
    touch -t "$r69_ts" "$r69/.agent-state/last-suite-receipt.json"
    r69_rc=0; r69_out=$(_r69_run --check --require-receipt) || r69_rc=$?
    report "T69 TC-1443 a stale receipt still fails closed rc2" 2 "$r69_rc"

    rm -f "$r69/.agent-state/last-suite-receipt.json" "$r69/.agent-state/embedded-ran"
    r69_rc=0; r69_out=$(_r69_run) || r69_rc=$?
    report "T69 TC-1443 write mode runs the suite exactly once" 1 "$(_r69_sent)"
    report "T69 TC-1443 write mode backfills tests/.suite-baseline" 777 "$(tr -d '[:space:]' < "$r69/tests/.suite-baseline")"
    report "T69 TC-1443 write mode re-syncs both README claims" 2 \
      "$( { grep -c '777 golden-case assertions' "$r69/README.md"; grep -c '777 项 golden-case 断言' "$r69/README.zh-CN.md"; } | awk '{s+=$1} END{print s}')"
    r69_rc=0; r69_out=$(_r69_run --check --from-baseline) || r69_rc=$?
    report "T69 TC-1443 the backfilled baseline reads back green" 0 "$r69_rc"
    rm -rf "$r69"
  fi
}

section_T70() {
# ------------------------------------------------ T70 facts.sh 一次读完的事实面（v3.87.0，CHG-115，REQ-1186/1193）
# 每一轮 Agent 都在用 git/读文件/跑套件问同一批事实。facts 把它们压成一次只读 JSON：
# 键集固定、随工作树变化、绝不跑套件、<10s，且是源层专属（bootstrap 清单里不能有它）。
  local r70 r70_rc r70_out r70_t0 r70_dt r70_keys r70_p f r70_hang_pid r70_watchdog
  if [[ ! -f "$ROOT/scripts/dev/facts.sh" || ! -f "$ROOT/scripts/dev/lib-source-facts.sh" || ! -f "$ROOT/scripts/lib-suite-tree-fingerprint.sh" ]]; then
    echo "SKIP T70: facts.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r70=$(mktemp -d "${TMPDIR:-/tmp}/facts-test.XXXXXX")
    mkdir -p "$r70/scripts" "$r70/tests" "$r70/resources" "$r70/.agent-state"
    mkdir -p "$r70/scripts/dev" && cp "$ROOT/scripts/dev/facts.sh" "$ROOT/scripts/dev/lib-source-facts.sh" "$r70/scripts/dev/"
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r70/scripts/"
    printf '.agent-state/\n' > "$r70/.gitignore"
    printf '规范版本：v1.2.3\n' > "$r70/resources/DEVELOPMENT_STANDARDS.md"
    printf '1000\n' > "$r70/tests/.suite-baseline"
    printf '500\n' > "$r70/tests/.audit-baseline"
    cat > "$r70/tests/run-tests.sh" <<'R70FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/../.agent-state/embedded-ran"
printf '1 passed, 0 failed\n'
R70FAKE
    printf 'notes\n' > "$r70/notes.md"
    ( cd "$r70" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    mkdir -p "$r70/.git/agent-governance"
    printf 'CHG-9001\n' > "$r70/.git/agent-governance/active-change"
    r70_t0=$(date +%s)
    _r70_run() { ( cd "$r70" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r70/.agent-state/last-suite-receipt.json" bash scripts/dev/facts.sh "$@" 2>&1 ); }
    r70_rc=0; r70_out=$(_r70_run) || r70_rc=$?
    r70_dt=$(( $(date +%s) - r70_t0 ))
    report "T70 TC-1444 facts exits 0 on a well-formed checkout" 0 "$r70_rc"
    r70_keys=$(printf '%s\n' "$r70_out" | grep -oE '"(schema|head|branch|version|tree_fingerprint|dirty|changed_count|changed_files|active_change|audit_baseline|suite_baseline|suite_receipt)":' | sort -u | wc -l | tr -d ' ')
    report "T70 TC-1444 the fact key set is complete" 12 "$r70_keys"
    report "T70 TC-1444 version resolves from the DS footer" 1 "$(printf '%s\n' "$r70_out" | grep -c '"version": "1.2.3"')"
    report "T70 TC-1444 both committed baselines are surfaced" 2 \
      "$(printf '%s\n' "$r70_out" | grep -cE '"(audit_baseline)": 500|"suite_baseline": 1000')"
    report "T70 TC-1444 the active change comes from the governance pointer" 1 \
      "$(printf '%s\n' "$r70_out" | grep -c '"active_change": "CHG-9001"')"
    report "T70 TC-1444 a clean tree reports no receipt and no dirt" 2 \
      "$(printf '%s\n' "$r70_out" | grep -cE '"exists": false|"dirty": false')"
    r70_rc=0; r70_out=$(_r70_run --root "$r70" ) || r70_rc=$?
    report "T70 TC-1446 --root inspects an explicit checkout" 0 "$r70_rc"
    printf '{"head":"%s","tree_fingerprint":"%s","passed":1000,"failed":0,"wall_time_s":9,"generated_at":"now"}\n' \
      "$(git -C "$r70" rev-parse HEAD)" "$(git -C "$r70" rev-parse 'HEAD^{tree}')" > "$r70/.agent-state/last-suite-receipt.json"
    r70_out=$(_r70_run)
    report "T70 TC-1444 a fresh same-tree receipt is reported fresh" 1 "$(printf '%s\n' "$r70_out" | grep -c '"fresh": true')"
    touch -t "$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)" "$r70/.agent-state/last-suite-receipt.json"
    r70_out=$(_r70_run)
    report "T70 TC-1444 a stale receipt is reported not fresh" 1 "$(printf '%s\n' "$r70_out" | grep -c '"fresh": false')"
    rm -f "$r70/.agent-state/last-suite-receipt.json"
    printf 'more\n' >> "$r70/notes.md"
    r70_out=$(_r70_run)
    report "T70 TC-1445 a tracked edit shows up in dirty/changed_files" 2 \
      "$(printf '%s\n' "$r70_out" | grep -cE '"dirty": true|"changed_count": 1')"
    report "T70 TC-1445 the changed path is named" 1 "$(printf '%s\n' "$r70_out" | grep -c '"notes.md"')"
    printf '2000\n' > "$r70/tests/.suite-baseline"
    r70_out=$(_r70_run)
    report "T70 TC-1445 a baseline bump is visible without any run" 1 "$(printf '%s\n' "$r70_out" | grep -c '"suite_baseline": 2000')"
    report "T70 TC-1446 facts never executes the suite" 0 "$([[ -f "$r70/.agent-state/embedded-ran" ]] && echo 1 || echo 0)"
    report "T70 TC-1446 facts stays inside the read-only budget" 1 "$([[ $r70_dt -le 10 ]] && echo 1 || echo 0)"
    git -C "$r70" checkout -q -- notes.md tests/.suite-baseline 2>/dev/null || true
    r70_p="$r70/.agent-state/facts-override.json"
    r70_rc=0; r70_out=$(_r70_run --write --path "$r70_p") || r70_rc=$?
    report "T70 TC-1446 --write --path lands the snapshot" 1 "$([[ -s "$r70_p" ]] && echo 1 || echo 0)"
    report "T70 TC-1446 the written file is the JSON body" 1 "$(grep -c '"schema": 1' "$r70_p")"
    _r70_run --write >/dev/null 2>&1
    report "T70 TC-1446 the default --write path is .agent-state/facts.json" 1 \
      "$([[ -s "$r70/.agent-state/facts.json" ]] && echo 1 || echo 0)"
    report "T70 TC-1446 --write replaces atomically and leaves no temp file" 0 \
      "$(ls "$r70_p".* 2>/dev/null | wc -l | tr -d ' ')"
    r70_rc=0; r70_out=$(_r70_run --root) || r70_rc=$?
    report "T70 TC-1444 a trailing flag without its value dies rc2 instead of hanging" 2 "$r70_rc"
    r70_rc=0; r70_out=$(_r70_run --nope) || r70_rc=$?
    report "T70 TC-1444 an unknown facts argument dies rc2" 2 "$r70_rc"
    # A trailing option that takes a value must die, not keep the default: before
    # the arity guard `--path` with no operand printed to stdout as if it had been
    # ignored (v3.87.0 R4, finding #10 — same family as the suite's -T).
    r70_rc=0; r70_out=$(_r70_run --path) || r70_rc=$?
    report "T70 TC-1444 a trailing --path dies rc2 naming the option" 0 \
      "$([[ $r70_rc -eq 2 && $(printf '%s\n' "$r70_out" | grep -c -- '--path needs a value') -eq 1 ]] && echo 0 || echo 1)"
    r70_rc=0; r70_out=$(bash "$ROOT/scripts/dev/facts.sh" --root "$r70/does-not-exist" 2>&1) || r70_rc=$?
    report "T70 TC-1444 a missing --root dies rc2 instead of inventing facts" 2 "$r70_rc"
    # N1 同族回归：随 bootstrap --guard 下发的套件自身也必须在尾随 -T 上立即失败。
    # 修复前实测是死循环（shift 2 在 $# == 1 时不推进），所以这里用看门狗把「挂住」
    # 本身变成断言失败，而不是让整套套件卡死。
    bash "$ROOT/tests/run-tests.sh" -T >"$r70/trailing-t.err" 2>&1 &
    r70_hang_pid=$!
    ( sleep 8; kill -0 "$r70_hang_pid" 2>/dev/null && kill -9 "$r70_hang_pid" 2>/dev/null ) &
    r70_watchdog=$!
    r70_rc=0; wait "$r70_hang_pid" || r70_rc=$?
    kill "$r70_watchdog" 2>/dev/null; wait "$r70_watchdog" 2>/dev/null
    report "T70 TC-1444 the shipped runner dies rc2 on a trailing -T instead of hanging" 2 "$r70_rc"
    report "T70 TC-1444 the hang fix is a named usage error, not a silent full run" 1 \
      "$(grep -c 'invalid -T value' "$r70/trailing-t.err")"
    report "T70 TC-1447 facts declares the source-layer boundary" 1 \
      "$([[ $(grep -cF 'Source-layer only (NOT shipped with the Skill)' "$ROOT/scripts/dev/facts.sh") -ge 1 && $(grep -cF 'lib-source-facts.sh' "$ROOT/scripts/dev/lib-source-facts.sh") -ge 1 ]] && echo 1 || echo 0)"
    report "T70 TC-1447 bootstrap ships neither facts nor its lib" 0 \
      "$(grep -cE 'facts\.sh|lib-source-facts' "$ROOT/scripts/bootstrap.sh")"
    r70_rc=0; r70_out=$(bash "$ROOT/scripts/dev/facts.sh" 2>&1) || r70_rc=$?
    report "T70 TC-1446 facts runs against the live source repo" 0 "$r70_rc"
    report "T70 TC-1446 the live facts carry this suite's version authority" 1 \
      "$(printf '%s\n' "$r70_out" | grep -c "\"version\": \"${CURRENT_VERSION:-unset}\"")"
    rm -rf "$r70"
  fi
}

section_T71() {
# ------------------------------------------------ T71 verify-all 串行编排与收据复用（v3.87.0，CHG-115，REQ-1187）
# 一次调用拿到完整红/绿图：release→ledger→audit→suite 固定顺序、collect-all（前面失败
# 不短路）、套件收据复用（--fresh 强制真跑）、验证期间树变必须显式失败。
# 五步都可注入命令（AGENT_GUARD_VERIFY_*_CMD 测试缝），本节全靠缝，不碰真实套件。
  local r71 r71_rc r71_out r71_order r71_rec r71_logs r71_srecv r71_head r71_tree
  local r71_c_rel r71_c_led r71_c_aud r71_c_sui r71_seq
  if [[ ! -f "$ROOT/scripts/dev/verify-all.sh" || ! -f "$ROOT/scripts/dev/lib-source-facts.sh" ]]; then
    echo "SKIP T71: verify-all.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r71=$(mktemp -d "${TMPDIR:-/tmp}/verify-all.XXXXXX")
    mkdir -p "$r71/repo/scripts" "$r71/repo/tests" "$r71/repo/.agent-state"
    mkdir -p "$r71/repo/scripts/dev" && cp "$ROOT/scripts/dev/verify-all.sh" "$ROOT/scripts/dev/lib-source-facts.sh" "$r71/repo/scripts/dev/"
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r71/repo/scripts/"
    printf '.agent-state/\n' > "$r71/repo/.gitignore"
    cat > "$r71/repo/tests/run-tests.sh" <<'R71FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/../.agent-state/embedded-ran"
printf '777 passed, 0 failed\n'
printf 'wall-time: 1s\n'
R71FAKE
    printf 'notes\n' > "$r71/repo/notes.md"
    ( cd "$r71/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    r71_order="$r71/repo/.agent-state/order.txt"
    r71_rec="$r71/repo/.agent-state/verify-receipt.json"
    r71_logs="$r71/repo/.agent-state/verify-logs"
    r71_srecv="$r71/repo/.agent-state/last-suite-receipt.json"
    r71_head=$(git -C "$r71/repo" rev-parse HEAD 2>/dev/null || true)
    # Same reason as T73b: seed with the value sf_receipt_fresh will compare against.
    r71_tree=$(bash -c 'source "$1/scripts/dev/lib-source-facts.sh"; sf_tree_fingerprint "$1"' _ "$r71/repo" 2>/dev/null || true)
    r71_c_rel="printf 'release\\n' >> $r71_order"
    r71_c_led="printf 'ledger\\n' >> $r71_order"
    r71_c_aud="printf 'audit\\n' >> $r71_order"
    r71_c_sui="printf 'suite\\n' >> $r71_order"
    r71_c_gat="printf 'gate\\n' >> $r71_order"
    _r71_run() { ( cd "$r71/repo" && AGENT_GUARD_VERIFY_RECEIPT_PATH="$r71_rec" AGENT_GUARD_VERIFY_LOG_DIR="$r71_logs" AGENT_GUARD_SUITE_RECEIPT_PATH="$r71_srecv" AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=30 AGENT_GUARD_VERIFY_RELEASE_CMD="$r71_c_rel" AGENT_GUARD_VERIFY_LEDGER_CMD="$r71_c_led" AGENT_GUARD_VERIFY_AUDIT_CMD="$r71_c_aud" AGENT_GUARD_VERIFY_SUITE_CMD="$r71_c_sui" AGENT_GUARD_VERIFY_GATE_CMD="$r71_c_gat" bash scripts/dev/verify-all.sh "$@" 2>&1 ); }
    _r71_seed() { printf '{"kind":"full","head":"%s","tree_fingerprint":"%s","passed":%s,"failed":0,"wall_time_s":123,"generated_at":"now"}\n' "$1" "$2" "$3" > "$r71_srecv"; }
    rm -f "$r71_order" "$r71_srecv" "$r71_rec"; rm -rf "$r71_logs"

    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1448 the five-step orchestration is green" 0 "$r71_rc"
    r71_seq=$(tr '\n' ' ' < "$r71_order" | sed -e 's/^ *//' -e 's/ *$//')
    report "T71 TC-1448 the step order is release ledger audit suite gate" 1 \
      "$([[ "$r71_seq" == "release ledger audit suite gate" ]] && echo 1 || echo 0)"
    report "T71 TC-1448 every step reports a PASS line" 5 "$(printf '%s\n' "$r71_out" | grep -c '^PASS')"
    report "T71 TC-1448 the receipt records five steps" 5 "$(grep -o '"name":' "$r71_rec" | wc -l | tr -d ' ')"
    report "T71 TC-1448 the receipt says pass and the tree stayed stable" 2 \
      "$(grep -cE '"status": "pass"|"tree_stable": true' "$r71_rec")"
    report "T71 TC-1448 each step keeps its own log file" 5 "$(ls "$r71_logs" 2>/dev/null | wc -l | tr -d ' ')"

    r71_c_sui=""
    _r71_seed "$r71_head" "$r71_tree" 1000
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1449 a fresh same-tree receipt is reused instead of rerun" 0 "$r71_rc"
    report "T71 TC-1449 the reuse line names the reused receipt" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'reused fresh same-tree receipt')"
    report "T71 TC-1449 reuse carries the receipt counts into the verify receipt" 1 \
      "$(grep -c '"reused": true, "passed": 1000' "$r71_rec")"
    r71_rc=0; r71_out=$(_r71_run --fresh) || r71_rc=$?
    report "T71 TC-1452 --fresh forbids reuse and runs the suite" 1 \
      "$([[ $(grep -c '"reused": false' "$r71_rec") -ge 1 ]] && echo 1 || echo 0)"
    report "T71 TC-1452 --fresh parses counts out of the real suite output" 1 "$(grep -c '"passed": 777, "failed": 0, "wall_time_s": 1' "$r71_rec")"
    rm -f "$r71/repo/.agent-state/embedded-ran"

    rm -f "$r71_order" "$r71_srecv"; rm -rf "$r71_logs"
    r71_c_sui="printf 'suite\\n' >> $r71_order"
    r71_c_led="printf 'ledger\\n' >> $r71_order; exit 1"
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1450 a failing middle step makes the run rc1" 1 "$r71_rc"
    r71_seq=$(tr '\n' ' ' < "$r71_order" | sed -e 's/^ *//' -e 's/ *$//')
    report "T71 TC-1450 collect-all still runs the later steps" 1 \
      "$([[ "$r71_seq" == "release ledger audit suite gate" ]] && echo 1 || echo 0)"
    report "T71 TC-1450 the receipt status is fail with the failing rc kept" 1 \
      "$(grep -cE '"status": "fail"' "$r71_rec")"
    report "T71 TC-1450 the FAIL line points at the step log" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'FAIL ledger')"

    rm -f "$r71_order" "$r71_srecv"; rm -rf "$r71_logs"
    r71_c_led="printf 'ledger\\n' >> $r71_order"
    r71_c_sui="printf 'suite\\n' >> $r71_order; echo change >> notes.md"
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1451 a tree change during verification fails rc1" 1 "$r71_rc"
    report "T71 TC-1451 the tree change is reported explicitly" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'changed during verification')"
    report "T71 TC-1451 the receipt marks the tree unstable" 1 "$(grep -c '"tree_stable": false' "$r71_rec")"
    git -C "$r71/repo" checkout -q -- notes.md 2>/dev/null || true

    # R4 (review finding #4): both fingerprints empty compares equal, so an
    # uncomputable fingerprint used to certify "tree_stable": true for a run whose
    # inputs were never pinned. A root that is not a git repo must fail instead.
    mkdir -p "$r71/nogit/scripts" "$r71/nogit/.agent-state"
    mkdir -p "$r71/nogit/scripts/dev" && cp "$ROOT/scripts/dev/verify-all.sh" "$ROOT/scripts/dev/lib-source-facts.sh" "$r71/nogit/scripts/dev/"
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r71/nogit/scripts/"
    r71_rc=0; r71_out=$( cd "$r71/nogit" && AGENT_GUARD_VERIFY_RECEIPT_PATH="$r71/nogit/.agent-state/verify-receipt.json" AGENT_GUARD_VERIFY_LOG_DIR="$r71/nogit/.agent-state/verify-logs" AGENT_GUARD_SUITE_RECEIPT_PATH="$r71/nogit/.agent-state/last-suite-receipt.json" AGENT_GUARD_VERIFY_RELEASE_CMD="$r71_c_rel" AGENT_GUARD_VERIFY_LEDGER_CMD="$r71_c_led" AGENT_GUARD_VERIFY_AUDIT_CMD="$r71_c_aud" AGENT_GUARD_VERIFY_SUITE_CMD="$r71_c_sui" bash scripts/dev/verify-all.sh --root "$r71/nogit" 2>&1 ) || r71_rc=$?
    report "T71 TC-1451 a root with no computable fingerprint dies rc1" 1 "$r71_rc"
    report "T71 TC-1451 the missing fingerprint is named instead of guessed" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'stability cannot be proven')"
    report "T71 TC-1451 that receipt never claims a stable tree" 0 \
      "$(grep -c '"tree_stable": true' "$r71/nogit/.agent-state/verify-receipt.json")"

    rm -f "$r71_order" "$r71_rec"; rm -rf "$r71_logs"
    r71_c_sui="printf 'suite\\n' >> $r71_order"
    r71_rc=0; r71_out=$(_r71_run --skip-suite) || r71_rc=$?
    report "T71 TC-1448 --skip-suite still exits green" 0 "$r71_rc"
    report "T71 TC-1448 the skipped step is recorded as skip, not pass" 1 \
      "$(grep -c '"name":"suite","status":"skip"' "$r71_rec")"
    # R4 (review finding #5): the batch's headline hard gate must exist in the
    # local entry too, not only in CI — otherwise "verify-all is the local truth"
    # silently excludes the baseline==receipt check it was sold on.
    r71_rc=0; r71_out=$(_r71_run --skip-gate) || r71_rc=$?
    report "T71 TC-1448 --skip-gate records the gate as skip, never as pass" 0 \
      "$([[ $r71_rc -eq 0 && $(grep -c '"name":"gate","status":"skip"' "$r71_rec") -eq 1 ]] && echo 0 || echo 1)"
    r71_c_gat="printf 'gate\\n' >> $r71_order; exit 1"
    r71_rc=0; r71_out=$(_r71_run) || r71_rc=$?
    report "T71 TC-1448 a red baseline/receipt gate reddens the whole local entry" 1 "$r71_rc"
    report "T71 TC-1448 the FAIL line names the gate step" 1 \
      "$(printf '%s\n' "$r71_out" | grep -c 'FAIL gate')"
    r71_c_gat="printf 'gate\\n' >> $r71_order"
    r71_rc=0; r71_out=$(_r71_run --nope) || r71_rc=$?
    report "T71 TC-1448 an unknown verify-all argument dies rc2" 2 "$r71_rc"
    r71_rc=0; r71_out=$(_r71_run --jobs) || r71_rc=$?
    report "T71 TC-1444 a trailing --jobs dies rc2 instead of taking the default" 0 \
      "$([[ $r71_rc -eq 2 && $(printf '%s\n' "$r71_out" | grep -c -- '--jobs needs a value') -eq 1 ]] && echo 0 || echo 1)"
    # -j is the spelling used by the suite this tool forwards to; a documented
    # "-j 4" that dies as an unknown argument is a trap (v3.87.0 R4).
    r71_rc=0; r71_out=$(_r71_run --fresh -j 4) || r71_rc=$?
    report "T71 TC-1444 the suite spelling -j is accepted as an alias" 0 \
      "$([[ $r71_rc -eq 0 && $(printf '%s\n' "$r71_out" | grep -c 'unknown argument') -eq 0 ]] && echo 0 || echo 1)"
    report "T71 TC-1452 verify-all shares the receipt-reuse rule with the generator" 1 \
      "$(grep -cF 'sf_receipt_fresh' "$ROOT/scripts/dev/verify-all.sh")"
    report "T71 TC-1447 verify-all declares the source-layer boundary and stays unshipped" 0 \
      "$(grep -cE 'verify-all\.sh' "$ROOT/scripts/bootstrap.sh")"
    rm -rf "$r71"
  fi
}

section_T72() {
# ------------------------------------------------ T72 pre-review-check 评审前置机检（v3.87.0，CHG-115，REQ-1188）
# 评审 Agent 不该把时间花在"产物齐不齐"上。16 产物在位非空、FILL 残留、00.5 确认行、
# 05 真实执行证据、责任人独立、07 署名与结论、provenance 戳、载体一致、README 计数、
# 空 glob 陷阱——全部机检；只读，失败不许改动任何产物。
  local r72 r72_rc r72_out r72_art r72_snap f g
  if [[ ! -f "$ROOT/scripts/dev/pre-review-check.sh" || ! -f "$ROOT/scripts/dev/lib-source-facts.sh" ]]; then
    echo "SKIP T72: pre-review-check.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r72=$(mktemp -d "${TMPDIR:-/tmp}/pre-review.XXXXXX")
    mkdir -p "$r72/repo/scripts" "$r72/repo/tests" "$r72/repo/.agent-state"
    mkdir -p "$r72/repo/scripts/dev" && cp "$ROOT/scripts/dev/pre-review-check.sh" "$ROOT/scripts/dev/lib-source-facts.sh" "$r72/repo/scripts/dev/"
    printf '.agent-state/\n' > "$r72/repo/.gitignore"
    printf 'README (1000 golden-case assertions) (assertions: 500)\n' > "$r72/repo/README.md"
    printf '这里声称 1000 项 golden-case 断言（断言：500）。\n' > "$r72/repo/README.zh-CN.md"
    printf '1000\n' > "$r72/repo/tests/.suite-baseline"
    printf '500\n' > "$r72/repo/tests/.audit-baseline"
    r72_art="$r72/repo/docs/changes/BATCH-20990101"
    mkdir -p "$r72_art"
    for f in 00-intent.md 00.5-communication.md 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md \
             03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md \
             06-delivery-summary.md 06.5-deployment-config.md 07-review-report.md 09-changelog.md handoff.md; do
      printf '# %s\n\n正文。\n<!-- provenance: CHG-9001 batch BATCH-20990101 -->\n' "$f" > "$r72_art/$f"
    done
    printf '{"change_id": "CHG-9001", "risk_level": "L1", "spec_author": "alice", "implementation_owner": "bob", "test_owner": "carol", "review_owner": "dave"}\n' > "$r72_art/00-governance.json"
    printf -- '- 确认状态：已确认\n' >> "$r72_art/00.5-communication.md"
    printf '套件：1127 passed, 0 failed\n' >> "$r72_art/05-test-results.md"
    printf '评审人：dave\n评审结论：通过\n' >> "$r72_art/07-review-report.md"
    ( cd "$r72/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    _r72_run() { ( cd "$r72/repo" && bash scripts/dev/pre-review-check.sh --root "$r72/repo" --skip-release --skip-audit "$@" 2>&1 ); }

    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 a complete artifact set passes with zero findings" 0 "$r72_rc"
    report "T72 TC-1453 the summary line says PASS with no failures" 1 "$(printf '%s\n' "$r72_out" | grep -c 'pre-review-check: PASS (0 failure')"
    r72_rc=0; r72_out=$(_r72_run) || r72_rc=$?
    report "T72 TC-1453 the newest governance file is discovered without --change" 0 "$r72_rc"
    # R4 (self-caught): the fixture dir is BATCH-20990101 while its governance id
    # is CHG-9001 — addressing a batch by its own name used to match nothing and
    # silently skip every artifact check.
    r72_rc=0; r72_out=$(_r72_run --change BATCH-20990101) || r72_rc=$?
    report "T72 TC-1465 a batch directory name resolves as --change" 0 "$r72_rc"
    report "T72 TC-1465 the resolved directory is the batch face" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'change directory: .*BATCH-20990101$')"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9999) || r72_rc=$?
    report "T72 TC-1465 an id matching neither face is rc1" 1 "$r72_rc"
    report "T72 TC-1465 the finding names both resolution faces" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'neither a directory under docs/changes nor a 00-governance.json change_id')"
    # Traversal / containing-slash operands are excluded from the directory-name
    # face by design (`*/*|.|..`); they must fall through to the same fail-closed
    # finding instead of being treated as a path or crashing the resolution.
    r72_rc=0; r72_out=$(_r72_run --change ../evil) || r72_rc=$?
    report "T72 TC-1465 a traversal change operand is rejected, not taken as a path" 1 "$r72_rc"
    report "T72 TC-1465 the traversal rejection names the resolution faces" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'neither a directory under docs/changes nor a 00-governance.json change_id')"
    r72_snap="$r72/snap"; mkdir -p "$r72_snap"; cp -R "$r72_art/." "$r72_snap/"

    printf '<!-- FILL: 待补 -->\n' >> "$r72_art/01-spec.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1454 leftover FILL placeholders are rc1" 1 "$r72_rc"
    report "T72 TC-1454 the finding names the placeholder class" 1 "$(printf '%s\n' "$r72_out" | grep -c 'placeholders remain')"
    git -C "$r72/repo" checkout -q -- docs/changes/BATCH-20990101/01-spec.md 2>/dev/null || true

    sed -e 's/确认状态：已确认/沟通摘要：见下/' "$r72_art/00.5-communication.md" > "$r72/.t" && mv "$r72/.t" "$r72_art/00.5-communication.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1455 a missing 00.5 confirmation line is rc1" 1 "$r72_rc"
    report "T72 TC-1455 the finding names 确认状态" 1 "$(printf '%s\n' "$r72_out" | grep -c '确认状态')"
    cp "$r72_snap/00.5-communication.md" "$r72_art/00.5-communication.md"

    sed -e 's/- 确认状态：已确认/- **沟通确认**：未命中，不适用（L0）/' "$r72_art/00.5-communication.md" > "$r72/.t" && mv "$r72/.t" "$r72_art/00.5-communication.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1463 the L0 bold 沟通确认 bullet declaration is accepted" 0 "$r72_rc"
    cp "$r72_snap/00.5-communication.md" "$r72_art/00.5-communication.md"

    sed -e 's/套件：1127 passed, 0 failed/（证据待补）/' "$r72_art/05-test-results.md" > "$r72/.t" && mv "$r72/.t" "$r72_art/05-test-results.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 05 without execution evidence is rc1" 1 "$r72_rc"
    report "T72 TC-1456 the finding asks for a passed/failed line" 1 "$(printf '%s\n' "$r72_out" | grep -c 'no recognizable execution evidence')"
    cp "$r72_snap/05-test-results.md" "$r72_art/05-test-results.md"

    rm -f "$r72_art/07-review-report.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 a missing 07 artifact is rc1 and is named" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c '07-review-report.md') -ge 1 ]] && echo 0 || echo 1)"
    report "T72 TC-1456 a failing pre-review check never rewrites the artifacts" 0 \
      "$([[ -z "$(diff -rq -x 07-review-report.md "$r72_snap" "$r72_art" 2>/dev/null)" ]] && echo 0 || echo 1)"
    cp "$r72_snap/07-review-report.md" "$r72_art/07-review-report.md"

    sed -e 's/评审人：dave/评审人：alice/' "$r72_snap/07-review-report.md" > "$r72_art/07-review-report.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 07 must name the recorded review owner" 1 "$r72_rc"
    report "T72 TC-1456 the finding says 07 does not name review_owner" 1 \
      "$(printf '%s\n' "$r72_out" | grep -c 'does not name review_owner')"
    sed -e 's/评审结论：通过/（结论待补）/' "$r72_snap/07-review-report.md" > "$r72_art/07-review-report.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1456 07 without a verdict is rc1" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'no review verdict') -ge 1 ]] && echo 0 || echo 1)"
    cp "$r72_snap/07-review-report.md" "$r72_art/07-review-report.md"

    sed -e 's/"review_owner": "dave"/"review_owner": "alice"/' "$r72_snap/00-governance.json" > "$r72_art/00-governance.json"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1455 a reviewer who wrote the spec is rc1" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'review owner equals') -ge 1 ]] && echo 0 || echo 1)"
    cp "$r72_snap/00-governance.json" "$r72_art/00-governance.json"

    printf '# 无戳产物\n' > "$r72_art/09-changelog.md"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 an unstamped markdown artifact is rc1" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'unstamped artifacts') -ge 1 ]] && echo 0 || echo 1)"
    cp "$r72_snap/09-changelog.md" "$r72_art/09-changelog.md"

    printf '999\n' > "$r72/repo/tests/.suite-baseline"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 README counts are compared against the committed baseline" 0 \
      "$([[ $r72_rc -eq 1 && $(printf '%s\n' "$r72_out" | grep -c 'README suite counts drift') -ge 1 ]] && echo 0 || echo 1)"
    printf '1000\n' > "$r72/repo/tests/.suite-baseline"
    r72_rc=0; r72_out=$(_r72_run --change CHG-9001) || r72_rc=$?
    report "T72 TC-1453 the fixture is green again once the baseline is restored" 0 "$r72_rc"

    r72_rc=0; r72_out=$(cd "$r72/repo" && bash scripts/dev/pre-review-check.sh --root "$r72/repo" --skip-audit 2>&1) || r72_rc=$?
    report "T72 TC-1453 a missing release.sh is a warning, not a failure" 0 "$r72_rc"
    r72_rc=0; r72_out=$(cd "$r72/repo" && bash scripts/dev/pre-review-check.sh --root "$r72/repo" --skip-audit --strict 2>&1) || r72_rc=$?
    report "T72 TC-1453 --strict promotes the warning to rc1" 1 "$r72_rc"
    r72_rc=0; r72_out=$(_r72_run --nope) || r72_rc=$?
    report "T72 TC-1453 an unknown pre-review argument dies rc2" 2 "$r72_rc"
    r72_rc=0; r72_out=$(_r72_run --change) || r72_rc=$?
    report "T72 TC-1444 a trailing --change dies rc2 instead of scanning every batch" 0 \
      "$([[ $r72_rc -eq 2 && $(printf '%s\n' "$r72_out" | grep -c -- '--change needs a value') -eq 1 ]] && echo 0 || echo 1)"
    report "T72 TC-1447 pre-review-check declares the source-layer boundary and stays unshipped" 0 \
      "$(grep -cE 'pre-review-check\.sh' "$ROOT/scripts/bootstrap.sh")"
    rm -rf "$r72"
  fi
}

section_T73() {
# ------------------------------------------------ T73 检查器自证：变异必须让检查器变红（v3.87.0，CHG-115，REQ-1190）
# 快路径检查器（版本载体 / 基线消费）一旦永绿，整条快路径就是假证据。本节在源仓的临时
# 副本上跑变异：四类枚举齐全、version-drift 被捕获、control 前后各一次绿，
# 且受跟踪文件逐字节不变——变异只发生在副本里，活树永远干净。
  local r73 r73_rc r73_out r73_before r73_after r73_n
  if [[ ! -f "$ROOT/scripts/dev/mutation-check.sh" || ! -f "$ROOT/scripts/release.sh" || ! -f "$ROOT/tests/.suite-baseline" ]]; then
    echo "SKIP T73: mutation-check.sh / release.sh / the committed baseline are absent (source-layer only)"
  else
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/dev/mutation-check.sh --list 2>&1) || r73_rc=$?
    r73_n=$(printf '%s\n' "$r73_out" | grep -cE '^(version-drift|gate-version-drift|baseline-missing|readme-count-drift)$')
    report "T73 TC-1457 --list enumerates the four fixed mutations" 4 "$r73_n"
    report "T73 TC-1457 --list exits 0" 0 "$r73_rc"
    r73_before=$(git -C "$ROOT" status --porcelain 2>/dev/null)
    r73_rc=0; r73_out=$(cd "$ROOT" && TMPDIR="${TMPDIR:-/tmp}" bash scripts/dev/mutation-check.sh --only version-drift 2>&1) || r73_rc=$?
    report "T73 TC-1458 version-drift makes the release checker red (sweep PASS rc0)" 0 "$r73_rc"
    report "T73 TC-1458 the caught verdict is printed" 1 "$(printf '%s\n' "$r73_out" | grep -c 'caught by the checker')"
    report "T73 TC-1460 the un-mutated control is green before and after" 2 "$(printf '%s\n' "$r73_out" | grep -c 'control green')"
    r73_after=$(git -C "$ROOT" status --porcelain 2>/dev/null)
    report "T73 TC-1459 the sweep leaves the live tree byte-identical" 0 "$([[ "$r73_before" == "$r73_after" ]] && echo 0 || echo 1)"
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/dev/mutation-check.sh --only not-a-mutation 2>&1) || r73_rc=$?
    report "T73 TC-1457 an unknown mutation name dies rc2" 2 "$r73_rc"
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/dev/mutation-check.sh --list --only 2>&1) || r73_rc=$?
    report "T73 TC-1444 a trailing --only dies rc2 instead of selecting every mutation" 0 \
      "$([[ $r73_rc -eq 2 && $(printf '%s\n' "$r73_out" | grep -c -- '--only needs a value') -eq 1 ]] && echo 0 || echo 1)"
    r73_rc=0; r73_out=$(cd "$ROOT" && bash scripts/dev/mutation-check.sh --root "$ROOT/does-not-exist" --list >/dev/null 2>&1) || r73_rc=$?
    report "T73 TC-1459 a missing --root dies rc2" 2 "$r73_rc"
    report "T73 TC-1460 the no-op mutation guard is part of the recipe" 1 "$(grep -cF 'no-op mutation' "$ROOT/scripts/dev/mutation-check.sh")"
    report "T73 TC-1460 the live-tree guard hashes every git-visible path, not a hand-picked list" 1 \
      "$(awk '/^live_state\(\)/,/^}/' "$ROOT/scripts/dev/mutation-check.sh" | grep -c -- '--others --exclude-standard')"
    report "T73 TC-1460 an empty live-tree listing is refused instead of comparing two empty files" 1 \
      "$(grep -cF '[ -s "$SNAP_BEFORE" ]' "$ROOT/scripts/dev/mutation-check.sh")"
    report "T73 TC-1447 mutation-check declares the source-layer boundary and stays unshipped" 0 \
      "$(grep -cE 'mutation-check\.sh' "$ROOT/scripts/bootstrap.sh")"
  fi
}

section_T73b() {
# ------------------------------------------------ T73b CI 证据汇总 + 批次指标（v3.87.0，CHG-115，REQ-1189/1191/1192/1193）
# 运行期真值只有一份：CI 全量跑出来的收据。ci-summary --check 把它和受跟踪基线硬对齐
# （陈旧基线在 CI 里响亮地红，而不是安静地 documenting 一个没人跑的数）；batch-metrics
# 把每批次的成本（轮次/编辑/轮询/整跑）落到 .agent-state 台账。两者都是源层私货。
  local r73b r73b_rc r73b_out r73b_head r73b_tree r73b_rec r73b_sum f
  if [[ ! -f "$ROOT/scripts/dev/ci-summary.sh" || ! -f "$ROOT/scripts/dev/batch-metrics.sh" || ! -f "$ROOT/scripts/dev/lib-source-facts.sh" ]]; then
    echo "SKIP T73b: ci-summary.sh / batch-metrics.sh absent (source-layer tools do not ship)"
  else
    r73b=$(mktemp -d "${TMPDIR:-/tmp}/ci-metrics.XXXXXX")
    mkdir -p "$r73b/repo/scripts" "$r73b/repo/tests" "$r73b/repo/resources" "$r73b/repo/.agent-state" "$r73b/repo/docs/changes/BATCH-20990101"
    mkdir -p "$r73b/repo/scripts/dev" && cp "$ROOT/scripts/dev/ci-summary.sh" "$ROOT/scripts/dev/batch-metrics.sh" "$ROOT/scripts/dev/lib-source-facts.sh" "$r73b/repo/scripts/dev/"
    cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r73b/repo/scripts/"
    printf '.agent-state/\n' > "$r73b/repo/.gitignore"
    printf '规范版本：v1.2.3\n' > "$r73b/repo/resources/DEVELOPMENT_STANDARDS.md"
    printf '1000\n' > "$r73b/repo/tests/.suite-baseline"
    printf '500\n' > "$r73b/repo/tests/.audit-baseline"
    printf '{"change_id": "CHG-9001", "risk_level": "L2"}\n' > "$r73b/repo/docs/changes/BATCH-20990101/00-governance.json"
    for f in 00-intent.md 01-spec.md 05-test-results.md; do printf '# %s\n' "$f" > "$r73b/repo/docs/changes/BATCH-20990101/$f"; done
    ( cd "$r73b/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
    r73b_head=$(git -C "$r73b/repo" rev-parse HEAD 2>/dev/null || true)
    # Seed the receipt with the value the CONSUMER computes, not HEAD^{tree}:
    # the fingerprint recipe differs from a bare tree OID as soon as anything in
    # the fixture is untracked or dirty, so a HEAD^{tree} seed only accidentally
    # matched while ci-summary ignored the field (v3.87.0 R4, review finding #7).
    r73b_tree=$(bash -c 'source "$1/scripts/dev/lib-source-facts.sh"; sf_tree_fingerprint "$1"' _ "$r73b/repo" 2>/dev/null || true)
    r73b_rec="$r73b/repo/.agent-state/last-suite-receipt.json"
    _r73b_seed() { printf '{"kind":"full","head":"%s","tree_fingerprint":"%s","passed":%s,"failed":%s,"wall_time_s":210,"generated_at":"now"}\n' "$1" "$2" "$3" "$4" > "$r73b_rec"; }
    _r73b_ci() { ( cd "$r73b/repo" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" bash scripts/dev/ci-summary.sh "$@" 2>&1 ); }
    _r73b_bm() { ( cd "$r73b/repo" && AGENT_GUARD_BATCH_METRICS_PATH="$r73b/repo/.agent-state/bm.json" AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" bash scripts/dev/batch-metrics.sh "$@" 2>&1 ); }

    _r73b_seed "$r73b_head" "$r73b_tree" 1000 0
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 the baseline gate is green when the receipt agrees" 0 "$r73b_rc"
    printf '999\n' > "$r73b/repo/tests/.suite-baseline"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a stale committed baseline fails the gate rc1" 1 "$r73b_rc"
    report "T73b TC-1461 the failure names both numbers and the sync command" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'baseline is 999 but the run passed 1000')"
    printf '1000\n' > "$r73b/repo/tests/.suite-baseline"
    _r73b_seed "$r73b_head" "$r73b_tree" 1000 3
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a red receipt fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'failed=3') -ge 1 ]] && echo 0 || echo 1)"
    _r73b_seed deadbeefdeadbeefdeadbeefdeadbeefdeadbeef "$r73b_tree" 1000 0
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a receipt from another HEAD fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'receipt HEAD') -ge 1 ]] && echo 0 || echo 1)"
    # The trust rule is one rule: ci-summary --check must reject the same receipt
    # sf_receipt_fresh rejects, otherwise "reused evidence" and "CI gate" disagree.
    _r73b_seed "$r73b_head" 0000000000000000000000000000000000000000 1000 0
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a same-HEAD receipt from another tree fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'tree fingerprint') -ge 1 ]] && echo 0 || echo 1)"
    rm -f "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a missing receipt fails the gate rc1" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'no suite receipt') -ge 1 ]] && echo 0 || echo 1)"
    printf '{"head":"%s","tree_fingerprint":"%s","failed":0,"generated_at":"now"}\n' "$r73b_head" "$r73b_tree" > "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1461 a receipt without a numeric passed field fails closed" 0 \
      "$([[ $r73b_rc -eq 1 && $(printf '%s\n' "$r73b_out" | grep -c 'no numeric passed field') -ge 1 ]] && echo 0 || echo 1)"
    _r73b_seed "$r73b_head" "$r73b_tree" 1000 0
    r73b_sum="$r73b/repo/.agent-state/step-summary.md"
    r73b_rc=0; r73b_out=$( cd "$r73b/repo" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" GITHUB_STEP_SUMMARY="$r73b_sum" bash scripts/dev/ci-summary.sh 2>&1 ) || r73b_rc=$?
    report "T73b TC-1461 the summary renderer exits 0 and prints the table" 0 \
      "$([[ $r73b_rc -eq 0 && $(printf '%s\n' "$r73b_out" | grep -c '| suite baseline (tests/.suite-baseline) | 1000 |') -ge 1 ]] && echo 0 || echo 1)"
    report "T73b TC-1461 the summary states the private-ledger scope explicitly" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'is not pushed and is \*\*not\*\* checked here')"
    report "T73b TC-1461 GITHUB_STEP_SUMMARY receives the same body" 1 "$([[ -s "$r73b_sum" ]] && echo 1 || echo 0)"
    report "T73b TC-1461 the version column resolves from the DS footer" 1 "$(printf '%s\n' "$r73b_out" | grep -c '| standards version | 1.2.3 |')"
    r73b_rc=0; r73b_out=$(_r73b_ci --nope) || r73b_rc=$?
    report "T73b TC-1461 an unknown ci-summary argument dies rc2" 2 "$r73b_rc"

    r73b_rc=0; r73b_out=$(_r73b_bm report) || r73b_rc=$?
    report "T73b TC-1462 reading a ledger that does not exist yet dies rc1" 1 "$r73b_rc"
    r73b_rc=0; r73b_out=$(_r73b_bm record --batch BATCH-20990101) || r73b_rc=$?
    report "T73b TC-1462 batch-metrics record writes the canonical TSV" 1 \
      "$([[ $r73b_rc -eq 0 && -s "$r73b/repo/.agent-state/bm.tsv" ]] && echo 1 || echo 0)"
    report "T73b TC-1462 the JSON mirror is regenerated from the TSV" 1 \
      "$([[ -s "$r73b/repo/.agent-state/bm.json" ]] && echo 1 || echo 0)"
    report "T73b TC-1462 the row carries artifact completeness and the batch id" 1 \
      "$(grep -c $'BATCH-20990101\tL2\tCHG-9001\t4/16' "$r73b/repo/.agent-state/bm.tsv")"
    r73b_rc=0; r73b_out=$(_r73b_bm report --batch BATCH-20990101) || r73b_rc=$?
    report "T73b TC-1462 report reads the batch row back" 0 \
      "$([[ $r73b_rc -eq 0 && $(printf '%s\n' "$r73b_out" | grep -c 'BATCH-20990101') -ge 1 ]] && echo 0 || echo 1)"
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1462 re-recording upserts instead of appending" 1 \
      "$([[ $(tail -n +2 "$r73b/repo/.agent-state/bm.tsv" | wc -l | tr -d ' ') -eq 1 ]] && echo 1 || echo 0)"
    report "T73b TC-1462 the JSON mirror splits artifacts and keeps the cost columns" 2 \
      "$(grep -oE '"artifacts_present":4,"artifacts_required":16|"suite_wall_s":210' "$r73b/repo/.agent-state/bm.json" | wc -l | tr -d ' ')"
    _r73b_bm record --batch 'Q"X' >/dev/null 2>&1
    report "T73b TC-1462 a quote in a ledger value cannot corrupt the JSON mirror" 1 \
      "$(grep -cF 'Q\"X' "$r73b/repo/.agent-state/bm.json")"
    r73b_rc=0; r73b_out=$(_r73b_bm nope) || r73b_rc=$?
    report "T73b TC-1462 an unknown batch-metrics action dies rc2" 2 "$r73b_rc"
    r73b_rc=0; r73b_out=$(_r73b_bm record --batch) || r73b_rc=$?
    report "T73b TC-1444 a trailing --batch dies rc2 instead of ledgering an empty batch id" 0 \
      "$([[ $r73b_rc -eq 2 && $(printf '%s\n' "$r73b_out" | grep -c -- '--batch needs a value') -eq 1 ]] && echo 0 || echo 1)"

    # Self-caught in the final measurement pass: a verify receipt carries "status"
    # inside every step as well as at the top level, and a generic last-match
    # reader returned the suite step — an audit-red batch got ledgered as pass.
    _r73b_vr() { printf '{\n  "schema": 1,\n  "status": "%s",\n  "steps": [{"name":"release","status":"pass","rc":0},{"name":"audit","status":"%s","rc":%s},{"name":"suite","status":"pass","rc":0}]\n}\n' "$1" "$2" "$3" \
      > "$r73b/repo/.agent-state/verify-receipt.json"; }
    _r73b_vfield() { tail -n 1 "$r73b/repo/.agent-state/bm.tsv" | cut -f16; }
    _r73b_vr fail fail 1
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1464 a red verify step is ledgered as fail, not as the suite step" 0 \
      "$([[ $(_r73b_vfield) == fail ]] && echo 0 || echo 1)"
    r73b_rc=0; r73b_out=$( cd "$r73b/repo" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r73b_rec" bash scripts/dev/ci-summary.sh 2>&1 ) || r73b_rc=$?
    report "T73b TC-1464 the CI summary prints the same top-level status, not a step's" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c '| verify-all status (if run locally) | fail |')"
    _r73b_vr pass pass 0
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1464 a green receipt is still ledgered as pass (the reader is not stuck on fail)" 0 \
      "$([[ $(_r73b_vfield) == pass ]] && echo 0 || echo 1)"
    rm -f "$r73b/repo/.agent-state/verify-receipt.json"
    _r73b_bm record --batch BATCH-20990101 >/dev/null 2>&1
    report "T73b TC-1464 a missing verify receipt is ledgered as none" 0 \
      "$([[ $(_r73b_vfield) == none ]] && echo 0 || echo 1)"

    # v3.88.0 (CHG-116, REQ-1198): only a full run may pose as full authority.
    # kind is the machine boundary — a partial (auto) receipt and a pre-v3.88
    # legacy receipt without any kind both fail closed; kind:"full" keeps the
    # pre-existing green path so the boundary adds no false reds.
    printf '{"kind":"partial","head":"%s","tree_fingerprint":"%s","sections":"T50 T70","passed":1000,"failed":0,"wall_time_s":9,"generated_at":"now"}\n' "$r73b_head" "$r73b_tree" > "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1480 a partial receipt is not full authority (rc1)" 1 "$r73b_rc"
    report "T73b TC-1480 the finding says partial receipts are rejected" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'not full authority')"
    printf '{"head":"%s","tree_fingerprint":"%s","passed":1000,"failed":0,"wall_time_s":210,"generated_at":"now"}\n' "$r73b_head" "$r73b_tree" > "$r73b_rec"
    r73b_rc=0; r73b_out=$(_r73b_ci --check) || r73b_rc=$?
    report "T73b TC-1481 a legacy receipt without a kind field fails closed" 1 "$r73b_rc"
    report "T73b TC-1481 the finding names the missing kind" 1 \
      "$(printf '%s\n' "$r73b_out" | grep -c 'kind')"
    _r73b_seed "$r73b_head" "$r73b_tree" 1000 0
    r73b_rc=0; _r73b_ci --check >/dev/null 2>&1 || r73b_rc=$?
    report "T73b TC-1482 a kind:full receipt keeps the green path" 0 "$r73b_rc"
    report "T73b TC-1472 the A56 leak ring grew to 14 tokens and six discipline tags" 1 \
      "$([[ $(sed -n 's/.*split("\([^"]*\)", wd, "|").*/\1/p' "$ROOT/tests/audit-standards-src.sh" | tr '|' '\n' | grep -c . | tr -d ' ') == 14 && $(grep -oE 'PD-[0-9]' "$ROOT/tests/audit-standards-src.sh" | sort -u | wc -l | tr -d ' ') == 6 ]] && echo 1 || echo 0)"

    report "T73b TC-1462 both evidence tools declare the source-layer boundary" 2 \
      "$( { grep -cF 'Source-layer only (NOT shipped with the Skill)' "$ROOT/scripts/dev/ci-summary.sh"; grep -cF 'Source-layer only (NOT shipped with the Skill)' "$ROOT/scripts/dev/batch-metrics.sh"; } | awk '{s+=$1} END{print s}')"
    report "T73b TC-1462 bootstrap ships neither the CI summarizer nor the metrics ledger" 0 \
      "$(grep -cE 'ci-summary\.sh|batch-metrics\.sh' "$ROOT/scripts/bootstrap.sh")"
    report "T73b TC-1462 the private maintenance workspace stays untracked" 0 \
      "$(git -C "$ROOT" ls-files .opencode 2>/dev/null | wc -l | tr -d ' ')"
    rm -rf "$r73b"
  fi
}

section_T74() {
# ------------------------------------------------ T74 pre-review 声称链对账（v3.88.0，CHG-116，REQ-1194）
# F5/N6 两母题的机检化：机器面（run-tests report 行的 TC 号）与声称面（04 映射表+落点清单+01.5
# 矩阵）双向差集必红；01.5 的 file:line（token）锚点逐条实测行内容。对账对象在 gitignored
# docs/，本节只在本地 pre-review 存在——CI 的 not-checked-here 边界不变。
  local r74 r74_rc r74_out r74_art f
  if [[ ! -f "$ROOT/scripts/dev/pre-review-check.sh" || ! -f "$ROOT/scripts/dev/lib-source-facts.sh" ]]; then
    echo "SKIP T74: pre-review-check.sh / lib-source-facts.sh absent (source-layer tools do not ship)"
  else
    r74=$(mktemp -d "${TMPDIR:-/tmp}/claims.XXXXXX")
    mkdir -p "$r74/repo/scripts" "$r74/repo/tests" "$r74/repo/.agent-state"
    mkdir -p "$r74/repo/scripts/dev" && cp "$ROOT/scripts/dev/pre-review-check.sh" "$ROOT/scripts/dev/lib-source-facts.sh" "$r74/repo/scripts/dev/"
    printf '.agent-state/\n' > "$r74/repo/.gitignore"
    printf 'README (1000 golden-case assertions) (assertions: 500)\n' > "$r74/repo/README.md"
    printf '这里声称 1000 项 golden-case 断言（断言：500）。\n' > "$r74/repo/README.zh-CN.md"
    printf '1000\n' > "$r74/repo/tests/.suite-baseline"
    printf '500\n' > "$r74/repo/tests/.audit-baseline"
    # synthetic machine face: two report TC ids the claims face must mirror
    printf '# runner\nreport "T1 TC-1466 alpha" 0 0\nreport "T1 TC-1467 beta" 0 0\n' > "$r74/repo/tests/run-tests.sh"
    # anchor target: token lives on line 3
    printf '# tool\n# line two\n采集入口 here\n' > "$r74/repo/scripts/tool.sh"
    r74_art="$r74/repo/docs/changes/BATCH-20990102"
    mkdir -p "$r74_art"
    for f in 00-intent.md 00.5-communication.md 01-spec.md 01.5-rtvm-matrix.md 02-code-impact-analysis.md \
             03-modification-plan.md 03.5-tasks.md 04-test-scripts.md 04.5-coding-record.md 05-test-results.md \
             06-delivery-summary.md 06.5-deployment-config.md 07-review-report.md 09-changelog.md handoff.md; do
      printf '# %s\n\n正文。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->\n' "$f" > "$r74_art/$f"
    done
    printf '{"change_id": "CHG-9002", "risk_level": "L1", "spec_author": "alice", "implementation_owner": "bob", "test_owner": "carol", "review_owner": "dave"}\n' > "$r74_art/00-governance.json"
    printf -- '- 确认状态：已确认\n' >> "$r74_art/00.5-communication.md"
    printf '套件：1127 passed, 0 failed\n' >> "$r74_art/05-test-results.md"
    printf '评审人：dave\n评审结论：通过\n' >> "$r74_art/07-review-report.md"
    printf 'TC-1466 TC-1467 两条用例，落点节 T1。\n- TC-1466 → 节 T1\n- TC-1467 → 节 T1\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/04-test-scripts.md"
    printf '矩阵：TC-1466/TC-1467；锚点 `scripts/tool.sh:3`（采集入口）。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/01.5-rtvm-matrix.md"
    ( cd "$r74/repo" && git init -q >/dev/null 2>&1 && git add -A >/dev/null 2>&1 \
      && git -c user.email=t@t.local -c user.name=t commit -qm seed >/dev/null 2>&1 )
    _r74_run() { ( cd "$r74/repo" && bash scripts/dev/pre-review-check.sh 2>&1 ); }
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1466 an aligned claims chain passes" 0 "$r74_rc"
    report "T74 TC-1466 the claims line reports the verified id count" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'claims chain: 2 machine TC ids')"
    report "T74 TC-1469 the green run verifies the 01.5 anchor" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'claims chain:.*1 anchors')"
    # machine face grew, docs did not (F5 family: TC-1465 incident)
    printf '# runner\nreport "T1 TC-1466 alpha" 0 0\nreport "T1 TC-1467 beta" 0 0\nreport "T1 TC-1468 gamma" 0 0\n' > "$r74/repo/tests/run-tests.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1467 an unregistered TC fails and is named" 1 "$r74_rc"
    report "T74 TC-1467 the finding says unregistered and names the id" 1 \
      "$(printf '%s\n' "$r74_out" | grep -cE 'unregistered TC.*TC-1468')"
    # docs claim a TC no report line produces
    printf 'TC-1466 TC-1467 TC-9999 三条用例。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/04-test-scripts.md"
    printf '# runner\nreport "T1 TC-1466 alpha" 0 0\nreport "T1 TC-1467 beta" 0 0\n' > "$r74/repo/tests/run-tests.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1468 a phantom TC fails and is named" 1 "$r74_rc"
    report "T74 TC-1468 the finding says phantom and names the id" 1 \
      "$(printf '%s\n' "$r74_out" | grep -cE 'phantom TC.*TC-9999')"
    # anchor freshness: token moved away from the pinned line
    printf '矩阵：TC-1466/TC-1467；锚点 `scripts/tool.sh:3`（采集入口）。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/01.5-rtvm-matrix.md"
    printf 'TC-1466 TC-1467 两条用例。\n<!-- provenance: CHG-9002 batch BATCH-20990102 -->' > "$r74_art/04-test-scripts.md"
    printf '# tool\n# moved\n# down\n# three\n采集入口 here\n' > "$r74/repo/scripts/tool.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1470 a drifted anchor fails and names file:line" 1 "$r74_rc"
    report "T74 TC-1470 the finding names the drifted anchor" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'tool.sh:3.（采集入口）')"
    # dangling: the anchored file is gone
    printf '# tool\n# line two\n采集入口 here\n' > "$r74/repo/scripts/tool.sh"
    rm "$r74/repo/scripts/tool.sh"
    r74_rc=0; r74_out=$(_r74_run) || r74_rc=$?
    report "T74 TC-1471 a dangling anchor file fails and is named" 1 "$r74_rc"
    report "T74 TC-1471 the finding says dangling" 1 \
      "$(printf '%s\n' "$r74_out" | grep -c 'dangling')"
    rm -rf "$r74"
  fi
}

section_T75() {
# ------------------------------------------------ T75 -T auto 裁剪 + 部分收据隔离（v3.88.0，CHG-116，REQ-1197/1198）
# 映射是优化、不是正确性依赖：无映射命中 / runner 自改一律回落全量。partial 收据只落
# last-suite-partial.json（kind:"partial"），权威路径 last-suite-receipt.json 永不被部分运行触碰。
  local r75 r75_rc r75_out r75_rec r75_part
  if ! is_source_layout; then
    echo "SKIP T75: -T auto maps source-layer tools (source repo layout only)"
  else
    r75=$(mktemp -d "${TMPDIR:-/tmp}/auto.XXXXXX")
    r75_rec="$r75/last-suite-receipt.json"
    r75_part="$r75/last-suite-partial.json"
    # resolution-only seam: decide without executing sections
    # E160-5 既有豁免,本次仅路径改名(scripts/ -> scripts/dev/),非新增例外 owner=geek007 期限=2026-12-31
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="scripts/dev/facts.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
      bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1476 auto maps a changed tool to its sections plus the registry pin" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: T50 T70')"
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="unknown/unmapped.xyz,scripts/dev/facts.sh" \
      AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1477 an unmapped changed file falls back to FULL" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: FULL')"
    # TC-1496/1497 (2026-10-25 wiring): two gaps the old 12-entry table left open —
    # docs/artifacts dragged a 25-minute FULL run in, and the standards body itself
    # was unmapped. Both are pure selection logic (resolve-only, no execution).
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="docs/changes/CHG-001/05-test-results.md,MAINTAINER.md" \
      AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1496 suite-irrelevant files resolve to NONE (no suite)" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: NONE')"
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="resources/DEVELOPMENT_STANDARDS.md" \
      AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1497 the standards body maps to its sections (registry pin in source order)" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only:.*T48 T50 T55')"
    r75_out=$(AGENT_GUARD_SUITE_AUTO_DIFF="tests/run-tests.sh" AGENT_GUARD_SUITE_AUTO_RESOLVE_ONLY=1 \
      bash "$ROOT/tests/run-tests.sh" -T auto 2>&1)
    report "T75 TC-1479 a runner self-edit always resolves to FULL" 1 \
      "$(printf '%s\n' "$r75_out" | grep -c 'auto-resolve-only: FULL')"
    # real partial run (T50+T70 are seconds): the authority path must stay untouched
    r75_rc=0
    AGENT_GUARD_SUITE_AUTO_DIFF="scripts/dev/facts.sh" AGENT_GUARD_SUITE_RECEIPT_PATH="$r75_rec" \
      AGENT_GUARD_SUITE_PARTIAL_PATH="$r75_part" AGENT_GUARD_SESSION_STATS_PATH="$r75/stats.json" \
      bash "$ROOT/tests/run-tests.sh" -T auto -j 2 >/dev/null 2>&1 || r75_rc=$?
    report "T75 TC-1476 a mapped auto run is green and writes a partial receipt" 0 "$r75_rc"
    report "T75 TC-1476 the partial receipt carries kind:partial" 1 \
      "$(grep -c '"kind":"partial"' "$r75_part" 2>/dev/null)"
    report "T75 TC-1478 the authority receipt path is never touched by a partial run" 0 \
      "$([[ ! -e "$r75_rec" ]] && echo 0 || echo 1)"
    rm -rf "$r75"
  fi
}

section_T76() {
# ------------------------------------------------ T76 套件自记 full_suite（v3.88.0，CHG-116，REQ-1196）
# 全量运行才是一次"套件购买"：full_suite 只在全量路径 +1（-T 部分 run 与 verify-all 复用都不算）。
# 计数器本体用 FAKE_FULL seam 实跑（真实全跑在收口权威一次时自证——05 引 stats 增量）；门控
# 本身用真实 -T 不加 seam 钉（TC-1474），A57 另钉条件行结构。
  local r76 r76_rc r76_out r76_stats r76_after
  if ! is_source_layout; then
    echo "SKIP T76: session stats self-counting ships with the runner's tools (source repo layout only)"
  else
    r76=$(mktemp -d "${TMPDIR:-/tmp}/stats.XXXXXX")
    r76_stats="$r76/stats.json"
    printf '{"turns":3,"full_suite":4,"edits":1,"sleep_polls":0}\n' > "$r76_stats"
    r76_rc=0
    AGENT_GUARD_SESSION_STATS_PATH="$r76_stats" AGENT_GUARD_SUITE_FAKE_FULL=1 \
      AGENT_GUARD_SUITE_RECEIPT_PATH="$r76/rec.json" bash "$ROOT/tests/run-tests.sh" -T T50 >/dev/null 2>&1 || r76_rc=$?
    r76_after=$(sed -n 's/.*"full_suite":\([0-9]*\).*/\1/p' "$r76_stats" | tail -1)
    report "T76 TC-1473 a full run increments full_suite and preserves sibling keys" 0 \
      "$([[ $r76_rc -eq 0 && $r76_after == 5 && $(grep -c '"turns":3' "$r76_stats") -eq 1 ]] && echo 0 || echo 1)"
    r76_rc=0
    AGENT_GUARD_SESSION_STATS_PATH="$r76_stats" \
      AGENT_GUARD_SUITE_RECEIPT_PATH="$r76/rec.json" bash "$ROOT/tests/run-tests.sh" -T T50 >/dev/null 2>&1 || r76_rc=$?
    r76_after=$(sed -n 's/.*"full_suite":\([0-9]*\).*/\1/p' "$r76_stats" | tail -1)
    report "T76 TC-1474 a filtered run never touches the counter (real gating)" 0 \
      "$([[ $r76_rc -eq 0 && $r76_after == 5 ]] && echo 0 || echo 1)"
    r76_rc=0
    mkdir -p "$r76/ro" && chmod 555 "$r76/ro"
    AGENT_GUARD_SESSION_STATS_PATH="$r76/ro/stats.json" AGENT_GUARD_SUITE_FAKE_FULL=1 \
      AGENT_GUARD_SUITE_RECEIPT_PATH="$r76/rec.json" bash "$ROOT/tests/run-tests.sh" -T T50 >"$r76/out.log" 2>&1 || r76_rc=$?
    chmod 755 "$r76/ro"
    report "T76 TC-1475 a stats write failure warns but never blocks the suite" 0 \
      "$([[ $r76_rc -eq 0 && $(grep -c 'non-fatal' "$r76/out.log") -ge 1 ]] && echo 0 || echo 1)"
    rm -rf "$r76"
  fi
}

section_T77() {
# ------------------------------------------------ T77 gate 无账源码改动门（v3.89.0，CHG-117，REQ-1200，DES-1956）
# 交付边界 fail-closed：staged 扫暂存面、stop 扫 git status 合并面；豁免阶梯 =
# 活跃变更 / 当日缺陷组 / AGENT_GUARD_ALLOW_UNACCOUNTED=1（WARN 不静默，09 义务）。
if [[ ! -f "$GATE_SRC" ]]; then echo "SKIP T77: agent-gate absent"; return 0; fi
# TC-1483 red: staged source change, no active change, no same-day defect batch
new_repo
printf 'chg\n' > src/a.go
git add src/a.go
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1483 staged unaccounted source change dies E125" 2 "$t77_rc"
check_output "T77 TC-1483 die message carries the three-option ladder" "bind the defect batch" "$t77_out"
check_output "T77 TC-1483 die message names the exemption env" "AGENT_GUARD_ALLOW_UNACCOUNTED" "$t77_out"
check_output "T77 TC-1483 die message anchors standards §2.17.2b" "2\.17\.2b" "$t77_out"
# TC-1483b stop lane scans the merged worktree face (untracked source file included)
new_repo
printf 'x\n' > src/b.py
t77_out=$(scripts/agent-gate --stage stop 2>&1); t77_rc=$?
report "T77 TC-1483b stop merged face catches an untracked source file" 2 "$t77_rc"
check_output "T77 TC-1483b the stop-face red is E125 (not a downstream artifact complaint)" "GATE-E125" "$t77_out"
# TC-1483c: staged DELETION of tracked source is a source change too (A/M/R/D face)
new_repo
printf 'x\n' > src/gone.py
git add src/gone.py && git commit -qm addsrc
git rm -q src/gone.py
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1483c staged source deletion is unaccounted (E125)" 2 "$t77_rc"
check_output "T77 TC-1483c the deletion red is E125" "GATE-E125" "$t77_out"
# TC-1484 green: active change in place
new_repo
seed_begin CHG-1170 L1 claude/s-1
printf 'chg\n' > src/a.go
git add src/a.go
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T77 TC-1484 staged source change with an active change passes" 0 $?
# TC-1484b/c (独立评审 F2): an empty same-day batch directory is NOT a credential —
# the identity piece (01-diagnosis.md with a `## BUG-` anchor) is what counts.
# The assertion is scoped to E125: downstream gates (E57 completeness / E66
# change-artifact rule) keep their own bars and are not this case's subject.
new_repo
mkdir -p "docs/bugs/BATCH-$(date -u +%Y%m%d)"
printf 'chg\n' > src/a.go
git add src/a.go
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1484b empty same-day defect-batch dir does not exempt E125" 2 "$t77_rc"
check_output "T77 TC-1484b the red is E125 (no silent exemption)" "GATE-E125" "$t77_out"
printf '## BUG-9002\nseverity: P3\n诊断骨架\n' > "docs/bugs/BATCH-$(date -u +%Y%m%d)/01-diagnosis.md"
t77_out=$(scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1484c same-day batch carrying a BUG anchor clears E125" 0 "$(printf '%s\n' "$t77_out" | grep -c 'GATE-E125')"
# TC-1485a docs-only staged face never trips the gate (is_code_path exclusion face)
new_repo
seed_begin CHG-1171 L1 claude/s-1b
printf 'docs\n' >> README.md
git add README.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T77 TC-1485a docs-only staged change passes" 0 $?
# TC-1485b explicit env bypass is loud and does not hide the artifacts backstop
new_repo
printf 'chg\n' > src/a.go
git add src/a.go
seed_artifacts CHG-1172 L1 claude/s-1c   # complete artifacts face, deliberately NOT begun
t77_out=$(AGENT_GUARD_ALLOW_UNACCOUNTED=1 scripts/agent-gate --stage staged 2>&1); t77_rc=$?
report "T77 TC-1485b env bypass releases the unaccounted gate (artifacts face still enforced)" 0 "$t77_rc"
check_output "T77 TC-1485b bypass is never silent (WARN line, 09 duty)" "WARN" "$t77_out"
}

section_T78() {
# ------------------------------------------------ T78 session-gate check 两态 + idle 收窄（v3.89.0，CHG-117，REQ-1199/1200，DES-1957/1958）
if [[ ! -f "$SESSION_GATE_SRC" ]]; then echo "SKIP T78: session-gate absent"; return 0; fi
new_repo
t_install_session_gate
# TC-1486 red: unaccounted source edit at edit time → exit 2 + three options
t78_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check 2>&1); t78_rc=$?
report "T78 TC-1486 check blocks an unaccounted source edit (exit 2)" 2 "$t78_rc"
check_output "T78 TC-1486 message carries the signal-③ three options" "三选项" "$t78_out"
check_output "T78 TC-1486 message names AGENT_GUARD_ALLOW_UNACCOUNTED" "ALLOW_UNACCOUNTED" "$t78_out"
# TC-1486b: Claude PreToolUse hands an ABSOLUTE file_path — normalization, not a silent bypass
t78_out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/a.go"}}' "$PWD" | bash scripts/session-gate.sh check 2>&1); t78_rc=$?
report "T78 TC-1486b absolute hook path still hits the unaccounted gate (exit 2)" 2 "$t78_rc"
check_output "T78 TC-1486b absolute-path message carries the signal-③ three options" "三选项" "$t78_out"
# TC-1486c (独立评审 F4): a physical-root path into a NOT-yet-existing directory
# (dirname cannot be pwd -P'd) must still normalize, not fall open.
t78_phys=$(cd "$REPO" && pwd -P)
t78_out=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/newdir/a.go"}}' "$t78_phys" | bash scripts/session-gate.sh check 2>&1); t78_rc=$?
report "T78 TC-1486c physical path into a new directory still hits the gate" 2 "$t78_rc"
check_output "T78 TC-1486c normalized physical-path red is the unaccounted gate" "三选项" "$t78_out"
# TC-1487 green: accounted edit (active change + G-测试门 face) and docs paths
seed_begin CHG-1173 L1 claude/s-1
mkdir -p tests && printf 'assert "t78"\n' > tests/test_a.py
t_tc_landing docs/changes/CHG-1173/04-test-scripts.md tests/test_a.py
t78_rc=0
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t78_rc=$?
report "T78 TC-1487 accounted source edit with the testplan face in place passes" 0 "$t78_rc"
t78_rc=0
printf '{"tool_name":"Write","tool_input":{"file_path":"docs/notes.md"}}' | bash scripts/session-gate.sh check >/dev/null 2>&1 || t78_rc=$?
report "T78 TC-1487b docs-path edit passes (exclusion face)" 0 "$t78_rc"
# TC-1488 SKIP_VERIFY narrowing (DES-1958): the env + the internal idle marker
# never waive the unaccounted gate — only the three structural exemptions do.
new_repo
t_install_session_gate
printf 'x\n' > src/a.go
git add src/a.go
t78_out=$(AGENT_GUARD_SKIP_VERIFY=1 AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle scripts/agent-gate --stage staged 2>&1); t78_rc=$?
report "T78b TC-1488a SKIP_VERIFY=1 + idle marker still red on the staged face" 2 "$t78_rc"
check_output "T78b TC-1488a the red is the unaccounted gate (E125), not a skip" "GATE-E125" "$t78_out"
t78_out=$(AGENT_GUARD_SKIP_VERIFY=1 AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle scripts/agent-gate --stage stop 2>&1); t78_rc=$?
report "T78b TC-1488b same narrowing on the stop merged face" 2 "$t78_rc"
check_output "T78b TC-1488b the stop-face red is E125" "GATE-E125" "$t78_out"
t78_rc=0
AGENT_GUARD_SKIP_VERIFY_CONTEXT=idle scripts/agent-gate --stage staged >/dev/null 2>&1 || t78_rc=$?
report "T78b TC-1488c the internal marker alone grants nothing (anti-spoof)" 2 "$t78_rc"
}

