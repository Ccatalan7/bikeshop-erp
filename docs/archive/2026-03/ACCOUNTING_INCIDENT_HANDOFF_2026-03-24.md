# Handoff: incidente contable IVA / journal entries / Balance General

**Fecha:** 2026-03-24  
**Tenant:** Viñabike  
**Tenant ID:** `5443b130-cc28-45af-a420-cd500b288890`  
**Proyecto Supabase:** `xzdvtzdqjeyqxnkqprtf`

---

## Resumen ejecutivo

Se investigó y reparó un incidente contable de producción relacionado con IVA en ventas y asientos de pagos.

### Estado actual resumido

- ✅ **Se corrigió el problema de `sales_payments` que posteaban IVA (`2150`) indebidamente**.
- ✅ **Se eliminaron los payment JEs desbalanceados detectados en ese flujo**.
- ✅ **Se confirmó que el problema restante del Balance General ya no está en `sales_payments`**.
- ❌ **El Balance General sigue descuadrado por un problema fuerte en `2106 Sueldos por Pagar`**.
- ✅ **Se aisló la causa principal restante:** múltiples asientos de `expense_payments` debitan `2106` sin existir el crédito/acrual correspondiente.
- ⏳ **Falta aplicar o validar la corrección histórica del ledger para `expense_payments`**.
- ⏳ **Falta corregir la función origen para que no vuelva a ocurrir**.

---

## Problema original investigado

El incidente comenzó por ventas donde el terminal/pago guardó IVA en `sales_payments`, mientras la factura (`sales_invoices`) había quedado guardada como `no_tax` o con `iva_amount = 0`.

Eso produjo un modelo contable incorrecto:

- la factura no reconocía IVA correctamente
- el JE del pago sí estaba llevando IVA a `2150`
- eso generaba reconocimiento duplicado o mal ubicado del impuesto

### Modelo correcto

**Factura de venta:**
- reconoce ingreso
- reconoce IVA débito fiscal (`2150`)
- reconoce cuenta por cobrar (`1130`)

**Pago de venta:**
- **NO** reconoce IVA
- solo cancela `1130` contra caja/banco/tarjeta

---

## Archivos y artefactos relevantes

### 1. `supabase/migrations/20260324_fix_sales_terminal_tax_accounting.sql`
Archivo de reparación masiva para:
- detectar facturas afectadas por IVA en `sales_payments`
- actualizar `sales_invoices`
- reconstruir JEs de factura
- reconstruir JEs de pago

Incluye:
- creación de `tmp_broken_sales_tax`
- update de factura a `tax_included`
- rebuild de invoice JE vía `create_sales_invoice_journal_entry(...)`
- rebuild de payment JE vía `delete_sales_payment_journal_entry(...)` + `create_sales_payment_journal_entry(...)`

### 2. `supabase/migrations/20260324_rebuild_sales_payment_jes_after_tax_fix.sql`
Script creado para reconstruir payment JEs después de corregir la función de pagos.

### 3. `supabase/sql/core_schema.sql`
Source of truth local. Ahí están las funciones relevantes:
- `create_sales_payment_journal_entry(...)`
- `create_sales_invoice_journal_entry(...)`
- `get_balance_sheet_data(...)`
- `user_tenant_id()`

---

## Qué se hizo durante la sesión

## 1) Se verificó acceso real a Supabase

Se usó Supabase CLI con proyecto real.

### Hecho
- usuario hizo `supabase login`
- luego se verificó acceso con listado de proyectos

### Resultado
- acceso al proyecto remoto confirmado

---

## 2) Se ejecutó lint remoto del schema

Se corrió lint contra la DB remota.

### Hallazgo importante
La DB remota tiene **drift** y varios errores en funciones no relacionadas directamente a este incidente.

Ejemplos detectados:
- `create_purchase_invoice_journal_entry` referencia `invoice_date` faltante
- `create_sales_invoice_journal_entry` referencia `journal_entries.reference_type` inexistente
- otras funciones rotas: `cancel_online_order`, `update_online_order_status`, `reverse_purchase_invoice_journal_entry`, etc.

### Conclusión
La producción **no coincide completamente** con el código local.

---

## 3) Se intentó `supabase test db --linked`

