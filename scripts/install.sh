#!/usr/bin/env bash
# install.sh — dev-standards-bootstrap 一键安装/升级器（源层工具，不随 Skill 分发）
#
# 一条命令完成「拿到 Skill」+「装进目标仓」两件事：
#
#   一句话（安装或升级，目标仓默认当前目录）：
#     curl -fsSL https://raw.githubusercontent.com/geekma/dev-standards-bootstrap/main/scripts/install.sh | bash -s -- .
#   或先克隆再执行：
#     git clone https://github.com/geekma/dev-standards-bootstrap.git
#     bash dev-standards-bootstrap/scripts/install.sh <目标仓库>
#
# 行为：
#   1) 确保 Skill checkout：--from 直用本地路径；否则缺则 git clone（全量克隆，
#      保留 bootstrap --check/--self-update 依赖的完整历史）；已存在则按 --ref
#      fast-forward pull——本地有改动时**拒绝并指路**，绝不覆盖。
#   2) 模式自动探测：目标仓已接入（<target>/<docs>/DEVELOPMENT_STANDARDS.md 存在）
#      → bootstrap --upgrade；否则 → bootstrap --all。可用 --upgrade / --install 显式指定。
#   3) 冲突 / 脏树 / 部分安装语义 100% 复用 bootstrap（fail-closed）——本脚本不复制
#      任何安装逻辑，bootstrap 是清单与守卫的唯一权威源。
#
# 零依赖：bash 3.2+、git、curl（仅 URL 模式需要）。不删除任何文件；网络只用于
# 克隆/拉取本仓库——克隆落地之后运行的全部是仓内脚本，不再执行任何网络下载物。
set -euo pipefail

DEFAULT_REPO="https://github.com/geekma/dev-standards-bootstrap.git"
DEFAULT_SKILL_DIR="$HOME/.dev-standards-bootstrap/dev-standards-bootstrap"

usage() {
  cat <<EOF
Usage: scripts/install.sh [target_root] [flags]

Args:
  [target_root]            target repository root (default: current directory)

Flags:
  --skill-dir <path>       where the skill checkout lives (default: $DEFAULT_SKILL_DIR)
  --from <path>            install from an existing local checkout (offline / testing)
  --repo <url>             source repository (default: $DEFAULT_REPO)
  --ref <git-ref>          branch or tag to clone / pull (default: upstream default branch)
  --install                force a full install (bootstrap --all)
  --upgrade                force an upgrade (bootstrap --upgrade)
  --check                  read-only three-way version report (bootstrap --check), exits 1 on drift
  --as-skill <claude|opencode|all|/path>
                           register the Skill itself (SKILL.md + resources/ + scripts/) with an AI
                           client's skill directory as a symlink to the checkout — no target repo is
                           touched; mutually exclusive with --install/--upgrade/--check/--layer.
                           claude -> ~/.claude/skills, opencode -> ~/.config/opencode/skills, all ->
                           both; a value containing '/' is used as the destination directory itself
                           (any other client). Reload the client afterwards (/reload-skills).
  --skills-root <path>     override the parent root for named --as-skill clients (tests / CI)
  --force                  pass --force through to bootstrap (override conflicts / dirty tree);
                           for --as-skill: retarget an existing symlink or replace an EMPTY dir
  --layer <name>           pass a layer flag through (core/claude/ci/guard/pipeline; repeatable)
  --docs-dir <p> / --scripts-dir <p> / --tests-dir <p> / --githooks-dir <p>
                           pass-through to bootstrap (default roots when omitted)
  -h, --help               this help

Exit codes: 0 success; 2 bad usage, clone failure, bad --ref, or bootstrap conflict (fail-closed).
Notes:
  - a failed fast-forward pull on an EXISTING checkout is NOT fatal: it prints a
    NOTE and continues with the local copy (offline-friendly); a failed CLONE is fatal.
  - hook wiring (core.hooksPath) requires the target to be a git repository; a
    bare directory installs the files but cannot receive Git hooks.
EOF
}

