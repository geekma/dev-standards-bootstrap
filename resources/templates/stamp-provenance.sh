#!/usr/bin/env bash
# stamp-provenance.sh — 把「谁、在哪台机器、什么时候」写进变更/缺陷产物（v3.17.0）
#
# 解决的问题：`00-governance.json` 里的 implementation_owner 是**人/模型手写**的
# 字符串，写什么就是什么——回溯时无法区分"真跑过"与"顺手编的"。本脚本把溯源
# 信息**从运行环境里读出来**（git 配置与提交者、主机名、平台、UTC 时间），
# 手写改不出这些真值。
#
# 用法：
#   scripts/stamp-provenance.sh <CHG-id> [file ...]   # 就地写入（默认 04.5-coding-record.md）
#   scripts/stamp-provenance.sh --all <CHG-id>        # 全量盖章：活跃变更目录下全部 *.md（v3.22.0）
#   scripts/stamp-provenance.sh --trace <CHG-id>      # 从 01.5 矩阵派生 09 §4 追踪矩阵块（v3.42.0）
#   scripts/stamp-provenance.sh --bug <BUG-id>        # 缺陷六件套盖章：docs/bugs/<id>/*.md（v3.28.0）
#   scripts/stamp-provenance.sh --print <CHG-id>      # 只打印块，不写文件
#   scripts/stamp-provenance.sh --check <file>        # 校验已有块（CI 用，形状 + 非占位）
#
# --all 把溯源块盖到解析后变更目录的**每一个 *.md**（15 件产物批量可溯；幂等整块
# 替换，重复运行不叠加）。`00-governance.json` **刻意不盖**——JSON 里注入 HTML 注释
# 会破坏机器读取（门禁/审计按扁平 JSON 切分记录）。强制范围（v3.26.0，CHG-026）＝全部 *.md：
# v3.26.0（CHG-026）：--all 升为交付必跑——变更目录全部 *.md 产物均须携带溯源块，
# gate stop/CI 逐一校验；00-governance.json 刻意豁免（HTML 注释破坏扁平 JSON 读取）。
#
# 写入位置：文件首个 H1（`# ` 开头）之后；已有块则**整块替换**（幂等，可重复跑）。
#
# 隐私开关：.agent-governance.yml 的 `provenance.include_email: false` →
#   email 写为 <redacted>（作者、提交者、主机信息保留）。默认 true。
#
# 零依赖：bash 3.2+、sed、awk、grep；git / hostname / uname / date 缺失时降级为
#   显式 unknown，不猜、不编。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || echo "")
GOV_YML="$ROOT/.agent-governance.yml"

# 与 agent-gate 同源的路径解析（只读两个键，够用即止）
cfg_path() { # key default
  local k="$1" d="$2" v=""
  if [[ -f "$GOV_YML" ]]; then
    v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" "$GOV_YML" 2>/dev/null \
        | head -n 1 | tr -d "[:space:]\"'" || true)
  fi
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}
DOCS_DIR="${AGENT_GUARD_DOCS_DIR:-$(cfg_path docs docs)}"
CHANGE_ROOT="${AGENT_GUARD_CHANGE_ROOT:-$(cfg_path change_root "$DOCS_DIR/changes")}"
BUGS_ROOT="${AGENT_GUARD_BUGS_ROOT:-$(cfg_path bugs_root "$DOCS_DIR/bugs")}"
INCLUDE_EMAIL="${AGENT_GUARD_PROVENANCE_EMAIL:-$(cfg_path include_email true)}"

usage() {
  cat <<'EOF'
Usage: scripts/stamp-provenance.sh <CHG-id> [file ...]
        scripts/stamp-provenance.sh --all <CHG-id>
        scripts/stamp-provenance.sh --trace <CHG-id>
        scripts/stamp-provenance.sh --bug <BUG-id>
       scripts/stamp-provenance.sh --print <CHG-id>
       scripts/stamp-provenance.sh --check <file>

Writes a provenance block (author / committer / host / platform / UTC time),
read from the environment — never hand-written. Idempotent: an existing block is
replaced wholesale, so re-running is safe.

Default target: <change_root>/<CHG-id>/04.5-coding-record.md
--all:          stamp every *.md artifact of the resolved change directory
                (batch-aware; 00-governance.json is deliberately NOT stamped —
                an HTML comment inside JSON would break the machine readers).
--bug <BUG-id>: stamp every *.md of the defect doc group <bugs_root>/<BUG-id>/
                (v3.28.0 — the six-piece set carries the same who/host/when
                header; the block labels the group with `bug:` instead of
                `change:` and `risk:` is `n/a`).
Privacy: set `provenance.include_email: false` in .agent-governance.yml to write
         email as <redacted>.
EOF
}