### Resultado
No fue usable en esta sesión porque intentó depender de Docker local.

### Conclusión práctica
Para incidentes productivos, se terminó usando:
- Supabase CLI para validaciones rápidas del proyecto
- REST API con service role para inspección precisa de datos reales

---

## 4) Se diagnosticó el problema de `sales_payments`

Se levantó información real de:
- `sales_invoices`
- `sales_payments`
- `journal_entries`
- `journal_lines`

### Hallazgos iniciales
Se detectó que existían payment JEs con IVA en `2150`, lo que era incorrecto.

También se detectó al menos un payment JE desbalanceado.

---

## 5) Se identificaron pagos sospechosos y se reconstruyeron

Se aislaron varios pagos puntuales y se les borró/reconstruyó el JE mediante RPCs:
- `delete_sales_payment_journal_entry(p_payment_id)`
- `create_sales_payment_journal_entry(v_payment)`

### Problema encontrado
Al reconstruir inicialmente, el problema persistía.

### Conclusión
La función **deployed en remoto** de `create_sales_payment_journal_entry(...)` seguía estando mal.

---

## 6) Se corrigió el enfoque

Luego se pasó a una reparación global más correcta:
- redeploy de la función corregida
- borrado de payment JEs con `2150`
- recreación de payment JEs
- verificación posterior

### Resultado confirmado por queries
- ✅ no quedaron payment JEs con `2150`
- ✅ no quedaron payment JEs desbalanceados

### Conclusión
El problema de IVA en `sales_payments` quedó resuelto.

---

## 7) Se investigó por qué el Balance General seguía roto

Después de corregir `sales_payments`, el balance seguía así:

- `total_assets = 2851426.45`
- `total_liabilities = -2962849.66`
- `total_equity = 0`
- `accounting_equation_difference = 5814276.11`

### Interpretación
El problema restante **ya no era ventas/IVA**.

Se aisló el descuadre en pasivos y patrimonio.

---

## 8) Se encontró el principal driver: cuenta `2106`

Se revisaron cuentas de pasivo/patrimonio y apareció:

- `2106 Sueldos por Pagar = -3288500.00`
- `2150 IVA Débito Fiscal = 382501.55`
- `2101 Cuentas por Pagar Proveedores = -56851.21`
- patrimonio en `0`

### Conclusión
La cuenta crítica es `2106`.

---

## 9) Se hizo drill-down de `2106`

Se analizaron los movimientos de `2106` por JE.

### Hallazgo definitivo
Una larga lista de JEs de `expense_payments` hace esto:

- debit `2106`
- credit caja/banco
- descripción tipo `Pago gasto GTO-00035`, `Pago gasto GTO-00032`, etc.

Ejemplos:
- `Pago gasto GTO-00035` → débito `2106` `160000`
- `Pago gasto GTO-00032` → débito `2106` `156000`
- `Pago gasto GTO-00020` → débito `2106` `144000`
- `Pago gasto GTO-00008` → débito `2106` `138500`
- `Pago gasto GTO-00042` → débito `2106` `133000`

### Interpretación contable
Eso solo es correcto **si antes existió un crédito equivalente en `2106`** (devengo de sueldo por pagar).

Pero por el saldo observado, ese crédito previo no existe o no existe en magnitud suficiente.

### Conclusión fuerte
El Balance General está roto principalmente porque:

- `expense_payments` está usando `2106` como contracuenta
- pero esa deuda no fue reconocida previamente
- entonces `2106` quedó con saldo negativo gigante

---

## Estado actual de las hipótesis

## Resuelto
### A. IVA en pagos de ventas
**Estado:** RESUELTO

- Los payment JEs de ventas ya no deberían tocar `2150`
- Los pagos deben solo cancelar `1130`

## Aislado pero no completado
### B. Balance General descuadrado por `2106`
**Estado:** DIAGNOSTICADO

- `2106` está siendo debitado por `expense_payments`
- falta aplicar la corrección histórica y luego arreglar la función origen

## A revisar después
### C. Patrimonio / utilidad acumulada
**Estado:** PENDIENTE

- `equity = 0` es sospechoso
- incluso después de arreglar `2106`, podría seguir faltando lógica para reflejar utilidad acumulada / retained earnings en Balance General

