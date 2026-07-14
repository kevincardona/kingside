# Cross-platform online play — one-time setup (~5 minutes)

Online matches between any two devices (macOS / Windows / Linux / Android /
iOS) run over **Firebase's free Spark tier**. There is no server to host or
maintain: the game talks straight to Firestore over HTTPS, and the free quota
(50K reads / 20K writes per day) is far more than a turn-based chess game
will ever use.

Apple-to-Apple play can additionally use Game Center (leaderboard, iMessage
invites) — that needs no setup beyond App Store Connect and works alongside
this.

## Steps

1. **Create a Firebase project**
   - Go to <https://console.firebase.google.com> → *Add project*.
   - Name it anything (e.g. `my-chess-app`). Disable Google Analytics (not needed).

2. **Enable Anonymous Authentication**
   - In the project: *Build → Authentication → Get started*.
   - *Sign-in method* tab → enable **Anonymous**.

3. **Create the Firestore database**
   - *Build → Firestore Database → Create database*.
   - Choose *production mode* and any region (pick one close to you).

4. **Publish the security rules**
   - *Firestore Database → Rules* tab.
   - Replace the contents with the rules from [`firestore.rules`](../firestore.rules)
     in this repo → *Publish*.

5. **Copy the two config values into the game**
   - *Project settings* (gear icon) → *General*:
     - **Web API Key** → `api_key`
     - **Project ID** → `project_id`
   - Paste them into [`online_service.cfg`](../online_service.cfg) at the repo
     root:

     ```ini
     [firebase]
     api_key="AIza...your-key..."
     project_id="my-chess-app"
     ```

That's it. Rebuild/export the game — the Online screen now shows
**Quick Match**, **Create Invite Code** and **Join with Code** on every
platform. Players are signed in anonymously and automatically on first use.

## Optional housekeeping

- **Auto-delete stale matches**: Firestore Console → *TTL* → create a TTL
  policy on collection `matches`, field `updated`. (TTL expects a timestamp
  field; if you skip this, abandoned docs just sit there — harmless at this
  scale.)
- **Quota check**: *Usage* tab shows reads/writes. A finished game is roughly
  80 writes and a few hundred reads (2.5s polling only while the board is
  open).

## How it works (for future reference)

- Anonymous auth → stable `uid` per install, cached in `user://online_identity.json`.
- One Firestore doc per match in `matches/{CODE}`; the 6-letter code doubles
  as the invite code shown to friends.
- Game state travels as a JSON payload `{v, moves:[uci...], fen, white_id}` —
  the same format the Game Center backend uses.
- Joining the Black seat uses an `updateTime` precondition, so two players
  racing for the same quick-match doc can't both get it.
- While a board is open the client polls the doc every 2.5 s; match lists
  refresh on demand.
