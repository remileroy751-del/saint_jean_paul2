-- ============================================================================
-- COMPLEXE SCOLAIRE SAINT JEAN PAUL II — SYSTÈME DE SUIVI DE SCOLARITÉ
-- SCHÉMA SUPABASE COMPLET (installation / réinstallation)
-- ============================================================================
-- À exécuter intégralement dans Supabase > SQL Editor > New query > Run.
--
-- ATTENTION : ce script REMPLACE les tables de l'application (classes, parents,
-- élèves, enseignants, notes, messages, cantine, frais…). Si vous l'exécutez
-- sur le projet de l'ancienne version « CONNECT TEST », les anciennes données
-- de test sont supprimées. Le compte Direction (table admin_users) est conservé.
--
-- Nouveautés par rapport à CONNECT TEST :
--   * 2 niveaux : Primaire (CI1…CM2) et Collège (6ième…3ième), avec leurs matières
--   * Primaire : un seul enseignant par classe (toutes les matières) ; Collège : plusieurs
--   * un élève ne peut exister que rattaché à un parent (Père, Mère, Tante,
--     Oncle, Tuteur) : la base refuse tout élève sans parent
--   * personnel de cantine (code à 6 caractères), menu du jour, 2 photos,
--     effacement automatique chaque dimanche à 00h GMT
--   * frais de scolarité : montant par classe, jusqu'à 15 tranches par élève,
--     rapport avancé pour la Direction, suivi côté parent
--   * messages Direction : niveau, classe, un parent précis, enseignants, cantine
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ============================================================
-- 1. NETTOYAGE (anciennes versions)
-- ============================================================

drop table if exists public.canteen_photos cascade;
drop table if exists public.canteen_menus cascade;
drop table if exists public.canteen_staff cascade;
drop table if exists public.fee_payments cascade;
drop table if exists public.class_fees cascade;
drop table if exists public.access_code_records cascade;
drop table if exists public.admin_security_settings cascade;
drop table if exists public.announcement_reads cascade;
drop table if exists public.announcement_receipts cascade;
drop table if exists public.messages cascade;
drop table if exists public.conversations cascade;
drop table if exists public.announcements cascade;
drop table if exists public.notes cascade;
drop table if exists public.teacher_assignments cascade;
drop table if exists public.student_parents cascade;
drop table if exists public.students cascade;
drop table if exists public.teachers cascade;
drop table if exists public.parents cascade;
drop table if exists public.subject_levels cascade;
drop table if exists public.subjects cascade;
drop table if exists public.classes cascade;

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prokind = 'f'
      and p.proname in (
        'acknowledge_announcement', 'admin_access_codes', 'admin_add_child_to_parent',
        'admin_add_payment', 'admin_add_subject', 'admin_assign_primary_teacher', 'admin_assign_teacher',
        'admin_delete_subject', 'trg_primary_single_teacher', 'admin_create_announcement',
        'admin_create_canteen_staff', 'admin_create_class', 'admin_create_parent',
        'admin_create_parent_with_children', 'admin_create_student',
        'admin_create_student_for_parent', 'admin_create_teacher',
        'admin_delete_announcements', 'admin_delete_parent', 'admin_fee_report',
        'admin_link_student_to_parent', 'admin_reset_canteen_code',
        'admin_reset_parent_code', 'admin_reset_teacher_code', 'admin_set_class_fee',
        'admin_update_parent', 'admin_update_payment',
        'admin_update_teacher_assignment', 'bootstrap_admin', 'canteen_add_photo',
        'canteen_announcements', 'canteen_menu_dates', 'canteen_menu_for_date',
        'canteen_save_menu', 'canteen_today', 'canteen_viewer_ok',
        'conversation_messages', 'hash_code', 'is_admin', 'login_with_access_code',
        'make_code', 'mark_announcements_read', 'mobile_notifications',
        'mobile_server_time', 'parent_child_teachers', 'parent_children', 'parent_fees',
        'purge_canteen_week', 'send_parent_message', 'student_announcements',
        'student_notes', 'teacher_announcements', 'teacher_class_statistics',
        'teacher_classes', 'teacher_conversation_messages', 'teacher_conversations',
        'teacher_save_note', 'teacher_send_parent_message', 'teacher_student_notes',
        'teacher_student_rankings', 'teacher_students', 'trg_student_requires_parent'
      )
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

