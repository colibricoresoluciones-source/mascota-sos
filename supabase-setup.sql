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

-- ========== 7. STORAGE (fotos) ==========
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do nothing;

create policy fotos_select on storage.objects for select
  to anon, authenticated using (bucket_id = 'fotos');

create policy fotos_insert on storage.objects for insert
  to anon, authenticated with check (bucket_id = 'fotos');
