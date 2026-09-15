#!/usr/bin/env python3
"""Prepare crank-drive successor metadata for local validation, without publishing."""
import json
from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = 'b477332c223b3d667a0a2542701fca8697802d5bee5c98f703e05588448b5458'
CASES_SHA = 'f5dbf16cd23ccab9283b8f42778b4a2ded82ed4752e60c091e94216a376f8da4'
PREIMAGE_SHA = 'e74791e3bd5809d37902b5b920b4c03d67c0df53e2b24275fee1b8728e325afe'


def compile_packet():
    catalog = load_pinned(RESEARCH/'existing-crank-drive-adjudicated-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH/'existing-crank-drive-adjudicated-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH/'existing-crank-drive-final-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog, cases=cases, before=before,
        families=['crankset','crank_arm','chainring'],
        hashes={'catalog_sha256':CATALOG_SHA,'cases_sha256':CASES_SHA,'preimage_sha256':PREIMAGE_SHA},
        adjudication=catalog['root_adjudications'] | {'activation_gate':
            'H1-H5 reviewed; exact SQL/adoption, model-scoped references and client verification/distribution still govern activation.'})
    return packet,cases


if __name__ == '__main__':
    packet,cases = compile_packet()
    write_json(RESEARCH/'existing-crank-drive-publication-packet-2026-09-08.json',packet)
    target=ROOT/'.tmp/db/existing-crank-drive-forward-candidate.sql'
    target.write_text(generate_migration(packet,source_sha=CATALOG_SHA))
    (target.parent/'existing-crank-drive-forward-verification.sql').write_text(generate_verifier(packet,cases))
    print(json.dumps({'templates':3,'new_definitions':len(packet['records']['spec_definitions']),
        'patches':len(packet['patches']),'cases':len(cases['cases']),'production_writes':False}))
