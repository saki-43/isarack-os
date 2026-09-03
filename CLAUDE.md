# ISA-OS — Guía para Claude Code

Este archivo lo lees automáticamente cada vez que trabajes en este repo.
Léelo entero antes de tocar código o proponer cambios.

Autor único: Isaac (owner de ISARACK, Tijuana). Trabaja en español.
Es nuevo en línea de comandos y en Git — explica los pasos, no des por sabido nada de terminal.

---

## 1. Qué es ISA-OS

- App administrativa de ISARACK (racks industriales y anaqueles).
- Un solo archivo `index.html` (~1 MB) con HTML + CSS + JS inline. **Sin frameworks**, sin build.
- Vive en producción en Vercel; despliega solo al hacer push a `main`.
- Parte de un ecosistema de 3 apps que comparten el mismo Supabase:
  - **ISA-OS** (este repo) — admin, la usan vendedores y administración.
  - **PWA Instaladores** (`isarack-instaladores`) — la usan los instaladores en campo.
  - **App Entrega/Recepción** (`isarack-entrega-recepcion`) — recepción de material.
- Repos relacionados: `isarack-web` (configurador 3D), `SEGUIMIENTO-DE-PEDIDOS` (versión vieja).

---

## 2. Regla de oro del deploy

**COMMIT SÍ, PUSH NO.** Nunca hagas `git push` sin que Isaac lo autorice explícitamente.

Motivo: Vercel despliega automáticamente al empujar a `main`. Un cambio malo llega a producción en un minuto y afecta a todo el equipo (Daniel, Miguel, Adrián, Gil, Jesús). El respaldo en GitHub no previene el rato que estarían con el sistema roto.

Flujo correcto:
1. Editas archivos.
2. Haces `git add` y `git commit` con mensaje descriptivo en español.
3. Le avisas a Isaac qué commit hiciste y qué contiene.
4. **ÉL** hace el push cuando lo revisó.

Adicional: después de cada deploy real, Isaac va a **Configuración → ☁ Sincronización → 🚀 Forzar versión a todos** para que los usuarios abiertos recarguen. No es tu problema, pero conviene que sepas que existe.

---

## 3. Versión

- Formato: `APP_VERSION = "2026.MM.DD.NN"` (año.mes.día.consecutivo del día).
- **Cada cambio incrementa la versión.** Si haces dos commits el mismo día, el segundo es `.02`.
- `min_version` en `empresa_config` fuerza recarga a todos. Cambiarlo con cuidado.

---

## 4. Constantes del sistema (no cambies sin preguntar)

| Cosa | Valor |
|---|---|
| Color de marca | `#DA6635` (naranja) |
| IVA | **8 %** (zona fronteriza Tijuana, NO 16 %) |
| Supabase project | `zjvuugslnfrivlyvzlei` |
| Supabase URL | `https://zjvuugslnfrivlyvzlei.supabase.co` |
| GitHub user | `saki-43` |
| Comisión Daniel | 2.20 % fijo (`COM_PCT_FIJO`) |
| Bimestres de comisión | JUN-JUL, AGO-SEP, OCT-NOV, DIC-ENE, FEB-MAR, ABR-MAY |

---

## 5. Arquitectura de datos

Tablas principales en Supabase:
`orders`, `ventas`, `facturas`, `inventario`, `contactos`, `empresa_config`, `bom_rules`, `inv_movimientos`, `papelera`, `pedidos_eliminados`.

**Todas las tablas tienen `updated_at`. Incluye `updated_at` en cada UPDATE** o la lógica de sync no ve el cambio.

Un folio de pedido vive **duplicado en 3 tablas**: nace en `ventas` (como cotización), al confirmarse se copia a `orders`, y al facturar se copia a `facturas`. A partir de ahí cada copia vive su vida — corregir el cliente en la venta no toca al pedido ni a la factura. Ten esto presente al proponer cambios.

`empresa_config`: upsert con `onConflict: 'clave'`. La columna `valor` es JSONB y **para algunas claves está doble-codificada** (jsonb que contiene un string con el JSON). Ejemplos: `pedidos_eliminados`, `diag_atendidos`, `min_version`. Para leer: `(valor #>> '{}')::jsonb`. Al escribir hay que conservar el formato o la app no lo parsea.

---

## 6. Patrón CRÍTICO de sincronización

**Cualquier mutación a `facturas[i]`, `orders`, `ventas` o `inventario` debe llamar a la función `cloudSync*` correspondiente inmediatamente después de `guardarLS()`.**

Si no lo haces, el cambio se ve en pantalla pero **desaparece al refrescar** porque no subió a Supabase. Este es el bug #1 histórico del sistema.

