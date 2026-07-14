# Rating-system audit — "played like" + bot Elo accuracy

_Prepared June 23, 2026. Question: the Game Review "played like ~Elo" doesn't
feel accurate to chess.com, and the bot ratings may be unrealistic. Can we make
the ratings accurate to known scales? What does Lichess use?_

## TL;DR

There are **three different "ratings"** in the app, and they're not equally
trustworthy:

| Number | What it is | Verdict |
|---|---|---|
| **Accuracy %** (review) | Lichess's exact win%/accuracy formulas | ✅ Already accurate — keep it |
| **"Played like ~Elo"** (review) | A single game's accuracy mapped to an Elo | ⚠️ Inherently noisy — nobody does this well, chess.com included |
| **Bot Elo** (Beginner…Max) | Hand-tuned Stockfish strength labels | ❌ The real fixable inaccuracy |
| **Your rating** (profile) | Glicko-style update vs the bots | ➖ Sound math, but inherits the bots' miscalibration |

**What Lichess uses:** **Glicko-2** for player/bot ratings (rating + a
confidence "deviation" + volatility). For game quality it shows **Accuracy %**
(the exact method this app already uses) and historically ACPL — Lichess does
**not** show a per-game "played like Elo." That feature is a chess.com thing, and
chess.com themselves call theirs inaccurate and "a work in progress."

---

## The part that's already right: Accuracy %

The review's accuracy is computed with **Lichess's exact published curves**
(`AIEngine`):

- Win% `= 50 + 50·(2/(1+e^(−0.00368208·cp)) − 1)`
- Per-move accuracy `= 103.1668·e^(−0.04354·Δwin%) − 3.1669`
- Game accuracy = the average of a **volatility-weighted mean** and the
  **harmonic mean** of per-move accuracies (also Lichess's method — the harmonic
  mean is what makes blunders actually cost you).

This is as close to "what Lichess does" as it gets. No change needed.

## Why "played like ~Elo" feels off

`_performance_rating()` maps the blended accuracy to an Elo through hand-set
anchors (35%→300 … 99%→2850). Four reasons it won't match chess.com:

1. **One game is too little signal.** The code itself notes single-game rating
   estimates have R² ≈ 0.05–0.5. A calm game inflates accuracy; one sharp game
   deflates it — for everyone, at every level.
2. **chess.com's own number is acknowledged-broken.** Their estimate is openly
   "a work in progress," and players have shown the *same moves* yield *different*
   estimated Elo depending on the players' actual ratings — so it isn't a pure
   move-quality function. You can't match a target that isn't stable.
3. **Accuracy→Elo isn't a fixed mapping.** Accuracy is dominated by position
   sharpness, not just skill, so any accuracy→Elo curve is approximate.
4. **The anchors are guesses,** not fit to data.

**Recommendation (pick one):**

- **(a) Relabel it honestly** — show a *range* ("played like ~1000–1400") instead
  of false-precise "1013", and keep the existing "rough estimate" framing.
- **(b) De-emphasize it** — lead with Accuracy % (which is principled) and make
  the Elo secondary, the way Lichess does.
- **(c) Estimate over the last N games**, not one — more samples, less noise.
  (Your **profile Glicko rating already is** your multi-game performance number,
  so the per-game Elo is the redundant, noisy one.)

I'd do (a)+(b): a range, with accuracy as the headline.

## Why the bot ratings feel unrealistic (the real fix)

This is the one worth engineering. Two concrete problems in `DIFFICULTIES`:

1. **Stockfish's `UCI_Elo` runs well above human/chess.com scales.** It's
   calibrated to engine pools, so `UCI_Elo 1600` plays roughly like a chess.com
   ~1900. Your **Hard/Expert/Master/Max tiers feed the label straight in as
   `UCI_Elo`**, so they *overperform* their labels — a bot called "2000" plays
   noticeably stronger than a human 2000.
2. **The top tiers have no handicap.** Only Beginner→Hard get the `blunder`
   layer; Expert/Master/Max are raw `UCI_Elo`, so the overshoot is largest
   exactly where players notice "this 2000 feels like 2400."

Below `UCI_Elo 1320` (Stockfish's floor) the app uses Skill Level 0–5 + blunders,
but **Skill Level 0 still plays ~1100–1300**, so the low labels also drift high
without the blunder correction — which is why that layer exists.

**How to make them realistic — the principled path:**

1. **Add a `human_elo → uci_elo` calibration curve.** To make a bot *play like*
   chess.com 1600, you set `UCI_Elo` to something higher (~1900) per a mapping,
   instead of passing 1600 through. I can add this function seeded with a
   sensible curve.
2. **Extend the handicap to Expert+** (a small `blunder`/contempt or a capped
   `UCI_Elo`) so the top tiers stop overshooting.
3. **Measure, don't guess — a self-play calibration harness.** A headless script
   that plays each tier against reference opponents (a sweep of fixed `UCI_Elo`
   bots, or tiers round-robin), then derives each tier's **performance rating**
   from the results (standard TPR: opponent rating + score%→Elo). That produces
   *real numbers* to set the labels to — this is the only way to be truly
   "accurate to what we know." It needs to run many games (compute), so it's a
   tuning pass, but I can build the tool.

## Your profile rating

`PlayerData.record_result()` is a **Glicko-1-style** update (rating + rating
deviation; `q = ln10/400`, g-factor, opponent RD≈80). That's the same family as
Lichess's **Glicko-2** — solid. Two notes:

- It's missing Glicko-2's **volatility (σ)** term; adding it is a modest upgrade
  if you want parity with Lichess.
- `k_factor()` / `expected_score()` are **vestigial** (not used by the Glicko
  update) — remove or wire them to avoid confusion.
- **Most important:** your rating is earned against the bots, so it's only as
  honest as their labels. **Fix the bot calibration and your rating
  auto-calibrates** — that's the highest-leverage change.

## Recommended order of work

1. **Bot calibration** (biggest impact): add the `human_elo→uci_elo` mapping +
   handicap the top tiers + build the self-play harness to set real numbers.
2. **"Played like"**: switch to a range + lead with Accuracy %.
3. **Player rating** (optional): upgrade Glicko-1 → Glicko-2; delete the
   vestigial helpers.

I can implement #1's mapping + harness and #2 now; the harness then needs a
playtest run to lock the final tier numbers.

## Sources

- [Lichess — Chess rating systems (Glicko-2)](https://lichess.org/page/rating-systems)
- [Glicko rating system — Wikipedia](https://en.wikipedia.org/wiki/Glicko_rating_system)
- [chess.com forum — "estimated rating is inaccurate / work in progress"](https://www.chess.com/forum/view/general/how-is-the-estimated-elo-from-the-game-reviews-so-inaccurate)
- [Stockfish FAQ — UCI_Elo / UCI_LimitStrength behavior](https://official-stockfish.github.io/docs/stockfish-wiki/Stockfish-FAQ.html)
- Repo: `scripts/autoload/AIEngine.gd` (`_performance_rating`, `_aggregate_accuracy`, `DIFFICULTIES`), `scripts/autoload/PlayerData.gd` (`record_result`).
