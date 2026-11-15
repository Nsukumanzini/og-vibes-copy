# Presentation mode

This copy launches the local presentation app from `lib/main.dart`.

- It uses bundled assets and sample content only.
- It does not initialize Supabase or Firebase, or request accounts, messages,
  notifications, or campus data from a server.
- Likes, event RSVPs, and posts are temporary in-memory demo interactions.
- The Supabase project files, Firebase web messaging setup, and backend client
  dependencies have been removed from this copy.

Build the web presentation with:

```sh
flutter build web --release --no-wasm-dry-run --base-href=/
```