Ejemplo correcto:
```js
facturas[idx].pagado = true;
guardarLS(FAC_KEY, facturas);
cloudSyncFactura(facturas[idx]);   // ← esta línea no se olvida
```

---

## 7. Casos que NO son errores (no los marques como bugs)

Isaac ya validó cada uno de estos. Márcalos como **normal** en cualquier auditoría:

1. **Ventas históricas** — ventas con `tipo='Venta'` y stage `'Pedido de venta / Confirmada'` que **no tienen pedido en `orders`**. Son ventas reales anteriores a que el sistema exigiera pedido. Ejemplos: Panasonic (S07179, S07180), Hunter (S07139, S07141, S07181), Encore, etc. La cotización de estas se toma directo de `ventas.lineas` (ver `verPedidoDesdeFactura`).
2. **Pedidos completados sin venta** — S07069, S07082, S07084. Los subió Daniel como históricos.
3. **Facturas en $0** — algunas históricas quedan así. Normal.
4. **Facturas pagadas sin fecha de pago** — se quedan así.
5. **Contactos con nombre duplicado** — clientes recurrentes. No deduplicar automáticamente.
6. **Facturas pagadas sin monto capturado** cuando existe pdfAnticipo/pdfFiniquito/pdfComplemento o pagosExtra — el comprobante ES el rastro del cobro. La regla no es "hay número", es "hay comprobante O hay número".
7. **`updated_at` reciente en `orders`** — no evidencia de escritura reciente. El loop `cloudSyncTodosLosPedidos` reescribe la tabla completa de un jalón. Usa `payload.updated` para saber la fecha real.
8. **12 SKUs SEL/PIC (diagonales D/H) con precio $4** — asignado en auditoría de julio 2026, no es error.
9. **PWA Instaladores: 7 usuarios con clave FIJA hardcodeada** (NO últimos 4 del teléfono):
   - Brayan Alexis: `1234`
   - Jonas Sañudo: `5678`
   - Gilberto Rodriguez: `2323`
   - Oscar Ochoa: `2271`
   - Israel Mendez: `7052`
   - Isaac Romero: `2110`
   - Samuel A. Gomez: `5232`
   Los usuarios "extras" que se agregan desde Configuración sí usan últimos-4.
   **La tabla vive duplicada en ISA-OS y en la PWA** — si se cambia un código hay que cambiarlo en los dos.

---

## 8. Trampas conocidas (evítalas)

