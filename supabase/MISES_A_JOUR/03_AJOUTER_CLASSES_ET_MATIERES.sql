-- ============================================================================
-- SAINT JEAN PAUL II — ÉTAPE 3 : CLASSES + MATIÈRES PAR NIVEAU (programme togolais)
-- ============================================================================
-- À exécuter dans Supabase > SQL Editor > New query > Run.
-- Le script peut être relancé sans danger : il n'ajoute jamais de doublons.
--
-- Contenu :
--   1. Classes du Primaire (CI1, CI2, CP1, CP2, CE1, CE2, CM1, CM2)
--      et du Collège (6ième, 5ième, 4ième, 3ième)
--   2. Frais de scolarité initiaux (0 FCFA, à définir ensuite dans l'admin)
--   3. Matières du Primaire et matières du Collège
--   4. Table "subject_levels" : indique pour chaque matière si elle est
--      enseignée au Primaire, au Collège, ou aux deux
-- ============================================================================

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

select
  (select count(*) from public.classes where level = 'primaire') as classes_primaire,
  (select count(*) from public.classes where level = 'college')  as classes_college,
  (select count(*) from public.subject_levels where level = 'primaire') as matieres_primaire,
  (select count(*) from public.subject_levels where level = 'college')  as matieres_college,
  (select count(*) from public.admin_users) as comptes_direction_actives;
