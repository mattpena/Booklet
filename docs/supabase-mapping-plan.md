# Optional shared mapping layer

V1 uses `LocalMappingRepository`, so there is no backend to configure. The app only knows the `MappingRepository` protocol; a later Supabase implementation can replace it without changing Spotify detection, release resolution, or the reader UI.

The shared table should contain curation data only. It must never contain Spotify history or local listening activity.

## Suggested table

```sql
create table public.album_release_mappings (
  local_album_key text primary key,
  musicbrainz_release_id uuid not null,
  confidence smallint not null default 100 check (confidence between 0 and 100),
  source text not null default 'curated',
  verified_at timestamptz not null default now()
);

alter table public.album_release_mappings enable row level security;

revoke all on table public.album_release_mappings from anon, authenticated;
grant select on table public.album_release_mappings to anon, authenticated;

create policy "Mappings are public read-only reference data"
on public.album_release_mappings
for select
to anon, authenticated
using (true);
```

There are intentionally no client insert, update, or delete policies. Curated writes should use trusted server-side tooling with a Supabase secret key. A distributed Mac app should contain only a publishable key and read the one row matching the normalized album key.
