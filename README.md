<!-- markdownlint-disable MD033 MD041 MD013 -->
<div align="center">

# dev-standards-bootstrap

### One-command AI Agent Development Governance & Quality Gate System for Any Repository

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Standards Version](https://img.shields.io/badge/Standards-v3.9.0-green.svg)](resources/DEVELOPMENT_STANDARDS.md)
[![AGENTS.md](https://img.shields.io/badge/Entry_Point-AGENTS.md-orange.svg)](resources/AGENTS.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](../../pulls)

[English](README.md) | [中文](README.zh-CN.md)

</div>

---

## Overview

**dev-standards-bootstrap** is a reusable AI agent Skill that injects a complete, battle-tested **software development and change management governance system** into any code repository with a single command: **five mandatory quality gates**, a **risk classification matrix**, an **agent role independence framework**, and **anti-skip execution rules** — installed once, enforced permanently.

The design is measured, not hypothetical. A CIKM '26 study of production agent memory ([arXiv:2608.22752](https://arxiv.org/abs/2608.22752)) shows `/compact` retains only **53% of safety rules after one round, 10% after five**; the [AI-Native SDLC Playbook](https://claude.com/blog/the-ai-native-sdlc-playbook) documents intent drift and incidents that never feed back. The answer is architectural: **never trust agent memory or self-reports** — governance state lives on disk as versioned artifacts, a dependency-free gate reads the filesystem (not the conversation) at every write, CI is the final arbiter, and the governance package tests itself with 151 golden-case assertions. Full rationale: [DEVELOPMENT_STANDARDS.md §2.17](resources/DEVELOPMENT_STANDARDS.md).

---

## Key Features

| Feature | Description |
|---|---|
| **5 Quality Gates + Two-Layer Acceptance** | Doc-First, Test-First, Evidence, Traceability, Independent Verification — non-bypassable; every stage passes machine-verifiable A-layer markers plus independent-role B-layer judgment (§2.5) |
| **Risk Classification × Role Independence** | L0–L3 matrix drives independence: separate execution entities, L2/L3 distinct platform/model vendors, L3 needs human Release Owner approval (§0.5) |
| **RTVM Traceability + One Change, One Document Set** | REQ→DES→TASK→TC full-chain matrix; every change opens a fresh `docs/changes/<new-id>/` group meeting the **eight-category** minimum (incl. `04.5-coding-record.md` enforced at stop/ci), every defect a fresh six-file bug group (一次变更一组文档, §2.15) |
| **10-Stage Lifecycle + AI Anti-Skip Rules** | ReAct (Thought→Action→Observation) on every step; anti-skip rules ban summary-style "done", silent downgrades, premature completion (§2.16) |
| **Test Coverage Standard (11 dimensions)** | Per-dimension design or explicit N/A; branch coverage ≥60% (L2+); LLM eval-set regression; **business-scenario coverage ≥80%** (SC-xxx, L3 ≥90%) |
| **Methodology Selection Layer (M0–M3)** | `METHODOLOGY.md` answers "which methodologies are allowed / forbidden"; `methodologies/` provide per-item engineering rationale (weak-typing ban, LLM I/O schema separation, state-trigger-audit) |
| **Bug Fix Log + Same-Family Scan** | Repo-level append-only `bugfix-log.md` index; root-cause tables carry a **same-family** scan row — fix without family scan is rejected (§2.5 Stage 6) |
| **Deterministic Gate + Pipeline Automation** | One dependency-free validator shared by write-time hooks, Git hooks, and CI; spec merge auto-dispatches skeletons, changelog merge auto-opens a release checklist, incidents auto-create `BUG-<ts>` intent PRs; autonomy capped at A2 (§2.17) |
| **Golden-Case Self-Tests** | `tests/run-tests.sh` regression-tests the gate and the installer (151 assertions) in throwaway git repos — bash + git only (§2.17.4) |

`agent-gate metrics` emits read-only JSON Lines pipeline metrics from git history — observation only, never a substitute for DoD (§2.17.5). Specialized standards cover deployment/config/DB changes, AI/LLM pipelines, test data isolation, emergency hotfixes, release, monitoring, and supply chain (§2.6–§2.13).

---

## Supported AI Coding Tools

`AGENTS.md` is a context mechanism, not an enforcement mechanism; support varies by client. Natively reads `AGENTS.md`: **Claude Code, Cursor, Codex, Windsurf, Gemini CLI, Qoder, Trae, OpenCode**. Clients without a known hook schema get no fabricated config — their enforcement path is Git hooks + CI, which validate the repository rather than the editor. The final cross-client control is protected branches plus required CI checks.

---

## Quick Start

Clone the repository into your Skill directory (`git clone https://github.com/geekma/dev-standards-bootstrap.git`, or add as a submodule), open your AI coding tool in any target repository and say:

> "Use dev-standards-bootstrap to initialize this repo."

The Skill runs `bash scripts/bootstrap.sh --core <target>` (layered flags `--claude/--ci/--guard/--pipeline`, `--all` for everything): it detects existing files and never overwrites silently (diffs first, `--force` to override), writes `AGENTS.md` plus the standards/methodology layer and templates into `docs/`, and optionally adds hook adapters, Git hooks, CI workflows, and the golden-case self-test suite.

---

## Repository Structure

```
dev-standards-bootstrap/
├── SKILL.md                                # Skill manifest (trigger, execution steps, red lines)
├── README.md                               # English documentation (this file)
├── README.zh-CN.md                         # Chinese documentation
├── LICENSE                                 # MIT License
├── scripts/
│   └── bootstrap.sh                        # Manifest-driven installer (not shipped): copies resources/ into a target repo by layer, idempotent, conflict-safe
├── screenshots/                            # README screenshots (gate blocking, change artifacts)
├── tests/
│   ├── run-tests.sh                        # Golden-case regression suite for governance templates incl. gate & bootstrap (151 assertions; copied to target tests/ — target-repo adaptive: unshipped/skipped cases auto-skip)
│   └── audit-standards-src.sh              # Source-layer only (NOT shipped): audits the standards text itself - version chain / keyword matrix / checklist uniqueness / numbering / tautology-proof greps
└── resources/
    ├── AGENTS.md                           # Entry point for AI agents (copied to target repo root)
    ├── DEVELOPMENT_STANDARDS.md             # Full standards document v3.9.0 (copied to docs/)
    ├── STANDARDS_CHANGELOG.md              # Standards upgrade history (sole home of §2.14 upgrade log, v3.8.0; copied to docs/)
    ├── METHODOLOGY.md                       # Methodology selection guide: M0-M3 levels + stage x methodology x applicable / not-applicable table (copied to docs/)
    ├── methodologies/
    │   ├── development.md                   # Code standards: SOLID/DRY/KISS/YAGNI applicability & exemptions + 7 engineering dimensions
    │   ├── data-structures.md               # Data structure standards: 6 model types + weak-typing ban + LLM input/output specifics
    │   └── state-trigger-audit.md           # State/trigger-link audit: 6 lessons + 6-step checklist + 3 anti-patterns (v3.4.0)
    └── templates/
        ├── CLAUDE.md                       # One-line import for Claude Code
        ├── PULL_REQUEST_TEMPLATE.md        # GitHub PR template with gate self-check
        ├── check-standards-compliance.sh   # CI compliance check script
        ├── agent-gate.sh                   # Shared pre-write / commit-msg / Git / CI validator (+ metrics)
        ├── intent.md                       # Pipeline entry template for each change's 00-intent.md
        ├── coding-record.md                # Per-change coding record template (→ docs/changes/<CHG>/04.5-coding-record.md)
        ├── bugfix-log.md                   # Repo-level bug-fix index template (copied to docs/bugfix-log.md)
        ├── bug-diagnosis.md, bug-impact.md, bug-test-plan.md, bug-matrix.md, bug-config.md, bug-tasks.md  # Six-file defect document set (→ docs/bugs/_templates/)
        ├── 06.5-deployment-config.md       # Deployment/config/DB record template (→ docs/; must declare "未命中，不适用" when not hit)
        ├── 06-delivery-summary.md          # Delivery summary + FU ledger template (→ docs/; four mandatory sections per §2.5 stage 9.5)
        ├── audit-docs-consistency.sh       # Cross-doc consistency audit: version chain / numbering continuity / checklist sync / bugfix cross-registration / RTVM backfill (copied to tests/)
        ├── governance-state.json           # Template for each change's 00-governance.json (risk level + execution owners)
        ├── agent-governance.yml            # Team-reviewable governance config record (copied to .agent-governance.yml)
        ├── pre-commit, pre-push, commit-msg  # Git hook templates (commit-msg: attribution gate)
        ├── install-hook-adapter.sh         # Generates the hook adapter for the detected tool (claude/cursor/gemini)
        ├── github-agent-governance.yml     # Required-check workflow template
        ├── github-artifact-pipeline.yml    # Artifact pipeline: spec merged -> 02/03/03.5/04 skeletons PR; changelog merged -> release checklist issue
        └── github-incident-to-intent.yml   # Incident loop: alert dispatch -> BUG-<ts> intent skeleton PR
```

---

## The Deterministic Gate (agent-gate)

Copy `agent-gate.sh` to `scripts/agent-gate`, create `docs/changes/CHG-123/` with `00-intent.md` (recorded intent) + `00-governance.json` (risk level + distinct execution owners; L3 needs the three `release_authorized_by`-family authorization fields) and the non-empty spec/impact/plan/tasks/test artifacts, then run:

```bash
scripts/agent-gate begin CHG-123
```

| Command | Purpose |
|---|---|
| `begin <change-id>` / `end` | Activate or clear the active change; requires the seven change artifacts (incl. `00-intent.md`, the `02` impact analysis, the `03.5` task breakdown), validates the governance state plus A-layer content markers |
| `--stage pre-write` | Validates the active change's artifacts and governance state before an agent writes source code; fails closed if the target path cannot be parsed from hook input |
| `--stage staged` | Staged source changes must ship with matching change artifacts and a valid governance state, otherwise the commit is rejected |
| `--stage commit-msg <msgfile>` | Attribution gate: a commit that stages code files must reference a valid change id (waived for merge / revert / docs-only commits) |
| `--stage stop` | Ending a turn after source edits requires `04.5-coding-record.md` (checked first), `05-test-results.md`, `09-changelog.md` (with ReAct Observation records), plus a passing `AGENT_GUARD_VERIFY_COMMAND` when configured; changelog REQ ids must be backfilled as rows in `docs/<feature>/01.5-rtvm-matrix.md` (Gate 4 RTVM closure) |
| `--stage ci [--base <ref>]` | Rechecks the branch/PR diff (artifacts + governance state + delivery evidence for touched changes) and runs the real verification command |
| `metrics` | Read-only pipeline metrics as JSON Lines — observations only, never a substitute for DoD |

![The required artifact set of a new change: 00-governance.json, 01-spec.md, 03-modification-plan.md, 04-test-scripts.md staged as new files](screenshots/change-artifacts-required-set.png)

![agent-gate blocking a non-compliant commit of source changes in an IDE](screenshots/agent-gate-blocked-in-trae.png)

Install Git hooks with `git config core.hooksPath .githooks`, set `AGENT_GUARD_VERIFY_COMMAND` to the real build/lint/test/security command, then mark the GitHub workflow as a required branch-protection check. Run `scripts/install-hook-adapter` for the Claude Code/Cursor/Gemini CLI pre-write adapters. State files and checkboxes are declarations, not proof: CI re-runs the real command and is mandatory for enforcement.

### Optional Pipeline Automation (§2.17)

- **Artifact pipeline** (`github-artifact-pipeline.yml`): merging `01-spec.md` auto-creates a scaffold branch with `02`/`03`/`03.5`/`04` skeleton PRs; merging `09-changelog.md` auto-opens a release-checklist issue. Skeletons contain headings and to-fill comments only.
- **Incident loop** (`github-incident-to-intent.yml`): monitoring systems fire `repository_dispatch` type `incident`; the workflow creates a `BUG-<UTC-timestamp>` intent skeleton PR — every incident re-enters the pipeline as recorded intent.
- **Autonomy cap**: hosted workflows are limited to A2 actions (branches, skeletons, PRs, issues); content (A3) and execution (A4) stay local; merge gates are never waived by automation. Semantics are defined by the standards §2.17, not by any platform.
- **Self-testing**: before modifying `agent-gate.sh`, hooks, or workflows, run `bash tests/run-tests.sh` — 151 golden-case assertions, bash + git only.

---

## The Five Quality Gates

A change passing through the gates accumulates its full artifact chain, from `01-spec.md` all the way to `08-supplement.md`:

![Full artifact lifecycle of a change: 01-spec through 08-supplement](screenshots/change-artifacts-full-lifecycle.png)

```
[ Gate 1: Doc-First ]      Requirements/design must exist before any code change
        │
        ▼
[ Gate 2: Test-First ]     Test cases (TDD red-green) must exist before implementation
        │
        ▼
[ Gate 3: Evidence ]       Real test output required-no verbal claims of "done"
        │
        ▼
[ Gate 4: Traceability ]   RTVM must be closed: REQ ↔ DES ↔ CODE ↔ TC
        │
        ▼
[ Gate 5: Independent ]    Test & review by different agents/humans; high-risk needs human approval
```

Any change that fails any gate is **blocked from merge to main**.

---

## Risk Classification Matrix

| Level | Criteria | Independence | Cross-Platform | Human Approval |
|---|---|---|---|---|
| **L0** Very Low | No logic change (docs, comments, formatting) | Roles may merge | Not required | No |
| **L1** Low | Non-core modules, no external interfaces | Separate sub-tasks | Not required | No |
| **L2** Medium (default) | Core business logic, P0/P1 priority | Separate execution entities | Recommended | No |
| **L3** High | Sensitive personal data (PII), auth, prod DB, AI/Prompt, breaking API changes, P0 hotfix | Mandatory cross-platform/cross-model | **Mandatory** (≥2 model vendors) | **Mandatory** |

---

## Contributing

Contributions are welcome! Please follow the standards defined in this repository: documentation before code (Gate 1), tests first (Gate 2), real test output (Gate 3), closed RTVM (Gate 4), independent review (Gate 5). Pull requests should use the [PR template](resources/templates/PULL_REQUEST_TEMPLATE.md) and complete all gate self-checks.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

<div align="center">

**Standards Version:** v3.9.0 | **Last Updated:** 2026-09-14 | **Maintainer:** [geekma](https://x.com/geekma) | **Email:** geekma@gmail.com

[Report Bug](../../issues) | [Request Feature](../../issues) | [Read the Standards](resources/DEVELOPMENT_STANDARDS.md)

</div>
