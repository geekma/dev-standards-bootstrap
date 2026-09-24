#!/usr/bin/env bash
# generate-reading-pack.sh — 条款注册表 → 按变更类型生成阅读包（v3.46.0，CHG-056 REQ-969）
#
# 用法：generate-reading-pack.sh <type> [--verify]
#   <type>     封闭词表：L0-bugfix | L1-standards | L2-architecture | L3-critical | universal
#   --verify   只校验（锚点可解析性），不输出阅读包；绿态静默退出 0
#
# 权威关系（防双权威源漂移）：注册表是机器索引层，DS 是叙事唯一权威。本脚本逐条解析
# 注册表锚点存在性——文件缺失/锚点失配/多命中一律 fail-closed 指名 Rxx，永不产出与权威
# 漂移的副本。阅读包是按需生成物，不入库、不手编（预生成入库=双权威源，禁止）。
#
# 退出码：0 成功；2 用法/未知类型/注册表缺失；3 锚点 fail-closed；4 该类型零条款。
set -euo pipefail

die() { echo "generate-reading-pack: $1" >&2; exit "${2:-2}"; }

usage() {
  cat >&2 <<'USAGE'
usage: generate-reading-pack.sh <type> [--verify]
  <type>: L0-bugfix | L1-standards | L2-architecture | L3-critical | universal
  --verify: validate anchors only, no output
USAGE
  exit 2
}

TYPE="${1:-}"; VERIFY=0
[[ "${2:-}" == "--verify" ]] && VERIFY=1
[[ "$#" -ge 1 && -n "$TYPE" ]] || usage
case "$TYPE" in
  L0-bugfix|L1-standards|L2-architecture|L3-critical|universal) ;;
  *) die "unknown type '$TYPE' (closed vocab: L0-bugfix L1-standards L2-architecture L3-critical universal)" 2 ;;
esac

# 仓根解析：git 优先，退化为脚本相对（resources/templates/ → 上两级）。
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# 注册表落点候选（源仓 resources/，安装仓 <docs>/，env 显式优先）。
REG="${CLAUSE_REGISTRY_FILE:-}"
if [[ -z "$REG" ]]; then
  for cand in "$ROOT/resources/CLAUSE_REGISTRY.md" "$ROOT/docs/CLAUSE_REGISTRY.md"; do
    [[ -s "$cand" ]] && { REG="$cand"; break; }
  done
fi
[[ -n "$REG" && -s "$REG" ]] || die "registry missing (tried CLAUSE_REGISTRY_FILE, resources/, docs/)" 2

# 锚点落点解析：注册表登记 basename（DEVELOPMENT_STANDARDS.md::anchor），按仓形态
# 多候选定位（源仓 resources/、安装仓 docs/、仓根），首个存在者胜。
resolve_loc() { # <basename-or-path> -> absolute file or empty
  local p="$1"
  local cand
  # 纵深防御：注册表 path 字段禁止路径穿越（评审 P3-1）。
  [[ "$p" == *..* || "$p" == /* ]] && return 1
  for cand in "$ROOT" "$ROOT/resources" "$ROOT/docs"; do
    [[ -f "$cand/$p" && -s "$cand/$p" ]] && { printf '%s' "$cand/$p"; return 0; }
  done
  return 1
}

# 解析注册表行：| Rxx | 标题 | path::anchor | 标签 | 级别 | 生命周期 |
# 只认行首 "| R<数字>" 形态；表头/分隔行/正文自然跳过。
rows="$(grep -E '^\| R[0-9]+[[:space:]]*\|' "$REG" || true)"

total=0
missed=0
pack_lines=0
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

emit_clause() { # id title path anchor level life
  printf '%s\n' "$1" >> "$out"
}

while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  id="$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/,"",$2); print $2}')"
  title="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3}')"
  loc="$(printf '%s'  "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$4); print $4}')"
  label="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$5); print $5}')"
  level="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$6); print $6}')"
  life="$(printf '%s'  "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$7); print $7}')"

  [[ "$label" == "$TYPE" || "$label" == "universal" ]] || continue

  path="${loc%%::*}"
  anchor="${loc#*::}"
  [[ -n "$path" && -n "$anchor" && "$loc" == *::* ]] \
    || { echo "generate-reading-pack: MALFORMED LOC ($id): '$loc'" >&2; exit 3; }
  target_file="$(resolve_loc "$path" || true)"
  [[ -n "$target_file" ]] \
    || { echo "generate-reading-pack: ANCHOR FILE MISSING ($id): $path" >&2; exit 3; }

  hits="$(grep -nF -- "$anchor" "$target_file" || true)"
  hit_count="$(printf '%s' "$hits" | grep -c . || true)"
  if [[ "$hit_count" -eq 0 ]]; then
    echo "generate-reading-pack: ANCHOR MISS ($id): '$anchor' not found in $path" >&2
    exit 3
  fi
  if [[ "$hit_count" -gt 1 ]]; then
    echo "generate-reading-pack: ANCHOR NOT UNIQUE ($id): '$anchor' matched $hit_count times in $path" >&2
    exit 3
  fi
  line_no="$(printf '%s' "$hits" | head -1 | cut -d: -f1)"

  total=$((total + 1))
  emit_clause "| $id | $title | ${target_file#$ROOT/}:$line_no | $level | $life |"
done <<< "$rows"

if [[ "$total" -eq 0 ]]; then
  die "no clauses registered for type '$TYPE'" 4
fi

if [[ "$VERIFY" -eq 1 ]]; then
  # 校验模式：零输出（绿态静默），锚点全可解析即成功。
  exit 0
fi

pack_body_lines="$(grep -c . "$out" || true)"
{
  echo "# 阅读包：${TYPE}（生成物，勿手编辑、不入库）"
  echo ""
  echo "- 类型：$TYPE"
  echo "- 条款数：$total"
  echo "- 生成命令：generate-reading-pack.sh $TYPE"
  echo "- 生成时间：$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- 声明：本包由条款注册表按需生成；条款正文以权威文件为准，本包只做路由（落点:行号）。"
  echo ""
  echo "| 条款 | 标题 | 权威落点:行号 | 强制级别 | 生命周期 |"
  echo "| --- | --- | --- | --- | --- |"
  cat "$out"
}
if [[ "$pack_body_lines" -gt 200 ]]; then
  echo "generate-reading-pack: WARN pack body $pack_body_lines lines exceeds ~200 target (advisory, not blocking)" >&2
fi
