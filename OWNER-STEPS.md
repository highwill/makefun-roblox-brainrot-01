# Owner steps — Haunted Brainrot Manor (roblox-brainrot-01)

Everything here happens on **your own device**. Roblox Studio is **not installed**
on the Linux build machine, so none of this can be done there — open Studio on your
own computer and work through this list in order.

## 0. The play code (already fetched for you)

Put this exact code in the experience description in step 2:

```
makefun-island-drizzle-mulberry
```

It is play code **0** of your 4 for roblox-brainrot-01. If Roblox refuses the
description with it, fetch another with
`node cli/makefun.mjs check --repo /home/hatch/workspace/make-fun/roblox-brainrot-01 --play-code 1`
from the kit directory.

## 1. Sanity-check the repo (optional, on the build machine)

```bash
cd /home/hatch/workspace/make-fun/roblox-brainrot-01
/home/hatch/workspace/bin/rojo build default.project.json --output game.rbxl
mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
```

## 2. Publish the game from Studio

1. In Studio, open `game.rbxl` from this repo.
2. **File → Publish to Roblox As…** — create a **new Public experience** on your
   Roblox account (already confirmed publish-ready: account ≥ 2 days old, age
   check passed).
3. In the experience description, paste the play code from step 0 **exactly as it
   stands** — any one of your codes passes.
4. Set the genre and answer the content questions.
5. **File → Game Settings → Basic Info** — confirm it is Public.

## 3. Fill in PLAY.json

In this repo, replace the zeros in `PLAY.json` with the real ids:

```json
{"url": "https://www.roblox.com/games/<placeId>", "place_id": <placeId>, "universe_id": <universeId>}
```

- `place_id` is the number in the play link.
- `universe_id` is the number after `experiences/` in the experience's address on
  the Creator Dashboard, or `game.GameId` in Studio (`game.PlaceId` is the place id).
- Both must be positive whole numbers. Then rebuild (`rojo build …`) and re-run
  `main.ts` so the new ids land in the output.

## 4. Capture the 3 screenshots (1280x720, each ≤ 256 KiB)

Capture while the game is **running** in Studio (a capture tool can take focus from
Studio, and a game that pauses when Studio loses focus is captured paused). Keep
the HUD text clear of the top-left corner — Roblox's menu buttons sit there.

**Stage every shot dense — a sparse cover ranks low. Before capturing, buy several
brainrots so the bases are full, and capture mid-storm with the event banner live.**

- **1-start.png — the cover / first thumbnail. Make it the densest shot:** wide
  plaza shot from the spawn point looking toward the manor facade, **mid Poltergeist
  Storm** (wait for the 150s timer — the banner reads "POLTERGEIST STORM! EVERY
  BRAINROT IS MUTATED"), The Poltergeist stomping, brainrots on bases with their
  floating labels, full HUD (cash, quest panel, Prize Book feed, bottom buttons).
  This file is also uploaded as the first thumbnail in step 5.
- **2-play.png — buying / carrying:** your character touching a brainrot on the
  hallway to buy it, or carrying a stolen brainrot with the orange "CARRYING: …
  RUN TO YOUR BASE!" banner showing.
- **3-end.png — storm + burglar + full bases:** the Ghost Burglar in the manor
  (wait for a ~90s visit — the red "THE GHOST BURGLAR IS IN THE MANOR!" banner),
  bases full of brainrots, storm fog sweeping the grounds.

If a capture is over 256 KiB, re-encode it as a JPEG (or scale it down) until it
fits — long side at most 1280, short side at least 480. Replace the three files in
`screenshots/` — **the files there now are starter placeholders showing a grey
square and must not be submitted.**

## 5. Icon + thumbnail on the Creator Dashboard

1. Upload a **512x512 icon** for the experience.
2. Upload **`1-start.png`** as the **first thumbnail** — it must be the same picture
   as `screenshots/1-start.png`.
3. Wait until both show past review.

## 6. Tell the parent agent

When steps 2–5 are done, tell the parent agent. It runs the pre-submit check
(`node cli/makefun.mjs check --kit . --repo /home/hatch/workspace/make-fun/roblox-brainrot-01 --worktree`
from the kit dir), pushes the repo, and runs the submit. Do **not** submit from here
yourself — submission needs the recorded session and the API key the parent holds.
