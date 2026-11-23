-- MIGRATION SÛRE POUR UN PROJET SUPABASE EXISTANT DU PROJET SOURCE CONNECT TEST.
-- Ne supprime pas les tables ni les données scolaires existantes.
-- Faire une sauvegarde avant exécution.

alter table public.access_code_records add column if not exists canteen_id uuid;
alter table public.access_code_records drop constraint if exists access_code_records_role_check;
alter table public.access_code_records drop constraint if exists access_code_records_owner_check;
alter table public.access_code_records add constraint access_code_records_role_check check(role in ('parent','teacher','canteen'));
alter table public.access_code_records add constraint access_code_records_owner_check check(
 (role='parent' and parent_id is not null and teacher_id is null and canteen_id is null)
 or (role='teacher' and teacher_id is not null and parent_id is null and canteen_id is null)
 or (role='canteen' and canteen_id is not null and parent_id is null and teacher_id is null)
);

insert into public.classes(name,code) values
 ('CI1','CI1'),('CI2','CI2'),('CP1','CP1'),('CP2','CP2'),('CE1','CE1'),('CE2','CE2'),('CM1','CM1'),('CM2','CM2'),
 ('6ième','6E'),('5ième','5E'),('4ième','4E'),('3ième','3E')
on conflict(name) do update set code=excluded.code;

-- ============================================================================
-- COMPLEXE SCOLAIRE SAINT JEAN PAUL II : CANTINE + FRAIS DE SCOLARITE
-- ============================================================================
alter table public.student_parents add column if not exists relationship text not null default 'Père';
alter table public.parents add column if not exists relationship text not null default 'Père';

