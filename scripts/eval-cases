#!/usr/bin/env bash
# eval-cases — 评测资产派生视图（v3.75.0, CHG-099 / REQ-1108）
#
# 状态（v3.86.0）：实验性。只从本地缺陷台账派生，输出落 .agent-state/（运行时
# 产物、禁止入库）；不接外部评测框架、不做跨仓聚合。0 用例是合法初始态。
#
# 机制契约（唯一权威 = 本头注释；规范正文只写不变量与指针，§2.17.2c 同源纪律）
#
# 输入（确定性、磁盘单源，无网络、无 LLM）：
#   1) <docs>/bugs/**/01-diagnosis.md  —— 缺陷组诊断件。三形态解析：独立目录 BUG-xxx/
#      与嵌套 BATCH-*/BUG-xxx/ 取目录名为缺陷身份；扁平目录 BATCH-*/ 取件内
#      `## BUG-xxx` 锚点分节为缺陷身份。批次共享件若既非 BUG-* 目录、又无 `## BUG-`
#      锚点，则无缺陷身份，不产 case（跳过，不臆造 id）。
#   2) <docs>/bugs/**/04-matrix.md     —— 回归用例引用来源（同目录；扁平形态同锚点分节）
#
# 输出（制表符分隔，表头固定）：
#   case_id  source  bug_id  captured_layer  landing  regression_ref
#   · case_id       = EC-<bug_id>（派生 id 内嵌源 id，新增缺陷时不重排既有行；**按 case_id 唯一**
#                     ——同 id 多形态出现时取稳定序首行，防覆盖比分母重复计数）
#   · source        = regression（诊断件含「复现记录（自动）」节，§2.17.2b 自动建组的确证；
#                     优先于 id 形态——两条自动通道都用 BUG-<UTCts> 编号）
#                     | incident（无自动节但 id 形如 BUG-<UTC 时间戳>，§2.17.2 事故重入）
#                     | manual（其余人工编号）
#   · captured_layer= 诊断件「应捕获层」行的值；缺失写 未声明（不臆造，§2.17.5 第 2 条）
#   · landing       = 缺陷组落点（相对仓库根）
#   · regression_ref= 04-matrix 中首个 TC 编号；无写空串（= 该教训未沉淀防回归用例）
#
# 参数：--verify        只校验输入面可解析性（不写盘；零输出 = 绿）
#       --out <path>    覆盖输出落点（默认 <repo>/.agent-state/eval-cases.tsv）
#       -h | --help     本用法
# 退出码：0 = 成功 / 校验通过；1 = 校验失败；2 = usage 错误
# 幂等：内容无时间戳；LC_ALL=C 稳定排序；重复运行结果逐字节相同。
# 生成物语义：运行时产物（禁止入库、禁止手编）；缺失输入面 = 0 用例 + 仅表头 + 退出 0。
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'USAGE'
usage: eval-cases [--verify] [--out <path>]

  --verify       校验缺陷资产可派生（只读，零输出即绿；不写盘）
  --out <path>   输出落点（默认 <repo>/.agent-state/eval-cases.tsv）
  -h, --help     显示本用法

机制契约见脚本头注释（唯一权威）。
USAGE
}

root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[[ -n "$root" ]] || root=$PWD

