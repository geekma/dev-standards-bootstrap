#!/usr/bin/env bash
# lib-suite-lock.sh — source-layer workspace lock for full golden-case runs.
#
# A full run writes .agent-state/last-suite-receipt.json. Two concurrent full runs
# at different tree states can overwrite each other's receipt (observed during the
# v3.85.0 review: 3 suites + 2 audits in one workspace invalidated the fingerprint).
# The receipt contract is "the most recent FULL run was green"; a torn write breaks
# update-assertion-count's trust gate in both directions.
#
# Scope: FULL runs only. Filtered (-T) runs never write the receipt, and the suite
# itself spawns filtered children from T51/T57 — locking those would deadlock.
#
# Env:
#   AGENT_GUARD_SUITE_LOCK_DIR  override lock path (tests / CI isolation)
#   AGENT_GUARD_SUITE_LOCK_GRACE_MIN  empty-pid reclaim grace (default 1 min)
#
# Zero deps: bash 3.2+, mkdir, kill -0. Shipped with the suite (bootstrap --guard).

# Absolute by construction: the dispatcher may leave cwd inside a temp fixture
# when the trap fires, and a relative path would then release the wrong dir.
suite_lock_dir() {
  printf '%s' "${AGENT_GUARD_SUITE_LOCK_DIR:-${ROOT:-$PWD}/.agent-state/suite.lock}"
}

suite_lock_release() {
  local d pid
  d=$(suite_lock_dir)
  pid=$(sed -n '1p' "$d/pid" 2>/dev/null || true)
  # Only the owner may release; a stale takeover may already own the dir.
  [[ "$pid" == "$$" ]] || return 0
  rm -rf "$d" 2>/dev/null || true
}

# 0 = acquired, 1 = another live owner, 2 = filesystem failure.
suite_lock_acquire() {
  local d pid age now mtime grace_min
  d=$(suite_lock_dir)
  mkdir -p "$(dirname "$d")" 2>/dev/null || return 2
  if mkdir "$d" 2>/dev/null; then
    printf '%s\n' "$$" > "$d/pid" 2>/dev/null || true
    return 0
  fi
  pid=$(sed -n '1p' "$d/pid" 2>/dev/null || true)
  case "$pid" in ''|*[!0-9]*) pid="" ;; esac
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    printf 'suite lock held by live pid %s (%s)\n' "$pid" "$d" >&2
    return 1
  fi
  # Corrupt/empty pid (crash between mkdir and write) needs a grace window so a
  # concurrent acquirer cannot steal the dir mid-write; a recorded-but-dead pid
  # is unambiguous and reclaims immediately.
  grace_min="${AGENT_GUARD_SUITE_LOCK_GRACE_MIN:-1}"
  case "$grace_min" in ''|*[!0-9]*) grace_min=1 ;; esac
  now=$(date +%s 2>/dev/null || echo 0)
  mtime=$(stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null || echo 0)
  case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
  age=$((now - mtime))
  if [[ -n "$pid" ]] || [[ "$mtime" -eq 0 ]] || [[ "$age" -gt $((grace_min * 60)) ]]; then
    rm -rf "$d" 2>/dev/null || true
    if mkdir "$d" 2>/dev/null; then
      printf '%s\n' "$$" > "$d/pid" 2>/dev/null || true
      return 0
    fi
  fi
  printf 'suite lock present but owner is unknown and lock is younger than %smin (%s)\n' "$grace_min" "$d" >&2
  return 1
}
