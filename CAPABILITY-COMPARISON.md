# Capability Contribution Analysis: Model / Agent Harness / dev-standards-bootstrap

> **What this is**: a three-way contribution analysis based on measured data from 11 real working sessions — across the full SDLC, how much each party contributes in "LLM model × Agent Harness (tool loop / session persistence / hook integration) × dev-standards-bootstrap (governance layer)", how much is lost when the governance layer is removed, and the resulting benefits case.
>
> **Method**: one downstream integration project, 2026-09-18 to 09-22, 11 working sessions (session-DB measurements) cross-checked against git history and governance artifacts; share = party's slice of effective output per stage (evidence-triangulated estimate, not exact measurement); Harness = the execution framework wrapping the model (tool loop, session persistence, hook/gate integration points).
>
> Generated: 2026-09-22 ｜ Privacy: project and personal identifiers removed

## Summary

- Across 20 SDLC stages, the governance layer contributes a **simple average of 44%** — higher than the model (36%) and the Harness (17%).
- The value is **highly asymmetric**: for "intellectual + execution" stages (coding, test execution), the governance layer contributes almost nothing (85–95% remains without it). But for four "organizational-memory" stages — **knowledge retention, cross-session handoff, compliance audit, and change intent** — only 25–40% remains without it.
- **The essential value of governance = variance compression**: not making the model smarter, but nailing down its structural weaknesses — "smart but amnesiac, locally strong but globally weak, accurate once but unreproducible" — with machine enforcement, memory, and independence.
- Cost side: the governance machinery consumes roughly 25% of tool calls plus a resident context base; but the paired-config estimate shows **keeping the standards + tax-reduction optimizations yields ~90% attainment with a 30–50% token-cost reduction** — governance-grade quality at near-ungoverned cost.

## 1. Contribution by stage (20 stages)

Highest value per row in bold.

| # | Stage | Model (LLM) | Agent Harness | dev-standards-bootstrap | Key mechanism / evidence |
|---|---|---|---|---|---|
| 1 | Upfront research | **40%** | 20% | **40%** | Tie: model executes retrieval; standards enforce research + master-set reading + follow-up re-entry control |
| 2 | Intent / initiation | 30% | 10% | **60%** | `begin` machine-checks mandatory intent sections; incident→intent re-entry; same-day batching |
| 3 | Requirements spec | 35% | 5% | **60%** | REQ numbering + four-dimension RTVM traceability + numbering/backfill consistency checks |
| 4 | Impact analysis | **45%** | 5% | 40% | Three-dimension mandatory framework; state-trigger audit methodology |
| 5 | Solution design | **55%** | 5% | 40% | ≥2 candidate comparison; decision-record reuse |
| 6 | Task breakdown | 40% | 10% | **50%** | Structured task list + numbering chain |
| 7 | Coding | **70%** | 15% | 15% | Standards only govern WHY comments / change tags / provenance (deliberate whitespace) |
| 8 | Test-case design | 40% | 10% | **50%** | 11 coverage dimensions + scenario inventory + coverage thresholds |
| 9 | Test execution | 15% | **70%** | 15% | Builds all run via Harness; standards define gates and evidence shape |
| 10 | LLM production-chain quality | 30% | 10% | **60%** | Prompt contracts / whitelist injection / sample-value iron rules |
| 11 | Bug discovery | **25%** | 15% | 10% | Weakest stage: mostly external test feedback (~50% user side) |
| 12 | Bug root-cause analysis | 40% | 5% | **55%** | Same-family inference hit 8/10 in practice; masters read before diagnosis; ADR anchoring |
| 13 | Bug resolution | **60%** | 10% | 30% | Single-source / allowlist / no-hardcoding constraints shaping solutions |
| 14 | Regression prevention | 20% | 25% | **55%** | Three-clause mandatory regression TCs; double registration cross-check |
| 15 | Release / deploy | 20% | **40%** | **40%** | Tie: Harness executes deployments; standards define deployment records / hotfix / monitoring |
| 16 | Compliance docs / audit | 30% | 15% | **55%** | Nine audit groups + provenance stamping; 77 `die` enforcement points |
| 17 | Independent review | **45%** | 10% | **45%** | Tie: model supplies review intelligence; standards supply four-role separation + signature checks |
| 18 | Knowledge retention | 25% | 5% | **70%** | Mandatory stage 10 + experience ledger + anti-pattern registry |
| 19 | Cross-session handoff | 20% | 20% | **60%** | 12-volume project master set for cold start; disk as sole authority; ReAct logging |
| 20 | Session discipline / resource governance | 20% | **25%** | 5% | Largest gap at measurement time — closed by v3.38/v3.39 water-level & telemetry enforcement (see "Evolution note") |

