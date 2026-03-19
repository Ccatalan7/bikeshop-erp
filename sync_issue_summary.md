# Resumen del Problema de Sincronización

Este documento describe de forma general el problema de pérdida de datos detectado en la sincronización entre las Facturas de Venta y los Trabajos de Taller (Pegas).

## Contexto
El sistema implementa una **sincronización bidireccional**:
- Si cambias algo en la Factura, se actualiza el Trabajo de Taller vinculado.
- Si cambias algo en el Trabajo de Taller, se actualiza la Factura vinculada.

## El Problema
Cuando un usuario agrega productos o servicios desde el formulario de la Factura y hace clic en "Guardar", los elementos parecen guardarse correctamente. Sin embargo, al salir de la pantalla y volver a entrar, los artículos nuevos han desaparecido, dejando la factura vacía o incompleta.

## Causa Detectada (Resumen Conceptual)
El fallo se debe a un **conflicto de tiempos (Race Condition)** entre los "disparadores" (triggers) de la base de datos:

1. Al guardar la Factura, el sistema inicia el proceso de actualizar el Trabajo de Taller.
2. Durante este proceso, el sistema elimina los artículos viejos del Trabajo para insertar los nuevos.
3. En ese microsegundo donde el Trabajo está "vacío" (procesando el cambio), se activa accidentalmente la sincronización inversa (Trabajo -> Factura).
4. El sistema detecta que el Trabajo no tiene artículos y, siguiendo su lógica de espejo, sobreescribe la Factura original (que sí tenía los datos del usuario) con una lista vacía.

## Resultado
Los datos recién ingresados por el usuario son sobreescritos por un estado "vacío" temporal generado por la propia lógica de sincronización, resultando en la pérdida de la información.
