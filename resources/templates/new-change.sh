#!/usr/bin/env bash
# new-change — 变更管线入口骨架生成器（v3.38.0，规范 §2.17.1 入口件派发）
#
# 用法：scripts/new-change <change-id> --risk L0|L1|L2|L3
#
# 语义：
#   - 两段式（v3.52.0，沟通先行门 §2.17.2d）：第一段只生成 00-intent/00-governance/
#     00.5-communication.md（沟通稿+确认记录骨架）；检测到 00.5 含非空「用户整体确认
#     记录」（或 L0 单行声明）后才补齐 01-spec/02/03/03.5/04 五件——确认记录落盘前
#     不生成后续产物骨架。--allow-unconfirmed 供自动化入口显式越过（09 登记义务）。
#   - 专用目录形态：创建 <change_root>/<id>/ 并从 <docs>/templates/entry/ 复制
#     骨架（__CHANGE_ID__/__RISK__ 占位符随装随替）。
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
[[ -n "$id" ]] || die "NC-E01: usage: scripts/new-change <change-id> --risk L0|L1|L2|L3 [--allow-unconfirmed]"
shift || true
risk=""
allow_unconfirmed=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --risk)
      [[ $# -ge 2 && -n "${2:-}" ]] || die "NC-E02: --risk requires a value (L0|L1|L2|L3)"
      risk="$2"; shift 2 ;;
    --allow-unconfirmed)
      allow_unconfirmed=1; shift ;;
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

# 沟通先行门两段式（v3.52.0 §2.17.2d）：wave1 = 入口三件；wave2 = 确认后五件
wave1_docs=(00-intent.md 00-governance.json 00.5-communication.md)
wave2_docs=(01-spec.md 02-code-impact-analysis.md 03-modification-plan.md 03.5-tasks.md 04-test-scripts.md)

# 确认检测（与 gate GATE-E83 同锚点串同豁免语义）：批次按 `## <id>` 锚点取
# 本变更小节；L0 单行声明放行；显式确认标记 = `确认状态：已整体确认`。
confirm_ok() { # <comm-file> <id> <risk>
  local f="$1" cid="$2" risk="$3" scope others
  [[ -s "$f" ]] || return 1
  if grep -qE "^##[[:space:]]+${cid}([[:space:]]|$)" "$(dirname "$f")/00-intent.md" 2>/dev/null; then
    # 批次成员（以 00-intent 锚点判定，与 gate E83 同序）：小节跑到下一兄弟
    # 锚点为止（成员节内合法含 h2 结构标题）；本成员 00.5 无自身锚点=fail-closed；
    # 兄弟名单优先 governance 权威行（governance 不可读时回退锚点扫描，同
    # gate change_ids_in_dir 两级语义）；子壳 `|| true`——单成员批次
    # grep -vx 无输出 + pipefail 会静默 exit 1
    grep -qE "^##[[:space:]]+${cid}([[:space:]]|$)" "$f" || return 1
    # 兄弟名单：governance 权威行优先，不可读时回退锚点扫描。管道形态必须与
    # gate 一致——`||` 优先级低于管道，裸 `{...} || true | sort` 会让 grep
    # 命中时 sort/tr 不执行、others 残留换行 → awk stop 永不匹配 → 兄弟确认
    # 外溢（v3.54 收口修复；正确形态=子壳内 || true，对齐 agent-gate.sh）。
    others=$({ grep -oE '"change_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9._-]+"' "$(dirname "$f")/00-governance.json" 2>/dev/null \
      | sed 's/.*"\([^"]*\)"/\1/'; } || true)
    if [[ -z "$others" ]]; then
      others=$({ grep -oE '^##[[:space:]]+[A-Za-z0-9][A-Za-z0-9._-]*' "$f" 2>/dev/null \
        | sed 's/^##[[:space:]]*//'; } || true)
    fi
    others=$( (printf '%s\n' $others | grep -vx "$cid" || true) | sort -u | tr '\n' '|')
    others="${others%|}"
    if [[ -n "$others" ]]; then
      scope=$(awk -v cur="^##[[:space:]]+${cid}([[:space:]]|$)" -v stop="^##[[:space:]]+(${others})([[:space:]]|$)" '$0 ~ cur {f=1; next} f && $0 ~ stop {f=0} f' "$f")
    else
      scope=$(awk -v cur="^##[[:space:]]+${cid}([[:space:]]|$)" '$0 ~ cur {f=1; next} f' "$f")
    fi
  else
    scope=$(cat "$f")
  fi
  if printf '%s\n' "$scope" | grep -qE '^[[:space:]]*-[[:space:]]*\*\*沟通确认\*\*(：|:)[[:space:]]*未命中，不适用（.+）'; then
    [[ "$risk" == "L0" ]]   # L0-exclusive declaration channel (mirror of GATE-E83, §2.17.2d)
  else
    printf '%s\n' "$scope" | grep -q "用户整体确认记录" \
      && printf '%s\n' "$scope" | grep -qE '(确认状态|confirmation)[[:space:]]*(：|:)[[:space:]]*(已整体确认|confirmed)'
  fi
}

# 把一份骨架落入共享批次文件（存在即追加锚点节，不存在则建带头文件）
batch_put() { # <doc>
  local doc="$1"
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
}

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
  if grep -qE "^##[[:space:]]+$id([[:space:]]|$)" "$batch/00-intent.md" 2>/dev/null; then
    # 已 wave1 的成员：仅当 wave2 有本成员缺失小节时才继续（否则重复脚手架）
    wave2_missing=()
    for doc in "${wave2_docs[@]}"; do
      grep -qE "^##[[:space:]]+$id([[:space:]]|$)" "$batch/$doc" 2>/dev/null || wave2_missing+=("$doc")
    done
    if [[ ${#wave2_missing[@]} -eq 0 ]]; then
      die "NC-E07: change $id is fully scaffolded in $batch — open a new change id"
    fi
  else
    wave2_missing=("${wave2_docs[@]}")
    for doc in "${wave1_docs[@]}"; do
      batch_put "$doc"
    done
    scaffolded_wave1=1
    echo "new-change: batch-joined $batch (wave1 entry artifacts appended: ## $id)"
  fi
  if [[ ${#wave2_missing[@]} -gt 0 ]]; then
    if [[ "$allow_unconfirmed" == 1 ]] || confirm_ok "$batch/00.5-communication.md" "$id" "$risk"; then
      [[ "$allow_unconfirmed" == 1 ]] \
        && echo "new-change: --allow-unconfirmed — register the justification in 09「重要上下文」(standards §2.17.2d)"
      for doc in "${wave2_missing[@]}"; do
        batch_put "$doc"
      done
      echo "new-change: wave2 scaffolded (${wave2_missing[*]})"
    elif [[ "${scaffolded_wave1:-0}" == 1 ]]; then
      echo "new-change: wave2 withheld — record the user overall confirmation in $batch/00.5-communication.md (确认状态：已整体确认 or L0 single-line declaration, §2.17.2d), then re-run scripts/new-change $id --risk $risk" >&2
    else
      die "NC-E09: user-overall-confirmation not recorded in $batch/00.5-communication.md (## $id) — communication-first gate (standards §2.17.2d): present the round-1 communication, get overall confirmation, record it (确认状态：已整体确认 or L0 single-line declaration), then re-run scripts/new-change $id --risk $risk; --allow-unconfirmed is the explicit automation bypass"
    fi
  fi
  d="$batch"
else
  d="$change_root/$id"
  if [[ -e "$d" ]]; then
    # 已存在目录：全部 wave1+wave2 齐备 = 重复脚手架；否则补缺（wave2 仍过确认门）
    complete=1
    for doc in "${wave1_docs[@]}" "${wave2_docs[@]}"; do
      [[ -s "$d/$doc" ]] || { complete=0; break; }
    done
    [[ "$complete" == 1 ]] && die "NC-E08: $d already exists and is fully scaffolded — open a new change id (standards §2.15 rule 4)"
    for doc in "${wave1_docs[@]}"; do
      [[ -s "$d/$doc" ]] || fill "$tmpl_dir/$doc" > "$d/$doc"
    done
    wave2_missing=()
    for doc in "${wave2_docs[@]}"; do
      [[ -s "$d/$doc" ]] || wave2_missing+=("$doc")
    done
  else
    mkdir -p "$d"
    for doc in "${wave1_docs[@]}"; do
      fill "$tmpl_dir/$doc" > "$d/$doc"
    done
    wave2_missing=("${wave2_docs[@]}")
    scaffolded_wave1=1
    echo "new-change: scaffolded wave1 entry artifacts in $d"
  fi
  if [[ ${#wave2_missing[@]} -gt 0 ]]; then
    if [[ "$allow_unconfirmed" == 1 ]] || confirm_ok "$d/00.5-communication.md" "$id" "$risk"; then
      [[ "$allow_unconfirmed" == 1 ]] \
        && echo "new-change: --allow-unconfirmed — register the justification in 09「重要上下文」(standards §2.17.2d)"
      for doc in "${wave2_missing[@]}"; do
        fill "$tmpl_dir/$doc" > "$d/$doc"
      done
      echo "new-change: wave2 scaffolded (${wave2_missing[*]})"
    elif [[ "${scaffolded_wave1:-0}" == 1 ]]; then
      echo "new-change: wave2 withheld — record the user overall confirmation in $d/00.5-communication.md (确认状态：已整体确认 or L0 single-line declaration, §2.17.2d), then re-run scripts/new-change $id --risk $risk" >&2
    else
      die "NC-E09: user-overall-confirmation not recorded in $d/00.5-communication.md — communication-first gate (standards §2.17.2d): present the round-1 communication, get overall confirmation, record it (确认状态：已整体确认 or L0 single-line declaration), then re-run scripts/new-change $id --risk $risk; --allow-unconfirmed is the explicit automation bypass"
    fi
  fi
  echo "new-change: scaffolded $d"
fi

cat <<'EOF'
next steps (gate begin refuses skeletons until they are filled):
  1. deep-dive first, then present the round-1 communication (00.5:
     findings/impact/risks/options>=2/test approach) and record the user
     overall confirmation in 00.5-communication.md (确认状态：已整体确认);
     L0 may use the single-line declaration instead (§2.17.2d);
  2. fill 00-intent.md (问题/预期结果/开放问题) and pick real owners in
     00-governance.json — PENDING placeholders are rejected by begin;
  3. fill 01-spec REQ- / 02 三维 / 03 DES-+选型 / 03.5 依赖+里程碑 / 04 TC-+SC-;
  4. run: scripts/agent-gate begin <change-id>
EOF
