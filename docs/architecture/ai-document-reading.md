# Leer un documento o una foto con IA

Cómo se lee con un modelo de visión un dato que no puede salir mal (un código
de seguimiento, un folio, un RUT, un monto) desde una foto o un PDF. La
implementación de referencia es la boleta del envío de un pedido web:
`lib/modules/website/services/online_order_shipment_service.dart`
(`readReceipt`) y `lib/modules/website/models/online_order_shipment.dart`
(`ShipmentReceiptReading.withCloseUp`).

## Lo que pasó (2026-10-13)

La boleta de Correos de prueba decía «770000000099». Leyendo la **foto
entera**, `gemini-2.5-flash` y `gemini-3.6-flash` devolvieron «77000000099»
(un cero menos) en la mayoría de los intentos, **también cuando se les pidió el
código deletreado carácter por carácter**: dos lecturas del mismo modelo sobre
la misma imagen se equivocan juntas, así que compararlas no detecta nada. Ese
código le habría llegado al cliente en el correo «va en camino». Costó cuatro
rondas de prueba en la app encontrar lo que sí funciona.

## La regla

1. **Un código se lee de cerca, no de la foto entera.** La primera lectura
   devuelve también dónde está el código (`[ymin, xmin, ymax, xmax]`, de 0 a
   1000); la app recorta esa zona con margen (la caja puede quedar corta o
   corrida), la amplía a 900 px o más y la vuelve a leer. De cerca leyó bien en
   9 de 9 intentos.
2. **Tres lecturas del recorte, de dos modelos o dos temperaturas, en
   paralelo.** Gana la mayoría; el código queda *verificado* sólo si al menos
   dos lo leyeron y ninguna discrepa. Una lectura sola nunca verifica.
3. **Cada lectura se controla a sí misma con dos escrituras**: los caracteres
   uno por uno y en grupos de tres; si no coinciden, esa lectura no cuenta. La
   cantidad de caracteres que dice el modelo **no** sirve de control: enumeró
   bien doce caracteres y dijo «length: 11».
4. **Lo que no se verificó lo decide la persona, con el recorte a la vista.**
   El recorte va junto al campo siempre; si las lecturas difieren, cada una se
   ofrece para elegir y la acción pide «Revisé…». Nunca se esconde la duda
   eligiendo en silencio.
5. **Todos los campos del esquema son obligatorios y pueden ser null.** Con
   campos opcionales, `gemini-3.6-flash` a veces devolvió sólo los
   obligatorios (el código, sin destinatario, servicio ni monto).
6. **No se pide lo que no se va a guardar.** La boleta trae el nombre y el RUT
   del empleado que la llevó al mesón: el esquema no tiene campos del
   remitente.
7. **Lo leído se coteja con lo que el sistema ya sabe** (destinatario, RUT,
   comuna, calle y número del pedido) y una diferencia se muestra antes de
   actuar: el error caro no es un dígito, es registrar la boleta de otro
   cliente.
8. **Una fecha leída tiene que poder ser cierta** (2026-10-13: una boleta de
   ese día se leyó «13/10/2020», y esa fecha va en el correo al cliente y en
   el gasto). Se coteja con el contexto: la admisión no puede ser anterior al
   pedido ni futura (un día de holgura). Si el día y la hora calzan con este
   año o el anterior, se corrige el año **y se dice bajo la fecha**; si no,
   se descarta y se dice. La base repite el control al registrar
   (`online_order_shipment_check_admission`), porque la app vieja o un error
   no lo hacen. Pedirle al modelo «copia el año con sus cuatro cifras» ayuda,
   pero no reemplaza el control.

Un PDF o una foto HEIC que la app no puede recortar quedan sin verificar: se
leen igual, pero piden la confirmación.
