#!/usr/bin/env bash
# behavior-extract.sh — G13 静态行为清单抽取器（v3.68.0，CHG-043，REQ-1069）
#
# 能力定位：对一个静态 HTML/HTM/JS 原型页做**静态文本**行为面扫描，产出 G13 门禁
# 消费的 behavior-inventory.json（JSONL）。它是勘察期的"锚点生成器"：把原型上的
# 用户可触达行为（点击/输入/提交/弹层/跳转/请求/定时）变成可对账的 BHV-xxx 清单，
# 供 01-spec 事件链引用，并在 stop 阶段接受三方对账（GATE-E102：清单↔事件链↔登记簿）
# 与 hash 反腐校验（GATE-E100：抽取后原型再改动即失效，须重抽并重新锚定）。
#
# 用法：
#   behavior-extract.sh <artifact.html|htm|js> > docs/changes/<CHG-id>/behavior-inventory.json
#   其他扩展名 exit 2 —— 降级路径：人工枚举行为行（沿用同一 JSONL schema），
#   并在 01-spec 声明行写明理由（如 `- **origin_artifact**: 未命中（理由）`）。
#
# JSONL schema（首行头 + N 行行为，字段序固定）：
#   {"artifact":"<原样输入路径>","artifact_hash":"<sha256 64hex>","total_behaviors":N}
#   {"id":"BHV-001","kind":"click|input|change|submit|overlay|nav|fetch|timer|state|element",
#    "event":"<事件名字面量；kind=element 时为标签名小写>",
#    "target":"<行为行=行内最近 id/class/变量提示 ≤60 字符；元素行=#<id> 或 .<class> 或 <<tag>>>",
#    "line":<1-based 行号>,"detail":"<截断 ≤80 字符的原始行>","status":"pending"}
#   status 封闭集 pending|implemented|waived|missing（抽取器一律落 pending，交付期人工收敛；
#   missing 会被 GATE-E101 拦下，必须关闭或显式豁免）。
#
# ── 词表（唯一权威；G14e 元素枚举，CHG-044）────────────────────────────
# 标签面（行内 grep -iE 取 `<tag` 起始）：
#   button / input（排除 type="hidden"）/ select / textarea / a[href] / area[href] /
#   label[for=] / details
# 属性面（任意标签；与行为行 on*= 冗余并存——CHG-044 方案 A 已裁定）：
#   内联 on*= / contenteditable / role=（封闭集 button|checkbox|radio|switch|tab|
#   menuitem|option|slider|spinbutton|textbox|combobox|link）/ tabindex="≥0"（排除 -1）/
#   data-action= / hx-get= | hx-post= | hx-trigger= | hx-on=
# 排除面（命中即整行不出元素行）：aria-hidden="true" / role="presentation" / role="none"
# 元素行约束：仅对行内含 `<tag` 的行判定（HTML 上下文，含 JS 内嵌模板行）；每行至多一条；
#   event=标签名小写；target 三态 #<id> → .<class 首 token> → <<tag>> 兜底；kind=element，
#   在行为行之后按行续编号（BHV-NNN 递增不断号）。
# **词表变更只改本文件 + tests/run-tests.sh T54 行为断言，禁止复制进 DS/STAGE_PLAYBOOK
#   等叙事层（audit A43 单源执法）。**
#   判定语义：同一行命中多个规则时**首个标签获胜**（每行至多一条元素行）——压缩单行
#   HTML 会欠数（漏报方向，fail-safe）；属性排除按精确匹配（type=hidden 全等、
#   role= 全等），不做子串豁免（type=hiddenish 不误排由标签面兜底）。
#
# ── 锚点引用格式（唯一权威；自 STAGE_PLAYBOOK 移入单源维护，CHG-044）──────────
#   [origin: <文件名>#BHV-NNN]
# 行为 ID + inventory artifact_hash 为准（GATE-E100 反腐锚），行号仅辅助定位；
# 叙事层（STAGE_PLAYBOOK 等）只留指针，细则以本节为准。
#
# 退出码语义（fail-closed 面）：
#   0 = 产出清单（total_behaviors >= 1）；2 = 用法错误/扩展名不支持/sha 工具缺失；
#   3 = 零行为（fail-closed：零行为=抽取失败而非事实，禁止静默空清单过门；诊断入 stderr，
#       awk 中途死亡（rc!=0）同样落 3，绝不带半截清单 exit 0）。
#
# locale 钉死 WHY（v3.68.0 回测 record 687，CHG-043）：macOS awk（版本 20200816）在
# UTF-8 locale 下处理多字节大文件死于 `towc: multibyte conversion failure`——多字节
# 转换在读取缓冲边界误判，4491 行真实原型 100% 复现且死亡被吞（静默空清单 + exit 0，
# 正是本规范要杀的失效形态）。实测 LC_ALL=C 同文件 4491 行全过（行为密度 139+：
# addEventListener 101 / setTimeout 34 / setInterval 3 / window.open 1）。故脚本顶部
# `export LC_ALL=C` 强制字节语义，覆盖 awk/grep/sed 全部输入处理；副作用：detail/target
# 的 80/60 字符截断按字节计，可能切开多字节字符——门禁消费面（grep 对账 + E100 hash）
# 不受影响。
#
# 抽取 pattern 组：
#   addEventListener\(['"]、内联 on(click|change|input|submit|mouseover|mouseout|
#   keydown|keyup|focus|blur|load)=、\.on\(['"]、fetch\(|axios\.|\$\.ajax|
#   XMLHttpRequest、setInterval\(|setTimeout\(、location\.href\s*=|window\.open\(|
#   history\.push。同 (event,target,line) 三元组去重。
#
# 局限：仅静态文本扫描——运行时注册的行为（JS 动态 addEventListener、事件委托、
# 框架渲染后的虚拟 DOM 事件）不可见；target/detail 为行内启发式截取，允许不完美，
# 但行号与 artifact_hash 必须真实（E100 反腐锚点依赖二者）。零依赖：bash 3.2 +
# grep/awk/sed/shasum(或 sha256sum)；set -u（刻意不用 set -e：grep 无匹配是常态）。
#
# 自测样例（内联，覆盖全部 pattern 组 + 元素枚举；验收断言写死于注释）：
#   <button id="b1" onclick="save()">存</button>                       → click 行 + element(button) 行
#   <input id="i1" oninput="f()">                                      → input 行 + element(input) 行
#   <form onsubmit="g()"><div onmouseover="pop()">x</div></form>       → submit+overlay 行 + element(form) 行
#   <a onclick="location.href='/list'">go</a>                          → click+nav 行 + element(a) 行
#   document.getElementById("b1").addEventListener("click", save);     → 1 行 click
#   $("#f").on("change", h);                                           → 1 行 change
#   fetch("/api/x"); axios.get("/y"); $.ajax("/z"); new XMLHttpRequest(); → 4 行 fetch
#   setTimeout(tick, 100); setInterval(beat, 1000);                    → 2 行 timer
#   window.open("/w"); history.pushState({}, "", "/p");                → 2 行 nav
#   断言①：total_behaviors == 20 且数据行数 == 20（行为 16 + 元素 4，去重后；
#          元素行在行为行之后按行续编号）。
#   断言①b（CHG-044）：首行含 kind=element 且 event=="button"、target=="#b1"；
#          <input type="hidden"> 不出元素行。
#   断言②：首行 schema 字段序 artifact/artifact_hash/total_behaviors，
#          artifact_hash 为 64 位小写 hex；首条数据行 id=="BHV-001"、kind=="click"、
#          status=="pending"、line==1。
#   断言③（v3.68.0 回测后追加）：中文多字节文案样例（onclick + addEventListener）
#          exit 0 且 total_behaviors>0（locale 回归守卫）；零 pattern 纯静态 HTML
#          exit 3 且 stderr 含「零行为」诊断（fail-closed 空产出守卫）。
#   （回归锚：tests/run-tests.sh T53 TC-1128/1231/1232 + T54 TC-1234~1238。）
set -u
set -o pipefail
# v3.68.0 回测 record 687（CHG-043）：locale 钉死——macOS awk 20200816 在 UTF-8 locale
# 对多字节大文件死于 towc multibyte conversion failure（缓冲边界缺陷，4491 行 100% 复现，
# 死亡被吞=静默空清单 exit 0）；LC_ALL=C 整文件全过。覆盖脚本内全部 awk/grep/sed。
export LC_ALL=C

