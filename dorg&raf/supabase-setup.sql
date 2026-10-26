-- Run once in Supabase > SQL Editor. Replace ADMIN_EMAIL_HERE (twice below) with the admin's email.
-- IMPORTANT: first create the admin account yourself (Authentication > Users > Add user) BEFORE going live,
-- and keep "Confirm email" ON for the public so nobody can register the admin address.
create table public.orders(
  id text primary key,
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  status text not null default 'جديد',
  total numeric not null,
  data jsonb not null,
  created_at timestamptz not null default now());
alter table public.orders enable row level security;
create policy "place order" on public.orders for insert to anon, authenticated
  with check ((user_id is null or user_id = auth.uid()) and status = 'جديد');
create policy "read own or admin" on public.orders for select to authenticated
  using (user_id = auth.uid() or (auth.jwt()->>'email') = 'ADMIN_EMAIL_HERE');
create policy "admin update" on public.orders for update to authenticated
  using ((auth.jwt()->>'email') = 'ADMIN_EMAIL_HERE') with check ((auth.jwt()->>'email') = 'ADMIN_EMAIL_HERE');
create policy "admin delete" on public.orders for delete to authenticated
  using ((auth.jwt()->>'email') = 'ADMIN_EMAIL_HERE');

-- Sign in with phone number: looks up the account email by phone (last 10 digits).
-- Note: this lets anyone who knows a customer's phone learn that customer's email (they still need the password).
create or replace function public.email_for_phone(p text) returns text
language sql security definer set search_path = public, auth as $$
  select email::text from auth.users
  where length(regexp_replace(p,'\D','','g')) >= 8
    and right(regexp_replace(coalesce(raw_user_meta_data->>'phone',''),'\D','','g'),10) = right(regexp_replace(p,'\D','','g'),10)
  limit 1 $$;
grant execute on function public.email_for_phone(text) to anon, authenticated;

-- Google sign-in: Supabase > Authentication > Providers > Google (paste Client ID/Secret from Google Cloud Console),
-- then add your site URL under Authentication > URL Configuration > Redirect URLs.

-- Customer cancels own order only while status is new / processing (never after shipping).
create or replace function public.cancel_order(oid text) returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.orders set status = 'ملغي'
  where id = oid and user_id = auth.uid() and status in ('جديد','قيد التجهيز');
  get diagnostics n = row_count;
  return n > 0;
end $$;
grant execute on function public.cancel_order(text) to authenticated;

-- Email verification by CODE: Supabase > Authentication > Sign In / Providers > Email: keep "Confirm email" ON.
-- Then Authentication > Email Templates > "Confirm signup": replace the body with:
--   <h2>Your Dorg & Raf verification code</h2><p style="font-size:28px;letter-spacing:6px"><b>{{ .Token }}</b></p>
-- (use {{ .Token }}, NOT {{ .ConfirmationURL }}). Also set up custom SMTP (Resend / Brevo / Gmail) under
-- Project Settings > Authentication > SMTP, because Supabase's built-in mailer only sends a few emails per hour.