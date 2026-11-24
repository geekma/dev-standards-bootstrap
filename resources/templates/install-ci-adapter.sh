#!/usr/bin/env bash
# install-ci-adapter — dynamic capability-driven CI/CD & branch-protection adapter (v4.7.0, CHG-152).
#
# Design contract (ITEM-14 / ITEM-16, REQ-1418 / REQ-1420):
#   Only GitHub Actions templates ship statically in resources/templates/github-*.yml.
#   For ALL other CI platforms (GitLab CI, Gitea Actions, Woodpecker CI, Jenkins,
#   Bitbucket Pipelines, Alibaba Cloud Yunxiao, Azure DevOps, or custom runners),
#   the active AI runtime runs:
#     1) scripts/install-ci-adapter --detect [repo_root]
#     2) scripts/install-ci-adapter --print-contract [platform]
#     3) scripts/install-ci-adapter --print-branch-protection-contract [platform]
#     4) Author native platform CI config from the emitted contract
#     5) scripts/install-ci-adapter --verify-wiring <ci-config-path>
#
# Zero dependencies: bash 3.2+, grep, sed, awk, git.
# Usage:
#   install-ci-adapter --detect [repo_root]
#   install-ci-adapter --print-contract [platform] [--repo <dir>]
#   install-ci-adapter --print-branch-protection-contract [platform] [--repo <dir>]
#   install-ci-adapter --verify-wiring <ci-config-path> [--repo <dir>]
set -uo pipefail

ci_cfg_path() { # <repo_root> <key> <default>
  local root="$1" k="$2" d="$3" yml="$1/.agent-governance.yml" v=""
  if [[ -f "$yml" ]]; then
    case "$k" in
      docs|scripts|tests|githooks)
        v=$(sed -nE "/^paths:[[:space:]]*$/,/^[^[:space:]#]/s/^[[:space:]]+${k}:[[:space:]]*([^#]*).*$/\1/p" "$yml" 2>/dev/null \
          | head -1 | tr -d "[:space:]\"'" || true) ;;
      *)
        v=$(sed -nE "s/^[[:space:]]*${k}:[[:space:]]*([^#]*).*$/\1/p" "$yml" 2>/dev/null \
          | head -1 | tr -d "[:space:]\"'" || true) ;;
    esac
  fi
  [[ -n "$v" ]] || v="$d"
  printf '%s' "$v"
}

ci_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ci_detect_default_branch() { # <repo_root>
  local root="$1" b=""
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    b=$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
    [[ -n "$b" ]] || b=$(git -C "$root" symbolic-ref -q --short HEAD 2>/dev/null || true)
  fi
  [[ -n "$b" ]] || b="main"
  printf '%s' "$b"
}

ci_has_glob() { # <dir> <glob>
  local d="$1" g="$2" f
  [[ -d "$d" ]] || return 1
  for f in "$d"/$g; do
    [[ -e "$f" ]] && return 0
  done
  return 1
}

ci_detect_platform() { # <repo_root> -> "<platform>|<evidence>|<remote_url>"
  local root="$1" plat="" ev="" remote_url=""
  if [[ -f "$root/.gitlab-ci.yml" ]]; then
    plat="gitlab"; ev=".gitlab-ci.yml"
  elif ci_has_glob "$root/.gitea/workflows" "*.yml" || ci_has_glob "$root/.gitea/workflows" "*.yaml"; then
    plat="gitea"; ev=".gitea/workflows/*"
  elif [[ -f "$root/.woodpecker.yml" ]] || ci_has_glob "$root/.woodpecker" "*.yml" || ci_has_glob "$root/.woodpecker" "*.yaml"; then
    plat="woodpecker"; ev=".woodpecker"
  elif [[ -f "$root/Jenkinsfile" ]]; then
    plat="jenkins"; ev="Jenkinsfile"
  elif [[ -f "$root/bitbucket-pipelines.yml" ]]; then
    plat="bitbucket"; ev="bitbucket-pipelines.yml"
  elif [[ -f "$root/.flow.yml" ]] || ci_has_glob "$root/.yunxiao" "*.yml"; then
    plat="yunxiao"; ev="yunxiao/.flow.yml"
  elif [[ -f "$root/azure-pipelines.yml" ]]; then
    plat="azure-devops"; ev="azure-pipelines.yml"
  elif ci_has_glob "$root/.github/workflows" "*.yml" || ci_has_glob "$root/.github/workflows" "*.yaml"; then
    plat="github"; ev=".github/workflows/*"
  fi

  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    remote_url=$(git -C "$root" remote get-url origin 2>/dev/null || true)
  fi
  if [[ -z "$plat" && -n "$remote_url" ]]; then
    case "$remote_url" in
      *gitlab*) plat="gitlab"; ev="git-remote" ;;
      *gitea*|*forgejo*) plat="gitea"; ev="git-remote" ;;
      *bitbucket*) plat="bitbucket"; ev="git-remote" ;;
      *codeup*|*aliyun*) plat="yunxiao"; ev="git-remote" ;;
      *dev.azure.com*|*visualstudio.com*) plat="azure-devops"; ev="git-remote" ;;
      *github.com*) plat="github"; ev="git-remote" ;;
    esac
  fi
  [[ -n "$plat" ]] || { plat="unknown"; ev="none"; }
  printf '%s|%s|%s' "$plat" "$ev" "${remote_url:-none}"
}

