# Mando combinado: adjudicación final root

Aplicado y verificado: una plantilla, 15 definiciones, 15 usos, 55 casos. Pasaron 56 pruebas Dart, 55 SQL y cinco regresiones del publicador. Diez definiciones nuevas, cuatro opciones y cinco compartidas exactas. El verificador previo rechazó por ausencia. [Recibo, lectura autenticada y preservación](combined-control-integration-2026-09-07.md). Sin productos ni asignaciones escritos; fill y cobertura mecánica global false.

Se aceptó el sucesor de Claude tras dos correcciones de propiedad del dato: modo mecánico/electrónico canónico, circuito de freno propio y conexión externa condicionada. La lectura de Sheldon/Park fundamenta la separación de indexación/trim; [SRAM](https://support.sram.com/hc/en-us/articles/16420328834459-Can-I-change-assign-shifter-functions-in-the-AXS-app-e-g-move-the-derailleur-outboard-with-a-left-shifter-click) confirma que lado físico y asignación pueden diferir. Fuentes OEM de root en combined-control-oem-root-sources-2026-09-07.md. Las cifras de casos siguen sintéticas, con example.invalid.

Correcciones finales de root al candidato entregado:

- La identidad de una ocurrencia física es miembro/row_id, no modelo+lado+edición. Dos piezas idénticas pueden integrar un paquete; una pieza no puede aparecer dos veces con datos contradictorios. Se conserva cantidad como conteo de filas, sin sumar cantidades inventadas. La fixture de duplicación se tradujo explícitamente a la misma ocurrencia y se añadieron dos pruebas de contenido.
- La supuesta ausencia de requisito de veredicto no se reproduce: required_when.status ya depende del modo. Una prueba con destinatario completo y sólo status ausente da row_required_missing en status y row_prerequisite en sus condiciones dependientes. Se rechazó el diagnóstico de un operador de presencia faltante; no se cambió el motor ni esa exigencia.
- [TRP HY/RD](https://eu.trpcycling.com/en-at/products/hy-rd), página OEM abierta, describe un cáliper hidráulico para sistemas accionados por cable. La conversión externa no da un circuito hidráulico a la maneta. El token de sistema híbrido se acotó a salida por cable hacia conversor externo y sólo permite propiedades de cable; el fluido se registra en la pieza que lo contiene. Se rechazó la premisa del antiguo caso positivo sintético que mezclaba ambos propietarios, conservando sus valores como caso negativo y añadiendo un control de cable válido. El enlace antiguo al PDF dio404 y no se cita como manual leído; basta la página OEM para esta distinción, sin extrapolar sus claims de compatibilidad.
- SQL emite una incidencia por celda; Dart compara conjuntos código/campo. Sólo tres casos necesitaron conservar multiplicidades SQL (2,4,6). Los conjuntos coincidían: no se cambió la garantía ni se aceptaron códigos nuevos para hacer pasar la prueba.

Claude revisó su sucesor y17mutantes; las cuatro pruebas/adjudicaciones finales anteriores son de root. Ningún resultado prueba un montaje real ni autoriza llenar sin identidad y fuente exactas. Las11definiciones heredadas del congelado se conservan:5ya existen vivas; el origen histórico no sustituye la preimagen.10usos legacy quedan fuera de la edición activa, y el escritor v2 conserva datos antiguos pero rechaza nuevos/cambiados.

Backup con hash/permisos verificados: 20260908T041415Z-combined-control-metadata. Artefactos:

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_combined_control_catalog.py` | `3632803afac0d042e941f0a34856a8f795e87f7de37f22d7909189f276c8de74` |
| `scripts/inventory/compile_combined_control_root.py` | `5e18fdfd1f6f27656337003035a1f4e5f1f0d1ee380f8d932acd0fb348b2e7f8` |
| `scripts/inventory/compile_combined_control_publication.py` | `2767f61951c3a6f5e049ce0e2fff95fd6255765df0e81e54e05c52938bb4a2f2` |
| `docs/development/product-specs-research-2026-09-05/combined-control-catalog-2026-09-07.json` | `733781370463914b23c107a65d005109189ed9f1496b91053a1b628842fb5a44` |
| `docs/development/product-specs-research-2026-09-05/combined-control-cases-2026-09-07.json` | `26b26bcf71e211175822fa08ae45ddaeaaa0b86765288e311468cf1a88488772` |
| `docs/development/product-specs-research-2026-09-05/combined-control-publication-preimage-2026-09-07.json` | `fd4f5321739283a149ed5d01a118e0f51ce0fad78b3702fc85487a4338048e28` |
| `docs/development/product-specs-research-2026-09-05/combined-control-publication-packet-2026-09-07.json` | `60915e28d05212914d5ea264ce1bfe328e93032d04fe9daf1bb11eafa35b538a` |
| `supabase/migrations/20260908032000_combined_control_spec_templates.sql` | `3987f30346e1d987416c85e636db838e80214aaabb0943ac14cae634b11b5d4c` |
| `supabase/manual_checks/verification/20260908032000_combined_control_spec_templates.sql` | `b408695b4f19d2e00524f630f2a247bfac73de6b80435f6a3e7841975fba62a7` |
