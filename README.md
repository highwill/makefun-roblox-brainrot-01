# Haunted Brainrot Manor

[![roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/highwill/makefun-roblox-brainrot-01/rank.svg)](https://make.fun/bounty/roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/highwill/makefun-roblox-brainrot-01/reward.svg)](https://make.fun/bounty/roblox-brainrot-01)

A 3D Roblox brainrot game for make.fun's **roblox-brainrot-01** bounty ($1,000, top 50
paid): a haunted manor at night where absurd ghost-house characters ride a haunted
hallway from the Manor Gate to the Crypt Gate, and players buy them, keep them on
their base, steal from each other, and run for cover when the Poltergeist Storm
sweeps the grounds. All original characters — nothing copied from any existing game.

## The numbers

- **36 brainrots, 8 rarities, 6 mutations.** Common x8, Uncommon x7, Rare x6, Epic x5,
  Legendary x4, Mythic x3, Secret x2, Brainrot God x1. Rates run $1/s (Dusty Doormat)
  to $3,000/s (The Overlord of the Manor); price is always rate x 50.
- **Mutations:** Golden x2 (5%), Rainbow x5 (2%), Diamond x10 (1%), Spectral x3 (3%),
  Molten x4 (2%), Frozen x1.5 (4%). A mutated brainrot earns more and costs more.
- **6 base plots x 8 slots**, a money tick every second, rebirth at $100,000 total
  earned (income x2 per rebirth, stacking to x8).

## How the loop works

1. Brainrots walk the red-carpet hallway from the Manor Gate. Touch one to buy it —
   it flies to your first free base slot and earns its rate every second.
2. Touch a brainrot on **someone else's** base to steal it. It rides above your head
   until you reach your own base pad, where it becomes yours.
3. The owner fights back with the **Slap Glove** (click it, or press **F**): a thief
   in range drops the brainrot, gets thrown back and stunned for 3s. **Lock Base**
   (**L**) locks your base for 60s (120s cooldown) — a locked base cannot be stolen from.
4. Every 150s the **Poltergeist Storm** hits for 20s: a fog wall sweeps the grounds,
   The Poltergeist stomps across the plaza, every brainrot spawned during the storm
   is mutated, and players caught outside their base are slowed and lose 5% of their
   cash. The conveyor pauses while the storm rages.
5. Every ~90s **The Ghost Burglar** slips out of the manor, walks to a random
   unlocked base, steals its best brainrot and runs for the exit. Whack him (F) to
   make him drop it — if he escapes, the loot is gone.
6. **Rebirth** (**R**) at $100,000 total earned resets cash and brainrots and doubles
   income forever (cap x8), adding a star to your base sign.
7. **Upgrades** (**U**): Speed Boots $5,000 (WalkSpeed 16 → 24), Golden Glove $2,500
   (whack cooldown 5s → 2s).
8. **Quests** (11, with cash rewards) and the **Prize Book** (**B**, the index):
   every brainrot you have ever owned is recorded, x/36 found, announced server-wide
   as it happens.

## The HUD

Top-center cash + income/s + rebirth multiplier; a live event banner with the storm
countdown; a quest panel (right) with progress and rewards; a Prize Book feed (left);
slots and index counters; a carrying banner; and five bottom buttons with keybinds —
LOCK [L] / WHACK [F] / UPGRADES [U] / REBIRTH [R] / INDEX [B] — over the strip
"36 BRAINROTS · 8 RARITIES · 6 MUTATIONS · THIEVES · LOCK · REBIRTH". Every
brainrot wears a floating label with its name, rarity, $/s and BUY price.

## The cast (36)

| Rarity | Brainrots |
| --- | --- |
| Common ($1–$8/s) | Dusty Doormat, Squeaky Floorboard, Wobbly Candelabra, Grumpy Gargoyle, Leaky Teapot Ghost, Moth-Eaten Curtain, Creaky Rocking Chair, Sleepy Dust Bunny |
| Uncommon ($10–$40/s) | Sir Spooksalot, Count Candelabra, Madame Mirror, Batty Bookshelf, Professor Portraits, Wailing Wallpaper, Captain Cobweb |
| Rare ($50–$150/s) | The Haunted Piano, Baron Von Bathtub, Lady Lampshade, Duke of the Dustpan, The Screaming Kettle, Marquis de Mantelpiece |
| Epic ($180–$450/s) | Phantom Butler, The Grand Chandelier, Witch of the West Wing, Sir Reginald Rattling Chains, The Poltergeist Piano |
| Legendary ($500–$1,200/s) | The Headless Horseman's Horse, Madame Zucchini's Crystal Ball, The Vampire Vacuum, King Coffin |
| Mythic ($1,500–$2,200/s) | The Ghost King, Dracula's Doorknob, The Manor Itself |
| Secret ($2,500–$2,800/s) | The Butler Did It, Grandma's Haunted Fruitcake |
| Brainrot God ($3,000/s) | The Overlord of the Manor |

## Layout

- `main.ts` (Node 22, stdlib only) hands the game in: it copies `game.rbxl`, `src/`,
  `screenshots/` and `PLAY.json` to `/output` and writes `/output/dossier.json` with
  the kit's vendored `vendor/makefun-roblox.ts`, unchanged.
- `game.rbxl` is the binary place Rojo builds from `src/` and `default.project.json`.
- `src/shared/BrainrotData.luau` — the cast, rarities, mutations, quests, tuning.
- `src/shared/BrainrotFactory.luau` — builds every character model from the data
  table (body + head + one accessory part + floating name tag), plus the Ghost
  Burglar and The Poltergeist.
- `src/server/GameServer.server.luau` — the whole loop, server-authoritative:
  conveyor, money tick, steal/carry, whack, lock, rebirth, upgrades, storm,
  burglar, quests, index.
- `src/server/BaseManager.luau` — the six base plots, slots, locks, signs.
- `src/client/Game.client.luau` — the HUD: cash bar, event banner, quest panel,
  Prize Book feed and panel, buttons, keybinds (all through ContextActionService).
- `OWNER-STEPS.md` — the exact owner checklist to publish, capture and submit.

Run it as the grader does, writing `out/` in place of `/output`:

    /home/hatch/workspace/bin/rojo build default.project.json --output game.rbxl
    mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

## ⚠️⚠️⚠️ STOP — READ THIS BEFORE SUBMITTING ⚠️⚠️⚠️

**The screenshots in `screenshots/` are STARTER PLACEHOLDERS. They show the kit's
grey square, NOT this game. They MUST be replaced with real captures from Roblox
Studio before submission — see `OWNER-STEPS.md` for the exact staged shots.**

**`PLAY.json` still has zeros (`place_id: 0`, `universe_id: 0`). It MUST be filled
with the real published place's ids before submission — see `OWNER-STEPS.md`.**

Until both are done, the pre-submit check fails `play_link` (expected) and the
entry is not submittable. Everything else in the repo is finished: the game builds,
the hand-in program runs, and the code is the entry.
