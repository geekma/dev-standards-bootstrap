#!/usr/bin/env bash
# release.sh — source-layer release consistency (NOT shipped with the Skill).
#
#   release.sh check              # all carriers == DS footer; non-zero on drift
#   release.sh bump <X.Y.Z>       # rewrite carriers to X.Y.Z, then check
#   release.sh tag [<X.Y.Z>]      # check, then create annotated tag v<X.Y.Z>
#
# Why: v3.37.1 shipped four versions with plugin.json/marketplace.json drifting
# (A24 existence checks could not see it), and v3.85.0 still required hand-editing
# SKILL (4 sites), DS footer, AGENTS footer, README x2 (3 sites each), manifests x2,
# methodology footers, gate_version, and test pins. One missed carrier = a lying
# "latest version" badge. `bump` is deliberately mechanical; the CHANGELOG top row
# is NOT generated (its prose is human-authored) — `bump` refuses unless the row
# for the new version already exists, so the release note is written first.
#
# Zero deps: bash 3.2+, grep, sed. No network, no git mutation except local tag.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2

CARRIERS=(
  SKILL.md
  README.md
  README.zh-CN.md
  resources/DEVELOPMENT_STANDARDS.md
  resources/AGENTS.md
  resources/METHODOLOGY.md
  .claude-plugin/plugin.json
  .claude-plugin/marketplace.json
  resources/templates/agent-gate.sh
)

