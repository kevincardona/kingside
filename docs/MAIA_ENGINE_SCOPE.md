# Scope: Maia (human-like) engine as a second backend

**Goal:** give players genuinely different *playstyles* — not "alternate Stockfish
nets" (which are imperceptibly different), but **Maia**, which plays the moves
*humans at a given rating actually play*, blunders and all. Maia-1100 / 1500 /
1900 feel like real opponents at those levels and are exactly the "engines people
love" you're after. The downloadable-pack system you already have would deliver
the Maia nets; this doc scopes the engine itself.

## Why Maia can't reuse the Stockfish path
Maia is a **Leela (lc0) network**, not a Stockfish net — different engine, different
math. Stockfish does alpha-beta search with a small NNUE eval; Maia is a **CNN that
predicts the human move directly** and plays at **`nodes=1`** (one network
evaluation per move, *no search*). The good news in that: you don't need a fast
search engine on the phone — just **one neural-net forward pass per move**, which
is cheap. The cost is on-device CNN *inference*.

## How it slots into what exists
You're already set up for this — the abstraction is there:
- `AIEngineBackend` (interface) with `AINativeBackend` wrapping the `ChessEngine`
  GDExtension class. A Maia engine is **a second backend** (`MaiaBackend`).
- `EngineRegistry` already models multiple engines + downloadable nets. Maia
  entries are just catalog packs with `"engine": "maia"` + a net file; the
  validate/download/install/select flow is **done**.
- `AIEngine._pick_backend()` / `_apply_engine_profile()` would route to the Maia
  backend when the selected engine's `engine` is `"maia"`, else Stockfish.

So the **app-side plumbing is ~90% there.** The work is the native inference.

## Three ways to do the inference (the real decision)
| Path | What | Pros | Cons |
|---|---|---|---|
| **A. Vendor full lc0** | Compile lc0 into the GDExtension like Stockfish | Proven, full features | lc0's build (Meson + a compute backend) is **much** harder to cross-compile than Stockfish; big binary; overkill for nodes=1 |
| **B. Hand-write minimal inference** | A small C++ forward-pass for the Leela CNN (no deps) | Tiny footprint, no new build deps | You implement + validate the net math yourself — exacting, easy to get subtly wrong |
| **C. Bundle a small inference runtime** ⭐ | Convert Maia → ONNX, run via ONNX Runtime Mobile (or ncnn/TFLite); you write only the board→planes encoding + move decoding | Runtime handles the matrix math + is prebuilt per-platform; modest binary; no lc0 build hell | One new third-party dep to integrate into the CMake build |

**Recommended: Path C.** At `nodes=1` you just need one inference; a mobile runtime
does that reliably, and you only own the chess-specific glue (input encoding +
policy decoding), not the neural-net kernels.

## Work breakdown (Path C)
1. **Net conversion (offline, one-time per Maia net):** `lc0 leela2onnx` (or the
   maia-chess tooling) → an `.onnx` per level. Host them via the same catalog
   (they're ~10-50 MB; fine on a GitHub Release).
2. **`MaiaBackend` (C++ in the GDExtension):**
   - Link ONNX Runtime (prebuilt static libs exist for iOS arm64 / Android arm64 /
     macOS / Windows) into the existing CMake target.
   - **Board → input tensor:** Leela's 112-plane encoding (piece planes for the
     last 8 positions, castling, side-to-move, rule50, etc.). Well-documented but
     must match exactly or it plays nonsense.
   - **Run inference**, read the **policy head** (1858-move encoding), mask to legal
     moves, pick the argmax (or sample for variety). That's the move.
   - Expose the same `bestmove(fen, …)` surface the backend interface uses.
3. **Routing:** register the backend, add `engine:"maia"` handling in `AIEngine`.
4. **Catalog:** add Maia packs (1100/1500/1900) pointing at the `.onnx` nets +
   sizes/sha256. The download UI already lists them in the scrolling picker.
5. **Validation:** compare this backend's move choices against reference Maia
   (lc0 + the same net at nodes=1) on a few hundred positions — they must match.
6. **Per-platform builds:** wire ONNX Runtime into each target in
   `build_stockfish_extension.sh` / CMake (iOS xcframework, Android .so, macOS,
   Windows). This is the fiddliest part.

## Effort & risk (honest)
- **Effort:** ~1–2 weeks of focused work for someone comfortable with C++, a bit of
  ML inference, and the existing GDExtension build. The chess glue is a few hundred
  lines; most of the time goes to (a) wiring the runtime into 4 platform builds and
  (b) getting the input encoding bit-exact.
- **Main risks:** input-encoding mismatch (plays garbage until exactly right);
  ONNX Runtime mobile binary size (~5–15 MB/platform) and build integration; iOS
  app-size/review. None are blockers, all are real.
- **Licensing:** Maia weights are open (the maia-chess project, by CSSLab); lc0 is
  GPLv3 (only its tooling is used offline for conversion, not shipped). Fine to ship
  the converted nets; attribute Maia.

## Suggested phasing
1. **Desktop prototype first:** `MaiaBackend` + ONNX Runtime on macOS only, load
   Maia-1500, validate moves vs reference. Proves the encoding/decoding before any
   mobile build pain. (~half the effort, all the risk retired.)
2. **Port to iOS/Android** once desktop matches reference.
3. **Ship 3 Maia packs** via the catalog; market it ("play human-like bots at your
   level").

## Bottom line
The *app* is ready for a second engine — the registry, downloads, picker, and
backend interface all exist. The new work is a native **Maia inference backend**,
best done by bundling a small ONNX runtime (Path C) and owning only the chess
encode/decode. It's a real ~1–2 week project, best de-risked with a macOS-only
prototype first. The payoff is the feature you actually want: a scrolling list of
**human-like opponents at different levels** that people genuinely love.