usage_rc2() {
  echo "behavior-extract: usage: behavior-extract.sh <artifact.html|htm|js>" >&2
  echo "behavior-extract: 非 .html/.htm/.js 输入走降级路径：人工枚举行为行（沿用 JSONL schema），并在 01-spec 声明行写明理由（v3.68.0 CHG-043 §2.5 阶段 1）" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage_rc2
f="$1"
[[ -f "$f" ]] || { echo "behavior-extract: artifact not found: $f" >&2; exit 2; }
case "$f" in
  *.html|*.htm|*.js) ;;
  *) usage_rc2 ;;
esac

hash=""
if command -v shasum >/dev/null 2>&1; then
  hash=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  hash=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
fi
[[ "$hash" =~ ^[0-9a-f]{64}$ ]] \
  || { echo "behavior-extract: cannot compute sha256 (shasum/sha256sum both unavailable) — GATE-E100 anchoring impossible" >&2; exit 2; }

rows_file=$(mktemp "${TMPDIR:-/tmp}/behavior-extract.XXXXXX") || exit 2
trap 'rm -f "$rows_file"' EXIT

# 单趟 awk：每行先算 target/detail（行内启发式），再按四个 pattern 族循环匹配；
# 族内 while(match) 推进消费串，跨族重复由 (event,target,line) 三元组去重兜底。
awk -v rows_out="$rows_file" '
function esc(s) { gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return s }
function kindof(ev,   k) {
  k="state"
  if (ev=="click") k="click"
  else if (ev=="input") k="input"
  else if (ev=="change") k="change"
  else if (ev=="submit") k="submit"
  else if (ev=="mouseover" || ev=="mouseout") k="overlay"
  else if (ev=="fetch" || ev=="axios" || ev=="ajax" || ev=="$.ajax" || ev=="XMLHttpRequest") k="fetch"
  else if (ev=="setInterval" || ev=="setTimeout") k="timer"
  else if (ev=="location.href" || ev=="window.open" || ev=="history.push") k="nav"
  return k
}
# 去重键含 kind：行为行 (kind,event,target,line) 三元组语义不变（同 event 必同 kind），
# 且隔离元素行与行为行（如 <input oninput> 的 kind=input 行 vs kind=element 行）。
function emit(ev, kd, tg,   key) {
  key=kd SUBSEP ev SUBSEP tg SUBSEP NR
  if (key in seen) return
  seen[key]=1
  printf "{\"kind\":\"%s\",\"event\":\"%s\",\"target\":\"%s\",\"line\":%d,\"detail\":\"%s\",\"status\":\"pending\"}\n", \
    kd, esc(ev), esc(tg), NR, det >> rows_out
}
{
  sub(/\r$/, "")
  det=$0
  sub(/^[[:space:]]+/, "", det)
  det=substr(det, 1, 80)
  det=esc(det)
  # target 启发式优先级：id 属性 → #选择器 → getElementById → querySelector → HTML 标签名 → 接收者变量
  tgt=""
  if (match($0, /id=["\047][^"\047]+["\047]/)) {
    tgt=substr($0, RSTART+4, RLENGTH-5)
  } else if (match($0, /#[A-Za-z_][A-Za-z0-9_-]*/)) {
    tgt=substr($0, RSTART, RLENGTH)
  } else if (match($0, /getElementById\(["\047][^"\047]*/)) {
    tgt=substr($0, RSTART+16, RLENGTH-16)
  } else if (match($0, /querySelector(All)?\(["\047][^"\047]+["\047]/)) {
    tgt=substr($0, RSTART, RLENGTH)
    sub(/^querySelector(All)?\(["\047]/, "", tgt)
  } else if (match($0, /<[A-Za-z][A-Za-z0-9]*/)) {
    tgt=substr($0, RSTART+1, RLENGTH-1)
  } else if (match($0, /[A-Za-z_$][A-Za-z0-9_$.]*[[:space:]]*\.(on|addEventListener|onclick|oninput|onchange|onsubmit)\(["\047]?/)) {
    tgt=substr($0, RSTART, RLENGTH)
    sub(/[[:space:]]*\.(on|addEventListener|onclick|oninput|onchange|onsubmit).*/, "", tgt)
  }
  if (length(tgt) > 60) tgt=substr(tgt, 1, 60)
  # 族 1：内联 on(click|change|input|submit|mouseover|mouseout|keydown|keyup|focus|blur|load)=
  # （POSIX awk 无 \b 词界——去掉前缀锚，误报面由"后随 ="收窄；onchange/onclick 等
  #   JS 属性赋值形态 `el.onclick =` 也在本族覆盖）
  rest=$0
  while (match(rest, /on(click|change|input|submit|mouseover|mouseout|keydown|keyup|focus|blur|load)[[:space:]]*=/)) {
    ev=substr(rest, RSTART+2, RLENGTH-2)
    sub(/[[:space:]]*=+$/, "", ev)
    emit(ev, kindof(ev), tgt)
    rest=substr(rest, RSTART+RLENGTH)
  }
  # 族 2：addEventListener("x") / .on("x") —— 匹配止于开引号，事件字面量到下一个同种引号
  rest=$0
  while (match(rest, /(addEventListener\(|\.on\()["\047]/)) {
    q=substr(rest, RSTART+RLENGTH-1, 1)
    after=substr(rest, RSTART+RLENGTH)
    k=index(after, q)
    if (k < 2) break
    ev=substr(after, 1, k-1)
    emit(ev, kindof(ev), tgt)
    rest=substr(after, k)
  }
  # 族 3：fetch( | axios. | $.ajax | XMLHttpRequest
  rest=$0
  while (match(rest, /fetch\(|axios\.|\$\.ajax|XMLHttpRequest/)) {
    ev=substr(rest, RSTART, RLENGTH)
    sub(/[.(]$/, "", ev)
    emit(ev, "fetch", tgt)
    rest=substr(rest, RSTART+RLENGTH)
  }
  # 族 4：setInterval( | setTimeout(
  rest=$0
  while (match(rest, /setInterval\(|setTimeout\(/)) {
    ev=substr(rest, RSTART, RLENGTH)
    sub(/\($/, "", ev)
    emit(ev, "timer", tgt)
    rest=substr(rest, RSTART+RLENGTH)
  }
  # 族 5：location.href= | window.open( | history.push
  rest=$0
  while (match(rest, /location\.href[[:space:]]*=|window\.open\(|history\.push/)) {
    ev=substr(rest, RSTART, RLENGTH)
    sub(/[[:space:]]*=$/, "", ev)
    sub(/\($/, "", ev)
    emit(ev, "nav", tgt)
    rest=substr(rest, RSTART+RLENGTH)
  }
  # 族 6（G14e，CHG-044）：交互元素枚举 —— 词表唯一权威见头注释；每行至多一条元素行
  #（tag 面优先、属性面兜底）；排除面整行跳过；行内含 `<tag` 才判（HTML 上下文，含
  # JS 内嵌模板行）。元素行与行为行 on*= 冗余并存（CHG-044 方案 A 已裁定）。
  if ($0 !~ /aria-hidden=["\047]?true/ && $0 !~ /role=["\047]?(presentation|none)/ \
      && match($0, /<[A-Za-z][A-Za-z0-9]*/)) {
    etag=tolower(substr($0, RSTART+1, RLENGTH-1))
    ehit=0
    # 标签面：button / input（排除 type=hidden）/ select / textarea / a[href] /
    # area[href] / label[for=] / details —— a|area 的 href 判定放宽为行级（onclick
    # 内 location.href 赋值形态同样是链接语义）
    if (etag=="button" || etag=="select" || etag=="textarea" || etag=="details") ehit=1
    else if (etag=="input" && $0 !~ /type=["\047]?hidden/) ehit=1
    else if ((etag=="a" || etag=="area") && $0 ~ /href=/) ehit=1
    else if (etag=="label" && $0 ~ /for=/) ehit=1
    # 属性面（任意标签）：contenteditable / role 封闭集 / tabindex≥0 / data-action= /
    # hx-get|hx-post|hx-trigger|hx-on= / 内联 on*=
    if (!ehit && ($0 ~ /contenteditable/ \
        || $0 ~ /role=["\047]?(button|checkbox|radio|switch|tab|menuitem|option|slider|spinbutton|textbox|combobox|link)/ \
        || $0 ~ /tabindex=["\047]?(0|[1-9][0-9]*)/ \
        || $0 ~ /data-action=/ \
        || $0 ~ /hx-(get|post|trigger|on)=/ \
        || $0 ~ /on(click|change|input|submit|mouseover|mouseout|keydown|keyup|focus|blur|load)[[:space:]]*=/)) ehit=1
    if (ehit) {
      # 元素行 target 三态：#<id> → .<class 首 token> → <<tag>> 兜底
      etgt="<" etag ">"
      if (match($0, /id=["\047][^"\047]+["\047]/)) {
        etgt="#" substr($0, RSTART+4, RLENGTH-5)
      } else if (match($0, /class=["\047][^"\047]+["\047]/)) {
        ecl=substr($0, RSTART+7, RLENGTH-8)
        sub(/[[:space:]].*$/, "", ecl)
        etgt="." ecl
      }
      if (length(etgt) > 60) etgt=substr(etgt, 1, 60)
      emit(etag, "element", etgt)
    }
  }
}
' "$f"
bext_awk_rc=$?
if [[ "$bext_awk_rc" -ne 0 ]]; then
  # fail-closed：awk 中途死亡（如 towc multibyte 缺陷残余形态）绝不带半截清单 exit 0
  echo "behavior-extract: extraction died (awk rc=$bext_awk_rc) — 已强制 LC_ALL=C 仍失败，请检查文件编码/二进制混杂（v3.68.0 回测 record 687）" >&2
  exit 3
fi

total=$(grep -c . "$rows_file" 2>/dev/null || true)
[[ "$total" =~ ^[0-9]+$ ]] || total=0
if [[ "$total" -eq 0 ]]; then
  # fail-closed 空产出（v3.68.0 回测 record 687）：零行为=抽取失败而非事实，禁止静默空清单过门
  echo "behavior-extract: 零行为=抽取失败而非事实：已强制 LC_ALL=C（macOS awk towc multibyte 缓冲缺陷，CHG-043 回测 record 687），若仍为空请检查文件编码/是否为非交互式工件" >&2
  exit 3
fi

# 输出：首行头（artifact 原样、hash、total）+ BHV-001 递增编号的数据行
{
  printf '{"artifact":"%s","artifact_hash":"%s","total_behaviors":%s}\n' \
    "$(printf '%s' "$f" | sed 's/\\/\\\\/g; s/"/\\"/g')" "$hash" "$total"
  awk '{ sub(/^\{/, ""); printf "{\"id\":\"BHV-%03d\",%s\n", NR, $0 }' "$rows_file"
}
exit 0
