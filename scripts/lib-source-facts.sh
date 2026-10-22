#!/usr/bin/env bash
# lib-source-facts.sh — shared read-only facts for the source-layer toolchain
# (facts / verify-all / pre-review-check / mutation-check / ci-summary /
# batch-metrics). Source-layer only (NOT shipped with the Skill).
#
# Everything here is a pure read: git queries, file reads, mtime checks. No
# network, no suite run, no repo mutation. Consumers source this file; it defines
# functions only and has no top-level side effects.
#
# Bash 3.2 compatible (macOS): no associative arrays, no ${var,,}, no mapfile.
# Zero deps: bash, git, sed, tr, date, stat.

sf_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

sf_json_escape() {
  printf '%s' "${1-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '
}

sf_json_str() { printf '"%s"' "$(sf_json_escape "${1-}")"; }

sf_json_str_or_null() {
  if [ -n "${1-}" ]; then sf_json_str "$1"; else printf 'null'; fi
}

sf_json_num_or_null() {
  case "${1-}" in
    ''|*[!0-9]*) printf 'null' ;;
    *) printf '%s' "$1" ;;
  esac
}

sf_read_json_str() { # file key
  sed -nE "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$1" 2>/dev/null | tail -n 1
}

# Top-level status of a verify-all receipt. sf_read_json_str takes the LAST match,
# and a verify receipt carries a "status" inside every step as well as at the top
# level — reading it generically returns the suite step, so a batch whose audit
# failed got ledgered as "pass" (v3.87.0 R4, self-caught during the final
# measurement pass). verify-all writes the top-level key at two-space indentation
# and the steps inline, so anchoring on that indentation is exact.
sf_verify_status() { # verify-receipt file
  [ -f "$1" ] || return 0
  sed -nE 's/^  "status"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$1" 2>/dev/null | head -n 1
}

sf_read_json_num() { # file key
  sed -nE "s/.*\"$2\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$1" 2>/dev/null | tail -n 1
}

sf_repo_head() { git -C "$1" rev-parse HEAD 2>/dev/null || true; }

sf_repo_branch() { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || true; }

sf_ds_version() { # root — DS footer is the declared sole version authority
  sed -nE 's/.*规范版本：v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' \
    "$1/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null | head -n 1
}

