#!/usr/bin/env bash
# new-change — 变更管线入口骨架生成器（v3.38.0，规范 §2.17.1 入口件派发）
#
# 用法：scripts/new-change <change-id> --risk L0|L1|L2|L3
#
# 语义：
#   - 专用目录形态：创建 <change_root>/<id>/ 并从 <docs>/templates/entry/ 复制
#     begin 必检七件骨架（__CHANGE_ID__/__RISK__ 占位符随装随替）。
#   - 批次形态（§1.1）：当日 BATCH-YYYYMMDD 已存在且风险为 L0/L1 时，默认把
#     骨架以 `## <id>` 锚点小节追加进共享文件（00-governance.json 追加一行）；
#     L2/L3 一律专用目录（批次拒收 L2/L3）。独立目录须 AGENT_GUARD_ALLOW_INDEPENDENT=1
#     并在 09「重要上下文」登记理由（与 gate begin 豁免同键）。
#   - 铁律：本脚本只生成骨架与登记，不生成产物正文（§2.17.1.2）；占位符
#     PENDING 会被 agent-gate begin 拒绝——执行主体必须显式填写后才能 begin。
#
# 零依赖：bash 3.2+；路径根遵循 AGENT_GUARD_DOCS_DIR / AGENT_GUARD_CHANGE_ROOT。
set -uo pipefail

die() { printf 'new-change: %s\n' "$1" >&2; exit 2; }

id="${1:-}"
[[ -n "$id" ]] || die "NC-E01: usage: scripts/new-change <change-id> --risk L0|L1|L2|L3"
shift || true
risk=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --risk)
      [[ $# -ge 2 && -n "${2:-}" ]] || die "NC-E02: --risk requires a value (L0|L1|L2|L3)"
      risk="$2"; shift 2 ;;
    *) die "NC-E03: unknown argument '$1'" ;;
  esac
done
[[ "$risk" =~ ^L[0-3]$ ]] || die "NC-E04: --risk L0|L1|L2|L3 required"
[[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "NC-E05: invalid change id '$id' (start with [A-Za-z0-9], then alnum/_/-; no dots)"

docs_dir="${AGENT_GUARD_DOCS_DIR:-docs}"
change_root="${AGENT_GUARD_CHANGE_ROOT:-$docs_dir/changes}"
tmpl_dir="${AGENT_GUARD_TEMPLATES_DIR:-$docs_dir/templates/entry}"
[[ -d "$tmpl_dir" ]] || die "NC-E06: entry templates not found at $tmpl_dir (run bootstrap --core/--guard first)"
[[ -d "$change_root" ]] || mkdir -p "$change_root"

fill() { # <src> -> stdout with placeholders replaced
  sed -e "s/__CHANGE_ID__/$id/g" -e "s/__RISK__/$risk/g" -e "s/__DATE__/$(date +%Y-%m-%d)/g" "$1"
}

entry_docs=(00-intent.md 00-governance.json 01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md)

today=$(date +%Y%m%d)
batch="$change_root/BATCH-$today"
use_batch=0
if [[ -d "$batch" ]]; then
  case "$risk" in
    L0|L1)
      if [[ "${AGENT_GUARD_ALLOW_INDEPENDENT:-}" == "1" ]]; then
        echo "new-change: AGENT_GUARD_ALLOW_INDEPENDENT=1 — dedicated dir; record the justification in 09「重要上下文」(standards §1.1)"
      else
        use_batch=1
      fi
      ;;
    *) echo "new-change: L2/L3 never join a batch (standards §1.1) — dedicated dir" ;;
  esac
fi

if [[ "$use_batch" == 1 ]]; then
  grep -qE "^##[[:space:]]+$id([[:space:]]|$)" "$batch/00-intent.md" 2>/dev/null \
    && die "NC-E07: change $id already has a section in $batch — open a new change id"
  for doc in "${entry_docs[@]}"; do
    if [[ ! -e "$batch/$doc" ]]; then
      if [[ "$doc" == 00-governance.json ]]; then
        # JSON 件无 markdown 头：读取器按行解析 JSON 对象，夹注释行即坏（fail-closed）
        fill "$tmpl_dir/$doc" > "$batch/$doc"
      else
        { printf '# BATCH-%s %s\n\n## %s\n\n' "$today" "$doc" "$id"; fill "$tmpl_dir/$doc"; } > "$batch/$doc"
      fi
    elif [[ "$doc" == 00-governance.json ]]; then
      fill "$tmpl_dir/$doc" >> "$batch/$doc"
    else
      { printf '\n## %s\n\n' "$id"; fill "$tmpl_dir/$doc"; } >> "$batch/$doc"
    fi
  done
  echo "new-change: batch-joined $batch (## $id sections appended)"
  d="$batch"
else
  d="$change_root/$id"
  [[ -e "$d" ]] && die "NC-E08: $d already exists — open a new change id (standards §2.15 rule 4)"
  mkdir -p "$d"
  for doc in "${entry_docs[@]}"; do
    fill "$tmpl_dir/$doc" > "$d/$doc"
  done
  echo "new-change: scaffolded $d"
fi

cat <<'EOF'
next steps (gate begin refuses skeletons until they are filled):
  1. fill 00-intent.md (问题/预期结果/开放问题) and pick real owners in
     00-governance.json — PENDING placeholders are rejected by begin;
  2. fill 01-spec REQ- / 02 三维 / 03 DES-+选型 / 03.5 依赖+里程碑 / 04 TC-+SC-;
  3. run: scripts/agent-gate begin <change-id>
EOF
