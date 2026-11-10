-- 🤝 Distribuidores del Cotizador 3D (aplicado el 10 nov 2026 desde Claude Code).
-- Entran a isarack-web/configurador.html?dist=1 con usuario y contraseña.
-- La llave pública (anon) NO puede leer clave_hash, sesiones ni contactos: todo pasa
-- por funciones SECURITY DEFINER que validan el token de sesión.
-- RLS queda APAGADO a propósito (ver CLAUDE.md: RLS sin políticas = tabla vacía);
-- la protección es por permisos de columna/tabla.

create table public.distribuidores(
  id bigserial primary key, nombre text not null, usuario text not null, clave_hash text,
  descuento numeric not null default 0 check (descuento>=0 and descuento<=60),
  activo boolean not null default true, telefono text, email text, notas text,
  creado timestamptz not null default now(), updated_at timestamptz not null default now());
create unique index distribuidores_usuario_u on public.distribuidores (lower(usuario));
create table public.distribuidor_sesiones(
  token uuid primary key default gen_random_uuid(),
  distribuidor_id bigint not null references public.distribuidores(id) on delete cascade,
  creado timestamptz not null default now(), expira timestamptz not null default now()+interval '30 days',
  updated_at timestamptz not null default now());
create table public.distribuidor_contactos(
  id bigserial primary key, distribuidor_id bigint not null references public.distribuidores(id) on delete cascade,
  nombre text not null, razon text, rfc text, email text, tel text, dir text, contacto text, notas text,
  creado timestamptz not null default now(), updated_at timestamptz not null default now());
create index distribuidor_contactos_d on public.distribuidor_contactos(distribuidor_id);
alter table public.ventas add column if not exists distribuidor_id bigint;

revoke all on public.distribuidores, public.distribuidor_sesiones, public.distribuidor_contactos from anon, authenticated, public;
grant select (id,nombre,usuario,descuento,activo,telefono,email,notas,creado,updated_at) on public.distribuidores to anon, authenticated;
grant insert (nombre,usuario,descuento,activo,telefono,email,notas,updated_at) on public.distribuidores to anon, authenticated;
grant update (nombre,usuario,descuento,activo,telefono,email,notas,updated_at) on public.distribuidores to anon, authenticated;
grant usage on sequence public.distribuidores_id_seq to anon, authenticated;

-- Funciones: _dist_de_token (interna), dist_set_clave, dist_login, dist_yo, dist_salir,
-- dist_contactos, dist_contacto_guardar, dist_contacto_borrar, dist_cotizaciones.
-- Para ver su código: select pg_get_functiondef('public.dist_login(text,text)'::regprocedure);