verify=0
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) verify=1 ;;
    --out)
      shift
      [[ $# -gt 0 ]] || { echo "eval-cases: --out requires a path" >&2; exit 2; }
      out=$1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "eval-cases: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

bugs_dir="$root/docs/bugs"
[[ -n "$out" ]] || out="$root/.agent-state/eval-cases.tsv"

# extract_section <file> <anchor-or-empty> — 无锚点时整文件即一节（独立/嵌套形态）
extract_section() {
  local f=$1 a=${2:-}
  [[ -f "$f" ]] || return 0
  if [[ -z "$a" ]]; then
    cat "$f"
    return 0
  fi
  awk -v a="$a" '
    $0 ~ "^##[[:space:]]+" a "([[:space:]]|$)" { sec=1; next }
    /^##[[:space:]]/ { if (sec) exit }
    sec { print }
  ' "$f"
}

diag_value() { # <text> — 「应捕获层」行的值，缺失输出空串（纯 bash 解析，避免 C locale 下的多字节字符类陷阱）
  local text=$1 line val
  line=$(printf '%s\n' "$text" | grep -m1 '应捕获层' || true)
  [[ -n "$line" ]] || return 0
  val=$line
  if [[ "$val" == *'：'* ]]; then
    val=${val##*'：'}
  elif [[ "$val" == *':'* ]]; then
    val=${val##*':'}
  else
    val=${val##*应捕获层}
  fi
  val=${val//\*}
  # 去首尾空白（含全角空格）
  val=${val#"${val%%[! 　	]*}"}
  val=${val%"${val##*[! 　	]}"}
  printf '%s' "$val"
}

# 收集诊断件（稳定序）
diags=()
if [[ -d "$bugs_dir" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && diags+=("$f")
  done < <(find "$bugs_dir" -type f -name '01-diagnosis.md' 2>/dev/null | sort)
fi

rows=""
for f in "${diags[@]:-}"; do
  [[ -n "$f" ]] || continue
  rel=${f#"$root"/}
  dir=${rel%/*}
  base=${dir##*/}
  anchors=""
  if [[ "$base" != BUG-* ]]; then
    anchors=$(grep -E '^##[[:space:]]+BUG-' "$f" 2>/dev/null | sed -e 's/^##[[:space:]]*//' -e 's/[[:space:]].*$//' | sort -u || true)
  fi
  if [[ -z "$anchors" ]]; then
    [[ "$base" = BUG-* ]] || continue
    bug_id="$base"
    body=$(cat "$f")
    ref=$(printf '%s\n' "$(extract_section "$dir/04-matrix.md" "")" | grep -oE 'TC-[0-9]+' | head -1 || true)
    layer=$(diag_value "$body"); [[ -n "$layer" ]] || layer=未声明
    src=manual
    if grep -q '复现记录（自动）' <<< "$body"; then
      src=regression
    else
      case "$bug_id" in BUG-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) src=incident ;; esac
    fi
    rows="$rows$(printf '%s\t%s\t%s\t%s\t%s\t%s\n' "EC-$bug_id" "$src" "$bug_id" "$layer" "$dir" "$ref")"$'\n'
    continue
  fi
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    body=$(extract_section "$f" "$a")
    ref=$(printf '%s\n' "$(extract_section "$dir/04-matrix.md" "$a")" | grep -oE 'TC-[0-9]+' | head -1 || true)
    layer=$(diag_value "$body"); [[ -n "$layer" ]] || layer=未声明
    src=manual
    if grep -q '复现记录（自动）' <<< "$body"; then
      src=regression
    else
      case "$a" in BUG-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) src=incident ;; esac
    fi
    rows="$rows$(printf '%s\t%s\t%s\t%s\t%s\t%s\n' "EC-$a" "$src" "$a" "$layer" "$dir" "$ref")"$'\n'
  done <<EOF
$anchors
EOF
done

# v3.75.0 收尾整改（独立评审 F-8）：按 **case_id** 去重。同一缺陷若既以嵌套目录形态出现、
# 又在扁平批文件里带 `## BUG-<id>` 锚点（两形态 landing 不同），整行 `sort -u` 会留下两行，
# 覆盖比分母被重复计数。先整行稳定排序，再取每个 case_id 的首行（确定性；新增缺陷不重排既有行）。
body=$(printf '%s' "$rows" | sed '/^$/d' | LC_ALL=C sort -u | awk -F'\t' '!seen[$1]++' || true)

if [[ "$verify" = 1 ]]; then
  rc=0
  # (1) 诊断件非空
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ ! -s "$f" ]]; then
      echo "eval-cases: verify: empty diagnosis artifact: ${f#"$root"/}" >&2
      rc=1
    fi
  done < <(find "$bugs_dir" -type f -name '01-diagnosis.md' 2>/dev/null | sort)
  # (2) 缺陷组目录必须带诊断件（孤儿组 = 资产缺口；log↔组互证属 audit G4，不在本脚本重复）
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    if [[ ! -f "$d/01-diagnosis.md" ]]; then
      echo "eval-cases: verify: defect group without 01-diagnosis.md: ${d#"$root"/}" >&2
      rc=1
    fi
  done < <(find "$bugs_dir" -type d -name 'BUG-*' 2>/dev/null | sort)
  # (3) 派生行形状合法（bug_id 非空 / source 枚举内 / landing 存在 / ref 形态）
  while IFS=$'\t' read -r cid src bid layer landing ref; do
    [[ "$cid" = "case_id" || -z "$cid" ]] && continue
    case "$src" in incident|regression|manual) ;; *) echo "eval-cases: verify: bad source '$src' in $cid" >&2; rc=1 ;; esac
    [[ -n "$bid" ]] || { echo "eval-cases: verify: empty bug_id in $cid" >&2; rc=1; }
    [[ -d "$root/$landing" ]] || { echo "eval-cases: verify: landing not found: $landing ($cid)" >&2; rc=1; }
    [[ -z "$ref" || "$ref" =~ ^TC-[0-9]+$ ]] || { echo "eval-cases: verify: malformed regression_ref '$ref' in $cid" >&2; rc=1; }
  done <<EOF
$body
EOF
  # (4) case_id 唯一：REQ-1306 撤回（CHG-130 独立评审）——本脚本只收集
  # `01-diagnosis.md`（每个目录至多一份），单文件内锚点又经 `sort -u` 去重，
  # 因此「同 case_id 且同 landing」的行在数据构造上不可达；跨 landing 的同
  # case_id 是 F-8 明确允许的双形态。保留去重（下面 body 的 `!seen[$1]++`）
  # 作为输出契约，不再保留一条恒 0 的“校验”。
  exit "$rc"
fi

mkdir -p "$(dirname "$out")"
{
  printf 'case_id\tsource\tbug_id\tcaptured_layer\tlanding\tregression_ref\n'
  [[ -n "$body" ]] && printf '%s\n' "$body"
} > "$out"
exit 0
