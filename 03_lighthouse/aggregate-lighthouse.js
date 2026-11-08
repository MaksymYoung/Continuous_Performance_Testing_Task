// Reads performance-testing-essentials-run<N>.report.json (N = 1..10) and builds an averaged report:
//   performance-testing-essentials.summary.html  - averaged report (mean/median/min/max/std dev per step and metric)
//   performance-testing-essentials.summary.csv   - the same statistics, one row per step+metric
//   performance-testing-essentials.runs.csv      - raw values, one row per run+step+metric
//
// Usage:  node aggregate-lighthouse.js [folder]     (default: the folder of this script)
// HTML/CSS templates: ./templates/summary.html, ./templates/step.html, ./templates/summary.css
// No npm packages needed.

const fs = require('fs');
const path = require('path');

const DIR = process.argv[2] ? path.resolve(process.argv[2]) : __dirname;
const PREFIX = 'performance-testing-essentials';
const OUT_HTML = path.join(DIR, `${PREFIX}.summary.html`);
const OUT_SUMMARY_CSV = path.join(DIR, `${PREFIX}.summary.csv`);
const OUT_RUNS_CSV = path.join(DIR, `${PREFIX}.runs.csv`);

// key = column id; audit = Lighthouse audit id (null = performance category score)
const METRICS = [
  { key: 'fcp', audit: 'first-contentful-paint', label: 'First Contentful Paint', unit: 'ms', digits: 0 },
  { key: 'lcp', audit: 'largest-contentful-paint', label: 'Largest Contentful Paint', unit: 'ms', digits: 0 },
  { key: 'speed_index', audit: 'speed-index', label: 'Speed Index', unit: 'ms', digits: 0 },
  { key: 'tbt', audit: 'total-blocking-time', label: 'Total Blocking Time', unit: 'ms', digits: 0 },
  { key: 'cls', audit: 'cumulative-layout-shift', label: 'Cumulative Layout Shift', unit: '', digits: 3 },
  { key: 'tti', audit: 'interactive', label: 'Time to Interactive', unit: 'ms', digits: 0 },
  { key: 'inp', audit: 'interaction-to-next-paint', label: 'Interaction to Next Paint', unit: 'ms', digits: 0 },
  { key: 'performance_score', audit: null, label: 'Performance score', unit: '0-100', digits: 0 },
];

// ---------- templates ----------
// HTML and CSS live in ./templates (next to this script), not in the data folder.
const TEMPLATES_DIR = path.join(__dirname, 'templates');

function loadTemplate(name) {
  const file = path.join(TEMPLATES_DIR, name);
  try {
    return fs.readFileSync(file, 'utf8').replace(/^<!--[\s\S]*?-->\n/, ''); // drop the leading doc comment
  } catch (error) {
    console.error(`Cannot read template ${file}: ${error.message}`);
    process.exit(1);
  }
}

// Replaces {{name}} with vars[name]; a function replacer keeps "$" in values literal.
function render(template, vars) {
  return template.replace(/\{\{(\w+)\}\}/g, (match, key) => {
    if (!(key in vars)) throw new Error(`Template placeholder {{${key}}} has no value`);
    return String(vars[key]);
  });
}

// ---------- helpers ----------
const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

function stats(values) {
  const v = values.filter(isNum).sort((a, b) => a - b);
  const n = v.length;
  if (n === 0) return null;
  const mean = v.reduce((a, b) => a + b, 0) / n;
  const median = n % 2 ? v[(n - 1) / 2] : (v[n / 2 - 1] + v[n / 2]) / 2;
  const std = n > 1 ? Math.sqrt(v.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1)) : 0; // sample std dev
  return { n, mean, median, min: v[0], max: v[n - 1], std };
}

