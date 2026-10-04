# vinabike_public_core

Cómo se ve un producto de Viñabike para el público, en Dart sin Flutter. Lo
importan el ERP (Flutter) y el sitio en HTML (`services/storefront_html`), así
que cada regla tiene un solo dueño
(`docs/architecture/storefront-html-migration-plan.md`).

Lo que hay, con la misma ruta que tenía en `lib/`:

- `public_store/models/`: proyección comercial, ficha técnica, texto SEO
  (`PublicProductSeoCopyInput.fromSettings`), horario, logo, regla de marca.
- `public_store/seo/`: datos estructurados del producto y del negocio.
- `public_store/utils/`: URL canónica de producto, valores de la ficha técnica.
- `modules/website/models/`: presentación de categorías, menús y páginas
  (`WebsiteNavigation`, `WebsitePage`), destinos y consulta de catálogo.
- `modules/website/theme/`: colores del tema del editor.
- `shared/`: `Product`, utilidades chilenas y GTIN.

## Reglas

- **Nada de Flutter.** `dart test` en esta carpeta corre sin el SDK de Flutter;
  si un archivo lo importa, deja de compilar. CI lo comprueba (paso «Analyze
  and test the shared core and the HTML storefront» de
  `erp-integrity-gate.yml`).
- **Las rutas viejas reexportan.** Cada archivo que salió de `lib/` dejó una
  línea `export 'package:vinabike_public_core/...';`, para no tocar los 162
  archivos que lo importan. El código nuevo importa el paquete directamente.
  Las pruebas de las reglas siguen en `test/unit/` del ERP.
- Un archivo entra aquí cuando el sitio en HTML necesita su regla; se mueve con
  `git mv`, nunca se copia.

```bash
cd packages/vinabike_public_core && ../../.fvm/flutter_sdk/bin/dart test
```