---

## SQLs importantes usados durante la investigación

## 1. Verificación del balance real sin depender de `user_tenant_id()`

> Importante: desde SQL Editor / service role, `auth.uid()` suele ser `null`, por lo que funciones basadas en `user_tenant_id()` pueden devolver 0 filas.

```sql
with account_balances as (
  select
    a.type as account_type,
    a.category,
    a.code as account_code,
    a.name as account_name,
    case
      when a.type = 'asset' then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      when a.type in ('liability', 'equity') then
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
      else 0
    end::numeric(14,2) as amount
  from public.accounts a
  left join public.journal_lines jl
    on jl.account_id = a.id
   and jl.tenant_id = a.tenant_id
  left join public.journal_entries je
    on je.id = jl.entry_id
   and je.tenant_id = jl.tenant_id
   and je.status = 'posted'
   and je.entry_date <= '2026-03-31 23:59:59+00'::timestamptz
  where a.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and a.type in ('asset', 'liability', 'equity')
    and a.is_active = true
  group by a.id, a.type, a.category, a.code, a.name
  having coalesce(sum(jl.debit_amount), 0) <> 0
      or coalesce(sum(jl.credit_amount), 0) <> 0
)
select
  coalesce(sum(case when account_type = 'asset' then amount end), 0) as total_assets,
  coalesce(sum(case when account_type = 'liability' then amount end), 0) as total_liabilities,
  coalesce(sum(case when account_type = 'equity' then amount end), 0) as total_equity,
  coalesce(sum(case when account_type = 'asset' then amount end), 0)
    - (
        coalesce(sum(case when account_type = 'liability' then amount end), 0)
        + coalesce(sum(case when account_type = 'equity' then amount end), 0)
      ) as accounting_equation_difference
from account_balances;
```

## 2. Top cuentas de pasivo/patrimonio

```sql
with account_balances as (
  select
    a.type as account_type,
    a.category,
    a.code as account_code,
    a.name as account_name,
    case
      when a.type = 'asset' then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      when a.type in ('liability', 'equity') then
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
      else 0
    end::numeric(14,2) as amount
  from public.accounts a
  left join public.journal_lines jl
    on jl.account_id = a.id
   and jl.tenant_id = a.tenant_id
  left join public.journal_entries je
    on je.id = jl.entry_id
   and je.tenant_id = jl.tenant_id
   and je.status = 'posted'
   and je.entry_date <= '2026-03-31 23:59:59+00'::timestamptz
  where a.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and a.type in ('asset', 'liability', 'equity')
    and a.is_active = true
  group by a.id, a.type, a.category, a.code, a.name
  having coalesce(sum(jl.debit_amount), 0) <> 0
      or coalesce(sum(jl.credit_amount), 0) <> 0
)
select *
from account_balances
where account_type in ('liability', 'equity')
order by abs(amount) desc, account_code;
```

## 3. Drill-down de `2106`

```sql
select
  je.entry_date,
  je.source_module,
  je.source_reference,
  je.description,
  round(sum(jl.debit_amount), 2) as debit_2106,
  round(sum(jl.credit_amount), 2) as credit_2106,
  round(sum(jl.credit_amount) - sum(jl.debit_amount), 2) as net_2106
from public.journal_entries je
join public.journal_lines jl
  on jl.entry_id = je.id
 and jl.tenant_id = je.tenant_id
where je.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and je.status = 'posted'
  and jl.account_code = '2106'
group by je.entry_date, je.source_module, je.source_reference, je.description
order by net_2106 asc, je.entry_date asc
limit 100;
```

---

## Reparación histórica propuesta para `2106`

> ⚠️ Esto fue propuesto como siguiente paso lógico, pero al momento de este handoff **no está confirmado en producción** dentro de esta sesión.

La idea fue reclasificar líneas de `expense_payments` que hoy están en `2106` hacia `6101`.

### SQL propuesto

