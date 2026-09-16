# fill-001-cl573r: primera aplicación de investigación — 2026-09-16

Producto `4715575894768` «Conexión De Cadena Kmc Cl573r 6/7/8 Plata 2p» (3851271a-8631-4942-a7dc-776853ae0408), plantilla `chain_link`
contrato 40. Investigó `claude`, revisó `claude-peer`
(veredicto `accepted`, 2026-09-16); readiness `6eeca4fa-8daa-59aa-a020-a31056276632`.

| Artefacto | SHA-256 |
|---|---|
| Propuesta revisada `catalog-fill-first-proposal-cl573r-v3.json` | `7a80845addcdbc78f69b00bf00b6defa8514268c7d5535cd978853464c281772` |
| Preimagen fresca (snapshot) | `69f2af6012e96b40d5af813566b885bec6b458808b841be63c8ba391e626ca39` |
| Paquete sellado `bundle.json` | `ebbcb420c00333c5f60e6b396c6a5b2a75fe0650b3095fcc2d27525cb39b1a90` (comando `4d14bc93ae24d4c094577b19b14a21b9add8ec6a02ce2608698b97e3ddfdaf71`) |
| Registro `register.sql` | `935fd82de701f3ada339e50ee599d5479cf355f034ae9696f326ba6847fb3c0f` |
| Recibo (`before_snapshot_sha256` → `after_snapshot_sha256`) | `69f2af6012e96b40d5af813566b885bec6b458808b841be63c8ba391e626ca39` → `f7af092d432278257c1768e3a4eb40dc1a9dfa6717c7f913350b26e0e0c58924` |

## Qué cambió

- Identidad: {"model": "CL573R"}
- Hechos escritos (6): `chain_connector_type`, `spec_evidence_source`, `chain_speeds`, `chain_link_reusable`, `chain_connector_directional`, `connector_target_declarations`
- Revisión del producto: 0 → 11
- Observaciones después (6): spec_evidence_source (research), chain_connector_directional (research), chain_speeds (research), chain_connector_type (research), connector_target_declarations (research), chain_link_reusable (research)
- Recibo devuelto por el RPC con `replayed = False`; la lectura posterior coincide con el recibo: True.

## Qué no cambió

Precio, costo, stock, nombre, marca, categoría, imágenes y documentos; ninguna observación previa
existía. Nada se confirmó como medido: cada hecho lleva procedencia `research` y `confirmed = false`
hasta que un mecánico lo confirme en la app.

## Lo que ve el cliente

Lectura anónima de `get_public_product_technical_specs` después de aplicar: cuatro filas en la
ficha pública de la tienda («Tipo de conector: Missing link», «Clase de cadena declarada: 6, 7, 8»,
«Conector con sentido de montaje: No», «Reutilizable según el fabricante: Sí»). La URL de
evidencia y las cuatro declaraciones de cadenas objetivo quedan internas, como manda el contrato.

## Cómo se hizo, para repetirlo

`fill_snapshot_probe.py` (preimagen fresca como el actor por SQL) → `build_cl573r_proposal_v3.py`
(propuesta contra el contrato vivo; `chain_connector_target` es `legacy`, así que la declaración
de destinos va por filas) → `fill_research_runner.py simulate` → revisión por otra sesión de Claude
(`claude-peer`, dos rondas, una observación aceptada) → bloque `review` → `simulate` →
`prepare` → `register` (SQL por `query.sh production --write`) → `apply` (una sola llamada al
RPC, recibo, lectura posterior) → `write_fill_record.py`.
