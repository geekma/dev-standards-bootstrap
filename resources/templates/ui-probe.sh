#!/usr/bin/env bash
# ui-probe.sh — Optional DOM geometry & runtime probe for ui_change (v4.16.0, CHG-166, Batch F F-1).
# Exits 3 cleanly when Node or Playwright is unavailable (never produces a fake green).
set -euo pipefail

TOOL_VERSION="1.0.0"

probe_usage() {
  cat <<'EOF' >&2
Usage:
  scripts/ui-probe.sh --check
  scripts/ui-probe.sh --eval-fixture <fixture.json> [--out <ui-probe.json>] [--waivers <waivers.json>] [--fail-on-violation]
  scripts/ui-probe.sh --url <url-or-file> [--url ...] [--spec <03.6-ui-spec.md>] [--viewports 360,390,768,1280,1920] [--out <ui-probe.json>] [--evidence-dir <dir>] [--waivers <waivers.json>] [--fail-on-violation]
Exit codes: 0=pass, 2=violations detected (with --fail-on-violation), 3=unavailable (missing node/playwright), 1=usage/runtime error
EOF
}

probe_node_bin() {
  command -v node 2>/dev/null || return 1
}

probe_playwright_available() {
  local mock="${AGENT_GUARD_UI_PROBE_MOCK:-}"
  if [[ "$mock" == "unavailable" ]]; then return 1; fi
  if [[ "$mock" == "available" ]]; then return 0; fi
  local nb
  nb=$(probe_node_bin) || return 1
  "$nb" -e '
    const fs = require("fs");
    const path = require("path");
    const candidates = ["playwright", "playwright-core"];
    if (process.env.AGENT_GUARD_PLAYWRIGHT_PATH) candidates.unshift(process.env.AGENT_GUARD_PLAYWRIGHT_PATH);
    let ok = false;
    for (const c of candidates) {
      try { require.resolve(c); ok = true; break; } catch (_) {}
      const localNm = path.join(process.cwd(), "node_modules", c);
      if (fs.existsSync(localNm)) { ok = true; break; }
    }
    process.exit(ok ? 0 : 1);
  ' >/dev/null 2>&1
}

probe_parse_viewports_from_spec() {
  local spec="$1"
  [[ -s "$spec" ]] || { printf '360,390,768,1280,1920'; return 0; }
  local vps=""
  vps=$(awk '
    /^##[[:space:]]+多端适配/ { insec=1; next }
    insec && /^##[[:space:]]/ { exit }
    insec && /^\|/ {
      n = split($0, cols, "|")
      w = ""; app = ""
      if (n >= 4) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[3])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[4])
        w = cols[3]; app = cols[4]
      }
      if (w ~ /^(360|390|768|1280|1920)$/ && app !~ /^否/) {
        out = (out == "" ? w : out "," w)
      }
    }
    END { print out }
  ' "$spec" 2>/dev/null || true)
  printf '%s' "${vps:-360,390,768,1280,1920}"
}

CHECK_ONLY=0
FIXTURE=""
OUT_PATH=""
WAIVERS_PATH=""
SPEC_PATH=""
EVIDENCE_DIR=""
VIEWPORTS=""
FAIL_ON_VIOL=0
URLS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --eval-fixture) FIXTURE="${2:-}"; shift 2 ;;
    --url) URLS+=("${2:-}"); shift 2 ;;
    --spec) SPEC_PATH="${2:-}"; shift 2 ;;
    --viewports) VIEWPORTS="${2:-}"; shift 2 ;;
    --out) OUT_PATH="${2:-}"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="${2:-}"; shift 2 ;;
    --waivers) WAIVERS_PATH="${2:-}"; shift 2 ;;
    --fail-on-violation) FAIL_ON_VIOL=1; shift ;;
    -h|--help) probe_usage; exit 0 ;;
    *) echo "ui-probe: unknown argument '$1'" >&2; probe_usage; exit 1 ;;
  esac
done

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  if probe_playwright_available; then
    echo "ui-probe: available (node + playwright ready)"
    exit 0
  else
    echo "ui-probe: unavailable — node or playwright not found (use F-5 manual B-layer checklist)" >&2
    exit 3
  fi
fi

NODE_BIN=$(probe_node_bin) || {
  echo "ui-probe: unavailable — node executable not found" >&2
  exit 3
}

