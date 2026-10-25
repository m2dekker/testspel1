# Blackwake Isles – Sprint 2: Crew and Research

## Sprint Goal
The haven comes alive: crew arrive over time, you decide who works where, idle crew
earn gold, and scholars unlock the first research.

### Priority Order

1. Crew: the Captain's Quarters houses crew, and crew grows over time up to that cap
2. Job assignment: put crew to work at the Lumber Camp, Plantation and Academy
3. Idle crew earn gold (replaces the Captain's Quarters' fixed gold)
4. Tavern: makes crew arrive faster
5. Academy: scholars produce research points
6. Research: the Economy tree (4 techs, unlocked in order)
7. Neighbours: see the other havens on your island (name and captain only)

## Definition of Done for Sprint 2
- Crew grows over time (also offline) and stops at the housing cap
- Player can assign and remove workers; production follows the number of workers
- Idle crew produce gold
- Player can build a Tavern and an Academy
- Player can research all 4 Economy techs and their bonuses apply
- Player can see who else lives on their island
- All of the above is enforced by the server and covered by tests

## Decisions

- **Production = workers × rate per worker.** Building level sets how many jobs there
  are (Lumber Camp: 8 per level, Plantation: 6, Academy: 6).
- **Crew growth is linear** (12 per hour, +12 per Tavern level) up to the housing cap
  (20 per Captain's Quarters level). Gold from idle crew is integrated exactly over
  that growth, so offline gold is correct.
- **Research points are per haven for now** (players only have one haven until
  colonization). Techs are spent instantly, Ikariam-style.
- **Rum consumption at the Tavern is not in this sprint.** The Tavern only speeds up
  growth. Serving rum for extra growth/morale comes with the happiness system.
- **Only the Economy tree** this sprint. Seafaring, Warfare and Intrigue need ships and
  combat, which come later.
- **Neighbours show only haven name and captain.** No resources or buildings.