target=""
opt_skill_dir=""
opt_from=""
opt_repo=""
opt_ref=""
opt_skills_root=""
as_skill=""
as_skill_given=false
skills_root_given=false
force=false
mode="auto"          # auto | install | upgrade | check
layers_given=false
passthrough=()
pending=""
for arg in "$@"; do
  if [[ -n "$pending" ]]; then
    case "$pending" in
      skill-dir) opt_skill_dir="$arg" ;;
      from)      opt_from="$arg" ;;
      repo)      opt_repo="$arg" ;;
      ref)       opt_ref="$arg" ;;
      docs-dir)      passthrough+=("--docs-dir=$arg") ;;
      scripts-dir)   passthrough+=("--scripts-dir=$arg") ;;
      tests-dir)     passthrough+=("--tests-dir=$arg") ;;
      githooks-dir)  passthrough+=("--githooks-dir=$arg") ;;
      skills-root)   skills_root_given=true; opt_skills_root="$arg" ;;
      as-skill)      as_skill_given=true; as_skill="$arg" ;;
      layer)         layers_given=true; passthrough+=("--$arg") ;;
    esac
    pending=""
    continue
  fi
  case "$arg" in
    -h|--help)   usage; exit 0 ;;
    --install)   mode="install" ;;
    --upgrade)   mode="upgrade" ;;
    --check)     mode="check" ;;
    --force)     force=true; passthrough+=("--force") ;;
    --skill-dir) pending="skill-dir" ;;
    --skill-dir=*) opt_skill_dir="${arg#*=}" ;;
    --from)      pending="from" ;;
    --from=*)    opt_from="${arg#*=}" ;;
    --repo)      pending="repo" ;;
    --repo=*)    opt_repo="${arg#*=}" ;;
    --ref)       pending="ref" ;;
    --ref=*)     opt_ref="${arg#*=}" ;;
    --docs-dir)     pending="docs-dir" ;;
    --scripts-dir)  pending="scripts-dir" ;;
    --tests-dir)    pending="tests-dir" ;;
    --githooks-dir) pending="githooks-dir" ;;
    --skills-root)     skills_root_given=true; pending="skills-root" ;;
    --skills-root=*)   skills_root_given=true; opt_skills_root="${arg#*=}" ;;
    --as-skill)        as_skill_given=true; pending="as-skill" ;;
    --as-skill=*)      as_skill_given=true; as_skill="${arg#*=}" ;;
    --layer)        pending="layer" ;;
    -*)          echo "install: unknown flag '$arg'" >&2; usage >&2; exit 2 ;;
    *)           [[ -z "$target" ]] || { echo "install: unexpected extra argument '$arg' (target already '$target')" >&2; exit 2; }
                 target="$arg" ;;
  esac
done
[[ -z "$pending" ]] || { echo "install: --${pending} requires a value" >&2; exit 2; }
[[ -n "$target" ]] || target="$PWD"