# Pure Node deterministic geometry evaluator shared by fixture unit mode and browser capture mode
run_eval_fixture() {
  local fix="$1" out="$2" wfile="$3" failv="$4"
  [[ -s "$fix" ]] || { echo "ui-probe: fixture file not found: $fix" >&2; exit 1; }
  "$NODE_BIN" - "$fix" "$out" "$wfile" "$failv" "$TOOL_VERSION" <<'NODESCRIPT'
const fs = require("fs");
const [,, fixPath, outPath, waiversPath, failOnViol, toolVer] = process.argv;
const fx = JSON.parse(fs.readFileSync(fixPath, "utf8"));
let waivers = [];
if (waiversPath && fs.existsSync(waiversPath)) {
  waivers = JSON.parse(fs.readFileSync(waiversPath, "utf8"));
} else if (Array.isArray(fx.waivers)) {
  waivers = fx.waivers;
}

function rectsOverlapArea(a, b) {
  const x1 = Math.max(a[0], b[0]);
  const y1 = Math.max(a[1], b[1]);
  const x2 = Math.min(a[0] + a[2], b[0] + b[2]);
  const y2 = Math.min(a[1] + a[3], b[1] + b[3]);
  if (x2 <= x1 || y2 <= y1) return 0;
  return (x2 - x1) * (y2 - y1);
}

function evalSnapshot(snap) {
  const vp = Number(snap.viewport || 1280);
  const viols = [];
  if (Number(snap.docScrollWidth || 0) > Number(snap.innerWidth || vp)) {
    viols.push({
      kind: "overflow-x",
      selector: "document.scrollingElement",
      rect: [0, 0, Number(snap.docScrollWidth), 1],
      confidence: "high"
    });
  }
  const els = Array.isArray(snap.elements) ? snap.elements : [];
  for (const el of els) {
    const r = el.rect || [0, 0, 0, 0];
    if (el.clipped) {
      viols.push({ kind: "clipped", selector: el.selector || "unknown", rect: r, confidence: "high" });
    }
    if (el.interactive && el.occluded) {
      viols.push({ kind: "occluded", selector: el.selector || "unknown", rect: r, confidence: "high" });
    }
    if (vp <= 768 && el.interactive && Math.min(r[2], r[3]) < 44) {
      viols.push({ kind: "touch-target-small", selector: el.selector || "unknown", rect: r, confidence: "high" });
    }
    if (el.truncated && !el.allowTruncate) {
      viols.push({ kind: "text-truncated", selector: el.selector || "unknown", rect: r, confidence: "low" });
    }
    if (typeof el.fontSize === "number" && el.fontSize < 12) {
      viols.push({ kind: "small-font", selector: el.selector || "unknown", rect: r, confidence: "high" });
    }
    if (el.isImage && el.complete && Number(el.naturalWidth || 0) === 0) {
      viols.push({ kind: "broken-image", selector: el.selector || "img", rect: r, confidence: "high" });
    }
  }
  for (let i = 0; i < els.length; i++) {
    const a = els[i];
    if (!a.parentId || !a.inFlow || a.allowOverlap) continue;
    for (let j = i + 1; j < els.length; j++) {
      const b = els[j];
      if (!b.inFlow || b.allowOverlap || a.parentId !== b.parentId) continue;
      if (rectsOverlapArea(a.rect || [0,0,0,0], b.rect || [0,0,0,0]) > 0) {
        viols.push({ kind: "sibling-overlap", selector: `${a.selector}+${b.selector}`, rect: a.rect, confidence: "medium" });
      }
    }
  }
  const groups = {};
  for (const el of els) {
    if (!el.alignGroup) continue;
    (groups[el.alignGroup] = groups[el.alignGroup] || []).push(el);
  }
  for (const g of Object.keys(groups)) {
    const items = groups[g];
    if (items.length < 2) continue;
    const baseY = (items[0].rect || [0,0,0,0])[1];
    for (let i = 1; i < items.length; i++) {
      if (Math.abs((items[i].rect || [0,0,0,0])[1] - baseY) > 1) {
        viols.push({ kind: "align-deviation", selector: items[i].selector || g, rect: items[i].rect, confidence: "high" });
      }
    }
  }
  if (Number(snap.consoleErrors || 0) > 0) {
    viols.push({ kind: "console-error", selector: "window", rect: [0,0,0,0], confidence: "high" });
  }
  return viols;
}

const snaps = Array.isArray(fx.snapshots) ? fx.snapshots : [fx];
const results = [];
let totalHigh = 0;
for (const s of snaps) {
  const v = evalSnapshot(s);
  totalHigh += v.filter(x => x.confidence !== "low").length;
  results.push({
    viewport: Number(s.viewport || 1280),
    violations: v,
    screenshot: s.screenshot || "",
    screenshot_sha256: s.screenshot_sha256 || ""
  });
}
const report = {
  schema: 1,
  tool: "ui-probe",
  tool_version: toolVer,
  generated_at: new Date().toISOString(),
  target: fx.target || fixPath,
  viewports: results.map(r => r.viewport),
  results,
  violations_total: totalHigh,
  waivers
};
const jsonText = JSON.stringify(report);
if (outPath) {
  fs.mkdirSync(require("path").dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, jsonText + "\n", "utf8");
}
process.stdout.write(jsonText + "\n");
if (failOnViol === "1" && totalHigh > 0) process.exit(2);
NODESCRIPT
}

