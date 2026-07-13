import fs from 'node:fs';

const [leftPath, rightPath, leftName = 'left', rightName = 'right'] = process.argv.slice(2);
if (!leftPath || !rightPath) {
  console.error('Usage: node drift_summary.mjs LEFT.csv RIGHT.csv [LEFT_NAME] [RIGHT_NAME]');
  process.exit(64);
}

function readManifest(path) {
  const lines = fs.readFileSync(path, 'utf8').trim().split(/\r?\n/).slice(1);
  const rows = new Map();
  for (const line of lines) {
    if (!line) continue;
    const first = line.indexOf(',');
    const last = line.lastIndexOf(',');
    const component = line.slice(0, first);
    const identity = line.slice(first + 1, last).replace(/^"|"$/g, '').replaceAll('""', '"');
    const hash = line.slice(last + 1);
    rows.set(`${component}\u0000${identity}`, {component, identity, hash});
  }
  return rows;
}

const left = readManifest(leftPath);
const right = readManifest(rightPath);
const criticalPattern = /(stock|inventory|product|sales_(invoice|payment|return|credit)|purchase_(invoice|payment|receipt|return|credit)|journal|accounting|mechanic_job|operation_trace|checkpoint)/i;

function compare(filter = () => true) {
  const components = new Set([...left.values(), ...right.values()].filter(filter).map((row) => row.component));
  const summary = [];
  const examples = {missing: [], extra: [], changed: []};
  for (const component of [...components].sort()) {
    const counts = {component, missing: 0, extra: 0, changed: 0};
    for (const [key, row] of left) {
      if (row.component !== component || !filter(row)) continue;
      const candidate = right.get(key);
      if (!candidate) {
        counts.missing += 1;
        if (examples.missing.length < 10) examples.missing.push(`${component}: ${row.identity}`);
      } else if (candidate.hash !== row.hash) {
        counts.changed += 1;
        if (examples.changed.length < 10) examples.changed.push(`${component}: ${row.identity}`);
      }
    }
    for (const [key, row] of right) {
      if (row.component !== component || !filter(row) || left.has(key)) continue;
      counts.extra += 1;
      if (examples.extra.length < 10) examples.extra.push(`${component}: ${row.identity}`);
    }
    summary.push(counts);
  }
  return {summary, examples};
}

function printComparison(title, comparison) {
  console.log(title);
  console.log('component\tmissing\textra\tchanged');
  for (const row of comparison.summary) console.log(`${row.component}\t${row.missing}\t${row.extra}\t${row.changed}`);
  for (const [kind, values] of Object.entries(comparison.examples)) {
    if (!values.length) continue;
    console.log(`\n${kind} examples:`);
    for (const value of values) console.log(`- ${value}`);
  }
}

const all = compare();
const critical = compare((row) => criticalPattern.test(row.identity));
printComparison(`Application schema drift: ${leftName} → ${rightName}`, all);
console.log('');
printComparison('Critical inventory/accounting kernel subset', critical);

const drifted = all.summary.some((row) => row.missing || row.extra || row.changed);
process.exitCode = drifted ? 2 : 0;
