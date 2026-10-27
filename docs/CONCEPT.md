# Elsewhere (working title)

> Your life, elsewhere. A realistic AI clone of you lives its own life in real cities:
> cafés, day trips, nights out, money running low. You follow it live, read its
> journal, and nudge it. It grows from what it lives through and from what you like.

## The feeling

**Curious, entertained, and a bit jealous.** The clone does things you would put on
your own bucket list, and tells you about them as if you should have been there.

Inspiration: *Tabi Kaeru* (Travel Frog, 2018), a hugely popular game where a frog
travels without you and sends postcards. Elsewhere is that idea with AI, and with
*you* as the traveller.

## Decisions so far

| Topic | Decision |
|---|---|
| Who it's for | Everyone (with age limits and protected settings for minors) |
| Platform | Phone app first (iOS and Android), web for shared links |
| World | Real countries, cities, neighbourhoods and public landmarks. **Businesses are invented** (no reviews of real venues, no legal risk). |
| Time | Runs **3× real time**: a clone day passes in 8 real hours, a week's trip in about 2–3 real days. Nights pass faster. |
| Starting point | A short questionnaire sets personality, plus a name and a starting budget |
| Growth | Learns from its own experiences, your answers to its questions, and your reactions |
| Control | Nudges, not commands: answer its questions, react to its journal, suggest ideas, top up its money |
| Money | Virtual money only. It can run out; then it downgrades, finds work, or asks you for help |
| Other clones | Clones can meet anyone's clone, but **only clones talk to each other**, fully automatically. People never type messages to each other. |
| Look | **Realistic**, made with Hitchfield from your own photos |
| Business model | Paid unlock and/or subscription, cosmetics, and possibly sponsored (clearly labeled) places |

## How the clone lives

- **Traits** (each a scale): comfort-seeker ↔ adventurer, solo ↔ social, saver ↔ spender,
  eats to live ↔ foodie, early bird ↔ night owl, outdoorsy ↔ culture lover,
  city ↔ nature person, planner ↔ spontaneous.
- **Needs:** energy, mood, money.
- **Its day** runs in slots: breakfast, morning, lunch, afternoon, sunset, dinner, night,
  sleep. In each slot it picks an activity that fits its traits, needs and money.
- **Variety:** big experiences are not repeated within days, day trips at most one every
  three days, never on arrival day.
- **Organic growth:** experiences nudge traits slightly; a slow pull back toward who you
  made it keeps it recognisably *you*.
- **Bucket list:** starts with wishes that fit its personality and grows when it hears
  about new things. Ticking one off is a big moment.
- **Money trouble:** low money means hostels and street food; very low means it takes
  work (café shifts) or asks you to send money.
- **Meeting clones:** it runs into other people's clones; repeat meetings become
  friendships.

## Your influence

- **One question a day**, such as "Sintra or a surf lesson?". Answer before the deadline,
  or it follows its gut. Your choices teach it what you like.
- **Reactions** on journal entries ("Love this", "Meh") shift what it seeks out.
- **Rescue or not:** when it is broke, you decide whether to send money.
- Later: suggestions ("go see the northern lights"), which it may refuse if it doesn't
  fit its personality.

## Where AI is used

The clone has an **AI mind** and a **rule-based body**:

- **The mind (Claude), one check-in per clone day.** It gets the clone's personality,
  money, energy, bucket list, what you taught it and its last days, plus the menu of
  things it can do. In one call it returns:
  1. **A plan** for today and the next two days, one activity per part of the day, with a
     short note to you in its own voice, and sometimes the daily question for you.
  2. **Journal lines:** one sentence in its voice for each recent moment.
  3. **Meeting stories:** what happened when it met another clone.
- **The body (rules)** carries the plan out on the clock and keeps the books: money,
  energy, mood, beds, bucket-list ticks. If the plan no longer works (money ran low, too
  tired for a day trip), it changes plans on its own. Days without a plan fall back to
  personality-based instincts.
- **On tap:** postcards and diary entries.
- **Later:** realistic photos of key moments with Hitchfield.

Planning three days ahead means the clone keeps following its own plan while the app
is closed (at 3×, three clone days is about a real day).

**Cost rule:** AI runs at moments that matter, never continuously, so the cost per
player stays predictable.

## Social media and safety

- **Selfie check at sign-up:** only your own face can become your clone. Prevents cloning
  exes, celebrities or classmates. This is the biggest risk in the idea.
- **Everything AI-made is labeled** ("AI clone") in the app and in shared posts. Platforms
  and EU rules require labeling AI images of real people, and it avoids followers
  thinking you are really there.
- **Sharing:** the clone prepares a post and you tap Share (the phone's share sheet).
  Fully automatic posting is limited by the platforms (Instagram only for business or
  creator accounts, TikTok needs app review, X is paid), so it comes later, if at all.
- **Clone conversations never reveal personal details** about their owner (real name,
  address, workplace), even if the questionnaire knows them.

## Prototype: Lisbon

`prototypes/lisbon/index.html` is a playable single-file test:

- Questionnaire → personality → name, budget and test speed (3×, 30×, 300×)
- A simple avatar builder (skin, hair, colour, glasses or cap, shirt) as a placeholder
  for the realistic look; it appears in the header, as the map marker, and in drawn
  "sketch" photos of each highlight
- The clone lives in Lisbon on its own clock, also while the page is closed
- Live map of central Lisbon built from real OpenStreetMap data (streets, river,
  parks, the 25 de Abril bridge; © OpenStreetMap contributors, ODbL) with today's trail; day trips (Sintra, Cascais, Costa da
  Caparica) are pinned to the map edge
- Journal per day with spending, reactions, bucket-list ticks and clone meetings
- One question a day, money trouble with a rescue question
- AI check-in (Claude) when you open it: plans the next days (shown as "Today's plan"),
  writes journal lines in its voice and stories of clone meetings; a button when a new
  check-in is due while the page stays open
- AI-written postcards and diary entries (on tap)

## Open questions

- How many AI photos per day are affordable (Hitchfield credits per image)?
- When does the clone leave Lisbon, and who decides where it goes next?
- How do real friends' clones find each other (contacts, invite links, nearby)?
- What exactly is free and what is paid?
