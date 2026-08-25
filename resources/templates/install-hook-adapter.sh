#!/usr/bin/env bash
# Generate the client-specific hook adapter for the AI coding tool in use.
# Every supported client schema lives here as the single source of truth:
# no per-tool JSON files to maintain, and scripts/agent-gate stays the only
# validator. Tools without a known hook schema are enforced by the Git hooks
# and the CI workflow instead — those validate the repository, not the editor.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-hook-adapter.sh [claude|cursor|gemini] [--force]

With no argument the current tool is auto-detected from environment variables
(CLAUDECODE, CURSOR_AGENT/CURSOR_TRACE_ID, GEMINI_CLI). Writes the adapter
config for that tool:
  claude  -> .claude/settings.json
  cursor  -> .cursor/hooks.json
  gemini  -> .gemini/settings.json

An existing config with different content is never overwritten silently: the
diff is shown and the script exits 2 unless --force is given.
EOF
}

force=false
tool=""
for arg in "$@"; do
  case "$arg" in
    claude|cursor|gemini) tool="$arg" ;;
    --force) force=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install-hook-adapter: unknown argument '$arg'" >&2; usage >&2; exit 2 ;;
  esac
done

# Auto-detect: the hook only needs to exist for the client running right now.
if [[ -z "$tool" ]]; then
  if [[ "${CLAUDECODE:-}" == 1 ]]; then tool=claude
  elif [[ -n "${CURSOR_AGENT:-}" || -n "${CURSOR_TRACE_ID:-}" ]]; then tool=cursor
  elif [[ "${GEMINI_CLI:-}" == 1 ]]; then tool=gemini
  fi
fi

if [[ -z "$tool" ]]; then
  cat >&2 <<'EOF'
install-hook-adapter: no supported tool detected or specified.

Clients with a known hook schema: claude, cursor, gemini (pass the name as an
argument). For every other client, pre-write hooks are not the enforcement
path: the .githooks Git hooks and the agent-governance CI workflow already
cover all clients, because they validate the repository, not the editor.
EOF
  exit 0
fi

if [[ ! -x scripts/agent-gate ]]; then
  echo "install-hook-adapter: scripts/agent-gate not found or not executable." >&2
  echo "Install the enforcement package first (copy agent-gate.sh to scripts/agent-gate, chmod +x)." >&2
  exit 2
fi

adapter_content() {
  case "$1" in
    claude) cat <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "scripts/agent-gate --stage pre-write"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "scripts/agent-gate --stage stop"
          }
        ]
      }
    ]
  }
}
JSON
    ;;
    cursor) cat <<'JSON'
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "matcher": "Write",
        "command": "scripts/agent-gate --stage pre-write"
      }
    ],
    "stop": [
      {
        "command": "scripts/agent-gate --stage stop"
      }
    ]
  }
}
JSON
    ;;
    gemini) cat <<'JSON'
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "write_file|replace",
        "hooks": [
          {
            "type": "command",
            "command": "scripts/agent-gate --stage pre-write",
            "name": "agent-governance-pre-write"
          }
        ]
      }
    ]
  }
}
JSON
    ;;
  esac
}

target_path() {
  case "$1" in
    claude) echo .claude/settings.json ;;
    cursor) echo .cursor/hooks.json ;;
    gemini) echo .gemini/settings.json ;;
  esac
}

path=$(target_path "$tool")
content=$(adapter_content "$tool")

if [[ -e "$path" ]]; then
  if [[ "$content" == "$(cat "$path")" ]]; then
    echo "install-hook-adapter: $path already up to date."
    exit 0
  fi
  if [[ "$force" != true ]]; then
    echo "install-hook-adapter: $path exists with different content, diff:" >&2
    diff -u "$path" <(printf '%s\n' "$content") >&2 || true
    echo "Re-run with --force to overwrite, or merge the hooks manually." >&2
    exit 2
  fi
fi

mkdir -p "$(dirname "$path")"
printf '%s\n' "$content" > "$path"
echo "install-hook-adapter: wrote $path for $tool (all hooks call scripts/agent-gate)."