ci_branch_protection_guidance() { # <platform> <branch>
  local plat="$1" br="$2"
  case "$plat" in
    github)
      printf 'Settings -> Branches -> Rule (%s): require status check agent-governance; restrict direct pushes; require >=1 PR review (L3 >=2).' "$br" ;;
    gitlab)
      printf 'Settings -> Repository -> Protected branches (%s): Allowed to merge=Maintainers, Allowed to push=No one; require pipeline agent-governance to succeed; L3 approval rule >=2.' "$br" ;;
    gitea)
      printf 'Repository Settings -> Branches -> Add Branch Protection Rule (%s): Enable Status Check agent-governance; block direct push; require approvals >=1 (L3 >=2).' "$br" ;;
    bitbucket)
      printf 'Repository Settings -> Branch restrictions (%s): Prevent changes without PR, require minimum passing check agent-governance, require >=1 approval (L3 >=2).' "$br" ;;
    yunxiao)
      printf '仓库设置 -> 分支设置 -> 保护分支 (%s): 禁止直接推送、启用合并卡点 agent-governance 与 Flow 流水线通过、L3 须双人评审。' "$br" ;;
    azure-devops)
      printf 'Repos -> Branches -> Branch Policies (%s): Build Validation requiring agent-governance pipeline; minimum reviewers >=1 (L3 >=2); block direct push.' "$br" ;;
    *)
      printf 'Configure branch protection on %s: require passing check agent-governance, forbid direct pushes to default branch, enforce human+independent approval for L3.' "$br" ;;
  esac
}

ci_cmd_detect() {
  local root="${1:-$PWD}" info plat ev rurl br docs scripts tests
  [[ -d "$root" ]] || { echo "install-ci-adapter: directory not found: $root" >&2; exit 2; }
  info=$(ci_detect_platform "$root")
  plat="${info%%|*}"; info="${info#*|}"
  ev="${info%%|*}"; rurl="${info#*|}"
  br=$(ci_detect_default_branch "$root")
  docs=$(ci_cfg_path "$root" docs docs)
  scripts=$(ci_cfg_path "$root" scripts scripts)
  tests=$(ci_cfg_path "$root" tests tests)
  cat <<EOF
install-ci-adapter detect:
  repo: $root
  platform: $plat (evidence: $ev)
  default_branch: $br
  remote: $rurl
  paths: docs=$docs scripts=$scripts tests=$tests
EOF
}

ci_cmd_print_branch_protection() {
  local plat="${1:-}" root="${2:-$PWD}" br info guidance
  [[ -d "$root" ]] || { echo "install-ci-adapter: directory not found: $root" >&2; exit 2; }
  if [[ -z "$plat" ]]; then
    info=$(ci_detect_platform "$root")
    plat="${info%%|*}"
    [[ "$plat" != "unknown" ]] || plat="github"
  fi
  br=$(ci_detect_default_branch "$root")
  guidance=$(ci_branch_protection_guidance "$plat" "$br")
  cat <<EOF
{
  "contract_version": "1",
  "platform": "$(ci_json_escape "$plat")",
  "protected_branch": "$(ci_json_escape "$br")",
  "required_check": "agent-governance",
  "forbid_direct_push": true,
  "l3_approval_required": true,
  "platform_guidance": "$(ci_json_escape "$guidance")"
}
EOF
}

