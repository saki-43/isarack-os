-- Aplicado el 19 oct 2026 (ISA-OS v2026.10.19.07).
-- Pedidos ligeros: ISA-OS baja la vista sin el base64 de los archivos y sin cotHTML
-- cuando hay cotData. Medido: 5.7 MB / 0.70 s (tabla) → 0.6 MB / 0.14 s (vista).

create or replace function public._orden_ligera(p jsonb) returns jsonb
language sql immutable as $$
  select (
    coalesce(p,'{}'::jsonb) || coalesce((
      select jsonb_object_agg(k, (
        select coalesce(jsonb_agg(
          case
            when jsonb_typeof(e)='object' and left(coalesce(e->>'data',''),5)='data:' then (e - 'data') || '{"data":"","_enNube":true}'::jsonb
            when jsonb_typeof(e)='string' and left(e #>> '{}',5)='data:' then '{"_enNube":true}'::jsonb
            else e end order by o), '[]'::jsonb)
        from jsonb_array_elements(p->k) with ordinality t(e,o)))
      from unnest(array['pdfsPresupuesto','pdfsRecepcion','planos','fotosAvance','fotosTerminacion','fotosEntrega','firmaEntrega','fotosSurtido']) k
      where jsonb_typeof(p->k)='array'
    ), '{}'::jsonb)
  ) - (case when jsonb_typeof(p->'cotData')='object' and p ? 'cotHTML' then 'cotHTML' else '__nada__' end);
$$;

create or replace view public.orders_ligeras as
select id, num, cliente, fecha, estado, items, notas, created_at, updated_at,
       public._orden_ligera(payload) as payload,
       ejecutivo, instalador, estatus, whatsapp, ubicacion, total, moneda, po, repse, razon, rfc, planos
from public.orders;
grant select on public.orders_ligeras to anon, authenticated;

-- proteger_pedido v5: al inicio, ANTES de revisar _permitirQuitar, cada cascaron
-- ({_enNube:true, data:'' sin url/path}) que llega se cambia por el archivo real de la
-- version anterior (mismo nombre con data/url/path, o misma posicion si no trae nombre),
-- y si no viene cotHTML pero existia, se conserva. Ver la funcion en la base:
--   select pg_get_functiondef('public.proteger_pedido'::regproc);
