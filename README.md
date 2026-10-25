# Blackwake Isles

A mobile-first pirate strategy game (Flutter + Supabase), inspired by Ikariam.
Build a haven, produce resources, and (soon) trade and raid across the isles.

- Design and MVP scope: [`docs/DESIGN.md`](docs/DESIGN.md)
- Sprints: [`docs/SPRINT-1.md`](docs/SPRINT-1.md), [`docs/SPRINT-2.md`](docs/SPRINT-2.md)

## Status

**Sprint 1: done.** Log in (email + Google), get a haven, build and upgrade with
timers, resources grow (also offline), everything persists.

**Sprint 2: done.** Crew and research:

| Definition of Done | Status |
|---|---|
| Crew grows over time (also offline) and stops at the housing cap | ✅ |
| Assign and remove workers; production follows the number of workers | ✅ |
| Idle crew produce gold | ✅ |
| Build a Tavern (faster crew growth) and an Academy (research points) | ✅ |
| Research all 4 Economy techs, and their bonuses apply | ✅ |
| See who else lives on your island | ✅ |
| Enforced by the server and covered by tests | ✅ |

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
2. Run the migrations in order: paste each file from `supabase/migrations/`
   (oldest first) into the **SQL Editor** and run it, or use `supabase db push`
   with the Supabase CLI.
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
