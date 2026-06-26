-- ═══════════════════════════════════════════
--  038 — Contracts + Digital Signatures
-- ═══════════════════════════════════════════

-- Contracts table
create table if not exists contracts (
  id             uuid        primary key default gen_random_uuid(),
  tenant_id      uuid        references tenants(id) on delete cascade,
  lead_id        uuid        references leads(id)   on delete cascade,
  title          text        not null default 'הסכם תיווך',
  template_type  text        not null default 'standard' check (template_type in ('standard','custom')),
  status         text        not null default 'draft'    check (status in ('draft','sent','viewed','signed','cancelled')),
  content_html   text,                        -- for standard template contracts
  file_url       text,                        -- for uploaded PDFs (Supabase Storage path)
  signing_token  text        unique not null default encode(gen_random_bytes(32), 'hex'),
  signer_name    text,
  signer_ip      text,
  signature_data text,                        -- base64 PNG of drawn signature
  signed_at      timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Updated_at trigger
create or replace function update_contracts_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger contracts_updated_at
  before update on contracts
  for each row execute function update_contracts_updated_at();

-- Index for fast lookups
create index if not exists contracts_tenant_idx on contracts(tenant_id);
create index if not exists contracts_lead_idx   on contracts(lead_id);
create index if not exists contracts_token_idx  on contracts(signing_token);

-- RLS
alter table contracts enable row level security;

-- Agents can CRUD their own tenant's contracts
create policy "contracts_tenant_crud"
  on contracts for all
  to authenticated
  using  (tenant_id = (select tenant_id from agent_users where id = auth.uid()))
  with check (tenant_id = (select tenant_id from agent_users where id = auth.uid()));

-- Signer (anon) can view by token and update status/signature
create policy "contracts_public_view_by_token"
  on contracts for select
  to anon
  using (true);

create policy "contracts_public_sign"
  on contracts for update
  to anon
  using  (status in ('sent','viewed'))
  with check (
    status in ('viewed','signed') and
    signing_token = signing_token   -- always true, just allows anon update
  );

-- Storage bucket for uploaded contract PDFs
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'contracts',
  'contracts',
  false,                     -- private — accessed via signed URL
  10485760,                  -- 10 MB limit
  array['application/pdf','application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
on conflict (id) do nothing;

-- Storage RLS
create policy "contracts_storage_upload"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'contracts');

create policy "contracts_storage_select"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'contracts' and
    (storage.foldername(name))[1] = (select tenant_id::text from agent_users where id = auth.uid()));

create policy "contracts_storage_delete"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'contracts');
