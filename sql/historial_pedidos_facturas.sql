-- ════════════════════════════════════════════════════════════════════════════
-- HISTORIAL DE PEDIDOS Y FACTURAS (14 oct 2026)
-- Mismo principio que ventas_historial: antes de cada cambio real a un pedido
-- (orders) o a una factura (facturas) se guarda una copia de cómo estaba.
-- Los BORRADOS ya los cubre la papelera (trigger zz_papelera), aquí solo ediciones.
--
-- Cuidados:
--  • Facturas: los PDFs/XML viven como base64 dentro del renglón (hasta 9.5 MB).
--    NO se copian ni se leen (leerlos destoastea el base64 y choca con el
--    statement_timeout de 3 s del rol anon, ver CLAUDE.md). Solo se anota si
--    había archivo o no. pagos_extra / xml solo se copian si pesan < 20 KB.
--  • Pedidos: cualquier campo de más de 20 KB (planos o fotos en base64) se
--    sustituye por {"_omitido": true, "bytes": n}.
--  • Si el UPDATE no cambió nada (solo updated_at), no se guarda copia: el loop
--    cloudSyncTodosLosPedidos reescribe la tabla completa sin cambiar datos.
--  • AFTER UPDATE: se compara contra el renglón ya final (después de que
--    proteger_pedido / proteger_factura restauren lo que haga falta).
--  • La tabla no se expone a la app (sin permisos para anon/authenticated); se
--    consulta desde el chat de Supabase. NO se activa RLS.
--
-- Recuperar algo:
--   select guardado_en, datos from historial_cambios
--    where tabla='orders' and ref='S07536' order by guardado_en desc;
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.historial_cambios (
  id          bigserial primary key,
  tabla       text        not null,            -- 'orders' | 'facturas'
  ref         text,                            -- folio del pedido (S0xxxx)
  ref_id      bigint,                          -- id del renglón
  datos       jsonb       not null,            -- cómo estaba ANTES del cambio
  guardado_en timestamptz not null default now()
);
create index if not exists historial_cambios_ref_idx on public.historial_cambios (tabla, ref, guardado_en desc);
revoke all on public.historial_cambios from anon, authenticated;
revoke all on sequence public.historial_cambios_id_seq from anon, authenticated;

-- Quita del jsonb cualquier valor de más de `lim` bytes (base64 de planos/fotos).
-- Revisa el primer nivel y, dentro de 'payload', también su primer nivel.
create or replace function public._hist_aligerar(j jsonb, lim int default 20000)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k,
           case
             when k = 'payload' and jsonb_typeof(v) = 'object' then
               (select coalesce(jsonb_object_agg(k2,
                  case when length(v2::text) > lim
                       then jsonb_build_object('_omitido', true, 'bytes', length(v2::text))
                       else v2 end), '{}'::jsonb)
                  from jsonb_each(v) as e2(k2, v2))
             when length(v::text) > lim
               then jsonb_build_object('_omitido', true, 'bytes', length(v::text))
             else v
           end), '{}'::jsonb)
    from jsonb_each(j) as e(k, v)
$$;

-- ── Pedidos ──────────────────────────────────────────────────────────────────
create or replace function public.orders_guardar_historial()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if (to_jsonb(OLD) - 'updated_at') = (to_jsonb(NEW) - 'updated_at') then
    return NULL;
  end if;
  insert into historial_cambios (tabla, ref, ref_id, datos)
  values ('orders', coalesce(OLD.num, OLD.payload->>'num'), OLD.id,
          _hist_aligerar(to_jsonb(OLD) - 'updated_at'));
  return NULL;
exception when others then
  -- El historial nunca debe tumbar el guardado del pedido.
  raise warning 'orders_guardar_historial: %', SQLERRM;
  return NULL;
end $$;

drop trigger if exists trg_orders_historial on public.orders;
create trigger trg_orders_historial
  after update on public.orders
  for each row execute function public.orders_guardar_historial();

