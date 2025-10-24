# 📦 Guía de Lectores de Código de Barras

## 🎯 Resumen

Este ERP soporta **dos tipos de lectores de código de barras** para adaptarse a diferentes entornos de trabajo:

1. **🖥️ Lector USB/Teclado** - Para escritorio (Windows, macOS, Linux, Web)
2. **📱 Lector Bluetooth** - Para móviles (Android, iOS)

---

## 🖥️ Lector USB/Teclado (Recomendado para Desktop/POS)

### ¿Qué es?

Los lectores USB de código de barras que emulan un teclado (HID - Human Interface Device). Cuando escaneas un código, el lector "escribe" el código como si lo hubieras tecleado.

### ✅ Ventajas

- ✅ **Funciona en todos los sistemas operativos** (Windows, macOS, Linux, Web)
- ✅ **No requiere drivers** - Plug and play
- ✅ **No requiere permisos especiales**
- ✅ **Más económico** que lectores Bluetooth
- ✅ **Mayor velocidad** de escaneo
- ✅ **Ideal para POS/escritorio**

### 🛒 Ejemplos de productos compatibles

Cualquier lector USB que diga "Keyboard Wedge" o "HID" funcionará:

- **Symbol/Zebra LS2208** (~$100-150 USD)
- **Honeywell Voyager 1200g** (~$120-180 USD)
- **Datalogic QuickScan QD2430** (~$100-140 USD)
- **Inateck BCST-70** (~$30-50 USD) - Económico
- **Tera HW0002** (~$25-40 USD) - Básico

Buscar en Amazon/MercadoLibre: "USB barcode scanner keyboard emulation"

### 📋 Cómo usar

1. **Conectar el lector USB** al computador
2. **Abrir el módulo**: `Configuración → Dispositivos → Lector USB/Teclado`
3. **Presionar "Iniciar"** (se activa automáticamente)
4. **Escanear cualquier código de barras**
5. El código aparecerá automáticamente en la lista

### 🔧 Configuración del lector (opcional)

La mayoría de lectores USB vienen con configuración por defecto que funciona:
- **Sufijo**: Enter (envía Enter después de cada código)
- **Prefijo**: Ninguno
- **Código de caracteres**: ASCII estándar

Si necesitas cambiar la configuración:
1. Consulta el manual de tu lector
2. Usa los códigos de barras de configuración (generalmente incluidos)
3. Configura para que envíe "Enter" al final de cada código

### 💻 Uso en diferentes plataformas

| Plataforma | Estado | Notas |
|------------|--------|-------|
| **Windows** | ✅ Recomendado | Perfecto para POS y escritorio |
| **macOS** | ✅ Funciona | Plug and play |
| **Linux** | ✅ Funciona | Puede requerir permisos USB |
| **Web** | ✅ Funciona | Requiere foco en la ventana |

---

## 📱 Lector Bluetooth (Para móviles)

### ¿Qué es?

Lectores de código de barras que se conectan vía Bluetooth Low Energy (BLE) a dispositivos móviles.

### ✅ Ventajas

- ✅ **Inalámbrico** - Mayor movilidad
- ✅ **Ideal para inventario** en bodega
- ✅ **Funciona en tablets** Android/iOS
- ✅ **Portátil** - Llevar en el bolsillo

### ⚠️ Limitaciones

- ❌ **No funciona en web/desktop** (limitación técnica de Bluetooth)
- ⚠️ **Requiere permisos** de Bluetooth y ubicación
- ⚠️ **Más caro** que lectores USB
- ⚠️ **Requiere batería** y recarga

### 🛒 Ejemplos de productos compatibles

Lectores Bluetooth Low Energy (BLE):

- **Socket Mobile CHS 7Ci/7Di** (~$200-300 USD)
- **Inateck BCST-52** (~$60-80 USD)
- **TaoTronics TT-BS030** (~$50-70 USD)
- **Eyoyo EY-002** (~$40-60 USD)

⚠️ **IMPORTANTE**: Debe ser Bluetooth Low Energy (BLE/4.0+), no Bluetooth Classic

### 📋 Cómo usar

1. **Abrir el módulo**: `Configuración → Dispositivos → Lector Bluetooth`
2. **Encender el lector** Bluetooth
3. **Permitir permisos** cuando se soliciten
4. **Buscar dispositivos** disponibles
5. **Conectar** al lector deseado
6. **Escanear** - Los códigos llegarán automáticamente

### 🔐 Permisos necesarios

**Android:**
- Bluetooth Scan
- Bluetooth Connect
- Ubicación (requerido por Android para BLE)

**iOS:**
- Bluetooth (se solicita automáticamente)

### 💻 Uso en diferentes plataformas

| Plataforma | Estado | Notas |
|------------|--------|-------|
| **Android** | ✅ Funciona | Requiere permisos |
| **iOS** | ✅ Funciona | Requiere permiso |
| **Windows** | ❌ No soportado | Usar lector USB |
| **macOS** | ❌ No soportado | Usar lector USB |
| **Web** | ❌ No soportado | Usar lector USB |

---

## 🏢 Recomendaciones por Escenario

### 🛒 POS / Punto de Venta (Desktop)

**Recomendación: Lector USB/Teclado**

✅ Conexión estable sin interferencias  
✅ No requiere baterías  
✅ Más rápido para alto volumen  
✅ Funciona en Windows/Web  