ci_cmd_print_contract() {
  local plat="${1:-}" root="${2:-$PWD}" br info docs scripts tests guidance target_hint
  [[ -d "$root" ]] || { echo "install-ci-adapter: directory not found: $root" >&2; exit 2; }
  if [[ -z "$plat" ]]; then
    info=$(ci_detect_platform "$root")
    plat="${info%%|*}"
    [[ "$plat" != "unknown" ]] || plat="github"
  fi
  br=$(ci_detect_default_branch "$root")
  docs=$(ci_cfg_path "$root" docs docs)
  scripts=$(ci_cfg_path "$root" scripts scripts)
  tests=$(ci_cfg_path "$root" tests tests)
  guidance=$(ci_branch_protection_guidance "$plat" "$br")
  case "$plat" in
    github) target_hint=".github/workflows/agent-governance.yml" ;;
    gitlab) target_hint=".gitlab-ci.yml" ;;
    gitea) target_hint=".gitea/workflows/agent-governance.yml" ;;
    woodpecker) target_hint=".woodpecker.yml" ;;
    jenkins) target_hint="Jenkinsfile" ;;
    bitbucket) target_hint="bitbucket-pipelines.yml" ;;
    yunxiao) target_hint=".flow.yml" ;;
    azure-devops) target_hint="azure-pipelines.yml" ;;
    *) target_hint="<platform-ci-config>" ;;
  esac
  cat <<EOF
{
  "contract_version": "1",
  "platform": "$(ci_json_escape "$plat")",
  "target_file_hint": "$(ci_json_escape "$target_hint")",
  "default_branch": "$(ci_json_escape "$br")",
  "principle": "Static templates ship for GitHub Actions only; non-GitHub CI pipelines are generated dynamically by the runtime AI from this contract and self-verified via --verify-wiring.",
  "paths": {
    "docs": "$(ci_json_escape "$docs")",
    "scripts": "$(ci_json_escape "$scripts")",
    "tests": "$(ci_json_escape "$tests")"
  },
  "required_jobs": {
    "agent-governance": {
      "triggers": ["pull_request -> $br", "push -> $br"],
      "fetch_depth": 0,
      "commands": [
        "bash $(ci_json_escape "$scripts")/agent-gate --stage ci --base \"\$CI_BASE_REF\"",
        "bash $(ci_json_escape "$scripts")/check-standards-compliance.sh \"\$CI_BASE_REF\"",
        "bash $(ci_json_escape "$tests")/audit-docs-consistency.sh --only-fail"
      ]
    },
    "verify": {
      "description": "Read AGENT_GUARD_VERIFY_COMMAND or base-branch .agent-governance.yml ci.verification_command fallback; skip gracefully if placeholder."
    }
  },
  "branch_protection": {
    "protected_branch": "$(ci_json_escape "$br")",
    "required_check": "agent-governance",
    "forbid_direct_push": true,
    "l3_approval_required": true,
    "platform_guidance": "$(ci_json_escape "$guidance")"
  }
}
EOF
}

ci_cmd_verify_wiring() {
  local cfg="${1:-}" root="${2:-$PWD}" sdir gate_path
  [[ -n "$cfg" ]] || { echo "install-ci-adapter: --verify-wiring requires <ci-config-path>" >&2; exit 2; }
  [[ -d "$root" ]] || { echo "install-ci-adapter: directory not found: $root" >&2; exit 2; }
  case "$cfg" in
    /*) ;;
    *) cfg="$root/$cfg" ;;
  esac
  [[ -f "$cfg" && -s "$cfg" ]] || { echo "install-ci-adapter: CI config missing or empty: $cfg" >&2; exit 2; }
  case "$cfg" in
    *.yml|*.yaml)
      if grep -qn $'^\t' "$cfg" 2>/dev/null; then
        echo "install-ci-adapter: invalid YAML tab indentation in $cfg" >&2
        exit 2
      fi
      ;;
  esac
  if ! grep -q 'agent-gate' "$cfg" 2>/dev/null || ! grep -qE -- '--stage[[:space:]]+ci' "$cfg" 2>/dev/null; then
    echo "install-ci-adapter: CI config missing required 'agent-gate --stage ci' step: $cfg" >&2
    exit 2
  fi
  if ! grep -qE 'check-standards-compliance|audit-docs-consistency' "$cfg" 2>/dev/null; then
    echo "install-ci-adapter: CI config missing check-standards-compliance.sh or audit-docs-consistency.sh: $cfg" >&2
    exit 2
  fi
  sdir=$(ci_cfg_path "$root" scripts scripts)
  gate_path="$root/$sdir/agent-gate"
  [[ -f "$gate_path" ]] || { echo "install-ci-adapter: wired script not found: $gate_path" >&2; exit 2; }
  echo "install-ci-adapter: CI wiring verified ($cfg)"
}

mode="" arg1="" repo_opt="$PWD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detect) mode="detect"; shift ;;
    --print-contract) mode="contract"; shift ;;
    --print-branch-protection-contract) mode="bp"; shift ;;
    --verify-wiring) mode="verify"; shift ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "install-ci-adapter: --repo requires a path" >&2; exit 2; }
      repo_opt="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,21p' "$0"
      exit 0 ;;
    -*)
      echo "install-ci-adapter: unknown option '$1'" >&2
      exit 2 ;;
    *)
      if [[ -z "$arg1" ]]; then arg1="$1"; shift
      else echo "install-ci-adapter: unexpected argument '$1'" >&2; exit 2
      fi ;;
  esac
done

case "$mode" in
  detect) ci_cmd_detect "${arg1:-$repo_opt}" ;;
  contract) ci_cmd_print_contract "$arg1" "$repo_opt" ;;
  bp) ci_cmd_print_branch_protection "$arg1" "$repo_opt" ;;
  verify) ci_cmd_verify_wiring "$arg1" "$repo_opt" ;;
  *) ci_cmd_detect "${arg1:-$repo_opt}" ;;
esac
