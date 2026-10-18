#!/usr/bin/env bash
# eval-rescore — 评测集重打分（v3.75.0, CHG-099 / REQ-1109 / REQ-1110）
#
# 机制契约（唯一权威 = 本头注释）
#
# 口径（唯一，禁第二口径）：
#   score = covered / cases_total      覆盖比：已沉淀防回归用例的 case 占比
#   covered = 评测集中 regression_ref 非空的 case 数（引用存在性由 eval-cases 派生）
#   cases_total = 0  → score = null（禁臆造 0 或 1，§2.17.5 第 2 条）
#
# 结果绑定提交与漂移（N3）：
#   config_sha   = 治理面文件内容哈希（DS / CLAUSE_REGISTRY / AGENTS / SKILL / resources/templates/**）
#   member_cksum = 评测集 case_id 集合哈希
#   commit_sha   = 当前 HEAD（可追溯用；漂移判据用内容哈希，避免"整仓提交即假漂移"）
#   stale = (config_sha != 基线 config_sha) || (member_cksum != 基线 member_cksum)
#   语义边界：只覆盖「校验/评分证据」——不含人工审批/放行结论绑定提交。
#
# 参数：
#   --cases <path>        评测集（默认 <repo>/.agent-state/eval-cases.tsv）
#   --baseline <path>     基线（默认 <repo>/.agent-state/eval-score-baseline.json）
#   --receipt <path>      收据落点（默认 <repo>/.agent-state/eval-score-receipt.json）
#   --face <dir>          治理面根（默认仓库根；测试可指向 fixture）
#   --update-baseline     以本次结果重建基线
#   --dry-run             只计算与报告，零写盘
#   -h | --help
# 退出码：0 = 无漂移（或基线首次建立；**--dry-run 恒 0**——只报告不判定）；1 = 漂移（stale=true，告警语义，不阻断提交）；2 = usage/输入缺失
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'USAGE'
usage: eval-rescore [--cases <p>] [--baseline <p>] [--receipt <p>] [--face <dir>]
                    [--update-baseline] [--dry-run]

  --cases <path>      评测集 tsv（默认 <repo>/.agent-state/eval-cases.tsv）
  --baseline <path>   基线 json（默认 <repo>/.agent-state/eval-score-baseline.json）
  --receipt <path>    收据 json（默认 <repo>/.agent-state/eval-score-receipt.json）
  --face <dir>        治理面根（默认仓库根）
  --update-baseline   以本次结果重建基线
  --dry-run           零写盘
  -h, --help
USAGE
}

root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[[ -n "$root" ]] || root=$PWD

cases="$root/.agent-state/eval-cases.tsv"
baseline="$root/.agent-state/eval-score-baseline.json"
receipt="$root/.agent-state/eval-score-receipt.json"
face="$root"
dry=0
update=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cases|--baseline|--receipt|--face)
      key=$1; shift
      [[ $# -gt 0 ]] || { echo "eval-rescore: $key requires a value" >&2; exit 2; }
      case "$key" in
        --cases) cases=$1 ;;
        --baseline) baseline=$1 ;;
        --receipt) receipt=$1 ;;
        --face) face=$1 ;;
      esac ;;
    --update-baseline) update=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "eval-rescore: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[[ -s "$cases" ]] || { echo "eval-rescore: cases file not found or empty: $cases (run scripts/eval-cases first)" >&2; exit 2; }

cases_total=0
covered=0
members=""
while IFS=$'\t' read -r cid src bid layer landing ref; do
  [[ "$cid" = "case_id" ]] && continue
  [[ -n "$cid" ]] || continue
  cases_total=$((cases_total + 1))
  [[ -n "${ref:-}" ]] && covered=$((covered + 1))
  members="$members$cid"$'\n'
done < "$cases"

member_cksum=$(printf '%s' "$members" | cksum | awk '{print $1"-"$2}')

face_list=""
for p in resources/DEVELOPMENT_STANDARDS.md resources/CLAUSE_REGISTRY.md resources/AGENTS.md SKILL.md; do
  [[ -f "$face/$p" ]] && face_list="$face_list$face/$p"$'\n'
done
if [[ -d "$face/resources/templates" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && face_list="$face_list$f"$'\n'
  done < <(find "$face/resources/templates" -type f 2>/dev/null | sort)
fi
config_sha=$(printf '%s' "$face_list" | sed '/^$/d' | while IFS= read -r f; do cat "$f" 2>/dev/null || true; done | cksum | awk '{print $1"-"$2}')

commit_sha=$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)

if [[ "$cases_total" -eq 0 ]]; then
  score=null
else
  score=$(awk -v c="$covered" -v t="$cases_total" 'BEGIN { printf "%.4f", c / t }')
fi
missed=$((cases_total - covered))

baseline_present=false
stale=false
if [[ -s "$baseline" ]]; then
  baseline_present=true
  b_cfg=$(sed -n 's/.*"config_sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$baseline" | head -1)
  b_mem=$(sed -n 's/.*"member_cksum"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$baseline" | head -1)
  if [[ "$b_cfg" != "$config_sha" || "$b_mem" != "$member_cksum" ]]; then
    stale=true
  fi
fi

now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
line="{\"cases_total\":$cases_total,\"covered\":$covered,\"missed\":$missed,\"score\":$score,\"config_sha\":\"$config_sha\",\"member_cksum\":\"$member_cksum\",\"commit_sha\":\"$commit_sha\",\"baseline_present\":$baseline_present,\"stale\":$stale,\"generated_at\":\"$now\"}"

if [[ "$dry" = 1 ]]; then
  printf '%s\n' "$line"
elif [[ "$update" = 1 ]]; then
  mkdir -p "$(dirname "$baseline")"
  printf '%s\n' "{\"cases_total\":$cases_total,\"covered\":$covered,\"score\":$score,\"config_sha\":\"$config_sha\",\"member_cksum\":\"$member_cksum\",\"generated_at\":\"$now\"}" > "$baseline"
  mkdir -p "$(dirname "$receipt")"
  printf '%s\n' "$line" > "$receipt"
  printf 'eval-rescore: baseline rebuilt (config_sha=%s member_cksum=%s cases=%s score=%s)\n' "$config_sha" "$member_cksum" "$cases_total" "$score" >&2
else
  mkdir -p "$(dirname "$receipt")"
  printf '%s\n' "$line" > "$receipt"
  if [[ "$stale" = true ]]; then
    printf 'eval-rescore: STALE — baseline drift detected (receipt=%s); re-baseline with --update-baseline after reviewing the change\n' "$receipt" >&2
    exit 1
  fi
fi

exit 0