## 2. Summary comparison

| Dimension | Model (LLM) | Agent Harness | dev-standards-bootstrap |
|---|---|---|---|
| Simple average (20 stages) | 36% | 17% | **44%** |
| Weighted by token cost | 0.18% (effective output) | **~60% (bears the context-cost burden)** | ~20% (resident base + 25% of tool calls) |
| Strongest stage | **Coding 70%** | **Test execution 70%** | **Retention 70%** |
| Weakest stage | Bug discovery 25% | Retention 5% | Session discipline 5% (measurement-time gap; machine-enforced since v3.38/39) |
| Stage variance | High (15–70%, intellect-driven) | Medium (5–70%, execution-concentrated) | High (5–70%, governance-polarized) |

## 3. Measured token costs (session level)

| Session | Date | Turns | Fresh input | Cache read | Output | Context/turn |
|---|---|---|---|---|---|---|
| S-1 | 09-20 | 314 | 977K | 60.5M | 96K | ~193K |
| S-2 | 09-20 | 271 | 568K | 53.5M | 80K | ~197K |
| S-3 | 09-21 | 200 | 1.39M | 47.6M | 87K | ~238K |
| S-4 | 09-22 | 192 | 825K | 36.2M | 72K | ~189K |
| S-5 | 09-20 | 90 | 257K | 17.8M | 29K | ~198K |

- Totals: fresh ~5M / cache-read ~249M (**97.5%+**) / output ~456K (0.18%); compaction triggered **0 times**.
- Interpretation: the bill is dominated not by generation but by **cache-read prefill** — an un-switched session re-reads 190K+ of context every turn. This is exactly the tax that session discipline (handoff thresholds + water-level enforcement) targets.
- Classification of 803 bash calls: governance gates/audits/stamping ~25%, real build/test ~15%, file exploration ~20%+ — the basis for the exploration-budget enforcement.

## 4. Paired configuration: with vs without the standards

**Configurations**: A = model + Harness (no standards) vs B = model + Harness + dev-standards-bootstrap.
**Method**: each standards contribution is split into "self-substitutable" (writing/execution work a model can do, at lower consistency) and "irreplaceable loss" (enforcement / memory / independence / machine checks — gone entirely); A attainment estimated against B = 100%.

| Stage group | A (no standards) attainment | Loss type |
|---|---|---|
| Coding | **95%** | Substitutable — model home turf |
| Test execution | **85%** | Substitutable — Harness runs tests anyway |
| Bug discovery | **92%** | Externally driven anyway |
| Session discipline | **95%** | No standards contribution in the measurement window (pre-enforcement) |
| Impact / design / task breakdown | 60–70% | Half-substitutable — model does the work, off-framework and leaky |
| Requirements spec / intent | 40% | **Irreplaceable** — numbering chains and intent trail vanish |
| Compliance docs / audit | **30%** | **Irreplaceable** — docs still written, no consistency enforcement |
| Cross-session handoff | **30%** | **Irreplaceable** — every session starts from amnesia |
| Retention | **25%** | **Irreplaceable** — experience evaporates |

### Summary

| Metric | Value |
|---|---|
| A average attainment (20 stages) | **~59% (i.e., B is ~41 points higher)** |
| Smallest gaps | Coding 95% / discipline 95% / discovery 92% / execution 85% (intellectual + execution) |
| Largest gaps | Retention 25% / handoff 30% / compliance 30% / intent 40% (organizational memory) |
| Cost change | Dropping the layer saves ~25% of tool calls + resident base, a 30–50% token reduction; but same-family defect recurrence and the "six-fix" pattern return — **rework claws back part of the savings** |