sf_active_change() { # root
  local f
  f=$(git -C "$1" rev-parse --git-path agent-governance/active-change 2>/dev/null || true)
  [ -n "$f" ] || return 0
  case "$f" in /*) ;; *) f="$1/$f" ;; esac
  [ -s "$f" ] && tr -d '[:space:]' < "$f"
}

sf_suite_receipt_path() { # root
  printf '%s\n' "${AGENT_GUARD_SUITE_RECEIPT_PATH:-$1/.agent-state/last-suite-receipt.json}"
}

sf_receipt_max_age_min() {
  local m="${AGENT_GUARD_SUITE_RECEIPT_MAX_AGE_MIN:-30}"
  case "$m" in ''|*[!0-9]*) m=30 ;; esac
  printf '%s\n' "$m"
}

sf_tree_fingerprint() { # root
  if ! command -v suite_tree_fingerprint >/dev/null 2>&1; then
    [ -f "$1/scripts/lib-suite-tree-fingerprint.sh" ] \
      && source "$1/scripts/lib-suite-tree-fingerprint.sh"
  fi
  command -v suite_tree_fingerprint >/dev/null 2>&1 || { printf ''; return 0; }
  suite_tree_fingerprint "$1"
}

sf_receipt_fresh() { # root [fingerprint] -> 0 fresh, 1 stale/missing
  local root="$1" fp="${2-}" receipt r_head r_fp r_fail r_mtime age max
  receipt=$(sf_suite_receipt_path "$root")
  [ -f "$receipt" ] || return 1
  max=$(sf_receipt_max_age_min)
  [ "$max" != "0" ] || return 1
  [ -n "$fp" ] || fp=$(sf_tree_fingerprint "$root")
  [ -n "$fp" ] || return 1
  r_head=$(sf_read_json_str "$receipt" head)
  r_fp=$(sf_read_json_str "$receipt" tree_fingerprint)
  r_fail=$(sf_read_json_num "$receipt" failed)
  [ -n "$r_head" ] && [ "$r_head" = "$(sf_repo_head "$root")" ] || return 1
  [ -n "$r_fp" ] && [ "$r_fp" = "$fp" ] || return 1
  [ "$r_fail" = "0" ] || return 1
  r_mtime=$(stat -c %Y "$receipt" 2>/dev/null || stat -f %m "$receipt" 2>/dev/null || true)
  case "$r_mtime" in ''|*[!0-9]*) return 1 ;; esac
  age=$(( $(date +%s) - r_mtime ))
  [ "$age" -le $(( max * 60 )) ] || return 1
  return 0
}

sf_baseline_num() { # file
  local n
  [ -f "$1" ] || return 0
  n=$(tr -d '[:space:]' < "$1" 2>/dev/null || true)
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  printf '%s\n' "$n"
}

sf_changed_files() { # root — NUL-safe-ish line list (one path per line)
  git -C "$1" status --porcelain 2>/dev/null | sed -e 's/^...//'
}

sf_emit_facts() { # root -> JSON on stdout
  local root="$1" head branch version fp receipt r_exists r_head r_fp r_pass r_fail r_wall r_gen fresh
  local audit_base suite_base active dirty_count changed_first
  head=$(sf_repo_head "$root")
  branch=$(sf_repo_branch "$root")
  version=$(sf_ds_version "$root")
  fp=$(sf_tree_fingerprint "$root")
  receipt=$(sf_suite_receipt_path "$root")
  r_exists=false
  r_head=""; r_fp=""; r_pass=""; r_fail=""; r_wall=""; r_gen=""; fresh=false
  if [ -f "$receipt" ]; then
    r_exists=true
    r_head=$(sf_read_json_str "$receipt" head)
    r_fp=$(sf_read_json_str "$receipt" tree_fingerprint)
    r_pass=$(sf_read_json_num "$receipt" passed)
    r_fail=$(sf_read_json_num "$receipt" failed)
    r_wall=$(sf_read_json_num "$receipt" wall_time_s)
    r_gen=$(sf_read_json_str "$receipt" generated_at)
    sf_receipt_fresh "$root" "$fp" && fresh=true
  fi
  audit_base=$(sf_baseline_num "$root/tests/.audit-baseline")
  suite_base=$(sf_baseline_num "$root/tests/.suite-baseline")
  active=$(sf_active_change "$root")
  dirty_count=$(git -C "$root" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  changed_first=$(sf_changed_files "$root" | head -n 200)
  printf '{\n'
  printf '  "schema": 1,\n'
  printf '  "generated_at": %s,\n' "$(sf_json_str "$(sf_now)")"
  printf '  "root": %s,\n' "$(sf_json_str "$root")"
  printf '  "head": %s,\n' "$(sf_json_str_or_null "$head")"
  printf '  "branch": %s,\n' "$(sf_json_str_or_null "$branch")"
  printf '  "version": %s,\n' "$(sf_json_str_or_null "$version")"
  printf '  "tree_fingerprint": %s,\n' "$(sf_json_str_or_null "$fp")"
  printf '  "dirty": %s,\n' "$([ "$dirty_count" -gt 0 ] && echo true || echo false)"
  printf '  "changed_count": %s,\n' "$dirty_count"
  printf '  "changed_files": ['
  local first=1 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$first" -eq 1 ] && first=0 || printf ', '
    printf '%s' "$(sf_json_str "$f")"
  done <<EOF
$changed_first
EOF
  printf '],\n'
  printf '  "active_change": %s,\n' "$(sf_json_str_or_null "$active")"
  printf '  "audit_baseline": %s,\n' "$(sf_json_num_or_null "$audit_base")"
  printf '  "suite_baseline": %s,\n' "$(sf_json_num_or_null "$suite_base")"
  printf '  "suite_receipt": {\n'
  printf '    "path": %s,\n' "$(sf_json_str "$receipt")"
  printf '    "exists": %s,\n' "$r_exists"
  printf '    "fresh": %s,\n' "$fresh"
  printf '    "head": %s,\n' "$(sf_json_str_or_null "$r_head")"
  printf '    "tree_fingerprint": %s,\n' "$(sf_json_str_or_null "$r_fp")"
  printf '    "passed": %s,\n' "$(sf_json_num_or_null "$r_pass")"
  printf '    "failed": %s,\n' "$(sf_json_num_or_null "$r_fail")"
  printf '    "wall_time_s": %s,\n' "$(sf_json_num_or_null "$r_wall")"
  printf '    "generated_at": %s\n' "$(sf_json_str_or_null "$r_gen")"
  printf '  }\n'
  printf '}\n'
}