mode=write
stamp_all=false
stamp_trace=false
stamp_bug=false
bug_id=""
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --print)   mode=print; shift ;;
  --check)   mode=check; shift ;;
  --all)     stamp_all=true; shift ;;
  --trace)   stamp_trace=true; shift ;;
  --bug)     stamp_bug=true; bug_id="${2:-}"; shift 2 ;;
  "")        usage >&2; exit 2 ;;
esac

if [[ "$mode" == check ]]; then
  f="${1:-}"
  [[ -n "$f" ]] || { usage >&2; exit 2; }
  [[ -f "$f" ]] || { echo "stamp-provenance: no such file: $f" >&2; exit 2; }
  blk=$(sed -n '/^<!-- provenance$/,/^-->$/p' "$f" 2>/dev/null || true)
  if [[ -z "$blk" ]]; then
    echo "stamp-provenance: $f has no provenance block" >&2
    exit 1
  fi
  bad=0
  for k in author email generated_at generated_by; do
    printf '%s\n' "$blk" | grep -qE "^${k}:[[:space:]]*[^[:space:]]" || {
      echo "stamp-provenance: $f provenance block is missing '$k'" >&2; bad=1; }
  done
  printf '%s\n' "$blk" | grep -qE '^generated_at:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' || {
    echo "stamp-provenance: $f provenance 'generated_at' is not an ISO-8601 date" >&2; bad=1; }
  printf '%s\n' "$blk" | grep -qE '^generated_by:[[:space:]]*stamp-provenance\.sh' || {
    echo "stamp-provenance: $f provenance block was not produced by this script" >&2; bad=1; }
  norm=$(printf '%s' "$blk" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
  case "$norm" in
    *PENDING*|*TODO*|*TBD*|*待定*) echo "stamp-provenance: $f provenance block still holds a placeholder" >&2; bad=1 ;;
  esac
  [[ "$bad" -eq 0 ]] || exit 1
  echo "stamp-provenance: $f provenance block OK"
  exit 0
fi

