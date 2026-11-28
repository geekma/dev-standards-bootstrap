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
  resources/templates/lib-gate-staged.sh
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
  # v4.4.0 (CHG-148, FU-1012): the receipt version derives from the DS footer
  # inside the gate — assert the derivation is wired, not a (now forbidden)
  # hardcoded literal. A version bump no longer edits the gate.
  # v4.13.0 (CHG-158): validate_stop() lives in warm tier lib-gate-staged.sh.
  eq "gate receipt version derives from DS footer (template)" "$(grep -cF 'gate_receipt_json "$vc_gver"' resources/templates/lib-gate-staged.sh || true)" "1"
  eq "gate receipt version compares derived (template)" "$(grep -cF '"$vc_r_ver" == "$vc_gver"' resources/templates/lib-gate-staged.sh || true)" "1"
  # scripts/agent-gate is a gitignored local mirror or single-source exec wrapper
  # (ITEM-43), so absence is legal on a fresh clone; when present it must either
  # be byte-identical OR wrap resources/templates/agent-gate.sh directly.
  if [[ -f scripts/agent-gate ]]; then
    local _ag_ok="no"
    if cmp -s scripts/agent-gate resources/templates/agent-gate.sh; then
      _ag_ok="yes"
    elif grep -qF '# single-source wrapper -> resources/templates/agent-gate.sh' scripts/agent-gate \
      && grep -qF 'exec bash' scripts/agent-gate; then
      _ag_ok="yes"
    fi
    eq "gate mirror byte-identical or single-source wrapper" "$_ag_ok" "yes"
  fi
  if [[ -f scripts/lib-gate-staged.sh ]]; then
    eq "gate receipt version derives from DS footer (staged mirror)" "$(grep -cF 'gate_receipt_json "$vc_gver"' scripts/lib-gate-staged.sh || true)" "1"
    eq "gate receipt version compares derived (staged mirror)" "$(grep -cF '"$vc_r_ver" == "$vc_gver"' scripts/lib-gate-staged.sh || true)" "1"
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
  # v4.4.0 (CHG-148, FU-1012): the gate no longer carries version literals —
  # its receipt version derives from the DS footer at runtime, so a bump has
  # nothing to rewrite there (the old gate seds became dead code and were removed).
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

checksum_files() {
  (
    cd "$ROOT"
    {
      printf '%s\n' SKILL.md \
        scripts/bootstrap.sh scripts/install.sh scripts/release.sh \
        scripts/friction-report.sh scripts/mcp-governance-server.sh scripts/dev/sync-local-wrappers.sh \
        scripts/lib-suite-tree-fingerprint.sh scripts/lib-suite-lock.sh scripts/shard-sum.sh scripts/evidence-round.sh \
        tests/run-tests.sh tests/fresh-clone-check.sh tests/lib/test-harness.sh \
        resources/DEVELOPMENT_STANDARDS.md resources/AGENTS.md resources/CLAUSE_REGISTRY.md \
        resources/METHODOLOGY.md resources/STAGE_PLAYBOOK.md resources/STANDARDS_CHANGELOG.md \
        resources/templates/pre-commit resources/templates/pre-push resources/templates/commit-msg \
        resources/templates/agent-governance.yml
      for _cf in resources/templates/*.sh resources/templates/github-*.yml tests/suites/suite-*.sh; do
        [[ -f "$_cf" ]] && printf '%s\n' "$_cf"
      done
    } | LC_ALL=C sort -u
  )
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "release: neither shasum nor sha256sum found" >&2
    return 2
  fi
}

checksums() {
  local mode="write" f h sums="$ROOT/SHA256SUMS"
  [[ "${1:-}" == "--check" ]] && mode="check"
  if [[ -n "${1:-}" && "${1:-}" != "--check" ]]; then
    echo "usage: release.sh checksums [--check]" >&2; exit 2
  fi
  if [[ "$mode" == "write" ]]; then
    local tmp; tmp=$(mktemp) || exit 2
    while IFS= read -r f; do
      [[ -f "$ROOT/$f" ]] || { echo "release: missing checksum target $f" >&2; rm -f "$tmp"; exit 2; }
      h=$(sha256_file "$ROOT/$f") || { rm -f "$tmp"; exit 2; }
      printf '%s  %s\n' "$h" "$f" >> "$tmp"
    done < <(checksum_files)
    chmod 0644 "$tmp" && mv "$tmp" "$sums"
    echo "release: wrote $(wc -l < "$sums" | tr -d ' ') checksums to SHA256SUMS"
    return 0
  fi
  [[ -s "$sums" ]] || { echo "FAIL SHA256SUMS missing or empty" >&2; return 1; }
  local bad=0 line exp rel got
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    exp="${line%% *}"
    rel="${line#*  }"
    if [[ ! -f "$ROOT/$rel" ]]; then
      echo "FAIL checksum missing file: $rel" >&2; bad=1; continue
    fi
    got=$(sha256_file "$ROOT/$rel") || return 2
    if [[ "$got" != "$exp" ]]; then
      echo "FAIL checksum mismatch: $rel" >&2; bad=1
    fi
  done < "$sums"
  while IFS= read -r f; do
    if ! awk -v tgt="$f" 'length($1)==64 && $1 ~ /^[0-9a-f]+$/ && substr($0,67)==tgt {ok=1; exit} END{exit !ok}' "$sums" 2>/dev/null; then
      echo "FAIL SHA256SUMS missing tracked entry: $f" >&2; bad=1
    fi
  done < <(checksum_files)
  if [[ "$bad" -eq 0 ]]; then
    echo "release: checksums PASS ($(wc -l < "$sums" | tr -d ' ') files verified)"
    return 0
  fi
  return 1
}

case "${1:-check}" in
  check) check ;;
  bump) shift; bump "${1:-}" ;;
  tag) shift; tag "${1:-}" ;;
  checksums) shift; checksums "${1:-}" ;;
  *) echo "usage: release.sh check|bump <X.Y.Z>|tag [<X.Y.Z>]|checksums [--check]" >&2; exit 2 ;;
esac