create table if not exists public.canteen_staff (
 id uuid primary key default gen_random_uuid(), full_name text not null, phone text,
 access_code_hash text not null unique, created_at timestamptz not null default now()
);
create table if not exists public.canteen_meals (
 id uuid primary key default gen_random_uuid(), meal_date date not null default (timezone('UTC',now()))::date,
 menu_name text not null, photo1_url text, photo2_url text, created_by uuid references public.canteen_staff(id) on delete set null,
 created_at timestamptz not null default now(), unique(meal_date)
);
create table if not exists public.school_fees (
 id uuid primary key default gen_random_uuid(), class_id uuid not null unique references public.classes(id) on delete cascade,
 total_amount numeric(12,2) not null check(total_amount>=0), updated_at timestamptz not null default now()
);
create table if not exists public.school_fee_payments (
 id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id) on delete cascade,
 installment_no integer not null check(installment_no between 1 and 15), amount numeric(12,2) not null check(amount>0),
 paid_at timestamptz not null default now(), note text, created_at timestamptz not null default now()
);
create index if not exists idx_fee_payments_student on public.school_fee_payments(student_id,installment_no);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('sjp-canteen','sjp-canteen',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true, file_size_limit=5242880;
drop policy if exists sjp_canteen_public_read on storage.objects;
create policy sjp_canteen_public_read on storage.objects for select using(bucket_id='sjp-canteen');
drop policy if exists sjp_canteen_auth_upload on storage.objects;
create policy sjp_canteen_auth_upload on storage.objects for insert to anon,authenticated with check(bucket_id='sjp-canteen');

create or replace function public.admin_create_parent(p_full_name text,p_phone text default null,p_relationship text default 'Père')
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid; v_code text;
begin
 if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
 if nullif(trim(p_full_name),'') is null then raise exception 'Nom du parent obligatoire.'; end if;
 if p_relationship not in ('Père','Mère','Tante','Oncle','Tuteur') then raise exception 'Type de parent invalide.'; end if;
 loop v_code:=public.make_code(4); exit when not exists(select 1 from public.parents where access_code_hash=public.hash_code(v_code)); end loop;
 insert into public.parents(full_name,phone,access_code_hash,relationship) values(trim(p_full_name),nullif(trim(p_phone),''),public.hash_code(v_code),p_relationship) returning id into v_id;
 insert into public.access_code_records(role,parent_id,full_name,phone,access_code) values('parent',v_id,trim(p_full_name),nullif(trim(p_phone),''),v_code);
 return jsonb_build_object('success',true,'parent_id',v_id,'parent_code',v_code,'relationship',p_relationship);
end $$;
grant execute on function public.admin_create_parent(text,text,text) to authenticated;
drop function if exists public.admin_create_parent(text,text);

create or replace function public.admin_create_student_for_parent(p_student_full_name text,p_class_id uuid,p_parent_id uuid,p_relationship text default 'Père')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
 if p_relationship not in ('Père','Mère','Tante','Oncle','Tuteur') then raise exception 'Type de parent invalide.'; end if;
 if not exists(select 1 from public.parents where id=p_parent_id) then raise exception 'Un parent valide doit être créé avant l''élève.'; end if;
 if not exists(select 1 from public.classes where id=p_class_id) then raise exception 'Classe invalide.'; end if;
 insert into public.students(full_name,class_id) values(trim(p_student_full_name),p_class_id) returning id into v_id;
 insert into public.student_parents(student_id,parent_id,relationship) values(v_id,p_parent_id,p_relationship);
 return jsonb_build_object('success',true,'student_id',v_id);
end $$;
grant execute on function public.admin_create_student_for_parent(text,uuid,uuid,text) to authenticated;

create or replace function public.admin_create_canteen_staff(p_full_name text,p_phone text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid; v_code text;
begin
 if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
 loop v_code:=public.make_code(5); exit when not exists(select 1 from public.canteen_staff where access_code_hash=public.hash_code(v_code)) and not exists(select 1 from public.parents where access_code_hash=public.hash_code(v_code)) and not exists(select 1 from public.teachers where access_code_hash=public.hash_code(v_code)); end loop;
 insert into public.canteen_staff(full_name,phone,access_code_hash) values(trim(p_full_name),nullif(trim(p_phone),''),public.hash_code(v_code)) returning id into v_id;
 insert into public.access_code_records(role,canteen_id,full_name,phone,access_code) values('canteen',v_id,trim(p_full_name),nullif(trim(p_phone),''),v_code);
 return jsonb_build_object('staff_id',v_id,'staff_code',v_code);
end $$;
grant execute on function public.admin_create_canteen_staff(text,text) to authenticated;

create or replace function public.admin_set_class_fee(p_class_id uuid,p_total numeric)
returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
 insert into public.school_fees(class_id,total_amount) values(p_class_id,p_total) on conflict(class_id) do update set total_amount=excluded.total_amount,updated_at=now();
end $$;
grant execute on function public.admin_set_class_fee(uuid,numeric) to authenticated;

create or replace function public.admin_record_fee_payment(p_student_id uuid,p_installment_no integer,p_amount numeric,p_note text default null)
returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid;
begin if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
 if p_installment_no not between 1 and 15 or p_amount<=0 then raise exception 'Tranche ou montant invalide.'; end if;
 insert into public.school_fee_payments(student_id,installment_no,amount,note) values(p_student_id,p_installment_no,p_amount,p_note) returning id into v_id; return v_id;
end $$;
grant execute on function public.admin_record_fee_payment(uuid,integer,numeric,text) to authenticated;

create or replace function public.parent_fee_summary(p_code text)
returns table(student_id uuid,student_name text,class_name text,total_due numeric,total_paid numeric,remaining numeric,payments jsonb)
language sql security definer set search_path=public as $$
 select s.id,s.full_name,c.name,coalesce(f.total_amount,0),coalesce(sum(p.amount),0),greatest(coalesce(f.total_amount,0)-coalesce(sum(p.amount),0),0),
 coalesce(jsonb_agg(jsonb_build_object('installment',p.installment_no,'amount',p.amount,'paid_at',p.paid_at) order by p.installment_no) filter(where p.id is not null),'[]'::jsonb)
 from public.parents pa join public.student_parents sp on sp.parent_id=pa.id join public.students s on s.id=sp.student_id join public.classes c on c.id=s.class_id
 left join public.school_fees f on f.class_id=s.class_id left join public.school_fee_payments p on p.student_id=s.id
 where pa.access_code_hash=public.hash_code(p_code) group by s.id,s.full_name,c.name,f.total_amount order by s.full_name
$$;
grant execute on function public.parent_fee_summary(text) to anon,authenticated;

drop function if exists public.login_with_access_code(text);
create function public.login_with_access_code(p_code text)
returns table(success boolean,role text,profile_id uuid,full_name text,message text)
language plpgsql security definer set search_path=public as $$
begin
 return query select true,'parent'::text,p.id,p.full_name,'Connexion réussie'::text from public.parents p where p.access_code_hash=public.hash_code(p_code);
 if found then return; end if;
 return query select true,'teacher'::text,t.id,t.full_name,'Connexion réussie'::text from public.teachers t where t.access_code_hash=public.hash_code(p_code);
 if found then return; end if;
 return query select true,'canteen'::text,c.id,c.full_name,'Connexion réussie'::text from public.canteen_staff c where c.access_code_hash=public.hash_code(p_code);
 if found then return; end if;
 return query select false,null::text,null::uuid,null::text,'Code incorrect.'::text;
end $$;
grant execute on function public.login_with_access_code(text) to anon,authenticated;

create or replace function public.canteen_save_daily_menu(p_code text,p_menu_name text,p_photo1 text,p_photo2 text)
returns jsonb language plpgsql security definer set search_path=public as $$ declare v_staff uuid; v_id uuid; v_date date:=timezone('UTC',now())::date;
begin select id into v_staff from public.canteen_staff where access_code_hash=public.hash_code(p_code);
 if v_staff is null then raise exception 'Code cantine invalide.'; end if;
 if exists(select 1 from public.canteen_meals where meal_date=v_date) then raise exception 'Le menu du jour et ses photos ont déjà été publiés. Les autres membres peuvent les consulter.'; end if;
 insert into public.canteen_meals(meal_date,menu_name,photo1_url,photo2_url,created_by) values(v_date,trim(p_menu_name),p_photo1,p_photo2,v_staff) returning id into v_id;
 return jsonb_build_object('id',v_id,'meal_date',v_date);
end $$;
grant execute on function public.canteen_save_daily_menu(text,text,text,text) to anon,authenticated;

create or replace function public.canteen_daily_menu(p_code text default null)
returns table(id uuid,meal_date date,menu_name text,photo1_url text,photo2_url text,created_by_name text)
language sql security definer set search_path=public as $$
 select m.id,m.meal_date,m.menu_name,m.photo1_url,m.photo2_url,c.full_name from public.canteen_meals m left join public.canteen_staff c on c.id=m.created_by order by m.meal_date desc limit 90
$$;
grant execute on function public.canteen_daily_menu(text) to anon,authenticated;

-- Purge automatique : programmer dans Supabase Cron chaque dimanche à 00:00 UTC :
-- select cron.schedule('purge-canteen-weekly','0 0 * * 0',$$delete from public.canteen_meals where meal_date < timezone('UTC',now())::date;$$);


alter table public.canteen_staff enable row level security;
alter table public.canteen_meals enable row level security;
alter table public.school_fees enable row level security;
alter table public.school_fee_payments enable row level security;
drop policy if exists sjp_admin_canteen_staff on public.canteen_staff;
create policy sjp_admin_canteen_staff on public.canteen_staff for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists sjp_admin_canteen_meals on public.canteen_meals;
create policy sjp_admin_canteen_meals on public.canteen_meals for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists sjp_admin_school_fees on public.school_fees;
create policy sjp_admin_school_fees on public.school_fees for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists sjp_admin_fee_payments on public.school_fee_payments;
create policy sjp_admin_fee_payments on public.school_fee_payments for all to authenticated using(public.is_admin()) with check(public.is_admin());
-- Purge des lignes et des objets Storage associés aux photos du menu.
create or replace function public.purge_old_canteen_meals()
returns void language plpgsql security definer set search_path=public,storage as $$
declare r record; v_path text;
begin
 for r in select photo1_url,photo2_url from public.canteen_meals where meal_date < (timezone('UTC',now()))::date loop
   foreach v_path in array array[
     nullif(split_part(coalesce(r.photo1_url,''),'/sjp-canteen/',2),''),
     nullif(split_part(coalesce(r.photo2_url,''),'/sjp-canteen/',2),'')
   ] loop
     if v_path is not null then delete from storage.objects where bucket_id='sjp-canteen' and name=v_path; end if;
   end loop;
 end loop;
 delete from public.canteen_meals where meal_date < (timezone('UTC',now()))::date;
end $$;
-- Supabase Cron (si l'extension est disponible) : dimanche à 00:00 UTC.
do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule('sjp-canteen-weekly-purge') where exists(select 1 from cron.job where jobname='sjp-canteen-weekly-purge');
  perform cron.schedule('sjp-canteen-weekly-purge','0 0 * * 0', 'select public.purge_old_canteen_meals();');
exception when others then
  raise notice 'Planification pg_cron non activée automatiquement : %', sqlerrm;
end $$;


-- Communiqués réservés au personnel de la cantine.
create table if not exists public.canteen_announcements(
 id uuid primary key default gen_random_uuid(),title text not null,body text not null,
 importance text not null default 'pas_urgent',created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
alter table public.canteen_announcements enable row level security;
drop policy if exists sjp_admin_canteen_announcements on public.canteen_announcements;
create policy sjp_admin_canteen_announcements on public.canteen_announcements for all to authenticated using(public.is_admin()) with check(public.is_admin());
create or replace function public.admin_send_canteen_message(p_title text,p_body text,p_importance text default 'pas_urgent')
returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid;
begin if not public.is_admin() then raise exception 'Accès Direction requis.'; end if;
 if nullif(trim(p_title),'') is null or nullif(trim(p_body),'') is null then raise exception 'Titre et message obligatoires.'; end if;
 insert into public.canteen_announcements(title,body,importance,created_by) values(trim(p_title),trim(p_body),p_importance,auth.uid()) returning id into v_id; return v_id;
end $$;
grant execute on function public.admin_send_canteen_message(text,text,text) to authenticated;
create or replace function public.canteen_announcements_for_staff(p_code text)
returns table(announcement_id uuid,title text,body text,importance text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select a.id,a.title,a.body,a.importance,a.created_at from public.canteen_announcements a
 where exists(select 1 from public.canteen_staff s where s.access_code_hash=public.hash_code(p_code)) order by a.created_at desc
$$;
grant execute on function public.canteen_announcements_for_staff(text) to anon,authenticated;
create or replace function public.admin_delete_conversation(p_conversation_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'Accès Direction requis.'; end if; delete from public.conversations where id=p_conversation_id; end $$;
grant execute on function public.admin_delete_conversation(uuid) to authenticated;

-- Interdiction structurelle d'enregistrer un élève sans responsable légal.
drop function if exists public.admin_create_student(text,uuid,text,text);
create or replace function public.enforce_student_parent_link()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_student_id uuid;
begin
  if tg_table_name='students' then v_student_id:=new.id; else v_student_id:=old.student_id; end if;
  if exists(select 1 from public.students where id=v_student_id)
     and not exists(select 1 from public.student_parents where student_id=v_student_id) then
    raise exception 'Chaque élève doit être rattaché à un parent ou tuteur.';
  end if;
  return null;
end $$;
drop trigger if exists trg_student_requires_parent on public.students;
create constraint trigger trg_student_requires_parent after insert on public.students
 deferrable initially deferred for each row execute function public.enforce_student_parent_link();
drop trigger if exists trg_student_cannot_be_orphaned on public.student_parents;
create constraint trigger trg_student_cannot_be_orphaned after delete on public.student_parents
 deferrable initially deferred for each row execute function public.enforce_student_parent_link();