- **NUNCA uses `window.orders`.** `orders` está declarado con `let` y las `let` no viven en `window`. Devuelve undefined. `ventas`, `facturas` e `inventario` usan `var` y sí funcionan, pero por consistencia usa siempre `typeof X !== 'undefined' && Array.isArray(X)`.
- **NO actives RLS en Supabase sin migrar antes a Supabase Auth.** ISA-OS entra con login custom (tabla `users` + llave anon), NO usa `auth.users`. Activar RLS bloquea todas las escrituras. Se intentó el 18 jul 2026 y hubo que revertir el mismo día.
- **La lista negra `pedidos_eliminados`** (empresa_config) puede dejar pedidos "invisibles" — existen en la nube pero la app los oculta. Al re-confirmar una venta hay que sacar el folio de la lista (lo hace `reconciliarPedidosEliminados()` en cada sync).
- **`cloudUpsert` fallaba en silencio** hasta v2026.07.21.13. Ahora anota fallos en `isarack_fallos_sync` y los muestra en Diagnóstico. Si agregas rutas de subida nuevas, engancha `_registrarFalloSync` en el catch.
- **`encolar` NO descarta operaciones** desde v2026.07.21.14. Si falla 6 veces las marca `_atorado` en la cola pero no las tira. Botón "Reintentar pendientes" las reactiva.
- **Adjuntos de facturas viven como base64 en JSONB** (columnas `pdf_factura`, `pdf_rfc`, `pdf_po`, `pdf_anticipo`, `pdf_finiquito`). Bajarlos todos revienta el navegador — por eso existe la vista `facturas_ligeras` y el patrón `_cascaron` + hidratación on-demand (`_hidratarAdjFactura`). No regreses a bajar la tabla completa.
- **Checks de "hay archivo"** usan el helper global `_hayAdj(a)` — true si hay `.data`, `.url`, `._enNube` o `.name`. **NO uses `a.data` directo** o vas a decir "Falta" cuando el archivo está en la nube.
- **Trigger `proteger_pedido` v4 y `trg_proteger_factura`** en la base conservan datos si llega un UPDATE incompleto. Escape para borrar de verdad: `{"_borrar": true}`.
- **Reparadores automáticos** (`repararVentasHuerfanas`, `reconciliarInventario`, cualquier reparador similar): al crear un pedido nuevo desde una venta, **usar SIEMPRE `v.fecha` como base del `tsVenta`/`id`**, no `Date.now()`. Fórmula: `id/tsVenta = Number(v.tsVenta) || Date.parse(v.fecha+'T12:00:00') || Date.now()+random`. Si usas `Date.now()`, cuando el reparador crea muchos pedidos en un mismo tick TODOS quedan con la misma hora falsa y la tabla Seguimiento muestra la hora del reparador en vez de la fecha real de la venta. Bug corregido en v2026.09.01.01 con `_autoRepararTsVentaMasivo()` (detecta 5+ pedidos con `id` en el mismo segundo y adopta la fecha real de su venta). Los reparadores corren en cada arranque y en cada sync de nube — nunca creen datos con timestamp "del momento" si tienen la fecha real disponible.
- **`orders.id` es PRIMARY KEY** en Supabase. Si dos pedidos comparten el mismo `id` numérico, el upsert regresa **409 duplicate key value violates unique constraint "orders_pkey"** y la operación queda `_atorada` en `cloudQueue`. Nunca uses `Date.parse(fecha+'T12:00:00')` a solas para el `id` — dos ventas del mismo día colisionan. Usa el helper **`_idPedidoDesdeVenta(v)`** (v2026.09.01.03): prioriza `v.tsVenta` (hora real "minutero"); si no hay, base = `Date.parse(fecha+'T12:00:00')` + desvío determinista `hash(v.num) % 86_400_000` ms → único por folio y estable. `tsVenta` se guarda aparte y `_tsVentaOrden` lo prioriza para mostrar la hora en la tabla. Al confirmar una venta (crearCotizacionVenta / confirmVenta / guardarVenta caso A) escribe también `v.tsVenta=Date.now()` **en la venta** para preservar el minutero real y que futuros reparadores no lo pierdan. Cuando la cola se atore con 409-pkey, `_rescatarOrdersAtoradasPorPK()` regenera el id con el helper y reencola — corre en boot y en cada sync.
- **Visores de documentos** (v2026.09.01.08+ / v2026.09.02.01+): TODO ISA-OS abre presupuestos con el visor HTML (`openHTMLViewer`). En `viewPDF` y `verPresupuestoVenta` la prioridad es `cotData` → `cotHTML` → PDF web (fallback). Los RW/GW/PW ya no priorizan el PDF web del configurador. Para PDFs externos (PO, CSF, factura escaneada) `openPDFData` ahora renderiza **todas las páginas apiladas verticalmente** (una debajo de otra) — sin flechas de página. Fit inicial al ancho del scroll, modal max-width 1400px. Descarga e impresión siguen usando `_pdfRawBytes` (bytes originales), no dependen de los canvases. IDs de canvas: `pdf-cv` (primera página) y `pdf-cv-2`, `pdf-cv-3`... para las siguientes.

---

## 9. Dónde vive cada módulo (referencias rápidas)

- **Ventas / Cotizaciones**: función `guardarVenta` (transiciones de estado, Casos A/B/C).
- **Facturación**: pestaña con vistas Master-Detail y Vista Almacén.
- **Kardex / Inventario**: tabla `inventario`, movimientos en `inv_movimientos`, reglas de composición en `bom_rules`.
- **Instalaciones**: paquetes de documentos, cuadrillas, órdenes de compra.
- **Diagnóstico** (v2026.07.21.09+): pestaña solo admin, `_diagChequeos()` devuelve `{id, titulo, detalle, nivel, filas[]}` por chequeo. Para agregar chequeo nuevo: agrega función que devuelva filas.
- **Papelera** (v2026.07.20.02): pestaña dentro de Configuración, solo admin. Lee de tabla `papelera`.
- **SAKI**: widget de voz (ElevenLabs + Gemini 2.5 Flash), visible solo para Isaac y Gil. Conectado a 3 Edge Functions: `cotizar`, `inventario`, `pedidos`.

---

## 10. Cómo hablarle a Isaac

- Español, tono directo, respuestas breves.
- Es nuevo en línea de comandos y Git — pasos numerados y explícitos.
- Para cambios grandes de UI o estructurales (50+ líneas o varias funciones): primero mockup o descripción para aprobación, DESPUÉS código.
- Para arreglos chicos (un campo, una función): directo al código.
- Cuando propongas un cambio, di también qué NO cambia y qué podría romperse.

---

## 11. Cosas que Supabase se hace en el chat, no aquí

Isaac prefiere que las consultas y cambios directos a Supabase (SQL, migraciones, ajustar `empresa_config`, tocar triggers) se hagan **en el chat de Claude.ai**, no desde Claude Code. Ahí verificamos antes de escribir. Si te pide algo que requiere SQL, sugiérele hacerlo en el chat.