-- ── Facturas (sin tocar el contenido de los adjuntos) ───────────────────────
-- OJO: los campos se leen uno por uno de OLD/NEW. NO pasar el renglón completo a
-- otra función ni usar to_jsonb(OLD): eso arma el renglón entero y lee el base64
-- de todos los PDFs. `x is not null` y pg_column_size() no lo leen.
-- Si solo se reemplaza un PDF por otro (había y sigue habiendo), no se guarda copia.
create or replace function public.facturas_guardar_historial()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare antes jsonb; despues jsonb;
begin
  antes := jsonb_build_object(
      'id', OLD.id, 'pedido', OLD.pedido, 'cliente', OLD.cliente, 'razon', OLD.razon,
      'rfc', OLD.rfc, 'monto', OLD.monto, 'anticipo', OLD.anticipo, 'finiquito', OLD.finiquito,
      'factura', OLD.factura, 'cfdi', OLD.cfdi, 'fecha', OLD.fecha, 'estado', OLD.estado,
      'ejecutivo', OLD.ejecutivo, 'po_num', OLD.po_num, 'pagado', OLD.pagado, 'fecha_pago', OLD.fecha_pago,
      'po_na', OLD.po_na, 'factura_na', OLD.factura_na, 'rfc_na', OLD.rfc_na, 'anticipo_na', OLD.anticipo_na,
      'finiquito_na', OLD.finiquito_na, 'complemento_na', OLD.complemento_na, 'forma_pago_nf', OLD.forma_pago_nf, 'ts', OLD.ts,
      'created_at', OLD.created_at,
      'hay_pdf_data', OLD.pdf_data is not null,
      'hay_pdf_fact_num', OLD.pdf_fact_num is not null,
      'hay_pdf_factura', OLD.pdf_factura is not null,
      'hay_pdf_rfc', OLD.pdf_rfc is not null,
      'hay_pdf_po', OLD.pdf_po is not null,
      'hay_pdf_anticipo', OLD.pdf_anticipo is not null,
      'hay_pdf_finiquito', OLD.pdf_finiquito is not null,
      'hay_pdf_complemento', OLD.pdf_complemento is not null,
      'pagos_extra', case when coalesce(pg_column_size(OLD.pagos_extra), 0) < 20000 then OLD.pagos_extra else jsonb_build_object('_omitido', true) end,
      'xml_cfdi', case when coalesce(pg_column_size(OLD.xml_cfdi), 0) < 20000 then OLD.xml_cfdi else jsonb_build_object('_omitido', true) end,
      'xml_complemento', case when coalesce(pg_column_size(OLD.xml_complemento), 0) < 20000 then OLD.xml_complemento else jsonb_build_object('_omitido', true) end);
  despues := jsonb_build_object(
      'id', NEW.id, 'pedido', NEW.pedido, 'cliente', NEW.cliente, 'razon', NEW.razon,
      'rfc', NEW.rfc, 'monto', NEW.monto, 'anticipo', NEW.anticipo, 'finiquito', NEW.finiquito,
      'factura', NEW.factura, 'cfdi', NEW.cfdi, 'fecha', NEW.fecha, 'estado', NEW.estado,
      'ejecutivo', NEW.ejecutivo, 'po_num', NEW.po_num, 'pagado', NEW.pagado, 'fecha_pago', NEW.fecha_pago,
      'po_na', NEW.po_na, 'factura_na', NEW.factura_na, 'rfc_na', NEW.rfc_na, 'anticipo_na', NEW.anticipo_na,
      'finiquito_na', NEW.finiquito_na, 'complemento_na', NEW.complemento_na, 'forma_pago_nf', NEW.forma_pago_nf, 'ts', NEW.ts,
      'created_at', NEW.created_at,
      'hay_pdf_data', NEW.pdf_data is not null,
      'hay_pdf_fact_num', NEW.pdf_fact_num is not null,
      'hay_pdf_factura', NEW.pdf_factura is not null,
      'hay_pdf_rfc', NEW.pdf_rfc is not null,
      'hay_pdf_po', NEW.pdf_po is not null,
      'hay_pdf_anticipo', NEW.pdf_anticipo is not null,
      'hay_pdf_finiquito', NEW.pdf_finiquito is not null,
      'hay_pdf_complemento', NEW.pdf_complemento is not null,
      'pagos_extra', case when coalesce(pg_column_size(NEW.pagos_extra), 0) < 20000 then NEW.pagos_extra else jsonb_build_object('_omitido', true) end,
      'xml_cfdi', case when coalesce(pg_column_size(NEW.xml_cfdi), 0) < 20000 then NEW.xml_cfdi else jsonb_build_object('_omitido', true) end,
      'xml_complemento', case when coalesce(pg_column_size(NEW.xml_complemento), 0) < 20000 then NEW.xml_complemento else jsonb_build_object('_omitido', true) end);
  if antes = despues then
    return NULL;
  end if;
  insert into historial_cambios (tabla, ref, ref_id, datos)
  values ('facturas', OLD.pedido, OLD.id, antes);
  return NULL;
exception when others then
  raise warning 'facturas_guardar_historial: %', SQLERRM;
  return NULL;
end $$;

drop trigger if exists trg_facturas_historial on public.facturas;
create trigger trg_facturas_historial
  after update on public.facturas
  for each row execute function public.facturas_guardar_historial();

-- ── Verificación (correr después) ───────────────────────────────────────────
-- select tgname from pg_trigger where tgname in ('trg_orders_historial','trg_facturas_historial');
-- select tabla, count(*), pg_size_pretty(sum(pg_column_size(h.*))) from historial_cambios h group by 1;

-- ── Para quitarlo si algo sale mal ──────────────────────────────────────────
-- drop trigger if exists trg_orders_historial   on public.orders;
-- drop trigger if exists trg_facturas_historial on public.facturas;
