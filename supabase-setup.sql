-- ============================================================
-- Suivi des ventes — Salon en commission (équipe partagée)
-- À exécuter une seule fois dans l'éditeur SQL Supabase
-- ============================================================

-- 1) TARIFS — singleton (id = 1)
create table if not exists public.tarifs (
  id integer primary key default 1 check (id = 1),
  nu_prix numeric not null default 290,
  nu_cout numeric not null default 200,
  semi_prix numeric not null default 380,
  semi_cout numeric not null default 250,
  taux_defaut numeric not null default 0.15,
  frais_inscription numeric not null default 300,
  tva numeric not null default 0.19,
  updated_at timestamptz default now()
);
insert into public.tarifs (id) values (1) on conflict (id) do nothing;

-- 2) COMMERCIAUX
create table if not exists public.commerciaux (
  nom text primary key,
  taux numeric not null default 0.15,
  created_at timestamptz default now()
);

-- 3) VENTES
create table if not exists public.ventes (
  ref text primary key,
  date date,
  client text,
  commercial text,
  stand text,
  type text,
  surface numeric,
  prix numeric,
  cout_org numeric,
  statut text,
  bc text,
  acompte numeric default 0,
  taux numeric default 0.15,
  comm_payee text default 'Non',
  echeance date,
  comment text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 4) ENCAISSEMENTS
create table if not exists public.encaissements (
  id uuid primary key default gen_random_uuid(),
  date date,
  ref_vente text,
  client text,
  type text,
  montant numeric,
  mode text,
  created_at timestamptz default now()
);

-- 5) PROFILES (1 ligne par user, avec son rôle)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'responsable' check (role in ('superadmin','responsable')),
  created_at timestamptz default now()
);

-- À l'inscription d'un nouvel utilisateur, créer son profile (rôle: responsable)
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, role)
  values (new.id, new.email, 'responsable')
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.tarifs         enable row level security;
alter table public.commerciaux    enable row level security;
alter table public.ventes         enable row level security;
alter table public.encaissements  enable row level security;
alter table public.profiles       enable row level security;

-- Helper : rôle de l'utilisateur courant
create or replace function public.current_role()
returns text as $$
  select role from public.profiles where id = auth.uid();
$$ language sql stable security definer;

-- LECTURE : tout utilisateur connecté
create policy tarifs_read         on public.tarifs        for select to authenticated using (true);
create policy commerciaux_read    on public.commerciaux   for select to authenticated using (true);
create policy ventes_read         on public.ventes        for select to authenticated using (true);
create policy encaissements_read  on public.encaissements for select to authenticated using (true);
create policy profiles_read       on public.profiles      for select to authenticated using (true);

-- ECRITURE TARIFS / COMMERCIAUX : superadmin uniquement
create policy tarifs_write      on public.tarifs      for all to authenticated
  using (public.current_role() = 'superadmin')
  with check (public.current_role() = 'superadmin');

create policy commerciaux_write on public.commerciaux for all to authenticated
  using (public.current_role() = 'superadmin')
  with check (public.current_role() = 'superadmin');

-- VENTES : tous peuvent créer/modifier, seul superadmin peut supprimer
create policy ventes_insert on public.ventes for insert to authenticated with check (true);
create policy ventes_update on public.ventes for update to authenticated using (true);
create policy ventes_delete on public.ventes for delete to authenticated
  using (public.current_role() = 'superadmin');

-- ENCAISSEMENTS : idem
create policy enc_insert on public.encaissements for insert to authenticated with check (true);
create policy enc_update on public.encaissements for update to authenticated using (true);
create policy enc_delete on public.encaissements for delete to authenticated
  using (public.current_role() = 'superadmin');

-- PROFILES : seul superadmin peut changer les rôles
create policy profiles_update on public.profiles for update to authenticated
  using (public.current_role() = 'superadmin')
  with check (public.current_role() = 'superadmin');
