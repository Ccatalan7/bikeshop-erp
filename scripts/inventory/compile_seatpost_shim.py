#!/usr/bin/env python3
"""Build a piece-owned seatpost reducing sleeve, without copying product facts."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import uuid

from compile_non_drivetrain_publication import (
    ROOT, RESEARCH, TENANT, metadata_records, generate_migration,
    generate_verifier, write_json)
from compile_product_spec_catalog import validate_contract

KEY = 'seatpost_shim'
PREFIX = 'seatpost-shim-2026-09-15'
ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-template:' + KEY))
ROUND = 'Circular'
OEM = 'Perfil específico del fabricante'
UNKNOWN = 'Desconocido / sin confirmar'
# Existing global definitions of the inherited seatpost branch (production IDs
# fa6ff71e-7b9b-5415-8669-a0dfe586d6c8 / f091e753-d9f4-5b85-9f1b-2556821054ec):
# the sleeve's inner bore is the post it accepts, its outer face is the frame bore.
POST = 'shim_inner_diameter_mm'
FRAME = 'shim_outer_diameter_mm'
LENGTH = 'seatpost_shim_length_mm'
SUPPORT = 'seatpost_shim_support_length_mm'
REUSED = {'spec_evidence_source', 'material', 'weight_g', LENGTH, POST, FRAME}
STRICT_SCALAR_MIGRATION = '20260915200000'
STRICT_SCALAR_FUNCTIONS = {
    'spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)': 'be905e64b956bff3c947784d791a7c00',
    'spec_coherence_metadata_internal_v1(jsonb,jsonb)': '1ac8377c198430e211730278917cfdf3',
    'spec_coherence_pairs_internal_v1(jsonb,jsonb)': '7eedf2cd0074f0d14fa89a8f145b5c8f',
    'spec_coherence_publication_guard_internal_v1()': 'f95f1176094ae7376a826a85b0dbd8f0',
}


def definition(key, label, kind='number', options=(), unit=None):
    return {'id': str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-definition:' + key)),
            'key': key, 'label': label, 'data_type': kind, 'unit': unit,
            'origin': 'new', 'used_by': [KEY], 'allowed_values': list(options),
            'validation_rules': {'positive': True} if kind == 'number' else {}}


def new_definitions():
    items = [
        definition('seatpost_shim_shape', 'Geometría del casquillo', 'single_select', (ROUND, OEM, UNKNOWN)),
        definition('seatpost_shim_oem_interface', 'Perfil e interfaz específicos del fabricante', 'text'),
        definition(SUPPORT, 'Longitud de apoyo útil declarada', unit='mm'),
        definition('seatpost_shim_mount_instructions', 'Condiciones de montaje del fabricante', 'text'),
    ]
    return {d['key']: d for d in items}


def preimage_query():
    keys = ','.join("'" + k + "'" for k in sorted(REUSED | set(new_definitions())))
    return f"""select jsonb_build_object('tenant_id','{TENANT}',
 'captured_at',transaction_timestamp(),
 'template_collisions',(select coalesce(jsonb_agg(to_jsonb(t)),'[]')
  from public.spec_templates t where t.key='{KEY}' or t.id='{ID}'),
 'existing_definitions',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('options',
  (select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
   from public.spec_definition_values v where v.spec_definition_id=d.id)) order by d.key,d.id),'[]')
  from public.spec_definitions d where d.key in ({keys})
   and (d.tenant_id is null or d.tenant_id='{TENANT}'))) as metadata;\n"""


def when_shape(value):
    return {'kind': 'when', 'rows': [[{'field': 'seatpost_shim_shape',
        'operator': 'eq', 'value_type': 'token', 'value': value}]]}


def build_catalog(before):
    if before['tenant_id'] != TENANT or before['template_collisions']:
        raise ValueError('New shim identity or tenant scope changed')
    live = before['existing_definitions']
    if (len(live) != len(REUSED) or {d['key'] for d in live} != REUSED or
            any(d['tenant_id'] is not None for d in live)):
        raise ValueError('Review missing or colliding definitions')
    defs = {d['key']: {**deepcopy(d), 'origin': 'existing',
                      'allowed_values': [o['label'] for o in d['options'] if o['is_active']]}
            for d in live}
    defs.update(new_definitions())
    contract = {'rules_version': 2, 'roles': {}, 'semantic_roles': {},
                'labels': {LENGTH:'Longitud total del casquillo',
                           POST:'Diámetro nominal de tija admitida',
                           FRAME:'Diámetro nominal del alojamiento en el cuadro'},
                'allowed_options': {'material':['Aluminio','Acero','Acero inoxidable',
                    'Titanio','Carbono','Plástico','Nylon','Latón','Otro']},
                'allowed_when': {}, 'required_when': {},
                'prerequisites': {}, 'helpers': {}, 'evidence_requirements': {},
                'scalar_ordered_pairs': [[POST, FRAME, 'lt'], [SUPPORT, LENGTH]]}
    keys = ['spec_evidence_source', 'seatpost_shim_shape', POST, FRAME,
            'seatpost_shim_oem_interface', LENGTH, SUPPORT, 'material', 'weight_g',
            'seatpost_shim_mount_instructions']
    for key in keys:
        declaration = key in {'spec_evidence_source', 'seatpost_shim_mount_instructions'}
        contract['roles'][key] = 'declaration' if declaration else 'measurement'
        contract['semantic_roles'][key] = 'evidence' if declaration else 'compatibility'
        allowed = when_shape(ROUND) if key in {POST, FRAME} else (
            when_shape(OEM) if key == 'seatpost_shim_oem_interface' else {'kind':'always'})
        required = allowed if key in {POST, FRAME, 'seatpost_shim_oem_interface'} else (
            {'kind':'always'} if key in {'spec_evidence_source','seatpost_shim_shape'} else {'kind':'never'})
        contract['allowed_when'][key] = allowed
        contract['required_when'][key] = required
        deps = [] if key == 'spec_evidence_source' else ['spec_evidence_source']
        if key in {POST, FRAME, 'seatpost_shim_oem_interface'}:
            deps.append('seatpost_shim_shape')
        if key == SUPPORT:
            deps.append(LENGTH)
        contract['prerequisites'][key] = deps
        contract['evidence_requirements'][key] = 'oem_or_measurement'
    contract['helpers'] = {
        'seatpost_shim_shape': 'Una pieza concreta. No mezclar medidas de variantes ni conjuntos de casquillos.',
        POST: 'Medida nominal de la tija que acepta esta pieza; no un intervalo de diámetros.',
        FRAME: 'Medida nominal del ajuste interior del cuadro. No es el diámetro exterior del tubo ni el de su abrazadera.',
        'seatpost_shim_oem_interface': 'Identifica el perfil o código OEM de esta pieza. No sustituir una forma específica por un diámetro circular.',
        LENGTH: 'Longitud física de esta pieza cuando la fuente la publica; no determina la inserción mínima de la tija en el cuadro.',
        SUPPORT: 'Sólo la zona útil de apoyo declarada. No puede superar la longitud total del casquillo.',
        'material': 'Material del casquillo indicado por la fuente. No determina qué materiales de cuadro o tija admite.',
        'seatpost_shim_mount_instructions': 'Conserva las condiciones de la fuente para esta variante: montaje, materiales y restricciones. La coincidencia de diámetros por sí sola no acredita una instalación.',
    }
    fields = [{'key':key, 'section_key': ('declaration' if key=='spec_evidence_source' else
              'compatibility' if key in {POST,FRAME,'seatpost_shim_oem_interface','seatpost_shim_mount_instructions'} else 'construction'),
              'sort_order':i*10, 'is_required':False, 'visibility_rules':[],
              'option_rules':[], 'constraint_rules':[], 'helper_text':None, 'default_value_json':None}
              for i,key in enumerate(keys)]
    validate_contract(KEY, contract, defs, set(defs))
    template = {'id':ID, 'key':KEY, 'name':'Casquillo reductor de tija',
                'technical_family':KEY, 'origin':'new', 'form_contract':contract, 'fields':fields}
    return {'schema_version':2, 'templates':[template], 'definitions':defs,
            'publication_authorized':False, 'automatic_fill_authorized':False,
            'mechanical_coverage_complete':False}


def build_cases(sha):
    source = {'spec_evidence_source':'Synthetic fixture; no inventory claim.'}
    base = {**source,'seatpost_shim_shape':ROUND,POST:'27.2',FRAME:'30.9',LENGTH:'100'}
    cases=[]
    def add(name, values, blocking=(), pending=()):
        blocked=[{'code':c,'field':k} for c,k in blocking]
        hints=[{'code':c,'field':k,'blocking':False} for c,k in pending]
        case={'id':KEY+'_'+name,'template':KEY,'values':values,
              'expected_blocking':blocked,'expected_issue_subset':hints,
              'expected_sql_blocking':sorted(deepcopy(blocked),key=lambda x:(x['code'],x['field'])),
              'expected_sql_issue_subset':[{**p,'code':'prerequisite_missing' if p['code']=='prerequisite' else p['code']} for p in hints],
              'facts_verified_for_product':False,'automatic_fill_authorized':False}
        for issue in case['expected_sql_blocking']:
            if issue['code'] in {'constraint','range','type'}:issue['code']='field_constraint'
        cases.append(case)
    add('empty',{},pending=(('required_missing','spec_evidence_source'),('required_missing','seatpost_shim_shape')))
    add('no_published_length',{k:v for k,v in base.items() if k!=LENGTH})
    add('circular_valid',base)
    add('other_discrete_nominal',{**base,FRAME:'31.6'})
    add('documented_material',{**base,'material':'Aluminio'})
    add('apparel_material_not_a_shim_option',{**base,'material':'Algodón'},blocking=(('constraint','material'),))
    add('title_30_stays_30',{**base,FRAME:'30'})
    add('equal_nominal_diameters',{**base,FRAME:'27.2'},blocking=(('range_order',POST),('range_order',FRAME)))
    add('reversed_nominal_diameters',{**base,POST:'31.6'},blocking=(('range_order',POST),('range_order',FRAME)))
    add('positive_small_difference',{**base,POST:'27.200000000000000001',FRAME:'27.200000000000000002'})
    add('missing_post',{k:v for k,v in base.items() if k!=POST},pending=(('required_missing',POST),))
    add('missing_frame',{k:v for k,v in base.items() if k!=FRAME},pending=(('required_missing',FRAME),))
    add('unknown_geometry',{**source,'seatpost_shim_shape':UNKNOWN,LENGTH:'100'})
    add('specific_geometry',{**source,'seatpost_shim_shape':OEM,'seatpost_shim_oem_interface':'Synthetic profile drawing S1',LENGTH:'100'})
    add('specific_needs_interface',{**source,'seatpost_shim_shape':OEM,LENGTH:'100'},pending=(('required_missing','seatpost_shim_oem_interface'),))
    add('circular_cannot_keep_specific_code',{**base,'seatpost_shim_oem_interface':'S1'},blocking=(('field_applicability','seatpost_shim_oem_interface'),))
    add('specific_cannot_keep_round_diameters',{**base,'seatpost_shim_shape':OEM,'seatpost_shim_oem_interface':'S1'},blocking=(('field_applicability',POST),('field_applicability',FRAME)))
    add('support_within_length',{**base,SUPPORT:'90'})
    add('support_equals_length',{**base,SUPPORT:'100'})
    add('support_exceeds_length',{**base,SUPPORT:'101'},blocking=(('range_order',SUPPORT),('range_order',LENGTH)))
    add('support_needs_length',{**{k:v for k,v in base.items() if k!=LENGTH},SUPPORT:'90'},pending=(('prerequisite',SUPPORT),))
    add('zero_post',{**base,POST:'0'},blocking=(('range',POST),))
    add('zero_length',{**base,LENGTH:'0'},blocking=(('range',LENGTH),))
    add('no_multivariant_range',{**base,FRAME:'30.9-31.6'},blocking=(('type',FRAME),))
    add('no_cartesian_array',{**base,POST:['27.2','30.9']},blocking=(('type',POST),))
    return {'schema_version':1,'catalogue_sha256':sha,'cases':cases}


def main():
    if sys.argv[1:] == ['--query']:
        print(preimage_query());return
    if len(sys.argv)!=2:raise SystemExit('Usage: compile_seatpost_shim.py preimage.json | --query')
    path=Path(sys.argv[1]);before=json.loads(path.read_text())[0]['metadata']
    catalog=build_catalog(before);cp=RESEARCH/(PREFIX+'-catalog.json');write_json(cp,catalog)
    sha=hashlib.sha256(cp.read_bytes()).hexdigest();cases=build_cases(sha)
    write_json(RESEARCH/(PREFIX+'-cases.json'),cases)
    records=metadata_records(catalog['templates'],catalog['definitions'],REUSED)
    records['spec_templates'][0]['contract_version']=1+len(records['spec_template_fields'])
    for d in records['spec_definitions']:
        d['is_customer_visible']=True
        d['is_filterable']=d['data_type'] in {'number','single_select'}
    packet={'schema_version':1,'scope':'new_global_metadata_only','audited_tenant_id':TENANT,
            'catalog_sha256':sha,'preimage_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'families':[KEY],'reused_definitions':before['existing_definitions'],'records':records,
            'product_writes':False,'fill_allowed':False,'mechanical_approval':False,
            'adjudication':{'owner':'One physical reducing sleeve; exact nominal pair, not variant ranges',
                           'reused_interfaces':[POST,FRAME],
                           'total_length_required':False,
                           'requires_strict_scalar_extension':True,
                           'publication_dependency':{'migration':STRICT_SCALAR_MIGRATION,'functions':STRICT_SCALAR_FUNCTIONS}}}
    write_json(RESEARCH/(PREFIX+'-packet.json'),packet)
    migration=generate_migration(packet,source_sha=sha)
    anchor="   raise exception 'Unreviewed specification validator';\n end if;\n"
    if migration.count(anchor)!=1:raise ValueError('Review the publisher guard before adding the engine dependency')
    engine=' if '+' or '.join(f"md5(pg_get_functiondef(to_regprocedure('public.{sig}'))) is distinct from '{md5}'" for sig,md5 in sorted(STRICT_SCALAR_FUNCTIONS.items()))
    engine+=f" then\n   raise exception 'Strict scalar order extension {STRICT_SCALAR_MIGRATION} is not published';\n end if;\n"
    migration=migration.replace(anchor,anchor+engine)
    (ROOT/'.tmp/db'/(PREFIX+'-candidate.sql')).write_text(migration)
    (ROOT/'.tmp/db'/(PREFIX+'-verification.sql')).write_text(generate_verifier(packet,cases))
    print(json.dumps({'templates':1,'new_definitions':len(records['spec_definitions']),
                      'fields':len(records['spec_template_fields']),'cases':len(cases['cases']),
                      'applied':False,'fills':0}))


if __name__=='__main__':main()