fail=0
pass=0
ok()   { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL %s\n' "$1" >&2; }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected $3, got $2)"; fi; }
count(){ grep -cF -- "$2" "$1" 2>/dev/null || true; }

footer_version() {
  sed -nE 's/.*规范版本：v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$1" 2>/dev/null | head -1
}

sed_i() { # file args...
  local f="$1"; shift
  if sed --version >/dev/null 2>&1; then sed -i "$@" "$f"; else sed -i '' "$@" "$f"; fi
}

check() {
  local v; v=$(footer_version resources/DEVELOPMENT_STANDARDS.md)
  [[ -n "$v" ]] || { bad "cannot read DS footer version"; return 1; }
  echo "release: checking carriers for v$v"
  eq "SKILL frontmatter version" "$(sed -nE 's/^version: ([0-9.]+)$/\1/p' SKILL.md | head -1)" "$v"
  eq "SKILL current-version occurrences" "$(count SKILL.md "v$v")" "3"
  eq "AGENTS footer version" "$(sed -nE 's/.*当前对应规范版本：v([0-9.]+).*/\1/p' resources/AGENTS.md | head -1)" "$v"
  eq "README en current-version occurrences" "$(count README.md "$v")" "3"
  eq "README zh current-version occurrences" "$(count README.zh-CN.md "$v")" "3"
  eq "plugin.json version" "$(grep -m1 -oE '"version": "[0-9.]+"' .claude-plugin/plugin.json | grep -oE '[0-9.]+' || true)" "$v"
  eq "marketplace.json version" "$(grep -m1 -oE '"version": "[0-9.]+"' .claude-plugin/marketplace.json | grep -oE '[0-9.]+' || true)" "$v"
  local top; top=$(grep -m1 -oE '^\| v[0-9.]+' resources/STANDARDS_CHANGELOG.md | grep -oE '[0-9.]+' || true)
  eq "CHANGELOG top row" "$top" "$v"
  eq "METHODOLOGY footer" "$(footer_version resources/METHODOLOGY.md)" "$v"
  local m bad_m=0; for m in resources/methodologies/*.md; do
    [[ -e "$m" ]] || continue
    [[ "$(footer_version "$m")" == "$v" ]] || { bad_m=$((bad_m+1)); bad "methodology footer $m"; }
  done
  eq "methodology footer coverage" "$bad_m" "0"
  eq "gate_version write literal (template)" "$(grep -cF "\"gate_version\":\"$v\"" resources/templates/agent-gate.sh || true)" "1"
  eq "gate_version compare literal (template)" "$(grep -cF "\"\$vc_r_ver\" == \"$v\"" resources/templates/agent-gate.sh || true)" "1"
  # scripts/agent-gate is a gitignored local mirror (source layout), so absence is
  # legal on a fresh clone; when present it must be byte-identical (checked below).
  if [[ -f scripts/agent-gate ]]; then
    eq "gate mirror byte-identical" "$([[ "$(cmp -s scripts/agent-gate resources/templates/agent-gate.sh; echo $?)" == "0" ]] && echo yes || echo no)" "yes"
    eq "gate_version write literal (mirror)" "$(grep -cF "\"gate_version\":\"$v\"" scripts/agent-gate || true)" "1"
    eq "gate_version compare literal (mirror)" "$(grep -cF "\"\$vc_r_ver\" == \"$v\"" scripts/agent-gate || true)" "1"
  fi
  # tracked-carrier check: a carrier outside git can never ship with a tag.
  if git rev-parse --git-dir >/dev/null 2>&1; then
    local f; for f in "${CARRIERS[@]}"; do
      git ls-files --error-unmatch "$f" >/dev/null 2>&1 || bad "carrier not tracked by git: $f"
    done
    ok "all carriers tracked by git"
  fi
  echo "release: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

bump() {
  local old new; new="${1:-}"
  [[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: release.sh bump <X.Y.Z>" >&2; exit 2; }
  old=$(footer_version resources/DEVELOPMENT_STANDARDS.md)
  [[ -n "$old" ]] || { echo "release: cannot read DS footer version" >&2; exit 2; }
  [[ "$old" != "$new" ]] || { echo "release: already at v$new" >&2; exit 0; }
  # The changelog row is authored, not generated. Require it before touching carriers.
  if ! grep -qE "^\| v${new//./\\.} " resources/STANDARDS_CHANGELOG.md; then
    echo "release: add the v$new row to resources/STANDARDS_CHANGELOG.md first (prose is human-authored)" >&2
    exit 2
  fi
  local f
  # Update only declared carrier sites. A blanket s/vOLD/vNEW/ would rewrite
  # historical provenance (e.g. "added in v3.85.0, CHG-112"), violating the
  # append-only history rule and inflating the occurrence counts check enforces.
  sed_i SKILL.md \
    -e "s/^version: $old$/version: $new/" \
    -e "s/当前携带规范版本 v$old/当前携带规范版本 v$new/" \
    -e "s/当前携带版本：v$old/当前携带版本：v$new/" \
    -e "s/当前携带版本 v$old/当前携带版本 v$new/"
  sed_i README.md \
    -e "s|badge/Standards-v$old-green.svg|badge/Standards-v$new-green.svg|" \
    -e "s|Full standards document v$old|Full standards document v$new|" \
    -e "s/\*\*Standards Version:\*\* v$old/**Standards Version:** v$new/"
  sed_i README.zh-CN.md \
    -e "s|badge/规范版本-v$old-green.svg|badge/规范版本-v$new-green.svg|" \
    -e "s|完整规范文档 v$old|完整规范文档 v$new|" \
    -e "s/\*\*规范版本：\*\* v$old/**规范版本：** v$new/"
  sed_i resources/AGENTS.md -e "s/当前对应规范版本：v$old/当前对应规范版本：v$new/"
  sed_i resources/DEVELOPMENT_STANDARDS.md -e "s/规范版本：v$old/规范版本：v$new/"
  for f in resources/METHODOLOGY.md resources/methodologies/*.md; do
    sed_i "$f" -e "s/当前对应规范版本：v$old/当前对应规范版本：v$new/"
  done
  for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
    sed_i "$f" -e "s/\"version\": \"$old\"/\"version\": \"$new\"/"
  done
  for f in resources/templates/agent-gate.sh scripts/agent-gate; do
    [[ -f "$f" ]] || continue
    sed_i "$f" \
      -e "s/\"gate_version\":\"$old\"/\"gate_version\":\"$new\"/g" \
      -e "s/\"\\\$vc_r_ver\" == \"$old\"/\"\\\$vc_r_ver\" == \"$new\"/g"
  done
  echo "release: bumped v$old -> v$new"
  check
}

tag() {
  local v; v="${1:-$(footer_version resources/DEVELOPMENT_STANDARDS.md)}"
  check || exit 2
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "release: not a git repository" >&2; exit 2; }
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "release: working tree is dirty — commit the release before tagging (the tag would point at pre-bump content)" >&2
    exit 2
  fi
  if git rev-parse -q --verify "refs/tags/v$v" >/dev/null 2>&1; then
    echo "release: tag v$v already exists" >&2; exit 2
  fi
  git tag -a "v$v" -m "dev-standards-bootstrap v$v"
  echo "release: created annotated tag v$v (not pushed)"
}

case "${1:-check}" in
  check) check ;;
  bump) shift; bump "${1:-}" ;;
  tag) shift; tag "${1:-}" ;;
  *) echo "usage: release.sh check|bump <X.Y.Z>|tag [<X.Y.Z>]" >&2; exit 2 ;;
esac
