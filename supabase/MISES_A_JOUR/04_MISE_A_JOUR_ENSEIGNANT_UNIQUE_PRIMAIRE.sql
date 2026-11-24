-- ============================================================================
-- SAINT JEAN PAUL II — ÉTAPE 4 : UN SEUL ENSEIGNANT PAR CLASSE AU PRIMAIRE
-- ============================================================================
-- À exécuter dans Supabase > SQL Editor > New query > Run (après les étapes 1 à 3).
-- Peut être relancé sans danger. Ne supprime aucune donnée.
--
-- Règles mises en place :
--   * PRIMAIRE : une classe = UN seul enseignant, qui assure toutes les matières
--     du Primaire (affectées automatiquement). Changer d'enseignant conserve les notes.
--   * COLLÈGE  : plusieurs enseignants par classe, une matière par affectation.
--   * Ajout / retrait d'une matière géré par niveau (table subject_levels).
-- ============================================================================

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

select 'Étape 4 appliquée : un seul enseignant par classe au Primaire.' as message;
