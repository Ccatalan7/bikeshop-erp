#!/usr/bin/env python3
"""Rehearse exact function publication/replay and reject mixed or drifted state."""
import json
import subprocess

from compile_product_spec_strict_scalar import ROOT, compile_candidate
from compile_strict_scalar_publication import compile_publication


def main():
    before,_=compile_candidate();migration,verify=compile_publication()
    body=migration.split('begin isolation level repeatable read;',1)[1].rsplit('commit;',1)[0]
    seed='begin isolation level repeatable read;\n'+'\n;\n'.join(f['definition'] for f in before)+'\n;\n'
    first=seed+body+'\ndrop table strict_scalar_before;\n'
    tests={
        'forward_and_exact_replay':(first+body+'\nrollback;\n',None),
        'mixed_predecessor_and_new':(first+before[0]['definition']+'\n;\n'+body+'\nrollback;\n',
                                     'Unreviewed or mixed scalar-order function bodies'),
        'permission_mode_drift':(first+'alter function public.spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb) stable;\n'+body+'\nrollback;\n',
                                'Unreviewed scalar-order function permissions or mode'),
    }
    out=ROOT/'.tmp/product-spec-catalog/strict-scalar-20260915/publication-tests';out.mkdir(exist_ok=True)
    for name,(sql,error) in tests.items():
        path=out/(name+'.sql');path.write_text(sql)
        result=subprocess.run([str(ROOT/'scripts/db/query.sh'),'local','--file',str(path)],
                              cwd=ROOT,capture_output=True,text=True)
        log=result.stdout+result.stderr;(out/(name+'.log')).write_text(log)
        if ((error is None and (result.returncode or 'ROLLBACK' not in log)) or
                (error is not None and (result.returncode==0 or error not in log))):
            raise RuntimeError('Strict scalar publication regression failed: '+name)
        print('PASS: '+name)
    print(json.dumps({'publication_assertions':3,'behavior_cases':11,'rollback':True,'production_writes':0}))


if __name__=='__main__':main()
