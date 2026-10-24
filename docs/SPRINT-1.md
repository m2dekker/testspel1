# Blackwake Isles – First Sprint Backlog (Get Something Running Fast)

## Sprint Goal
Have a player log in, see a haven, place/upgrade a few buildings, and watch resources tick up.

### Priority Order

1. Flutter project setup + Supabase connection
2. Authentication (email + Google)
3. Basic profile creation
4. Create starting haven on login
5. Haven view screen (even if placeholder art)
6. List of available buildings
7. Place building → write to database
8. Simple resource ticking system (Edge Function or client-side simulation + sync)
9. Upgrade building with timer
10. Basic resource display

## Definition of Done for Sprint 1
- User can register/login
- User sees their haven
- User can build at least 3 different buildings
- Resources increase over time
- Data persists after refresh

## Decisions made during Sprint 1

- **Resource ticking:** server-side lazy settlement (`settle_haven()` in Postgres) plus
  client-side interpolation between fetches. No Edge Function needed.
- **Resources are columns on `havens`** instead of a separate `resources` table (it is 1:1).
- **Sprint 1 buildings:** Captain's Quarters (pre-built, produces a little gold as a
  stand-in for idle crew), Lumber Camp, Plantation (produces the island's luxury) and
  Warehouse (storage). The other six MVP buildings come in later sprints.
- **One of each building per haven, 8 plots per haven, one construction at a time.**
- **Placing a building** starts construction to level 1 with a short timer.
- **Crew assignment** is not in Sprint 1. Production is a fixed rate per building level.
