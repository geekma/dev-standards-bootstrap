#!/usr/bin/env bash
# suite-06-runner.sh — domain suite module (v4.13.0, CHG-158)

section_T50() {
  local t50_out t50_rc t50_list t50_expect
  local t50_n39 t50_n38 t50_green t50_n t50_dup t50_first t50_last
  t50_out=$(bash "$ROOT/tests/run-tests.sh" -T T39 2>&1); t50_rc=$?
  # bash [[ ]] parses no bare pipelines; precompute all intermediates (learned:
  # nested $() inside [[ ]] inside "$()" mis-parses on bash 3.2 — TC-1115 first
  # run died with "conditional binary operator expected").
  t50_n39=$(printf '%s\n' "$t50_out" | grep -c '^ok   T39')
  t50_n38=$(printf '%s\n' "$t50_out" | grep -c '^ok   T38')
  t50_green=$(grep -q ', 0 failed$' <<< "$t50_out" && echo 1 || echo 0)
  # v3.92.3: T39 reads resources/CLAUSE_REGISTRY.md, which a target repo does
  # not have (it lives under <docs>/). The explicit SKIP is the adaptive face;
  # requiring >=3 ok lines here made T50 red in every installed repo.
  t50_skip39=$(printf '%s\n' "$t50_out" | grep -c '^SKIP T39')
  report "T50 -T isolates single section (TC-1115)" 0 "$([[ $t50_rc -eq 0 && ( $t50_n39 -ge 3 || $t50_skip39 -ge 1 ) && $t50_n38 -eq 0 && "$t50_green" == 1 ]] && echo 0 || echo 1)"
  report "T50 unknown section dies rc2 (TC-1116)" 2 "$(bash "$ROOT/tests/run-tests.sh" -T NOPE >/dev/null 2>&1; echo $?)"
  report "T50 wall-time is last line (TC-1117)" 1 "$(printf '%s\n' "$t50_out" | tail -1 | grep -cE '^wall-time: [0-9]+s$')"
  report "T50 summary anchor intact before wall-time (TC-1117)" 1 "$(printf '%s\n' "$t50_out" | tail -2 | head -1 | grep -cE '^[0-9]+ passed, [0-9]+ failed$')"
  t50_out=$(bash "$ROOT/tests/run-tests.sh" -T T39,T38 2>&1)
  # The first section marker can be a SKIP line in a target repo (T38's source
  # fixtures are absent, so it emits only FAIL lines); match the section id
  # rather than the "ok" prefix.
  report "T50 -T multi keeps source order (TC-1119)" "T38" "$(printf '%s\n' "$t50_out" | grep -m1 -oE 'T3[89]')"
  t50_list=$(bash "$ROOT/tests/run-tests.sh" -l 2>&1); t50_rc=$?
  t50_expect=$(grep -h -c '^section_' "$ROOT/tests/run-tests.sh" "$ROOT/tests/suites/"*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')
  t50_n=$(printf '%s\n' "$t50_list" | grep -c '^T')
  t50_dup=$(printf '%s\n' "$t50_list" | sort | uniq -d)
  t50_first=$(printf '%s\n' "$t50_list" | head -1)
  t50_last=$(printf '%s\n' "$t50_list" | tail -1)
  # v3.66.0 (CHG-088): expected tail recalibrated T50→T51 after the receipt
  # self-test section joined the registry (same dynamic-count discipline).
  # v3.68.0 (CHG-043): tail recalibrated T52→T53 — T52 was taken by CHG-090 UX
  # gates, so the G13/G14 section registered as T53 (registry growth only;
  # count stays dynamic via t50_expect).
  # CHG-044: tail recalibrated T53→T54 (G14e element-enumeration section joins).
  # CHG-046: tail recalibrated T54→T55 (delivery four-gate section joins).
  # CHG-094: tail recalibrated T55→T56 (begin-artifact preflight probe joins).
  # CHG-095: tail recalibrated T56→T57 (parallel-dispatch / red-archive self-test joins).
  # CHG-096: tail recalibrated T57→T58 (telemetry discipline self-test joins).
  # CHG-100: tail recalibrated T60→T61 (验证通道方言与四态 golden 节 joins).
  # CHG-102: tail recalibrated T62→T63 (本变更注册 T63「治理面口径 + 下发面缺口」节).
  # CHG-109: tail recalibrated T63→T65 (秒级形状探针节 joins; T64 stays mid-list
  #   per CHG-107 scaffold ordering).
  # CHG-110: tail recalibrated T65→T66 (verify 结果缓存节 joins; TC-1414).
  # CHG-111: tail recalibrated T66→T67 (六不变量机校节 joins; TC-1424~1432).
  # CHG-113: tail recalibrated T67→T68; CHG-115: T68→T73b (基线/事实/编排/前置/变异/汇总六节 joins).
  # CHG-117: tail recalibrated T76→T81 (无账门/编辑硬拦/G16/阶段门/阶段感知五节 joins).
  # CHG-128: tail recalibrated T83→T84 (五道交付质量门 golden 节 joins).
  # CHG-129: tail recalibrated T84→T85 (repeat-run guard 节 joins).
  # CHG-131: tail recalibrated T85→T86 (dispatch-contract v2 节 joins).
  # CHG-132: tail recalibrated T86→T87 (套件基建并行/缓存节 joins).
  # CHG-145: tail recalibrated T87→T88 (E160 五类 diff-watch golden 节 joins).
  report "T50 -l lists all sections uniquely (TC-1120)" 0 "$([[ $t50_rc -eq 0 && $t50_n -eq "$t50_expect" && -z "$t50_dup" && "$t50_first" == T1 && "$t50_last" == T88 ]] && echo 0 || echo 1)"
}

section_T51() {
  # v3.92.3: target repos do not receive the source-layer receipt tools. The
  # section is a self-test of THEM, so skip explicitly instead of red-lighting
  # every installed suite (G-ENV must stay usable without the source layer).
  if [[ ! -f "$ROOT/scripts/dev/update-assertion-count.sh" || ! -f "$ROOT/scripts/dev/lib-source-facts.sh" ]]; then
    echo "SKIP T51: source-layer receipt tools absent (target repo) — 跳过收据采信自测"
    return 0
  fi
  local r51 r51_head r51_out r51_rc r51_receipt r51_ts
  local r51_sentinel r51_has999 r51_has777 r51_same r51_same2 r51_had
  local r51_tree fp1 fp2 fp3 r51_pre r51_post r51_mis r51_ng r51_ngfp r51_ng2
  r51=$(mktemp -d "${TMPDIR:-/tmp}/receipt-test.XXXXXX")
  mkdir -p "$r51/scripts" "$r51/tests" "$r51/.agent-state"
  mkdir -p "$r51/scripts/dev" && cp "$ROOT/scripts/dev/update-assertion-count.sh" "$r51/scripts/dev/"
  # v3.79.0 (CHG-103, REQ-1144): fixture carries the SAME fingerprint lib the
  # consumer sources, and ignores .agent-state like the real repo — without the
  # ignore rule the receipt file itself would be untracked content and shift
  # the tree fingerprint (TC-1378 would false-red for the wrong reason).
  printf '.agent-state/\n' > "$r51/.gitignore"
  cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r51/scripts/"
  mkdir -p "$r51/scripts/dev" && cp "$ROOT/scripts/dev/lib-source-facts.sh" "$r51/scripts/dev/"
  cat > "$r51/tests/run-tests.sh" <<'R51FAKE'
#!/usr/bin/env bash
: > "$(dirname "$0")/.embedded-ran"
printf '777 passed, 0 failed\n'
printf 'wall-time: 1s\n'
R51FAKE
  printf 'README claims 888 golden-case assertions here.\n' > "$r51/README.md"
  printf '这里声称 888 项 golden-case 断言。\n' > "$r51/README.zh-CN.md"
  ( cd "$r51" && git init -q && git add -A >/dev/null 2>&1 \
    && git -c user.email=t@t.local -c user.name=t commit -qm init >/dev/null 2>&1 )
  r51_head=$(git -C "$r51" rev-parse HEAD 2>/dev/null || true)
  r51_receipt="$r51/.agent-state/last-suite-receipt.json"
  # v3.79.0 (CHG-103): the clean fixture tree fingerprints as HEAD^{tree} — the
  # identity TC-1382 pins. The receipt file itself is gitignored, so seeding it
  # does not shift the fingerprint.
  r51_tree=$(git -C "$r51" rev-parse HEAD^{tree} 2>/dev/null || true)
  # _r51_seed <head> <passed> <failed> [tree_fp]：播种收据并清哨兵。
  # v3.79.0：第 4 参非空 → 新 schema（含 tree_fingerprint）；空 → 旧 5 字段 schema
  # （TC-1381 反向兼容反证用：无指纹字段一律视为不新鲜）。
  _r51_seed() {
    if [[ -n "${4:-}" ]]; then
      printf '{"head":"%s","tree_fingerprint":"%s","passed":%s,"failed":%s,"wall_time_s":1,"generated_at":"2026-01-01T00:00:00Z"}\n' \
        "$1" "$4" "$2" "$3" > "$r51_receipt"
    else
      printf '{"head":"%s","passed":%s,"failed":%s,"wall_time_s":1,"generated_at":"2026-01-01T00:00:00Z"}\n' \
        "$1" "$2" "$3" > "$r51_receipt"
    fi
    rm -f "$r51/tests/.embedded-ran"
  }
  # _r51_run：fixture 内 UAC 调用。MAX_AGE 显式钉 30——防外层调用方 env（如
  # UAC 强制内嵌跑 MAX_AGE=0）泄漏进 fixture 使采信门整体跳过（TC-1121/1378/
  # 1379/1381 全依赖采信门参与判定；实测红档四连）；TC-1122d 自带显式 0 覆盖。
  _r51_run() { ( cd "$r51" && AGENT_GUARD_SUITE_RECEIPT_PATH="$r51_receipt" AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=30 bash scripts/dev/update-assertion-count.sh --check 2>&1 ); }

  # TC-1121 采信主证：合法新鲜同 HEAD 收据 → 跳过内嵌（哨兵不在）+ N 来自收据（999）
  # v3.79.0（CHG-103）：fixture 升新 schema（含同树指纹）；TC-1378 追加断言指纹门参与判定
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has999=$(printf '%s\n' "$r51_out" | grep -c 'expected 999')
  report "T51 fresh same-HEAD receipt trusted, embedded run skipped (TC-1121)" 0 "$([[ "$r51_sentinel" == 0 && "$r51_has999" -ge 1 ]] && echo 0 || echo 1)"
  r51_has999=$(printf '%s\n' "$r51_out" | grep -c 'tree-match')
  report "T51 trust path reports tree fingerprint match (TC-1378)" 0 "$([[ "$r51_sentinel" == 0 && "$r51_has999" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122a head 不匹配 → 拒采（哨兵在 + expected 777）
  _r51_seed deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 999 0
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 head-mismatch receipt re-embeds (TC-1122a)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122b 陈旧 mtime（2h 前）→ 拒采
  _r51_seed "$r51_head" 999 0
  r51_ts=$(date -v-2H +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M.%S)
  touch -t "$r51_ts" "$r51_receipt"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 stale receipt re-embeds (TC-1122b)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122c 损坏 JSON → 拒采
  _r51_seed "$r51_head" 999 0
  printf 'not json at all\n' > "$r51_receipt"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 malformed receipt re-embeds (TC-1122c)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1122d MAX_AGE_MIN=0（禁用采信）→ 拒采
  _r51_seed "$r51_head" 999 0
  # E160-5 既有豁免,本次仅路径改名(scripts/ -> scripts/dev/),非新增例外 owner=geek007 期限=2026-12-31
  r51_out=$( cd "$r51" && AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN=0 bash scripts/dev/update-assertion-count.sh --check 2>&1 || true )
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 MAX_AGE_MIN=0 disables trusting (TC-1122d)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"

  # TC-2390（CHG-142，REQ-1379）：--from-evidence 分片求和 → 基线/README 同步
  r142=$(mktemp -d "${TMPDIR:-/tmp}/evidence-sync.XXXXXX")
  mkdir -p "$r142/scripts" "$r142/tests" "$r142/evidence/CHG-990/round-1"
  mkdir -p "$r142/scripts/dev" && cp "$ROOT/scripts/dev/update-assertion-count.sh" "$r142/scripts/dev/"
  printf '# readme\n(999 golden-case assertions)\n' > "$r142/README.md"
  printf '# readme\n（999 项 golden-case 断言）\n' > "$r142/README.zh-CN.md"
  printf '999\n' > "$r142/tests/.suite-baseline"
  printf 'ok shard-1\n10 passed, 0 failed\n' > "$r142/evidence/CHG-990/round-1/shard-1.log"
  printf '5 passed, 0 failed\n' > "$r142/evidence/CHG-990/round-1/shard-2.log"
  printf 'total: 15 passed, 0 failed\n' > "$r142/evidence/CHG-990/round-1/sum.txt"
  ( cd "$r142" && bash scripts/dev/update-assertion-count.sh --from-evidence "evidence/CHG-990/round-1" >/dev/null 2>&1 ); t142e_rc=$?
  report "T51 TC-2390 --from-evidence syncs baseline from shard sum" 0 "$t142e_rc"
  report "T51 TC-2390 suite baseline equals shard sum" 15 "$(cat "$r142/tests/.suite-baseline" | tr -d '[:space:]')"
  report "T51 TC-2390 README claim rewritten to shard sum" 1 "$(grep -c '15 golden-case assertions' "$r142/README.md")"

  # TC-2391（REQ-1379 负例）：分片求和 ≠ sum.txt total → 拒写、基线不动
  printf '9 passed, 0 failed\n' > "$r142/evidence/CHG-990/round-1/shard-1.log"
  printf '999\n' > "$r142/tests/.suite-baseline"
  ( cd "$r142" && bash scripts/dev/update-assertion-count.sh --from-evidence "evidence/CHG-990/round-1" >/dev/null 2>&1 ); t142f_rc=$?
  report "T51 TC-2391 drift between shard sum and sum.txt refuses" 2 "$t142f_rc"
  report "T51 TC-2391 baseline untouched on refusal" 999 "$(cat "$r142/tests/.suite-baseline" | tr -d '[:space:]')"

  # TC-2396（REQ-1379 负例）：红轮（failed>0，双源一致）→ 拒写
  printf '10 passed, 0 failed\n' > "$r142/evidence/CHG-990/round-1/shard-1.log"
  printf '0 passed, 1 failed\n' > "$r142/evidence/CHG-990/round-1/shard-2.log"
  printf 'total: 10 passed, 1 failed\n' > "$r142/evidence/CHG-990/round-1/sum.txt"
  ( cd "$r142" && bash scripts/dev/update-assertion-count.sh --from-evidence "evidence/CHG-990/round-1" >/dev/null 2>&1 ); t142g_rc=$?
  report "T51 TC-2396 red round refuses to sync" 2 "$t142g_rc"

  # TC-2397（REQ-1379 负例）：无分片日志 → 拒写
  rm -f "$r142"/evidence/CHG-990/round-1/shard-*.log
  ( cd "$r142" && bash scripts/dev/update-assertion-count.sh --from-evidence "evidence/CHG-990/round-1" >/dev/null 2>&1 ); t142h_rc=$?
  report "T51 TC-2397 no shard logs refuses" 2 "$t142h_rc"

  # v3.79.0 (CHG-103, REQ-1143/1144)：树指纹语义 golden（缺口主证 = SC-1841）
  # TC-1379 tracked 文件内容变更 → 指纹不等 → 拒采（含 mismatch 提示行）
  # 注：改的是 tests/run-tests.sh（套件输入面）——README×2 是声明文件（消费方改写面），
  # 已被指纹排除（TC-1383 反向承载），不可用作 tracked 变更样本。
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  printf '# dirty\n' >> "$r51/tests/run-tests.sh"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  r51_mis=$(printf '%s\n' "$r51_out" | grep -c 'tree-fingerprint mismatch')
  report "T51 tracked worktree change rejects receipt (TC-1379)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 && "$r51_mis" -ge 1 ]] && echo 0 || echo 1)"
  git -C "$r51" checkout -q -- tests/run-tests.sh 2>/dev/null || true

  # TC-1380 untracked 新文件内容 → 指纹不等 → 拒采（porcelain-only 配方的盲区，本门必拒）
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  printf 'new file\n' > "$r51/tests/untracked-extra.txt"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 untracked new file rejects receipt (TC-1380)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"
  rm -f "$r51/tests/untracked-extra.txt"

  # TC-1381 旧 schema（无指纹字段）→ 拒采（反向兼容，fail-closed 方向）
  _r51_seed "$r51_head" 999 0
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  r51_mis=$(printf '%s\n' "$r51_out" | grep -c 'tree-fingerprint missing')
  report "T51 pre-v3.79 schema receipt rejected (TC-1381)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 && "$r51_mis" -ge 1 ]] && echo 0 || echo 1)"

  # TC-1382 指纹确定性：同树两算同值，clean 树 = HEAD^{tree}
  # （先清内嵌哨兵：上一用例的 embedded run 会在 tests/ 留 untracked 哨兵，污染树）
  rm -f "$r51/tests/.embedded-ran"
  fp1=$(suite_tree_fingerprint "$r51")
  fp2=$(suite_tree_fingerprint "$r51")
  report "T51 fingerprint deterministic, clean tree = HEAD tree (TC-1382)" 0 "$([[ -n "$fp1" && "$fp1" == "$fp2" && "$fp1" == "$r51_tree" ]] && echo 0 || echo 1)"

  # TC-1383 指纹排除面：gitignored（.agent-state）不换指纹；声明文件（README×2/
  # .audit-baseline/.suite-baseline，消费方 UAC 全跑后自行改写的输出声明面）改内容
  # 也不换指纹——v3.87.0 CHG-115：漏掉 .suite-baseline 会让每次计数同步作废自己的收据，
  # 逼出一次 5 分钟重跑。真实 index 零副作用（porcelain 在指纹调用前后一致——两个采样点都含脏态）
  rm -f "$r51/tests/.embedded-ran"
  printf 'noise\n' > "$r51/.agent-state/noise.txt"
  printf 'README claims 777 golden-case assertions here.\n' > "$r51/README.md"
  printf '{"passed":777,"failed":0}\n' > "$r51/tests/.suite-baseline"
  r51_pre=$(git -C "$r51" status --porcelain)
  fp3=$(suite_tree_fingerprint "$r51")
  r51_post=$(git -C "$r51" status --porcelain)
  report "T51 ignored + claim files do not shift fingerprint; real index untouched (TC-1383)" 0 "$([[ "$fp3" == "$r51_tree" && -n "$r51_pre" && "$r51_pre" == "$r51_post" ]] && echo 0 || echo 1)"
  rm -f "$r51/.agent-state/noise.txt"
  printf 'README claims 888 golden-case assertions here.\n' > "$r51/README.md"
  printf '{"passed":888,"failed":0}\n' > "$r51/tests/.suite-baseline"

  # TC-1384 no-git 降级：lib 输出空串（exit 0）；UAC 无 git 走既有内嵌路径
  r51_ng=$(mktemp -d "${TMPDIR:-/tmp}/receipt-nogit.XXXXXX")
  r51_ngfp=$(suite_tree_fingerprint "$r51_ng")
  r51_ng2="$r51/nogit"
  mkdir -p "$r51_ng2/scripts" "$r51_ng2/tests"
  mkdir -p "$r51_ng2/scripts/dev" && cp "$ROOT/scripts/dev/update-assertion-count.sh" "$r51_ng2/scripts/dev/"
  cp "$ROOT/scripts/lib-suite-tree-fingerprint.sh" "$r51_ng2/scripts/"
  mkdir -p "$r51_ng2/scripts/dev" && cp "$ROOT/scripts/dev/lib-source-facts.sh" "$r51_ng2/scripts/dev/"
  cp "$r51/tests/run-tests.sh" "$r51_ng2/tests/"
  printf 'README claims 888 golden-case assertions here.\n' > "$r51_ng2/README.md"
  printf '这里声称 888 项 golden-case 断言。\n' > "$r51_ng2/README.zh-CN.md"
  r51_out=$( cd "$r51_ng2" && AGENT_GUARD_SUITE_RECEIPT_PATH="" bash scripts/dev/update-assertion-count.sh --check 2>&1 || true )
  r51_sentinel=$([[ -f "$r51_ng2/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 non-git repo: lib yields empty, UAC runs embedded (TC-1384)" 0 "$([[ -z "$r51_ngfp" && "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"
  rm -rf "$r51_ng" "$r51_ng2"

  # TC-1386 缺指纹 lib → 快路径整体关闭（fail-closed：无法证明树未变即不采信）
  _r51_seed "$r51_head" 999 0 "$r51_tree"
  mv "$r51/scripts/lib-suite-tree-fingerprint.sh" "$r51/scripts/lib.bak"
  r51_out=$(_r51_run || true)
  r51_sentinel=$([[ -f "$r51/tests/.embedded-ran" ]] && echo 1 || echo 0)
  r51_has777=$(printf '%s\n' "$r51_out" | grep -c 'expected 777')
  report "T51 missing fingerprint lib disables the fast path (TC-1386)" 0 "$([[ "$r51_sentinel" == 1 && "$r51_has777" -ge 1 ]] && echo 0 || echo 1)"
  mv "$r51/scripts/lib.bak" "$r51/scripts/lib-suite-tree-fingerprint.sh"

  # TC-1124/1125 真实仓：过滤 / rc2 运行不触收据（v3.86.0 起用隔离路径，
  # 不再播种/还原真实 .agent-state —— 并行会话与自测互不踩踏）
  r51_real="$ROOT/.agent-state/last-suite-receipt.json"
  r51_real_before=$(cksum < "$r51_real" 2>/dev/null || echo absent)
  r51_iso="$r51/.state-iso/last-suite-receipt.json"
  mkdir -p "$(dirname "$r51_iso")"
  printf '{"head":"seed","passed":12345,"failed":0,"wall_time_s":0,"generated_at":"seed"}\n' > "$r51_iso"
  cp "$r51_iso" "$r51/.seeded"
  r51_rc=0; AGENT_GUARD_SUITE_RECEIPT_PATH="$r51_iso" bash "$ROOT/tests/run-tests.sh" -T T1 >/dev/null 2>&1 || r51_rc=$?
  r51_same=0; cmp -s "$r51/.seeded" "$r51_iso" || r51_same=1
  report "T51 filtered run leaves receipt untouched (TC-1124)" 0 "$([[ $r51_rc -eq 0 && "$r51_same" == 0 ]] && echo 0 || echo 1)"
  r51_rc=2; AGENT_GUARD_SUITE_RECEIPT_PATH="$r51_iso" bash "$ROOT/tests/run-tests.sh" -T NOPE >/dev/null 2>&1 || r51_rc=$?
  r51_same2=0; cmp -s "$r51/.seeded" "$r51_iso" || r51_same2=1
  report "T51 rc2 run leaves receipt untouched (TC-1125)" 0 "$([[ $r51_rc -eq 2 && "$r51_same2" == 0 ]] && echo 0 || echo 1)"
  report "T51 isolated self-tests leave the REAL ledger untouched (TC-1124b)" 0 "$([[ "$(cksum < "$r51_real" 2>/dev/null || echo absent)" == "$r51_real_before" ]] && echo 0 || echo 1)"

  # TC-1126 发射端结构守卫：blk = 收据块数值行窗（grep -F 定锚）。自匹配三连教训：
  # ①grep 自身参数字面量 ②T51 注释里的同款字面量 ③起锚须带 'suite receipt' 后缀
  # 区别于 prelude 注释前缀——所有锚在 T51 源码内一律用 '"…"' 拼接断开。
  r51_s=$(grep -nF 'REQ-1049): '"suite receipt" "$ROOT/tests/run-tests.sh" | head -1 | cut -d: -f1)
  r51_e=$(grep -nF 'if [[ "$fail" -gt 0 ]]; '"then" "$ROOT/tests/run-tests.sh" | cut -d: -f1 | awk -v s="$r51_s" '$1>s{print;exit}')
  r51_blk=$(sed -n "${r51_s},${r51_e}p" "$ROOT/tests/run-tests.sh")
  r51_g1=$(grep -c '^SUITE_HEAD=' "$ROOT/tests/run-tests.sh")
  r51_g2=$(printf '%s\n' "$r51_blk" | grep -cF 'WANTED[@]} -eq 0 && -n "$SUITE_HEAD"')
  r51_g3=$(printf '%s\n' "$r51_blk" | grep -cF 'rm -f "$SUITE_RECEIPT_PATH"')
  r51_g4=$(printf '%s\n' "$r51_blk" | grep -cF 'date -u +%Y-%m-%dT%H:%M:%SZ')
  r51_w=$(grep -nF 'wall-time: '"%ds" "$ROOT/tests/run-tests.sh" | head -1 | cut -d: -f1)
  r51_r=$(grep -nF 'REQ-1049): '"suite receipt" "$ROOT/tests/run-tests.sh" | head -1 | cut -d: -f1)
  report "T51 emitter caches HEAD in prelude (TC-1126a)" 1 "$r51_g1"
  report "T51 receipt write guarded to full runs (TC-1126b)" 1 "$r51_g2"
  report "T51 red run deletes receipt (TC-1126c)" 1 "$r51_g3"
  report "T51 receipt stamped UTC (TC-1126d)" 1 "$([[ $r51_g4 -ge 1 ]] && echo 1 || echo 0)"
  report "T51 receipt block sits after wall-time (TC-1126e)" 0 "$([[ -n "$r51_w" && -n "$r51_r" && "$r51_w" -lt "$r51_r" ]] && echo 0 || echo 1)"
  # v3.79.0 (CHG-103, REQ-1142): emitter shape pins — the receipt printf carries
  # the tree_fingerprint field and the fingerprint is taken inside the guarded
  # block (runtime receipt content is evidenced by the T6 full run, 05).
  r51_mis=$(printf '%s\n' "$r51_blk" | grep -cF '"tree_fingerprint":"%s"')
  fp1=$(grep -cF '_tree_fp=$(suite_tree_fingerprint "$ROOT")' "$ROOT/tests/run-tests.sh")
  report "T51 receipt carries tree_fingerprint field, guarded compute (TC-1385)" 0 "$([[ "$r51_mis" -ge 1 && "$fp1" -ge 1 ]] && echo 0 || echo 1)"
  rm -rf "$r51"
}

section_T52() {
# ------------------------------------------------ T52 UX 条件门（v3.67.0）
new_repo
seed_artifacts CHG-1000 L1 claude/s-1
# E90：声明 ui_change 但无 UJ → begin 拒
# CHG-117: begin 默认收窄为入口门，E90 由兼容开关下的全量 begin 与 staged
# 交付面执法；本三态钉用显式开关（默认收窄本身由 T80 钉）。
printf '# spec\n- **ui_change**：true\n- REQ-001: r\n' > docs/changes/CHG-1000/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1000 >/dev/null 2>&1
report "T52 E90 rejects ui_change:true without a UJ" 2 $?
# E90 负例补强：模板形态的空挂靠（`**挂靠 UJ**：<!-- 待填 -->`）同样拒
printf '# spec\n- **ui_change**：true\n### REQ-001\n**描述**：r\n**挂靠 UJ**：<!-- 待填：UJ-xxx -->\n' > docs/changes/CHG-1000/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1000 >/dev/null 2>&1
report "T52 E90 rejects an unfilled UJ anchor placeholder" 2 $?
# E90 正例：REQ 块内挂靠真实 UJ → begin 过
printf '# spec\n- **ui_change**：true\n## 用户任务\n### UJ-001\n- **入口**：记录列表\n### REQ-001\n**描述**：r\n**挂靠 UJ**：UJ-001\n' > docs/changes/CHG-1000/01-spec.md
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1000 >/dev/null 2>&1
report "T52 E90 passes once a UJ anchors the REQ" 0 $?
echo x > src/a.go
git add src/a.go
# E92：ui_change 但缺 03.6
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E92 rejects ui_change:true without 03.6-ui-spec" 2 $?
printf '# ui\n## 逐屏字段与控件\n- 列表选择\n' > docs/changes/CHG-1000/03.6-ui-spec.md
# E94：03.6 缺显示名↔主键映射
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E94 rejects 03.6 without the key-mapping section" 2 $?
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n- 用户直接输入 record_id 开始查询\n' > docs/changes/CHG-1000/03.6-ui-spec.md
# E97：03.6 把裸主键当主入口
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E97 rejects a bare primary-key entry" 2 $?
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n' > docs/changes/CHG-1000/03.6-ui-spec.md
# E93：03.5 无 UX/UI 任务行（注释里的图例不算，review P1-4）
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E93 rejects 03.5 without a UX task row" 2 $?
printf '# tasks\n| 任务 | 类型 | 依赖 | 里程碑 | 说明 |\n|---|---|---|---|---|\n| T1 | UX | 无 | M1 | 设计 |\n- 评审输入: x\n' > docs/changes/CHG-1000/03.5-tasks.md
# E95：L1 阈值 1，04 无用户旅程 E2E
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E95 rejects zero user-journey E2E cases" 2 $?
printf '# tests\n- TC-001 用户旅程 E2E（真人入口）\n覆盖维度: 正常流\n- SC-001 用户旅程 E2E（覆盖: TC-001）\n' > docs/changes/CHG-1000/04-test-scripts.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E92-E95 pass once 03.6 + UX task + E2E are in place" 0 $?
# E96/E98：07 缺用户可用性验收 → E96；有验收缺人类走查行 → E98
printf '# review\n## 评审结论\n通过\n' > docs/changes/CHG-1000/07-review-report.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E96 rejects a review without usability sign-off" 2 $?
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n## 评审结论\n通过\n' > docs/changes/CHG-1000/07-review-report.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E98 rejects the missing human-walkthrough line" 2 $?
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 业务合理性终审\n- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）\n- **业务终审主体**：platform / glm / ses-t52a\n## 评审结论\n通过\n' > docs/changes/CHG-1000/07-review-report.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 E96+E98 pass with usability sign-off + human-walkthrough line" 0 $?
# 隔离：ui_change 缺省/为 false 时不启用任何 UX 条件门
new_repo
seed_artifacts CHG-1001 L1 claude/s-1
scripts/agent-gate begin CHG-1001 >/dev/null 2>&1
echo x > src/a.go
git add src/a.go
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T52 UX lane stays dormant without ui_change" 0 $?
# 软告警：UI 路径 diff + 未声明 ui_change → 仅告警不拒（P1-5）
mkdir -p web
echo x > web/page.html
git add web/page.html
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T52 soft warning fires for UI-path diffs without ui_change" "UX soft warning" "$out"
}

section_T53() {
# ------------------------------------------------ T53 G13/G14 行为面门禁（v3.68.0，CHG-043）
# TC↔REQ 映射：TC-1128→REQ-1067/1069/1076，TC-1129→REQ-1068，TC-1130→REQ-1067/1070，
# TC-1131→REQ-1071，TC-1132→REQ-1072，TC-1133→REQ-1073，TC-1134→REQ-1074，TC-1135→REQ-1075。
# 框架约束（v3.68.0 实际接线，DES-1842 已兑现）：begin 级门 E99/E100/E105/E106 执法点=
# validate_artifact_content 尾（begin 真执法）+ validate_dimensional_active（staged/stop 复验，
# 捕捉中途锚点腐烂）；complete_valid_change_exists 的结构探测经 AGENT_GUARD_DIM_PROBE=1 豁免
# 本门（探测只回答"件齐与否"，不回答"锚点新鲜否"——否则 E100 会被 E66 兜底掩盖）。
# 注意 T52 已被 CHG-090 UX 条件门占用，本节顺延为 T53。
EXTRACT_SRC="$ROOT/resources/templates/behavior-extract.sh"
[[ -f "$EXTRACT_SRC" ]] || EXTRACT_SRC="$ROOT/scripts/behavior-extract.sh"
new_repo
seed_artifacts CHG-1020 L1 claude/s-1
mkdir -p proto
cat > proto/index.html <<'EOF'
<button id="b1" onclick="save()">存</button>
<input id="i1" oninput="f()">
<form onsubmit="g()"><div onmouseover="pop()">x</div></form>
<a onclick="location.href='/list'">go</a>
<script>
document.getElementById("b1").addEventListener("click", save);
$("#f").on("change", h);
fetch("/api/x"); axios.get("/y"); $.ajax("/z"); new XMLHttpRequest();
setTimeout(tick, 100); setInterval(beat, 1000);
window.open("/w"); history.pushState({}, "", "/p");
</script>
EOF
cat > docs/changes/CHG-1020/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页改版
- **挂靠 UJ**：UJ-001
- **origin_artifact**: proto/index.html
- **chain_change**: true
- **ui_change**: true

## 数据流规格表
| 字段 | 来源 | 转换 | 去向 | 展示 |
|---|---|---|---|---|
| recordId | <表>.record_id | 直传 | 会话上下文 | 列表列 |
EOF
cat > docs/changes/CHG-1020/03.6-ui-spec.md <<'EOF'
# ui
## 显示名↔主键映射
- 记录显示名 → record_id
EOF
cat > docs/changes/CHG-1020/03.5-tasks.md <<'EOF'
# tasks
| 任务 | 类型 | 依赖 | 里程碑 | 说明 |
|---|---|---|---|---|
| T-001 | UX | 无 | M1 | 演示页改造 |
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点
EOF
cat > docs/changes/CHG-1020/04-test-scripts.md <<'EOF'
# tests
- TC-001 用户旅程 E2E：点击存档 → 列表刷新
覆盖维度: 正常流 / 边界 / 异常
## 否定测试
- NT-001: 断网点击存档必须失败提示，不得静默成功（回归: TC-001）
- SC-001: 演示页主流程（覆盖: TC-001）
EOF
# TC-1128：用真实行为抽取器产出 inventory（hash 一致性由 E100 复算兜底）
bash "$EXTRACT_SRC" proto/index.html > docs/changes/CHG-1020/behavior-inventory.json
inv=docs/changes/CHG-1020/behavior-inventory.json
inv_total=$(sed -n '1s/.*"total_behaviors":\([0-9]*\).*/\1/p' "$inv")
report "T53 TC-1128 extractor total_behaviors=20 (16 behaviors + 4 elements, CHG-044 schema pin)" 0 "$([[ "$inv_total" == 20 ]]; echo $?)"
report "T53 TC-1128 first data row is BHV-001 click pending" 1 "$(sed -n '2p' "$inv" | grep -c '"id":"BHV-001".*"kind":"click".*"status":"pending"')"
hrec=$(sed -n '1s/.*"artifact_hash":"\([a-f0-9]\{64\}\)".*/\1/p' "$inv")
hcur=$(shasum -a 256 proto/index.html 2>/dev/null | awk '{print $1}')
[[ -n "$hcur" ]] || hcur=$(sha256sum proto/index.html 2>/dev/null | awk '{print $1}')
report "T53 TC-1128 extractor hash equals recomputed sha256" 0 "$([[ -n "$hrec" && "$hrec" == "$hcur" ]]; echo $?)"
commit_all "t53 fixture CHG-1020"
scripts/agent-gate begin CHG-1020 >/dev/null 2>&1
report "T53 TC-1128 begin green with origin/chain/ui declared + inventory anchored" 0 $?
echo y > src/a.js
git add src/a.js
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1128 staged green: begin-lane E99/E100/E105/E106 all pass" 0 $?
# TC-1129（E100 锚点防腐）：篡改原型一个字符 → staged 红
printf 'x' >> proto/index.html
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1129 tampered origin artifact keeps staged red" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1129 refusal names GATE-E100 hash mismatch" "GATE-E100" "$out"
git checkout -q -- proto/index.html
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1129 staged green again after artifact restore" 0 $?
# TC-1130（E99 begin 级）：声明 origin 但清单缺失 → staged 红；补回抽取产物
rm docs/changes/CHG-1020/behavior-inventory.json
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1130 E99 staged red: origin declared but inventory missing" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1130 refusal names GATE-E99" "GATE-E99" "$out"
bash "$EXTRACT_SRC" proto/index.html > docs/changes/CHG-1020/behavior-inventory.json
# TC-1233（E109 begin 级，评审中3 补测）：origin_artifact 指向不存在路径 → begin 红
sed -e 's|origin_artifact\*\*: proto/index.html|origin_artifact**: proto/missing.html|' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
# CHG-117: E109 rides the full (legacy) begin lane and the delivery face;
# the default narrowed begin is covered by T80.
AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1020 >/dev/null 2>&1
report "T53 TC-1233 E109 begin red: origin artifact path not found" 2 $?
out=$(AGENT_GUARD_STAGE_GATES=0 scripts/agent-gate begin CHG-1020 2>&1 || true)
check_output "T53 TC-1233 refusal names GATE-E109" "GATE-E109" "$out"
sed -e 's|origin_artifact\*\*: proto/missing.html|origin_artifact**: proto/index.html|' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
# TC-1132（E105/E106 begin 级）：chain_change 而无 数据流规格表 / 空单元格 / 无 否定测试
sed -e '/^## 数据流规格表/,$d' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 E105 staged red: chain_change without 数据流规格表" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1132 refusal names GATE-E105" "GATE-E105" "$out"
cat >> docs/changes/CHG-1020/01-spec.md <<'EOF'
## 数据流规格表
| 字段 | 来源 | 转换 | 去向 | 展示 |
|---|---|---|---|---|
|  |  |  |  |  |
EOF
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 E105 staged red: blank-cell row is a design gap" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1132 blank-cell refusal names GATE-E105" "GATE-E105" "$out"
sed -e '/^## 数据流规格表/,$d' docs/changes/CHG-1020/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1020/01-spec.md
cat >> docs/changes/CHG-1020/01-spec.md <<'EOF'
## 数据流规格表
| 字段 | 来源 | 转换 | 去向 | 展示 |
|---|---|---|---|---|
| patientSn | fzzl_patient.patientSn | 直传 | 会话上下文 | 列表列 |
EOF
grep -v '否定测试' docs/changes/CHG-1020/04-test-scripts.md > .t53-04.tmp && mv .t53-04.tmp docs/changes/CHG-1020/04-test-scripts.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 E106 staged red: chain_change without 否定测试 section" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T53 TC-1132 refusal names GATE-E106" "GATE-E106" "$out"
cat >> docs/changes/CHG-1020/04-test-scripts.md <<'EOF'
## 否定测试
- NT-001: 断网点击存档必须失败提示，不得静默成功（回归: TC-001）
EOF
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-1132 staged green after table + negation section restored" 0 $?
# ---- stop 级夹具 CHG-1030（origin 声明 + ui_change:false：E101/E102/E103/E108 轨道）----
new_repo
seed_artifacts CHG-1030 L0 claude/s-1
mkdir -p proto
printf '<button id="b2" onclick="s1()">A</button>\n<button id="b3" onclick="s2()">B</button>\n<button id="b4" onclick="s3()">C</button>\n' > proto/index.html
cat > docs/changes/CHG-1030/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页对齐真实链路
- **origin_artifact**: proto/index.html
- **chain_change**: 未命中（静态演示页，无数据链变更）
- **ui_change**: false
- 事件链：BHV-001 → BHV-002 走真实业务链路（record_id 直传）
EOF
bash "$EXTRACT_SRC" proto/index.html > docs/changes/CHG-1030/behavior-inventory.json
scripts/agent-gate begin CHG-1030 >/dev/null 2>&1
report "T53 TC-1130 begin green before stop progression" 0 $?
seed_t53_delivery CHG-1030
echo y > src/t53b.js
inv2=docs/changes/CHG-1030/behavior-inventory.json
# TC-1130（E101 stop 级）：清单含 missing → stop 红
sed -e '4s/"status":"pending"/"status":"missing"/' "$inv2" > .t53-inv.tmp && mv .t53-inv.tmp "$inv2"
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1130 E101 stop red: inventory carries missing status" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1130 refusal names GATE-E101" "GATE-E101" "$out"
sed -e '4s/"status":"missing"/"status":"pending"/' "$inv2" > .t53-inv.tmp && mv .t53-inv.tmp "$inv2"
# TC-1130（E102 stop 级）：BHV-003 全目录无引用且未豁免 → stop 红；接线后绿
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1130 E102 stop red: BHV-003 never referenced nor waived" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1130 refusal names GATE-E102 with the orphan id" "GATE-E102.*BHV-003" "$out"
sed -e 's/- 事件链：BHV-001 → BHV-002 走真实业务链路/- 事件链：BHV-001 → BHV-002 → BHV-003 → BHV-004 → BHV-005 → BHV-006 走真实业务链路/' docs/changes/CHG-1030/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1030/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1130 stop green once all six BHVs (behavior+element) are referenced" 0 $?
# TC-1131（E103 stop 级）：demo_script 声明而 05 无 REPLAY: → 红；补证据行后绿
printf -- '- **demo_script**: 3\n' >> docs/changes/CHG-1030/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1131 E103 stop red: demo_script declared but 05 lacks REPLAY" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1131 refusal names GATE-E103" "GATE-E103" "$out"
printf 'REPLAY: 第1句 点击A按钮 → HTTP 200（快照 t53a）\n' >> docs/changes/CHG-1030/05-test-results.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1131 stop green with REPLAY evidence line" 0 $?
# TC-1133（E108 stop 级）：链上行为豁免行缺 00.5 → 红；补 00.5 引用后绿
cat >> docs/changes/CHG-1030/01-spec.md <<'EOF'

## 拆除/豁免登记簿
| 行为 | 处置 | 理由 |
|---|---|---|
| BHV-001 | 行为豁免 | 演示数据按钮，未走真实链 |
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1133 E108 stop red: chain-touching waiver without 00.5" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1133 refusal names GATE-E108" "GATE-E108" "$out"
sed -e 's#| BHV-001 | 行为豁免 | 演示数据按钮，未走真实链 |#| BHV-001 | 行为豁免 | 00.5 追加沟通轮已确认：演示按钮不触真实链 |#' docs/changes/CHG-1030/01-spec.md > .t53-spec.tmp && mv .t53-spec.tmp docs/changes/CHG-1030/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1133 stop green once waiver carries 00.5 reference" 0 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1133 stop lane clean receipt prints counters" "G13/G14 stop lane clean" "$out"
# ---- stop 级夹具 CHG-1040（ui_change:true：E104/E107 轨道，复用 T52 UX 门绿基线）----
new_repo
seed_artifacts CHG-1040 L0 claude/s-1
cat > docs/changes/CHG-1040/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页可用性收口
- **挂靠 UJ**：UJ-001
- **origin_artifact**: 未命中（无原型页，改版基线=线上页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: true

## 动作全集矩阵
- 对象=演示页；入口维度：桌面命中/移动未命中；改命中、其余格既有
EOF
cat > docs/changes/CHG-1040/03.6-ui-spec.md <<'EOF'
# ui
## 参照界面对照表
- 仓内同类既有界面：未命中（首次 ui_change，P12 UI 范式卡已沉淀）
- UI 范式卡：引用 P12（操作位置/弹窗家法随卡）
## 显示名↔主键映射
- 记录显示名 → record_id
EOF
cat > docs/changes/CHG-1040/03.5-tasks.md <<'EOF'
# tasks
| 任务 | 类型 | 依赖 | 里程碑 | 说明 |
|---|---|---|---|---|
| T-001 | UX | 无 | M1 | 可用性收口 |
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点
EOF
cat > docs/changes/CHG-1040/04-test-scripts.md <<'EOF'
# tests
- TC-001 用户旅程 E2E：入口到结果全程真人可走
覆盖维度: 正常流 / 边界 / 异常
- SC-001: 记录列表主流程（覆盖: TC-001）
EOF
cat > docs/changes/CHG-1040/07-review-report.md <<'EOF'
# review
## 用户可用性验收
- 结论：通过（依据 03.6 与 UJ-001）
- **建议人类走查（非阻塞）**：建议交付前真人走查一次
## 业务合理性终审
- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）
- **业务终审主体**：platform / glm / ses-t53a
- **发现处置**：未命中，不适用（T53 可用性夹具，无发现）
- **超限处置**：T53 夹具多轮 stop 为同一树多次终验的指纹变体，非重复评审批次；收敛证据=本节 E104/E107 三态绿
- 评审主体：platform / glm-5.3-flash / ses-t53c
EOF
scripts/agent-gate begin CHG-1040 >/dev/null 2>&1
report "T53 TC-1134 begin green: ui_change anchored to UJ-001" 0 $?
seed_t53_delivery CHG-1040
echo y > src/t53c.js
# TC-1134（E104 stop 级）：ui_change 而 05 无 UJ-001+证据词行 → 红
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1134 E104 stop red: UJ-001 lacks runtime evidence row in 05" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1134 refusal names GATE-E104" "GATE-E104" "$out"
printf -- '- UJ-001 运行时证据：HTTP 响应体 200，DB 行 <表> 更新，快照 snap-t53c\n' >> docs/changes/CHG-1040/05-test-results.md
printf -- '- **还原度断言**：未命中，不适用（T53 夹具无自动化浏览器环境，人工逐屏清单已附）\n' >> docs/changes/CHG-1040/05-test-results.md
# TC-1134（E107 stop 级）：07 有签名无 运行时走查 → 红
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1134 E107 stop red: 07 lacks 运行时走查 journey section" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-1134 refusal names GATE-E107" "GATE-E107" "$out"
printf '\n## 运行时走查\n- 走查记录：ses-t53c（UJ-001 全程真人入口可走通，截图 t53c-home.png 留痕）\n' >> docs/changes/CHG-1040/07-review-report.md
scripts/agent-gate --stage stop >/dev/null 2>&1; t53_1134_green_rc=$?
report "T53 TC-1134 stop green with per-UJ evidence + journey walkthrough" 0 "$t53_1134_green_rc"
report "T53 TC-2379 E104 old-word compatibility: HTTP row still passes" 0 "$t53_1134_green_rc"
# ---- TC-2378~2385（CHG-141，REQ-1371~1374：E104 词表扩两类 / E107 自产标记 / E157 三查 / E158-E159 锚点）----
new_repo
seed_artifacts CHG-1060 L0 claude/s-1
cat > docs/changes/CHG-1060/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页收口二批
- **挂靠 UJ**：UJ-001
- **origin_artifact**: 未命中（无原型页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: true

## 动作全集矩阵
- 对象=演示页；入口维度：桌面命中/移动未命中；改命中、其余格既有
EOF
cat > docs/changes/CHG-1060/03.6-ui-spec.md <<'EOF'
# ui
## 参照界面对照表
- 仓内同类既有界面：未命中（首次 ui_change，P12 UI 范式卡已沉淀）
- UI 范式卡：引用 P12（操作位置/弹窗家法随卡）
## 显示名↔主键映射
- 记录显示名 → record_id
EOF
cat > docs/changes/CHG-1060/03.5-tasks.md <<'EOF'
# tasks
| 任务 | 类型 | 依赖 | 里程碑 | 说明 |
|---|---|---|---|---|
| T-001 | UX | 无 | M1 | 演示页收口二批 |
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点
EOF
cat > docs/changes/CHG-1060/04-test-scripts.md <<'EOF'
# tests
- TC-001 用户旅程 E2E：入口到结果全程真人可走
覆盖维度: 正常流 / 边界 / 异常
- SC-001: 演示页主流程（覆盖: TC-001）
EOF
cat > docs/changes/CHG-1060/07-review-report.md <<'EOF'
# review
## 用户可用性验收
- 结论：通过（依据 03.6 与 UJ-001）
- **建议人类走查（非阻塞）**：建议交付前真人走查一次
## 业务合理性终审
- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）
- **业务终审主体**：platform / glm / ses-t53a
- **发现处置**：未命中，不适用（T53 可用性夹具，无发现）
- 评审主体：platform / glm-5.3-flash / ses-t53c
## 运行时走查
- 走查记录：ses-t53e（UJ-001 点击链路全程可走通，截图 t53e-home.png 留痕）
EOF
scripts/agent-gate begin CHG-1060 >/dev/null 2>&1
seed_t53_delivery CHG-1060
echo y > src/t53e.js
# TC-2379b（E104 负例，DES-2326 防假绿）：追加裸动词 POST 行（无标记词）→ 红（append 保 provenance，E19 先例）
printf -- '- UJ-001 运行时证据：提交表单 POST /api/demo 收 200（裸动词无标记词）\n' >> docs/changes/CHG-1060/05-test-results.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2379b E104 stop red: bare-verb POST row lacks marker word" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-2379b refusal names GATE-E104" "GATE-E104" "$out"
# TC-2378（E104 正例）：删裸动词行，追加 点击链路/截图 两类新证据词 → 绿
sedi '/提交表单 POST \/api\/demo 收 200/d' docs/changes/CHG-1060/05-test-results.md
printf -- '- UJ-001 运行时证据：点击链路：首页→点击 演示→提交→跳转 /done + 2026-11-06T05:00:00Z\n' >> docs/changes/CHG-1060/05-test-results.md
printf -- '- UJ-001 视觉证据：截图 t53e-home.png + 几何断言（间距 8px 网格）+ 2026-11-06T05:00:00Z\n' >> docs/changes/CHG-1060/05-test-results.md
printf -- '- **还原度断言**：未命中，不适用（T53 夹具）\n' >> docs/changes/CHG-1060/05-test-results.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2378 E104 stop green: 点击链路/截图 marker words accepted" 0 $?
# TC-2381（E107 负例）：走查行撤自产标记（留 ses-）→ 红；TC-2380 die 文本断言
sedi 's/截图 t53e-home.png 留痕//' docs/changes/CHG-1060/07-review-report.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2381 E107 stop red: walkthrough lacks self-produced marker" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-2380 E107 refusal demands 自产 evidence" "自产" "$out"
check_output "T53 TC-2380 E107 refusal demands 所见即所评" "所见即所评" "$out"
sedi 's/（UJ-001 点击链路全程可走通，）/（UJ-001 点击链路全程可走通，截图 t53e-home.png 留痕）/' docs/changes/CHG-1060/07-review-report.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2381 E107 stop green after marker restored" 0 $?
# TC-2382（E157 两独立负例+绿例）：①节内仅一锚点 ②豁免行置节外（证明节内切片）③节内豁免 → 绿
sedi 's/^- 专业质询三件：未命中（.*）/- 参照物指认：仅一锚点（负例）/' docs/changes/CHG-1060/00.5-communication.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2382 E157 stop red: section has one anchor only (anchors branch)" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-2382 refusal names GATE-E157" "GATE-E157" "$out"
sedi '/^- 参照物指认：仅一锚点（负例）/d' docs/changes/CHG-1060/00.5-communication.md
printf -- '- 专业质询三件：未命中（fixture 节外豁免不应放行）\n' >> docs/changes/CHG-1060/00.5-communication.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2382 E157 stop red: exemption outside the section is rejected" 2 $?
sedi '/节外豁免不应放行/d' docs/changes/CHG-1060/00.5-communication.md
awk 'BEGIN{done=0} /^## 用户整体确认记录/ && !done {print "- 专业质询三件：未命中（fixture 复原豁免单行）"; done=1} {print}' docs/changes/CHG-1060/00.5-communication.md > docs/changes/CHG-1060/00.5.tmp && mv docs/changes/CHG-1060/00.5.tmp docs/changes/CHG-1060/00.5-communication.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2382 E157 stop green with in-section one-line exemption" 0 $?
# TC-2383（E157 判定卡触发面）：触及被测核心（scripts/agent-gate 入 diff）缺判定卡 → 红
printf '# t53 core touch\n' >> scripts/agent-gate
git add scripts/agent-gate
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2383 E157 stop red: core-file diff without 判定卡" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-2383 refusal demands 判定卡 三选一" "三选一" "$out"
printf '\n## 判定卡（套件范围）\n- 判定卡三选一：FULL（触及被测核心，交付门一次全量）\n' >> docs/changes/CHG-1060/00.5-communication.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2383 E157 stop green with 判定卡 recorded" 0 $?
# ---- v4.5.0 (CHG-149, REQ-1385~1388): E104 bare HTTP, E161 outbound exit, E162 entry-owns-exit, E107 compensation gap ----
# TC-10015 (E104 bare HTTP): replace evidence with bare HTTP 200 (no body/DOM/latency) -> red
cp docs/changes/CHG-1060/05-test-results.md docs/changes/CHG-1060/05.bak
awk '1; /^-->/{exit}' docs/changes/CHG-1060/05.bak > docs/changes/CHG-1060/05.hdr
{ cat docs/changes/CHG-1060/05.hdr; printf '# 05\n- UJ-001 运行时证据：HTTP 200 @2026-11-24T00:00:00Z\n- **还原度断言**：未命中，不适用（T53 夹具）\n'; } > docs/changes/CHG-1060/05-test-results.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "T53 TC-10015 E104 stop red: bare HTTP 200 without body/latency rejected" 2 "$rc"
check_output "T53 TC-10015 refusal names GATE-E104" "GATE-E104" "$out"
{ cat docs/changes/CHG-1060/05.hdr; printf '# 05\n- UJ-001 运行时证据：HTTP 200 @2026-11-24T00:00:00Z 耗时正常 body={ok:true}\n- **还原度断言**：未命中，不适用（T53 夹具）\n'; } > docs/changes/CHG-1060/05-test-results.md
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "T53 TC-10027 E104 stop red: non-numeric 耗时正常 rejected" 2 "$rc"
check_output "T53 TC-10027 refusal names GATE-E104" "GATE-E104" "$out"
{ cat docs/changes/CHG-1060/05.hdr; printf '# 05\n- UJ-001 运行时证据：HTTP 200 @2026-11-24T00:00:00Z 耗时: 120ms body={ok:true}\n- **还原度断言**：未命中，不适用（T53 夹具）\n'; } > docs/changes/CHG-1060/05-test-results.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-10027 E104 stop green: numeric 耗时: 120ms accepted" 0 $?
rm -f docs/changes/CHG-1060/05.hdr
mv docs/changes/CHG-1060/05.bak docs/changes/CHG-1060/05-test-results.md
# TC-10012 (E161 outbound exit): add 出站出口节 with placeholder -> red; bind UJ-001 -> green
cp docs/changes/CHG-1060/01-spec.md docs/changes/CHG-1060/01.bak
printf '\n## 出站出口清单\n| 出口 | 目标 | 裁决 |\n|---|---|---|\n| 报表卡 | rep_ops.asp | <待填> |\n' >> docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-10012 E161 stop red: outbound exit section contains placeholder" 2 $?
sedi 's/<待填>/UJ-001/' docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-10012 E161 stop green: outbound exit bound to UJ-001" 0 $?
mv docs/changes/CHG-1060/01.bak docs/changes/CHG-1060/01-spec.md
# TC-10013 (E162 entry-owns-exit): 09 declares 已交付 with unmitigated 挂接待其 owner -> red; degrade -> green
cp docs/changes/CHG-1060/09-changelog.md docs/changes/CHG-1060/09.bak
printf '\n- 交付状态：已交付（下游页挂接待其 owner）\n' >> docs/changes/CHG-1060/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-10013 E162 stop red: 已交付 with unmitigated 挂接待其 owner" 2 $?
printf -- '- 处置：入口已降级隐藏，待下游闭合后开放\n' >> docs/changes/CHG-1060/09-changelog.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-10013 E162 stop green: entry degraded" 0 $?
mv docs/changes/CHG-1060/09.bak docs/changes/CHG-1060/09-changelog.md
# TC-10014 (E107 compensation gap): 工具面缺失 + 视觉证据包 + 未覆盖差集：非空 + bare 通过 -> red
cp docs/changes/CHG-1060/07-review-report.md docs/changes/CHG-1060/07.bak
sedi 's/截图 t53e-home.png 留痕/工具面缺失，视觉证据包补偿；未覆盖差集：非空（缺卡片下游页）/' docs/changes/CHG-1060/07-review-report.md
printf '\n## 评审结论\n通过\n' >> docs/changes/CHG-1060/07-review-report.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-10014 E107 stop red: compensation gap non-empty cannot give PASS" 2 $?
mv docs/changes/CHG-1060/07.bak docs/changes/CHG-1060/07-review-report.md
# TC-2384（E158 负例）：01-spec 撤动作全集矩阵节 → 红
sedi 's/；入口维度：桌面命中\/移动未命中//' docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2384 E158 stop red: 01-spec lacks 动作全集矩阵" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-2384 refusal names GATE-E158" "GATE-E158" "$out"
printf -- '- 入口维度：桌面命中/移动未命中\n' >> docs/changes/CHG-1060/01-spec.md
# TC-2385（E159 负例）：03.6 撤范式卡引用 → 红；复原 → 全绿收口
sedi '/仓内同类既有界面/d; /UI 范式卡/d' docs/changes/CHG-1060/03.6-ui-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2385 E159 stop red: 03.6 lacks 参照界面对照表/范式卡 reference" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T53 TC-2385 refusal names GATE-E159" "GATE-E159" "$out"
awk 'BEGIN{done=0} /^## 参照界面对照表/ && !done {print; print "- 仓内同类既有界面：未命中（首次 ui_change，P12 UI 范式卡已沉淀）"; print "- UI 范式卡：引用 P12（操作位置/弹窗家法随卡）"; done=1; next} {print}' docs/changes/CHG-1060/03.6-ui-spec.md > docs/changes/CHG-1060/03.6.tmp && mv docs/changes/CHG-1060/03.6.tmp docs/changes/CHG-1060/03.6-ui-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2378~2385 final stop green (all anchors restored)" 0 $?
# TC-2392（CHG-142，REQ-1380）：三件节占位符不再充当豁免 → E157 红
sedi 's/^- 专业质询三件：未命中（fixture 复原豁免单行）/- 专业质询三件：<路径或「未命中（理由）」>（占位符负例）/' docs/changes/CHG-1060/00.5-communication.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2392 E157 stop red: placeholder-only exemption rejected" 2 $?
sedi 's/^- 专业质询三件：<路径或「未命中（理由）」>（占位符负例）/- 专业质询三件：未命中（fixture 复原豁免单行）/' docs/changes/CHG-1060/00.5-communication.md
# TC-2393（REQ-1380）：矩阵节占位符 → E158 红
sedi 's/^- 入口维度：桌面命中\/移动未命中$/- 对象=<实体>；入口维度=<桌面\/移动>（占位符负例）/' docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2393 E158 stop red: placeholder-only matrix rejected" 2 $?
sedi 's/^- 对象=<实体>；入口维度=<桌面\/移动>（占位符负例）/- 入口维度：桌面命中\/移动未命中/' docs/changes/CHG-1060/01-spec.md
# TC-2394（REQ-1380）：对照节占位符 → E159 红；复原 → 绿
sedi 's/^- UI 范式卡：引用 P12（操作位置\/弹窗家法随卡）/- <UI 范式卡：引用 P12>（占位符负例）/' docs/changes/CHG-1060/03.6-ui-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2394 E159 stop red: placeholder-only reference rejected" 2 $?
sedi 's/^- <UI 范式卡：引用 P12>（占位符负例）/- UI 范式卡：引用 P12（操作位置\/弹窗家法随卡）/' docs/changes/CHG-1060/03.6-ui-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-2392~2394 final stop green after placeholder cleanup" 0 $?
# ---- TC-1135 负例（防门禁疲劳）：三行声明全 未命中 → begin/stop 全绿且零新门输出 ----
new_repo
seed_artifacts CHG-1050 L0 claude/s-1
cat > docs/changes/CHG-1050/01-spec.md <<'EOF'
# spec
- REQ-001: 纯文档微调
- **origin_artifact**: 未命中（无原型页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: false
EOF
scripts/agent-gate begin CHG-1050 >/dev/null 2>&1
report "T53 TC-1135 begin green when all three lanes declare 未命中" 0 $?
seed_t53_delivery CHG-1050
echo y > src/t53d.js
rc=0
out=$(scripts/agent-gate --stage stop 2>&1) || rc=$?
report "T53 TC-1135 stop green when all three lanes declare 未命中" 0 "$rc"
report "T53 TC-1135 zero new-gate output (anti gate-fatigue guard)" 0 "$(printf '%s' "$out" | grep -cE 'GATE-E(9[9]|10[0-9])|G13/G14')"
# TC-1231（v3.68.0 回测 record 687，locale 回归守卫）：含中文多字节文案的 HTML → exit 0 且 total>0
#（此前 macOS awk towc multibyte 死亡被吞=静默空清单 exit 0；现 LC_ALL=C 钉死 + fail-closed）
cat > .t53-locale.html <<'EOF'
<div class="panel">
  <button id="保存按钮" onclick="保存()">保存记录列表</button>
  <input id="搜索框" oninput="过滤()">
  <a href="#" onclick="跳转列表()">返回列表</a>
</div>
<script>
document.getElementById("保存按钮").addEventListener("click", 保存);
$("#搜索框").on("change", 过滤);
</script>
EOF
rc=0
t53c_out=$(bash "$EXTRACT_SRC" .t53-locale.html 2>/dev/null) || rc=$?
report "T53 TC-1231 extractor exit 0 on multibyte Chinese HTML (LC_ALL=C pinned)" 0 "$rc"
t53c_total=$(printf '%s\n' "$t53c_out" | sed -n '1s/.*"total_behaviors":\([0-9]*\).*/\1/p')
report "T53 TC-1231 multibyte extraction yields >0 behaviors" 0 "$([[ "$t53c_total" =~ ^[1-9][0-9]*$ ]]; echo $?)"
# TC-1232（fail-closed 空产出守卫）：零 pattern 纯静态 HTML → exit 3 + stderr 诊断词
cat > .t53-static.html <<'EOF'
<div class="static">
  <p>纯静态说明文案，无任何交互行为可抽取。</p>
  <span>keep-alive</span>
</div>
EOF
rc=0
t53d_err=$(bash "$EXTRACT_SRC" .t53-static.html 2>&1 >/dev/null) || rc=$?
report "T53 TC-1232 zero-pattern static HTML exits 3 (fail-closed empty output)" 3 "$rc"
check_output "T53 TC-1232 stderr names the zero-behavior diagnosis" "零行为" "$t53d_err"

# ---- TC-10047~10050 (v4.7.0 CHG-152, REQ-1422~1425) ----
# TC-10047 (ITEM-18): extensible test_weakening_patterns in .agent-governance.yml
new_repo
seed_artifacts CHG-1051 L0 claude/s-1
scripts/agent-gate begin CHG-1051 >/dev/null 2>&1
printf 'test_weakening_patterns: t\\.Skip\\(\n' > .agent-governance.yml
mkdir -p tests src
printf 'package foo\nfunc TestX() { t.%s("wip") }\n' "Skip" > tests/sample_test.go
git add tests/sample_test.go
rc=0
out=$(scripts/agent-gate --stage staged 2>&1) || rc=$?
report "T53 TC-10047 custom test_weakening_patterns blocks t.Skip via E160" 2 "$rc"
check_output "T53 TC-10047 die names GATE-E160" "GATE-E160" "$out"
printf 'package foo\n// owner=geek007 deadline=2099-12-31\nfunc TestX() { t.%s("wip") }\n' "Skip" > tests/sample_test.go
git add tests/sample_test.go
rc=0
scripts/agent-gate --stage staged >/dev/null 2>&1 || rc=$?
report "T53 TC-10047 custom test_weakening_patterns passes with owner+deadline" 0 "$rc"
# review F2: trailing comma (empty ERE branch) must not flag every test edit
printf 'test_weakening_patterns: t\\.Skip\\(,\n' > .agent-governance.yml
printf 'package foo\nfunc TestY() { assertOK() }\n' > tests/other_test.go
git add tests/other_test.go
rc=0
scripts/agent-gate --stage staged >/dev/null 2>&1 || rc=$?
report "T53 TC-10047 trailing comma in test_weakening_patterns is not an empty branch" 0 "$rc"

# TC-10048 (ITEM-30): structured KV priority in E104/E107/E157/E161/E162
new_repo
seed_artifacts CHG-1052 L0 claude/s-1
cat > docs/changes/CHG-1052/00.5-communication.md <<'EOF'
# comm
## 专业质询三件
inquiry_status: na
## 用户整体确认记录
- 确认状态：已整体确认
EOF
cat > docs/changes/CHG-1052/01-spec.md <<'EOF'
# spec
- REQ-001: UJ-001 KV check
- **origin_artifact**: 未命中（无原型）
- **chain_change**: 未命中（无数据链）
- **ui_change**: true
## 出站出口
outbound_exits: none
EOF
cat > docs/changes/CHG-1052/01.5-rtvm-matrix.md <<'EOF'
| REQ-001 | KV | DES-001 | s | T-1 | CHG-1052 | TC-1 | t | ✅ PASS |
EOF
cat > docs/changes/CHG-1052/03.6-ui-spec.md <<'EOF'
# UI Spec
## 参照界面对照表
reference_ui_table: na
## 显示名↔主键映射
- 记录显示名 → record_id
EOF
cat > docs/changes/CHG-1052/03.5-tasks.md <<'EOF'
# tasks
| 任务 | 类型 | 依赖 | 里程碑 | 说明 |
|---|---|---|---|---|
| T-001 | UX | 无 | M1 | KV check |
- 评审输入: 变更文件清单 + 待核对产物 + 行号锚点
EOF
cat > docs/changes/CHG-1052/04-test-scripts.md <<'EOF'
# tests
- TC-001 用户旅程 E2E：入口到结果全程真人可走
覆盖维度: 正常流 / 边界 / 异常
- SC-001: KV 主流程（覆盖: TC-001）
EOF
scripts/agent-gate begin CHG-1052 >/dev/null 2>&1
report "T53 TC-10048 begin CHG-1052 succeeds" 0 $?
seed_t53_delivery CHG-1052
printf -- 'red_repro: bash test -> rc1\ngreen_after: bash test -> rc0\nuj_evidence: id=UJ-001 kind=screenshot value=ok\n- **还原度断言**：未命中，不适用（T53 夹具）\n' >> docs/changes/CHG-1052/05-test-results.md
printf 'delivery_status: delivered\n' >> docs/changes/CHG-1052/09-changelog.md
cat > docs/changes/CHG-1052/07-review-report.md <<'EOF'
<!-- provenance
author: fixture
email: f@t
generated_at: 2026-01-01T00:00:00Z
generated_by: stamp-provenance.sh
-->
# 07
- 评审主体：antigravity / gemini / task-1052
## 用户可用性验收
- 结论：通过（依据 03.6 与 UJ-001）
- **建议人类走查（非阻塞）**：建议交付前真人走查一次
## 业务合理性终审
- 逐 UJ 质询结论：UJ-001 通过（业务现实依据）
- **业务终审主体**：antigravity / gemini / ses-t53kv
## 运行时走查
self_evidence: screenshot
## 发现处置
- **发现处置**：未命中，不适用（T53 KV 夹具）
## 评审结论
review_verdict: pass
EOF
echo y > src/t53kv.js
rc=0
scripts/agent-gate --stage stop >/dev/null 2>&1 || rc=$?
report "T53 TC-10048 structured KV lines pass E104/E107/E157/E161/E162" 0 "$rc"
cat > docs/changes/CHG-1052/07-review-report.md <<'EOF'
<!-- provenance
author: fixture
email: f@t
generated_at: 2026-01-01T00:00:00Z
generated_by: stamp-provenance.sh
-->
# 07
- 评审主体：antigravity / gemini / task-1052
## 用户可用性验收
- 结论：通过（依据 03.6 与 UJ-001）
- **建议人类走查（非阻塞）**：建议交付前真人走查一次
## 业务合理性终审
- 逐 UJ 质询结论：UJ-001 通过（业务现实依据）
- **业务终审主体**：antigravity / gemini / ses-t53kv
## 运行时走查
tool_surface_missing: true
visual_pack: pack.zip
compensation_uncovered_gap: non_empty
## 发现处置
- **发现处置**：未命中，不适用（T53 KV 夹具）
## 评审结论
review_verdict: pass
EOF
rc=0
out=$(scripts/agent-gate --stage stop 2>&1) || rc=$?
report "T53 TC-10048 structured KV catches E107 pass with non_empty gap" 2 "$rc"
check_output "T53 TC-10048 names GATE-E107" "GATE-E107" "$out"
cat > docs/changes/CHG-1052/07-review-report.md <<'EOF'
<!-- provenance
author: fixture
email: f@t
generated_at: 2026-01-01T00:00:00Z
generated_by: stamp-provenance.sh
-->
# 07
- 评审主体：antigravity / gemini / task-1052
## 用户可用性验收
- 结论：通过（依据 03.6 与 UJ-001）
- **建议人类走查（非阻塞）**：建议交付前真人走查一次
## 业务合理性终审
- 逐 UJ 质询结论：UJ-001 通过（业务现实依据）
- **业务终审主体**：antigravity / gemini / ses-t53kv
## 运行时走查
self_evidence: screenshot
## 发现处置
- **发现处置**：未命中，不适用（T53 KV 夹具）
## 评审结论
review_verdict: pass
EOF
printf 'downstream_status: hung\n' >> docs/changes/CHG-1052/09-changelog.md
rc=0
out=$(scripts/agent-gate --stage stop 2>&1) || rc=$?
report "T53 TC-10048 structured KV catches E162 delivered with hung downstream" 2 "$rc"
check_output "T53 TC-10048 names GATE-E162" "GATE-E162" "$out"

# TC-10049 & TC-10050 (ITEM-31 & ITEM-32): GATE-E164 secret scan & AI-LAZY warn
new_repo
seed_artifacts CHG-1053 L0 claude/s-1
scripts/agent-gate begin CHG-1053 >/dev/null 2>&1
mkdir -p src
_t53_sec_val='AK''IA1234567890ABCDEF' # agent-guard: allow-secret
printf 'KEY="%s"\n' "$_t53_sec_val" > src/cfg.py
git add src/cfg.py
rc=0
out=$(scripts/agent-gate --stage staged 2>&1) || rc=$?
report "T53 TC-10049 GATE-E164 blocks unexempted secret in staged diff" 2 "$rc"
check_output "T53 TC-10049 names GATE-E164" "GATE-E164" "$out"
printf 'KEY="%s" # agent-guard: allow-secret\n' "$_t53_sec_val" > src/cfg.py
git add src/cfg.py
rc=0
scripts/agent-gate --stage staged >/dev/null 2>&1 || rc=$?
report "T53 TC-10049 GATE-E164 allows annotated test fixture secret" 0 "$rc"
rm -f src/cfg.py && git add -A
printf 'function stub() { try { work(); } catch (e) {} }\n' > src/stub.js
git add src/stub.js
rc=0
out=$(scripts/agent-gate --stage staged 2>&1) || rc=$?
report "T53 TC-10050 AI-LAZY soft warn does not block staged (rc0)" 0 "$rc"
check_output "T53 TC-10050 stderr emits WARN [AI-LAZY]" "WARN \[AI-LAZY\]" "$out"

# ---- TC-10051, TC-10053, TC-10056, TC-10061, TC-10062 (v4.8.0 CHG-153) ----
# TC-10051 (ITEM-19): GATE-E163 causal DAG blocks code-before-intent & skips gitignored
new_repo
seed_artifacts CHG-1061 L2 claude/s-1
mkdir -p src
echo 'code1' > src/dag.js
git add docs/changes/CHG-1061 src/dag.js
scripts/agent-gate begin CHG-1061 >/dev/null 2>&1
rc=0
out=$(scripts/agent-gate --stage staged 2>&1) || rc=$?
report "T53 TC-10051 GATE-E163 blocks L2 code staged alongside uncommitted intent" 2 "$rc"
check_output "T53 TC-10051 names GATE-E163" "GATE-E163" "$out"
echo 'docs/changes/' > .gitignore
git reset -q HEAD docs/changes/CHG-1061
rc=0
scripts/agent-gate --stage staged >/dev/null 2>&1 || rc=$?
# If E125/E66 checks docs when ignored, check note emitted; restore explicit commit flow
rm -f .gitignore
git reset -q HEAD .
git add docs/changes/CHG-1061
git commit -qm "docs: CHG-1061 artifacts"
echo 'code1' > src/dag.js
git add src/dag.js
rc=0
scripts/agent-gate --stage staged >/dev/null 2>&1 || rc=$?
report "T53 TC-10051 L2 staged passes once 00-intent.md is committed in HEAD" 0 "$rc"
# Also check gitignored skip inside check-ignore repo
new_repo
seed_artifacts CHG-1062 L2 claude/s-2
echo 'docs/changes/' > .gitignore
git add .gitignore && git commit -qm "ignore changes"
scripts/agent-gate begin CHG-1062 >/dev/null 2>&1
mkdir -p src && echo 'x' > src/g.js && git add src/g.js
# owner=geek007 deadline=2099-12-31
out=$(AGENT_GUARD_CAUSAL_DAG=1 scripts/agent-gate --stage staged 2>&1) || true
check_output "T53 TC-10051 gitignored change_root degrades cleanly without E163" "is gitignored" "$out"
# Check --stage ci DAG order: oldest commits checked (intent -> code -> intent-edit passes; code -> intent -> code-edit blocks E163)
new_repo
seed_artifacts CHG-1066 L2 claude/s-6
scripts/agent-gate begin CHG-1066 >/dev/null 2>&1
base_ci1=$(git rev-parse HEAD)
git add docs/changes/CHG-1066 && git commit -qm "docs: initial intent"
mkdir -p src && echo 'c1' > src/dagci.js && git add src/dagci.js && git commit -qm "feat: code after intent"
printf '\n# follow-up intent clarification\n' >> docs/changes/CHG-1066/00-intent.md
printf '| REQ-001 | ok | DES-001 | TC-001 | PASS |\n' > docs/changes/CHG-1066/01.5-rtvm-matrix.md
printf '# code\n- src/dagci.js\n' > docs/changes/CHG-1066/04.5-coding-record.md
printf '# test\nPASS\n' > docs/changes/CHG-1066/05-test-results.md
printf '# delivery\n#### 遗留\n- 无\n' > docs/changes/CHG-1066/06-delivery-summary.md
printf '未命中，不适用（无配置变更）\n' > docs/changes/CHG-1066/06.5-deployment-config.md
printf '# review\n## 评审结论\n通过\n- **发现处置**：未命中，不适用（T53 夹具，无发现）\n- 评审主体：platform / glm-5.3-flash / ses-t53ci\n' > docs/changes/CHG-1066/07-review-report.md
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-1066/09-changelog.md
append_masters docs/changes/CHG-1066/09-changelog.md
ci_stamp_all docs/changes/CHG-1066
git add docs/changes/CHG-1066 && git commit -qm "docs: CHG-1066 delivery and intent refine"
rc=0
scripts/agent-gate --stage ci --base "$base_ci1" >/dev/null 2>&1 || rc=$?
report "T53 TC-10051 ci mode passes when initial intent precedes code even if intent refined later" 0 "$rc"
new_repo
seed_artifacts CHG-1067 L2 claude/s-7
scripts/agent-gate begin CHG-1067 >/dev/null 2>&1
base_ci2=$(git rev-parse HEAD)
mkdir -p src && echo 'c1' > src/dagbad.js && git add src/dagbad.js && git commit -qm "feat: premature code"
printf '| REQ-001 | ok | DES-001 | TC-001 | PASS |\n' > docs/changes/CHG-1067/01.5-rtvm-matrix.md
printf '# code\n- src/dagbad.js\n' > docs/changes/CHG-1067/04.5-coding-record.md
printf '# test\nPASS\n' > docs/changes/CHG-1067/05-test-results.md
printf '# delivery\n#### 遗留\n- 无\n' > docs/changes/CHG-1067/06-delivery-summary.md
printf '未命中，不适用（无配置变更）\n' > docs/changes/CHG-1067/06.5-deployment-config.md
printf '# review\n## 评审结论\n通过\n- **发现处置**：未命中，不适用（T53 夹具，无发现）\n- 评审主体：platform / glm-5.3-flash / ses-t53ci\n' > docs/changes/CHG-1067/07-review-report.md
printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-1067/09-changelog.md
append_masters docs/changes/CHG-1067/09-changelog.md
ci_stamp_all docs/changes/CHG-1067
git add docs/changes/CHG-1067 && git commit -qm "docs: CHG-1067 retroactive delivery"
echo 'c2' >> src/dagbad.js && git add src/dagbad.js && git commit -qm "feat: second code edit"
out=$(scripts/agent-gate --stage ci --base "$base_ci2" 2>&1 || true)
check_output "T53 TC-10051 ci mode catches earliest code before intent even with later code edit" "GATE-E163" "$out"

# TC-10053 (ITEM-21): record-red records non-zero receipt and satisfies E150
new_repo
seed_artifacts CHG-1063 L1 claude/s-3
scripts/agent-gate begin CHG-1063 >/dev/null 2>&1
scripts/agent-gate record-red CHG-1063 -- "exit 0" >/dev/null 2>&1
report "T53 TC-10053 record-red refuses passing command (rc2)" 2 $?
scripts/agent-gate record-red CHG-1063 -- "false" >/dev/null 2>&1
report "T53 TC-10053 record-red refuses unclassified bare false (rc2)" 2 $?
scripts/agent-gate record-red CHG-1063 -- "echo 'AssertionError: expected 1 got 2'; exit 1" >/dev/null 2>&1
report "T53 TC-10053 record-red succeeds on assertion failure command" 0 $?
mkdir -p resources/templates && echo '# edited core' >> resources/templates/agent-gate.sh
git add resources/templates/agent-gate.sh
mkdir -p docs/changes/CHG-1063
cat > docs/changes/CHG-1063/05-test-results.md <<'EOF'
# 05
green_after: echo ok -> rc0
EOF
# owner=geek007 deadline=2099-12-31
out=$(AGENT_GUARD_FRESH_CLONE=0 scripts/agent-gate --stage core 2>&1 || true)
report "T53 TC-10053 red-receipt satisfies E150 (reaches E151 next)" 0 "$(grep -q 'GATE-E151' <<< "$out"; echo $?)"

# TC-10056 (ITEM-24): pre-commit RETROACTIVE_PROBE triggers without begin receipt
if [[ -s "$ROOT/resources/templates/pre-commit" ]]; then
  new_repo
  seed_artifacts CHG-1064 L1 claude/s-4
  mkdir -p .githooks .git/agent-governance
  cp "$ROOT/resources/templates/pre-commit" .githooks/pre-commit
  chmod +x .githooks/pre-commit
  rm -rf docs/changes/CHG-1064
  mkdir -p src && echo 'bad' > src/p.js && git add src/p.js
  printf 'CHG-1064\n' > .git/agent-governance/active-change
  mkdir -p .agent-state
  rc=0
  out=$(bash .githooks/pre-commit 2>&1) || rc=$?
  report "T53 TC-10056 pre-commit fails when active change docs missing" 2 "$rc"
  check_output "T53 TC-10056 triggers RETROACTIVE_PROBE defense" "RETROACTIVE_PROBE" "$out"
  _pc_fcol1=$(awk -F'\t' '$1=="RETROACTIVE_PROBE"{print $1; exit}' .agent-state/gate-friction.tsv 2>/dev/null || true)
  report "T53 TC-10056 gate-friction col1 is RETROACTIVE_PROBE (5-col schema)" "RETROACTIVE_PROBE" "$_pc_fcol1"
  seed_artifacts CHG-1064 L1 claude/s-4
  scripts/agent-gate begin CHG-1064 >/dev/null 2>&1
  git add docs/changes/CHG-1064 src/p.js
  bash .githooks/pre-commit >/dev/null 2>&1
  _pc_left=$(grep -c '^CHG-1064	' .agent-state/pre-commit-streak.tsv 2>/dev/null || true)
  report "T53 TC-10056 passing pre-commit clears single-row streak" 0 "${_pc_left:-0}"
else
  report "T53 TC-10056 pre-commit fail (skip: template absent)" 0 0
  report "T53 TC-10056 RETROACTIVE_PROBE (skip: template absent)" 0 0
  report "T53 TC-10056 gate-friction col1 is RETROACTIVE_PROBE (skip: template absent)" 0 0
  report "T53 TC-10056 passing pre-commit clears streak (skip: template absent)" 0 0
fi

# TC-10063 (ITEM-45): hot/cold split — begin/preflight stay hot; help/next/review-models load cold lib
new_repo
seed_artifacts CHG-1069 L0 claude/s-7
_tc63_pre=$(bash -c 'scripts/agent-gate preflight CHG-1069 2>&1 || true')
check_output "T53 TC-10063 hot preflight works without error" "preflight" "$_tc63_pre"
out=$(bash scripts/agent-gate help 2>&1)
check_output "T53 TC-10063 cold help prints usage via lib-gate-cold" "Usage:" "$out"
out=$(bash scripts/agent-gate next CHG-1069 --json 2>&1)
check_output "T53 TC-10063 cold next --json returns JSON" '"change_id":"CHG-1069"' "$out"

# TC-10064 (ITEM-40) & TC-10065 (ITEM-42): STANDARDS_CHANGELOG <= 20480 + archive & DS <= 155648
if [[ -f "$ROOT/archive/STANDARDS_CHANGELOG_ARCHIVE.md" ]]; then
  _cl_sz=$(wc -c < "$ROOT/resources/STANDARDS_CHANGELOG.md" | tr -d ' ')
  _ds_sz=$(wc -c < "$ROOT/resources/DEVELOPMENT_STANDARDS.md" | tr -d ' ')
  report "T53 TC-10064 STANDARDS_CHANGELOG <= 20480B" 1 "$([[ "$_cl_sz" -le 20480 ]] && echo 1 || echo 0)"
  report "T53 TC-10064 STANDARDS_CHANGELOG_ARCHIVE retains v2.9.0" 1 "$(grep -c '^| v2\.9\.0 ' "$ROOT/archive/STANDARDS_CHANGELOG_ARCHIVE.md" || true)"
  report "T53 TC-10065 DEVELOPMENT_STANDARDS <= 155648B" 1 "$([[ "$_ds_sz" -le 155648 ]] && echo 1 || echo 0)"
fi

# TC-10061 (ITEM-29): optional L0/L1 single-file change-card mode
new_repo
printf 'change_card_mode: true\n' > .agent-governance.yml
cat > docs/changes/CHG-1065.md <<'EOF'
# CHG-1065
risk: L1
intent: small bugfix
scope: src/c.js
verification: echo ok
status: done
EOF
scripts/agent-gate begin CHG-1065 >/dev/null 2>&1
report "T53 TC-10061 L1 change-card begin passes" 0 $?
mkdir -p src && echo 'ok' > src/c.js && git add .agent-governance.yml docs/changes/CHG-1065.md src/c.js
scripts/agent-gate --stage pre-write --file src/c.js >/dev/null 2>&1
report "T53 TC-10061 change-card pre-write passes" 0 $?
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T53 TC-10061 change-card staged passes" 0 $?
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-10061 change-card stop passes" 0 $?
cat > docs/changes/CHG-1066.md <<'EOF'
# CHG-1066
risk: L2
intent: not allowed
scope: src/c.js
verification: echo ok
status: pending
EOF
scripts/agent-gate begin CHG-1066 >/dev/null 2>&1
report "T53 TC-10061 change-card rejects L2 risk" 2 $?

# TC-10062b (FU-15202): E164 detects Stripe underscore secret & github_pat_
new_repo
seed_artifacts CHG-1067 L0 claude/s-5
scripts/agent-gate begin CHG-1067 >/dev/null 2>&1
mkdir -p src
_t53_pat='github_p''at_1234567890abcdefghij123' # agent-guard: allow-secret
printf 'TOK="%s"\n' "$_t53_pat" > src/tok.py
git add src/tok.py
rc=0
out=$(scripts/agent-gate --stage staged 2>&1) || rc=$?
report "T53 TC-10062 FU-15202 E164 blocks github_pat_ token" 2 "$rc"

# TC-10052b (ITEM-20): stop emits non-blocking WARN [MTIME] when doc mtime > earliest code mtime
new_repo
seed_artifacts CHG-1068 L0 claude/s-6
scripts/agent-gate begin CHG-1068 >/dev/null 2>&1
mkdir -p src && echo 'old' > src/mt.js && git add src/mt.js
touch -t 202001010000 src/mt.js
seed_t53_delivery CHG-1068
out=$(scripts/agent-gate --stage stop 2>&1)
check_output "T53 TC-10052 stop emits WARN [MTIME] when doc newer than code" "WARN \[MTIME\]" "$out"

# TC-10069 (ITEM-46): enforcement.mode strict | ratchet | advisory (GATE-E164 never downgraded)
new_repo
_t53_ef=$(pwd)
mkdir -p src
printf 'export const x = 1;\n' > src/a.js
git add src/a.js
out=$(AGENT_GUARD_ENFORCEMENT_MODE=advisory bash scripts/agent-gate --stage staged 2>&1); rc=$?
report "T53 TC-10069 advisory mode downgrades non-security staged gate to rc0" 0 "$rc"
check_output "T53 TC-10069 advisory mode prints ADVISORY tag" "ADVISORY" "$out"
printf 'const tok = "%s%s";\n' "ghp_" "1234567890abcdef1234567890abcdef1234" > src/sec.js
git add src/sec.js
out=$(AGENT_GUARD_ENFORCEMENT_MODE=advisory bash scripts/agent-gate --stage staged 2>&1); rc=$?
report "T53 TC-10069 advisory mode NEVER downgrades GATE-E164 secret scan" 2 "$rc"
check_output "T53 TC-10069 refusal names GATE-E164" "GATE-E164" "$out"
git reset -q && rm -f src/sec.js src/a.js
mkdir -p docs/changes/CHG-OLD docs/changes/CHG-NEW .git/agent-governance
printf '# CHG-OLD\n' > docs/changes/CHG-OLD/00-intent.md
printf '{"change_id":"CHG-OLD","change_uid":"CHG-20261001-01","risk_level":"L1"}\n' > docs/changes/CHG-OLD/00-governance.json
printf '# 01\n### REQ-1\n' > docs/changes/CHG-OLD/01-spec.md
printf '| REQ-1 | r | DES-1 | d | T-1 | c | TC-1 | m | 待验证 |\n' > docs/changes/CHG-OLD/01.5-rtvm-matrix.md
printf '# 09\n' > docs/changes/CHG-OLD/09-changelog.md
printf '# CHG-NEW\n' > docs/changes/CHG-NEW/00-intent.md
printf '{"change_id":"CHG-NEW","change_uid":"CHG-20261125-01","risk_level":"L1"}\n' > docs/changes/CHG-NEW/00-governance.json
printf '# 01\n### REQ-1\n' > docs/changes/CHG-NEW/01-spec.md
printf '| REQ-1 | r | DES-1 | d | T-1 | c | TC-1 | m | 待验证 |\n' > docs/changes/CHG-NEW/01.5-rtvm-matrix.md
printf '# 09\n' > docs/changes/CHG-NEW/09-changelog.md
echo "CHG-OLD" > .git/agent-governance/active-change
out=$(AGENT_GUARD_ENFORCEMENT_MODE=ratchet AGENT_GUARD_RATCHET_SINCE=2026-11-01 bash scripts/agent-gate --stage rtvm 2>&1); rc=$?
report "T53 TC-10069 ratchet mode treats pre-since change as advisory" 0 "$rc"
echo "CHG-NEW" > .git/agent-governance/active-change
out=$(AGENT_GUARD_ENFORCEMENT_MODE=ratchet AGENT_GUARD_RATCHET_SINCE=2026-11-01 bash scripts/agent-gate --stage rtvm 2>&1); rc=$?
report "T53 TC-10069 ratchet mode enforces strict on post-since change" 2 "$rc"
cd "$ROOT"
rm -rf "$_t53_ef"

# ---- CHG-164 (REQ-1640~1644, DES-1640~1644): E-1/E-2/E-4/E-5/E-6 ----
# TC-1640a~d & TC-1641a~d: record-red output classification + record-green
new_repo
seed_artifacts CHG-1640 L1 claude/s-1
mkdir -p src tests
printf 'bad\n' > src/app.sh
cat > tests/test_app.sh <<'EOF'
#!/usr/bin/env bash
if [[ "${PASS_OVERRIDE:-0}" == "1" ]] || grep -q '^ok$' src/app.sh; then
  echo "1 passed"; exit 0
fi
echo "AssertionError: expected ok in src/app.sh" >&2; exit 1
EOF
chmod +x tests/test_app.sh
printf '# 05\n' > docs/changes/CHG-1640/05-test-results.md
git add src/app.sh tests/test_app.sh && git commit -qm "chore: add test fixture"
scripts/agent-gate begin CHG-1640 >/dev/null 2>&1

scripts/agent-gate record-red CHG-1640 -- "nonexistent_cmd_xyz_1640" >/dev/null 2>&1
report "T53 TC-1640a record-red refuses exit 127 command-not-found (rc2)" 2 $?

scripts/agent-gate record-red CHG-1640 -- "echo 'ModuleNotFoundError: No module named x' >&2; exit 1" >/dev/null 2>&1
report "T53 TC-1640b record-red refuses red-error ModuleNotFoundError (rc2)" 2 $?

scripts/agent-gate record-red CHG-1640 -- "false" >/dev/null 2>&1
report "T53 TC-1640c record-red refuses unclassified empty false without flag (rc2)" 2 $?

scripts/agent-gate record-red CHG-1640 --accept-unclassified "legacy fixture" -- "false" >/dev/null 2>&1
report "T53 TC-1640c record-red accepts unclassified with --accept-unclassified" 0 $?
report "T53 TC-1640c --accept-unclassified logs RED_UNCLASSIFIED to friction" 1 "$(grep -c '^RED_UNCLASSIFIED	' .agent-state/gate-friction.tsv 2>/dev/null || echo 0)"

scripts/agent-gate record-red CHG-1640 --layer api --target-tests "TC-1640" -- "bash tests/test_app.sh" >/dev/null 2>&1
report "T53 TC-1640d record-red accepts red-assertion command" 0 $?
_rr1640=$(cat .git/agent-governance/red-receipts/CHG-1640.json 2>/dev/null || true)
check_output "T53 TC-1640d red receipt records class red-assertion" '"class":"red-assertion"' "$_rr1640"
check_output "T53 TC-1640d red receipt records layer api" '"layer":"api"' "$_rr1640"
check_output "T53 TC-1640d red receipt records output_sha" '"output_sha":"[0-9a-f-]+' "$_rr1640"

scripts/agent-gate record-green CHG-1640 -- "echo different" >/dev/null 2>&1
report "T53 TC-1641a record-green refuses mismatched command (rc2)" 2 $?

PASS_OVERRIDE=1 scripts/agent-gate record-green CHG-1640 -- "bash tests/test_app.sh" >/dev/null 2>&1
report "T53 TC-1641b record-green refuses unchanged tracked_tree_sha (rc2)" 2 $?

printf 'still_bad\n' > src/app.sh
scripts/agent-gate record-green CHG-1640 -- "bash tests/test_app.sh" >/dev/null 2>&1
report "T53 TC-1641c record-green refuses failing command after tree change (rc2)" 2 $?

printf 'ok\n' > src/app.sh
scripts/agent-gate record-green CHG-1640 -- "bash tests/test_app.sh" >/dev/null 2>&1
report "T53 TC-1641d record-green succeeds on same cmd with changed tree and rc0" 0 $?
report "T53 TC-1641d green receipt file created" 0 "$([[ -s .git/agent-governance/green-receipts/CHG-1640.json ]]; echo $?)"
check_output "T53 TC-1641d 05-test-results gets green_after line" '^green_after:' "$(cat docs/changes/CHG-1640/05-test-results.md)"

# TC-1641e (F-03): command containing double quotes matches across record-red and record-green
printf 'bad\n' > src/app.sh
scripts/agent-gate record-red CHG-1640 -- 'bash -c "bash tests/test_app.sh"' >/dev/null 2>&1
report "T53 TC-1641e record-red succeeds on quoted command" 0 $?
printf 'ok\n' > src/app.sh
scripts/agent-gate record-green CHG-1640 -- 'bash -c "bash tests/test_app.sh"' >/dev/null 2>&1
report "T53 TC-1641e record-green matches quoted command via norm_cmd_sha" 0 $?

# TC-1642a: E-4 discovery layer alignment
new_repo
seed_artifacts CHG-1642 L1 claude/s-1
mkdir -p docs/bugs/BUG-1642
cat > docs/bugs/BUG-1642/01-diagnosis.md <<'EOF'
# BUG-1642
| 字段 | 内容 |
|---|---|
| 发现层 | e2e |
| 诊断人 / 处置主体 | Claude / s1 |
延伸发现：未发现
历史相似检索：未命中（x）
EOF
for _bf in 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
  printf '# %s\n' "$_bf" > "docs/bugs/BUG-1642/$_bf"
done
printf '{"change_id":"CHG-1642","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-t","review_owner":"claude/s-r","bug_ref":"BUG-1642"}\n' > docs/changes/CHG-1642/00-governance.json
scripts/agent-gate begin CHG-1642 >/dev/null 2>&1
scripts/agent-gate record-red CHG-1642 --layer unit -- "echo 'AssertionError: fail'; exit 1" >/dev/null 2>&1
report "T53 TC-1642a record-red refuses --layer unit below discovery layer e2e (rc2)" 2 $?
scripts/agent-gate record-red CHG-1642 --layer e2e -- "echo 'AssertionError: fail'; exit 1" >/dev/null 2>&1
report "T53 TC-1642a record-red accepts --layer e2e matching discovery layer" 0 $?

# TC-1643a~b & TC-1644a~b: E-5 defect_fp escalation + E-6 escape & metrics
new_repo
mkdir -p docs/bugs/BUG-1643A docs/bugs/BUG-1643B docs/bugs/BUG-1643C
for _bg in BUG-1643A BUG-1643B BUG-1643C; do
  for _bf in 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
    printf '# %s\n' "$_bf" > "docs/bugs/$_bg/$_bf"
  done
  for _bf in 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
    { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat "docs/bugs/$_bg/$_bf"; } > "docs/bugs/$_bg/$_bf.tmp" && mv "docs/bugs/$_bg/$_bf.tmp" "docs/bugs/$_bg/$_bf"
  done
done
cat > docs/bugs/BUG-1643A/01-diagnosis.md <<'EOF'
<!-- provenance
author: fixture
email: f@t
generated_at: 2026-01-01T00:00:00Z
generated_by: stamp-provenance.sh
-->
# BUG-1643A
| 字段 | 内容 |
|---|---|
| defect_fp | fp-alpha |
| 诊断人 / 处置主体 | Claude / s1 |
| 状态 | 已闭环 |
| 应捕获层 | 测试 |
延伸发现：未发现
历史相似检索：未命中（x）
EOF
cat > docs/bugs/BUG-1643B/01-diagnosis.md <<'EOF'
<!-- provenance
author: fixture
email: f@t
generated_at: 2026-01-02T00:00:00Z
generated_by: stamp-provenance.sh
-->
# BUG-1643B
| 字段 | 内容 |
|---|---|
| defect_fp | fp-alpha |
| 诊断人 / 处置主体 | Claude / s1 |
| 状态 | 诊断中 |
延伸发现：未发现
历史相似检索：未命中（x）
EOF
cat > docs/bugs/BUG-1643C/01-diagnosis.md <<'EOF'
<!-- provenance
author: fixture
email: f@t
generated_at: 2026-01-03T00:00:00Z
generated_by: stamp-provenance.sh
-->
# BUG-1643C
| 字段 | 内容 |
|---|---|
| defect_fp | fp-alpha |
| 诊断人 / 处置主体 | Antigravity / s3 |
| 状态 | 诊断中 |
## 升级节
- 观测先行：加调试日志
- 上次为何未修好：未处理边界
延伸发现：未发现
历史相似检索：未命中（x）
EOF
printf 'BUG-1643A\nBUG-1643B\nBUG-1643C\n' > docs/bugs/.gate-allowlist
mkdir -p src && printf 'x=1\n' > src/work.js && git add src/work.js
seed_artifacts CHG-1643 L2 claude/s-1 claude/s-2 claude/s-3
printf '{"change_id":"CHG-1643","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-2","review_owner":"claude/s-3","bug_ref":"BUG-1643B"}\n' > docs/changes/CHG-1643/00-governance.json
scripts/agent-gate begin CHG-1643 >/dev/null 2>&1
seed_t53_delivery CHG-1643
printf '\n- [dogfood] verified CHG-1643\n- [dogfood-next] next item\n' >> docs/changes/CHG-1643/09-changelog.md
printf '# coding record\n- file: src/work.js\n' > docs/changes/CHG-1643/04.5-coding-record.md
printf '# test results\n- TC-001: pass\n' > docs/changes/CHG-1643/05-test-results.md
printf '# review\n## 评审结论\n通过\n- **发现处置**：未命中，不适用（T53 夹具）\n- 评审主体：claude / model / ses-r1\n' > docs/changes/CHG-1643/07-review-report.md
stamp_all docs/changes/CHG-1643

out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "T53 TC-1643a 2nd fix with same diagnosis owner refuses at L2 (rc2)" 2 "$rc"
check_output "T53 TC-1643a names GATE-E81" "GATE-E81" "$out"

# L1 advisory only warns
printf '{"change_id":"CHG-1643","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-2","review_owner":"claude/s-3","bug_ref":"BUG-1643B"}\n' > docs/changes/CHG-1643/00-governance.json
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "T53 TC-1643a 2nd fix at L1 is advisory WARN (rc0)" 0 "$rc"
check_output "T53 TC-1643a L1 prints WARN for defect_fp" "WARN.*defect_fp" "$out"

# Back to L2, fix owner + escalation section -> passes
printf '{"change_id":"CHG-1643","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-2","review_owner":"claude/s-3","bug_ref":"BUG-1643B"}\n' > docs/changes/CHG-1643/00-governance.json
cat > docs/bugs/BUG-1643B/01-diagnosis.md <<'EOF'
<!-- provenance
author: fixture
email: f@t
generated_at: 2026-01-02T00:00:00Z
generated_by: stamp-provenance.sh
-->
# BUG-1643B
| 字段 | 内容 |
|---|---|
| defect_fp | fp-alpha |
| 诊断人 / 处置主体 | Antigravity / s2 |
| 状态 | 已闭环 |
## 升级节
- 观测先行：日志探针
- 上次为何未修好：漏边界
延伸发现：未发现
历史相似检索：未命中（x）
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1643a 2nd fix with new owner and escalation section passes" 0 $?

# TC-1643b: 3rd occurrence requires >=2 candidates in 03 and architecture signature in 07
seed_artifacts CHG-1644 L2 claude/s-1 claude/s-2 claude/s-3
printf '{"change_id":"CHG-1644","risk_level":"L2","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-2","review_owner":"claude/s-3","bug_ref":"BUG-1643C"}\n' > docs/changes/CHG-1644/00-governance.json
scripts/agent-gate begin CHG-1644 >/dev/null 2>&1
seed_t53_delivery CHG-1644
printf '\n- [dogfood] verified CHG-1644\n- [dogfood-next] next item\n' >> docs/changes/CHG-1644/09-changelog.md
printf '# coding record\n- file: src/work.js\n' > docs/changes/CHG-1644/04.5-coding-record.md
printf '# test results\n- TC-001: pass\n' > docs/changes/CHG-1644/05-test-results.md
printf '# review\n## 评审结论\n通过\n- **发现处置**：未命中，不适用（T53 夹具）\n- 评审主体：claude / model / ses-r2（架构）\n' > docs/changes/CHG-1644/07-review-report.md
printf '# plan\n- DES-001: patch\n## 技术选型\n单方案说明\n## 既有范式关系\n- **既有范式关系**：未命中（x）\n' > docs/changes/CHG-1644/03-modification-plan.md
stamp_all docs/changes/CHG-1644
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "T53 TC-1643b 3rd fix single-factor: arch review present but 03 lacks >=2 options refuses (rc2)" 2 "$rc"
check_output "T53 TC-1643b names GATE-E81" "GATE-E81" "$out"

printf '# plan\n- DES-001: redesign\n## 技术选型\n| 方案 | 说明 |\n|---|---|\n| 方案 A | 局部补丁 |\n| 方案 B | 架构重构 |\n## 既有范式关系\n- **既有范式关系**：未命中（x）\n' > docs/changes/CHG-1644/03-modification-plan.md
stamp_all docs/changes/CHG-1644
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T53 TC-1643b 3rd fix with >=2 options and architecture signature passes" 0 $?

# TC-1643c (F-02): missing defect_fp with >=50% affected files overlap emits advisory WARN
printf '| 字段 | 内容 |\n|---|---|\n| 影响文件 | src/work.js |\n' >> docs/bugs/BUG-1643A/01-diagnosis.md
mkdir -p docs/bugs/BUG-1643D
for _bf in 02-impact.md 03-test-plan.md 04-matrix.md 05-config.md 06-tasks.md; do
  { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-04T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# %s\n' "$_bf"; } > "docs/bugs/BUG-1643D/$_bf"
done
printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-04T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# BUG-1643D\n| 字段 | 内容 |\n|---|---|\n| defect_fp | <待填> |\n延伸发现：未发现\n历史相似检索：未命中（x）\n' > docs/bugs/BUG-1643D/01-diagnosis.md
printf 'BUG-1643D\n' >> docs/bugs/.gate-allowlist
seed_artifacts CHG-1645 L1 claude/s-1 claude/s-2 claude/s-3
printf '{"change_id":"CHG-1645","risk_level":"L1","spec_author":"author/a-1","implementation_owner":"claude/s-1","test_owner":"claude/s-2","review_owner":"claude/s-3","bug_ref":"BUG-1643D"}\n' > docs/changes/CHG-1645/00-governance.json
scripts/agent-gate begin CHG-1645 >/dev/null 2>&1
seed_t53_delivery CHG-1645
printf '\n- [dogfood] verified CHG-1645\n- [dogfood-next] next item\n' >> docs/changes/CHG-1645/09-changelog.md
printf '# coding record\n- file: src/work.js\n' > docs/changes/CHG-1645/04.5-coding-record.md
printf '# test results\n- TC-001: pass\n' > docs/changes/CHG-1645/05-test-results.md
printf '# review\n## 评审结论\n通过\n- **发现处置**：未命中，不适用（T53 夹具）\n- 评审主体：claude / model / ses-r3\n' > docs/changes/CHG-1645/07-review-report.md
stamp_all docs/changes/CHG-1645
out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
report "T53 TC-1643c missing defect_fp with >=50% file overlap passes with WARN (rc0)" 0 "$rc"
check_output "T53 TC-1643c warns about >=50% affected file overlap" "overlap" "$out"

# TC-1644a~b: escape command + metrics --summary
scripts/agent-gate escape BUG-1643A --should-catch 测试 >/dev/null 2>&1
report "T53 TC-1644a escape records defect into diagnosis and eval-cases.tsv" 0 $?
check_output "T53 TC-1644a diagnosis marked escaped_after_claim" 'escaped_after_claim:[[:space:]]*yes' "$(cat docs/bugs/BUG-1643A/01-diagnosis.md)"
report "T53 TC-1644a eval-cases.tsv holds EC-BUG-1643A" 1 "$(grep -c '^EC-BUG-1643A	escape	BUG-1643A	测试	' .agent-state/eval-cases.tsv 2>/dev/null || echo 0)"
scripts/agent-gate escape BUG-1643A --should-catch 测试 >/dev/null 2>&1
report "T53 TC-1644a escape is idempotent on repeat run" 1 "$(grep -c '^EC-BUG-1643A	' .agent-state/eval-cases.tsv 2>/dev/null || echo 0)"
_m164=$(scripts/agent-gate metrics --summary --json 2>/dev/null || true)
check_output "T53 TC-1644b metrics summary json includes numeric escape_rate" '"escape_rate":0\.' "$_m164"
check_output "T53 TC-1644b metrics summary json includes numeric same_fp_reopen_rate" '"same_fp_reopen_rate":1\.00' "$_m164"
}

section_T54() {
# ------------------------------------------------ T54 G14e 交互元素枚举（CHG-044）
# TC-1234~1238：元素行抽取（静态按钮/hidden 排除）→ 与行为行并存 → E102 元素孤儿对账 →
# 逗号列表批量接线 → 登记簿豁免传递（00.5）。词表唯一权威 = resources/templates/
# behavior-extract.sh 头注释（audit A43 单源执法），本节只持行为断言，禁止复制词表。
# CHG-044 01-spec REQ 尚为占位，REQ 映射待其填实后补记。
EXTRACT_SRC="$ROOT/resources/templates/behavior-extract.sh"
[[ -f "$EXTRACT_SRC" ]] || EXTRACT_SRC="$ROOT/scripts/behavior-extract.sh"
new_repo
seed_artifacts CHG-1060 L0 claude/s-1
mkdir -p proto
cat > proto/page.html <<'EOF'
<button id="btnStatic">静态按钮</button>
<button id="mic" onclick="录音()">主操作</button>
<input type="hidden" id="hid" value="x">
<div role="checkbox" aria-checked="false"></div>
<a href="/list">列表</a>
EOF
cat > docs/changes/CHG-1060/01-spec.md <<'EOF'
# spec
- REQ-001: 演示页对齐真实链路
- **origin_artifact**: proto/page.html
- **chain_change**: 未命中（静态演示页，无数据链变更）
- **ui_change**: false
- 事件链：BHV-002 主操作点击走真实业务链路（BHV-003 同元素）
EOF
bash "$EXTRACT_SRC" proto/page.html > docs/changes/CHG-1060/behavior-inventory.json
inv=docs/changes/CHG-1060/behavior-inventory.json
t54_total=$(sed -n '1s/.*"total_behaviors":\([0-9]*\).*/\1/p' "$inv")
report "T54 TC-1234 fixture pins total=5 (2 behavior + 3 element rows)" 0 "$([[ "$t54_total" == 5 ]]; echo $?)"
report "T54 TC-1234 handler-free static button yields an element row" 1 "$(grep -c '"kind":"element","event":"button","target":"#btnStatic"' "$inv")"
report "T54 TC-1234 hidden input is excluded from element rows" 0 "$(grep -c '"target":"#hid"' "$inv")"
report "T54 TC-1235 behavior row for #mic (click)" 1 "$(grep -c '"kind":"click","event":"click","target":"mic"' "$inv")"
report "T54 TC-1235 element row coexists for #mic" 1 "$(grep -c '"kind":"element","event":"button","target":"#mic"' "$inv")"
scripts/agent-gate begin CHG-1060 >/dev/null 2>&1
report "T54 TC-1236 begin green before stop progression" 0 $?
seed_t53_delivery CHG-1060
echo y > src/t54.js
# TC-1236（E102 stop 级）：元素 BHV-001 全目录无引用且未豁免 → stop 红
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1236 E102 stop red: element BHV-001 never referenced nor waived" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T54 TC-1236 refusal names GATE-E102 with the element orphan id" "GATE-E102.*BHV-001" "$out"
# TC-1237：03.6/产物以逗号列表批量接线元素 BHV → 绿
printf -- '- 元素清单：BHV-001, BHV-004, BHV-005（逗号列表批量接线）\n' >> docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1237 stop green once element BHVs wired via comma list" 0 $?
# TC-1238：登记簿豁免元素 BHV（行为豁免+00.5 引用）→ 绿；去掉 00.5 → E108 红 → 恢复绿
cat >> docs/changes/CHG-1060/01-spec.md <<'EOF'

## 拆除/豁免登记簿
| 行为 | 处置 | 理由 |
|---|---|---|
| BHV-001 | 行为豁免 | 00.5 追加沟通轮：静态占位按钮已确认豁免 |
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1238 stop green: element waiver carries 00.5 reference" 0 $?
sed -e 's/00\.5 追加沟通轮：静态占位按钮已确认豁免/静态占位按钮已确认豁免（无沟通轮）/' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1238 E108 stop red: element waiver loses 00.5 reference" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T54 TC-1238 refusal names GATE-E108 with the element id" "GATE-E108.*BHV-001" "$out"
sed -e 's/静态占位按钮已确认豁免（无沟通轮）/00.5 追加沟通轮：静态占位按钮已确认豁免/' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1238 stop green again after 00.5 restored" 0 $?
# TC-1239（FU-934 收窄①，v3.70.0）：登记簿节外的「行为豁免」表行 → E108 红（堵节外躲检）
awk '{print} /元素清单/{print "| BHV-001 | 行为豁免 | 节外豁免行试图躲检 |"}' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1239 E108 stop red: waiver row outside the ledger section" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T54 TC-1239 refusal names the outside-ledger narrowing" "GATE-E108" "$out"
grep -v '^| BHV-001 | 行为豁免 | 节外豁免行试图躲检 |$' docs/changes/CHG-1060/01-spec.md > .t54-spec.tmp && mv .t54-spec.tmp docs/changes/CHG-1060/01-spec.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T54 TC-1239 stop green again after stray row removed" 0 $?
}

section_T55() {
# ------------------------------------------------ T55 交付四门（v3.71.0，CHG-046）
# ① E110（REQ-1087）：ui_change 变更 05 还原度断言行三态
new_repo
seed_begin CHG-1070 L1 claude/s-1
printf '# spec\n- **ui_change**：true\n## 用户任务\n### UJ-001\n- **入口**：记录列表\n### REQ-001\n**描述**：r\n**挂靠 UJ**：UJ-001\n' > docs/changes/CHG-1070/01-spec.md
printf '# ui\n## 显示名↔主键映射\n- 记录显示名 → record_id\n' > docs/changes/CHG-1070/03.6-ui-spec.md
printf '# tasks\n| 任务 | 类型 | 依赖 | 里程碑 | 说明 |\n|---|---|---|---|---|\n| T1 | UX | 无 | M1 | 设计 |\n- 评审输入: x\n' > docs/changes/CHG-1070/03.5-tasks.md
printf '# tests\n- TC-001 用户旅程 E2E（真人入口）\n覆盖维度: 正常流\n- SC-001 用户旅程 E2E（覆盖: TC-001）\n' > docs/changes/CHG-1070/04-test-scripts.md
scripts/agent-gate begin CHG-1070 >/dev/null 2>&1
printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-1070/04.5-coding-record.md
printf '# 05 测试结果\n- UJ-001 HTTP 200 响应体 {"ok":true} @2026-10-14T00:00:00Z\n' > docs/changes/CHG-1070/05-test-results.md
printf '# review\n## 用户可用性验收\n- 结论：通过（依据 03.6 与 UJ-001）\n- **建议人类走查（非阻塞）**：建议走查一次\n## 业务合理性终审\n- 逐 UJ 质询结论：UJ-001 通过（业务现实依据，未引本变更图纸）\n- **业务终审主体**：platform / glm / ses-t55a\n- **发现处置**：未命中，不适用（T55 交付四门夹具，无发现）\n## 评审结论\n通过\n## 运行时走查\n- ses-rev-1 走查 UJ-001，截图 t55-home.png 留痕\n\n署名：agent-platform / llm-model / task-rev-1\n' > docs/changes/CHG-1070/07-review-report.md
printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：本变更无配置项、无 DB 变更。\n' > docs/changes/CHG-1070/06.5-deployment-config.md
printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-901 | 样例遗留 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-1070/06-delivery-summary.md
printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | grep -c REQ- 01-spec.md -> 1 |\n' > docs/changes/CHG-1070/09-changelog.md
append_masters docs/changes/CHG-1070/09-changelog.md
stamp_all docs/changes/CHG-1070
echo x > src/a.go
scripts/agent-gate --stage stop >/dev/null 2>&1
rc_e110a=$?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
report "T55 TC-1248 E110 red: 05 lacks the restoration-assertion line" 2 "$rc_e110a"
check_output "T55 TC-1248 refusal names GATE-E110" "GATE-E110" "$out"
# 豁免声明行 → E110 过（走到后续门全绿，写入首次交付记录）
printf '# 05 测试结果\n- UJ-001 HTTP 200 响应体 {"ok":true} @2026-10-14T00:00:00Z\n- **还原度断言**：未命中，不适用（无自动化环境，人工逐屏清单已附）\n' > docs/changes/CHG-1070/05-test-results.md
stamp_all docs/changes/CHG-1070
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1249 waiver declaration passes E110 (full stop green)" 0 $?
# 指向不存在文件 → 红；点名路径（05 换行重写后补章保 E19）
printf '# 05 测试结果\n- UJ-001 HTTP 200 响应体 {"ok":true} @2026-10-14T00:00:00Z\n- **还原度断言**：tests/ui-proto.test.js（断言面：节序/占位形态）\n' > docs/changes/CHG-1070/05-test-results.md
stamp_all docs/changes/CHG-1070
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T55 TC-1249 E110 red: assertion file missing" "GATE-E110.*ui-proto" "$out"
# 文件在 + 断言标记在 → 绿（全 stop 再绿；为 E112 铺垫交付记录）
mkdir -p tests
printf 'describe("proto", () => { it("节序", () => expect(1).toBe(1)); });\n' > tests/ui-proto.test.js
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1247 evidence line with a real test file passes (stop green)" 0 $?
# ② E112（REQ-1090）：同会话重复交付换挡执法（new_repo 已置 started_at=-1H 与
#    AGENT_GUARD_ALLOW_NO_SHIFT=1 导出——本组用 =0 显式开启执法面，T49 同法）
echo y > src/b.js
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop >/dev/null 2>&1
rc_e112=$?
out=$(AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop 2>&1 || true)
report "T55 TC-1254 E112 red: in-session re-delivery without handoff" 2 "$rc_e112"
check_output "T55 TC-1254 refusal names GATE-E112" "GATE-E112" "$out"
printf '\n- **换挡声明**：未到换挡点（同批次连续变更，用户明示继续）\n' >> docs/changes/CHG-1070/09-changelog.md
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1254 换挡声明 line passes E112" 0 $?
perl -ni -e 'print unless /换挡声明/' docs/changes/CHG-1070/09-changelog.md
AGENT_GUARD_ALLOW_NO_SHIFT=1 scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1254 escape env passes E112" 0 $?
printf '# handoff\nCHG-1070 handoff record\n' > docs/changes/CHG-1070/handoff.md
stamp_all docs/changes/CHG-1070
AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1253 handoff.md passes E112" 0 $?
# ③ E113（REQ-1091）：TC 落点清单
new_repo
seed_begin CHG-1071 L1 claude/s-1
printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-1071/04.5-coding-record.md
printf '# 05 测试结果\nok: 1\n' > docs/changes/CHG-1071/05-test-results.md
printf 'chg\n#### 执行记录（ReAct）\n| 阶段 | Thought | Observation |\n|---|---|---|\n| 阶段1 | t | ok |\n' > docs/changes/CHG-1071/09-changelog.md
append_masters docs/changes/CHG-1071/09-changelog.md
printf '# 06.5 部署/配置/DB 记录\n未命中，不适用：无配置。\n' > docs/changes/CHG-1071/06.5-deployment-config.md
printf '# 06-delivery-summary\n## 遗留事项（FU 台账）\n| 编号 | 说明 | 负责人 | 期限 |\n|---|---|---|---|\n| FU-902 | 样例 | claude/s-1 | 2026-10-01 |\n' > docs/changes/CHG-1071/06-delivery-summary.md
stamp_all docs/changes/CHG-1071
printf '\n## TC 落点清单\n- TC-9001: tests/missing.test.js（类型：自动化）\n' >> docs/changes/CHG-1071/04-test-scripts.md
echo z > src/c.go
scripts/agent-gate --stage stop >/dev/null 2>&1
rc_e113=$?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
report "T55 TC-1256 E113 red: automated TC landing file missing" 2 "$rc_e113"
check_output "T55 TC-1256 refusal names GATE-E113 and the TC id" "GATE-E113.*TC-9001" "$out"
mkdir -p tests
printf 'it("works", () => expect(1).toBe(1));\n' > tests/ui-proto.test.js
sed -e 's#tests/missing.test.js#tests/ui-proto.test.js#' docs/changes/CHG-1071/04-test-scripts.md > .t55-04.tmp && mv .t55-04.tmp docs/changes/CHG-1071/04-test-scripts.md
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1255 E113 green: landing file exists with assertion marker" 0 $?
sed -e 's#（类型：自动化）#（类型：人工）#' docs/changes/CHG-1071/04-test-scripts.md > .t55-04.tmp && mv .t55-04.tmp docs/changes/CHG-1071/04-test-scripts.md
rm -f tests/ui-proto.test.js
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T55 TC-1256 人工-typed landing skips the file check" 0 $?
# ④ E111（REQ-1088）：基建冒烟门 fail-closed 三态 + check-smoke 探针
new_repo
seed_begin CHG-1072 L1 claude/s-1
printf 'smoke_placeholder: true\n' > pom.xml
git add pom.xml
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_e111a=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1251 E111 red: infra diff without a declared smoke command" 2 "$rc_e111a"
check_output "T55 TC-1251 refusal names GATE-E111 fail-closed" "GATE-E111" "$out"
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：login 200 ok @2026-10-14T00:00:00Z\n' > docs/changes/CHG-1072/05-test-results.md
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1250 E111 green: declared command + fresh evidence line" 0 $?
perl -ni -e 'print unless /冒烟证据/' docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_e111b=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1252 E111 red: declared command but no evidence" 2 "$rc_e111b"
check_output "T55 TC-1252 refusal asks for the evidence line" "冒烟证据" "$out"
printf '# 05 测试结果\n- **基建冒烟**：未命中，不适用（文档性配置，无运行面）\n' > docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1252 waiver declaration passes E111 with a warning" 0 $?
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: zzz\.nomatch\n' > .agent-governance.yml
printf '# 05 测试结果\n' > docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1252 smoke_paths override shrinks the trigger face" 0 $?
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
git add pom.xml .agent-governance.yml docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate check-smoke >/dev/null 2>&1
report "T55 TC-1257 check-smoke probe: violation exits 1" 1 $?
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-10-14T00:00:00Z\n' > docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate check-smoke >/dev/null 2>&1
report "T55 TC-1257 check-smoke probe: evidence present exits 0" 0 $?
# 证据窗时效（TC-1252 评审补强）：证据行在但 mtime 超窗 → 红
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-01-01T00:00:00Z\n' > docs/changes/CHG-1072/05-test-results.md
touch -t 202601010000 docs/changes/CHG-1072/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_stale=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1252 E111 red: evidence line present but stale beyond the window" 2 "$rc_stale"
check_output "T55 TC-1252 refusal names the evidence line requirement" "冒烟证据" "$out"
# win=0 = 存在级（P1-1 裁定：窗只管时效，行必须查）
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_evidence_max_age_h: 0\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1252 win=0 keeps presence-level enforcement (stale file still passes)" 0 $?
# pre-commit 运行级（TC-1257 评审补强）：SHIFT REMINDER 输出 + 不阻塞
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\n' > .agent-governance.yml
touch docs/changes/CHG-1072/05-test-results.md
printf '{"delivered_at":"%s","change":"CHG-1072","stage":"stop","session":""}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .agent-state/last-delivery.json
cp "$STAMP_SRC" scripts/stamp-provenance.sh
out=$(bash "$PAYLOAD_HOOKS/pre-commit" 2>&1 || true)
check_output "T55 TC-1257 pre-commit emits the SHIFT REMINDER" "SHIFT REMINDER" "$out"
pre_rc=0; bash "$PAYLOAD_HOOKS/pre-commit" >/dev/null 2>&1 || pre_rc=$?
# v3.91.7 (CHG-127): pre-commit stays warning-only, but `--stage shift` (called
# by pre-push) must hard-fail E112 without handoff and pass once it lands.
printf '{"started_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-started.json
shift_rc=0; AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage shift >/dev/null 2>&1 || shift_rc=$?
printf '# handoff\n' > docs/changes/CHG-1072/handoff.md
shift_ok=0; AGENT_GUARD_ALLOW_NO_SHIFT=0 scripts/agent-gate --stage shift >/dev/null 2>&1 || shift_ok=$?
report "T55 TC-1257 pre-commit reminder does not block (rc=0); shift gate red→green" 0 \
  "$([[ $pre_rc -eq 0 && $shift_rc -eq 2 && $shift_ok -eq 0 ]] && echo 0 || echo 1)"
# ④b CHG-093（v3.71.0 erratum，REQ-1093/1094）：E111 扫描面收敛活跃变更 + 非法 smoke_paths ERE 拦截
new_repo
seed_begin CHG-1080 L1 claude/s-1
mkdir -p docs/changes/CHG-1079
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-01-01T00:00:00Z\n- **基建冒烟**：未命中，不适用（历史变更裁定）\n' > docs/changes/CHG-1079/05-test-results.md
printf '# 05 测试结果\n' > docs/changes/CHG-1080/05-test-results.md
printf 'smoke_placeholder: true\n' > pom.xml
git add pom.xml
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_hist=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1259 E111 red: historical change 05 waiver line no longer passes" 2 "$rc_hist"
check_output "T55 TC-1259 refusal names GATE-E111" "GATE-E111" "$out"
# TC-1260：活跃变更 05 豁免行放行 + stderr 指明活跃变更路径
printf '# 05 测试结果\n- **基建冒烟**：未命中，不适用（本变更裁定，无运行面）\n' > docs/changes/CHG-1080/05-test-results.md
out=$(scripts/agent-gate --stage staged 2>&1 || true)
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1260 active-change 05 waiver line passes E111" 0 $?
check_output "T55 TC-1260 waiver stderr names the active-change 05 path" "CHG-1080/05-test-results\.md" "$out"
# TC-1261：win=0 下非活跃陈年证据行失效；活跃变更证据行放行
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_evidence_max_age_h: 0\n' > .agent-governance.yml
printf '# 05 测试结果\n' > docs/changes/CHG-1080/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_evid=$?
report "T55 TC-1261 E111 red: win=0 evidence line in a non-active change is void" 2 "$rc_evid"
printf '# 05 测试结果\n- **冒烟证据**：bash scripts/smoke.sh：ok @2026-01-01T00:00:00Z\n' > docs/changes/CHG-1080/05-test-results.md
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1261 win=0 evidence line in the active change passes" 0 $?
# TC-1262：指针缺失 fail-open（rc=0 + stderr 含 fail-open）
rm -f "$(git rev-parse --git-path agent-governance/active-change)"
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1262 missing active-change pointer fail-opens E111" 0 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T55 TC-1262 fail-open stderr explains the skip" "smoke gate fail-open" "$out"
printf 'CHG-1080\n' > "$(git rev-parse --git-path agent-governance/active-change)"
# TC-1263：smoke_paths 非法 ERE die + 报文含修复指引
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: pom\\.xml((\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
rc_ere=$?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
report "T55 TC-1263 E111 red: invalid smoke_paths ERE dies fail-closed" 2 "$rc_ere"
check_output "T55 TC-1263 refusal names GATE-E111 regex invalid" "GATE-E111.*regex invalid" "$out"
check_output "T55 TC-1263 refusal carries the smoke_paths repair guidance" "fix the comma-separated EREs" "$out"
# TC-1264：合法 ERE 覆写触发面行为不变（回归钉）
printf '# 05 测试结果\n' > docs/changes/CHG-1080/05-test-results.md
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: pom\\.xml\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1264 valid ERE override still trips E111 on the matched face" 2 $?
printf 'paths:\nsmoke_command: bash scripts/smoke.sh\nsmoke_paths: zzz\\.nomatch\n' > .agent-governance.yml
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1264 valid ERE override that misses keeps the gate green" 0 $?
# TC-1265：pre-commit 零触碰钉 + 行形权威派生面在位
report "T55 TC-1265 pre-commit consumes no ALLOW_NO_SHIFT env (FU-943 erratum pin)" 0 "$(grep -c 'ALLOW_NO_SHIFT' "$PAYLOAD_HOOKS/pre-commit")"
report "T55 TC-1265 gate header pins the CHG-093 erratum" 1 "$(cat "$GATE_SRC" "$(dirname "$GATE_SRC")/lib-gate-staged.sh" | grep -c '^# --- v3.71.0 (CHG-046, REQ-1088) + v3.71.0 erratum (CHG-093, REQ-1093/1094)')"
report "T55 TC-1265 governance yml pins the active-change scan face" 1 "$(grep -c '扫描面' "$PAYLOAD_YML")"
report "T55 TC-1265 playbook pins the narrowed scan face" 1 "$(grep -c '扫描面限活跃变更 05' "$PAYLOAD_DOCS/STAGE_PLAYBOOK.md")"
report "T55 TC-1265 DS anchor pins the narrowed scan face" 1 "$(grep -c '豁免/证据限活跃变更 05' "$STD_SRC")"
report "T55 TC-1265 registry pins pointer fail-open semantics" 1 "$(grep -c '指针缺失 fail-open' "$PAYLOAD_DOCS/CLAUSE_REGISTRY.md")"
# TC-1266（评审 P1-1 第 4 象限机钉）：指针缺失 × 未声明 smoke_command → 配置门仍拦（fail-open 仅豁免扫描面）
new_repo
seed_begin CHG-1081 L1 claude/s-1
printf 'smoke_placeholder: true\n' > pom.xml
git add pom.xml
rm -f "$(git rev-parse --git-path agent-governance/active-change)"
scripts/agent-gate --stage staged >/dev/null 2>&1
report "T55 TC-1266 E111 fail-closed: config gate survives a missing pointer" 2 $?
out=$(scripts/agent-gate --stage staged 2>&1 || true)
check_output "T55 TC-1266 stderr shows the bounded fail-open skip" "smoke gate fail-open" "$out"
# ⑤ 条款与模板在位（TC-1258，audit 同源口径）
report "T55 TC-1258 DS carries the four-gate row" 1 "$(grep -c '交付四门' "$STD_SRC")"
report "T55 TC-1258 DS carries the config-observability clause" 1 "$(grep -c '生效配置可观测' "$STD_SRC")"
report "T55 TC-1258 playbook carries the four-gate detail" 1 "$(grep -c '交付四门细则' "$PAYLOAD_DOCS/STAGE_PLAYBOOK.md")"
report "T55 TC-1258 playbook carries the no-parallel red line" 1 "$(grep -c '禁并行集成测试' "$PAYLOAD_DOCS/STAGE_PLAYBOOK.md")"
report "T55 TC-1258 AGENTS carries the no-parallel discipline" 1 "$(grep -c '禁并行集成测试' "$PAYLOAD_AGENTS")"
report "T55 TC-1258 pre-commit carries the reminder and pre-push the shift gate" 1 \
  "$([[ $(grep -c 'SHIFT REMINDER' "$PAYLOAD_HOOKS/pre-commit") -ge 1 && $(grep -c -- '--stage shift' "$PAYLOAD_HOOKS/pre-push") -ge 1 ]] && echo 1 || echo 0)"
report "T55 TC-1258 04 entry template carries the landing section" 1 "$(grep -c 'TC 落点清单' "$PAYLOAD_DOCS/templates/entry/04-test-scripts.md")"
report "T55 TC-1258 governance yml carries the smoke key" 1 "$(grep -c 'smoke_command:' "$PAYLOAD_YML")"
report "T55 TC-1258 registry indexes the four new codes" 4 "$(grep -cE 'GATE-E11[0-3] \|' "$PAYLOAD_DOCS/CLAUSE_REGISTRY.md")"
# ⑥ A42 通用性：四门 payload 面无来源项目特异 token（扫描面=评审 P0-1 扩至 8 文件）
a42_hit=0
for pf in resources/templates/agent-gate.sh resources/templates/pre-commit resources/STAGE_PLAYBOOK.md resources/templates/agent-governance.yml resources/templates/entry/04-test-scripts.md resources/DEVELOPMENT_STANDARDS.md resources/AGENTS.md resources/CLAUSE_REGISTRY.md; do
  grep -qE 'chg044|paper-proto|doctor01|fzzl_|ASR_UPSTREAM|dev\.sh && ' "$ROOT/$pf" && a42_hit=$(( a42_hit + 1 ))
done
report "T55 TC-1258 A42: no source-project tokens in the four-gate payload (8 files)" 0 "$a42_hit"
}

section_T56() {
  # TC-1267 + TC-1270 共仓：四类缺锚并存（DES 行/SC 行/覆盖维度行/00.5 确认标记）
  new_repo
  seed_artifacts CHG-1073 L1 claude/s-56
  grep -v 'DES-001' docs/changes/CHG-1073/03-modification-plan.md > .t56-03.tmp && mv .t56-03.tmp docs/changes/CHG-1073/03-modification-plan.md
  grep -v -e '覆盖维度' -e 'SC-001' docs/changes/CHG-1073/04-test-scripts.md > .t56-04.tmp && mv .t56-04.tmp docs/changes/CHG-1073/04-test-scripts.md
  printf '# 00.5\n## 深挖结论\nf\n## 影响范围\ns\n## 风险\nr\n## 候选方案与取舍\no\n## 测试思路\nt\n## 用户整体确认记录\n' > docs/changes/CHG-1073/00.5-communication.md
  t56_friction_before=$([[ -f .agent-state/gate-friction.tsv ]] && wc -l < .agent-state/gate-friction.tsv || echo 0)  # -f 守卫免 "No such file" stderr 噪声（TC-1275，CHG-095）
  t56_out=$(scripts/agent-gate preflight CHG-1073 2>&1); t56_rc=$?
  report "T56 TC-1267 preflight multi-anchor dir exits 1" 1 "$t56_rc"
  report "T56 TC-1267 collects GATE-E83 (empty confirmation)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E83')"
  report "T56 TC-1267 collects GATE-E07 (DES anchor)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E07')"
  report "T56 TC-1267 collects GATE-E09 (SC scenario)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E09')"
  report "T56 TC-1267 collects GATE-E11 (coverage dimension)" 1 "$(printf '%s\n' "$t56_out" | grep -c 'GATE-E11')"
  report "T56 TC-1267 single run reports ≥4 GATE lines" 0 "$([[ $(printf '%s\n' "$t56_out" | grep -c 'GATE-E') -ge 4 ]] && echo 0 || echo 1)"
  t56_friction_after=$([[ -f .agent-state/gate-friction.tsv ]] && wc -l < .agent-state/gate-friction.tsv || echo 0)  # -f 守卫免 "No such file" stderr 噪声（TC-1275，CHG-095）
  report "T56 TC-1270 friction ledger unchanged" 0 "$([[ "$t56_friction_after" == "$t56_friction_before" ]] && echo 0 || echo 1)"
  report "T56 TC-1270 active-change pointer not written" 0 "$([[ -e .git/agent-governance/active-change ]] && echo 1 || echo 0)"

  # TC-2388（CHG-142，REQ-1378）：delivery-phase 探针——stop 内容面缺口秒级同屏（collect-all）
  new_repo
  seed_artifacts CHG-1074 L1 claude/s-56
  printf '# spec\n- REQ-001: 演示页收口\n- **挂靠 UJ**：UJ-001\n- **origin_artifact**: 未命中（无原型页）\n- **chain_change**: 未命中（无数据链变更）\n- **ui_change**: true\n' > docs/changes/CHG-1074/01-spec.md
  printf '<!-- provenance\nauthor: fixture\nemail: fixture@test\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# 编码记录\ncr\n' > docs/changes/CHG-1074/04.5-coding-record.md
  printf '# 05 测试结果\n- **测试证据**：未命中，不适用（L0 轻量通道）\n' > docs/changes/CHG-1074/05-test-results.md
  printf 'chg\n#### 执行记录（ReAct）\n| Observation |\n|---|\n| t -> ok |\n' > docs/changes/CHG-1074/09-changelog.md
  append_masters docs/changes/CHG-1074/09-changelog.md
  stamp_all docs/changes/CHG-1074
  sedi 's/^- 专业质询三件：未命中（fixture 通用夹具，无沟通期新增面）/- 参照物指认：仅一锚点（TC-2388 负例）/' docs/changes/CHG-1074/00.5-communication.md
  t142_out=$(scripts/agent-gate preflight CHG-1074 2>&1); t142_rc=$?
  report "T56 TC-2388 preflight delivery-phase exits 1 (content-face gaps)" 1 "$t142_rc"
  report "T56 TC-2388 collects GATE-E157 (three-item anchors gap)" 1 "$(printf '%s\n' "$t142_out" | grep -c 'GATE-E157')"
  report "T56 TC-2388 collects GATE-E104 (runtime evidence gap)" 1 "$(printf '%s\n' "$t142_out" | grep -c 'GATE-E104')"
  report "T56 TC-2388 two content-face codes same screen" 0 "$([[ $(printf '%s\n' "$t142_out" | grep -cE 'GATE-E(157|104)') -ge 2 ]] && echo 0 || echo 1)"

  # TC-2389（REQ-1378 反例）：begin-era 干净夹具 → preflight rc0（探针不误报）
  new_repo
  seed_artifacts CHG-1075 L1 claude/s-56
  scripts/agent-gate begin CHG-1075 >/dev/null 2>&1
  t142b_out=$(scripts/agent-gate preflight CHG-1075 2>&1); t142b_rc=$?
  report "T56 TC-2389 preflight begin-era clean exits 0" 0 "$t142b_rc"
  report "T56 TC-2389 clean probe prints all-clean line" 1 "$(printf '%s\n' "$t142b_out" | grep -c 'all artifact gates clean')"
  # TC-1268: 干净夹具（seed_begin 全件）→ exit 0 + clean 行
  new_repo
  seed_begin CHG-1074 L1 claude/s-56
  scripts/agent-gate preflight CHG-1074 >/dev/null 2>&1
  report "T56 TC-1268 clean fixture exits 0" 0 $?
  t56_out=$(scripts/agent-gate preflight CHG-1074 2>&1)
  check_output "T56 TC-1268 clean run prints the all-clean line" "agent-gate: preflight: CHG-1074: all artifact gates clean" "$t56_out"
  # TC-1269: usage/bad-id → exit 2（不经 die 的探针参数面）
  scripts/agent-gate preflight >/dev/null 2>&1
  report "T56 TC-1269 no argument exits 2" 2 $?
  t56_out=$(scripts/agent-gate preflight 'CHG.094' 2>&1)
  report "T56 TC-1269 dotted id exits 2" 2 "$?"
  check_output "T56 TC-1269 bad id names the FU-023 shape" "valid change id" "$t56_out"
  # TC-1277（v3.72.0 erratum，CHG-095/DES-1870）：bypass env 不得泄漏进 preflight
  # 探针（p_run unset，探针确定性）；实现缺席时本组两断言红。
  new_repo
  seed_artifacts CHG-1075 L1 claude/s-56
  printf '# 00.5\n## 用户整体确认记录\n' > docs/changes/CHG-1075/00.5-communication.md
  t56_bypass_out=$(AGENT_GUARD_ALLOW_UNCONFIRMED=1 scripts/agent-gate preflight CHG-1075 2>&1); t56_bypass_rc=$?
  report "T56 TC-1277 bypass env does not relax preflight (rc stays 1)" 1 "$t56_bypass_rc"
  report "T56 TC-1277 preflight still collects GATE-E83 under bypass env" 1 "$(printf '%s\n' "$t56_bypass_out" | grep -c 'GATE-E83')"
  # TC-1278（N4 顺手项）：tpl usage 块 preflight 行存在钉
  report "T56 TC-1278 tpl usage block carries the preflight line" 1 "$(grep -c '^  scripts/agent-gate preflight <change-id>' "$ROOT/resources/templates/lib-gate-cold.sh")"
}

section_T57() {
  local t57_a t57_b t57_c t57_rc t57_had t57_redhad t57_tmp t57_dir t57_iso t57_red
  t57_tmp="${TMPDIR:-/tmp}"
  # TC-1272: -j 2 ≡ 串行（通过数/序/汇总行同形）
  t57_a=$(bash "$ROOT/tests/run-tests.sh" -T T41,T48 2>&1)
  t57_b=$(bash "$ROOT/tests/run-tests.sh" -T T41,T48 -j 2 2>&1)
  report "T57 TC-1272 -j2 keeps the serial pass count" "$(printf '%s\n' "$t57_a" | grep -c '^ok ')" "$(printf '%s\n' "$t57_b" | grep -c '^ok ')"
  report "T57 TC-1272 -j2 keeps the serial fail count" "$(printf '%s\n' "$t57_a" | grep -c '^FAIL ')" "$(printf '%s\n' "$t57_b" | grep -c '^FAIL ')"
  report "T57 TC-1272 -j2 replay keeps source order" "T41" "$(printf '%s\n' "$t57_b" | grep -m1 '^ok' | awk '{print $2}')"
  report "T57 TC-1272 -j2 keeps the summary shape" 1 "$(printf '%s\n' "$t57_b" | tail -2 | head -1 | grep -cE '^[0-9]+ passed, [0-9]+ failed$')"
  # TC-1273: 过滤 × 并行 → 收据不写（v3.86.0：隔离路径，不触真实台账）
  t57_dir=$(mktemp -d "${TMPDIR:-/tmp}/t57-state.XXXXXX")
  t57_iso="$t57_dir/last-suite-receipt.json"
  printf '{"head":"seed","passed":12345,"failed":0,"wall_time_s":0,"generated_at":"seed"}\n' > "$t57_iso"
  cp "$t57_iso" "$t57_dir/seeded"
  AGENT_GUARD_SUITE_RECEIPT_PATH="$t57_iso" bash "$ROOT/tests/run-tests.sh" -T T41,T48 -j 2 >/dev/null 2>&1; t57_rc=$?
  report "T57 TC-1273 filtered -j2 run exits clean" 0 "$t57_rc"
  report "T57 TC-1273 filtered -j2 run leaves receipt untouched" 0 "$(cmp -s "$t57_dir/seeded" "$t57_iso" && echo 0 || echo 1)"
  # TC-1276: FORCE_RED 缝 → rc 1 + 红归档含 FAIL 行 + 收据仍不被过滤跑触碰
  t57_red="$t57_dir/last-suite-red.txt"
  AGENT_GUARD_SUITE_RECEIPT_PATH="$t57_iso" AGENT_GUARD_SUITE_RED_PATH="$t57_red" AGENT_GUARD_SUITE_FORCE_RED=1 bash "$ROOT/tests/run-tests.sh" -T T41 >/dev/null 2>&1; t57_rc=$?
  report "T57 TC-1276 FORCE_RED run exits 1" 1 "$t57_rc"
  report "T57 TC-1276 red archive carries the forced FAIL line" 1 "$(grep -cF 'FAIL T0 forced-red seam (AGENT_GUARD_SUITE_FORCE_RED)' "$t57_red")"
  report "T57 TC-1276 FORCE_RED filtered run leaves receipt untouched" 0 "$(cmp -s "$t57_dir/seeded" "$t57_iso" && echo 0 || echo 1)"
  # TC-1274: 并行 T56 计数互证 + -j 1 逐字节等价串行（wall-time 行除外）
  t57_a=$(bash "$ROOT/tests/run-tests.sh" -T T56 2>"$t57_dir/t56.err")
  t57_b=$(bash "$ROOT/tests/run-tests.sh" -T T56 -j 2 2>&1)
  t57_c=$(bash "$ROOT/tests/run-tests.sh" -T T56 -j 1 2>/dev/null)
  report "T57 TC-1274 -j2 T56 pass count matches serial" "$(printf '%s\n' "$t57_a" | grep -c '^ok ')" "$(printf '%s\n' "$t57_b" | grep -c '^ok ')"
  # v3.91.2 (CHG-127 self-audit): `[done] T56 Ns` is a TIMING line (it varies by
  # ±2 s); comparing it byte-wise made this assertion flaky. Compare the verdict
  # face only.
  report "T57 TC-1274 -j1 is byte-equivalent to serial (modulo wall-time)" "$(printf '%s\n' "$t57_a" | grep -vE '^(\[done\]|wall-time: )')" "$(printf '%s\n' "$t57_c" | grep -vE '^(\[done\]|wall-time: )')"
  # TC-1275: 源层卫生钉（:3417 label 语义 + T56 friction -f 守卫 + stderr 无噪声）
  # TC-1275 钉用 -F + 引号拼接断开字面（T51 自匹配三连教训），只命中 T48 label 行
  report "T57 TC-1275 T48 label carries the superseded-row semantics" 1 "$(grep -h -cF 'v3.70.0 row exists (superseded by current '"top)" "$ROOT/tests/run-tests.sh" "$ROOT/tests/suites/"*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')"
  report "T57 TC-1275 T56 friction reads carry the -f guard" 2 "$(grep -h -cE '\[\[ -f \.agent-state/gate-friction\.tsv \]\] && wc -l < \.agent-state/gate-friction\.tsv' "$ROOT/tests/run-tests.sh" "$ROOT/tests/suites/"*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')"
  report "T57 TC-1275 T56 stderr carries no missing-file noise" 0 "$(grep -c 'No such file' "$t57_dir/t56.err" 2>/dev/null || true)"
  # 收据/红归档夹具清理（v3.86.0：全部落隔离目录，真实台账从未参与）
  rm -rf "$t57_dir"
  rm -f "$t57_tmp/t57-receipt.real" "$t57_tmp/t57-receipt.seeded" "$t57_tmp/t57-red.real"
  # TC-1279: helper 提升后的顺序无关性持久钉（T19 单跑须全绿；嵌套 ≈8s 可接受）
  # v3.91.2: T19 gained assertions, so the old hard-coded "9 passed" pin was stale
  # (the full suite had not run since). Assert "all green", not a frozen count.
  out=$(bash "$ROOT/tests/run-tests.sh" -T T19 2>&1 || true)
  report "T57 TC-1279 T19 standalone passes after hoisting (order-independence)" 1 "$(printf '%s\n' "$out" | grep -cE '^[0-9]+ passed, 0 failed$')"
  # TC-1280: CHG-500 续仓链（T5→T22a→T16）经 SERIAL_CHAIN 在 -j 下串行保续，须全绿
  # v3.96.0 (CHG-133, REQ-1333): attribute the inner failure first. T22a continues
  # T5's fixture (it never calls new_repo, so `-T T22a` alone is red by design),
  # hence the attribution baseline is the chain PREFIX T5+T22a. A red prefix means
  # the chain red has the SAME root cause — report it under its own name and do
  # not double-count it as T57's. Only a green prefix + red full chain is T57's.
  _t57_pre=$(bash "$ROOT/tests/run-tests.sh" -T T5,T22a 2>&1); _t57_pre_rc=$?
  report "T57 TC-1280 前置段 T5+T22a 健康（内层红非 T57 责任）" 0 "$_t57_pre_rc"
  if [[ "$_t57_pre_rc" -eq 0 ]]; then
    out=$(bash "$ROOT/tests/run-tests.sh" -T T5,T22a,T16 -j 2 2>&1 || true)
    report "T57 TC-1280 CHG-500 chain sections pass under -j (cwd continuity)" 0 "$(( $(printf '%s\n' "$out" | grep -cE '^FAIL ') > 0 || $(printf '%s\n' "$out" | grep -cE '^ok ') < 51 ? 1 : 0 ))"
  fi
}

section_T58() {
# ------------------------------------------------ T58 long-task wait + full-suite telemetry (v3.73.0)
new_repo
SESSION_GATE_SRC="$ROOT/resources/templates/session-gate.sh"
if [[ -f "$SESSION_GATE_SRC" ]]; then
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  # TC-1281 (REQ-1100/SC-001 positive): declared governance; sleep-head counted; yellow at threshold 2
  printf 'full_test_patterns: ^mvn test$\n' > .agent-governance.yml
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='sleep 900; grep -c FAIL x.log' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1281 sleep head counted once" '"sleep_polls":1' "$(cat .agent-state/session-tool-stats.json)"
  DEV_STDARDS_CMD_HEAD='sleep 900; grep -c FAIL x.log' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1281 sleep head counted twice" '"sleep_polls":2' "$(cat .agent-state/session-tool-stats.json)"
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1281 sleep yellow light on status" "YELLOW.*长任务等待" "$out"
  bash scripts/session-gate.sh count tool bash 'sleep 15' >/dev/null 2>&1
  check_output "T58 TC-1281 argv cmd-head counted" '"sleep_polls":3' "$(cat .agent-state/session-tool-stats.json)"
  printf '{"tool_name":"bash","tool_input":{"command":"sleep 5; ls"}}\n' | bash scripts/session-gate.sh count tool - >/dev/null 2>&1
  check_output "T58 TC-1281 stdin tool_input.command counted" '"sleep_polls":4' "$(cat .agent-state/session-tool-stats.json)"
  # TC-1282 (REQ-1100 negative): while-form exempt (first token); env override fires at 1
  DEV_STDARDS_CMD_HEAD='while ! grep -q DONE f; do sleep 30; done' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1282 while-form not counted" '"sleep_polls":4' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='sleep 60' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  out=$(bash scripts/session-gate.sh status 2>&1)
  if grep -q "长任务等待" <<< "$out"; then report "T58 TC-1282 default threshold stays silent at 1" 1 0; else report "T58 TC-1282 default threshold stays silent at 1" 0 0; fi
  out=$(AGENT_GUARD_SLEEP_POLL_LIMIT=1 bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1282 sleep-limit env override fires at 1" "YELLOW.*长任务等待" "$out"
  # TC-1283 (REQ-1102 declared): anchored ERE counts the exact full form; variants miss
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='mvn test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1283 anchored full pattern counted" '"full_suite":1' "$(cat .agent-state/session-tool-stats.json)"
  DEV_STDARDS_CMD_HEAD='mvn test -Dtest=X' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='mvn -q test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1283 flag/reordered variants not matched" '"full_suite":1' "$(cat .agent-state/session-tool-stats.json)"
  # TC-1284 (REQ-1102 negative): undeclared = off (fail-open); limit env override
  rm -f .agent-governance.yml
  bash scripts/session-gate.sh start >/dev/null 2>&1
  DEV_STDARDS_CMD_HEAD='mvn test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1284 undeclared pattern not counted" '"full_suite":0' "$(cat .agent-state/session-tool-stats.json)"
  printf 'full_test_patterns: ^mvn test$\n' > .agent-governance.yml
  DEV_STDARDS_CMD_HEAD='mvn test' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  out=$(AGENT_GUARD_FULL_TEST_LIMIT=1 bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1284 full-test limit env override fires at 1" "YELLOW.*全量回归" "$out"
  # TC-1286 (regression): legacy pre-CHG-096 stats JSON survives count (missing keys read 0) + status read
  printf '{"turns":3,"bash":1,"grep":0,"other":0,"total":1,"updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  DEV_STDARDS_CMD_HEAD='sleep 30' bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  check_output "T58 TC-1286 legacy stats JSON migrates on count (missing keys read 0)" '"sleep_polls":1,"full_suite":0' "$(cat .agent-state/session-tool-stats.json)"
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T58 TC-1286 status reads migrated stats" "session stats" "$out"
  rm -f .agent-governance.yml
else
  echo "SKIP T58: session-gate.sh absent — 跳过长任务等待/全量遥测 golden cases"
fi

}

section_T59() {
# --------------------------------- T59 发现处置闭环 + 评审轮次收敛（v3.74.0，CHG-098）
# TC↔REQ：TC-1307/1308/1309/1310/1311→REQ-1104；TC-1312/1313→REQ-1105；TC-1314/1317→REQ-1106。
# 夹具沿用 T53 的 L0 轻量通道形态（seed_t53_delivery = 已证绿的 stop 交付面）；07 一律
# 本行自写 provenance（在 seed_t53_delivery 之后覆写，避免出现两个 provenance 块）。
new_repo
# 本节负例矩阵会反复改写 07（每改一次即一轮），故先把阈值抬高；只有收敛用例用
# 行内 `AGENT_GUARD_REVIEW_ROUND_LIMIT=0` 覆写来触发 E116。
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99
seed_artifacts CHG-1090 L0 claude/s-1
cat > docs/changes/CHG-1090/01-spec.md <<'EOF'
# spec
- REQ-001: 发现处置与评审轮次闭环
- **origin_artifact**: 未命中（无原型页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: false
EOF
scripts/agent-gate begin CHG-1090 >/dev/null 2>&1
seed_t53_delivery CHG-1090
echo y > src/t59a.js
t59_07() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat; } > docs/changes/CHG-1090/07-review-report.md; }
# TC-1307（REQ-1104/SC-001 正面）：处置节齐备且严重行已处置 → 放行
t59_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 |
| F2 | 命名不一致 | 低 | 已驳回（误报） | 与 §1.3 命名表一致 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1307 stop green with a complete disposition table" 0 $?
# TC-1308（REQ-1104/SC-002 负面）：无「发现处置」节 → E115
t59_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1308 E115 red: disposition section missing" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T59 TC-1308 refusal names GATE-E115" "GATE-E115" "$out"
# TC-1309（负面）：严重行处置=待处置 → E114
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 待处置 | 尚未修复 |
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1309 E114 red: severe row left undisposed" 2 $?
out=$(scripts/agent-gate --stage stop 2>&1 || true)
check_output "T59 TC-1309 refusal names GATE-E114" "GATE-E114" "$out"
# TC-1310（负面）：安全性质发现处置=不处理 → E114（安全面须修复或显式驳回）
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 输入未做安全转义 | 低 | 不处理（登记 FU-99） | 待下批 |
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1310 E114 red: security finding shelved as 不处理" 2 $?
# TC-1311（边界，三值化）：表头/分隔行/列数不足行一律不判罚（不得假红）
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 已处置的真实行 | 低 | 已修复 | 已统一 |
| F2 | 列数不足的畸形行 | 严重 |
| 低 | 仅两列的畸形行 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1311 header/separator/short rows never fire a verdict" 0 $?
# TC-1311b（fail-closed）：只有占位/畸形行且无单行声明 → E115（畸形不得成为短路借口）
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| <编号> | <发现> | <严重度> | <处置> | <证据/理由> |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
out=$(scripts/agent-gate --stage stop 2>&1 || true)
report "T59 TC-1311b placeholder-only disposition section fails closed" 2 "$(scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
check_output "T59 TC-1311b refusal names GATE-E115" "GATE-E115" "$out"
# TC-1311c（放行）：单行声明等价于处置节（无发现时的轻量形态）
t59_07 <<'EOF'
# review
- **发现处置**：未命中，不适用（本夹具无发现）
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T59 TC-1311c single-line 未命中 declaration passes" 0 $?
# TC-1312a（REQ-1105 幂等）：同一 07 内容重复调用不增轮
t59_n=$(awk -F'\t' '$1=="CHG-1090" && $2!=""{c++} END{print c+0}' .agent-state/review-rounds.tsv 2>/dev/null)
scripts/agent-gate --stage stop >/dev/null 2>&1
t59_n2=$(awk -F'\t' '$1=="CHG-1090" && $2!=""{c++} END{print c+0}' .agent-state/review-rounds.tsv 2>/dev/null)
report "T59 TC-1312a ledger records at least one round" 1 "$([[ "${t59_n:-0}" -ge 1 ]] && echo 1 || echo 0)"
report "T59 TC-1312a unchanged 07 adds no round (idempotent)" "$t59_n" "$t59_n2"
# TC-1312b（REQ-1105 收敛）：超限且无「超限处置」行 → E116；补行后放行且亮黄灯
report "T59 TC-1312b E116 red: over the round cap without a 超限处置 line" 2 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
out=$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop 2>&1 || true)
check_output "T59 TC-1312b refusal names GATE-E116" "GATE-E116" "$out"
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 命名不一致 | 低 | 已修复 | 已统一 |
- **评审轮次**：4
- **超限处置**：回退重议——拆分为两批，先落门禁再做版本链
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
rc=0
out=$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop 2>&1) || rc=$?
report "T59 TC-1312b over-cap run passes once the 超限处置 line exists" 0 "$rc"
check_output "T59 TC-1312b over-cap run prints the YELLOW convergence notice" "YELLOW.*review rounds" "$out"
# TC-1312c（F3 回归）：模板派生的 07（占位行 + 注释态「超限处置」）不得短路 E116 / E115
t59_07_tpl() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n# CHG-1090 评审报告（L2）\n'; sed -n '2,$p' "$ROOT/resources/templates/entry/07-review-report.md"; printf -- '- 评审主体：platform / fixture-model / ses-t59tpl\n'; } > docs/changes/CHG-1090/07-review-report.md; }
t59_07_tpl
out=$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop 2>&1 || true)
report "T59 TC-1312c template-derived 07 still hits E116 over the cap" 2 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
check_output "T59 TC-1312c refusal names GATE-E116" "GATE-E116" "$out"
report "T59 TC-1312c template-derived 07 fails closed on the unfilled disposition table" 2 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=99 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
# TC-1313（兼容性/降级）：非法阈值回落 3（非 0）；`.agent-state` 整体缺位 → fail-open
t59_07 <<'EOF'
# review
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 命名不一致 | 低 | 已修复 | 已统一 |
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t59a
EOF
rm -f .agent-state/review-rounds.tsv
report "T59 TC-1313 invalid AGENT_GUARD_REVIEW_ROUND_LIMIT falls back to 3, not 0" 0 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=abc scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
rm -rf .agent-state
report "T59 TC-1313 absent .agent-state is fail-open (no counting, no E116)" 0 "$(AGENT_GUARD_REVIEW_ROUND_LIMIT=0 scripts/agent-gate --stage stop >/dev/null 2>&1; echo $?)"
# TC-1314（REQ-1106）：metrics 追加评审质效字段；无 07 的变更输出 0/null
seed_artifacts CHG-1091 L0 claude/s-1
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T59 TC-1314 metrics emits review-quality fields" \
  '"change_id":"CHG-1090".*"review_rounds":[0-9]+,"review_rounds_over_limit":(true|false),"findings_total":[0-9]+,"findings_dismissed":[0-9]+,"dismissal_rate":(null|[0-9]+\.[0-9]+)' "$out"
check_output "T59 TC-1314 metrics defaults to 0/null without a review report" \
  '"change_id":"CHG-1091".*"findings_total":0,"findings_dismissed":0,"dismissal_rate":null' "$out"
# TC-1317（CHG-098 评审 V2 回归）：模板派生的 07（仅占位行）不得被 metrics 计为发现——
# 处置计数必须与门禁裁决同源（占位/注释态行一律不计），否则空 07 会报出"最高噪声"。
t59_07_tpl
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T59 TC-1317 metrics ignores the template placeholder row" \
  '"change_id":"CHG-1090".*"findings_total":0,"findings_dismissed":0,"dismissal_rate":null' "$out"
}

section_T60() {
# ------------------------------- T60 评测资产派生 + 重打分 + 来源维 + 复盘汲取（v3.75.0，CHG-099）
# TC↔REQ：TC-1318/1319/1320/1321/1322→REQ-1108；TC-1323/1324/1325/1328/1333→REQ-1109；
# TC-1326/1327→REQ-1110；TC-1329/1330/1331/1332→REQ-1111；TC-1334→全量回归；TC-1335→安全面。
# 夹具纪律：new_repo 自带 scripts/agent-gate；本节自拷 eval-cases/eval-rescore，治理面一律用
# `--face` 指向自建 fixture 目录（不读本仓真实治理面，避免自指漂移与跨平台哈希耦合）。
CASES_SRC="$ROOT/resources/templates/eval-cases.sh"
[[ -f "$CASES_SRC" ]] || CASES_SRC="$ROOT/scripts/eval-cases"
SCORE_SRC="$ROOT/resources/templates/eval-rescore.sh"
[[ -f "$SCORE_SRC" ]] || SCORE_SRC="$ROOT/scripts/eval-rescore"
new_repo
cp "$CASES_SRC" scripts/eval-cases
cp "$SCORE_SRC" scripts/eval-rescore
chmod +x scripts/eval-cases scripts/eval-rescore
mkdir -p docs/bugs/BUG-002 docs/bugs/BUG-001 docs/bugs/BUG-20260101120000 docs/bugs/BATCH-20260102
# 手工缺陷（manual）：无「应捕获层」行 → 未声明；含敏感 canary 供 TC-1335 断言
cat > docs/bugs/BUG-001/01-diagnosis.md <<'EOF'
# 诊断
- **应捕获层**：测试
- **该层检查落点 / 补强**：tests/run-tests.sh T60（本次新增）
EOF
printf '# 矩阵\n| TC | 覆盖 |\n|---|---|\n| TC-1111 | 回归 |\n' > docs/bugs/BUG-001/04-matrix.md
cat > docs/bugs/BUG-002/01-diagnosis.md <<'EOF'
# 诊断
SECRET-CANARY-9f3
## 根因表
- R1 触发条件
EOF
printf '# 矩阵\n| TC | 覆盖 |\n|---|---|\n| 无 | — |\n' > docs/bugs/BUG-002/04-matrix.md
# 事故通道（incident）：id 形如 BUG-<UTC 时间戳>
cat > docs/bugs/BUG-20260101120000/01-diagnosis.md <<'EOF'
# 诊断
- **应捕获层**：门禁
- **该层检查落点 / 补强**：agent-gate E999（本次新增）
EOF
# 扁平批次（BATCH-* + `## BUG-*` 锚点）：自动回归锚点 + 事故锚点
cat > docs/bugs/BATCH-20260102/01-diagnosis.md <<'EOF'
# 批次诊断
## BUG-20260102000000 自动回归
- **复现记录（自动）**：fingerprint abc
- **应捕获层**：设计
## BUG-20260103000000 事故重入
- **应捕获层**：编码前置
EOF
cat > docs/bugs/BATCH-20260102/04-matrix.md <<'EOF'
# 批次矩阵
## BUG-20260102000000 自动回归
| TC | 覆盖 |
|---|---|
| TC-2222 | 回归 |
## BUG-20260103000000 事故重入
| TC | 覆盖 |
|---|---|
| 无 | — |
EOF
t60_tsv=.agent-state/eval-cases.tsv
rm -f "$t60_tsv"
scripts/eval-cases >/dev/null 2>&1
report "T60 TC-1318 derivation exits 0" 0 $?
report "T60 TC-1318 header + 5 derived cases" 6 "$(wc -l < "$t60_tsv" | tr -d ' ')"
t60_p1=$(printf '^EC-BUG-001\tmanual\tBUG-001\t测试\tdocs/bugs/BUG-001\tTC-1111$')
t60_p2=$(printf '^EC-BUG-002\tmanual\tBUG-002\t未声明\tdocs/bugs/BUG-002\t$')
t60_p3=$(printf '^EC-BUG-20260101120000\tincident\tBUG-20260101120000\t门禁\t')
t60_p4=$(printf '^EC-BUG-20260102000000\tregression\tBUG-20260102000000\t设计\t')
t60_p5=$(printf '^EC-BUG-20260103000000\tincident\tBUG-20260103000000\t编码前置\t')
check_output "T60 TC-1318 derived columns for the manual case" "$t60_p1" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 undeclared capture layer stays 未声明" "$t60_p2" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 incident channel derived from a timestamp id" "$t60_p3" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 regression channel derived from the auto marker" "$t60_p4" "$(cat "$t60_tsv")"
check_output "T60 TC-1322 flat-batch anchor derives its own case" "$t60_p5" "$(cat "$t60_tsv")"
report "T60 TC-1320 stable order: first derived case is the lowest id" 0 "$([[ "$(awk -F'\t' 'NR==2{print $1}' "$t60_tsv")" == "EC-BUG-001" ]] && echo 0 || echo 1)"
# v3.75.0 收尾整改（独立评审 F-7）：补齐 REQ-1108 的两条 A 层验收——原 TC-1318 断言的是
# "5 组 → 6 行"，**空缺陷面**与**派生视图禁止入库**两条从未被机校（用例声称与实际断言不一致）。
t60_cases="$PWD/scripts/eval-cases"
t60_empty=$(mktemp -d "${TMPDIR:-/tmp}/t60-empty.XXXXXX")
( cd "$t60_empty" && bash "$t60_cases" --out "$t60_empty/out.tsv" >/dev/null 2>&1; echo $? > "$t60_empty/rc" )
report "T60 TC-1318b empty defect face exits 0" 0 "$(cat "$t60_empty/rc")"
report "T60 TC-1318b empty defect face emits the header only" 1 "$(wc -l < "$t60_empty/out.tsv" | tr -d ' ')"
# 派生视图禁止入库：路径无跟踪文件 → `git ls-files --error-unmatch` 以 1 退出
report "T60 TC-1318c no docs/evals derived asset is tracked" 1 "$(git ls-files --error-unmatch docs/evals >/dev/null 2>&1; echo $?)"
# F-8：同一缺陷 id 以"嵌套目录 + 扁平锚点"两形态出现时，必须按 case_id 去重（覆盖比分母不重复计数）
t60_mix=$(mktemp -d "${TMPDIR:-/tmp}/t60-mix.XXXXXX")
mkdir -p "$t60_mix/docs/bugs/BATCH-A/BUG-900" "$t60_mix/docs/bugs/BATCH-B"
printf '# 诊断\n- **应捕获层**：测试\n' > "$t60_mix/docs/bugs/BATCH-A/BUG-900/01-diagnosis.md"
printf '# 矩阵\n| TC | 覆盖 |\n|---|---|\n| TC-9 | 回归 |\n' > "$t60_mix/docs/bugs/BATCH-A/BUG-900/04-matrix.md"
printf '# 批诊断\n## BUG-900 重复锚点\n- **应捕获层**：测试\n' > "$t60_mix/docs/bugs/BATCH-B/01-diagnosis.md"
( cd "$t60_mix" && bash "$t60_cases" --out "$t60_mix/out.tsv" >/dev/null 2>&1 )
report "T60 TC-1318d duplicate bug id collapses to one case_id" 2 "$(wc -l < "$t60_mix/out.tsv" | tr -d ' ')"
rm -rf "$t60_empty" "$t60_mix"
t60_sum1=$(cksum < "$t60_tsv")
scripts/eval-cases >/dev/null 2>&1
report "T60 TC-1319 re-derivation is byte-identical (idempotent)" 0 "$([[ "$t60_sum1" == "$(cksum < "$t60_tsv")" ]] && echo 0 || echo 1)"
out=$(scripts/eval-cases --verify 2>&1)
report "T60 TC-1321 verify green on a well-formed defect face" 0 $?
report "T60 TC-1321 verify is silent when green" 0 "$([[ -z "$out" ]] && echo 0 || echo 1)"
cp docs/bugs/BUG-002/01-diagnosis.md "${TMPDIR:-/tmp}/t60-diag.bak"
: > docs/bugs/BUG-002/01-diagnosis.md
out=$(scripts/eval-cases --verify 2>&1)
report "T60 TC-1321 verify red on an empty diagnosis artifact" 1 $?
check_output "T60 TC-1321 refusal names the empty artifact" "empty diagnosis artifact" "$out"
cp "${TMPDIR:-/tmp}/t60-diag.bak" docs/bugs/BUG-002/01-diagnosis.md
out=$(scripts/eval-cases --verify 2>&1)
report "T60 TC-1321 verify green again after repair" 0 $?
# TC-1323/1324/1325/1328（REQ-1109）：覆盖比口径、零 case 契约、确定性、只读
out=$(scripts/eval-rescore --dry-run 2>&1)
report "T60 TC-1323 rescore dry-run exits 0" 0 $?
check_output "T60 TC-1323 coverage ratio = 2/5 and no invented fields" '"cases_total":5,"covered":2,"missed":3,"score":0.4000' "$out"
printf 'case_id\tsource\tbug_id\tcaptured_layer\tlanding\tregression_ref\n' > t60-empty.tsv
out=$(scripts/eval-rescore --cases t60-empty.tsv --dry-run 2>&1)
report "T60 TC-1324 zero-case run exits 0" 0 $?
check_output "T60 TC-1324 zero cases yields a null score, not 0 or 1" '"cases_total":0,"covered":0,"missed":0,"score":null,"config_sha"' "$out"
check_output "T60 TC-1324 zero cases is not reported stale" '"baseline_present":false,"stale":false' "$out"
t60_d1=$(scripts/eval-rescore --dry-run 2>&1 | sed 's/"generated_at":"[^"]*"/"generated_at":"X"/')
t60_d2=$(scripts/eval-rescore --dry-run 2>&1 | sed 's/"generated_at":"[^"]*"/"generated_at":"X"/')
report "T60 TC-1325 rescore is deterministic apart from the timestamp" 0 "$([[ "$t60_d1" == "$t60_d2" && -n "$t60_d1" ]] && echo 0 || echo 1)"
rm -f .agent-state/eval-score-receipt.json .agent-state/eval-score-baseline.json
scripts/eval-rescore --dry-run >/dev/null 2>&1
report "T60 TC-1328 dry-run writes no receipt" 0 "$([[ ! -e .agent-state/eval-score-receipt.json ]] && echo 0 || echo 1)"
report "T60 TC-1328 dry-run writes no baseline" 0 "$([[ ! -e .agent-state/eval-score-baseline.json ]] && echo 0 || echo 1)"
# TC-1335（安全面）：派生视图与收据不得携带诊断正文里的敏感值
report "T60 TC-1335 derived view carries no diagnosis-body secret" 0 "$([[ "$(grep -c 'SECRET-CANARY-9f3' "$t60_tsv" || true)" == 0 ]] && echo 0 || echo 1)"
# TC-1326/1327（REQ-1110）：治理面内容哈希漂移 + 用例集成员漂移
mkdir -p face1/resources/templates
printf 'g1=v1\n' > face1/resources/templates/g1.sh
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" --update-baseline >/dev/null 2>&1
report "T60 TC-1326 baseline build exits 0" 0 $?
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" >/dev/null 2>&1
report "T60 TC-1326 unchanged governance face stays green" 0 $?
printf 'g1=v2\n' > face1/resources/templates/g1.sh
out=$(scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" 2>&1)
report "T60 TC-1326 governance-face change is stale (rc 1)" 1 $?
check_output "T60 TC-1326 stale receipt marks the drift" '"stale":true' "$(cat .agent-state/eval-score-receipt.json)"
check_output "T60 TC-1326 drift alert is surfaced" "STALE" "$out"
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" --update-baseline >/dev/null 2>&1
mkdir -p docs/bugs/BUG-003
printf '# 诊断\n- **应捕获层**：需求\n' > docs/bugs/BUG-003/01-diagnosis.md
scripts/eval-cases >/dev/null 2>&1
scripts/eval-rescore --cases "$t60_tsv" --face "$REPO/face1" >/dev/null 2>&1
report "T60 TC-1327 new eval member is stale (rc 1)" 1 $?
report "T60 TC-1335 receipt carries no diagnosis-body secret" 0 "$([[ "$(grep -c 'SECRET-CANARY-9f3' .agent-state/eval-score-receipt.json || true)" == 0 ]] && echo 0 || echo 1)"
# TC-1329/1330/1331/1332（REQ-1111）：07「来源」列与 metrics 字段
# 夹具切换：评测面用的 docs/bugs 夹具只服务派生测试（非六件套），在门禁面测试前移除，
# 避免把「缺陷组缺六件套」的无关红灯误记到本节的门禁断言上。
rm -rf docs/bugs
export AGENT_GUARD_REVIEW_ROUND_LIMIT=99
seed_artifacts CHG-1091 L0 claude/s-1
cat > docs/changes/CHG-1091/01-spec.md <<'EOF'
# spec
- REQ-001: 发现来源维闭环
- **origin_artifact**: 未命中（无原型页）
- **chain_change**: 未命中（无数据链变更）
- **ui_change**: false
EOF
scripts/agent-gate begin CHG-1091 >/dev/null 2>&1
seed_t53_delivery CHG-1091
echo y > src/t60a.js
t60_07() { { printf '<!-- provenance\nauthor: fixture\nemail: f@t\ngenerated_at: 2026-01-01T00:00:00Z\ngenerated_by: stamp-provenance.sh\n-->\n'; cat; } > docs/changes/CHG-1091/07-review-report.md; }
t60_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 | 本次引入 |
| F2 | 命名不一致 | 低 | 已驳回（误报） | 与 §1.3 命名表一致 | 既有存量 |
| F3 | 注释缺失 | 低 | 已修复 | 补齐注释 | 本次引入 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t60a
EOF
scripts/agent-gate --stage stop >/dev/null 2>&1
report "T60 TC-1329 stop green with a lawful provenance column" 0 $?
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T60 TC-1332 metrics counts introduced/pre-existing findings" '"findings_introduced":2,"findings_pre_existing":1' "$out"
t60_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 | 来源 |
|---|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 | 存量问题 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t60a
EOF
out=$(scripts/agent-gate --stage stop 2>&1)
report "T60 TC-1330 E117 red on an unlawful provenance value" 2 $?
check_output "T60 TC-1330 refusal names GATE-E117" "GATE-E117" "$out"
t60_07 <<'EOF'
# review
## 问题分级
- 严重：1 条（F1）
## 发现处置
| 编号 | 发现 | 严重度 | 处置 | 证据/理由 |
|---|---|---|---|---|
| F1 | 边界条件缺失 | 严重 | 已修复 | 补测并复跑全绿 |
- **评审轮次**：1
## 评审结论
通过
- 评审主体：platform / fixture-model / ses-t60a
EOF
out=$(scripts/agent-gate --stage stop 2>&1)
report "T60 TC-1331 legacy five-column table stays green (upgrade compat)" 0 $?
check_output "T60 TC-1331 legacy shape gets a soft notice" "缺「来源」列" "$out"
out=$(scripts/agent-gate metrics 2>/dev/null || true)
check_output "T60 TC-1332 legacy shape reports null provenance, not zero" '"findings_introduced":null,"findings_pre_existing":null' "$out"
# TC-1333（REQ-1109）：工作流模板形状（schedule + 调用本地脚本）
# v3.75.0 收尾整改（独立评审 F-14）：原断言只数 `schedule:` 关键词（注释里也有），改钉
# **锚定行**（`^\s+schedule:` + `^\s+cron:` 同现），注释掉/空格错位即红。
t60_wf="$ROOT/resources/templates/github-reviewer-rescore.yml"
t60_sched=$(grep -cE '^[[:space:]]+schedule:' "$t60_wf" || true)
t60_cron=$(grep -cE '^[[:space:]]+(-[[:space:]]+)?cron:' "$t60_wf" || true)
report "T60 TC-1333 rescore workflow declares an anchored schedule + cron" 1 "$([[ "$t60_sched" -ge 1 && "$t60_cron" -ge 1 ]] && echo 1 || echo 0)"
report "T60 TC-1333 rescore workflow calls scripts/eval-rescore" 0 "$([[ "$(grep -c 'scripts/eval-rescore' "$ROOT/resources/templates/github-reviewer-rescore.yml")" -ge 1 ]] && echo 0 || echo 1)"
}

section_T61() {
  local yml=".agent-governance.yml" out rc t61_bt t61_f
  new_repo
  t61_yml() { printf '%b' "$1" > "$yml"; git add -A >/dev/null 2>&1; git commit -qm yml >/dev/null 2>&1 || true; }
  t61_probe() { out=$(scripts/agent-gate verify-channel 2>&1); rc=$?; }

  # ---- TC-1338 / REQ-1115：旧型（双引号无转义）语义零回归 -------------------
  t61_yml 'ci:\n  verification_command: "bash tests/run-tests.sh"\n'
  t61_probe
  report "T61 TC-1338 legacy double-quoted yml still resolves (rc 0)" 0 "$rc"
  check_output "T61 TC-1338 legacy value is byte-identical" 'state=yml .*command=bash tests/run-tests\.sh$' "$out"

  # ---- TC-1337 / REQ-1115：方言矩阵（声明式超集） --------------------------
  t61_yml "ci:\n  verification_command: 'bash tests/run-tests.sh'\n"
  t61_probe
  check_output "T61 TC-1337 single-quoted scalar parses" 'command=bash tests/run-tests\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: bash tests/run-tests.sh\n'
  t61_probe
  check_output "T61 TC-1337 bare scalar parses" 'command=bash tests/run-tests\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: bash a.sh  # trailing comment\n'
  t61_probe
  check_output "T61 TC-1337 trailing comment is stripped" 'command=bash a\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: "bash -lc \\"echo hi\\""\n'
  t61_probe
  check_output "T61 TC-1337 escaped double quote decodes" 'command=bash -lc "echo hi"$' "$out"
  t61_yml 'ci:\n  verification_command: |\n    bash a.sh\n    bash b.sh\n'
  t61_probe
  check_output "T61 TC-1337 literal block keeps the first line" 'bash a\.sh' "$out"
  check_output "T61 TC-1337 literal block keeps the second line" 'bash b\.sh' "$out"
  t61_yml 'ci:\n  verification_command: >\n    bash a.sh\n    bash b.sh\n'
  t61_probe
  check_output "T61 TC-1337 folded block joins lines with a space" 'command=bash a\.sh bash b\.sh$' "$out"
  # F1（独立评审）：块标量**后面还有同级键/别的段**时，已收集的块不得被丢掉——
  # 本变更初版会在这种（最常见的）形态下静默判 absent，正是要消灭的事故形态。
  t61_yml 'ci:\n  verification_command: |\n    bash blk.sh\n  smoke_command: "x"\n'
  t61_probe
  check_output "T61 TC-1337 block scalar survives a following sibling key" 'command=bash blk\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: >\n    bash fol.sh\nstop_hook:\n  a: b\n'
  t61_probe
  check_output "T61 TC-1337 folded block survives a following section" 'command=bash fol\.sh$' "$out"
  t61_yml 'ci:\n  verification_command: |-\n    bash a.sh\n'
  t61_probe
  check_output "T61 TC-1337 chomping indicator is accepted" 'command=bash a\.sh$' "$out"
  t61_yml 'ci:\r\n  verification_command: "bash c.sh"\r\n'
  t61_probe
  check_output "T61 TC-1337 CRLF line endings parse" 'command=bash c\.sh$' "$out"

  # ---- TC-1339 / REQ-1116：unparsable → fail-closed（探针 rc 2）-------------
  t61_yml 'ci:\n  verification_command:\n'
  t61_probe
  report "T61 TC-1339 empty value is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339 empty value names the state" 'state=unparsable' "$out"
  t61_yml 'ci:\n  verification_command: ""\n'
  t61_probe
  report "T61 TC-1339 empty double quotes are unparsable (rc 2)" 2 "$rc"
  t61_yml 'ci:\n  verification_command: "bash a.sh\n'
  t61_probe
  report "T61 TC-1339 unterminated quote is unparsable (rc 2)" 2 "$rc"
  t61_yml 'ci:\n  verification_command: |x\n'
  t61_probe
  report "T61 TC-1339 illegal block indicator is unparsable (rc 2)" 2 "$rc"
  # F7：多行裸标量（合法 YAML，方言外）不得被静默截断成第一行
  t61_yml 'ci:\n  verification_command: bash a.sh\n    bash b.sh\n'
  t61_probe
  report "T61 TC-1339c multiline plain scalar is unparsable (rc 2)" 2 "$rc"
  # F6①：别的段（stop_hook）里的同名键不是通道
  t61_yml 'ci:\n  docs: ok\nstop_hook:\n  verification_command: "bash hook.sh"\n'
  t61_probe
  report "T61 TC-1339c a foreign-section key is unparsable (rc 2)" 2 "$rc"
  # F6②：更深的同名键（ci 子键之下）不是通道
  t61_yml 'ci:\n  sub:\n    verification_command: "bash nested.sh"\n'
  t61_probe
  report "T61 TC-1339c a deeper key is unparsable (rc 2)" 2 "$rc"
  # F6③ / 整改 R1：别的键的**块正文**里出现同名行 → fail-closed（不是配置，也不是
  # 静默 absent——yml 注释是方言声明唯一权威载体，已声明这类形态"一律 unparsable"）。
  t61_yml 'ci:\n  docs: |\n    verification_command: "bash ex.sh"\n'
  t61_probe
  report "T61 TC-1339c a block-body lookalike inside ci is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339c block-body lookalike names the misplaced state" 'state=unparsable' "$out"
  # R1②：顶层键的块正文（同一形态、另一位置）——同样 misplaced，不许"合法跳过"
  t61_yml 'docs: |\n  verification_command: "bash ex.sh"\n'
  t61_probe
  report "T61 TC-1339c a top-level block-body lookalike is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339c top-level block-body lookalike names the misplaced state" 'state=unparsable' "$out"
  # R1 反例（真键胜出，第 3 轮评审新发现 1）：兄弟键块正文含同名行不得污染真键
  t61_yml 'ci:\n  docs: |\n    verification_command: "bash ex.sh"\n  verification_command: "bash real.sh"\n'
  t61_probe
  report "T61 TC-1339c a real key beats a sibling block-body lookalike (rc 0)" 0 "$rc"
  check_output "T61 TC-1339c the real key's command wins over the lookalike" 'command=bash real.sh' "$out"
  # 第 3 轮评审新发现 4：行尾垃圾（引号后跟残余 token）是方言外形态，不得静默采值
  t61_yml 'ci:\n  verification_command: "bash a.sh" trailing\n'
  t61_probe
  report "T61 TC-1339c trailing garbage after a quoted value is unparsable (rc 2)" 2 "$rc"
  check_output "T61 TC-1339c trailing garbage names the state" 'state=unparsable' "$out"
  # 第 3 轮评审新发现 4：注释行里的同名键不得被误采（合法跳过，不是配置）
  t61_yml 'ci:\n  # verification_command: "bash x.sh"\n'
  t61_probe
  report "T61 TC-1339c a commented-out key is not the channel (rc 0)" 0 "$rc"
  check_output "T61 TC-1339c a commented-out key names the absent state" 'state=absent' "$out"

  # ---- TC-1340 / REQ-1116：合法跳过态（absent / placeholder）---------------
  rm -f "$yml"
  git add -A >/dev/null 2>&1; git commit -qm rmyml >/dev/null 2>&1 || true
  t61_probe
  report "T61 TC-1340 missing key is a lawful skip (rc 0)" 0 "$rc"
  check_output "T61 TC-1340 missing key names the absent state" 'state=absent' "$out"
  t61_yml 'ci:\n  verification_command: "<replace-with-project-test-command>"\n'
  t61_probe
  report "T61 TC-1340 install placeholder is a lawful skip (rc 0)" 0 "$rc"
  check_output "T61 TC-1340 install placeholder names the state" 'state=placeholder' "$out"
  # v3.76.0 整改（独立评审 F13）：顶层同名键**显式拒**（曾静默 absent，与旧 sed 的
  # "会执行"行为反向差异且无痕）——位置非法 = unparsable → GATE-E118。
  t61_yml 'verification_command: "bash toplevel.sh"\n'
  t61_probe
  report "T61 TC-1340 a top-level key is rejected, not silently absent (rc 2)" 2 "$rc"
  check_output "T61 TC-1340 misplaced key names the state" 'state=unparsable' "$out"

  # ---- TC-1341 / REQ-1119：anti-tamper × env 组合矩阵 ----------------------
  t61_yml 'ci:\n  verification_command: "bash committed.sh"\n'
  out=$(AGENT_GUARD_VERIFY_COMMAND='bash env.sh' scripts/agent-gate verify-channel 2>&1)
  check_output "T61 TC-1341 env wins over a clean yml" 'state=env source=env command=bash env\.sh' "$out"
  printf 'ci:\n  verification_command: "bash edited.sh"\n' > "$yml"
  t61_probe
  check_output "T61 TC-1341 pending yml blocks auto-execution (tampered)" 'state=tampered' "$out"
  out=$(AGENT_GUARD_VERIFY_COMMAND='bash env.sh' scripts/agent-gate verify-channel 2>&1)
  check_output "T61 TC-1341 pending yml + env is the lawful maintenance path" 'state=tampered\+env' "$out"

  # ---- TC-1342/1343 / REQ-1117/1118：stop 车道落状态文件 + 05 自检证据 ------
  new_repo
  seed_artifacts CHG-710 L0 claude/s-1
  scripts/agent-gate begin CHG-710 >/dev/null 2>&1
  seed_t53_delivery CHG-710
  cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  out=$(scripts/session-gate.sh status 2>&1 || true)
  check_output "T61 TC-1342 status says the channel is unrecorded before any stop" '验证通道：未记录' "$out"
  t61_yml 'ci:\n  verification_command: "printf ok > t61-probe.txt"\n'
  echo y > src/t61a.js
  out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1342 stop executes the yml channel command" 0 "$([[ -s t61-probe.txt ]] && echo 0 || echo 1)"
  report "T61 TC-1342 stop stays green when the channel passes" 0 "$rc"
  for t61_f in state source command exit_code reason env_fingerprint generated_at head; do
    grep -q "\"$t61_f\":" .agent-state/verify-channel.json
    report "T61 TC-1342 channel state file carries '$t61_f'" 0 $?
  done
  grep -q '"state":"yml"' .agent-state/verify-channel.json
  report "T61 TC-1342 channel state file records the yml source" 0 $?
  grep -q '通道自检证据' docs/changes/CHG-710/05-test-results.md
  report "T61 TC-1343 05 records the channel self-check evidence" 0 $?
  out=$(scripts/session-gate.sh status 2>&1 || true)
  check_output "T61 TC-1342 session-gate status shows the channel line" '- 验证通道：' "$out"

  # ---- TC-1343 / REQ-1118：未执行时 05 显式写「通道未验证」-----------------
  new_repo
  seed_artifacts CHG-711 L0 claude/s-1
  scripts/agent-gate begin CHG-711 >/dev/null 2>&1
  seed_t53_delivery CHG-711
  cp "$ROOT/resources/templates/session-gate.sh" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  echo y > src/t61b.js
  out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1343 stop without a channel still passes" 0 "$rc"
  grep -q '通道未验证（absent' docs/changes/CHG-711/05-test-results.md
  report "T61 TC-1343 05 records the explicit not-verified reason" 0 $?
  out=$(scripts/session-gate.sh status 2>&1 || true)
  check_output "T61 TC-1343 status surfaces the absent state, not a silent skip" '验证通道：absent' "$out"

  # ---- TC-1344 / REQ-1120：安装/升级写入 yml 提示通道暂停 ------------------
  t61_bt=$(mktemp -d "${TMPDIR:-/tmp}/t61-boot.XXXXXX")
  if [[ -f "$BOOT_SRC" ]]; then
    out=$(bash "$BOOT_SRC" --guard "$t61_bt" 2>&1 || true)
    check_output "T61 TC-1344 guard install warns the channel is paused" 'verification channel paused' "$out"
    out=$(bash "$BOOT_SRC" --guard --upgrade "$t61_bt" 2>&1 || true)
    report "T61 TC-1344 upgrade without a yml rewrite stays quiet" 0 "$(printf '%s' "$out" | grep -c 'verification channel paused')"
  else
    report "T61 TC-1344 bootstrap available (skill-repo layout only)" 0 "$([[ -f "$BOOT_SRC" ]] && echo 0 || echo 1)"
  fi
  rm -rf "$t61_bt"

  # ---- TC-1344b / REQ-1120（整改 F9）：提示口径必须与实际结果一致 -------------
  # 初版不分叉：本轮刚自动探测并把 `npm test` 写进 yml，却提示「paused：请声明
  # ci.verification_command」——与磁盘事实相反，维护者会以为通道还是断的。
  t61_bt2="${TMPDIR:-/tmp}/t61-boot-detect.$$"
  rm -rf "$t61_bt2"; mkdir -p "$t61_bt2"
  if [[ -f "$BOOT_SRC" ]]; then
    printf '{"name":"x","scripts":{"test":"exit 0"}}\n' > "$t61_bt2/package.json"
    # v3.91.2 (CHG-127 self-audit): P0-10 refuses to auto-wire a command that
    # runs nothing. The old fixture had package.json only, so the (correct)
    # "found no real test files" guard kept the placeholder and the stale
    # expectation failed. Give the fixture one real test file.
    mkdir -p "$t61_bt2/test" && printf '// real test\n' > "$t61_bt2/test/x.test.js"
    out=$(bash "$BOOT_SRC" --guard "$t61_bt2" 2>&1 || true)
    check_output "T61 TC-1344b auto-wired channel reports the detected command" 'verification channel updated by this run' "$out"
    check_output "T61 TC-1344b the detected command is named" 'verification_command = npm test' "$out"
    report "T61 TC-1344b auto-wired channel is not called paused" 0 "$(printf '%s' "$out" | grep -c 'verification channel paused')"
  else
    report "T61 TC-1344b bootstrap available (skill-repo layout only)" 0 "$([[ -f "$BOOT_SRC" ]] && echo 0 || echo 1)"
  fi
  rm -rf "$t61_bt2"

  # ---- TC-1346 / REQ-1122：红档语义=最近一次运行结果（绿跑清档）-----------
  grep -qF 'if [[ ${#WANTED[@]} -eq 0 && "$fail" -eq 0 && -n "$SUITE_HEAD" ]]; then' "$ROOT/tests/run-tests.sh"
  report "T61 TC-1346 green clear is gated on a FULL run" 0 $?
  grep -qF 'rm -f "$SUITE_RED_PATH"' "$ROOT/tests/run-tests.sh"
  report "T61 TC-1346 full green run deletes the stale red archive" 0 $?
  grep -qF "recent run's result" "$ROOT/tests/run-tests.sh"
  report "T61 TC-1346 archive semantics documented as the most recent run" 0 $?
  # 行为面（F16：结构性 pin 不等于行为验证）：强制红跑留档；**过滤**绿跑不清档
  # （清档只归"全量绿跑"这一条路径）。v3.86.0：归档落在隔离路径，不触真实台账。
  t61_dir=$(mktemp -d "${TMPDIR:-/tmp}/t61-state.XXXXXX")
  t61_ar="$t61_dir/last-suite-red.txt"
  AGENT_GUARD_SUITE_RED_PATH="$t61_ar" AGENT_GUARD_SUITE_FORCE_RED=1 bash "$ROOT/tests/run-tests.sh" -T T39 >/dev/null 2>&1
  report "T61 TC-1346 a forced-red filtered run leaves the archive" 1 "$([[ -f "$t61_ar" ]] && echo 1 || echo 0)"
  AGENT_GUARD_SUITE_RED_PATH="$t61_ar" bash "$ROOT/tests/run-tests.sh" -T T39 >/dev/null 2>&1
  report "T61 TC-1346 a filtered green run does NOT clear the archive" 1 "$([[ -f "$t61_ar" ]] && echo 1 || echo 0)"
  rm -rf "$t61_dir"

  # ---- TC-1339b / REQ-1116：unparsable 在 **stop 车道**也 fail-closed ----------
  # （F3/F16：初版只测了探针，正好漏掉"die 行在 bash 3.2 上因全角标点吞变量名而
  #  崩溃、GATE-E118 文案根本没打出来"这一类缺陷——现在真跑 stop 车道。）
  new_repo
  seed_artifacts CHG-712 L0 claude/s-1
  scripts/agent-gate begin CHG-712 >/dev/null 2>&1
  seed_t53_delivery CHG-712
  t61_yml 'ci:\n  verification_command: "bash never-closed\n'
  echo y > src/t61c.js
  out=$(scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1339b stop lane rejects an unparsable channel (rc 2)" 2 "$rc"
  check_output "T61 TC-1339b stop lane names GATE-E118" 'GATE-E118' "$out"
  check_output "T61 TC-1339b stop lane carries the repair example" '修复示例' "$out"
  report "T61 TC-1339b state file is written before the refusal" 0 "$(grep -c '\"state\":\"unparsable\"' .agent-state/verify-channel.json >/dev/null 2>&1 && echo 0 || echo 1)"

  # ---- TC-1341b / REQ-1119：SKIP_VERIFY 真跳过（既有存量缺口，当批闭环）-----
  new_repo
  seed_artifacts CHG-713 L0 claude/s-1
  scripts/agent-gate begin CHG-713 >/dev/null 2>&1
  seed_t53_delivery CHG-713
  echo y > src/t61d.js
  rm -f t61-skip.txt
  out=$(AGENT_GUARD_SKIP_VERIFY=1 AGENT_GUARD_VERIFY_COMMAND='printf ran > t61-skip.txt' scripts/agent-gate --stage stop 2>&1); rc=$?
  report "T61 TC-1341b SKIP_VERIFY does not execute an env channel" 0 "$([[ -e t61-skip.txt ]] && echo 1 || echo 0)"
  report "T61 TC-1341b SKIP_VERIFY keeps the stop lane green" 0 "$rc"
  report "T61 TC-1341b a skipped run leaves no channel state file behind" 0 "$([[ -e .agent-state/verify-channel.json ]] && echo 1 || echo 0)"

  # ---- TC-1343b / REQ-1118：证据行受控覆盖 + 不刷新 05 的 mtime ------------
  # （F5：行内含 UTC 时间戳 → 无界追加把 05 涨成噪声；F4：通道证据刷新 05 的
  #  mtime 会把 GATE-E111 冒烟时效窗静默降级为"存在性"。）
  new_repo
  seed_artifacts CHG-714 L0 claude/s-1
  scripts/agent-gate begin CHG-714 >/dev/null 2>&1
  seed_t53_delivery CHG-714
  t61_yml 'ci:\n  verification_command: "printf ok > t61-ev.txt"\n'
  echo y > src/t61e.js
  scripts/agent-gate --stage stop >/dev/null 2>&1
  touch -t 202001010000 docs/changes/CHG-714/05-test-results.md
  t61_m1=$(stat -c %Y docs/changes/CHG-714/05-test-results.md 2>/dev/null || stat -f %m docs/changes/CHG-714/05-test-results.md 2>/dev/null || echo 0)
  echo y2 > src/t61e2.js
  scripts/agent-gate --stage stop >/dev/null 2>&1
  t61_m2=$(stat -c %Y docs/changes/CHG-714/05-test-results.md 2>/dev/null || stat -f %m docs/changes/CHG-714/05-test-results.md 2>/dev/null || echo 0)
  report "T61 TC-1343b repeated stops keep exactly one evidence line" 1 "$(grep -c '通道自检证据' docs/changes/CHG-714/05-test-results.md)"
  report "T61 TC-1343b the evidence line does not refresh the 05 mtime" 0 "$([[ -n "$t61_m1" && "$t61_m1" == "$t61_m2" ]] && echo 0 || echo 1)"

  # ---- TC-1347 / REQ-1115/1117：两对镜像可解析（工具面零新依赖）-----------
  bash -n "$GATE_SRC" && bash -n "$ROOT/resources/templates/session-gate.sh"
  report "T61 TC-1347 gate + session-gate mirrors parse (bash -n)" 0 $?
}

section_T62() {
# --------------------------------- T62 edit/write 密度遥测（v3.77.0，CHG-101）
# TC↔REQ：TC-1110~1113（REQ-1127/SC-1101~1106）。夹具仿 T58（templates 副本直装）。
new_repo
SESSION_GATE_SRC="$ROOT/resources/templates/session-gate.sh"
if [[ -f "$SESSION_GATE_SRC" ]]; then
  cp "$SESSION_GATE_SRC" scripts/session-gate.sh
  chmod +x scripts/session-gate.sh
  # TC-1110 (SC-1101 positive): edit/write/MultiEdit 族计数；bash/grep 不计
  bash scripts/session-gate.sh start >/dev/null 2>&1
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  check_output "T62 TC-1349 edit counted" '"edits":1' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh count tool Write >/dev/null 2>&1
  bash scripts/session-gate.sh count tool multiedit >/dev/null 2>&1
  check_output "T62 TC-1349 write+MultiEdit counted (case-insensitive)" '"edits":3' "$(cat .agent-state/session-tool-stats.json)"
  bash scripts/session-gate.sh count tool bash >/dev/null 2>&1
  bash scripts/session-gate.sh count tool grep >/dev/null 2>&1
  check_output "T62 TC-1349 bash/grep not counted" '"edits":3' "$(cat .agent-state/session-tool-stats.json)"
  # TC-1111 (SC-1102 boundary): default threshold 40 silent below / fires at 40
  bash scripts/session-gate.sh start >/dev/null 2>&1
  for i in $(seq 1 39); do bash scripts/session-gate.sh count tool edit >/dev/null 2>&1; done
  out=$(bash scripts/session-gate.sh status 2>&1)
  if grep -q "调用批处理" <<< "$out"; then report "T62 TC-1350 below threshold stays silent at 39" 1 0; else report "T62 TC-1350 below threshold stays silent at 39" 0 0; fi
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  out=$(bash scripts/session-gate.sh status 2>&1)
  check_output "T62 TC-1350 yellow at threshold 40" "YELLOW.*调用批处理" "$out"
  # TC-1112 (SC-1103): env override fires at 1
  bash scripts/session-gate.sh start >/dev/null 2>&1
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  out=$(AGENT_GUARD_EDIT_LIMIT=1 bash scripts/session-gate.sh status 2>&1)
  check_output "T62 TC-1351 env override fires at 1" "YELLOW.*调用批处理" "$out"
  # TC-1113 (SC-1104): legacy stats JSON (no edits key) reads 0, no false yellow
  printf '{"turns":3,"bash":1,"grep":0,"other":0,"total":1,"updated_at":"2026-01-01T00:00:00Z"}\n' > .agent-state/session-tool-stats.json
  bash scripts/session-gate.sh count tool edit >/dev/null 2>&1
  check_output "T62 TC-1352 legacy schema migrates (edits reads 0 then 1)" '"edits":1' "$(cat .agent-state/session-tool-stats.json)"
  rm -f .agent-state/session-gate-last.md # stale report yellow lines would leak into status cat
  out=$(bash scripts/session-gate.sh status 2>&1)
  if grep -q "调用批处理" <<< "$out"; then report "T62 TC-1352 legacy schema no false yellow at 1" 1 0; else report "T62 TC-1352 legacy schema no false yellow at 1" 0 0; fi
  # SC-1105: reset writes initial edits key
  bash scripts/session-gate.sh start >/dev/null 2>&1
  check_output "T62 TC-1353 reset writes edits:0" '"edits":0' "$(cat .agent-state/session-tool-stats.json)"
  # SC-1106: emit wording + report file carries 09 registration line
  for i in $(seq 1 40); do bash scripts/session-gate.sh count tool write >/dev/null 2>&1; done
  out=$(bash scripts/session-gate.sh idle 2>&1 || true)
  check_output "T62 TC-1354 idle yellow wording" "YELLOW.*调用批处理" "$out"
  check_output "T62 TC-1354 report file carries 09 wording" "调用批处理.*登记 09" "$(cat .agent-state/session-gate-last.md 2>/dev/null || echo)"
  # mirror consistency (source vs template) — byte-identical OR single-source exec wrapper (ITEM-43)
  _t62_m_ok=0
  if [[ -f "$ROOT/scripts/session-gate.sh" ]]; then
    if cmp -s "$ROOT/scripts/session-gate.sh" "$SESSION_GATE_SRC"; then
      _t62_m_ok=0
    elif grep -qF '# single-source wrapper -> resources/templates/session-gate.sh' "$ROOT/scripts/session-gate.sh" && grep -qF 'exec bash' "$ROOT/scripts/session-gate.sh"; then
      _t62_m_ok=0
    else
      _t62_m_ok=2
    fi
  fi
  report "T62 TC-1355 session-gate source/template byte-identical" 0 "$_t62_m_ok"
else
  echo "SKIP T62: session-gate.sh absent — 跳过 edit/write 密度 golden cases"
fi

}

