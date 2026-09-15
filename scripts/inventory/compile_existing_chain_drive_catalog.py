#!/usr/bin/env python3
"""Successors for chains, connectors and packaged drivetrain components.

Preserve the implemented chain baseline and all published observations. A
documented application is one tuple; contents and fitment have different owners.
This compiler does not write products or publish metadata.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import condition, rows, case
from compile_existing_drivetrain_service_parts_catalog import _add, _retire
from compile_wheel_small_parts_catalog import ALWAYS, NEVER, column
from compile_product_spec_catalog import validate_contract

FAMILIES = ('chain', 'chain_link', 'drivetrain_kit')
PREIMAGE = RESEARCH / 'existing-chain-drive-preimage-2026-09-08.json'
PREIMAGE_SHA = '4b19e6c99f7099b9f030db6bd834ad032eaf8cdb2fc625964fc9204f79feeddc'
EVIDENCE = 'spec_evidence_source'
PARK = 'https://www.parktool.com/en-us/blog/repair-help/chain-compatibility'
SHELDON = 'https://www.sheldonbrown.com/chains.html'
X8 = 'https://www.kmcchain.eu/products/x8-silver'
CL573 = 'https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed'
LG = 'https://bike.shimano.com/en-AU/products/components/pdp.P-SM-CN900-11.html'
SRAM = ('https://support.sram.com/hc/en-us/articles/26180202731931-'
        'Can-I-use-an-Eagle-Drivetrain-PowerLock-on-my-Eagle-Transmission-Chain')
SYNTHETIC = 'https://example.invalid/synthetic'
MODEL, SYSTEM = 'Modelo documentado', 'Sistema documentado'
YES, NO, CONDITIONAL = 'Admitido por la fuente', 'Excluido por la fuente', 'Condicionado por la fuente'
EXTERNAL, SINGLE, IGH = 'Desviador externo', 'Una relación sin cambio interno', 'Cambio interno'


def source_columns():
    return [column('source_document', 'Documento o envase identificado', required=True),
            column('source_url', 'URL del documento, si existe', 'url')]


def claim_columns():
    return [column('claim_identity', 'Identificación de esta declaración', required=True),
            column('scope_kind', 'Alcance', 'token', required=True, options=[MODEL, SYSTEM]),
            column('target_brand', 'Marca del modelo de destino'),
            column('target_model', 'Modelo de destino'),
            column('target_generation', 'Generación del destino'),
            column('target_system', 'Sistema y generación declarados'),
            column('verdict', 'Declaración de la fuente', 'token', required=True,
                   options=[YES, NO, CONDITIONAL]),
            column('conditions', 'Condiciones y límites'), *source_columns()]


def claim_conditions():
    model, system = condition('scope_kind', MODEL), condition('scope_kind', SYSTEM)
    return {'allowed_when': {'target_brand': model, 'target_model': model,
                            'target_generation': model, 'target_system': system},
            'required_when': {'target_brand': model, 'target_model': model,
                              'target_system': system,
                              'conditions': condition('verdict', CONDITIONAL)}}


def add_table(definitions, template, key, label, columns, *, unique=(),
              allowed=ALWAYS, required=NEVER, conditions=None, role='declaration',
              semantic='declaration', helper=None):
    schema = {'version': 1, 'columns': columns}
    if unique:
        schema['unique_by'] = [list(x) for x in unique]
    _add(definitions, template, key, label, 'json', role=role, semantic=semantic,
         rules={'rows_schema': schema}, allowed=allowed, required=required, helper=helper)
    if conditions:
        template['form_contract'].setdefault('row_conditions',
            {'version': 1, 'fields': {}})['fields'][key] = conditions


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA), (PREIMAGE, PREIMAGE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Pinned input changed: ' + path.name)
    base, before = json.loads(CATALOG.read_text()), json.loads(PREIMAGE.read_text())
    templates = {t['key']: deepcopy(t) for t in base['templates'] if t['key'] in FAMILIES}
    definitions = {f['key']: deepcopy(base['definitions'][f['key']])
                   for t in templates.values() for f in t['fields']}
    for actual in before['existing_definitions']:
        key = actual['key']
        definitions[key] = {k: deepcopy(actual[k]) for k in (
            'id', 'key', 'label', 'data_type', 'unit', 'allowed_values', 'validation_rules')}
        definitions[key].update(origin='existing', used_by=[f for f,t in templates.items()
            if any(x['key'] == key for x in t['fields'])])
    for live in before['templates']:
        templates[live['key']]['name'] = live['name']
    for t in templates.values():
        # Earlier applied help is more precise than the frozen all-family draft.
        live = next(x for x in before['templates'] if x['key'] == t['key'])
        for section in ('labels', 'helpers'):
            t['form_contract'][section].update({k:v for k,v in live['form_contract'].get(section, {}).items()
                if k in t['form_contract']['roles']})
    chain(definitions, templates['chain'])
    connector(definitions, templates['chain_link'])
    kit(definitions, templates['drivetrain_kit'])
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions, {f['key'] for f in t['fields']})
    owned = {f['key'] for t in templates.values() for f in t['fields']}
    if set(definitions) != owned:
        raise ValueError('Unowned definition')
    catalog = {**base, 'title': 'Chain applications, exact connector targets and kit members',
        'templates': list(templates.values()), 'definitions': definitions,
        'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA, 'preimage': PREIMAGE_SHA},
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False,
        'source_urls': [PARK, SHELDON, X8, CL573, LG, SRAM],
        'stats': {'templates': 3, 'definitions': len(definitions),
                  'field_uses': sum(len(t['fields']) for t in templates.values())}}
    return catalog, {'cases': fixtures(), 'pending_cases': relation_fixtures()}


def chain(definitions, t):
    c = t['form_contract']
    _retire(t, ['drivetrain_primary_ecosystem', 'drivetrain_declared_compatible_ecosystems',
                'drivetrain_platform', 'chain_profile_family'])
    # Preserve the already deployed, narrowly scoped 1/8 + modern derailleur
    # prohibition. Broad speed declarations remain descriptive, not a join key.
    c['prerequisites']['chain_speeds'] = [EVIDENCE]
    c['helpers']['chain_speeds'] += (' Las aplicaciones siguientes conservan las '
        'condiciones por sistema; esta lista no se cruza con marcas ni plataformas.')
    for key in ('chain_width_family', 'chain_outer_width_mm', 'chain_directional',
                'link_count', 'quick_link_included'):
        c['prerequisites'][key] = [EVIDENCE]
    _add(definitions, t, 'chain_pitch_mm', 'Paso nominal entre pasadores', 'number',
         unit='mm', rules={'positive': True})
    c['prerequisites']['chain_pitch_mm'] = [EVIDENCE]
    _add(definitions, t, 'chain_other_width_designation', 'Otra denominación de ancho',
         'text', allowed=condition('chain_width_family', 'Otro'),
         required=condition('chain_width_family', 'Otro'))
    applications = 'chain_application_declarations'
    cond = claim_conditions()
    cond['allowed_when']['rear_sprockets'] = condition('drive_kind', EXTERNAL)
    cond['allowed_when']['internal_gears'] = condition('drive_kind', IGH)
    # An OEM may state a named system without an explicit number of gears.
    # Neither gear count is inferred nor required merely to name that system.
    add_table(definitions, t, applications, 'Aplicaciones documentadas de esta cadena',
        [*claim_columns(), column('drive_kind', 'Tipo de transmisión de esta aplicación',
            'token', required=True, options=[EXTERNAL, SINGLE, IGH]),
         column('rear_sprockets', 'Piñones de esta aplicación', 'integer', positive=True),
         column('internal_gears', 'Marchas internas declaradas', 'integer', positive=True),
         column('chain_class', 'Clase de cadena citada por la fuente')],
        unique=[['claim_identity']], conditions=cond, required=ALWAYS,
        helper='Una fila por modelo o sistema, alcance y número documentado. '
        'Las marchas internas no son piñones; una clase HG 11 puede tener otra '
        'cobertura LINKGLIDE. La fila es una declaración, no una certificación del montaje.')
    add_table(definitions, t, 'chain_mass_declarations', 'Peso y base declarada',
        [column('weighing_identity', 'Configuración pesada', required=True),
         column('weight_g', 'Peso', 'decimal', unit='g', positive=True, required=True),
         column('basis_links', 'Eslabones usados para declarar este peso', 'integer', positive=True),
         column('basis_description', 'Qué incluye la medición', required=True), *source_columns()],
        unique=[['weighing_identity']], role='measurement', semantic='measurement',
        helper='Los eslabones de pesaje no son la longitud vendida. No se aplica '
        'una cifra de un modelo a todas sus presentaciones.')
    included = condition('quick_link_included', True, 'boolean')
    add_table(definitions, t, 'chain_quick_links_supplied', 'Cierres rápidos incluidos',
        [column('connector_identity', 'Cierre de este envase', required=True),
         column('quantity', 'Conectores completos', 'integer', positive=True, required=True),
         column('brand', 'Marca del conector'), column('model', 'Modelo del conector'),
         column('manufacturer_sku', 'Código de la presentación del conector'), *source_columns()],
        unique=[['connector_identity']], allowed=included, required=included,
        role='contents', semantic='contents',
        helper='Dos mitades forman un cierre. Su presencia no establece reutilización '
        'ni compatibilidad con otras cadenas.')


def connector(definitions, t):
    c = t['form_contract']
    _retire(t, ['chain_connector_target', 'drivetrain_primary_ecosystem',
                'drivetrain_declared_compatible_ecosystems', 'chain_profile_family', 'drivetrain_mode'])
    c['prerequisites']['chain_speeds'] = ['chain_connector_type', EVIDENCE]
    for key in ('chain_width_family', 'chain_outer_width_mm', 'chain_link_pack_qty'):
        c['prerequisites'][key] = ['chain_connector_type', EVIDENCE]
    # The existing pin non-reusability constraint is retained on its field use.
    _add(definitions, t, 'connector_reuse_limit', 'Máximo de usos declarado', 'number',
         role='declaration', semantic='declaration', rules={'positive': True, 'integer': True},
         allowed=condition('chain_link_reusable', True, 'boolean'))
    c['prerequisites']['connector_reuse_limit'] = [EVIDENCE]
    add_table(definitions, t, 'connector_target_declarations', 'Cadenas admitidas o excluidas',
        [*claim_columns(), column('chain_class', 'Clase de cadena de esta declaración')],
        unique=[['claim_identity']], conditions=claim_conditions(), required=ALWAYS,
        helper='El destino es la cadena, con modelo/generación o sistema explícito. '
        'No es el cambio de la bicicleta. Igual marca, velocidad o silueta no '
        'demuestran que el cierre sirva; una exclusión permanece en su propio alcance.')
    c['prerequisites']['connector_target_declarations'] = ['chain_connector_type']


def kit(definitions, t):
    c = t['form_contract']
    keep = {'kit_members', 'kit_contents', EVIDENCE}
    _retire(t, [f['key'] for f in t['fields'] if f['key'] not in keep])
    c['required_when']['kit_members'] = deepcopy(ALWAYS)
    c['helpers']['kit_members'] = ('Componentes de esta presentación. No se presupone '
        'que un kit contenga cadena/cassette/mando ni que todas sus piezas compartan '
        'medidas o velocidades. Las evidencias y las interfaces nombran cada fila.')
    add_table(definitions, t, 'drivetrain_kit_member_evidence', 'Identificación y evidencia por componente',
        [column('member_reference', 'Componente incluido', required=True),
         column('manufacturer_sku', 'Código de fabricante del componente'),
         column('edition', 'Generación o edición documentada'), *source_columns()],
        unique=[['member_reference']], role='contents', semantic='evidence', required=ALWAYS)
    add_table(definitions, t, 'drivetrain_kit_member_interfaces', 'Interfaces propias de cada componente',
        [column('interface_identity', 'Identificación de esta interfaz', required=True),
         column('member_reference', 'Componente dueño de la interfaz', required=True),
         column('interface_role', 'Extremo y función de la interfaz', required=True),
         column('designation', 'Estándar y variante documentados', required=True),
         column('conditions', 'Límites del documento'), *source_columns()],
        unique=[['interface_identity']],
        helper='La interfaz pertenece a una pieza y un extremo. Mid, BSA o DUB '
        'no se aplican al kit entero ni certifican el cuadro, eje o biela.')
    add_table(definitions, t, 'drivetrain_kit_member_fitments', 'Destinos declarados por componente',
        [column('member_reference', 'Componente de esta declaración', required=True),
         *claim_columns()], unique=[['claim_identity']], conditions=claim_conditions(),
        helper='Una afirmación sobre un componente no se hereda a las demás piezas '
        'del envase. El modelo del kit continúa en la identidad del producto.')
    c['row_coherence'] = {'version': 1, 'links': [
        {'id': 'kit_owner_' + key, 'field': key, 'column': 'member_reference',
         'target_field': 'kit_members', 'label_columns': ['family', 'position', 'identity_model']}
        for key in ('drivetrain_kit_member_evidence', 'drivetrain_kit_member_interfaces',
                    'drivetrain_kit_member_fitments')]}
    for key in ('kit_members', 'drivetrain_kit_member_evidence',
                'drivetrain_kit_member_interfaces', 'drivetrain_kit_member_fitments'):
        c['prerequisites'][key] = [EVIDENCE]


def fixtures():
    out = []
    def add(name, family, values, **kw):
        out.append(case('cd_' + name, family, values, **kw))
    application = {'claim_identity': 'a', 'scope_kind': SYSTEM,
        'target_system': 'Sistema explícito', 'verdict': YES, 'drive_kind': EXTERNAL,
        'rear_sprockets': '8', 'source_document': 'Documento identificado'}
    apps = 'chain_application_declarations'
    base = {EVIDENCE: X8, 'drivetrain_mode': 'Derailleur', 'chain_speeds': ['6','7','8'],
            'chain_width_family': '3/32', 'chain_outer_width_mm': '7.3'}
    add('x8_keeps_discrete_applications', 'chain', {**base, apps: rows(*[
        {**application, 'claim_identity': 'x8-' + str(n), 'target_system': 'Todos los sistemas de ' + str(n) + ' velocidades',
         'rear_sprockets': str(n), 'source_document': 'KMC X8 BX08NP114', 'source_url': X8}
        for n in (6,7,8)])}, sources=[X8])
    add('wide_chain_modern_derailleur_still_blocks', 'chain', {**base, 'chain_width_family': '1/8'},
        blocking=[('constraint','chain_width_family')], sources=[PARK, SHELDON])
    add('width_is_not_a_speed_limit', 'chain', {EVIDENCE: SYNTHETIC, 'chain_outer_width_mm': '10'}, sources=[PARK])
    add('other_width_needs_designation', 'chain', {EVIDENCE: PARK, 'chain_width_family':'Otro'},
        pending=[('required_missing','chain_other_width_designation')])
    add('three_sixteenths_is_representable', 'chain', {EVIDENCE: PARK, 'chain_width_family':'Otro',
        'chain_other_width_designation':'3/16'}, sources=[PARK])
    add('width_other_text_does_not_override_known_width', 'chain', {EVIDENCE: X8,
        'chain_width_family':'3/32', 'chain_other_width_designation':'1/8'},
        blocking=[('field_applicability','chain_other_width_designation')])
    add('application_missing_source_pending', 'chain', {apps: rows({k:v for k,v in application.items()
        if k != 'source_document'})}, pending=[('row_incomplete',apps)])
    add('internal_gears_are_not_rear_sprockets', 'chain', {apps: rows({**application,
        'drive_kind': IGH, 'internal_gears':'8', 'rear_sprockets':'8'})},
        blocking=[('row_field_applicability',apps)])
    internal = {k:v for k,v in application.items() if k != 'rear_sprockets'}
    add('internal_gear_application_retains_its_count', 'chain', {apps: rows({**internal,
        'drive_kind': IGH, 'internal_gears':'8'})}, sources=[PARK])
    add('external_application_cannot_borrow_internal_gears', 'chain', {apps: rows({**application,
        'internal_gears':'8'})}, blocking=[('row_field_applicability',apps)])
    add('named_system_does_not_require_invented_cog_count', 'chain', {apps: rows(internal)})
    add('speed_array_in_one_tuple_blocks', 'chain', {apps: rows({**application,'rear_sprockets':['8','9']})},
        blocking=[('row_shape',apps)])
    add('two_distinct_claims_do_not_merge', 'chain', {apps: rows(application, {**application,
        'claim_identity':'b', 'target_system':'Otro sistema', 'rear_sprockets':'11'})})
    add('same_claim_twice_blocks', 'chain', {apps: rows(application,application)},
        blocking=[('row_shape',apps)])
    add('conditional_claim_needs_its_condition', 'chain', {apps: rows({**application,'verdict':CONDITIONAL})},
        pending=[('row_required_missing',apps)])
    weight = 'chain_mass_declarations'
    add('weight_basis_is_not_sold_length', 'chain', {**base, 'link_count':'114', weight: rows({
        'weighing_identity':'KMC basis', 'weight_g':'316', 'basis_links':'110',
        'basis_description':'Masa publicada por 110 eslabones', 'source_document':'KMC X8', 'source_url':X8})}, sources=[X8])
    add('weight_missing_basis_pending', 'chain', {weight: rows({'weighing_identity':'a',
        'weight_g':'316','source_document':'KMC X8'})}, pending=[('row_incomplete',weight)])
    supplied = 'chain_quick_links_supplied'
    link = rows({'connector_identity':'a','quantity':'1','source_document':'Envase identificado'})
    add('included_quick_link_needs_contents', 'chain', {EVIDENCE:X8,'quick_link_included':True},
        pending=[('required_missing',supplied)])
    add('two_halves_can_be_one_complete_link', 'chain', {EVIDENCE:X8,'quick_link_included':True,supplied:link})
    add('not_included_cannot_have_supplied_links', 'chain', {EVIDENCE:X8,'quick_link_included':False,supplied:link},
        blocking=[('field_applicability',supplied)])
    targets = 'connector_target_declarations'
    target = {'claim_identity':'x8','scope_kind':MODEL,'target_brand':'KMC','target_model':'X8',
        'verdict':YES,'source_document':'KMC CL573R','source_url':CL573}
    connector_values = {EVIDENCE:CL573,'chain_connector_type':'Missing link','chain_speeds':['6','7','8']}
    add('connector_target_is_chain_model', 'chain_link', {**connector_values, targets:rows(target)},sources=[CL573])
    add('connector_model_does_not_accept_system_text', 'chain_link', {**connector_values,
        targets:rows({**target,'target_system':'SRAM'})}, blocking=[('row_field_applicability',targets)])
    add('connector_model_needs_brand', 'chain_link', {**connector_values,
        targets:rows({k:v for k,v in target.items() if k != 'target_brand'})},
        pending=[('row_required_missing',targets)])
    add('hg11_connector_can_target_linkglide', 'chain_link', {EVIDENCE:LG,
        'chain_connector_type':'Missing link','chain_speeds':['11'],targets:rows({
        'claim_identity':'lg','scope_kind':SYSTEM,'target_system':'LINKGLIDE',
        'verdict':YES,'source_document':'Shimano SM-CN900-11','source_url':LG})},sources=[LG])
    add('pin_not_reusable_guard_preserved', 'chain_link', {EVIDENCE:SHELDON,
        'chain_connector_type':'Pin','chain_link_reusable':True},blocking=[('constraint','chain_link_reusable')])
    add('non_reusable_cannot_declare_reuse_limit', 'chain_link', {EVIDENCE:SRAM,
        'chain_connector_type':'Missing link','chain_link_reusable':False,'connector_reuse_limit':'5'},
        blocking=[('field_applicability','connector_reuse_limit')])
    add('reuse_limit_needs_whole_positive_uses', 'chain_link', {EVIDENCE:SYNTHETIC,
        'chain_connector_type':'Missing link','chain_link_reusable':True,'connector_reuse_limit':'1.5'},
        blocking=[('integer','connector_reuse_limit')])
    members = rows({'member_role':'biela','family':'crank_arm','quantity':'1','position':'Izquierdo','identity_model':'Brazo documentado'},
                   {'member_role':'pedalier','family':'bottom_bracket','quantity':'1','position':'Sin posición'})
    evidence = 'drivetrain_kit_member_evidence'
    evidence_row = {'member_reference':'r1','source_document':'Envase identificado'}
    add('kit_does_not_require_cassette_or_chain', 'drivetrain_kit', {EVIDENCE:SYNTHETIC,'kit_members':members,
        evidence:rows(evidence_row, {**evidence_row,'member_reference':'r2'})})
    add('kit_evidence_cannot_belong_to_other_component', 'drivetrain_kit', {'kit_members':members,
        evidence:rows({**evidence_row,'member_reference':'outside'})},blocking=[('row_reference_unresolved',evidence)])
    add('kit_duplicate_component_evidence_blocks', 'drivetrain_kit', {'kit_members':members,
        evidence:rows(evidence_row,evidence_row)},blocking=[('row_shape',evidence)])
    fitments = 'drivetrain_kit_member_fitments'
    target = {'claim_identity':'Synthetic counterpart','scope_kind':MODEL,
        'target_brand':'Synthetic','target_model':'Synthetic compatible spindle',
        'verdict':YES,'source_document':'Synthetic document','source_url':SYNTHETIC}
    add('kit_fitment_belongs_to_one_member', 'drivetrain_kit', {'kit_members':members,
        fitments:rows({**target,'member_reference':'r1'})})
    add('kit_fitment_foreign_member_blocks', 'drivetrain_kit', {'kit_members':members,
        fitments:rows({**target,'member_reference':'outside'})},blocking=[('row_reference_unresolved',fitments)])
    add('kit_members_require_the_package_evidence', 'drivetrain_kit', {'kit_members':members},
        pending=[('prerequisite','kit_members')])
    out[-1]['expected_sql_issue_subset'] = [{**issue,'code':'prerequisite_missing'}
        for issue in out[-1]['expected_issue_subset']]
    complete = next(f for f in out if f['id'] == 'cd_kit_does_not_require_cassette_or_chain')
    complete['forbidden_issue_fields'] = ['kit_members', evidence]
    applications = rows(
        {**target,'claim_identity':'External','drive_kind':EXTERNAL,'rear_sprockets':'8'},
        {**target,'claim_identity':'Internal','drive_kind':IGH,'internal_gears':'8'})
    add('documented_external_and_internal_uses_do_not_require_one_global_mode', 'chain',
        {EVIDENCE:SYNTHETIC,'chain_speeds':['8'],'chain_application_declarations':applications})
    out[-1]['forbidden_issue_fields'] = ['chain_speeds','drivetrain_mode','chain_application_declarations']
    for fixture in out:
        if fixture['id'] in ('cd_wide_chain_modern_derailleur_still_blocks','cd_pin_not_reusable_guard_preserved'):
            fixture['expected_sql_blocking'] = [{**x,'code':'field_constraint'} for x in fixture['expected_blocking']]
        if fixture['id'] == 'cd_reuse_limit_needs_whole_positive_uses':
            fixture['expected_sql_blocking'] = [{**x,'code':'field_constraint'} for x in fixture['expected_blocking']]
    return out


def relation_fixtures():
    # The evaluator already exists in both engines. These immutable-source
    # relations belong to references, never to arbitrary facts or all SRAM.
    def term(field, value):
        return {'field':field,'operator':'eq','value_type':'token','value':value}
    relation = {'schema_version':2,'interface':'connector_chain',
        'label':'Eagle Drivetrain PowerLock frente a cadena Eagle Transmission',
        'alternatives':[{'id':'eagle','label':'Cadena Eagle Drivetrain',
            'conditions':[term('connector_technology','Eagle Drivetrain'),term('chain_technology','Eagle Drivetrain')],
            'sources':[SRAM]}],
        'exclusions':[{'id':'ttype','label':'Este PowerLock no admite cadena T-Type',
            'conditions':[term('connector_technology','Eagle Drivetrain'),term('chain_technology','T-Type')],
            'sources':[SRAM]}]}
    return [{'id':'cd_relation_' + name,'template':'chain_link','kind':'relation_integration_pending',
        'relation_claim':relation,'configuration':config,'required_verdict':verdict,
        'runnable_against_templates':False,'source_urls':[SRAM],
        'reason':'Requiere cadena instalada y referencia de conector identificadas; no inferidas por marca o 12v.'}
        for name,config,verdict in [
            ('explicit_ttype_exclusion',{'connector_technology':'Eagle Drivetrain','chain_technology':'T-Type'},'excluded'),
            ('chain_unknown',{'connector_technology':'Eagle Drivetrain'},'unknown'),
            ('same_speed_not_identity',{'connector_technology':'12','chain_technology':'12'},'outsideDeclaredScope')]]


if __name__ == '__main__':
    catalog, cases = compile_catalog()
    path = RESEARCH / 'existing-chain-drive-catalog-2026-09-08.json'
    write_json(path,catalog)
    cases['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-chain-drive-cases-2026-09-08.json',cases)
    print(json.dumps({**catalog['stats'],'cases':len(cases['cases']),'production_writes':False}))
