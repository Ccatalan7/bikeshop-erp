#!/usr/bin/env python3
"""Prepare the reviewed 37-family integration checkpoint, never activate it.

Includes the independently reviewed crank H1-H5 corrections. Remaining
mechanical, consumer and distribution gates still prevent activation.
"""
import json
from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = 'e0cccea8cdea5835e47301d11060bc735454334a9bdf6e0666b9bb5b5d87b28d'
CASES_SHA = '3d8f9a4dd6c79af3ebeeacb730506d72479a057a3ef13b29bc06e6e9175e5af8'
PREIMAGE_SHA = 'e3f3432e49057020067adb1611992a2065d3ce313a49a1a50c06250e23ce3f35'


def compile_packet():
    catalog=load_pinned(RESEARCH/'original-successors-integrated-catalog-2026-09-08.json',CATALOG_SHA)
    cases=load_pinned(RESEARCH/'original-successors-integrated-cases-2026-09-08.json',CASES_SHA)
    before=load_pinned(RESEARCH/'original-successors-integrated-preimage-2026-09-08.json',PREIMAGE_SHA)
    packet=prepare(catalog=catalog,cases=cases,before=before,
        families=[t['key'] for t in catalog['templates']],
        hashes={'catalog_sha256':CATALOG_SHA,'cases_sha256':CASES_SHA,'preimage_sha256':PREIMAGE_SHA},
        adjudication={'shared_definitions':'37 families agree on 376 canonical meanings; 152 are published and immutable.',
            'checkpoint_only':'Includes crank H1-H5 corrections delivered in message 192; integration is not activation.',
            'open_gates':'Kit member profiles, final reference/consumer/editor/distribution integration and global sanitation remain open.'})
    return packet,cases


if __name__ == '__main__':
    packet,cases=compile_packet()
    write_json(RESEARCH/'original-successors-integrated-publication-packet-2026-09-08.json',packet)
    target=ROOT/'.tmp/db/original-successors-integrated-forward-candidate.sql'
    target.write_text(generate_migration(packet,source_sha=CATALOG_SHA))
    (target.parent/'original-successors-integrated-verification.sql').write_text(generate_verifier(packet,cases))
    print(json.dumps({'templates':37,'new_definitions':len(packet['records']['spec_definitions']),
        'patches':len(packet['patches']),'cases':len(cases['cases']),'product_writes':False,'published':False}))