const fmt = (v, digits) => (isNum(v) ? v.toFixed(digits) : 'n/a');
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const csvCell = (v) => {
  const s = String(v ?? '');
  return /[",\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const csvRow = (cells) => cells.map(csvCell).join(',');

function metricValue(lhr, metric) {
  if (metric.audit === null) {
    const score = lhr.categories?.performance?.score;
    return isNum(score) ? score * 100 : null;
  }
  const value = lhr.audits?.[metric.audit]?.numericValue;
  return isNum(value) ? value : null;
}

// ---------- load runs ----------
const runFiles = fs.readdirSync(DIR)
  .map((file) => ({ file, match: file.match(new RegExp(`^${PREFIX}-run(\\d+)\\.report\\.json$`)) }))
  .filter((x) => x.match)
  .map((x) => ({ file: x.file, run: Number(x.match[1]) }))
  .sort((a, b) => a.run - b.run);

if (runFiles.length === 0) {
  console.error(`No ${PREFIX}-run<N>.report.json files found in ${DIR}`);
  process.exit(1);
}

const stepOrder = []; // step names in the order of the flow
const data = {}; // data[step][metricKey] = [{ run, value }]
const runs = []; // successfully loaded runs
let fetchTimes = [];

for (const { file, run } of runFiles) {
  let flow;
  try {
    flow = JSON.parse(fs.readFileSync(path.join(DIR, file), 'utf8'));
  } catch (error) {
    console.warn(`Skipping ${file}: cannot parse JSON (${error.message})`);
    continue;
  }
  if (!Array.isArray(flow.steps)) {
    console.warn(`Skipping ${file}: no "steps" array`);
    continue;
  }

  runs.push(run);
  for (const step of flow.steps) {
    const name = step.name;
    if (!data[name]) {
      data[name] = {};
      stepOrder.push(name);
    }
    if (step.lhr?.fetchTime) fetchTimes.push(step.lhr.fetchTime);
    for (const metric of METRICS) {
      const value = metricValue(step.lhr || {}, metric);
      if (value === null) continue;
      (data[name][metric.key] ||= []).push({ run, value });
    }
  }
}

if (runs.length === 0) {
  console.error('No valid run reports could be loaded.');
  process.exit(1);
}

const gatherModeByStep = {};
for (const { file } of runFiles.slice(0, 1)) {
  try {
    const flow = JSON.parse(fs.readFileSync(path.join(DIR, file), 'utf8'));
    for (const step of flow.steps) gatherModeByStep[step.name] = step.lhr?.gatherMode || '';
  } catch (_) { /* ignore */ }
}

fetchTimes = fetchTimes.sort();
const period = fetchTimes.length
  ? `${fetchTimes[0].replace('T', ' ').slice(0, 19)} - ${fetchTimes[fetchTimes.length - 1].replace('T', ' ').slice(0, 19)} UTC`
  : 'n/a';

// ---------- statistics ----------
const rows = []; // one per step + metric
for (const step of stepOrder) {
  for (const metric of METRICS) {
    const list = data[step][metric.key];
    if (!list) continue;
    const s = stats(list.map((x) => x.value));
    rows.push({ step, metric, stat: s, list });
  }
}

// ---------- CSV ----------
const summaryCsv = [csvRow(['step', 'metric', 'unit', 'runs', 'mean', 'median', 'min', 'max', 'std_dev'])];
for (const r of rows) {
  const d = r.metric.digits;
  summaryCsv.push(csvRow([r.step, r.metric.label, r.metric.unit, r.stat.n,
    fmt(r.stat.mean, d), fmt(r.stat.median, d), fmt(r.stat.min, d), fmt(r.stat.max, d), fmt(r.stat.std, d)]));
}
fs.writeFileSync(OUT_SUMMARY_CSV, '\uFEFF' + summaryCsv.join('\n') + '\n', 'utf8'); // BOM: Excel opens UTF-8 correctly

const runsCsv = [csvRow(['run', 'step', 'metric', 'unit', 'value'])];
for (const r of rows) {
  for (const item of r.list) {
    runsCsv.push(csvRow([item.run, r.step, r.metric.label, r.metric.unit, fmt(item.value, r.metric.digits + 2)]));
  }
}
fs.writeFileSync(OUT_RUNS_CSV, '\uFEFF' + runsCsv.join('\n') + '\n', 'utf8');

// ---------- HTML ----------
const PAGE_TEMPLATE = loadTemplate('summary.html');
const STEP_TEMPLATE = loadTemplate('step.html');

function stepSection(step) {
  const stepRows = rows.filter((r) => r.step === step);
  const mode = gatherModeByStep[step];

  const statRows = stepRows.map((r) => {
    const d = r.metric.digits;
    const unit = r.metric.unit ? ` <span class="unit">${esc(r.metric.unit)}</span>` : '';
    return `<tr><th scope="row">${esc(r.metric.label)}${unit}</th><td>${r.stat.n}</td>`
      + `<td class="key">${fmt(r.stat.median, d)}</td><td>${fmt(r.stat.mean, d)}</td>`
      + `<td>${fmt(r.stat.min, d)}</td><td>${fmt(r.stat.max, d)}</td><td>${fmt(r.stat.std, d)}</td></tr>`;
  }).join('\n');

  // per-run table: rows = runs, columns = metrics available in this step
  const metricsInStep = stepRows.map((r) => r.metric);
  const head = metricsInStep.map((m) => `<th>${esc(m.label)}${m.unit ? `<br><span class="unit">${esc(m.unit)}</span>` : ''}</th>`).join('');
  const runRows = runs.map((run) => {
    const cells = stepRows.map((r) => {
      const item = r.list.find((x) => x.run === run);
      if (!item) return '<td>n/a</td>';
      const outlier = r.stat.std > 0 && Math.abs(item.value - r.stat.mean) > 2 * r.stat.std;
      return `<td${outlier ? ' class="outlier" title="more than 2 std dev from the mean"' : ''}>${fmt(item.value, r.metric.digits)}</td>`;
    }).join('');
    const reportLink = fs.existsSync(path.join(DIR, `${PREFIX}-run${run}.report.html`))
      ? `<a href="${PREFIX}-run${run}.report.html">run ${run}</a>` : `run ${run}`;
    return `<tr><th scope="row">${reportLink}</th>${cells}</tr>`;
  }).join('\n');

  return render(STEP_TEMPLATE, {
    title: esc(step),
    modeTag: mode ? ` <span class="tag">${esc(mode)}</span>` : '',
    statRows,
    runCount: runs.length,
    runsHead: head,
    runRows,
  });
}

const overallScore = rows.filter((r) => r.metric.key === 'performance_score');
const scoreOverview = overallScore.map((r) =>
  `<tr><th scope="row">${esc(r.step)}</th><td class="key">${fmt(r.stat.median, 0)}</td><td>${fmt(r.stat.mean, 1)}</td>`
  + `<td>${fmt(r.stat.min, 0)}</td><td>${fmt(r.stat.max, 0)}</td></tr>`).join('\n');

const html = render(PAGE_TEMPLATE, {
  css: loadTemplate('summary.css').trimEnd().split('\n').map((l) => (l ? '  ' + l : l)).join('\n'),
  runCount: runs.length,
  runList: runs.join(', '),
  period: esc(period),
  scoreRows: scoreOverview || '<tr><td colspan="5">n/a</td></tr>',
  steps: stepOrder.map(stepSection).join('\n'),
});
fs.writeFileSync(OUT_HTML, html, 'utf8');

console.log(`Aggregated ${runs.length} run(s): ${runs.join(', ')}`);
console.log(`Saved:\n${OUT_HTML}\n${OUT_SUMMARY_CSV}\n${OUT_RUNS_CSV}`);
