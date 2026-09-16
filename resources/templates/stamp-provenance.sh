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
#   scripts/stamp-provenance.sh --print <CHG-id>      # 只打印块，不写文件
#   scripts/stamp-provenance.sh --check <file>        # 校验已有块（CI 用，形状 + 非占位）
#
# --all 把溯源块盖到解析后变更目录的**每一个 *.md**（12 件产物批量可溯；幂等整块
# 替换，重复运行不叠加）。`00-governance.json` **刻意不盖**——JSON 里注入 HTML 注释
# 会破坏机器读取（门禁/审计按扁平 JSON 切分记录）。强制范围不变：§1.1 仍只强制
# 04.5-coding-record.md 携带溯源块，--all 是可选的全量加强，不是新的硬性要求。
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
INCLUDE_EMAIL="${AGENT_GUARD_PROVENANCE_EMAIL:-$(cfg_path include_email true)}"

usage() {
  cat <<'EOF'
Usage: scripts/stamp-provenance.sh <CHG-id> [file ...]
       scripts/stamp-provenance.sh --all <CHG-id>
       scripts/stamp-provenance.sh --print <CHG-id>
       scripts/stamp-provenance.sh --check <file>

Writes a provenance block (author / committer / host / platform / UTC time),
read from the environment — never hand-written. Idempotent: an existing block is
replaced wholesale, so re-running is safe.

Default target: <change_root>/<CHG-id>/04.5-coding-record.md
--all:          stamp every *.md artifact of the resolved change directory
                (batch-aware; 00-governance.json is deliberately NOT stamped —
                an HTML comment inside JSON would break the machine readers).
Privacy: set `provenance.include_email: false` in .agent-governance.yml to write
         email as <redacted>.
EOF
}

mode=write
stamp_all=false
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --print)   mode=print; shift ;;
  --check)   mode=check; shift ;;
  --all)     stamp_all=true; shift ;;
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

# Batch-aware resolution (v3.18.0): a same-day L0/L1 batch keeps its artifacts in
# BATCH-YYYYMMDD/, addressed by `## <change-id>` anchors. Resolve the directory
# the same way the gate does, so the remedy the gate prints
# (`scripts/stamp-provenance.sh <CHG-id>`) keeps working for batch members.
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
CHG_DIR=$(resolve_dir "$chg")

if [[ "$#" -gt 0 ]]; then
  targets=("$@")
  default_target=false
elif [[ "$stamp_all" == true ]]; then
  # v3.22.0 --all: every *.md of the resolved change dir. Missing files are
  # skipped loudly (the loop below prints "skip"); only a ZERO-success run
  # fails, because "nothing stamped" must never masquerade as success.
  targets=("$CHG_DIR"/*.md)
  default_target=false
else
  targets=("$CHG_DIR/04.5-coding-record.md")
  default_target=true
fi

# What the block attests. In a batch the coding record is SHARED by every
# bundled change, so naming one member would be a claim the next member's stamp
# silently overwrites. Attest the batch and list what it covers instead.
if [[ "$(basename "$CHG_DIR")" =~ ^BATCH-[0-9]{8}$ ]]; then
  block_change="$(basename "$CHG_DIR")"
  batch_changes=$(for f in "$CHG_DIR"/*.md; do
      [[ -f "$f" ]] || continue
      sed -nE 's/^##[[:space:]]+([A-Za-z0-9][A-Za-z0-9_-]*)([[:space:]].*)?$/\1/p' "$f"
    done | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
else
  block_change="$chg"
  batch_changes=""
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
  echo "change: $block_change"
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
exit 0
