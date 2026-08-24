<!-- markdownlint-disable MD033 MD041 MD013 -->
<div align="center">

# dev-standards-bootstrap

### One-command AI Agent Development Governance & Quality Gate System for Any Repository

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Standards Version](https://img.shields.io/badge/Standards-v2.16.0-green.svg)](resources/DEVELOPMENT_STANDARDS.md)
[![AGENTS.md](https://img.shields.io/badge/Entry_Point-AGENTS.md-orange.svg)](resources/AGENTS.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](../../pulls)

[English](README.md) | [中文](README.zh-CN.md)

</div>

---

## Overview

**dev-standards-bootstrap** is a reusable AI agent Skill that injects a complete, battle-tested **software development and change management governance system** into any code repository with a single command.

It writes only **one content file** (`AGENTS.md`) into the target repo—which all modern AI coding tools (Claude Code, Cursor, Codex, Windsurf, Gemini CLI, Qoder, Trae, OpenCode) natively read as of 2026. No per-tool configuration, no duplicated files, no maintenance burden.

### Why You Need This

When multiple AI agents work on the same codebase, chaos is inevitable without governance:

- Agents skip documentation and jump straight to code
- Tests are an afterthought—or missing entirely
- No traceability between requirements, design, code, and tests
- The same agent writes, tests, and approves its own work
- Silent step-skipping disguised as "summaries"

This Skill solves all of the above by installing **five mandatory quality gates**, a **risk classification matrix**, an **agent role independence framework**, and **anti-skip execution rules** into your repository—once, permanently.

---

## Key Features

| Feature | Description |
|---|---|
| **5 Quality Gates** | Doc-First, Test-First, Evidence-Before-Assertions, Traceability, and Independent Verification—non-bypassable |
| **Risk Classification (L0–L3)** | Determines agent independence requirements and cross-platform/cross-model verification rules |
| **Agent Role Independence** | Orchestrator, Requirements, Architecture/Planning, Development, Testing, and Review roles must be separate execution entities |
| **4-Dimensional RTVM** | Requirement (REQ) → Design (DES) → Task (TASK) → Test Case (TC) full-chain traceability matrix |
| **10-Stage Development Lifecycle** | From requirements definition through memory sedimentation and continuous improvement |
| **AI Anti-Skip Rules** | Specifically designed to prevent AI agents from silently skipping steps, using summaries instead of checklists, or marking tasks complete prematurely |
| **CI/PR Guardrails** | GitHub PR template and bash compliance script for automated baseline checks |
| **Specialized Standards** | Coverage for deployment, config, DB changes, AI/LLM pipelines, test data isolation, emergency hotfixes, release, monitoring, and supply chain |

---

## Supported AI Coding Tools

This Skill leverages the `AGENTS.md` open standard, which is natively supported by:

| Tool | Status |
|---|---|
| Claude Code | Natively reads `AGENTS.md` |
| Cursor | Natively reads `AGENTS.md` |
| Codex (OpenAI) | Natively reads `AGENTS.md` |
| Windsurf | Natively reads `AGENTS.md` |
| Gemini CLI | Natively reads `AGENTS.md` |
| Qoder | Natively reads `AGENTS.md` |
| Trae | Natively reads `AGENTS.md` |
| OpenCode | Natively reads `AGENTS.md` |

> No per-tool configuration files needed. One `AGENTS.md` entry point governs all tools.

---

## Quick Start

### Install the Skill

Copy this repository (or the `SKILL.md` + `resources/` directory) into your personal or organizational Skill directory.

### Bootstrap a Repository

Open your AI coding tool (e.g., Claude Code) in any target repository and say:

> "Use dev-standards-bootstrap to initialize this repo."

The Skill will:

1. Detect existing files and avoid overwriting (shows diffs first)
2. Write `AGENTS.md` to the repo root
3. Write `DEVELOPMENT_STANDARDS.md` to `docs/`
4. Optionally add Claude Code one-line import (`CLAUDE.md`)
5. Optionally add PR template and CI compliance script
6. Optionally scaffold the first feature directory under `docs/<feature>/`

---

## Repository Structure

```
dev-standards-bootstrap/
├── SKILL.md                                # Skill manifest (trigger, execution steps, red lines)
├── README.md                               # English documentation (this file)
├── README.zh-CN.md                         # Chinese documentation
├── LICENSE                                 # MIT License
└── resources/
    ├── AGENTS.md                           # Entry point for AI agents (copied to target repo root)
    ├── DEVELOPMENT_STANDARDS.md             # Full standards document v2.16.0 (copied to docs/)
    └── templates/
        ├── CLAUDE.md                       # One-line import for Claude Code
        ├── PULL_REQUEST_TEMPLATE.md        # GitHub PR template with gate self-check
        └── check-standards-compliance.sh   # CI compliance check script
```

---

## The Five Quality Gates

```
[ Gate 1: Doc-First ]      Requirements/design must exist before any code change
        │
        ▼
[ Gate 2: Test-First ]     Test cases (TDD red-green) must exist before implementation
        │
        ▼
[ Gate 3: Evidence ]       Real test output required—no verbal claims of "done"
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
| **L3** High | Patient PII, auth, prod DB, AI/Prompt, breaking API changes, P0 hotfix | Mandatory cross-platform/cross-model | **Mandatory** (≥2 model vendors) | **Mandatory** |

---

## Contributing

Contributions are welcome! Please follow the standards defined in this repository when submitting changes:

1. Ensure documentation is updated before code changes (Gate 1)
2. Write tests first (Gate 2)
3. Provide real test output (Gate 3)
4. Close the RTVM (Gate 4)
5. Ensure independent review (Gate 5)

Pull requests should use the [PR template](resources/templates/PULL_REQUEST_TEMPLATE.md) and complete all gate self-checks.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

<div align="center">

**Standards Version:** v2.16.0 | **Last Updated:** 2026-08-24 | **Maintainer:** AI Assistant & Architecture Team

[Report Bug](../../issues) | [Request Feature](../../issues) | [Read the Standards](resources/DEVELOPMENT_STANDARDS.md)

</div>
