# Doce familias no motrices: aptitud para publicar representación

Claude, revisor independiente · 2026-09-07

**Esto es una revisión, no una autorización.** Publicar representación con el llenado cerrado no certifica compatibilidad, no aprueba montajes y no convierte un saneamiento parcial en un saneamiento global terminado. La decisión y el ensayo de adopción sobre productos reales son tuyos.

Catálogo congelado `all-family-port-cardinality-integrated-2026-09-07.json`, SHA `16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`. No leí base de datos ni runtime, así que no miré ningún dato de producto. No rehíce investigación: reutilicé las revisiones congeladas y verifiqué contra el catálogo si sus hallazgos quedaron implementados.

## Veredicto

| Familia | Campos | Filas | Veredicto | Defecto |
|---|---|---|---|---|
| bottle | 11 | 1 | apta | — |
| bottle_cage | 13 | — | apta | — |
| lock | 15 | 2 | apta tras corregir | PUB-D01 |
| audible_signal | 7 | — | apta | — |
| reflector | 4 | — | apta | — |
| souvenir | 4 | — | apta | — |
| food_beverage | 21 | 1 | apta | — |
| rider_apparel | 11 | — | apta | — |
| rider_glove | 12 | — | apta | — |
| rider_protection | 9 | 2 | apta tras corregir | PUB-D01 |
| helmet | 17 | 1 | apta | — |
| workshop_chemical | 8 | — | apta | — |

**10 aptas, 2 aptas tras una corrección concreta, 0 no aptas, 1 defecto.**

## Por qué no las bloqueo con la matriz de transmisión

Los cinco campos de filas del bloque son `bottle_body_dimensions`, `kit_members`, `security_rating_configurations`, `nutrition_facts` y `certification_configurations`. **Ninguno es una matriz `compatible_*`.** Estas familias no dependen de la matriz de transmisión, así que bloquearlas por ella sería importar un pendiente ajeno. Lo más cercano son los anchos de tubo del portabidón, que son la interfaz que él declara y no una lista de cuadros aprobados.

La certificación tampoco es compatibilidad: `certification_configurations` la comparten helmet y rider_protection y las dos están en este bloque, y la laguna G03 que cita se refiere al alcance de la propia norma —edición, mercado, modelo cubierto—, que el esquema ya representa en columnas.

## El único defecto que encontré

### PUB-D01 — kit_members admite family=light fuera de la plantilla light

*Evidencia.* La columna family de kit_members enumera las 105 claves de plantilla y no ofrece «Otro». El estrechamiento que excluye light existe en una sola de las 23 plantillas que usan el campo: la propia light, con 104 opciones. Las otras 22, entre ellas lock y rider_protection, no declaran allowed_options sobre family.

*Por qué importa.* La integración de luces decidió que cada luz posee sus datos y sus modos por id de miembro en light_member_configurations, y el estrechamiento cerraba el segundo dueño. Un kit de candado o de protección puede declarar hoy un miembro family=light, que es exactamente ese segundo dueño, sin modos y sin enlace de miembro. Un chaleco con luz integrada no es hipotético.

*Lo que no afirmo.* No afirmo que ningún producto lo haga hoy: no miré datos de producto. El agujero es anterior a este bloque y afecta a 22 plantillas; lo que cambia al publicar es que por primera vez queda alcanzable desde una superficie publicada.

*Corrección mínima.* Un allowed_options sobre family en row_conditions de lock y de rider_protection, con la misma lista de 104 que ya usa light. Es metadato, no motor, y no toca la definición compartida ni a las otras 20 plantillas.

Es una contradicción de arquitectura y no un dato de producto sin investigar: la decisión de que una luz posee sus datos por id de miembro ya está tomada e implementada en una plantilla, y aquí hay dos puertas que la eluden.

## Definiciones compartidas: publicar este bloque no altera a las demás

Catorce definiciones del bloque se usan también fuera. Publicar una plantilla no muta una definición, así que ninguna otra familia cambia por esta publicación. El riesgo es el inverso y es hacia adelante: un cambio futuro en una definición de alcance amplio caería sobre familias ya publicadas.

| Definición | Familias que la usan | Fuera del bloque |
|---|---|---|
| `spec_evidence_source` | 105 | 93 |
| `color` | 37 | 28 |
| `material` | 27 | 24 |
| `kit_members` | 23 | 21 |
| `volume_ml` | 4 | 2 |
| `bolts_included` | 3 | 2 |

Las ocho restantes alcanzan una o dos familias fuera del bloque y están en el JSON.

## Familia por familia

### bottle — apta

**Revisión previa.**
- Mi revisión ND congelada halló que bottle_diameter_mm quedaba permitido siempre mientras el portabidón ya lo condicionaba a su sistema de retención (parche RND-ND16-bottle_diameter-gate) y que reducir una botella TWIST a un solo diámetro era lo que el hallazgo prohibía (fixturas RF6 y RF7).
- Root adjudicó aceptar ese parche, corregir el rótulo del campo compartido y añadir bottle_body_dimensions.
- Verificado hoy en el catálogo congelado: bottle_diameter_mm está condicionado, base_included e included_base_model también, y bottle_body_dimensions existe y es exclusiva de esta familia.