**Producto sugerido**: Honeywell Voyager 1200g o Inateck BCST-70 (económico)

---

### 📦 Inventario en Bodega (Móvil)

**Recomendación: Lector Bluetooth + Tablet/Celular**

✅ Movilidad total  
✅ Escanear mientras caminas  
✅ Tablet con pantalla grande para ver stock  

**Producto sugerido**: Socket Mobile CHS 7Ci o Inateck BCST-52

---

### 🚴 Taller de Bicicletas (Híbrido)

**Recomendación: Ambos**

**En escritorio (Windows)**: Lector USB para registro de pegas  
**En bodega (móvil)**: Lector Bluetooth para buscar repuestos  

---

### 🌐 Uso en Web/Navegador

**Recomendación: Lector USB/Teclado (única opción)**

Los navegadores web no soportan Bluetooth Low Energy para escaneo de códigos.

---

## 🔧 Solución de Problemas

### Lector USB no funciona

1. **Verificar conexión**: Desconectar y reconectar USB
2. **Probar en otro puerto**: Algunos puertos USB pueden tener problemas
3. **Verificar en editor de texto**: Abrir Notepad/TextEdit y escanear - debería escribir el código
4. **Configurar sufijo**: El lector debe enviar "Enter" al final (consultar manual)
5. **Reiniciar aplicación**: Cerrar y volver a abrir la página/app

### Lector Bluetooth no conecta

1. **Verificar permisos**: Ir a Configuración de Android/iOS → Permisos de la app
2. **Bluetooth activado**: Verificar que Bluetooth esté encendido
3. **Modo de emparejamiento**: Algunos lectores requieren botón especial para emparejar
4. **Distancia**: Mantener el lector cerca del dispositivo (< 5 metros)
5. **Batería**: Verificar que el lector tenga batería
6. **Reiniciar lector**: Apagar y encender el lector Bluetooth

### Códigos se escanean duplicados

**Lector USB:**
- El lector puede estar enviando el código dos veces
- Configurar "tiempo de espera entre escaneos" en el lector (consultar manual)

**Lector Bluetooth:**
- Normal en algunos lectores - el sistema filtra duplicados automáticamente

### Códigos con caracteres extraños

- **Problema**: Layout del teclado diferente (español vs inglés)
- **Solución**: Configurar el lector para usar ASCII estándar sin caracteres especiales
- **Alternativa**: Configurar layout del teclado del sistema

---

## 🎓 Mejores Prácticas

### ✅ Para POS/Escritorio

1. Usar **lector USB con soporte**
2. Colocar el lector a la **derecha del teclado**
3. Configurar **sufijo Enter** para escaneo rápido
4. Tener **lector de repuesto** para emergencias

### ✅ Para Inventario Móvil

1. **Cargar el lector** antes de iniciar turno
2. Mantener **tablet/celular con datos móviles** para sincronizar
3. Usar **funda con clip** para llevar el lector
4. **Sincronizar inventario** al final del día

### ✅ Para Taller

1. **Proteger el lector** del polvo y grasa (funda plástica)
2. Limpiar regularmente con **paño seco**
3. Evitar caídas - los lectores son frágiles
4. Etiquetar repuestos con **códigos legibles**

---

## 📊 Comparación Rápida

| Característica | USB/Teclado | Bluetooth |
|----------------|-------------|-----------|
| **Plataformas** | Windows, Mac, Linux, Web | Solo Android/iOS |
| **Instalación** | Plug and play | Requiere emparejamiento |
| **Permisos** | No requiere | Requiere permisos |
| **Precio** | $25-150 USD | $40-300 USD |
| **Movilidad** | Cable (1-2 metros) | Inalámbrico (10 metros) |
| **Batería** | No requiere | Requiere recarga |
| **Velocidad** | Muy rápida | Rápida |
| **Ideal para** | POS, Escritorio | Inventario, Bodega |

---

## 🛠️ Configuración Técnica

### Para desarrolladores

El sistema detecta automáticamente la plataforma:

```dart
// Desktop/Web → Lector USB/Teclado
if (Platform.isWindows || Platform.isMacOS || Platform.isLinux || kIsWeb) {
  // Usa BarcodeScannerService (keyboard listener)
}

// Mobile → Lector Bluetooth
if (Platform.isAndroid || Platform.isIOS) {
  // Usa BluetoothScannerService (flutter_blue_plus)
}
```

**Stream unificado de códigos:**

```dart
scannerService.barcodeStream.listen((barcode) {
  print('Código escaneado: $barcode');
  // Buscar producto, agregar a carrito, etc.
});
```

---

## 📞 Soporte

Si tienes problemas con los lectores:

1. **Verificar compatibilidad**: Asegúrate de que tu lector esté en la lista de compatibles
2. **Leer manual**: Cada lector tiene configuraciones específicas
3. **Contactar soporte**: Si el problema persiste

---

## ✅ Conclusión

Para un ERP en una bikeshop con operaciones mixtas:

- **🖥️ Windows POS**: Lector USB (Honeywell Voyager 1200g)
- **📦 Inventario móvil**: Lector Bluetooth + Tablet Android (Socket Mobile CHS 7Ci)
- **💰 Presupuesto limitado**: Lector USB económico (Inateck BCST-70)

**El sistema soporta ambos - elige según tu caso de uso!** 🎯