if [[ -n "$FIXTURE" ]]; then
  run_eval_fixture "$FIXTURE" "$OUT_PATH" "$WAIVERS_PATH" "$FAIL_ON_VIOL"
  exit $?
fi

if [[ "${#URLS[@]}" -eq 0 ]]; then
  echo "ui-probe: missing --url or --eval-fixture" >&2
  probe_usage
  exit 1
fi

if ! probe_playwright_available; then
  echo "ui-probe: unavailable — playwright not found; cannot capture live browser viewports (use F-5 manual B-layer checklist)" >&2
  exit 3
fi

if [[ -z "$VIEWPORTS" ]]; then
  VIEWPORTS=$(probe_parse_viewports_from_spec "$SPEC_PATH")
fi

OUT_FILE="${OUT_PATH:-ui-probe.json}"
EV_DIR="${EVIDENCE_DIR:-$(dirname "$OUT_FILE")}"
mkdir -p "$EV_DIR" "$(dirname "$OUT_FILE")"

URLS_CSV=$(IFS=','; echo "${URLS[*]}")

"$NODE_BIN" - "$URLS_CSV" "$VIEWPORTS" "$OUT_FILE" "$EV_DIR" "${WAIVERS_PATH:-}" "$FAIL_ON_VIOL" "$TOOL_VERSION" <<'NPLAY'
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const [,, urlsCsv, vpsCsv, outFile, evDir, waiversFile, failOnViol, toolVer] = process.argv;
let pw;
try {
  pw = require(process.env.AGENT_GUARD_PLAYWRIGHT_PATH || "playwright");
} catch (_) {
  try { pw = require("playwright-core"); } catch (e) {
    console.error("ui-probe: unavailable — failed to load playwright:", e.message);
    process.exit(3);
  }
}

const urls = urlsCsv.split(",").filter(Boolean);
const viewports = vpsCsv.split(",").map(s => Number(s.trim())).filter(n => n > 0);
let waivers = [];
if (waiversFile && fs.existsSync(waiversFile)) {
  waivers = JSON.parse(fs.readFileSync(waiversFile, "utf8"));
}

