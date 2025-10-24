# 🧪 Guía Rápida de Prueba - Lector USB/Teclado

## 🎯 Cómo probar SIN lector físico

### Opción 1: Simular con el teclado

1. **Abrir la página**: `Configuración → Dispositivos → Lector USB/Teclado`
2. **Verificar que esté en "Escuchando"** (debería estar activado automáticamente)
3. **Hacer click en la página** (para asegurar el foco)
4. **Escribir un código** en el teclado, por ejemplo: `123456789`
5. **Presionar Enter**
6. ✅ Deberías ver el código en la lista de "Códigos recientes"

### Opción 2: Usar generador online de códigos de barras

1. Abrir: https://barcode.tec-it.com/en/Code128
2. Ingresar un código (ej: "TEST123")
3. Copiar el código
4. En la app, escribir `TEST123` y presionar Enter
5. ✅ Debería aparecer en la lista

---

## 🖱️ Funcionalidades a probar

### ✅ Escaneo básico
- [ ] Escribir código + Enter → Aparece en lista
- [ ] El código se muestra en negrita
- [ ] Se muestra notificación verde "Código escaneado"
- [ ] El contador "Códigos recientes (X)" se actualiza

### ✅ Múltiples escaneos
- [ ] Escanear 3-4 códigos seguidos
- [ ] Los códigos más recientes aparecen arriba
- [ ] El contador aumenta correctamente

### ✅ Botón Iniciar/Detener
- [ ] Click en "Detener" → Estado cambia a "Detenido"
- [ ] Escanear código → NO debería agregarse
- [ ] Click en "Iniciar" → Estado cambia a "Escuchando"
- [ ] Escanear código → SÍ debería agregarse

### ✅ Botón Copiar
- [ ] Click en ícono de copiar de un código
- [ ] Pegar en un editor de texto
- [ ] Se copia el código correcto

### ✅ Botón Limpiar
- [ ] Escanear varios códigos
- [ ] Click en "Limpiar"
- [ ] La lista se vacía
- [ ] Contador vuelve a (0)

### ✅ Diseño responsive
- [ ] La página se ve bien en pantalla completa
- [ ] La tarjeta de estado se ve completa
- [ ] Las instrucciones son legibles
- [ ] La lista de códigos tiene scroll

---

## 🔬 Prueba avanzada: Velocidad de escaneo

Los lectores USB reales escanean MUY rápido (< 50ms entre caracteres). Para simular:

1. **Copiar un código largo**: `ABCDEFGH123456789`
2. **Pegarlo rápidamente** en la página (Ctrl+V / Cmd+V)
3. **Presionar Enter**
4. ✅ Debería detectarse como un solo código

Si escribes letra por letra lentamente (> 100ms), el sistema puede detectarlo como entrada manual y limpiará el buffer. Esto es **intencional** para distinguir entre:
- 🤖 **Scanner**: Entrada rápida, captura automáticamente
- ⌨️ **Humano**: Entrada lenta, requiere Enter explícito

---

## 🛒 Prueba CON lector USB real

### Setup inicial

1. **Conectar lector USB** al computador
2. **Abrir Notepad/TextEdit**
3. **Escanear un código de barras**
4. ✅ Si el código aparece en Notepad, el lector funciona
5. ❌ Si no aparece nada, el lector tiene problemas

### En la aplicación

1. **Abrir**: `Configuración → Dispositivos → Lector USB/Teclado`
2. **Click en la página** (asegurar foco)
3. **Escanear código de barras físico**
4. ✅ Debería aparecer automáticamente (sin presionar Enter manualmente)

### Problemas comunes

**El código no aparece:**
- Hacer click en la página para dar foco
- Verificar que esté en estado "Escuchando"
- Probar escanear en Notepad primero

**El código se duplica:**
- Normal en algunos lectores
- El sistema debería filtrar duplicados por timestamp

**Caracteres extraños:**
- Layout del teclado (español vs inglés)
- Configurar el lector para ASCII estándar

---

## 📊 Resultados esperados

### ✅ Funcionando correctamente

```
Estado: ✅ Escuchando
Últimos códigos:
1. 📦 123456789012
2. 📦 987654321098
3. 📦 ABC123XYZ
```

### ❌ Problemas

```
Estado: ❌ Detenido
Últimos códigos: (vacío)
```

**Solución**: Click en "Iniciar"

---

## 🎓 Notas técnicas

### Detección de scanner vs humano

El sistema usa un timeout de **100ms** entre teclas:

- Si 2 teclas llegan en < 100ms → Es un scanner
- Si 2 teclas llegan en > 100ms → Es un humano (limpia buffer)

Esto previene que escritura manual accidental se detecte como código de barras.

### Longitud mínima

Los códigos deben tener **mínimo 3 caracteres**. Esto evita falsos positivos.

---

## ✅ Checklist de aceptación

Antes de marcar como completo:

- [ ] La página carga sin errores
- [ ] Se puede activar/desactivar la escucha
- [ ] Los códigos se detectan correctamente
- [ ] La lista muestra códigos recientes
- [ ] El botón copiar funciona
- [ ] El botón limpiar funciona
- [ ] Las instrucciones son claras
- [ ] Funciona en Windows/Web

---

## 🚀 Siguientes pasos

Una vez validado:

1. **Integrar con POS**: Agregar scanner a la página de venta
2. **Integrar con Inventario**: Buscar productos por código
3. **Integrar con Recepciones**: Registrar entrada de productos
4. **Dashboard de estadísticas**: Mostrar códigos escaneados por día

---

**¿Todo funciona? Excelente! 🎉 Ahora puedes proceder a integrar el scanner en otros módulos.**
