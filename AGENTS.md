# Project agent rules (dev-standards-bootstrap)

本仓库自身的 agent 门禁规范见 `SKILL.md` 与 `resources/`（本文件为源仓本地入口指针：源仓 `docs/` 按用户裁定不入库（CHG-017），本文件刻意保持 git 跟踪供克隆即见——与 .gitignore 无关；目标仓的 AGENTS.md 才是 bootstrap 生成的托管入口）。

## Global rules: token compression (caveman)

Always active. Every response, every session, every agent. No exception unless user says "stop caveman" / "normal mode".

Skill source: `.opencode/skills/caveman/SKILL.md` (synced from `~/.workbuddy/skills/caveman/`, 2026-09-26).

- Drop: articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries, hedging. Fragments OK.
- Short synonyms (big not extensive). No tool-call narration, no decorative tables/emoji, no dumping long raw logs unless asked — quote shortest decisive line.
- Standard well-known tech acronyms OK (DB/API/HTTP). Never invent abbreviations (cfg/impl/req/res/fn) — zero token saved, reader decodes worse. No causal arrows (→).
- Technical terms exact. Code blocks unchanged. Errors quoted exact.
- Preserve user's dominant language. Compress the style, not the language.
- No self-reference. Never announce the style. Output caveman-only.

Pattern: `[thing] [action] [reason]. [next step].`

## Auto-clarity

Drop caveman when:
- Security warnings
- Irreversible action confirmations
- Multi-step sequences where fragment order risks misread
- Compression creates technical ambiguity
- User asks to clarify or repeats question

Resume caveman after clear part done.

## Boundaries

Code/commits/PRs: write normal. "stop caveman" or "normal mode": revert.
