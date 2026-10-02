#!/usr/bin/env python3
"""Drop the values a production rehearsal rejected because the sheet's rules say
they do not apply (a pair of shifters has no single clamp, a hub set no single
OLD). Kept aside in residual.json with the rule's message; option and schema
errors are fixed in the fill files instead, not dropped here."""
import json, sys, os
S = os.path.dirname(os.path.abspath(__file__))
cands = json.load(open(S + '/candidates_expert.json'))['candidates']
verdicts = json.load(open(sys.argv[1]))['verdicts']
drop = {}
for v in verdicts:
    if v['verdict'] == 'recorded': continue
    det = v.get('details') or ''
    issues = json.loads(det) if det.startswith('[') else []
    blocking = [i for i in issues if i.get('blocking')]
    if blocking and all(i.get('code') == 'field_applicability' for i in blocking):
        drop[(v['product_id'], v['field_key'])] = blocking[0]['message']
keep = [c for c in cands if (c['product_id'], c['field_key']) not in drop]
residual = [{**c, 'rule': drop[(c['product_id'], c['field_key'])]} for c in cands if (c['product_id'], c['field_key']) in drop]
json.dump({'candidates': keep}, open(S + '/candidates_final.json', 'w'), ensure_ascii=False, indent=0)
json.dump(residual, open(S + '/residual.json', 'w'), ensure_ascii=False, indent=1)
print(len(cands), '->', len(keep), 'dropped', len(residual))
