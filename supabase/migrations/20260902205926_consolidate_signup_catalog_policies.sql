-- The public signup catalogue policies already cover authenticated users, so
-- remove the older duplicate SELECT policies to keep one permissive path.
drop policy if exists "Authenticated users can view programmes" on public.programmes;
drop policy if exists "Authenticated users can view modules" on public.modules;