# --as-skill validation runs BEFORE any checkout/clone work: a usage error must
# not have side effects (no network, no clone, no filesystem writes).
if [[ "$as_skill_given" == true ]]; then
  [[ -n "$as_skill" ]] || { echo "install: --as-skill requires a value (claude|opencode|all|/path)" >&2; exit 2; }
  [[ "$skills_root_given" == false || -n "$opt_skills_root" ]] \
    || { echo "install: --skills-root requires a value" >&2; exit 2; }
  if [[ "$mode" != "auto" || "$layers_given" == true ]]; then
    echo "install: --as-skill cannot be combined with --install/--upgrade/--check/--layer" >&2
    exit 2
  fi
  case "$as_skill" in
    claude|opencode|all|*/*) : ;;
    *) echo "install: unknown --as-skill target '$as_skill' (claude|opencode|all|/path)" >&2; exit 2 ;;
  esac
fi

[[ -d "$target" ]] || { echo "install: target is not a directory: $target" >&2; exit 2; }
target=$(cd "$target" && pwd)
skill_dir="${opt_skill_dir:-$DEFAULT_SKILL_DIR}"

# --- 1) ensure the skill checkout -------------------------------------------
if [[ -n "$opt_from" ]]; then
  [[ -d "$opt_from" ]] || { echo "install: --from is not a directory: $opt_from" >&2; exit 2; }
  [[ -z "$opt_skill_dir" ]] || echo "install: NOTE  --skill-dir ignored together with --from" >&2
  [[ -z "$opt_ref" ]]      || echo "install: NOTE  --ref ignored together with --from (offline mode uses the checkout as-is)" >&2
  skill_dir=$(cd "$opt_from" && pwd)
  echo "install: using local checkout (offline): $skill_dir"
elif [[ -d "$skill_dir/.git" ]]; then
  if [[ -n "$(git -C "$skill_dir" status --porcelain 2>/dev/null)" ]]; then
    echo "install: skill checkout has local changes: $skill_dir" >&2
    echo "install:   commit or stash them first — this tool never overwrites your checkout" >&2
    exit 2
  fi
  if [[ -n "$opt_ref" ]]; then
    # --ref must not fail silently on an existing checkout: the clone path exits 2
    # on a bad ref, so this path must be just as loud. Resolve first, then switch.
    if ! git -C "$skill_dir" rev-parse --verify --quiet "$opt_ref^{commit}" >/dev/null 2>&1 \
       && ! GIT_TERMINAL_PROMPT=0 git -C "$skill_dir" fetch --quiet origin "$opt_ref" 2>/dev/null; then
      echo "install: --ref '$opt_ref' not found in $skill_dir (and fetch failed)" >&2
      exit 2
    fi
    if ! git -C "$skill_dir" rev-parse --verify --quiet "$opt_ref^{commit}" >/dev/null 2>&1; then
      echo "install: --ref '$opt_ref' not found in $skill_dir" >&2
      exit 2
    fi
    git -C "$skill_dir" checkout --quiet "$opt_ref" 2>/dev/null || true
  fi
  GIT_TERMINAL_PROMPT=0 git -C "$skill_dir" pull --ff-only --quiet 2>/dev/null \
    || echo "install: NOTE  pull failed (offline?) — continuing with the local copy" >&2
  echo "install: skill checkout up to date: $skill_dir"
else
  if [[ -e "$skill_dir" ]]; then
    echo "install: $skill_dir exists but is not a git checkout — pass --skill-dir or --from" >&2
    exit 2
  fi
  repo="${opt_repo:-$DEFAULT_REPO}"
  mkdir -p "$(dirname "$skill_dir")"
  clone_args=(--quiet)
  if [[ -n "$opt_ref" ]]; then
    clone_args+=("--branch" "$opt_ref")
  fi
  echo "install: cloning $repo -> $skill_dir"
  GIT_TERMINAL_PROMPT=0 git clone "${clone_args[@]}" "$repo" "$skill_dir" >&2 \
    || { echo "install: git clone failed — check network / URL / --ref" >&2; exit 2; }
fi

[[ -f "$skill_dir/scripts/bootstrap.sh" ]] \
  || { echo "install: $skill_dir does not look like dev-standards-bootstrap (scripts/bootstrap.sh missing)" >&2; exit 2; }

carried=$(grep -oE '规范版本：v[0-9.]+' "$skill_dir/resources/DEVELOPMENT_STANDARDS.md" 2>/dev/null \
  | head -1 | grep -oE '[0-9.]+' || true)

# --- 2b) --as-skill: register the Skill itself with an AI client -------------
# The checkout IS the skill layout (root SKILL.md + resources/ + scripts/), so
# registration is a symlink — zero copies, --self-update flows through. No
# target repo is touched: governing a repository stays the bootstrap path.
if [[ -n "$as_skill" ]]; then
  [[ -f "$skill_dir/SKILL.md" ]] \
    || { echo "install: $skill_dir has no SKILL.md at its root — not a skill layout" >&2; exit 2; }

  link_dest() { # $1 = destination directory (the dev-standards-bootstrap link path)
    local dest="$1"
    if [[ -L "$dest" ]]; then
      if [[ "$(readlink "$dest")" == "$skill_dir" ]]; then
        echo "install: skill already linked: $dest -> $skill_dir"
        return 0
      fi
      if [[ "$force" != true ]]; then
        echo "install: $dest is a symlink to '$(readlink "$dest")' — pass --force to retarget it" >&2
        return 2
      fi
      rm "$dest"
    elif [[ -e "$dest" ]]; then
      if [[ "$force" == true && -d "$dest" && -z "$(ls -A "$dest")" ]]; then
        rmdir "$dest"
      else
        echo "install: $dest already exists and is not a symlink — refusing (fail-closed;" >&2
        echo "install:   move it aside, or pass --force to replace an EMPTY directory)" >&2
        return 2
      fi
    fi
    mkdir -p "$(dirname "$dest")"
    ln -s "$skill_dir" "$dest" || return 2
    if [[ ! -f "$dest/SKILL.md" ]]; then
      echo "install: link created but SKILL.md is not reachable through $dest" >&2
      return 2
    fi
    echo "install: skill installed: $dest -> $skill_dir"
  }

  rc_all=0
  case "$as_skill" in
    claude)
      link_dest "${opt_skills_root:-$HOME/.claude/skills}/dev-standards-bootstrap" || rc_all=2 ;;
    opencode)
      link_dest "${opt_skills_root:-$HOME/.config/opencode/skills}/dev-standards-bootstrap" || rc_all=2 ;;
    all)
      link_dest "${opt_skills_root:-$HOME/.claude/skills}/dev-standards-bootstrap" || rc_all=2
      link_dest "${opt_skills_root:-$HOME/.config/opencode/skills}/dev-standards-bootstrap" || rc_all=2 ;;
    */*)
      case "$as_skill" in /*) as_dest="$as_skill" ;; *) as_dest="$PWD/$as_skill" ;; esac
      link_dest "$as_dest" || rc_all=2 ;;
    *)
      echo "install: unknown --as-skill target '$as_skill' (claude|opencode|all|/path)" >&2
      exit 2 ;;
  esac
  [[ "$rc_all" -eq 0 ]] || exit "$rc_all"
  echo "install: done — reload the client to pick it up (/reload-skills in Claude Code, or restart the session)"
  echo "install: then say \"use dev-standards-bootstrap to initialize this repo\" in any repository."
  echo "install: note: this registered the SKILL only — no repository has been governed (that is the default bootstrap path)."
  exit 0
fi

# --- 2) delegate to bootstrap (the single authority for install/upgrade) -----
if [[ "$mode" == "auto" ]]; then
  # Detect an already-governed target. The docs root may be customized, so read
  # it from the target's own config when present (same precedence the gate uses:
  # env > yml > default). A miss falls back to the default roots — a governed
  # target with exotic roots still fails CLOSED below via bootstrap's CONFLICT
  # path (diff + --force hint), never a silent overwrite.
  tgt_docs="docs"
  if [[ -f "$target/.agent-governance.yml" ]]; then
    yml_docs=$(sed -nE 's/^[[:space:]]*docs:[[:space:]]*([^#]*).*$/\1/p' "$target/.agent-governance.yml" 2>/dev/null \
      | head -n 1 | tr -d "[:space:]\"'" || true)
    [[ -z "$yml_docs" ]] || tgt_docs="$yml_docs"
  fi
  if [[ -f "$target/$tgt_docs/DEVELOPMENT_STANDARDS.md" ]]; then
    mode="upgrade"
  else
    mode="install"
  fi
fi

case "$mode" in
  install)
    echo "install: mode=install  target=$target  skill=v${carried:-unknown}"
    if [[ "$layers_given" == true ]]; then
      exec bash "$skill_dir/scripts/bootstrap.sh" ${passthrough[@]+"${passthrough[@]}"} "$target"
    fi
    exec bash "$skill_dir/scripts/bootstrap.sh" --all ${passthrough[@]+"${passthrough[@]}"} "$target"
    ;;
  upgrade)
    echo "install: mode=upgrade  target=$target  skill=v${carried:-unknown}"
    exec bash "$skill_dir/scripts/bootstrap.sh" --upgrade ${passthrough[@]+"${passthrough[@]}"} "$target"
    ;;
  check)
    exec bash "$skill_dir/scripts/bootstrap.sh" --check ${passthrough[@]+"${passthrough[@]}"} "$target"
    ;;
  *)
    echo "install: unknown mode '$mode'" >&2; exit 2 ;;
esac