```sql
begin;

update public.journal_lines jl
set
  account_id = a.id,
  account_code = a.code,
  account_name = a.name,
  updated_at = now()
from public.journal_entries je
join public.accounts a
  on a.tenant_id = je.tenant_id
 and a.code = '6101'
where jl.entry_id = je.id
  and jl.tenant_id = je.tenant_id
  and je.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and je.status = 'posted'
  and je.source_module = 'expense_payments'
  and jl.account_code = '2106';

commit;
```

### Riesgo / nota técnica
Esto **corrige el ledger histórico**, pero antes de dejarlo como definitivo conviene validar:

- si `expense_payments` realmente debía ir contra `6101` en todos esos casos
- o si algunos pagos debían cancelar pasivos devengados reales
- o si existe más de un tipo de gasto mezclado en `expense_payments`

En otras palabras: **la evidencia apunta fuerte a que esto resuelve el descuadre**, pero vale la pena validar el modelo funcional antes de correrlo a ciegas en todos los casos.

---

## Qué falta por hacer

## Prioridad 1 — corregir ledger histórico de `2106`

### Objetivo
Quitar el falso pasivo negativo generado por `expense_payments`.

### Pendiente
- decidir si se aplica la reclasificación masiva `2106 -> 6101`
- correrla en producción
- volver a calcular Balance General

### Verificación posterior requerida
Ejecutar nuevamente la query de balance:

```sql
with account_balances as (
  select
    a.type as account_type,
    a.category,
    a.code as account_code,
    a.name as account_name,
    case
      when a.type = 'asset' then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      when a.type in ('liability', 'equity') then
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
      else 0
    end::numeric(14,2) as amount
  from public.accounts a
  left join public.journal_lines jl
    on jl.account_id = a.id
   and jl.tenant_id = a.tenant_id
  left join public.journal_entries je
    on je.id = jl.entry_id
   and je.tenant_id = jl.tenant_id
   and je.status = 'posted'
   and je.entry_date <= '2026-03-31 23:59:59+00'::timestamptz
  where a.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and a.type in ('asset', 'liability', 'equity')
    and a.is_active = true
  group by a.id, a.type, a.category, a.code, a.name
  having coalesce(sum(jl.debit_amount), 0) <> 0
      or coalesce(sum(jl.credit_amount), 0) <> 0
)
select
  coalesce(sum(case when account_type = 'asset' then amount end), 0) as total_assets,
  coalesce(sum(case when account_type = 'liability' then amount end), 0) as total_liabilities,
  coalesce(sum(case when account_type = 'equity' then amount end), 0) as total_equity,
  coalesce(sum(case when account_type = 'asset' then amount end), 0)
    - (
        coalesce(sum(case when account_type = 'liability' then amount end), 0)
        + coalesce(sum(case when account_type = 'equity' then amount end), 0)
      ) as accounting_equation_difference
from account_balances;
```

---

## Prioridad 2 — arreglar la función origen

### Objetivo
Que `expense_payments` no vuelva a postear contra `2106` incorrectamente.

### Pendiente
- localizar función que genera esos JEs
- confirmar si es una función tipo:
  - `create_expense_journal_entry(...)`
  - `create_expense_payment_journal_entry(...)`
  - o trigger relacionado a `expenses` / `expense_payments`
- corregirla en `supabase/sql/core_schema.sql`
- generar snippet de despliegue o migration puntual

### Qué buscar
Buscar en `core_schema.sql` y/o funciones remotas:
- `expense_payments`
- `2106`
- `Sueldos por Pagar`
- `create_expense`
- `payment_account_id`
- `salary_account_id`

---

## Prioridad 3 — revisar patrimonio / retained earnings

### Objetivo
Explicar por qué `total_equity = 0`.

### Pendiente
Incluso arreglando `2106`, puede seguir faltando reflejar:
- utilidades acumuladas
- cierre hacia patrimonio
- retained earnings en Balance General

### Hipótesis
El ledger podría estar bien a nivel de ingresos/gastos, pero el Balance General todavía no mostrar utilidad acumulada como patrimonio si no existe el asiento de cierre o una lógica equivalente en el reporte.

---

## Uso correcto de Supabase CLI en este proyecto

## 1. Login

```bash
supabase login
```

Esto abre autenticación web o pide token según entorno.

---

## 2. Verificar acceso al proyecto

```bash
supabase projects list
```

