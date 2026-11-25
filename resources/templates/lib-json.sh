#!/usr/bin/env bash
# Zero-dependency JSON & scalar YAML helpers (Bash 3.2+, ITEM-44)
if [[ "${_LIB_JSON_LOADED:-0}" != "1" ]]; then
_LIB_JSON_LOADED=1

json_escape() {
  printf '%s' "${1:-}" | tr '\t\n\r' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

json_field() { # <json-line> <key> -> value (quoted string only; null/missing -> empty)
  local rec="${1:-}" key="${2:-}"
  printf '%s' "$rec" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" 2>/dev/null | head -n 1 || true
}

json_str() { # <json-line> <key> [default] -> string
  local rec="${1:-}" key="${2:-}" def="${3:-}" v=""
  v=$(printf '%s' "$rec" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" | head -n 1 || true)
  [[ -n "$v" ]] && printf '%s' "$v" || printf '%s' "$def"
}

json_bool() { # <json-line> <key> [default=false] -> true|false
  local rec="${1:-}" key="${2:-}" def="${3:-false}" v=""
  v=$(printf '%s' "$rec" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*(true|false)([[:space:],}]|$).*/\1/p" | head -n 1 || true)
  [[ "$v" == "true" || "$v" == "false" ]] && printf '%s' "$v" || printf '%s' "$def"
}

json_int() { # <json-line> <key> [default=0] -> int
  local rec="${1:-}" key="${2:-}" def="${3:-0}" v=""
  v=$(printf '%s' "$rec" | sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*(-?[0-9]+)([[:space:],}]|$).*/\1/p" | head -n 1 || true)
  [[ "$v" =~ ^-?[0-9]+$ ]] && printf '%s' "$v" || printf '%s' "$def"
}

yml_flat_scalar() { # <file> <key> [default] -> scalar without quotes or # comment
  local f="${1:-}" k="${2:-}" def="${3:-}" v=""
  [[ -f "$f" ]] || { printf '%s' "$def"; return 0; }
  v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" "$f" 2>/dev/null \
    | head -n 1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr -d "\"'" || true)
  [[ -n "$v" ]] && printf '%s' "$v" || printf '%s' "$def"
}

is_windows_shell() {
  case "${AGENT_GUARD_FORCE_OS:-$(uname -s 2>/dev/null || echo unknown)}" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

if is_windows_shell; then
  export MSYS_NO_PATHCONV=1
  export MSYS2_ARG_CONV_EXCL='*'
fi

has_real_python3() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1
}
fi
