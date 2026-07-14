# Engine packs (downloadable NNUE networks)

This folder is the **hosted engine catalog** for Kingside. It is served as
static files by GitHub Pages and fetched at runtime by the app's
`EngineRegistry`. It lets players download additional **neural-net evaluation
files** (`.nnue`) and UCI option sets so they can try different "engines"
without an app update.

## Why this is allowed on iOS

A chess engine is executable code, and Apple's **App Store Guideline 2.5.2**
forbids downloading and running *new executable code*. So we never download an
engine binary. The Stockfish binary is compiled into the app at build time;
packs here carry only **DATA**:

- a neural-net file (`.nnue`) — applied via Stockfish's `EvalFile` UCI option, and
- optional UCI option overrides (`uci`) — applied via `set_option(...)`.

That is data + configuration, not code, which keeps in-app installs compliant.

## How it works end-to-end

1. `assets/engines/engines.json` sets `catalog_url` to
   `https://<user>.github.io/chess/engines/catalog.json`.
2. In **Settings → Chess Engine → Check for engine packs**, the app calls
   `EngineRegistry.fetch_catalog()` and lists every pack not already installed.
3. **Download** streams the pack's `net_url` to `user://engines/nets/<net>.part`,
   validates it against the declared `size_bytes` and `sha256`, then atomically
   renames it into place and saves the pack profile to `user://engines/<id>.json`.
4. The pack now appears under **Installed** and can be selected. The next move /
   review applies its net via `EvalFile` (see `AIEngine._apply_engine_profile`).

Everything works offline once installed.

## catalog.json format

```jsonc
{
  "version": 1,
  "packs": [
    {
      "id": "unique-id",                 // required, stable id
      "name": "Display Name",            // shown in the UI
      "engine": "stockfish",             // which bundled binary it runs on
      "author": "…",                     // optional, shown small
      "tagline": "…",                    // optional one-liner
      "description": "…",                // optional, shown on the download card
      "net": "my-net.nnue",              // filename saved under nets/
      "net_url": "https://…/nets/my-net.nnue",
      "size_bytes": 3519630,             // optional but recommended — validated
      "sha256": "…",                     // optional but recommended — validated
      "uci": { "Hash": "64" }            // optional UCI overrides (NOT strength;
                                         // strength stays under the difficulty system)
    }
  ]
}
```

## Adding a new network

1. Obtain a `.nnue` that is **compatible with this build's Stockfish version**
   (the NNUE architecture must match, or the engine refuses to load it). Verify
   it loads by pointing `EvalFile` at it in a headless run before publishing.
2. Copy it into `docs/engines/nets/`.
3. Compute its size and checksum:
   ```sh
   stat -f%z docs/engines/nets/<net>.nnue          # size_bytes
   shasum -a 256 docs/engines/nets/<net>.nnue       # sha256
   ```
4. Add a pack entry to `catalog.json` with those values.
5. Commit and push; GitHub Pages serves it automatically.

> Note: `uci` overrides here are configuration only. Bot *strength* is governed
> by the difficulty system (`AIEngine._configure_native_strength`), so a pack
> can't accidentally make a "Beginner" bot play at full strength.
