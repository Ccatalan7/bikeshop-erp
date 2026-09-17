#!/usr/bin/env python3
"""Build a schema-v2 research proposal from a brief and a fresh snapshot.

The brief is a small JSON the researcher writes by hand next to the archived
evidence: identity patches, facts (scalar, list or rows) and the evidence
entries that back them. This tool binds the brief to the fresh snapshot
captured by fill_snapshot_probe.py (fingerprints, revision, contract), checks
every key against the live contract (present in the template, not `legacy`),
computes the archive hashes, and writes the proposal with status
`review_ready` and an empty review record. It never invents a value: what is
not in the brief is not in the proposal.

Brief shape:
{
  "researcher": "claude",
  "identity": [{"field": "model", "proposed": "CL559R", "evidence": ["kmc-model"], "reason": "…"}],
  "facts": [{"key": "chain_speeds", "proposed": ["10"], "method": "…", "evidence": ["kmc-model"],
             "scope": "…", "reason": "…"}],
  "evidence": [{"id": "kmc-model", "kind": "oem_page", "source": "KMC", "locator": "https://…",
                "consulted_on": "2026-09-16", "scope": "…", "finding": "…",
                "artifact_path": "evidence/kmc-cl559r-20260916.md"}],
  "notes": "…"
}
`artifact_path` is relative to docs/development/product-specs-research-2026-09-05 (the simulator's evidence root); its sha256 is computed here.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--brief', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    brief = json.loads(args.brief.read_text())
    product, editor = snapshot['product'], snapshot['editor']
    fields = {f['spec_definitions']['key']: f['spec_definitions'] for f in editor['template']['fields']}
    roles = editor['template']['form_contract'].get('roles', {})
    existing = {o['definition']['key']: o for o in snapshot['observations']}
    evidence_ids = {e['id'] for e in brief['evidence']}

    evidence = []
    for entry in brief['evidence']:
        item = dict(entry)
        artifact = item.get('artifact_path')
        if artifact:
            path = RESEARCH / artifact
            if not path.is_file():
                raise SystemExit('evidence artifact not archived under the research folder: ' + artifact)
            item['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            item['artifact_path'] = artifact
        else:
            item['sha256'] = None
            item['artifact_path'] = None
        evidence.append(item)

    def current_of(key):
        # The preimage the simulator checks is the editor's resolved value
        # (an option's canonical value for a select, text for a number), not
        # the raw fact columns: a single_select fact keeps its value in
        # spec_fact_values, so reading the columns would report None and the
        # simulator would refuse the proposal with fact_preimage.
        o = existing.get(key)
        value = editor['values'].get(key)
        if o is None:
            return {'value': value, 'source': None, 'fact_id': None, 'fact_sha256': None, 'confirmed': None}
        fact = o['fact']
        return {'value': value, 'source': fact['source'], 'fact_id': fact['id'],
                'fact_sha256': o.get('fact_sha256'), 'confirmed': fact.get('confirmed')}

    facts = []
    for item in brief['facts']:
        key = item['key']
        if key not in fields or roles.get(key) == 'legacy':
            raise SystemExit('key not active in contract: ' + key)
        if not item['evidence'] or any(e not in evidence_ids for e in item['evidence']):
            raise SystemExit('fact without archived evidence: ' + key)
        facts.append({'key': key, 'current': current_of(key), 'proposed': item['proposed'],
                      'unit': fields[key].get('unit'), 'method': item['method'], 'origin': 'research',
                      'evidence': item['evidence'], 'scope': item['scope'], 'reason': item['reason']})

    identity = []
    for item in brief.get('identity', []):
        if any(e not in evidence_ids for e in item['evidence']):
            raise SystemExit('identity without archived evidence: ' + item['field'])
        identity.append({'field': item['field'], 'current': product.get(item['field']),
                         'proposed': item['proposed'], 'evidence': item['evidence'], 'reason': item['reason']})

    proposal = {
        'schema_version': 2, 'product_id': product['id'], 'researcher': brief['researcher'],
        'status': 'review_ready',
        'based_on': {'tenant_id': snapshot['tenant_id'], 'snapshot_sha256': snapshot['snapshot_sha256'],
                     'fingerprints': snapshot['fingerprints'], 'spec_revision': product['spec_revision'],
                     'updated_at': product['updated_at'], 'template_id': editor['template_id'],
                     'contract_version': editor['contract_version']},
        'identity': identity, 'reference': None, 'facts': facts, 'evidence': evidence,
        'conflicts': brief.get('conflicts', []),
        'review': {'by': None, 'verdict': 'pending', 'date': None, 'reviewed_proposal_sha256': None,
                   'notes': brief.get('notes', '')},
    }
    args.output.write_text(json.dumps(proposal, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'product': product['sku'], 'facts': len(facts),
                      'identity': len(identity), 'contract_version': editor['contract_version'],
                      'snapshot_sha256': snapshot['snapshot_sha256']}))


if __name__ == '__main__':
    main()
