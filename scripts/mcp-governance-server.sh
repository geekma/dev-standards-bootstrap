#!/usr/bin/env bash
# mcp-governance-server.sh — optional thin read-only MCP stdio wrapper (v4.10.0, CHG-155, ITEM-52)
# Zero dependencies: Bash 3.2+ JSON-RPC 2.0 over stdio exposing read-only agent-gate inspection tools.
set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/.." && pwd)
for _jlib in "$REPO_ROOT/resources/templates/lib-json.sh" "$SELF_DIR/lib-json.sh"; do
  if [[ -f "$_jlib" ]]; then
    # shellcheck source=/dev/null
    . "$_jlib"
    break
  fi
done
if ! command -v json_escape >/dev/null 2>&1; then
  json_escape() { printf '%s' "${1:-}" | tr '\t\n\r' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
fi
if ! command -v json_field >/dev/null 2>&1; then
  json_field() { printf '%s' "${1:-}" | sed -nE "s/.*\"${2:-}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" 2>/dev/null | head -n 1 || true; }
fi

GATE_BIN="$REPO_ROOT/scripts/agent-gate"
[[ -f "$GATE_BIN" ]] || GATE_BIN="$REPO_ROOT/resources/templates/agent-gate.sh"

_rpc_id() {
  local top="${1:-}" v
  top=$(printf '%s' "$top" | sed -E 's/"params"[[:space:]]*:\{.*//')
  v=$(json_field "$top" id)
  if [[ -n "$v" ]]; then printf '"%s"' "$(json_escape "$v")"; return 0; fi
  v=$(printf '%s' "$top" | sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*(-?[0-9]+)([[:space:],}]|$).*/\1/p' | head -n 1 || true)
  [[ "$v" =~ ^-?[0-9]+$ ]] && printf '%s' "$v" || printf 'null'
}

_has_rpc_id() {
  local top
  top=$(printf '%s' "${1:-}" | sed -E 's/"params"[[:space:]]*:\{.*//')
  grep -qE '"id"[[:space:]]*:' <<< "$top"
}

_run_tool() {
  local tname="$1" line="$2" cid="" out="" rc=0
  case "$tname" in
    governance_status)
      out=$(cd "$REPO_ROOT" && bash "$GATE_BIN" status --json 2>&1) || rc=$? ;;
    governance_next)
      cid=$(json_field "$line" change_id)
      if [[ -n "$cid" && ! "$cid" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        printf '{"error":-32602,"message":"invalid change_id"}'
        return 1
      fi
      out=$(cd "$REPO_ROOT" && bash "$GATE_BIN" next ${cid:+"$cid"} --json 2>&1) || rc=$? ;;
    governance_doctor)
      out=$(cd "$REPO_ROOT" && bash "$GATE_BIN" doctor --json 2>&1) || rc=$? ;;
    governance_preflight)
      cid=$(json_field "$line" change_id)
      [[ -n "$cid" && "$cid" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { printf '{"error":-32602,"message":"change_id required"}'; return 1; }
      out=$(cd "$REPO_ROOT" && bash "$GATE_BIN" preflight "$cid" --json 2>&1) || rc=$? ;;
    *)
      printf '{"error":-32601,"message":"unknown tool"}'
      return 1 ;;
  esac
  printf '%s' "$out"
  return "$rc"
}

serve_stdio() {
  local line method id tname res_out tool_rc=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    method=$(json_field "$line" method)
    id=$(_rpc_id "$line")
    case "$method" in
      notifications/*) continue ;;
      initialize)
        printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"dev-standards-governance","version":"4.10.0"}}}\n' "$id" ;;
      tools/list)
        printf '{"jsonrpc":"2.0","id":%s,"result":{"tools":[{"name":"governance_status","description":"Read-only agent-gate runtime status JSON","inputSchema":{"type":"object","properties":{}}},{"name":"governance_next","description":"Read-only next stage/command wizard JSON","inputSchema":{"type":"object","properties":{"change_id":{"type":"string"}}}},{"name":"governance_doctor","description":"Read-only governance health check JSON","inputSchema":{"type":"object","properties":{}}},{"name":"governance_preflight","description":"Read-only artifact gate preflight JSON","inputSchema":{"type":"object","properties":{"change_id":{"type":"string"}},"required":["change_id"]}}]}}\n' "$id" ;;
      tools/call)
        tname=$(json_field "$line" name)
        tool_rc=0
        res_out=$(_run_tool "$tname" "$line") || tool_rc=$?
        if [[ "$tool_rc" -ne 0 && "$res_out" == '{"error":'* ]]; then
          local ecode emsg
          ecode=$(printf '%s' "$res_out" | sed -nE 's/.*"error":(-?[0-9]+).*/\1/p')
          emsg=$(json_field "$res_out" message)
          printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%s,"message":"%s"}}\n' "$id" "${ecode:--32602}" "$(json_escape "$emsg")"
        elif [[ "$tool_rc" -ne 0 ]]; then
          printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"%s"}],"isError":true}}\n' "$id" "$(json_escape "$res_out")"
        else
          printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"%s"}]}}\n' "$id" "$(json_escape "$res_out")"
        fi ;;
      *)
        _has_rpc_id "$line" || continue
        printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"method not found"}}\n' "$id" ;;
    esac
  done
}

case "${1:-}" in
  --print-config)
    printf '{"mcpServers":{"dev-standards":{"command":"bash","args":["%s"]}}}\n' "$(json_escape "$SELF_DIR/mcp-governance-server.sh")" ;;
  --self-test)
    _st_out=$(serve_stdio <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"notifications/initialized"}
{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{}}
EOF
)
    grep -q '"protocolVersion":"2024-11-05"' <<< "$_st_out" || { echo "mcp-governance-server: self-test initialize failed" >&2; exit 1; }
    grep -q '"governance_doctor"' <<< "$_st_out" || { echo "mcp-governance-server: self-test tools/list failed" >&2; exit 1; }
    echo "mcp-governance-server: self-test PASS (4 read-only tools)" ;;
  -h|--help)
    echo "Usage: mcp-governance-server.sh [--print-config|--self-test|--help] (no args: stdio JSON-RPC 2.0 server)" ;;
  "")
    serve_stdio ;;
  *)
    echo "mcp-governance-server: unknown option '$1'" >&2; exit 2 ;;
esac