-- ============================================================
-- 2. TABLES
-- ============================================================

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text not null unique,
  level text not null check (level in ('primaire','college')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.parents (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  parent_type text not null default 'Tuteur'
    check (parent_type in ('Père','Mère','Tante','Oncle','Tuteur')),
  registered_level text not null default 'college'
    check (registered_level in ('primaire','college')),
  access_code_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  registered_level text not null default 'college'
    check (registered_level in ('primaire','college')),
  access_code_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.canteen_staff (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  access_code_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  class_id uuid not null references public.classes(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.student_parents (
  student_id uuid not null references public.students(id) on delete cascade,
  parent_id uuid not null references public.parents(id) on delete cascade,
  relationship text,
  primary key (student_id, parent_id)
);

create table public.teacher_assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  is_homeroom boolean not null default false,
  created_at timestamptz not null default now(),
  unique (teacher_id, class_id, subject_id)
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  teacher_assignment_id uuid not null references public.teacher_assignments(id) on delete cascade,
  term text not null check (term in ('1er trimestre','2e trimestre','3e trimestre')),
  note_type text not null check (note_type in ('devoir','moyenne_classe','composition')),
  value numeric(5,2) not null check (value >= 0 and value <= 20),
  title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  importance text not null check (importance in ('urgent','pas_urgent')),
  target_type text not null check (target_type in (
    'all_parents','level_parents','class_parents','student',
    'all_teachers','teacher','all_canteen'
  )),
  level text check (level in ('primaire','college')),
  class_id uuid references public.classes(id) on delete cascade,
  student_id uuid references public.students(id) on delete cascade,
  teacher_id uuid references public.teachers(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint announcements_target_check check (
    (target_type = 'all_parents')
    or (target_type = 'level_parents' and level is not null)
    or (target_type = 'class_parents' and class_id is not null)
    or (target_type = 'student' and student_id is not null)
    or (target_type = 'all_teachers')
    or (target_type = 'teacher' and teacher_id is not null)
    or (target_type = 'all_canteen')
  )
);

create table public.announcement_reads (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  parent_id uuid not null references public.parents(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, parent_id, student_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.parents(id) on delete cascade,
  teacher_id uuid not null references public.teachers(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (parent_id, teacher_id, student_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_role text not null check (sender_role in ('parent','teacher')),
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz not null default now()
);

-- Registre administratif des codes d'accès (consultable uniquement par la Direction)
create table public.access_code_records (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('parent','teacher','canteen')),
  parent_id uuid references public.parents(id) on delete cascade,
  teacher_id uuid references public.teachers(id) on delete cascade,
  canteen_id uuid references public.canteen_staff(id) on delete cascade,
  full_name text not null,
  phone text,
  access_code text not null,
  generated_at timestamptz not null default now(),
  is_current boolean not null default true,
  constraint access_code_records_owner_check check (
    (role = 'parent' and parent_id is not null and teacher_id is null and canteen_id is null)
    or (role = 'teacher' and teacher_id is not null and parent_id is null and canteen_id is null)
    or (role = 'canteen' and canteen_id is not null and parent_id is null and teacher_id is null)
  )
);

-- Cantine : un menu par jour, 2 photos maximum par menu
create table public.canteen_menus (
  id uuid primary key default gen_random_uuid(),
  menu_date date not null unique,
  dish_name text not null,
  description text,
  created_by uuid references public.canteen_staff(id) on delete set null,
  created_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.canteen_photos (
  id uuid primary key default gen_random_uuid(),
  menu_id uuid not null references public.canteen_menus(id) on delete cascade,
  slot smallint not null check (slot in (1,2)),
  image_base64 text not null,
  added_by uuid references public.canteen_staff(id) on delete set null,
  added_by_name text,
  created_at timestamptz not null default now(),
  unique (menu_id, slot)
);

-- Frais de scolarité : montant total par classe + tranches payées par élève
create table public.class_fees (
  class_id uuid primary key references public.classes(id) on delete cascade,
  total_amount numeric(12,0) not null default 0 check (total_amount >= 0),
  updated_at timestamptz not null default now()
);

create table public.fee_payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  installment_no smallint not null check (installment_no between 1 and 15),
  amount numeric(12,0) not null check (amount > 0),
  paid_at date not null default ((now() at time zone 'utc')::date),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, installment_no)
);

-- ============================================================
-- 3. INDEX
-- ============================================================

create index idx_students_class on public.students(class_id);
create index idx_student_parents_parent on public.student_parents(parent_id);
create index idx_teacher_assignments_teacher on public.teacher_assignments(teacher_id);
create index idx_teacher_assignments_class on public.teacher_assignments(class_id);
create index idx_notes_student_term on public.notes(student_id, term);
create index idx_notes_assignment_term on public.notes(teacher_assignment_id, term);
create index idx_announcements_created on public.announcements(created_at desc);
create index idx_announcement_reads_parent_student on public.announcement_reads(parent_id, student_id);
create index idx_conversations_parent on public.conversations(parent_id);
create index idx_conversations_teacher on public.conversations(teacher_id);
create index idx_messages_conversation on public.messages(conversation_id, created_at);
create index idx_messages_created on public.messages(created_at);
create index idx_fee_payments_student on public.fee_payments(student_id);
create index idx_canteen_photos_menu on public.canteen_photos(menu_id);
create index idx_access_code_records_role on public.access_code_records(role);

create unique index uq_notes_class_average
  on public.notes(student_id, teacher_assignment_id, term)
  where note_type = 'moyenne_classe';

create unique index uq_notes_composition
  on public.notes(student_id, teacher_assignment_id, term)
  where note_type = 'composition';

create unique index ux_access_code_records_parent_current
  on public.access_code_records(parent_id) where is_current and parent_id is not null;
create unique index ux_access_code_records_teacher_current
  on public.access_code_records(teacher_id) where is_current and teacher_id is not null;
create unique index ux_access_code_records_canteen_current
  on public.access_code_records(canteen_id) where is_current and canteen_id is not null;

-- ============================================================
-- 4. DONNÉES DE BASE : CLASSES ET MATIÈRES
-- ============================================================

insert into public.classes (name, code, level, sort_order) values
  ('CI1', 'CI1', 'primaire', 1),
  ('CI2', 'CI2', 'primaire', 2),
  ('CP1', 'CP1', 'primaire', 3),
  ('CP2', 'CP2', 'primaire', 4),
  ('CE1', 'CE1', 'primaire', 5),
  ('CE2', 'CE2', 'primaire', 6),
  ('CM1', 'CM1', 'primaire', 7),
  ('CM2', 'CM2', 'primaire', 8),
  ('6ième', '6E', 'college', 11),
  ('5ième', '5E', 'college', 12),
  ('4ième', '4E', 'college', 13),
  ('3ième', '3E', 'college', 14);

insert into public.class_fees (class_id, total_amount)
select id, 0 from public.classes;

insert into public.subjects (name) values
  ('Français'),
  ('Anglais'),
  ('Mathématiques'),
  ('Sciences Physiques'),
  ('SVT'),
  ('Histoire-Géographie'),
  ('Informatique'),
  ('EPS'),
  ('Technologie'),
  ('Éducation Civique'),
  ('Lecture'),
  ('Écriture'),
  ('Dictée'),
  ('Calcul'),
  ('Éveil scientifique');

-- ============================================================
-- 5. OUTILS : CODES D'ACCÈS, ADMIN
-- ============================================================

create or replace function public.make_code(p_length integer)
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i integer;
begin
  if p_length is null or p_length < 1 then
    raise exception 'La longueur du code doit être supérieure à 0';
  end if;
  for i in 1..p_length loop
    result := result || substr(alphabet, floor(random() * length(alphabet) + 1)::integer, 1);
  end loop;
  return result;
end;
$$;

create or replace function public.hash_code(p_code text)
returns text
language sql
immutable
strict
set search_path = public, extensions
as $$
  select encode(
    extensions.digest(convert_to(upper(trim(p_code)), 'UTF8'), 'sha256'::text),
    'hex'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;

-- Un élève ne peut JAMAIS exister sans parent : contrôle à la fin de la transaction.
create or replace function public.trg_student_requires_parent()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.student_parents where student_id = new.id) then
    raise exception 'Un élève ne peut pas être enregistré sans parent. Créez d''abord le parent.';
  end if;
  return null;
end;
$$;

create constraint trigger student_requires_parent
  after insert on public.students
  deferrable initially deferred
  for each row execute function public.trg_student_requires_parent();

-- ============================================================
-- 6. SÉCURITÉ (RLS) : seule la Direction accède directement aux tables
-- ============================================================

alter table public.classes enable row level security;
alter table public.subjects enable row level security;
alter table public.parents enable row level security;
alter table public.teachers enable row level security;
alter table public.canteen_staff enable row level security;
alter table public.students enable row level security;
alter table public.student_parents enable row level security;
alter table public.teacher_assignments enable row level security;
alter table public.notes enable row level security;
alter table public.announcements enable row level security;
alter table public.announcement_reads enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.admin_users enable row level security;
alter table public.access_code_records enable row level security;
alter table public.canteen_menus enable row level security;
alter table public.canteen_photos enable row level security;
alter table public.class_fees enable row level security;
alter table public.fee_payments enable row level security;

create policy admin_all_classes on public.classes for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_subjects on public.subjects for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_parents on public.parents for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_teachers on public.teachers for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_canteen_staff on public.canteen_staff for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Élèves : lecture, modification et suppression seulement. AUCUN ajout direct :
-- les élèves sont créés uniquement par les fonctions « parent + enfants ».
create policy admin_select_students on public.students for select to authenticated
  using (public.is_admin());
create policy admin_update_students on public.students for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_delete_students on public.students for delete to authenticated
  using (public.is_admin());

create policy admin_all_student_parents on public.student_parents for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_assignments on public.teacher_assignments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_notes on public.notes for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_announcements on public.announcements for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_reads on public.announcement_reads for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_conversations on public.conversations for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_messages on public.messages for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_canteen_menus on public.canteen_menus for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_canteen_photos on public.canteen_photos for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_class_fees on public.class_fees for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_all_fee_payments on public.fee_payments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy access_code_records_no_direct_access on public.access_code_records
  for all to anon, authenticated using (false) with check (false);

drop policy if exists admin_self on public.admin_users;
create policy admin_self on public.admin_users
  for select to authenticated using (user_id = auth.uid());

revoke all on all tables in schema public from anon;

-- ============================================================
-- 7. DIRECTION : COMPTE ADMIN
-- ============================================================

create or replace function public.bootstrap_admin(p_email text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  mail text := coalesce(nullif(trim(p_email), ''), '');
begin
  if uid is null then
    raise exception 'Vous devez être connecté avec un compte Supabase Auth.';
  end if;

  if exists (select 1 from public.admin_users)
     and not exists (select 1 from public.admin_users where user_id = uid) then
    raise exception 'Ce compte Supabase n''est pas autorisé comme compte Direction.';
  end if;

  insert into public.admin_users(user_id, email)
  values (uid, nullif(mail, ''))
  on conflict (user_id) do update
    set email = coalesce(excluded.email, public.admin_users.email);

  return jsonb_build_object('success', true, 'message', 'Compte Direction activé.');
end;
$$;

-- ============================================================
-- 8. DIRECTION : PARENTS ET ENFANTS (le parent d'abord, toujours)
-- ============================================================

-- Crée le parent (avec son type) ET ses enfants inscrits en une seule opération.
-- p_children = [{"name":"Kofi Mensah","class_id":"<uuid>"}, ...]  (au moins 1 enfant)
create or replace function public.admin_create_parent_with_children(
  p_full_name text,
  p_phone text,
  p_parent_type text,
  p_level text,
  p_children jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_parent_id uuid;
  v_code text;
  v_phone text := nullif(trim(p_phone), '');
  v_name text := trim(p_full_name);
  v_child jsonb;
  v_student_id uuid;
  v_class_level text;
  v_ids uuid[] := '{}';
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(v_name, '') is null then raise exception 'Nom du parent obligatoire.'; end if;
  if p_parent_type is null or p_parent_type not in ('Père','Mère','Tante','Oncle','Tuteur') then
    raise exception 'Type de parent invalide (Père, Mère, Tante, Oncle ou Tuteur).';
  end if;
  if p_level is null or p_level not in ('primaire','college') then
    raise exception 'Niveau invalide.';
  end if;
  if p_children is null or jsonb_typeof(p_children) <> 'array' or jsonb_array_length(p_children) = 0 then
    raise exception 'Ajoutez au moins un enfant : un parent est enregistré avec ses enfants inscrits.';
  end if;

  loop
    v_code := public.make_code(4);
    exit when not exists (
      select 1 from public.parents where access_code_hash = public.hash_code(v_code)
    );
  end loop;

  insert into public.parents(full_name, phone, parent_type, registered_level, access_code_hash)
  values (v_name, v_phone, p_parent_type, p_level, public.hash_code(v_code))
  returning id into v_parent_id;

  insert into public.access_code_records(role, parent_id, full_name, phone, access_code)
  values ('parent', v_parent_id, v_name, v_phone, v_code);

  for v_child in select * from jsonb_array_elements(p_children)
  loop
    if nullif(trim(v_child ->> 'name'), '') is null then
      raise exception 'Le nom de chaque enfant est obligatoire.';
    end if;
    select c.level into v_class_level
    from public.classes c
    where c.id = nullif(v_child ->> 'class_id', '')::uuid;
    if v_class_level is null then
      raise exception 'Classe introuvable pour l''enfant %.', trim(v_child ->> 'name');
    end if;
    if v_class_level <> p_level then
      raise exception 'La classe de % n''appartient pas au niveau sélectionné.', trim(v_child ->> 'name');
    end if;

    insert into public.students(full_name, class_id)
    values (trim(v_child ->> 'name'), (v_child ->> 'class_id')::uuid)
    returning id into v_student_id;

    insert into public.student_parents(student_id, parent_id, relationship)
    values (v_student_id, v_parent_id, p_parent_type);

    v_ids := v_ids || v_student_id;
  end loop;

  return jsonb_build_object(
    'success', true,
    'parent_id', v_parent_id,
    'parent_code', v_code,
    'student_ids', to_jsonb(v_ids)
  );
end;
$$;

-- Ajoute un enfant supplémentaire à un parent déjà enregistré.
create or replace function public.admin_add_child_to_parent(
  p_parent_id uuid,
  p_student_full_name text,
  p_class_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
  v_student_id uuid;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(trim(p_student_full_name), '') is null then raise exception 'Nom de l''élève obligatoire.'; end if;

  select parent_type into v_type from public.parents where id = p_parent_id;
  if v_type is null then raise exception 'Parent introuvable.'; end if;
  if not exists (select 1 from public.classes where id = p_class_id) then
    raise exception 'Classe introuvable.';
  end if;

  insert into public.students(full_name, class_id)
  values (trim(p_student_full_name), p_class_id)
  returning id into v_student_id;

  insert into public.student_parents(student_id, parent_id, relationship)
  values (v_student_id, p_parent_id, v_type);

  return jsonb_build_object('success', true, 'student_id', v_student_id, 'parent_id', p_parent_id);
end;
$$;

create or replace function public.admin_update_parent(
  p_parent_id uuid,
  p_full_name text,
  p_phone text,
  p_parent_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(trim(p_full_name), '') is null then raise exception 'Nom du parent obligatoire.'; end if;
  if p_parent_type is null or p_parent_type not in ('Père','Mère','Tante','Oncle','Tuteur') then
    raise exception 'Type de parent invalide.';
  end if;

  update public.parents
  set full_name = trim(p_full_name),
      phone = nullif(trim(p_phone), ''),
      parent_type = p_parent_type,
      updated_at = now()
  where id = p_parent_id;

  if not found then raise exception 'Parent introuvable.'; end if;

  update public.student_parents set relationship = p_parent_type where parent_id = p_parent_id;
  update public.access_code_records
  set full_name = trim(p_full_name), phone = nullif(trim(p_phone), '')
  where parent_id = p_parent_id;

  return jsonb_build_object('success', true);
end;
$$;

-- Supprime un parent ainsi que les enfants qui n'ont aucun autre parent
-- (un élève ne reste jamais sans parent).
create or replace function public.admin_delete_parent(p_parent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_students integer := 0;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.parents where id = p_parent_id) then
    raise exception 'Parent introuvable.';
  end if;

  delete from public.students s
  where s.id in (select sp.student_id from public.student_parents sp where sp.parent_id = p_parent_id)
    and not exists (
      select 1 from public.student_parents o
      where o.student_id = s.id and o.parent_id <> p_parent_id
    );
  get diagnostics v_deleted_students = row_count;

  delete from public.parents where id = p_parent_id;

  return jsonb_build_object('success', true, 'deleted_students', v_deleted_students);
end;
$$;

-- ============================================================
-- 9. DIRECTION : ENSEIGNANTS ET PERSONNEL DE CANTINE
-- ============================================================

create or replace function public.admin_create_teacher(
  p_full_name text,
  p_phone text default null,
  p_level text default 'college'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_teacher_id uuid;
  v_code text;
  v_phone text := nullif(trim(p_phone), '');
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(trim(p_full_name), '') is null then raise exception 'Nom de l''enseignant obligatoire.'; end if;
  if p_level is null or p_level not in ('primaire','college') then raise exception 'Niveau invalide.'; end if;

  loop
    v_code := public.make_code(5);
    exit when not exists (select 1 from public.teachers where access_code_hash = public.hash_code(v_code));
  end loop;

  insert into public.teachers(full_name, phone, registered_level, access_code_hash)
  values (trim(p_full_name), v_phone, p_level, public.hash_code(v_code))
  returning id into v_teacher_id;

  insert into public.access_code_records(role, teacher_id, full_name, phone, access_code)
  values ('teacher', v_teacher_id, trim(p_full_name), v_phone, v_code);

  return jsonb_build_object('success', true, 'teacher_id', v_teacher_id, 'teacher_code', v_code);
end;
$$;

-- Personnel de cantine : code généré automatiquement (6 caractères).
create or replace function public.admin_create_canteen_staff(
  p_full_name text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_code text;
  v_phone text := nullif(trim(p_phone), '');
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(trim(p_full_name), '') is null then raise exception 'Nom de la personne obligatoire.'; end if;

  loop
    v_code := public.make_code(6);
    exit when not exists (select 1 from public.canteen_staff where access_code_hash = public.hash_code(v_code));
  end loop;

  insert into public.canteen_staff(full_name, phone, access_code_hash)
  values (trim(p_full_name), v_phone, public.hash_code(v_code))
  returning id into v_id;

  insert into public.access_code_records(role, canteen_id, full_name, phone, access_code)
  values ('canteen', v_id, trim(p_full_name), v_phone, v_code);

  return jsonb_build_object('success', true, 'canteen_id', v_id, 'canteen_code', v_code);
end;
$$;

create or replace function public.admin_reset_parent_code(p_parent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
  v_name text;
  v_phone text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  select full_name, phone into v_name, v_phone from public.parents where id = p_parent_id;
  if v_name is null then raise exception 'Parent introuvable.'; end if;

  loop
    v_code := public.make_code(4);
    exit when not exists (select 1 from public.parents where access_code_hash = public.hash_code(v_code));
  end loop;

  update public.access_code_records set is_current = false where parent_id = p_parent_id and is_current;
  update public.parents set access_code_hash = public.hash_code(v_code), updated_at = now() where id = p_parent_id;
  insert into public.access_code_records(role, parent_id, full_name, phone, access_code)
  values ('parent', p_parent_id, v_name, v_phone, v_code);

  return jsonb_build_object('success', true, 'parent_id', p_parent_id, 'parent_code', v_code);
end;
$$;

create or replace function public.admin_reset_teacher_code(p_teacher_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
  v_name text;
  v_phone text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  select full_name, phone into v_name, v_phone from public.teachers where id = p_teacher_id;
  if v_name is null then raise exception 'Enseignant introuvable.'; end if;

  loop
    v_code := public.make_code(5);
    exit when not exists (select 1 from public.teachers where access_code_hash = public.hash_code(v_code));
  end loop;

  update public.access_code_records set is_current = false where teacher_id = p_teacher_id and is_current;
  update public.teachers set access_code_hash = public.hash_code(v_code), updated_at = now() where id = p_teacher_id;
  insert into public.access_code_records(role, teacher_id, full_name, phone, access_code)
  values ('teacher', p_teacher_id, v_name, v_phone, v_code);

  return jsonb_build_object('success', true, 'teacher_id', p_teacher_id, 'teacher_code', v_code);
end;
$$;

create or replace function public.admin_reset_canteen_code(p_canteen_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_code text;
  v_name text;
  v_phone text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  select full_name, phone into v_name, v_phone from public.canteen_staff where id = p_canteen_id;
  if v_name is null then raise exception 'Personne de la cantine introuvable.'; end if;

  loop
    v_code := public.make_code(6);
    exit when not exists (select 1 from public.canteen_staff where access_code_hash = public.hash_code(v_code));
  end loop;

  update public.access_code_records set is_current = false where canteen_id = p_canteen_id and is_current;
  update public.canteen_staff set access_code_hash = public.hash_code(v_code), updated_at = now() where id = p_canteen_id;
  insert into public.access_code_records(role, canteen_id, full_name, phone, access_code)
  values ('canteen', p_canteen_id, v_name, v_phone, v_code);

  return jsonb_build_object('success', true, 'canteen_id', p_canteen_id, 'canteen_code', v_code);
end;
$$;

create or replace function public.admin_access_codes()
returns table (
  id uuid,
  role text,
  parent_id uuid,
  teacher_id uuid,
  canteen_id uuid,
  full_name text,
  phone text,
  access_code text,
  generated_at timestamptz,
  is_current boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;

  return query
  select r.id, r.role, r.parent_id, r.teacher_id, r.canteen_id, r.full_name, r.phone,
         r.access_code, r.generated_at, r.is_current
  from public.access_code_records r
  order by r.role, r.is_current desc, r.full_name, r.generated_at desc;
end;
$$;

-- ============================================================
-- 10. DIRECTION : AFFECTATIONS DES ENSEIGNANTS
-- ============================================================

create or replace function public.admin_assign_teacher(
  p_teacher_id uuid,
  p_class_id uuid,
  p_subject_id uuid,
  p_is_homeroom boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment_id uuid;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.teachers where id = p_teacher_id) then raise exception 'Enseignant introuvable.'; end if;
  if not exists (select 1 from public.classes where id = p_class_id) then raise exception 'Classe introuvable.'; end if;
  if not exists (select 1 from public.subjects where id = p_subject_id) then raise exception 'Matière introuvable.'; end if;

  if p_is_homeroom then
    update public.teacher_assignments set is_homeroom = false where class_id = p_class_id;
  end if;

  insert into public.teacher_assignments(teacher_id, class_id, subject_id, is_homeroom)
  values (p_teacher_id, p_class_id, p_subject_id, p_is_homeroom)
  on conflict (teacher_id, class_id, subject_id)
  do update set is_homeroom = excluded.is_homeroom
  returning id into v_assignment_id;

  return jsonb_build_object('success', true, 'assignment_id', v_assignment_id);
end;
$$;

create or replace function public.admin_update_teacher_assignment(
  p_assignment_id uuid,
  p_teacher_id uuid,
  p_class_id uuid,
  p_subject_id uuid,
  p_is_homeroom boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.teacher_assignments where id = p_assignment_id) then raise exception 'Affectation introuvable.'; end if;
  if not exists (select 1 from public.teachers where id = p_teacher_id) then raise exception 'Enseignant introuvable.'; end if;
  if not exists (select 1 from public.classes where id = p_class_id) then raise exception 'Classe introuvable.'; end if;
  if not exists (select 1 from public.subjects where id = p_subject_id) then raise exception 'Matière introuvable.'; end if;

  if p_is_homeroom then
    update public.teacher_assignments set is_homeroom = false where class_id = p_class_id and id <> p_assignment_id;
  end if;

  update public.teacher_assignments
  set teacher_id = p_teacher_id, class_id = p_class_id, subject_id = p_subject_id, is_homeroom = p_is_homeroom
  where id = p_assignment_id
  returning id into v_id;

  return jsonb_build_object('success', true, 'assignment_id', v_id);
exception
  when unique_violation then
    raise exception 'Cette affectation existe déjà pour cet enseignant, cette classe et cette matière.';
end;
$$;

-- ============================================================
-- 11. DIRECTION : MESSAGES (communiqués)
-- ============================================================
-- Destinataires :
--   level_parents  : tous les parents d'un niveau (primaire ou collège)
--   all_parents    : tous les parents de l'école
--   class_parents  : les parents d'une classe
--   student        : le(s) parent(s) d'un élève précis
--   all_teachers / teacher : tous les enseignants / un enseignant
--   all_canteen    : tout le personnel de la cantine (un seul clic)

create or replace function public.admin_create_announcement(
  p_title text,
  p_body text,
  p_importance text,
  p_target_type text,
  p_level text default null,
  p_class_id uuid default null,
  p_student_id uuid default null,
  p_teacher_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if nullif(trim(p_title), '') is null then raise exception 'Titre obligatoire.'; end if;
  if nullif(trim(p_body), '') is null then raise exception 'Message obligatoire.'; end if;
  if p_importance not in ('urgent','pas_urgent') then
    raise exception 'Importance invalide. Choisissez Urgent ou Pas urgent.';
  end if;
  if p_target_type not in ('all_parents','level_parents','class_parents','student','all_teachers','teacher','all_canteen') then
    raise exception 'Destinataire invalide.';
  end if;

  if p_target_type = 'level_parents' and (p_level is null or p_level not in ('primaire','college')) then
    raise exception 'Le niveau (primaire ou collège) est obligatoire.';
  end if;
  if p_target_type = 'class_parents' and not exists (select 1 from public.classes where id = p_class_id) then
    raise exception 'Classe introuvable.';
  end if;
  if p_target_type = 'student' and not exists (select 1 from public.students where id = p_student_id) then
    raise exception 'Élève introuvable.';
  end if;
  if p_target_type = 'teacher' and not exists (select 1 from public.teachers where id = p_teacher_id) then
    raise exception 'Enseignant introuvable.';
  end if;

  insert into public.announcements(
    title, body, importance, target_type, level, class_id, student_id, teacher_id, created_by
  )
  values (
    trim(p_title), trim(p_body), p_importance, p_target_type,
    case when p_target_type = 'level_parents' then p_level else null end,
    case when p_target_type = 'class_parents' then p_class_id else null end,
    case when p_target_type = 'student' then p_student_id else null end,
    case when p_target_type = 'teacher' then p_teacher_id else null end,
    auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('success', true, 'announcement_id', v_id);
end;
$$;

create or replace function public.admin_delete_announcements(p_announcement_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if p_announcement_ids is null or cardinality(p_announcement_ids) = 0 then
    raise exception 'Aucun message sélectionné.';
  end if;

  delete from public.announcements where id = any(p_announcement_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

-- ============================================================
-- 12. DIRECTION : FRAIS DE SCOLARITÉ
-- ============================================================

create or replace function public.admin_set_class_fee(p_class_id uuid, p_amount numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.classes where id = p_class_id) then raise exception 'Classe introuvable.'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'Montant invalide.'; end if;

  insert into public.class_fees(class_id, total_amount, updated_at)
  values (p_class_id, round(p_amount), now())
  on conflict (class_id)
  do update set total_amount = excluded.total_amount, updated_at = now();

  return jsonb_build_object('success', true, 'class_id', p_class_id, 'total_amount', round(p_amount));
end;
$$;

-- Enregistre une tranche : le numéro libre le plus bas (1 à 15) est attribué.
create or replace function public.admin_add_payment(
  p_student_id uuid,
  p_amount numeric,
  p_paid_at date default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_no integer;
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.students where id = p_student_id) then raise exception 'Élève introuvable.'; end if;
  if p_amount is null or round(p_amount) <= 0 then raise exception 'Montant invalide.'; end if;

  select min(n) into v_no
  from generate_series(1, 15) as n
  where not exists (
    select 1 from public.fee_payments fp
    where fp.student_id = p_student_id and fp.installment_no = n
  );

  if v_no is null then
    raise exception 'Les 15 tranches de cet élève sont déjà saisies.';
  end if;

  insert into public.fee_payments(student_id, installment_no, amount, paid_at, note)
  values (
    p_student_id, v_no, round(p_amount),
    coalesce(p_paid_at, (now() at time zone 'utc')::date),
    nullif(trim(p_note), '')
  )
  returning id into v_id;

  return jsonb_build_object('success', true, 'payment_id', v_id, 'installment_no', v_no);
end;
$$;

create or replace function public.admin_update_payment(
  p_payment_id uuid,
  p_amount numeric,
  p_paid_at date default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if p_amount is null or round(p_amount) <= 0 then raise exception 'Montant invalide.'; end if;

  update public.fee_payments
  set amount = round(p_amount),
      paid_at = coalesce(p_paid_at, paid_at),
      note = nullif(trim(p_note), ''),
      updated_at = now()
  where id = p_payment_id;

  if not found then raise exception 'Tranche introuvable.'; end if;
  return jsonb_build_object('success', true);
end;
$$;

-- Rapport complet : une ligne par élève (montant dû, payé, reste, tranches, parents).
-- Les tris, filtres et seuils (ex. « moins de 15 000 FCFA ») sont appliqués dans l'interface.
create or replace function public.admin_fee_report()
returns table (
  student_id uuid,
  student_name text,
  class_id uuid,
  class_name text,
  level text,
  sort_order integer,
  fee_defined boolean,
  total_due numeric,
  paid numeric,
  remaining numeric,
  installments integer,
  last_payment date,
  parent_names text,
  parent_phones text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    s.full_name,
    c.id,
    c.name,
    c.level,
    c.sort_order,
    (coalesce(cf.total_amount, 0) > 0),
    coalesce(cf.total_amount, 0),
    coalesce(pay.paid, 0),
    greatest(coalesce(cf.total_amount, 0) - coalesce(pay.paid, 0), 0),
    coalesce(pay.n, 0)::integer,
    pay.last_date,
    par.names,
    par.phones
  from public.students s
  join public.classes c on c.id = s.class_id
  left join public.class_fees cf on cf.class_id = c.id
  left join lateral (
    select sum(fp.amount) as paid, count(*) as n, max(fp.paid_at) as last_date
    from public.fee_payments fp
    where fp.student_id = s.id
  ) pay on true
  left join lateral (
    select
      string_agg(p.full_name || ' (' || coalesce(sp.relationship, p.parent_type) || ')', ' · ' order by p.full_name) as names,
      string_agg(coalesce(p.phone, '—'), ' · ' order by p.full_name) as phones
    from public.student_parents sp
    join public.parents p on p.id = sp.parent_id
    where sp.student_id = s.id
  ) par on true
  where public.is_admin()
  order by c.sort_order, s.full_name, s.id;
$$;

-- ============================================================
-- 13. CONNEXION PAR CODE (parent 4 car. / enseignant 5 car. / cantine 6 car.)
-- ============================================================

create or replace function public.login_with_access_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
  v_parent record;
  v_teacher record;
  v_staff record;
begin
  if nullif(trim(p_code), '') is null then
    raise exception 'Code d''accès obligatoire.';
  end if;

  v_hash := public.hash_code(p_code);

  select id, full_name, phone, parent_type into v_parent
  from public.parents where access_code_hash = v_hash limit 1;

  if v_parent.id is not null then
    return jsonb_build_object(
      'success', true, 'role', 'parent', 'id', v_parent.id,
      'full_name', v_parent.full_name, 'phone', v_parent.phone,
      'parent_type', v_parent.parent_type
    );
  end if;

  select id, full_name, phone into v_teacher
  from public.teachers where access_code_hash = v_hash limit 1;

  if v_teacher.id is not null then
    return jsonb_build_object(
      'success', true, 'role', 'teacher', 'id', v_teacher.id,
      'full_name', v_teacher.full_name, 'phone', v_teacher.phone
    );
  end if;

  select id, full_name, phone into v_staff
  from public.canteen_staff where access_code_hash = v_hash limit 1;

  if v_staff.id is not null then
    return jsonb_build_object(
      'success', true, 'role', 'canteen', 'id', v_staff.id,
      'full_name', v_staff.full_name, 'phone', v_staff.phone
    );
  end if;

  return jsonb_build_object('success', false, 'message', 'Code d''accès incorrect.');
end;
$$;

-- ============================================================
-- 14. PARENT : ENFANTS, ENSEIGNANTS, NOTES, MESSAGES DE LA DIRECTION
-- ============================================================

create or replace function public.parent_children(p_code text)
returns table (
  student_id uuid,
  student_name text,
  class_id uuid,
  class_name text,
  level text
)
language sql
security definer
set search_path = public
as $$
  select s.id, s.full_name, c.id, c.name, c.level
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id
  join public.students s on s.id = sp.student_id
  join public.classes c on c.id = s.class_id
  where p.access_code_hash = public.hash_code(p_code)
  order by s.full_name;
$$;

create or replace function public.parent_child_teachers(p_code text, p_student_id uuid)
returns table (
  teacher_id uuid,
  teacher_name text,
  subject_id uuid,
  subject_name text,
  is_homeroom boolean
)
language sql
security definer
set search_path = public
as $$
  select distinct t.id, t.full_name, su.id, su.name, ta.is_homeroom
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id and sp.student_id = p_student_id
  join public.students s on s.id = sp.student_id
  join public.teacher_assignments ta on ta.class_id = s.class_id
  join public.teachers t on t.id = ta.teacher_id
  join public.subjects su on su.id = ta.subject_id
  where p.access_code_hash = public.hash_code(p_code)
  order by ta.is_homeroom desc, t.full_name, su.name;
$$;

create or replace function public.student_notes(p_code text, p_student_id uuid, p_term text)
returns table (
  subject_id uuid,
  subject_name text,
  devoirs jsonb,
  moyenne_classe numeric,
  composition numeric,
  moyenne_matiere numeric
)
language sql
security definer
set search_path = public
as $$
  with authorized_student as (
    select s.id, s.class_id
    from public.parents p
    join public.student_parents sp on sp.parent_id = p.id and sp.student_id = p_student_id
    join public.students s on s.id = sp.student_id
    where p.access_code_hash = public.hash_code(p_code)
  ),
  subject_rows as (
    select
      su.id as subject_id,
      su.name as subject_name,
      max(n.value) filter (where n.note_type = 'moyenne_classe') as moyenne_classe,
      max(n.value) filter (where n.note_type = 'composition') as composition,
      coalesce(
        jsonb_agg(
          jsonb_build_object('id', n.id, 'value', n.value, 'title', n.title, 'created_at', n.created_at)
          order by n.created_at
        ) filter (where n.note_type = 'devoir'),
        '[]'::jsonb
      ) as devoirs
    from authorized_student a
    cross join public.subjects su
    left join public.teacher_assignments ta on ta.class_id = a.class_id and ta.subject_id = su.id
    left join public.notes n
      on n.teacher_assignment_id = ta.id and n.student_id = a.id and n.term = p_term
    group by su.id, su.name
  )
  select
    subject_id,
    subject_name,
    devoirs,
    round(moyenne_classe, 2),
    round(composition, 2),
    case
      when moyenne_classe is not null and composition is not null
      then round((moyenne_classe + composition) / 2, 2)
      else null
    end
  from subject_rows
  where moyenne_classe is not null
     or composition is not null
     or jsonb_array_length(devoirs) > 0
  order by subject_name;
$$;

create or replace function public.student_announcements(p_code text, p_student_id uuid)
returns table (
  announcement_id uuid,
  title text,
  body text,
  importance text,
  target_type text,
  created_at timestamptz,
  is_read boolean
)
language sql
security definer
set search_path = public
as $$
  select
    a.id,
    a.title,
    a.body,
    a.importance,
    a.target_type,
    a.created_at,
    exists (
      select 1 from public.announcement_reads ar
      where ar.announcement_id = a.id and ar.parent_id = p.id and ar.student_id = p_student_id
    ) as is_read
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id and sp.student_id = p_student_id
  join public.students s on s.id = sp.student_id
  join public.classes c on c.id = s.class_id
  join public.announcements a
    on (
      a.target_type = 'all_parents'
      or (a.target_type = 'level_parents' and a.level = c.level)
      or (a.target_type = 'class_parents' and a.class_id = s.class_id)
      or (a.target_type = 'student' and a.student_id = s.id)
    )
  where p.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

create or replace function public.mark_announcements_read(p_code text, p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_id uuid;
  v_count integer := 0;
begin
  select p.id into v_parent_id
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id and sp.student_id = p_student_id
  where p.access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_parent_id is null then
    raise exception 'Parent ou élève non autorisé.';
  end if;

  insert into public.announcement_reads(announcement_id, parent_id, student_id, read_at)
  select a.id, v_parent_id, p_student_id, now()
  from public.announcements a
  join public.students s on s.id = p_student_id
  join public.classes c on c.id = s.class_id
  where (
    a.target_type = 'all_parents'
    or (a.target_type = 'level_parents' and a.level = c.level)
    or (a.target_type = 'class_parents' and a.class_id = s.class_id)
    or (a.target_type = 'student' and a.student_id = s.id)
  )
  on conflict (announcement_id, parent_id, student_id)
  do update set read_at = excluded.read_at;

  get diagnostics v_count = row_count;
  return jsonb_build_object('success', true, 'read_count', v_count);
end;
$$;

-- Frais de scolarité vus par le parent : total de la classe, déjà payé, reste à payer.
create or replace function public.parent_fees(p_code text, p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_id uuid;
  v_class_name text;
  v_total numeric;
  v_paid numeric;
  v_payments jsonb;
begin
  select s.class_id, c.name into v_class_id, v_class_name
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id and sp.student_id = p_student_id
  join public.students s on s.id = sp.student_id
  join public.classes c on c.id = s.class_id
  where p.access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_class_id is null then
    raise exception 'Parent ou élève non autorisé.';
  end if;

  select cf.total_amount into v_total from public.class_fees cf where cf.class_id = v_class_id;
  v_total := coalesce(v_total, 0);

  select coalesce(sum(fp.amount), 0) into v_paid
  from public.fee_payments fp where fp.student_id = p_student_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object('installment_no', fp.installment_no, 'amount', fp.amount, 'paid_at', fp.paid_at)
      order by fp.installment_no
    ),
    '[]'::jsonb
  ) into v_payments
  from public.fee_payments fp where fp.student_id = p_student_id;

  return jsonb_build_object(
    'defined', v_total > 0,
    'class_name', v_class_name,
    'total_due', v_total,
    'paid', v_paid,
    'remaining', greatest(v_total - v_paid, 0),
    'payments', v_payments
  );
end;
$$;

-- ============================================================
-- 15. MESSAGERIE PARENT <-> ENSEIGNANT (5 messages / jour / compte, remise à 00h GMT)
-- ============================================================

create or replace function public.conversation_messages(p_code text, p_teacher_id uuid, p_student_id uuid)
returns table (message_id uuid, sender_role text, body text, created_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select m.id, m.sender_role, m.body, m.created_at
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id and sp.student_id = p_student_id
  join public.conversations c
    on c.parent_id = p.id and c.teacher_id = p_teacher_id and c.student_id = p_student_id
  join public.messages m on m.conversation_id = c.id
  where p.access_code_hash = public.hash_code(p_code)
  order by m.created_at;
$$;

create or replace function public.send_parent_message(
  p_code text,
  p_teacher_id uuid,
  p_student_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
  v_day_start timestamptz;
  v_used integer;
begin
  if nullif(trim(p_body), '') is null then raise exception 'Le message est vide.'; end if;

  v_day_start := timezone('UTC', date_trunc('day', now() at time zone 'UTC'));

  select p.id into v_parent_id
  from public.parents p
  join public.student_parents sp on sp.parent_id = p.id and sp.student_id = p_student_id
  where p.access_code_hash = public.hash_code(p_code)
  limit 1;

  if v_parent_id is null then raise exception 'Parent non autorisé.'; end if;

  if not exists (
    select 1 from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.teacher_id = p_teacher_id and s.id = p_student_id
  ) then
    raise exception 'Cet enseignant n''intervient pas dans la classe de cet élève.';
  end if;

  select count(*)::integer into v_used
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  where c.parent_id = v_parent_id and m.created_at >= v_day_start;

  if v_used >= 5 then
    raise exception 'Quota atteint : ce compte a déjà envoyé ou reçu 5 messages aujourd''hui. Nouveau quota à 00h GMT.';
  end if;

  insert into public.conversations(parent_id, teacher_id, student_id)
  values (v_parent_id, p_teacher_id, p_student_id)
  on conflict (parent_id, teacher_id, student_id)
  do update set parent_id = excluded.parent_id
  returning id into v_conversation_id;

  insert into public.messages(conversation_id, sender_role, body)
  values (v_conversation_id, 'parent', trim(p_body))
  returning id into v_message_id;

  return jsonb_build_object('success', true, 'message_id', v_message_id, 'conversation_id', v_conversation_id);
end;
$$;

create or replace function public.teacher_send_parent_message(
  p_code text,
  p_student_id uuid,
  p_parent_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
  v_day_start timestamptz;
  v_used integer;
begin
  if nullif(trim(p_body), '') is null then raise exception 'Le message est vide.'; end if;

  v_day_start := timezone('UTC', date_trunc('day', now() at time zone 'UTC'));

  select id into v_teacher_id from public.teachers
  where access_code_hash = public.hash_code(p_code) limit 1;

  if v_teacher_id is null then raise exception 'Code enseignant invalide.'; end if;

  if not exists (
    select 1 from public.student_parents sp
    where sp.student_id = p_student_id and sp.parent_id = p_parent_id
  ) then
    raise exception 'Ce parent n''est pas lié à cet élève.';
  end if;

  if not exists (
    select 1 from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.teacher_id = v_teacher_id and s.id = p_student_id
  ) then
    raise exception 'Cet enseignant n''est pas affecté à la classe de cet élève.';
  end if;

  select count(*)::integer into v_used
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  where c.teacher_id = v_teacher_id and m.created_at >= v_day_start;

  if v_used >= 5 then
    raise exception 'Quota atteint : ce compte a déjà envoyé ou reçu 5 messages aujourd''hui. Nouveau quota à 00h GMT.';
  end if;

  insert into public.conversations(parent_id, teacher_id, student_id)
  values (p_parent_id, v_teacher_id, p_student_id)
  on conflict (parent_id, teacher_id, student_id)
  do update set teacher_id = excluded.teacher_id
  returning id into v_conversation_id;

  insert into public.messages(conversation_id, sender_role, body)
  values (v_conversation_id, 'teacher', trim(p_body))
  returning id into v_message_id;

  return jsonb_build_object('success', true, 'message_id', v_message_id, 'conversation_id', v_conversation_id);
end;
$$;

-- ============================================================
-- 16. ENSEIGNANT
-- ============================================================

create or replace function public.teacher_classes(p_code text)
returns table (
  class_id uuid,
  class_name text,
  subject_id uuid,
  subject_name text,
  assignment_id uuid,
  is_homeroom boolean,
  level text
)
language sql
security definer
set search_path = public
as $$
  select c.id, c.name, su.id, su.name, ta.id, ta.is_homeroom, c.level
  from public.teachers t
  join public.teacher_assignments ta on ta.teacher_id = t.id
  join public.classes c on c.id = ta.class_id
  join public.subjects su on su.id = ta.subject_id
  where t.access_code_hash = public.hash_code(p_code)
  order by c.sort_order, su.name;
$$;

create or replace function public.teacher_students(p_code text, p_class_id uuid)
returns table (student_id uuid, student_name text, class_name text)
language sql
security definer
set search_path = public
as $$
  select distinct s.id, s.full_name, c.name
  from public.teachers t
  join public.teacher_assignments ta on ta.teacher_id = t.id
  join public.classes c on c.id = ta.class_id
  join public.students s on s.class_id = c.id
  where t.access_code_hash = public.hash_code(p_code) and c.id = p_class_id
  order by s.full_name;
$$;

create or replace function public.teacher_save_note(
  p_code text,
  p_student_id uuid,
  p_assignment_id uuid,
  p_term text,
  p_note_type text,
  p_value numeric,
  p_title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_note_id uuid;
  v_existing_id uuid;
begin
  select id into v_teacher_id from public.teachers
  where access_code_hash = public.hash_code(p_code) limit 1;

  if v_teacher_id is null then raise exception 'Code enseignant invalide.'; end if;
  if p_term not in ('1er trimestre','2e trimestre','3e trimestre') then raise exception 'Trimestre invalide.'; end if;
  if p_note_type not in ('devoir','moyenne_classe','composition') then raise exception 'Type de note invalide.'; end if;
  if p_value is null or p_value < 0 or p_value > 20 then raise exception 'La note doit être comprise entre 0 et 20.'; end if;

  if not exists (
    select 1 from public.teacher_assignments ta
    join public.students s on s.class_id = ta.class_id
    where ta.id = p_assignment_id and ta.teacher_id = v_teacher_id and s.id = p_student_id
  ) then
    raise exception 'Vous n''êtes pas autorisé à saisir cette note.';
  end if;

  if p_note_type = 'devoir' then
    insert into public.notes(student_id, teacher_assignment_id, term, note_type, value, title, updated_at)
    values (p_student_id, p_assignment_id, p_term, 'devoir', p_value, nullif(trim(p_title), ''), now())
    returning id into v_note_id;
  else
    select id into v_existing_id from public.notes
    where student_id = p_student_id and teacher_assignment_id = p_assignment_id
      and term = p_term and note_type = p_note_type
    limit 1;

    if v_existing_id is null then
      insert into public.notes(student_id, teacher_assignment_id, term, note_type, value, title, updated_at)
      values (p_student_id, p_assignment_id, p_term, p_note_type, p_value, nullif(trim(p_title), ''), now())
      returning id into v_note_id;
    else
      update public.notes
      set value = p_value, title = nullif(trim(p_title), ''), updated_at = now()
      where id = v_existing_id
      returning id into v_note_id;
    end if;
  end if;

  return jsonb_build_object('success', true, 'note_id', v_note_id);
end;
$$;

create or replace function public.teacher_conversations(p_code text)
returns table (
  parent_id uuid,
  parent_name text,
  student_id uuid,
  student_name text,
  class_name text,
  last_message text,
  last_sender_role text,
  last_message_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.full_name, s.id, s.full_name, cclass.name, lm.body, lm.sender_role, lm.created_at
  from public.teachers t
  join public.conversations c on c.teacher_id = t.id
  join public.parents p on p.id = c.parent_id
  join public.students s on s.id = c.student_id
  join public.classes cclass on cclass.id = s.class_id
  join lateral (
    select m.body, m.sender_role, m.created_at
    from public.messages m
    where m.conversation_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  where t.access_code_hash = public.hash_code(p_code)
  order by lm.created_at desc;
$$;

create or replace function public.teacher_conversation_messages(p_code text, p_student_id uuid, p_parent_id uuid)
returns table (message_id uuid, sender_role text, body text, created_at timestamptz)
language sql
security definer
set search_path = public
as $$
  select m.id, m.sender_role, m.body, m.created_at
  from public.teachers t
  join public.conversations c
    on c.teacher_id = t.id and c.student_id = p_student_id and c.parent_id = p_parent_id
  join public.messages m on m.conversation_id = c.id
  where t.access_code_hash = public.hash_code(p_code)
  order by m.created_at;
$$;

create or replace function public.teacher_class_statistics(p_code text, p_term text)
returns table (class_id uuid, class_name text, effectif bigint)
language sql
security definer
set search_path = public
as $$
  select c.id, c.name, count(distinct s.id)
  from public.teachers t
  join public.teacher_assignments ta on ta.teacher_id = t.id
  join public.classes c on c.id = ta.class_id
  left join public.students s on s.class_id = c.id
  where t.access_code_hash = public.hash_code(p_code)
  group by c.id, c.name, c.sort_order
  order by c.sort_order;
$$;

-- Classement : moyenne générale = moyenne des moyennes de matières
-- (Moyenne de classe + Composition) / 2. Les devoirs sont exclus.
create or replace function public.teacher_student_rankings(p_code text, p_class_id uuid, p_term text)
returns table (student_id uuid, student_name text, moyenne_generale numeric)
language sql
security definer
set search_path = public
as $$
  with authorized_teacher as (
    select distinct ta.class_id
    from public.teachers t
    join public.teacher_assignments ta on ta.teacher_id = t.id
    where t.access_code_hash = public.hash_code(p_code) and ta.class_id = p_class_id
  ),
  assignment_subjects as (
    select
      s.id as student_id,
      ta.subject_id,
      ta.id as assignment_id,
      max(n.value) filter (where n.note_type = 'moyenne_classe') as moyenne_classe,
      max(n.value) filter (where n.note_type = 'composition') as composition
    from public.students s
    join authorized_teacher at on at.class_id = s.class_id
    join public.teacher_assignments ta on ta.class_id = s.class_id
    left join public.notes n
      on n.student_id = s.id and n.teacher_assignment_id = ta.id and n.term = p_term
    group by s.id, ta.subject_id, ta.id
  ),
  subject_averages as (
    select student_id, subject_id, avg((moyenne_classe + composition) / 2.0) as subject_average
    from assignment_subjects
    where moyenne_classe is not null and composition is not null
    group by student_id, subject_id
  )
  select s.id, s.full_name, round(avg(sa.subject_average), 2)
  from public.students s
  join authorized_teacher at on at.class_id = s.class_id
  left join subject_averages sa on sa.student_id = s.id
  group by s.id, s.full_name
  order by avg(sa.subject_average) desc nulls last, s.full_name asc;
$$;

create or replace function public.teacher_announcements(p_code text)
returns table (
  announcement_id uuid,
  title text,
  body text,
  importance text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select a.id, a.title, a.body, a.importance, a.created_at
  from public.teachers t
  join public.announcements a
    on a.target_type = 'all_teachers'
    or (a.target_type = 'teacher' and a.teacher_id = t.id)
  where t.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

-- ============================================================
-- 17. CANTINE
-- ============================================================

-- Efface menus + photos antérieurs au dernier dimanche 00h GMT.
create or replace function public.purge_canteen_week()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cut timestamptz;
  v_n integer := 0;
begin
  v_cut := (
    date_trunc('day', now() at time zone 'utc')
    - (extract(dow from (now() at time zone 'utc'))::integer * interval '1 day')
  ) at time zone 'utc';

  delete from public.canteen_menus where created_at < v_cut;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

create or replace function public.canteen_viewer_ok(p_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.parents where access_code_hash = public.hash_code(p_code))
      or exists (select 1 from public.canteen_staff where access_code_hash = public.hash_code(p_code));
$$;

-- Dates pour lesquelles un menu existe (semaine en cours) : parents et cantine.
create or replace function public.canteen_menu_dates(p_code text)
returns table (menu_date date, dish_name text, photo_count integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.canteen_viewer_ok(p_code) then raise exception 'Code d''accès invalide.'; end if;
  perform public.purge_canteen_week();

  return query
  select m.menu_date, m.dish_name,
         (select count(*)::integer from public.canteen_photos cp where cp.menu_id = m.id)
  from public.canteen_menus m
  order by m.menu_date desc;
end;
$$;

-- Menu + photos d'une date précise (parents et cantine).
create or replace function public.canteen_menu_for_date(p_code text, p_date date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_menu record;
  v_photos jsonb;
begin
  if not public.canteen_viewer_ok(p_code) then raise exception 'Code d''accès invalide.'; end if;
  perform public.purge_canteen_week();

  select * into v_menu from public.canteen_menus where menu_date = p_date;
  if not found then
    return jsonb_build_object('exists', false, 'menu_date', p_date, 'photos', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(cp.image_base64 order by cp.slot), '[]'::jsonb) into v_photos
  from public.canteen_photos cp where cp.menu_id = v_menu.id;

  return jsonb_build_object(
    'exists', true,
    'menu_date', v_menu.menu_date,
    'dish_name', v_menu.dish_name,
    'description', v_menu.description,
    'staff_name', v_menu.created_by_name,
    'photos', v_photos
  );
end;
$$;

-- Menu du jour (GMT) vu par une personne de la cantine.
create or replace function public.canteen_today(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id uuid;
  v_today date := (now() at time zone 'utc')::date;
  v_menu record;
  v_photos jsonb;
  v_count integer;
begin
  select id into v_staff_id from public.canteen_staff
  where access_code_hash = public.hash_code(p_code) limit 1;
  if v_staff_id is null then raise exception 'Code cantine invalide.'; end if;

  perform public.purge_canteen_week();

  select * into v_menu from public.canteen_menus where menu_date = v_today;
  if not found then
    return jsonb_build_object(
      'date', v_today, 'exists', false, 'dish_name', '', 'description', '',
      'photo_count', 0, 'locked', false, 'staff_name', null, 'photos', '[]'::jsonb
    );
  end if;

  select count(*)::integer into v_count from public.canteen_photos where menu_id = v_menu.id;
  select coalesce(jsonb_agg(cp.image_base64 order by cp.slot), '[]'::jsonb) into v_photos
  from public.canteen_photos cp where cp.menu_id = v_menu.id;

  return jsonb_build_object(
    'date', v_today,
    'exists', true,
    'dish_name', v_menu.dish_name,
    'description', coalesce(v_menu.description, ''),
    'photo_count', v_count,
    'locked', v_count >= 2,
    'staff_name', v_menu.created_by_name,
    'photos', v_photos
  );
end;
$$;

-- Enregistre le nom du plat du jour (tant que les 2 photos ne sont pas toutes ajoutées).
create or replace function public.canteen_save_menu(p_code text, p_dish_name text, p_description text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id uuid;
  v_staff_name text;
  v_today date := (now() at time zone 'utc')::date;
  v_menu_id uuid;
  v_count integer;
begin
  select id, full_name into v_staff_id, v_staff_name from public.canteen_staff
  where access_code_hash = public.hash_code(p_code) limit 1;
  if v_staff_id is null then raise exception 'Code cantine invalide.'; end if;
  if nullif(trim(p_dish_name), '') is null then raise exception 'Le nom du plat est obligatoire.'; end if;

  perform public.purge_canteen_week();

  select id into v_menu_id from public.canteen_menus where menu_date = v_today for update;

  if v_menu_id is null then
    insert into public.canteen_menus(menu_date, dish_name, description, created_by, created_by_name)
    values (v_today, trim(p_dish_name), nullif(trim(p_description), ''), v_staff_id, v_staff_name)
    returning id into v_menu_id;
  else
    select count(*)::integer into v_count from public.canteen_photos where menu_id = v_menu_id;
    if v_count >= 2 then
      raise exception 'Le plat du jour est complet : les 2 photos ont déjà été ajoutées. Vous pouvez seulement les consulter.';
    end if;
    update public.canteen_menus
    set dish_name = trim(p_dish_name), description = nullif(trim(p_description), ''), updated_at = now()
    where id = v_menu_id;
  end if;

  return jsonb_build_object('success', true, 'menu_id', v_menu_id);
end;
$$;

-- Ajoute UNE photo au plat du jour (2 maximum pour toute la cantine).
create or replace function public.canteen_add_photo(p_code text, p_image text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff_id uuid;
  v_staff_name text;
  v_today date := (now() at time zone 'utc')::date;
  v_menu_id uuid;
  v_count integer;
  v_slot integer;
begin
  select id, full_name into v_staff_id, v_staff_name from public.canteen_staff
  where access_code_hash = public.hash_code(p_code) limit 1;
  if v_staff_id is null then raise exception 'Code cantine invalide.'; end if;
  if p_image is null or length(p_image) < 100 then raise exception 'Photo invalide.'; end if;
  if length(p_image) > 2500000 then raise exception 'Photo trop lourde.'; end if;

  perform public.purge_canteen_week();

  select id into v_menu_id from public.canteen_menus where menu_date = v_today for update;
  if v_menu_id is null then
    raise exception 'Enregistrez d''abord le nom du plat du jour.';
  end if;

  select count(*)::integer into v_count from public.canteen_photos where menu_id = v_menu_id;
  if v_count >= 2 then
    raise exception 'Les 2 photos du plat du jour ont déjà été ajoutées. Vous pouvez seulement les consulter.';
  end if;

  select min(sl) into v_slot
  from generate_series(1, 2) as sl
  where not exists (
    select 1 from public.canteen_photos cp where cp.menu_id = v_menu_id and cp.slot = sl
  );

  insert into public.canteen_photos(menu_id, slot, image_base64, added_by, added_by_name)
  values (v_menu_id, v_slot, p_image, v_staff_id, v_staff_name);

  return jsonb_build_object('success', true, 'photo_count', v_count + 1, 'locked', (v_count + 1) >= 2);
end;
$$;

create or replace function public.canteen_announcements(p_code text)
returns table (
  announcement_id uuid,
  title text,
  body text,
  importance text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select a.id, a.title, a.body, a.importance, a.created_at
  from public.canteen_staff cs
  join public.announcements a on a.target_type = 'all_canteen'
  where cs.access_code_hash = public.hash_code(p_code)
  order by a.created_at desc;
$$;

-- ============================================================
-- 18. NOTIFICATIONS ANDROID
-- ============================================================

create or replace function public.mobile_server_time()
returns timestamptz
language sql
security definer
set search_path = public
as $$
  select clock_timestamp();
$$;

create or replace function public.mobile_notifications(p_code text, p_role text, p_since timestamptz)
returns table (
  notification_id text,
  title text,
  body text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with incoming as (
    -- Parent : message de la Direction
    select
      'direction-' || a.id::text as notification_id,
      case when a.importance = 'urgent' then 'URGENT • Message de la Direction' else 'Message de la Direction' end as title,
      (a.title || ' : ' || a.body) as body,
      a.created_at as created_at
    from public.parents p
    join public.student_parents sp on sp.parent_id = p.id
    join public.students s on s.id = sp.student_id
    join public.classes c on c.id = s.class_id
    join public.announcements a
      on (
        a.target_type = 'all_parents'
        or (a.target_type = 'level_parents' and a.level = c.level)
        or (a.target_type = 'class_parents' and a.class_id = s.class_id)
        or (a.target_type = 'student' and a.student_id = s.id)
      )
    where p_role = 'parent'
      and p.access_code_hash = public.hash_code(p_code)
      and a.created_at > (p_since - interval '10 seconds')

    union all

    -- Parent : message reçu d'un enseignant
    select
      'teacher-message-' || m.id::text,
      ('Message de ' || t.full_name || ' (' || s.full_name || ')'),
      m.body,
      m.created_at
    from public.parents p
    join public.conversations c on c.parent_id = p.id
    join public.teachers t on t.id = c.teacher_id
    join public.students s on s.id = c.student_id
    join public.messages m on m.conversation_id = c.id
    where p_role = 'parent'
      and p.access_code_hash = public.hash_code(p_code)
      and m.sender_role = 'teacher'
      and m.created_at > (p_since - interval '10 seconds')

    union all

    -- Enseignant : message de la Direction
    select
      'direction-teacher-' || a.id::text,
      case when a.importance = 'urgent' then 'URGENT • Message de la Direction' else 'Message de la Direction' end,
      (a.title || ' : ' || a.body),
      a.created_at
    from public.teachers t
    join public.announcements a
      on a.target_type = 'all_teachers'
      or (a.target_type = 'teacher' and a.teacher_id = t.id)
    where p_role = 'teacher'
      and t.access_code_hash = public.hash_code(p_code)
      and a.created_at > (p_since - interval '10 seconds')

    union all

    -- Enseignant : message reçu d'un parent
    select
      'parent-message-' || m.id::text,
      ('Message du parent de ' || s.full_name),
      m.body,
      m.created_at
    from public.teachers t
    join public.conversations c on c.teacher_id = t.id
    join public.students s on s.id = c.student_id
    join public.messages m on m.conversation_id = c.id
    where p_role = 'teacher'
      and t.access_code_hash = public.hash_code(p_code)
      and m.sender_role = 'parent'
      and m.created_at > (p_since - interval '10 seconds')

    union all

    -- Cantine : message de la Direction
    select
      'direction-canteen-' || a.id::text,
      case when a.importance = 'urgent' then 'URGENT • Message de la Direction' else 'Message de la Direction' end,
      (a.title || ' : ' || a.body),
      a.created_at
    from public.canteen_staff cs
    join public.announcements a on a.target_type = 'all_canteen'
    where p_role = 'canteen'
      and cs.access_code_hash = public.hash_code(p_code)
      and a.created_at > (p_since - interval '10 seconds')
  )
  select n.notification_id, n.title, n.body, n.created_at
  from (
    select distinct on (i.notification_id) i.notification_id, i.title, i.body, i.created_at
    from incoming i
    order by i.notification_id, i.created_at asc
  ) n
  order by n.created_at asc
  limit 30;
$$;

-- ============================================================
-- 19. NETTOYAGE AUTOMATIQUE DE LA CANTINE : chaque dimanche à 00h GMT
-- ============================================================
-- Utilise pg_cron (Supabase > Database > Extensions > pg_cron).
-- Si pg_cron n'est pas disponible, le nettoyage est quand même garanti :
-- chaque appel cantine/parent exécute purge_canteen_week() au préalable.

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule(
    'canteen-weekly-purge',
    '0 0 * * 0',
    $cmd$select public.purge_canteen_week();$cmd$
  );
exception when others then
  raise notice 'pg_cron indisponible (%). Le nettoyage hebdomadaire se fera automatiquement au premier appel cantine après dimanche 00h GMT.', sqlerrm;
end $$;

-- ============================================================
-- 20. DROITS D'EXÉCUTION
-- ============================================================

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
      and p.proname in (
        'admin_access_codes', 'admin_add_child_to_parent', 'admin_add_payment',
        'admin_assign_teacher', 'admin_create_announcement',
        'admin_create_canteen_staff', 'admin_create_parent_with_children',
        'admin_create_teacher', 'admin_delete_announcements', 'admin_delete_parent',
        'admin_fee_report', 'admin_reset_canteen_code', 'admin_reset_parent_code',
        'admin_reset_teacher_code', 'admin_set_class_fee', 'admin_update_parent',
        'admin_update_payment', 'admin_update_teacher_assignment', 'bootstrap_admin',
        'canteen_add_photo', 'canteen_announcements', 'canteen_menu_dates',
        'canteen_menu_for_date', 'canteen_save_menu', 'canteen_today',
        'canteen_viewer_ok', 'conversation_messages', 'hash_code', 'is_admin',
        'login_with_access_code', 'make_code', 'mark_announcements_read',
        'mobile_notifications', 'mobile_server_time', 'parent_child_teachers',
        'parent_children', 'parent_fees', 'purge_canteen_week', 'send_parent_message',
        'student_announcements', 'student_notes', 'teacher_announcements',
        'teacher_class_statistics', 'teacher_classes', 'teacher_conversation_messages',
        'teacher_conversations', 'teacher_save_note', 'teacher_send_parent_message',
        'teacher_student_rankings', 'teacher_students', 'trg_student_requires_parent'
      )
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);

    if r.proname like 'admin\_%' or r.proname in ('bootstrap_admin', 'is_admin') then
      execute format('grant execute on function %s to authenticated', r.sig);
    elsif r.proname in ('make_code', 'hash_code', 'purge_canteen_week', 'canteen_viewer_ok', 'trg_student_requires_parent') then
      null;
    else
      execute format('grant execute on function %s to anon, authenticated', r.sig);
    end if;
  end loop;
end $$;

-- ============================================================
-- 21. CLASSES, MATIÈRES PAR NIVEAU (programme togolais)
-- ============================================================

-- ------------------------------------------------------------
-- 1. CLASSES
-- ------------------------------------------------------------
insert into public.classes (name, code, level, sort_order) values
  ('CI1',   'CI1', 'primaire', 1),
  ('CI2',   'CI2', 'primaire', 2),
  ('CP1',   'CP1', 'primaire', 3),
  ('CP2',   'CP2', 'primaire', 4),
  ('CE1',   'CE1', 'primaire', 5),
  ('CE2',   'CE2', 'primaire', 6),
  ('CM1',   'CM1', 'primaire', 7),
  ('CM2',   'CM2', 'primaire', 8),
  ('6ième', '6E',  'college',  11),
  ('5ième', '5E',  'college',  12),
  ('4ième', '4E',  'college',  13),
  ('3ième', '3E',  'college',  14)
on conflict (code) do update
  set name       = excluded.name,
      level      = excluded.level,
      sort_order = excluded.sort_order;

-- ------------------------------------------------------------
-- 2. FRAIS DE SCOLARITÉ (une ligne par classe, montant à 0 au départ)
-- ------------------------------------------------------------
insert into public.class_fees (class_id, total_amount)
select c.id, 0
from public.classes c
on conflict (class_id) do nothing;

-- ------------------------------------------------------------
-- 3. MATIÈRES
-- ------------------------------------------------------------
insert into public.subjects (name) values
  -- Primaire
  ('Lecture'),
  ('Écriture'),
  ('Dictée'),
  ('Expression orale'),
  ('Grammaire'),
  ('Conjugaison'),
  ('Orthographe'),
  ('Rédaction'),
  ('Calcul'),
  ('Géométrie'),
  ('Éveil scientifique'),
  ('Histoire'),
  ('Géographie'),
  ('Éducation Civique'),
  ('Dessin'),
  ('Chant'),
  -- Collège
  ('Français'),
  ('Mathématiques'),
  ('Sciences Physiques'),
  ('SVT'),
  ('Histoire-Géographie'),
  ('Informatique'),
  ('Technologie'),
  ('Allemand'),
  ('Espagnol'),
  ('Arts plastiques'),
  ('Éducation musicale'),
  -- Primaire et Collège
  ('Anglais'),
  ('EPS')
on conflict (name) do nothing;

-- ------------------------------------------------------------
-- 4. MATIÈRES PAR NIVEAU
-- ------------------------------------------------------------
create table if not exists public.subject_levels (
  subject_id uuid not null references public.subjects(id) on delete cascade,
  level text not null check (level in ('primaire','college')),
  primary key (subject_id, level)
);

create index if not exists idx_subject_levels_level on public.subject_levels(level);

alter table public.subject_levels enable row level security;

drop policy if exists admin_all_subject_levels on public.subject_levels;
create policy admin_all_subject_levels on public.subject_levels for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

revoke all on public.subject_levels from anon;

-- Primaire
insert into public.subject_levels (subject_id, level)
select s.id, 'primaire'
from public.subjects s
where s.name in (
  'Lecture', 'Écriture', 'Dictée', 'Expression orale', 'Grammaire', 'Conjugaison',
  'Orthographe', 'Rédaction', 'Calcul', 'Géométrie', 'Éveil scientifique', 'Histoire',
  'Géographie', 'Éducation Civique', 'Dessin', 'Chant', 'Anglais', 'EPS'
)
on conflict do nothing;

-- Collège
insert into public.subject_levels (subject_id, level)
select s.id, 'college'
from public.subjects s
where s.name in (
  'Français', 'Anglais', 'Mathématiques', 'Sciences Physiques', 'SVT',
  'Histoire-Géographie', 'Éducation Civique', 'EPS', 'Informatique', 'Technologie',
  'Allemand', 'Espagnol', 'Arts plastiques', 'Éducation musicale'
)
on conflict do nothing;

-- ------------------------------------------------------------
-- 5. DIAGNOSTIC (résultat affiché à la fin)
-- ------------------------------------------------------------
-- Si "comptes_direction_actives" vaut 0, l'interface admin ne verra AUCUNE donnée
-- (listes vides). Dans ce cas : déconnectez-vous de l'interface admin, reconnectez-vous
-- avec votre e-mail/mot de passe, ou exécutez la ligne commentée ci-dessous en
-- remplaçant l'adresse par celle de votre compte Direction :
--
--   insert into public.admin_users (user_id, email)
--   select id, email from auth.users where email = 'VOTRE_EMAIL_ICI'
--   on conflict (user_id) do nothing;

-- ============================================================
-- 22. PRIMAIRE : UN SEUL ENSEIGNANT PAR CLASSE / COLLÈGE : PLUSIEURS
-- ============================================================

-- Sécurité : la table des niveaux de matières doit exister (créée à l'étape 3)
create table if not exists public.subject_levels (
  subject_id uuid not null references public.subjects(id) on delete cascade,
  level text not null check (level in ('primaire','college')),
  primary key (subject_id, level)
);
alter table public.subject_levels enable row level security;
drop policy if exists admin_all_subject_levels on public.subject_levels;
create policy admin_all_subject_levels on public.subject_levels for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
revoke all on public.subject_levels from anon;

-- ------------------------------------------------------------
-- 1. Garde-fou : un seul enseignant par classe du Primaire
-- ------------------------------------------------------------
create or replace function public.trg_primary_single_teacher()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level text;
  v_count integer;
begin
  select level into v_level from public.classes where id = new.class_id;
  if v_level = 'primaire' then
    select count(distinct teacher_id) into v_count
    from public.teacher_assignments where class_id = new.class_id;
    if v_count > 1 then
      raise exception 'Au Primaire, une classe n''a qu''un seul enseignant, qui assure toutes les matières.';
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists primary_single_teacher on public.teacher_assignments;
create constraint trigger primary_single_teacher
  after insert or update of teacher_id, class_id on public.teacher_assignments
  deferrable initially deferred
  for each row execute function public.trg_primary_single_teacher();

-- ------------------------------------------------------------
-- 2. Affecter l'enseignant unique d'une classe du Primaire
-- ------------------------------------------------------------
create or replace function public.admin_assign_primary_teacher(
  p_teacher_id uuid,
  p_class_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level text;
  v_count integer;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.teachers where id = p_teacher_id) then raise exception 'Enseignant introuvable.'; end if;
  select level into v_level from public.classes where id = p_class_id;
  if v_level is null then raise exception 'Classe introuvable.'; end if;
  if v_level <> 'primaire' then raise exception 'Cette action est réservée aux classes du Primaire.'; end if;
  if not exists (select 1 from public.subject_levels where level = 'primaire') then
    raise exception 'Aucune matière du Primaire n''est définie.';
  end if;

  -- remplace l'ancien enseignant en conservant les notes déjà saisies
  update public.teacher_assignments
     set teacher_id = p_teacher_id, is_homeroom = true
   where class_id = p_class_id and teacher_id <> p_teacher_id;

  -- toutes les matières du Primaire pour cet enseignant
  insert into public.teacher_assignments (teacher_id, class_id, subject_id, is_homeroom)
  select p_teacher_id, p_class_id, sl.subject_id, true
  from public.subject_levels sl
  where sl.level = 'primaire'
  on conflict (teacher_id, class_id, subject_id) do update set is_homeroom = true;

  select count(*) into v_count from public.teacher_assignments where class_id = p_class_id;
  return jsonb_build_object('success', true, 'subjects_count', v_count);
end;
$$;

-- ------------------------------------------------------------
-- 3. admin_assign_teacher : redirige les classes du Primaire,
--    et vérifie que la matière est enseignée à ce niveau (Collège)
-- ------------------------------------------------------------
create or replace function public.admin_assign_teacher(
  p_teacher_id uuid,
  p_class_id uuid,
  p_subject_id uuid,
  p_is_homeroom boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment_id uuid;
  v_level text;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if not exists (select 1 from public.teachers where id = p_teacher_id) then raise exception 'Enseignant introuvable.'; end if;
  select level into v_level from public.classes where id = p_class_id;
  if v_level is null then raise exception 'Classe introuvable.'; end if;
  if not exists (select 1 from public.subjects where id = p_subject_id) then raise exception 'Matière introuvable.'; end if;

  if v_level = 'primaire' then
    return public.admin_assign_primary_teacher(p_teacher_id, p_class_id);
  end if;

  if exists (select 1 from public.subject_levels where subject_id = p_subject_id)
     and not exists (select 1 from public.subject_levels where subject_id = p_subject_id and level = v_level) then
    raise exception 'Cette matière n''est pas enseignée à ce niveau.';
  end if;

  if p_is_homeroom then
    update public.teacher_assignments set is_homeroom = false where class_id = p_class_id;
  end if;

  insert into public.teacher_assignments(teacher_id, class_id, subject_id, is_homeroom)
  values (p_teacher_id, p_class_id, p_subject_id, p_is_homeroom)
  on conflict (teacher_id, class_id, subject_id)
  do update set is_homeroom = excluded.is_homeroom
  returning id into v_assignment_id;

  return jsonb_build_object('success', true, 'assignment_id', v_assignment_id);
end;
$$;

-- ------------------------------------------------------------
-- 4. Ajouter une matière à un niveau
--    (Primaire : elle est aussitôt ajoutée à l'enseignant de chaque classe)
-- ------------------------------------------------------------
create or replace function public.admin_add_subject(p_name text, p_level text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(p_name), '');
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if v_name is null then raise exception 'Nom de matière obligatoire.'; end if;
  if p_level not in ('primaire', 'college') then raise exception 'Niveau invalide.'; end if;

  select id into v_id from public.subjects where lower(name) = lower(v_name) limit 1;
  if v_id is null then
    insert into public.subjects(name) values (v_name) returning id into v_id;
  end if;

  insert into public.subject_levels(subject_id, level) values (v_id, p_level)
  on conflict do nothing;

  if p_level = 'primaire' then
    insert into public.teacher_assignments (teacher_id, class_id, subject_id, is_homeroom)
    select distinct on (ta.class_id) ta.teacher_id, ta.class_id, v_id, true
    from public.teacher_assignments ta
    join public.classes c on c.id = ta.class_id
    where c.level = 'primaire'
    order by ta.class_id, ta.created_at
    on conflict (teacher_id, class_id, subject_id) do nothing;
  end if;

  return jsonb_build_object('success', true, 'subject_id', v_id);
end;
$$;

-- ------------------------------------------------------------
-- 5. Retirer une matière d'un niveau
-- ------------------------------------------------------------
create or replace function public.admin_delete_subject(p_subject_id uuid, p_level text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
  if p_level not in ('primaire', 'college') then raise exception 'Niveau invalide.'; end if;

  delete from public.teacher_assignments ta
  using public.classes c
  where ta.class_id = c.id and c.level = p_level and ta.subject_id = p_subject_id;

  delete from public.subject_levels where subject_id = p_subject_id and level = p_level;

  -- plus aucun niveau et plus aucune affectation : la matière disparaît
  if not exists (select 1 from public.subject_levels where subject_id = p_subject_id)
     and not exists (select 1 from public.teacher_assignments where subject_id = p_subject_id) then
    delete from public.subjects where id = p_subject_id;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

-- ------------------------------------------------------------
-- 6. Rattrapage : classes du Primaire ayant déjà un seul enseignant
--    -> il reçoit toutes les matières du Primaire manquantes
-- ------------------------------------------------------------
insert into public.teacher_assignments (teacher_id, class_id, subject_id, is_homeroom)
select one.teacher_id, one.class_id, sl.subject_id, true
from (
  select ta.class_id, min(ta.teacher_id::text)::uuid as teacher_id
  from public.teacher_assignments ta
  join public.classes c on c.id = ta.class_id
  where c.level = 'primaire'
  group by ta.class_id
  having count(distinct ta.teacher_id) = 1
) one
cross join public.subject_levels sl
where sl.level = 'primaire'
on conflict (teacher_id, class_id, subject_id) do nothing;

update public.teacher_assignments ta
   set is_homeroom = true
  from public.classes c
 where c.id = ta.class_id and c.level = 'primaire' and ta.is_homeroom = false;

-- ------------------------------------------------------------
-- 7. Droits d'exécution des nouvelles fonctions
-- ------------------------------------------------------------
revoke all on function public.admin_assign_primary_teacher(uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_add_subject(text, text)            from public, anon, authenticated;
revoke all on function public.admin_delete_subject(uuid, text)         from public, anon, authenticated;
revoke all on function public.trg_primary_single_teacher()             from public, anon, authenticated;
revoke all on function public.admin_assign_teacher(uuid, uuid, uuid, boolean) from public, anon;

grant execute on function public.admin_assign_primary_teacher(uuid, uuid) to authenticated;
grant execute on function public.admin_add_subject(text, text)            to authenticated;
grant execute on function public.admin_delete_subject(uuid, text)         to authenticated;
grant execute on function public.admin_assign_teacher(uuid, uuid, uuid, boolean) to authenticated;

select 'Complexe Scolaire SAINT JEAN PAUL II — base installée avec succès.' as message;