*Lo que queda es dato de producto, no arquitectura:* Volumen, material y medidas concretas de cada botella siguen sin investigar por producto.

### bottle_cage — apta

**Revisión previa.**
- Auditada en la propuesta de row_conditions como uso de plantilla sin campo de filas.
- Verificado hoy: cinco campos condicionados —anchos de tubo, separación y número de anclajes, y lado de entrada— que son la interfaz declarada del propio portabidón.

Sus medidas de tubo describen la interfaz que el portabidón declara, no una matriz de modelos aprobados. No confundir una interfaz declarada con compatibilidad certificada.

*Lo que queda es dato de producto, no arquitectura:* Qué cuadros acepta cada modelo concreto es dato de producto.

### lock — apta tras corregir

**Revisión previa.**
- Mi revisión ND fijó en la fixtura RF16 que las medidas del arco y del cable conviven en una presentación sin transferir el nivel de seguridad de uno a otro.
- Mi revisión de cierre de carencias verificó que security_rating_configurations ganó la columna rating_scheme y que lock declara required_when sobre ella, con los casos ejecutables rnd_root_security_programme_missing y rnd_root_two_security_programmes.

**Defecto que corregir antes:** PUB-D01.

*Lo que queda es dato de producto, no arquitectura:* Qué certificación tiene cada candado concreto es dato de producto.

### audible_signal — apta

**Revisión previa.**
- Auditada en la propuesta de row_conditions; sin campo de filas y sin condiciones.

*Lo que queda es dato de producto, no arquitectura:* Datos de cada bocina o timbre concreto.

### reflector — apta

**Revisión previa.**
- Auditada en la propuesta de row_conditions; cuatro campos, sin filas.

*Lo que queda es dato de producto, no arquitectura:* Normas y medidas de cada reflector concreto.

### souvenir — apta

**Revisión previa.**
- Auditada en la propuesta de row_conditions; cuatro campos, una sola definición compartida.

*Lo que queda es dato de producto, no arquitectura:* Nada estructural pendiente.

### food_beverage — apta

**Revisión previa.**
- Mi revisión ND fijó que dos cantidades del mismo nutriente sobre la misma base son una contradicción (RF13) y que el mismo nutriente sobre dos bases distintas es legítimo (RF14).
- La laguna G08 de la propuesta advertía que nutrition_facts sólo aplica a preparation_kind = Envasado y que «Por porción servida» no habilita productos preparados en barra.

G08 está implementada y lo verifiqué: allowed_when de nutrition_facts condiciona a preparation_kind = «Envasado». El alcance del padre ya no depende de una convención escrita.

*Lo que queda es dato de producto, no arquitectura:* La tabla nutricional de cada producto concreto.

### rider_apparel — apta

**Revisión previa.**
- Auditada en la propuesta de row_conditions; sin filas. Nueve de sus once definiciones son compartidas y sólo tres salen del bloque.

*Lo que queda es dato de producto, no arquitectura:* Tallas y materiales de cada prenda concreta.

### rider_glove — apta

**Revisión previa.**
- Auditada en la propuesta de row_conditions; misma forma que rider_apparel.

*Lo que queda es dato de producto, no arquitectura:* Datos de cada guante concreto.

### rider_protection — apta tras corregir

**Revisión previa.**
- Auditada en la propuesta de row_conditions con dos campos de filas.
- Comparte certification_configurations con helmet, y las dos familias están en este bloque.

**Defecto que corregir antes:** PUB-D01.

*Lo que queda es dato de producto, no arquitectura:* Qué norma cumple cada protección concreta.

### helmet — apta

**Revisión previa.**
- Mi revisión ND fijó que construcción y público deben poder declararse a la vez sin obligar a elegir (RF11) y que sin etiqueta observada no hay declaración de norma, sin escribir la ausencia como una norma más (RF12).
- Verificado hoy: certification_configurations exige standard, standard_text y evidence_kind, ofrece «Otra» como salida y conserva edición, mercado y alcance como columnas propias.

La exigencia de evidence_kind es lo que sostiene RF12 en el esquema: no se puede registrar una norma sin decir de dónde salió.

*Lo que queda es dato de producto, no arquitectura:* Qué certificación tiene cada casco concreto.

### workshop_chemical — apta

**Revisión previa.**
- Auditada en la propuesta de row_conditions; sin filas.
- En mi auditoría de los 33 registros sin ficha propuse esta familia para ACEITE NACIONAL, y tú corrigiste que la falta de evidencia no se escribe como prohibición en not_for.

Esa corrección es una regla de uso del campo not_for, no un defecto del esquema: not_for existe para prohibiciones declaradas y sigue siendo el lugar correcto para ellas.

*Lo que queda es dato de producto, no arquitectura:* Volumen, envase y aplicaciones declaradas de cada producto concreto.

## Lo que deliberadamente no hice

- No aprobé nada por falta de pruebas en contra: cada «apta» se apoya en una revisión previa citada y en una verificación contra el catálogo, no en el silencio.
- No conté como defecto que una fila parcial sea admisible. La falta de un grupo de presencia es un límite de expresión conocido, compartido con otras once tablas, y no una contradicción de estas familias.
- No miré datos de producto, así que no digo de ninguna familia que sus productos estén listos.
- No toqué compuertas: llenado, compatibilidad y asignación siguen cerradas.
