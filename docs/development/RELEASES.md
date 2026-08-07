# Releases

The canonical promotion path is:

```text
feature/current line → pull request to protected main → integrity + preview
→ intentional merge → Production environment → post-deploy smoke
```

- `main` is protected and rejects force-pushes/deletion.
- Firebase ERP/store and Windows release workflows consume the merged commit.
- Production jobs use the `Production` GitHub Environment; pull-request previews use `staging`.
- A workflow dispatch is diagnostic or exceptional and must still run its integrity dependency.
- Never deploy a dirty working tree or run direct production upload helpers as a normal release path.
- Record commit SHA, actor, environment, timestamps, checks and rollback reference.
- Web builds publish `release.json` and retained SHA-256 evidence. Promotion is
  successful only when the live Firebase target reports the exact merged commit.
- The ERP production job then runs the read-only inventory/payment/journal/trace
  invariant dashboard. A critical violation fails the release record without
  attempting an automatic data repair.

## El recuadro de novedades (2026-08-06)

`prepare_erp_update.sh` genera la nota de usuario con el **Codex local**. Esa
cuenta lleva tiempo sin cuota: el generador responde «the Codex account hit its
usage limit», el pipeline sigue adelante y la actualización sale con el texto
determinista («Esta actualización incluye ajustes en …»). Ése es el motivo real
—no un bug del recuadro— de que las publicaciones nunca hayan llevado una
descripción escrita.

La salida está en el propio pipeline: **`--notes-candidate <archivo.json>`**.
Quien conduce la publicación escribe la nota y el gate la valida; el productor
del texto es intercambiable, lo que garantiza que sea cierta es la validación.
Cuatro reglas que cuestan un intento fallido cada una si se ignoran:

1. Forma exacta: `{title ≤80, summary ≤280, modules[1..5]}`, y cada módulo
   `{id, label, items[1..3] ≤160, evidence_ids[1..12]}`. `id` y `label` salen
   de `RELEASE_NOTE_MODULES`; el label debe ser el del id, no otro.
2. **Cada `evidence_id` debe pertenecer al módulo que lo cita.** El módulo lo
   decide la ruta del archivo, no el tema: casi todo el trabajo de AliExpress
   vive en `lib/shared/` y por eso cuenta como `general`, no como `purchases`.
3. Sólo valen las evidencias del catálogo **inspeccionable** (sin binarios,
   generados ni sensibles); por ejemplo un `supabase/tests/*.sql` queda fuera.
4. Los `change_NNN` se leen del inventario del rango, no se inventan:
   `collectReleaseInventory(...)` + `createCodexReleaseContext(inv).changes`.

5. **El gate mide qué tan concreta es la nota, no sólo su forma.** Rechaza con
   «AI release notes are too generic» si los ítems no nombran algo observable.
   Cada ítem se valida contra dos vocabularios de `generate_release_notes.mjs`:
   el del módulo (`CONCRETE_RELEASE_LANGUAGE`, p. ej. en `general`: botones,
   ventanas, listas, notificaciones, búsqueda, descargas) y el de conducta
   visible (`USER_OBSERVABLE_RELEASE_LANGUAGE`: ahora, puedes, muestra, avisa,
   elige, móvil…), con un mínimo de 6 palabras. En una publicación con dos o
   más commits, **la mitad de los ítems y al menos dos deben pasar**. Escribir
   «se mejoró el flujo» nunca pasa; «Ahora el menú del móvil incorpora un botón
   para abrir otro espacio de trabajo» sí, y además se entiende.

Antes de gastar una publicación, valida el candidato en seco con
`acceptCodexReleaseEnvelope(envelope, {inventory})`: devuelve `source: "ai"`
cuando pasa, y el motivo exacto cuando no.

Firebase rollback uses the previous Hosting release. Windows rollback uses the previous signed/checksummed artifact. macOS internal rollback restores the previous verified bundle retained under the per-user updater support directory. Database rollback follows the database backup/restore runbook and must not improvise destructive reverse SQL.

For a Firebase rollback, select the last release whose retained evidence and
post-deploy checks passed, restore it through Firebase Hosting release history,
then verify its `release.json` commit and rerun `just db-health production`.
