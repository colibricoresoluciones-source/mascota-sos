-- ============================================================
--  MASCOTA SOS — Setup Supabase
--  Plataforma publica (sin login) para reportar y buscar mascotas
--  perdidas/encontradas tras el terremoto en Colombia.
--  COMO USAR: crea un proyecto nuevo en supabase.com, entra al
--  SQL Editor, pega TODO este archivo y dale RUN.
-- ============================================================

-- ========== 1. TABLA PRINCIPAL ==========
create table if not exists public.reportes (
  id                uuid primary key default gen_random_uuid(),
  tipo              text not null check (tipo in ('perdido','encontrado')),
  especie           text not null default 'perro',        -- 'perro' | 'gato' | 'otro'
  nombre_mascota    text,                                   -- si se conoce (mascota perdida)
  raza              text,
  color             text,
  tamano            text,                                   -- 'pequeño' | 'mediano' | 'grande'
  descripcion       text,
  ciudad            text not null,
  sector            text,                                   -- barrio/zona/punto de referencia
  fecha_evento      date,
  foto_url          text,
  contacto_nombre   text not null,
  contacto_telefono text not null,
  contacto_email    text,
  estado            text not null default 'activo',         -- 'activo' | 'resuelto'
  codigo_edicion    text not null default substr(md5(random()::text),1,8),
  created_at        timestamptz default now()
);

create index if not exists reportes_ciudad_idx on public.reportes (ciudad);
create index if not exists reportes_tipo_idx on public.reportes (tipo);
create index if not exists reportes_estado_idx on public.reportes (estado);

-- ========== 2. ROW LEVEL SECURITY ==========
-- A proposito NO se crea NINGUNA policy sobre esta tabla (ni select, ni
-- insert, ni update). Con RLS activado y cero policies, nadie puede tocar
-- la tabla directamente -- todo el acceso publico pasa por la vista
-- reportes_publico (lectura) y por funciones SECURITY DEFINER (escritura),
-- que son las unicas formas de leer/crear/editar reportes. Asi el
-- codigo_edicion nunca queda expuesto ni siquiera por error de configuracion.
alter table public.reportes enable row level security;

-- ========== 3. VISTA PUBLICA (sin el codigo_edicion) ==========
create or replace view public.reportes_publico as
  select id, tipo, especie, nombre_mascota, raza, color, tamano, descripcion,
         ciudad, sector, fecha_evento, foto_url, contacto_nombre,
         contacto_telefono, contacto_email, estado, created_at
  from public.reportes;

-- ========== 4. GRANTS (necesarios ademas de las policies de RLS) ==========
grant usage on schema public to anon, authenticated;
grant select on public.reportes_publico to anon, authenticated;
-- Notese que NO se otorga ningun privilegio sobre public.reportes en si
-- (ni select ni insert) -- todo pasa por las funciones de abajo.

-- ========== 5. FUNCION: crear reporte (devuelve el codigo secreto) ==========
create or replace function public.crear_reporte(
  p_tipo text, p_especie text, p_nombre_mascota text, p_raza text, p_color text,
  p_tamano text, p_descripcion text, p_ciudad text, p_sector text,
  p_fecha_evento date, p_foto_url text, p_contacto_nombre text,
  p_contacto_telefono text, p_contacto_email text
)
returns table(id uuid, codigo_edicion text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  insert into public.reportes (
    tipo, especie, nombre_mascota, raza, color, tamano, descripcion,
    ciudad, sector, fecha_evento, foto_url, contacto_nombre,
    contacto_telefono, contacto_email
  ) values (
    p_tipo, p_especie, p_nombre_mascota, p_raza, p_color, p_tamano, p_descripcion,
    p_ciudad, p_sector, p_fecha_evento, p_foto_url, p_contacto_nombre,
    p_contacto_telefono, p_contacto_email
  )
  returning reportes.id, reportes.codigo_edicion;
end;
$$;

grant execute on function public.crear_reporte(
  text, text, text, text, text, text, text, text, text, date, text, text, text, text
) to anon, authenticated;

-- ========== 6. FUNCION: marcar como resuelto (requiere el codigo) ==========
create or replace function public.marcar_resuelto(p_id uuid, p_codigo text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  filas int;
begin
  update public.reportes set estado = 'resuelto'
  where id = p_id and codigo_edicion = p_codigo;
  get diagnostics filas = row_count;
  return filas > 0;
end;
$$;

grant execute on function public.marcar_resuelto(uuid, text) to anon, authenticated;

-- ========== 6b. FUNCION: eliminar el propio reporte (requiere el codigo) ==========
create or replace function public.eliminar_reporte(p_id uuid, p_codigo text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  filas int;
begin
  delete from public.reportes where id = p_id and codigo_edicion = p_codigo;
  get diagnostics filas = row_count;
  return filas > 0;
end;
$$;

grant execute on function public.eliminar_reporte(uuid, text) to anon, authenticated;

-- ========== 6c. FUNCION: marcar como encontrado, PUBLICA (sin codigo) ==========
-- A diferencia de marcar_resuelto (que exige el codigo secreto del dueño),
-- esta funcion la puede usar CUALQUIERA que vea el reporte -- pensada para
-- que la comunidad marque cuando ve que una mascota ya aparecio, aunque no
-- sea la persona que hizo el reporte original.
create or replace function public.marcar_encontrado_publico(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  filas int;
begin
  update public.reportes set estado = 'resuelto' where id = p_id and estado <> 'resuelto';
  get diagnostics filas = row_count;
  return filas > 0;
end;
$$;

grant execute on function public.marcar_encontrado_publico(uuid) to anon, authenticated;

-- ========== 6d. TABLA DE COMENTARIOS (publicos, tipo redes sociales) ==========
create table if not exists public.comentarios (
  id            uuid primary key default gen_random_uuid(),
  reporte_id    uuid not null references public.reportes(id) on delete cascade,
  autor_nombre  text not null,
  texto         text not null,
  created_at    timestamptz default now()
);

create index if not exists comentarios_reporte_idx on public.comentarios (reporte_id);

alter table public.comentarios enable row level security;

-- Los comentarios no tienen ningun dato sensible (a diferencia de reportes,
-- que tiene el codigo_edicion), asi que aqui SI se permite select/insert
-- directo sobre la tabla, sin necesidad de vista ni funciones intermedias.
create policy comentarios_select on public.comentarios for select
  to anon, authenticated using (true);

create policy comentarios_insert on public.comentarios for insert
  to anon, authenticated with check (
    char_length(trim(texto)) > 0 and char_length(texto) <= 500
    and char_length(trim(autor_nombre)) > 0 and char_length(autor_nombre) <= 80
  );

grant select, insert on public.comentarios to anon, authenticated;

-- ========== 7. STORAGE (fotos) ==========
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do nothing;

create policy fotos_select on storage.objects for select
  to anon, authenticated using (bucket_id = 'fotos');

create policy fotos_insert on storage.objects for insert
  to anon, authenticated with check (bucket_id = 'fotos');
