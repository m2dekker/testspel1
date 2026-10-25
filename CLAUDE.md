# Blackwake Isles

A mobile-first Flutter + Supabase pirate strategy game, inspired by Ikariam.

- Full design: `docs/DESIGN.md` (single source of truth for features and scope)
- Sprints: `docs/SPRINT-1.md` (done), `docs/SPRINT-2.md` (current)

## Instructions for Claude

- Always prioritize MVP scope. Do not add features outside the defined MVP.
- Prefer simple, working solutions over perfect architecture in early stages.
- When writing Flutter code, use modern practices (Riverpod, go_router, clean folder structure).
- When writing Supabase code, use Row Level Security from the beginning.
- Keep the code easy to understand and well-commented.
- When in doubt about design decisions, choose the option that gets a playable version faster.
- Ask before implementing anything that expands scope.

## Current focus

Sprint 2: crew, jobs, Tavern, Academy and the Economy research tree.

## Architecture rules

- **The server is the referee.** Clients can only read their own data (RLS). Every game
  action goes through a `security definer` Postgres function (RPC) that checks the rules.
  There are no insert/update/delete policies for players.
- **Resources are settled lazily.** A haven stores resource amounts plus
  `resources_updated_at`. `settle_haven()` adds production for the elapsed time (and
  completes finished constructions in order) whenever an action or read happens. This is
  what makes offline progress work.
- **Every new migration revokes execute on all public functions and re-grants only the
  RPCs.** Supabase grants new functions to `anon`/`authenticated` by default.
- **The offline demo mirrors the SQL rules** (`app/lib/features/haven/data/demo_game_backend.dart`).
  Change both together; their tests mirror each other.
- **Game data lives in the database.** Building stats are in `building_types`, and costs
  and times are computed by `building_cost()` / `build_seconds()` in SQL. The client
  displays what the server sends and never duplicates game formulas.
- **The client only interpolates.** It ticks resources locally between fetches using the
  rates the server returned, and refetches when a construction finishes.

## Layout

- `supabase/migrations/`: database schema, RLS and game functions
- `supabase/tests/`: SQL test script (run with `scripts/test_db.sh`)
- `app/`: the Flutter client (`lib/core`, `lib/features/<feature>`)

## Commands

```bash
# database tests (local Postgres, or Docker)
scripts/test_db.sh

# Flutter
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --dart-define-from-file=env.json
```