(async () => {
  const browser = await pw.chromium.launch({ headless: true });
  const results = [];
  let total = 0;
  try {
    for (let uIdx = 0; uIdx < urls.length; uIdx++) {
      const rawUrl = urls[uIdx];
      const targetUrl = rawUrl.match(/^https?:\/\//) || rawUrl.startsWith("file://")
        ? rawUrl
        : "file://" + path.resolve(rawUrl);
      for (const vp of viewports) {
        const context = await browser.newContext({ viewport: { width: vp, height: 800 } });
        const page = await context.newPage();
        let consoleErrors = 0;
        page.on("console", m => { if (m.type() === "error") consoleErrors++; });
        page.on("pageerror", () => { consoleErrors++; });
        await page.goto(targetUrl, { waitUntil: "networkidle" }).catch(() => page.goto(targetUrl));
        const viols = await page.evaluate((vpWidth) => {
          const out = [];
          const se = document.scrollingElement || document.documentElement;
          if (se && se.scrollWidth > window.innerWidth) {
            out.push({ kind: "overflow-x", selector: "document.scrollingElement", rect: [0,0,se.scrollWidth,1], confidence: "high" });
          }
          const selOf = el => el.id ? "#" + el.id : el.tagName.toLowerCase();
          const all = Array.from(document.querySelectorAll("a,button,input,select,textarea,[role=button],img,p,span,div,[data-align-group]"));
          for (const el of all) {
            const st = window.getComputedStyle(el);
            if (st.display === "none" || st.visibility === "hidden" || st.opacity === "0") continue;
            const r = el.getBoundingClientRect();
            if (r.width === 0 || r.height === 0) continue;
            const rectArr = [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)];
            let anc = el.parentElement;
            while (anc && anc !== document.body && anc !== document.documentElement) {
              const ast = window.getComputedStyle(anc);
              if (ast.overflowX !== "visible" && ast.overflowX !== "") {
                const ar = anc.getBoundingClientRect();
                if (r.right > ar.right + 1 || r.left < ar.left - 1) {
                  out.push({ kind: "clipped", selector: selOf(el), rect: rectArr, confidence: "high" });
                  break;
                }
              }
              anc = anc.parentElement;
            }
            const interactive = /^(A|BUTTON|INPUT|SELECT|TEXTAREA)$/.test(el.tagName) || el.getAttribute("role") === "button";
            if (interactive) {
              if (vpWidth <= 768 && Math.min(r.width, r.height) < 44) {
                out.push({ kind: "touch-target-small", selector: selOf(el), rect: rectArr, confidence: "high" });
              }
              const pts = [
                [r.left + r.width / 2, r.top + r.height / 2],
                [r.left + 2, r.top + 2], [r.right - 2, r.top + 2],
                [r.left + 2, r.bottom - 2], [r.right - 2, r.bottom - 2]
              ];
              let occ = false;
              for (const [px, py] of pts) {
                if (px < 0 || py < 0 || px > window.innerWidth || py > window.innerHeight) continue;
                const hit = document.elementFromPoint(px, py);
                if (hit && hit !== el && !el.contains(hit)) { occ = true; break; }
              }
              if (occ) out.push({ kind: "occluded", selector: selOf(el), rect: rectArr, confidence: "high" });
            }
            const fsPx = parseFloat(st.fontSize || "14");
            if (!isNaN(fsPx) && fsPx < 12 && (el.textContent || "").trim().length > 0) {
              out.push({ kind: "small-font", selector: selOf(el), rect: rectArr, confidence: "high" });
            }
            if (st.textOverflow === "ellipsis" && el.scrollWidth > el.clientWidth && !el.hasAttribute("data-allow-truncate")) {
              out.push({ kind: "text-truncated", selector: selOf(el), rect: rectArr, confidence: "low" });
            }
            if (el.tagName === "IMG" && el.complete && el.naturalWidth === 0) {
              out.push({ kind: "broken-image", selector: selOf(el), rect: rectArr, confidence: "high" });
            }
          }
          for (const parent of document.querySelectorAll("div,section,main,header,footer,nav,ul,ol")) {
            const kids = Array.from(parent.children).filter(k => {
              const ks = window.getComputedStyle(k);
              return ks.display !== "none" && ks.position !== "fixed" && ks.position !== "absolute" && !k.hasAttribute("data-allow-overlap");
            });
            for (let i = 0; i < kids.length; i++) {
              const ra = kids[i].getBoundingClientRect();
              if (ra.width === 0 || ra.height === 0) continue;
              for (let j = i + 1; j < kids.length; j++) {
                const rb = kids[j].getBoundingClientRect();
                if (rb.width === 0 || rb.height === 0) continue;
                if (Math.min(ra.right, rb.right) > Math.max(ra.left, rb.left) + 1 &&
                    Math.min(ra.bottom, rb.bottom) > Math.max(ra.top, rb.top) + 1) {
                  out.push({ kind: "sibling-overlap", selector: selOf(kids[i]) + "+" + selOf(kids[j]), rect: [Math.round(ra.x), Math.round(ra.y), Math.round(ra.width), Math.round(ra.height)], confidence: "medium" });
                }
              }
            }
          }
          const groups = {};
          for (const g of document.querySelectorAll("[data-align-group]")) {
            const k = g.getAttribute("data-align-group");
            (groups[k] = groups[k] || []).push(g);
          }
          for (const k of Object.keys(groups)) {
            const arr = groups[k];
            if (arr.length < 2) continue;
            const y0 = arr[0].getBoundingClientRect().top;
            for (let i = 1; i < arr.length; i++) {
              const ri = arr[i].getBoundingClientRect();
              if (Math.abs(ri.top - y0) > 1) {
                out.push({ kind: "align-deviation", selector: selOf(arr[i]), rect: [Math.round(ri.x), Math.round(ri.y), Math.round(ri.width), Math.round(ri.height)], confidence: "high" });
              }
            }
          }
          return out;
        }, vp);
        if (consoleErrors > 0) {
          viols.push({ kind: "console-error", selector: "window", rect: [0,0,0,0], confidence: "high" });
        }
        const shotName = urls.length > 1 ? `ui-${uIdx + 1}-${vp}.png` : `ui-${vp}.png`;
        const shotPath = path.join(evDir, shotName);
        await page.screenshot({ path: shotPath, fullPage: true });
        const sha = crypto.createHash("sha256").update(fs.readFileSync(shotPath)).digest("hex");
        total += viols.filter(x => x.confidence !== "low").length;
        results.push({ viewport: vp, violations: viols, screenshot: path.relative(path.dirname(path.dirname(outFile)), shotPath).replace(/\\/g, "/"), screenshot_sha256: sha });
        await context.close();
      }
    }
  } finally {
    await browser.close();
  }
  const report = {
    schema: 1,
    tool: "ui-probe",
    tool_version: toolVer,
    generated_at: new Date().toISOString(),
    target: urls.join(","),
    viewports,
    results,
    violations_total: total,
    waivers
  };
  const txt = JSON.stringify(report, null, 2) + "\n";
  fs.writeFileSync(outFile, txt, "utf8");
  process.stdout.write(txt);
  if (failOnViol === "1" && total > 0) process.exit(2);
})().catch(err => {
  console.error("ui-probe: fatal error:", err);
  process.exit(1);
});
NPLAY
