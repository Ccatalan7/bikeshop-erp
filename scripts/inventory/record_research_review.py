#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema[format-nongpl]==4.26.0"]
# ///
"""Write an independent reviewer's verdict into a research proposal.

The reviewer (another session, another agent or the owner) answers with a
verdict and notes; this tool records them in the proposal's `review` block,
binds them to the exact reviewed content with `proposal_hash` (the same hash
the simulator and the sealed command use) and moves the status to `reviewed`
when the verdict is `accepted`. The researcher and the reviewer must differ,
as the applier RPC demands. It refuses to record over an existing verdict.

  uv run --script scripts/inventory/record_research_review.py --proposal p.json \
    --by claude-peer --verdict accepted --date 2026-09-16 --notes '…' --output p-reviewed.json
"""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from simulate_product_spec_research import proposal_hash  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proposal', type=Path, required=True)
    parser.add_argument('--by', required=True, choices=['codex', 'claude', 'claude-peer', 'owner'])
    parser.add_argument('--verdict', required=True, choices=['accepted', 'changes_requested', 'unresolved'])
    parser.add_argument('--date', required=True)
    parser.add_argument('--notes', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    proposal = json.loads(args.proposal.read_text())
    if proposal['review'].get('verdict') not in (None, 'pending'):
        raise SystemExit('this proposal already carries a verdict; review a fresh copy')
    if args.by == proposal['researcher']:
        raise SystemExit('the reviewer must differ from the researcher')
    # The hash covers everything but the review block, status included, so the
    # status is settled before the hash is taken.
    proposal['status'] = 'reviewed' if args.verdict == 'accepted' else 'review_ready'
    proposal['review'] = {'by': args.by, 'verdict': args.verdict, 'date': args.date,
                          'reviewed_proposal_sha256': proposal_hash(proposal), 'notes': args.notes}
    args.output.write_text(json.dumps(proposal, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'status': proposal['status'],
                      'reviewed_proposal_sha256': proposal['review']['reviewed_proposal_sha256']}))


if __name__ == '__main__':
    main()
