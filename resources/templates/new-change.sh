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

# 确认检测下沉 gate（v3.55.0，CHG-068 REQ-1002）：check-confirm 子命令承载
# GATE-E83 语义单源（独立/批次锚点 scope+机校标记+L0-exclusive 声明+env 豁免），
# exit 0=确认在位 / 1=无确认（stderr reason）/ 2=错误。本脚本不再持有第二实现。

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
      die "NC-E07: change $id is fully scaffolded in $batch — open a new change id (upgrading repo with pre-v3.52 members: hand-add the missing 00.5 anchor sections first)"
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
    confirm_gate_rc=0
    if [[ "$allow_unconfirmed" == 1 ]]; then
      echo "new-change: --allow-unconfirmed — register the justification in 09「重要上下文」(standards §2.17.2d)"
    else
      [[ -x "scripts/agent-gate" ]] || die "NC-E10: scripts/agent-gate not found — wave-2 confirmation gate moved into the gate (check-confirm, v3.55.0); run bootstrap --guard first"
      scripts/agent-gate check-confirm "$id" || confirm_gate_rc=$?
    fi
    if [[ "$allow_unconfirmed" == 1 || "$confirm_gate_rc" == 0 ]]; then
      for doc in "${wave2_missing[@]}"; do
        batch_put "$doc"
      done
      echo "new-change: wave2 scaffolded (${wave2_missing[*]})"
    elif [[ "$confirm_gate_rc" == 1 ]]; then
      if [[ "${scaffolded_wave1:-0}" == 1 ]]; then
        echo "new-change: wave2 withheld — record the user overall confirmation in $batch/00.5-communication.md (确认状态：已整体确认 or L0 single-line declaration, §2.17.2d), then re-run scripts/new-change $id --risk $risk" >&2
      else
        die "NC-E09: user-overall-confirmation not recorded in $batch/00.5-communication.md (## $id) — communication-first gate (standards §2.17.2d): present the round-1 communication, get overall confirmation, record it (确认状态：已整体确认 or L0 single-line declaration), then re-run scripts/new-change $id --risk $risk; --allow-unconfirmed is the explicit automation bypass; upgrading repo with pre-v3.52 batch members: hand-add the 00.5 anchor section to the shared file"
      fi
    else
      die "NC-E10: check-confirm failed (rc=$confirm_gate_rc) — see scripts/agent-gate output above"
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
    confirm_gate_rc=0
    if [[ "$allow_unconfirmed" == 1 ]]; then
      echo "new-change: --allow-unconfirmed — register the justification in 09「重要上下文」(standards §2.17.2d)"
    else
      [[ -x "scripts/agent-gate" ]] || die "NC-E10: scripts/agent-gate not found — wave-2 confirmation gate moved into the gate (check-confirm, v3.55.0); run bootstrap --guard first"
      scripts/agent-gate check-confirm "$id" || confirm_gate_rc=$?
    fi
    if [[ "$allow_unconfirmed" == 1 || "$confirm_gate_rc" == 0 ]]; then
      for doc in "${wave2_missing[@]}"; do
        fill "$tmpl_dir/$doc" > "$d/$doc"
      done
      echo "new-change: wave2 scaffolded (${wave2_missing[*]})"
    elif [[ "$confirm_gate_rc" == 1 ]]; then
      if [[ "${scaffolded_wave1:-0}" == 1 ]]; then
        echo "new-change: wave2 withheld — record the user overall confirmation in $d/00.5-communication.md (确认状态：已整体确认 or L0 single-line declaration, §2.17.2d), then re-run scripts/new-change $id --risk $risk" >&2
      else
        die "NC-E09: user-overall-confirmation not recorded in $d/00.5-communication.md — communication-first gate (standards §2.17.2d): present the round-1 communication, get overall confirmation, record it (确认状态：已整体确认 or L0 single-line declaration), then re-run scripts/new-change $id --risk $risk; --allow-unconfirmed is the explicit automation bypass; upgrading repo with pre-v3.52 batch members: hand-add the 00.5 anchor section to the shared file"
      fi
    else
      die "NC-E10: check-confirm failed (rc=$confirm_gate_rc) — see scripts/agent-gate output above"
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