Esto confirma que el CLI realmente ve el proyecto remoto.

**Proyecto correcto esperado:** `xzdvtzdqjeyqxnkqprtf`

---

## 3. Lint remoto del schema

```bash
supabase db lint --linked --level warning --schema public
```

### Para qué sirve
- detectar funciones remotas rotas
- detectar drift evidente
- confirmar si producción tiene referencias a columnas inexistentes

### Observación importante
En esta sesión sí funcionó y fue útil.

---

## 4. Tests de DB ligados

```bash
supabase test db --linked
```

### Importante
En esta sesión **no fue confiable** porque intentó usar Docker local.

### Recomendación
Si no hay Docker disponible, no perder tiempo ahí durante incidentes urgentes.

---

## 5. Cuándo usar CLI y cuándo usar REST con service role

## Usa Supabase CLI para:
- verificar acceso al proyecto
- lint remoto
- operaciones de proyecto
- algunos checks de estructura

## Usa REST API + service role para:
- diagnósticos productivos exactos
- consultar tablas reales rápidamente
- ejecutar RPCs directamente
- inspección masiva de `journal_entries` / `journal_lines`

---

## Uso correcto de REST con service role en este repo

La documentación del repo deja claro que para consultas productivas se prefirió REST por sobre psql.

### Obtener la key desde `.env`
Variable usada:
- `SUPABASE_SECRET_KEY`

### Patrón Python usado en esta sesión

```python
import json, pathlib, urllib.request
root = pathlib.Path('/Users/Vinabike/dev/bikeshop-erp')
key = None
for line in (root / '.env').read_text().splitlines():
    if line.startswith('SUPABASE_SECRET_KEY='):
        key = line.split('=', 1)[1].strip().strip('"').strip("'")
        break

base = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1'
headers = {
    'apikey': key,
    'Authorization': f'Bearer {key}',
}
```

### Patrón de fetch usado

```python
def fetch(path):
    req = urllib.request.Request(f'{base}/{path}', headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.load(r)
```

---

## Buenas prácticas para retomar en otro PC

## 1. Llevar este archivo
Archivo recomendado de continuidad:
- `ACCOUNTING_INCIDENT_HANDOFF_2026-03-24.md`

## 2. Verificar acceso al proyecto apenas abras el repo

```bash
supabase login
supabase projects list
supabase db lint --linked --level warning --schema public
```

## 3. No uses `get_balance_sheet_data(...)` desde SQL editor para validar producción
Porque depende de:
- `auth.uid()`
- `user_tenant_id()`

Desde SQL editor/service role suele devolver 0 filas.

Usa mejor queries directas filtrando `tenant_id`.

## 4. Antes de correr la reclasificación histórica de `2106`
Haz una última validación de muestra:
- el tipo real de documentos en `expense_payments`
- si todos son pagos de sueldos o si hay mezcla de gastos

## 5. Después de corregir `2106`
Recalcular inmediatamente:
- balance general
- top liabilities/equity
- revisar si aún queda pendiente patrimonio / utilidad acumulada

---

## Siguiente paso recomendado al retomar

1. Verificar nuevamente los movimientos de `2106` por `source_module`
2. Si se confirma que casi todo viene de `expense_payments`, aplicar la reclasificación histórica propuesta
3. Recalcular Balance General
4. Si sigue descuadrado, revisar patrimonio / utilidad acumulada
5. Luego corregir definitivamente la función de origen en `core_schema.sql`

---

## TL;DR rápido

- El problema de IVA en `sales_payments` quedó corregido.
- El Balance General sigue roto por `2106 Sueldos por Pagar`.
- `expense_payments` está debitando `2106` sin pasivo previo suficiente.
- Siguiente reparación importante: reclasificar esos débitos históricos y corregir función origen.
- No validar `get_balance_sheet_data(...)` desde SQL editor porque `auth.uid()` queda en `null`.

---

## Estado final de esta sesión

**Completado:**
- diagnóstico y reparación del error de IVA en payment JEs de ventas
- aislamiento del problema restante en `2106`

**Pendiente crítico:**
- corrección histórica de `expense_payments` / `2106`
- corrección de la función que genera esos JEs
- eventual revisión de patrimonio / retained earnings
