#!/usr/bin/env python3
"""Prepare the chain/connector/kit successor for exact local evaluation."""
import json
from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = 'ab1e52a97a73ea1530d48845b7b470871f35ec7898687bbbcda71e4d80dcd1f5'
CASES_SHA = '987ec6c10317ea76e1702cd660c18dcc347e4ed97a1faaafc7523801a09dd653'
PREIMAGE_SHA = '7a1fdb10197ec113d062d5dda761c60429cff1238d4db027d0985e91fb08cbab'
FAMILIES = ['chain','chain_link','drivetrain_kit']


def compile_packet():
    catalog = load_pinned(RESEARCH/'existing-chain-drive-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH/'existing-chain-drive-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH/'existing-chain-drive-final-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog,cases=cases,before=before,families=FAMILIES,
        hashes={'catalog_sha256':CATALOG_SHA,'cases_sha256':CASES_SHA,'preimage_sha256':PREIMAGE_SHA},
        adjudication={
            'chain':'Retain the scoped published 1/8 prohibition and separate whole application tuples, nominal dimensions, contents and weighing basis.',
            'connector':'Targets are chain models/systems, not bicycle sprocket counts; retain the joining-pin single-use guard.',
            'kit':'Each component owns its identity, interface, source and target declaration; no scalar parts are inherited by the kit.',
            'legacy':'All shared definitions are immutable; retired observations remain auditable.',
            'activation_gate':'Independent review, live adoption, reference integration and client verification/distribution remain required.'})
    return packet,cases


if __name__ == '__main__':
    packet,cases = compile_packet()
    write_json(RESEARCH/'existing-chain-drive-publication-packet-2026-09-08.json',packet)
    target=ROOT/'.tmp/db/existing-chain-drive-forward-candidate.sql'
    target.write_text(generate_migration(packet,source_sha=CATALOG_SHA))
    (target.parent/'existing-chain-drive-forward-verification.sql').write_text(generate_verifier(packet,cases))
    print(json.dumps({'templates':3,'cases':len(cases['cases']),
        'new_definitions':len(packet['records']['spec_definitions']),
        'patches':len(packet['patches']),'production_writes':False}))
