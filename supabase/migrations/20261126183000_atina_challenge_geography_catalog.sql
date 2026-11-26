-- Catálogo geográfico normalizado para desafios ATINA.
-- Preparação apenas: não popula catálogos nem migra geographic_scope automaticamente.
-- Aplicar somente após revisão e autorização explícita para alterar a produção.

create table if not exists private.atina_countries (
  country_id bigint generated always as identity primary key,
  iso2 char(2) not null unique
    check (iso2 ~ '^[A-Z]{2}$'),
  name_pt text not null
    check (char_length(btrim(name_pt)) between 1 and 120),
  continent text
    check (continent is null or char_length(btrim(continent)) between 1 and 80),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.atina_regions (
  region_id bigint generated always as identity primary key,
  country_id bigint not null
    references private.atina_countries(country_id) on delete restrict,
  code text,
  name_pt text not null
    check (char_length(btrim(name_pt)) between 1 and 160),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint atina_regions_country_name_unique unique (country_id, name_pt),
  constraint atina_regions_id_country_unique unique (region_id, country_id)
);

create table if not exists private.atina_challenge_geography (
  challenge_id integer primary key
    references private.atina_challenges(challenge_id) on delete cascade,
  scope_type text not null
    check (scope_type in ('country', 'region', 'international', 'universal')),
  country_id bigint,
  region_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint atina_challenge_geography_country_fk
    foreign key (country_id)
    references private.atina_countries(country_id) on delete restrict,
  constraint atina_challenge_geography_region_country_fk
    foreign key (region_id, country_id)
    references private.atina_regions(region_id, country_id) on delete restrict,
  constraint atina_challenge_geography_scope_shape_check
    check (
      (scope_type = 'country' and country_id is not null and region_id is null)
      or (scope_type = 'region' and country_id is not null and region_id is not null)
      or (scope_type in ('international', 'universal') and country_id is null and region_id is null)
    )
);

create index if not exists atina_regions_country_active_idx
  on private.atina_regions(country_id, active, name_pt);
create index if not exists atina_challenge_geography_country_idx
  on private.atina_challenge_geography(country_id)
  where country_id is not null;
create index if not exists atina_challenge_geography_region_idx
  on private.atina_challenge_geography(region_id)
  where region_id is not null;

alter table private.atina_countries enable row level security;
alter table private.atina_regions enable row level security;
alter table private.atina_challenge_geography enable row level security;

revoke all on table private.atina_countries, private.atina_regions,
  private.atina_challenge_geography from public, anon, authenticated;

comment on table private.atina_countries is
  'Controlled country catalogue for administrative challenge geography.';
comment on table private.atina_regions is
  'Country-scoped region catalogue for administrative challenge geography.';
comment on table private.atina_challenge_geography is
  'Optional normalized geographic classification; existing geographic_scope values remain untouched until explicitly mapped.';