if [[ "$stamp_bug" == true ]]; then
  # v3.28.0 --bug：缺陷六件套组。目录就是 <bugs_root>/<id>，无批次、无 governance。
  chg="$bug_id"
  [[ -n "$chg" ]] || { usage >&2; exit 2; }
  [[ "$chg" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "stamp-provenance: invalid defect id '$chg'" >&2; exit 2; }
else
  chg="${1:-}"
  [[ -n "$chg" ]] || { usage >&2; exit 2; }
  [[ "$chg" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "stamp-provenance: invalid change id '$chg'" >&2; exit 2; }
  shift
  # --all 与显式文件清单互斥：组合会把优先级问题留给读者（显式清单生效、--all 静默
  # 丢失）——拒绝组合，让语义只有一种。
  if [[ "$stamp_all" == true && "$#" -gt 0 ]]; then
    echo "stamp-provenance: --all cannot be combined with an explicit file list" >&2
    exit 2
  fi
  if [[ "$stamp_trace" == true && "$#" -gt 0 ]]; then
    echo "stamp-provenance: --trace cannot be combined with an explicit file list" >&2
    exit 2
  fi
fi

# Batch-aware resolution (v3.18.0): a same-day L0/L1 batch keeps its artifacts in
# BATCH-YYYYMMDD/, addressed by `## <change-id>` anchors. Resolve the directory
# the same way the gate does, so the remedy the gate prints
# (`scripts/stamp-provenance.sh <CHG-id>`) keeps working for batch members.
# ANCHOR PIN (v3.58.0, REQ-1008): the `## <id>` anchor regex below is a
# deliberate single-line copy of the gate's anchor_re() shape
# (`^##[[:space:]]+<id>([[:space:]]|$)`; agent-gate.sh keeps the canonical
# def). Keep them byte-identical — changing one without the other desyncs
# gate validation from stamping (single-file zero-dep policy blocks an
# import; review B-F6 accepted the copy with this pin).
resolve_dir() { # <change-id> -> directory
  # NOTE (bash 3.2): `local` expands every word BEFORE assigning any of them, so
  # a second assignment may not reference the first. Keep declarations split.
  local id="$1"
  local d="$CHANGE_ROOT/$id" b
  [[ -d "$d" ]] && { printf '%s' "$d"; return 0; }
  if [[ -n "${AGENT_GUARD_CHANGE_DIR:-}" && -d "${AGENT_GUARD_CHANGE_DIR:-}" ]]; then
    printf '%s' "$AGENT_GUARD_CHANGE_DIR"; return 0
  fi
  for b in "$CHANGE_ROOT"/BATCH-*/; do
    [[ -d "$b" ]] || continue
    if grep -qE "^##[[:space:]]+${id}([[:space:]]|\$)" "$b"/*.md 2>/dev/null; then
      printf '%s' "${b%/}"; return 0
    fi
  done
  printf '%s' "$d"
}

# v3.42.0 (REQ-955): derive the 09 §4 traceability block from the 01.5 matrix —
# single-source (§1.2): REQ/DES/TC ids are copied from the matrix, never
# hand-typed again. Fail-open: any missing input skips with a loud stderr line
# and exit 0 (derivation is an optimization; G5/gate 4 remain the enforcement).
derive_trace_block() { # <chg-id> <chg-dir>
  local id="$1" dir="$2" nine="$2/09-changelog.md"
  [[ -f "$nine" ]] || { echo "stamp-provenance: trace skip (no 09-changelog.md in $dir)" >&2; return 0; }
  local blk; blk=$(mktemp)
  # this change's own section (batch-aware; same anchor shape as the gate/audit)
  awk -v id="$id" '
    $0 ~ ("^##[[:space:]]+" id "([[:space:]]|$)") { on=1; print; next }
    on && /^##[[:space:]]/ { exit }
    on { print }
  ' "$nine" > "$blk"
  grep -q "^#### 追踪矩阵映射" "$blk" \
    || { echo "stamp-provenance: trace skip (no §4 traceability heading in CHG section)" >&2; rm -f "$blk"; return 0; }
  # matrix resolution (gate 门禁 4 double-placement protocol, §2.17):
  # 1) an explicit path mentioned in the section, 2) depth-1 scan of both roots.
  local matrix="" cand m found=""
  # path-char class only (letters/digits/._/): CJK prose like `完整矩阵：` must
  # not glue onto the candidate path (would make "$ROOT/$cand" nonexistent and
  # silently fall through to the scan — masked by single-matrix fixtures).
  cand=$(grep -oE '[A-Za-z0-9._/-]*01\.5-rtvm-matrix\.md' "$blk" | head -1 || true)
  if [[ -n "$cand" && -f "$ROOT/$cand" ]]; then matrix="$ROOT/$cand"; fi
  if [[ -z "$matrix" ]]; then
    for m in "$DOCS_DIR"/*/01.5-rtvm-matrix.md "$CHANGE_ROOT"/*/01.5-rtvm-matrix.md; do
      [[ -f "$m" ]] || continue
      if [[ -n "$found" ]]; then
        echo "stamp-provenance: trace skip (multiple 01.5 matrices found — ambiguous)" >&2
        rm -f "$blk"; return 0
      fi
      found="$m"
    done
    matrix="$found"
  fi
  [[ -n "$matrix" ]] || { echo "stamp-provenance: trace skip (no 01.5-rtvm-matrix.md found)" >&2; rm -f "$blk"; return 0; }
  local reqs dess tcs
  # F1 (review): `|| true` guards — grep exits 1 on zero matches; with
  # `set -euo pipefail` a bare pipeline would kill the script mid-derivation
  # (the REQ-empty / DES-empty / TC-empty fail-open branches were dead code,
  # and --all would abort after stamping). Empty set → the loud SKIP below.
  reqs=$(grep -oE 'REQ-[0-9]+' "$matrix" | sort -u | tr '\n' ' ' | sed 's/ $//' || true)
  [[ -n "$reqs" ]] || { echo "stamp-provenance: trace skip (01.5 matrix has no REQ rows)" >&2; rm -f "$blk"; return 0; }
  dess=$(grep -oE 'DES-[0-9]+' "$matrix" | sort -u | tr '\n' ' ' | sed 's/ $//' || true)
  tcs=$(grep -oE 'TC-[0-9]+' "$matrix" | sort -u | tr '\n' ' ' | sed 's/ $//' || true)
  join_bt() { printf '%s' "$1" | tr ' ' '\n' | sed '/^$/d' | awk '{printf "%s`%s`", sep, $0; sep="、"}'; }
  local req_l des_l tc_l
  req_l="- 对应需求（派生）：$(join_bt "$reqs")"
  if [[ -n "$dess" ]]; then des_l="- 对应设计（派生）：$(join_bt "$dess")"; else des_l="- 对应设计（派生）：—（01.5 未含 DES 编号）"; fi
  if [[ -n "$tcs" ]]; then tc_l="- 对应测试（派生）：$(join_bt "$tcs")"; else tc_l="- 对应测试（派生）：—（01.5 未含 TC 编号）"; fi
  local tb; tb=$(mktemp)
  {
    echo "<!-- trace-derive begin (stamp-provenance.sh v3.42.0; 派生自 01.5-rtvm-matrix.md，勿手改) -->"
    printf '%s\n' "$req_l" "$des_l" "$tc_l"
    echo "<!-- trace-derive end -->"
  } > "$tb"
  # idempotent rewrite (F2, review): ONE awk pass — marker deletion is scoped
  # to THIS change's section (a shared batch 09 must never have a sibling's
  # delivered trace block swept), then the fresh block is inserted after the
  # §4 heading of this section only.
  local tmp; tmp=$(mktemp)
  awk -v bf="$tb" -v id="$id" '
    $0 ~ ("^##[[:space:]]+" id "([[:space:]]|$)") { on=1; print; next }
    on && /^##[[:space:]]/ { on=0 }
    on && /^<!-- trace-derive begin/ { del=1; next }
    on && /^<!-- trace-derive end/ { del=0; next }
    del { next }
    { print }
    on && !done && /^#### 追踪矩阵映射/ {
      while ((getline l < bf) > 0) print l
      close(bf); done=1
    }
  ' "$nine" > "$tmp" && mv "$tmp" "$nine"
  rm -f "$blk" "$tb"
  echo "trace-derive  $nine"
  return 0
}
if [[ "$stamp_bug" == true ]]; then
  # v3.35.0 (BUG-005): defect groups live standalone OR inside a per-day batch
  # (<bugs_root>/BATCH-YYYYMMDD/<id>/) — resolve to exactly one (standards §1.1).
  # v3.36.0 (BUG-006): THIRD layout — a FLAT batch whose members are `## <id>`
  # anchors in the batch's own six pieces; resolving to the batch dir stamps the
  # shared files once with the batch label + member list.
  if [[ -d "$BUGS_ROOT/$chg" ]]; then
    CHG_DIR="$BUGS_ROOT/$chg"
  else
    nested=""
    flat=""
    for b in "$BUGS_ROOT"/BATCH-*/; do
      if [[ -d "${b}${chg}" ]]; then
        [[ -n "$nested" ]] && { echo "stamp-provenance: defect group '$chg' exists in more than one day batch under $BUGS_ROOT" >&2; exit 2; }
        nested="${b%/}/$chg"
      fi
      if [[ -s "${b}01-diagnosis.md" ]] \
        && grep -qE "^##[[:space:]]+${chg}([[:space:]]|\$)" "${b}01-diagnosis.md" 2>/dev/null; then
        [[ -n "$flat" ]] && { echo "stamp-provenance: defect group '$chg' is anchored in more than one day batch under $BUGS_ROOT" >&2; exit 2; }
        flat="${b%/}"
      fi
    done
    if [[ -n "$nested" && -n "$flat" ]]; then
      echo "stamp-provenance: defect group '$chg' exists both nested ($nested) and flat-anchored ($flat) — keep exactly one (standards §1.1)" >&2
      exit 2
    fi
    if [[ -n "$nested" ]]; then
      CHG_DIR="$nested"
    elif [[ -n "$flat" ]]; then
      CHG_DIR="$flat"
    else
      echo "stamp-provenance: defect group not found: $BUGS_ROOT/$chg (standalone, BATCH-*/<id>, or flat BATCH-*/ anchor)" >&2
      exit 2
    fi
  fi
else
  CHG_DIR=$(resolve_dir "$chg")
fi

# v3.42.0 --trace: derive-only mode (no provenance stamping).
if [[ "$stamp_trace" == true ]]; then
  derive_trace_block "$chg" "$CHG_DIR"
  exit 0
fi

if [[ "$#" -gt 0 ]]; then
  targets=("$@")
  default_target=false
elif [[ "$stamp_all" == true ]]; then
  # v3.22.0 --all: every *.md of the resolved change dir. Missing files are
  # skipped loudly (the loop below prints "skip"); only a ZERO-success run
  # fails, because "nothing stamped" must never masquerade as success.
  targets=("$CHG_DIR"/*.md)
  default_target=false
elif [[ "$stamp_bug" == true ]]; then
  # v3.28.0 --bug: every *.md of the defect doc group (typically the six-piece).
  targets=("$CHG_DIR"/*.md)
  default_target=false
else
  targets=("$CHG_DIR/04.5-coding-record.md")
  default_target=true
fi

# What the block attests. In a batch the coding record is SHARED by every
# bundled change, so naming one member would be a claim the next member's stamp
# silently overwrites. Attest the batch and list what it covers instead.
# Bug mode (v3.28.0) attests the defect group with a `bug:` label and no batch;
# v3.36.0 (BUG-006): a bug id resolved to a FLAT batch attests the batch
# (`bug: <BATCH-id>` + `batch_bugs:` member list aggregated from the anchors).
if [[ "$stamp_bug" == true ]]; then
  block_label="bug"
  if [[ "$(basename "$CHG_DIR")" =~ ^BATCH-[0-9]{8}$ ]]; then
    block_change="$(basename "$CHG_DIR")"
    batch_changes=$(sed -nE 's/^##[[:space:]]+([A-Za-z0-9][A-Za-z0-9_-]*)([[:space:]].*)?$/\1/p' "$CHG_DIR/01-diagnosis.md" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  else
    block_change="$chg"
    batch_changes=""
  fi
elif [[ "$(basename "$CHG_DIR")" =~ ^BATCH-[0-9]{8}$ ]]; then
  block_change="$(basename "$CHG_DIR")"
  batch_changes=$(for f in "$CHG_DIR"/*.md; do
      [[ -f "$f" ]] || continue
      sed -nE 's/^##[[:space:]]+([A-Za-z0-9][A-Za-z0-9_-]*)([[:space:]].*)?$/\1/p' "$f"
    done | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  block_label="change"
else
  block_change="$chg"
  batch_changes=""
  block_label="change"
fi

# --- 从环境取真值（缺什么写 unknown，不编造）---------------------------------
g() { command -v "$1" >/dev/null 2>&1; }

if g git && git rev-parse --git-dir >/dev/null 2>&1; then
  author=$(git config user.name 2>/dev/null || true)
  email=$(git config user.email 2>/dev/null || true)
  [[ -n "$email" ]] || email=$(git log -1 --format=%ae 2>/dev/null || true)
  committer=$(git log -1 --format='%an <%ae>' 2>/dev/null || true)
  commit=$(git rev-parse --short HEAD 2>/dev/null || true)
else
  author=""; email=""; committer=""; commit=""
fi
[[ -n "$author" ]]    || author="${USER:-unknown}"
[[ -n "$email" ]]     || email="unknown"
[[ -n "$committer" ]] || committer="unknown"
[[ -n "$commit" ]]    || commit="unknown"

if [[ "$INCLUDE_EMAIL" == "false" ]]; then
  email="<redacted>"
fi

host=$(hostname 2>/dev/null || true)
[[ -n "$host" ]] || host="unknown"
os=$(uname -s 2>/dev/null || echo unknown)
arch=$(uname -m 2>/dev/null || echo unknown)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)

risk="unknown"
gov="$CHG_DIR/00-governance.json"
if [[ -f "$gov" ]]; then
  # Scope to THIS change's record: a batch holds one JSON line per change, so a
  # bare "first risk_level in the file" would report a sibling's risk.
  r=$(grep -E "\"change_id\"[[:space:]]*:[[:space:]]*\"${chg}\"" "$gov" 2>/dev/null \
      | head -n 1 \
      | sed -nE 's/.*"risk_level"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' || true)
  [[ -n "$r" ]] && risk="$r"
fi
# For a batch the block attests the WHOLE batch, so the risk it reports must not
# depend on which member happened to run the stamp — otherwise re-stamping by a
# sibling silently rewrites the block's risk line. Report the batch's HIGHEST
# declared risk: stable across members, and the conservative direction (batches
# are L0/L1 only, so the value is at most L1).
if [[ -n "$batch_changes" && -f "$gov" ]]; then
  risk=""
  for _bc in $batch_changes; do
    _br=$(grep -E "\"change_id\"[[:space:]]*:[[:space:]]*\"${_bc}\"" "$gov" 2>/dev/null \
        | head -n 1 \
        | sed -nE 's/.*"risk_level"[[:space:]]*:[[:space:]]*"(L[0-3])".*/\1/p' || true)
    [[ -n "$_br" ]] || continue
    # Numeric compare only inside the L0..L3 domain; never compare 'unknown'.
    if [[ -z "$risk" ]]; then risk="$_br"
    elif [[ "${_br#L}" -gt "${risk#L}" ]]; then risk="$_br"; fi
  done
  [[ -n "$risk" ]] || risk="unknown"
fi

# Bug mode: no governance record exists for a defect group — say so instead of
# letting the risk lookup fall through to a misleading "unknown".
[[ "$stamp_bug" == true ]] && risk="n/a"

skill_ver="unknown"
std="$DOCS_DIR/DEVELOPMENT_STANDARDS.md"
if [[ -f "$std" ]]; then
  v=$(grep -oE '规范版本：v[0-9.]+' "$std" 2>/dev/null | head -1 | grep -oE '[0-9.]+' || true)
  [[ -n "$v" ]] && skill_ver="$v"
fi

BLK=$(mktemp) || exit 2
trap 'rm -f "$BLK"' EXIT
{
  echo "<!-- provenance"
  echo "$block_label: $block_change"
  echo "risk: $risk"
  if [[ -n "$batch_changes" ]]; then
    echo "batch_changes: $batch_changes"
  fi
  echo "author: $author"
  echo "email: $email"
  echo "committer: $committer"
  echo "commit: $commit"
  echo "host: $host"
  echo "platform: $os $arch"
  echo "generated_at: $now"
  echo "generated_by: stamp-provenance.sh"
  echo "skill_version: $skill_ver"
  echo "-->"
} > "$BLK"

if [[ "$mode" == print ]]; then
  cat "$BLK"
  exit 0
fi

# --- 写入：整块替换（幂等），否则插到首个 H1 之后 -----------------------------
# 默认目标（未显式给文件名）缺失时**不**自动建空文件：门禁对 04.5 只查"存在且非空"，
# 自动建骨架会让"空壳也算交付"——那正是本脚本要收窄的缺口。改为给出可执行的下一步。
stamped=0
for f in "${targets[@]}"; do
  if [[ ! -f "$f" ]]; then
    if [[ "$default_target" == true ]]; then
      echo "stamp-provenance: $f does not exist yet" >&2
      echo "stamp-provenance: write the coding record first (changed-file list / WHY decisions / ReAct), then re-run:" >&2
      echo "stamp-provenance:   scripts/stamp-provenance.sh $chg" >&2
      exit 2
    fi
    echo "stamp-provenance: skip (no such file) $f" >&2
    continue
  fi
  stripped=$(mktemp) || exit 2
  out=$(mktemp) || exit 2
  # 1) 去掉已有块（含其后的一个空行），保证重复运行不叠加
  sed '/^<!-- provenance$/,/^-->$/d' "$f" > "$stripped"
  # 2) 插到首个 H1 之后；没有 H1 就置于文件头
  awk -v bf="$BLK" '
    { print }
    !done && /^# / { print ""; while ((getline l < bf) > 0) print l; close(bf); done=1 }
    END { if (!done) { } }
  ' "$stripped" > "$out"
  if ! grep -q '^<!-- provenance$' "$out"; then
    { cat "$BLK"; echo; cat "$stripped"; } > "$out"
  fi
  cat "$out" > "$f"
  rm -f "$stripped" "$out"
  echo "stamped      $f"
  stamped=$(( stamped + 1 ))
done

[[ "$stamped" -gt 0 ]] || { echo "stamp-provenance: nothing stamped" >&2; exit 2; }
if [[ "$stamp_all" == true ]]; then
  derive_trace_block "$chg" "$CHG_DIR"
fi
exit 0
