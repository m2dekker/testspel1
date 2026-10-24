# Blackwake Isles

A mobile-first pirate strategy game (Flutter + Supabase), inspired by Ikariam.
Build a haven, produce resources, and (soon) trade and raid across the isles.

- Design and MVP scope: [`docs/DESIGN.md`](docs/DESIGN.md)
- Current sprint: [`docs/SPRINT-1.md`](docs/SPRINT-1.md)

## Status: Sprint 1

| Definition of Done | Status |
|---|---|
| User can register / log in (email + Google) | ✅ |
| User sees their haven | ✅ |
| User can build at least 3 different buildings | ✅ Lumber Camp, Plantation, Warehouse |
| Resources increase over time (also while offline) | ✅ |
| Data persists after refresh | ✅ |

## How it works

- **The server is the referee.** Players can only read their own data (Row Level
  Security). Every action (place, upgrade) is a Postgres function that checks the
  rules. See [`supabase/migrations`](supabase/migrations).
- **Offline progress for free.** Resources are settled lazily: when you come back, the
  server adds production for the time you were away and finishes constructions in
  the order they completed.
- **Offline demo mode.** Without Supabase settings the app runs the same rules locally
  and saves to the device. Handy for quick testing and previews.

## Run it

### 1. Offline demo (no setup)

```bash
cd app
flutter pub get
flutter run -d chrome
```

### 2. With Supabase (real accounts and multiplayer-ready data)

1. Create a project at [supabase.com](https://supabase.com).
2. Run the migration: paste
   `supabase/migrations/20261024000000_sprint1_havens.sql` into the **SQL Editor**
   and run it (or use `supabase db push` with the Supabase CLI).
3. Create `app/env.json` (it's git-ignored):

   ```json
   {
     "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
     "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..."
   }
   ```

   Both values are under **Project Settings → API**. The publishable key is
   safe to ship in the app.
4. Run: `flutter run --dart-define-from-file=env.json`

**Email login** works out of the box. By default Supabase asks new users to confirm
their email first; you can switch that off under **Authentication → Providers →
Email** while testing.

**Google login** needs a Google OAuth client:

1. In Google Cloud Console, create an OAuth client (type *Web application*) and add
   `https://YOUR-PROJECT.supabase.co/auth/v1/callback` as a redirect URI.
2. In Supabase, **Authentication → Providers → Google**: enable it and paste the
   client ID and secret.
3. In Supabase, **Authentication → URL Configuration**, add these redirect URLs:
   `io.blackwake.isles://login-callback` (mobile) and your web app's URL.

## Tests

```bash
scripts/test_db.sh          # database rules (needs local Postgres or Docker)
cd app && flutter test      # models, demo rules, and a full UI flow
cd app && flutter analyze
```

Both run automatically on every push (`.github/workflows/ci.yml`).

## Live demo on GitHub Pages (optional)

`.github/workflows/pages.yml` publishes the offline demo when `main` changes.
To turn it on: **Settings → Pages → Source: GitHub Actions**. The demo then appears at
`https://<your-user>.github.io/testspel1/`.

## Project layout

```
app/                     Flutter client
  lib/core/              config, theme, router, providers
  lib/features/auth/     login (Supabase or demo)
  lib/features/haven/    haven screen, models, game backends
supabase/migrations/     schema, RLS and game rules
supabase/tests/          SQL tests
scripts/test_db.sh       runs the SQL tests
docs/                    design and sprint documents
```
