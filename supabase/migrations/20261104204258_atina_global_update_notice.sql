-- Reconstructed from the live public.atina_site_notice catalog and policies.
-- Restores the missing historical source required for clean database replay.

create table public.atina_site_notice (
  id integer not null,
  active boolean not null default false,
  message text not null default 'Estamos a fazer melhorias no ATINA. Poderão ocorrer interrupções temporárias.',
  updated_at timestamp with time zone not null default now(),
  constraint atina_site_notice_pkey primary key (id),
  constraint atina_site_notice_id_check check (id = 1)
);

alter table public.atina_site_notice enable row level security;

create policy atina_notice_read_all
  on public.atina_site_notice
  for select
  to anon, authenticated
  using (true);

create policy atina_notice_admin_insert
  on public.atina_site_notice
  for insert
  with check ((auth.jwt() ->> 'email') = 'lufime@gmail.com');

create policy atina_notice_admin_update
  on public.atina_site_notice
  for update
  using ((auth.jwt() ->> 'email') = 'lufime@gmail.com')
  with check ((auth.jwt() ->> 'email') = 'lufime@gmail.com');

grant select, insert, update on public.atina_site_notice to anon, authenticated;
grant all privileges on public.atina_site_notice to service_role;

insert into public.atina_site_notice (id) values (1);
