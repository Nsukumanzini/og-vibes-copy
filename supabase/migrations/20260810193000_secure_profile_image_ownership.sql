drop policy if exists "Students can upload images" on storage.objects;
create policy "Students upload own profile image"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'profile_images'
  and owner_id = (select auth.uid())::text
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Students can update images" on storage.objects;
create policy "Students update own profile image"
on storage.objects for update to authenticated
using (
  bucket_id = 'profile_images'
  and owner_id = (select auth.uid())::text
)
with check (
  bucket_id = 'profile_images'
  and owner_id = (select auth.uid())::text
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Students can delete images" on storage.objects;
create policy "Students delete own profile image"
on storage.objects for delete to authenticated
using (
  bucket_id = 'profile_images'
  and owner_id = (select auth.uid())::text
);
