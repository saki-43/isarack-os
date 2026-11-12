-- Diseños guardados del Cotizador 3D (12 nov 2026)
-- "💾 Guardar avance" / "📂 Mis diseños". El equipo (sin token) ve los del equipo;
-- cada distribuidor (con su token de sesión) ve solo los suyos.
-- La tabla NO se lee directo con la llave pública: todo va por las funciones disenos_*
-- (SECURITY DEFINER), igual que los dist_*. Sin RLS (ver CLAUDE.md), sin permisos para anon.
create table if not exists public.disenos_guardados(
  id bigserial primary key,
  nombre text not null,
  autor text,
  distribuidor_id bigint references public.distribuidores(id) on delete cascade,
  sistema text,
  resumen text,
  estado text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists disenos_guardados_dist_idx on public.disenos_guardados(distribuidor_id, updated_at desc);
revoke all on public.disenos_guardados from anon, authenticated;
revoke all on sequence public.disenos_guardados_id_seq from anon, authenticated;

-- Dueño según el token: null = equipo ISARACK; token inválido o vencido = error.
create or replace function public._disenos_dueno(p_token uuid)
returns bigint language plpgsql stable security definer set search_path to 'public' as $$
declare v bigint;
begin
  if p_token is null then return null; end if;
  v := _dist_de_token(p_token);
  if v is null then raise exception 'Tu sesión venció. Vuelve a entrar.'; end if;
  return v;
end $$;

create or replace function public.disenos_listar(p_token uuid default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare d bigint := _disenos_dueno(p_token);
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'nombre',g.nombre,'autor',g.autor,
      'sistema',g.sistema,'resumen',g.resumen,'updated_at',g.updated_at) order by g.updated_at desc)
    from disenos_guardados g where g.distribuidor_id is not distinct from d), '[]'::jsonb);
end $$;

create or replace function public.disenos_abrir(p_token uuid, p_id bigint)
returns text language plpgsql stable security definer set search_path to 'public' as $$
declare d bigint := _disenos_dueno(p_token);
begin
  return (select g.estado from disenos_guardados g where g.id=p_id and g.distribuidor_id is not distinct from d);
end $$;

-- p_id null = nuevo; con id = sobreescribe (solo si es del mismo dueño).
create or replace function public.disenos_guardar(p_token uuid, p_id bigint, p_nombre text, p_autor text,
  p_sistema text, p_resumen text, p_estado text)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare d bigint := _disenos_dueno(p_token); v bigint;
begin
  if coalesce(trim(p_nombre),'')='' then raise exception 'Ponle nombre al diseño.'; end if;
  if coalesce(p_estado,'')='' or length(p_estado)>2000000 then raise exception 'Diseño vacío o demasiado grande.'; end if;
  if p_id is not null then
    update disenos_guardados set nombre=left(trim(p_nombre),120), autor=left(p_autor,80), sistema=left(p_sistema,40),
      resumen=left(p_resumen,300), estado=p_estado, updated_at=now()
    where id=p_id and distribuidor_id is not distinct from d returning id into v;
    if v is not null then return v; end if;
  end if;
  insert into disenos_guardados(nombre,autor,distribuidor_id,sistema,resumen,estado)
  values(left(trim(p_nombre),120),left(p_autor,80),d,left(p_sistema,40),left(p_resumen,300),p_estado) returning id into v;
  return v;
end $$;

create or replace function public.disenos_borrar(p_token uuid, p_id bigint)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare d bigint := _disenos_dueno(p_token);
begin
  delete from disenos_guardados where id=p_id and distribuidor_id is not distinct from d;
  return found;
end $$;

grant execute on function public.disenos_listar(uuid), public.disenos_abrir(uuid,bigint),
  public.disenos_guardar(uuid,bigint,text,text,text,text,text), public.disenos_borrar(uuid,bigint) to anon, authenticated;
revoke execute on function public._disenos_dueno(uuid) from anon, authenticated, public;
