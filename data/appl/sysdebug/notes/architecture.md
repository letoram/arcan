# Arcan codebase architecture map

Coordinator notes — research output that anchors Part I Ch 0
("Architecture") of the sysdebug appl. Consult before writing any
chapter that names a subsystem; do not paraphrase generically when
you can name a real path. Last refreshed 2026-05-01.

A display server, window manager, and Lua/JavaScript shell stack
implemented largely in Zig with a modern self-hosted backend.
Target: aarch64 Asahi (M-series MacBooks).

## 1. Top-Level Directories

| Path | What It Is | Notes |
|------|-----------|-------|
| `src/` | Engine + frameservers + shmif library | Core C / Zig / mixed codebase |
| `data/` | Lua appls: durian desktop, lash shell, hem builtins | Bundled Lua modules installed to `zig-out/share/arcan/appl/durian/` |
| `build_llvm/` | Standalone Zig project for LLVM-implicating targets | qtarcan, gamescope, llama-cli, afsrv_bun; kept separate so selfhost doesn't see them |
| `.fossil` | Fossil DB — single source of truth for tickets (~103 as of 2026-05-02). Read via `bugs show <id>` hem builtin or `fossil sql ...`. The legacy `bugs/` markdown folder was deleted per ticket 0150. |
| `docs/` | Architecture/migration docs | `selfhost_plan.md`, `auto_arch_plan.md`, `fossil_migration_report.md`, `hem_visual_agent/` |
| `tools/` | Utilities: auto-arch orchestrator, refactor harnesses, test runners | `auto-arch/`, `refactor/`, `selfhost/`, `test/`, `bun-shmif/` |
| `reference/` | Upstream arcan & durian sources for reference | `durian-upstream/` (master branch; used as external docs) |
| `build.zig` | Main build script (Zig 0.15.2) | Entry point; delegates LLVM targets to `build_llvm/` |
| `build.zig.zon` | Dependency lock; ffmpeg, sqlite3, TrueType | LLVM deps kept in `build_llvm/build.zig.zon` |
| `CLAUDE.md` | Agent operating manual | Load-bearing visibility rules; hem integration; TS bindings |
| `zig-out/` | Install root after `zig build install` | `bin/` (arcan, afsrv_*), `lib/` (libarcan_shmif.a, libarcan_a12.a), `share/arcan/appl/durian/` |

**Noise (build artifacts):** `.o`, `.a` files at root from earlier
build attempts; `anet_session_*` temp files; `.fossil`, `.fslckout`
(Fossil VCS state); `.zig-cache`, `.claude/` (harness state).

## 2. Engine + Frameservers

### Engine entry point

`src/engine/arcan_main.zig` — main event loop. Booted by arcan
binary as `main(argc, argv)`, spins the compositor, drives Lua VM,
polls frameserver events.

### Shared-memory interface (shmif)

- Header: `src/shmif/arcan_shmif.h` (C ABI)
- Zig wrappers: `src/shmif/shmif_types.zig`
- Subsegment support: `src/shmif/arcan_shmif_sub.zig`
- Debug interface: `src/shmif/arcan_shmif_debugif.zig`
- Library: `libarcan_shmif.a`

What it exposes: shared-page protocol for frameserver↔engine comms;
pixel buffer, events (input, resize, video signal), subsegments
(nested windows).

### Frameservers (afsrv_*)

Each has `default/` (main Zig) and `embed/` (terminal-only, for
in-durian bootstrapping):

| Frameserver | Location | Role |
|-------------|----------|------|
| **afsrv_terminal** | `src/frameserver/terminal/` | TUI host; runs shell/editors/hem/hem; linked to libarcan_tui |
| **afsrv_decode** | `src/frameserver/decode/` | Video decode (ffmpeg-backed); demux + codec bridge |
| **afsrv_encode** | `src/frameserver/encode/` | Video encode output; recording, streaming |
| **afsrv_net** | `src/frameserver/net/` | a12 network protocol client; streams frameserver windows over LAN |
| **afsrv_bun** | `src/frameserver/bun/` → `build_llvm/build_afsrv_bun.zig` | TypeScript host via Bun (Phase 3); shmif C bindings + JSC integration; **built in build_llvm** |
| **afsrv_game** | `src/frameserver/game/` | Game input ↔ arcan bridge |
| **afsrv_probe** | `src/frameserver/probe/` | Device introspection (GPU caps, audio) |
| **afsrv_avfeed** | `src/frameserver/avfeed/` | Audio/video pump for Lua-driven A/V pipelines |

**Trap:** afsrv_bun is NOT in the top-level build.zig; must
`cd build_llvm && zig build afsrv-bun-link` (link-only; obj emitted
by Bun's own build). `BUILD_PROFILE=release` forced on Asahi due to
JSC strict-`<` ASSERT bug on 16K pages.

### a12 protocol

- Core: `src/a12/a12.zig` (handshake, stream mux), `a12_encode.zig`
  (payload packing), `a12_decode.zig` (parse), `a12_types.zig`
  (Zig type layer over C structs)
- Crypto: `src/a12/crypto_shim.zig` (openssl wrapper);
  `a12_int.h` (state machine internals)
- External deps: blake3 hash, zstd compression, mono protocol
  (partial TLS simulation for offline mode)
- Version: 0.1.0

### posix_libc shim

- Location: `src/platform/posix/libc.zig`
- What: hand-written Zig module replacing @cImport for POSIX libc
  (pthread, select, epoll, socket, file ops). Part of T46 sweep to
  purge @cImport.
- Connected to: zig-SH-fork self-host effort. Referenced in
  `build.zig`'s createAnetTypesMod helper (line 186 onwards).
- Status: functional; enables Zig-only builds without LLVM-era libc
  binding overhead.

## 3. Lua-Side Appls + Builtins

### Bundled Applications (`data/appl/`)

Installed to `zig-out/share/arcan/appl/durian/`:

| Appl | Location | Purpose |
|------|----------|---------|
| **welcome** | `data/appl/welcome/` | First-run greeting + theme picker |
| **console** | `data/appl/console/` | Lua REPL for engine introspection |
| **callgraph** | `data/appl/callgraph/` | Binary call-graph visualization |
| **texttest** | `data/appl/texttest/` | TUI rendering test harness |
| **vktest** | `data/appl/vktest/` | GPU (Vulkan) smoke test |
| **sysdebug** | `data/appl/sysdebug/` | THIS APPL |

### Lash Shell

- Location: `data/lash/`
- Entry: run via `/global/open/lash` durian menu
- Role: command dispatcher; loads `hem_dev` verbs on `builtin
  dev`. Terminal or afsrv_bun hosted.

### hem_dev Builtins (`data/lash_builtins/hem_dev/`)

All Lua, installed at build time. Grouped by family:

**System / Debug:**
- `status` — live "what's happening now" title-bar spread
- `ps [filter]` — /proc walker, no shell dependency
- `procfs <pid> <view>` — fd / threads / maps / status introspection
- `proc <subcommand>` — process tree walker (Phase 1.1, bug 0118)
- `cores [list|info|debug|bt]` — coredump browser + backtrace
- `metrics [pid|name]` — live resource usage (CPU, mem, fd)
- `engine [introspect|watch] [name|*]` — read live arcan engine globals

**Files / Search:**
- `read <file>` — render file in a job cell (visible editor)
- `edit <file> <pat> <rep>` — in-place edit via Lua patterns
- `write <file> <content|#N|clipboard:>` — create/overwrite file
- `find <dir> [pat]` — recursive walk, clickable spread
- `grep <pat> <file>` — pattern search, spreadsheet output
- `glob <pat> [dir]` — single-dir glob, clickable
- `head <file> [N]` / `tail <file> [N]` — slice lines
- `wc <file>` — 1×3 spread (lines/words/bytes)
- `fs <subcommand>` — small file-management primitives (bug 0118)
- `hash <path...> [algo]` — md5/sha256/blake3 + dup detection

**Build / Compile:**
- `compile <target> [-Dopt]` — Zig build with live error spread
- `zigbuild [target] [-Dopt]` — alias + legacy compatibility
- `atlas` — build atlas (E.1 auto-arch surface)
- `refactor` — drive tools/refactor/ Zig binaries from hem
- `selfhost` — drive zig-SH-fork self-host attempt

**Code Analysis:**
- `disasm <obj.o> [--func <name>]` — asm ↔ source spread
- `dwarf` — addr → DIE resolver (Group D.1)
- `dietree` — Compilee DIE-tree spread (Group D.2)
- `diegraph` — DWARF DIE relation graph (E.5)
- `sym <binary> [name=pat] [strings=pat] [disasm=sym]` — nm + strings + objdump
- `snippet <bug_id>` — extract snippet from bug ticket

**Time / Data Analysis:**
- `time` — time-bucket aggregator (C.1) + E.3 record-replay scaffold
- `hilbert` — Hilbert-curve build-graph spatial map
- `memcloud` — live mapping point cloud (E.2)
- `snippets [bug_id]` — template snippets from issues

**Introspection:**
- `git [verb] [args]` — VCS state
- `fossil status/log/diff` — version control
- `bugs show <id>` — render bug ticket markdown
- `logwatch <file> [filter] [emit] [tail]` — bucket panic/atlas/font/orphan logs
- `sheet` — letoram-aligned spreadsheet patterns from metadata
- `paste <file> <base64-payload>` — write base64 into file
- `screenshot [outpath]` — capture durian display as PNG
- `dashboard` — single-keystroke composition of auto-arch surface
- `run <bin> [args...]` — execute binary in new cell

**TS / JavaScript Host:**
- `bun <script.ts> [args...]` — run TypeScript via afsrv_bun
- `claude [args...]` — spawn Claude Code CLI in new tile

**Internals (not verbs):**
- `_helpers.lua` — shared utilities; imported by other verbs
- `edits` — state of recent edits

## 4. Reference Durian

- Location: `reference/durian-upstream/durian/`
- Entry: `reference/durian-upstream/durian/durian.lua`
- Provides: menu system (durian.send verbs), workspace layout,
  window dispatch, keyboard bindings, signal event handlers
- **Trap:** this is UPSTREAM reference; the actual running durian
  is at `zig-out/share/arcan/appl/durian/`, which is a **compiled**
  snapshot. Changes here require `zig build install` to propagate
  to the working appl tree.

## 5. Build System

### Top-level (`build.zig`)

- Entry: `pub fn build(b: *std.Build) void`
- Default: SH backend only (no LLVM). Uses `useC` and
  `useLlvmForSource()` helpers to gate LLVM-requiring code paths.
- Outputs: `arcan` (engine), `afsrv_*` (frameservers), libraries
  (`libarcan_shmif.a`, `libarcan_a12.a`, `libarcan_tui.a`), hem
  builtins to durian appl tree.
- Opts: `build_shmif`, `build_tui`, `build_a12`, `with_ffmpeg`,
  `build_afsrv_terminal`, `build_afsrv_decode`,
  `build_afsrv_encode`, `build_afsrv_net`, `build_arcan_vk`, etc.

### `build.zig.zon`

- Version: 0.7.2
- Minimum Zig: 0.15.2
- Lazy deps: ffmpeg (7.0.1), sqlite3 (3.51.0), TrueType (custom fork)

### `build_llvm/build.zig`

- Decoupled: LLVM targets (qtarcan, gamescope, llama-cli, afsrv_bun)
  built separately
- Invocation: `cd build_llvm && zig build <target>`
- Helpers: `build_qtarcan.zig`, `build_gamescope.zig`,
  `build_llama.zig`, `build_afsrv_bun.zig`
- afsrv_bun: object linked via `build_llvm/tools/link-afsrv-bun.sh`;
  Bun's build.zig produces the .o, top-level just installs it
- Profile: `BUILD_PROFILE=release` forced on Asahi due to JSC
  strict-`<` ASSERT on 16K-page systems

### `build_llvm/build.zig.zon`

Separate lock file; includes llama_cpp, Bun, Qt, gamescope deps.

## 6. Tools

| Subdir | Purpose |
|--------|---------|
| **`auto-arch/`** | Orchestrator driving sh-zig rounds (`test_suite.sh`, `orchestrate.sh`, `match_errors.sh`, `draft_ticket.sh`, `eval.sh`); ticket bootstrap/migration |
| **`refactor/`** | Zig harnesses for code transformation; `LESSONS.md` (rationale); `dryrun.sh` (safe preview) |
| **`selfhost/`** | `run.sh` — drives zig-SH-fork self-host attempt; wraps zig build with stage-n progress tracking |
| **`test/`** | `hem_runner.sh`, `hem_eq_runner.sh`, `hem_workflow_runner.sh`, `hem_caveats_runner.sh`; harnesses for lash/cat9 dispatch |
| **`bun-shmif/`** | README + helpers for shmif ↔ TypeScript integration; Phase 3 Bun embeddings |
| **`screenshot.sh`** | Capture PNG from durian; used by hem's `screenshot` builtin |

## 7. External / Vendored

- `build_llvm/vendor/` — Bun, Qt, gamescope deps
- `~/next/senseye` — referenced externally (0.4-wip branch cloned
  separately; not in repo)

## 8. Output Tree (`zig-out/`)

After `zig build install`:

| Path | Contents |
|------|----------|
| `bin/` | arcan, afsrv_terminal, afsrv_decode, afsrv_encode, afsrv_net, afsrv_game, afsrv_probe, afsrv_avfeed, arcan_frameserver, arcan-net, arcan-net-session, callgraph, etc. |
| `lib/` | libarcan_shmif.a, libarcan_a12.a, libarcan_shmif_server.a, libarcan_tui.a |
| `share/arcan/appl/durian/` | **Durian appl tree:** durian.lua, dispatch.lua, display.lua, lash/ (shell), hem_dev/*.lua (builtins), atypes/, fonts/, config.lua, clipboard.lua, etc. |

**Trap:** Durian's persistent state lives in
`~/.arcan/arcan.sqlite` (DO NOT DELETE per CLAUDE.md). First-run
wizard triggered if missing.

## 9. Bugs and Docs

### Bugs (fossil DB at `.fossil`)

- ~103 tickets as of 2026-05-02; single source of truth
- Schema: standard fossil ticket fields + 12 auto-arch metadata
  columns (bug_id, bug_slug, bug_signature, ticket_phase,
  ticket_sensor, run_history, disasm_refs, cell_refs, ...).
- Layout: numbered open/in-progress/fixed bugs (`bug_id` like
  `0001`, `0036`, ...) + drafts (`status='draft'`) + dev-loop
  master tickets.
- Viewer: `bugs show <id-or-slug>` hem builtin renders ticket
  body. Direct query: `fossil sql "SELECT comment FROM ticket
  WHERE bug_slug='...'"`.
- File new: `fossil ticket add bug_id NNNN bug_slug ...` or via
  `tools/auto-arch/draft_ticket.sh "<sig>"` for auto-staging.
- Example: `bugs show 0036-afsrv-bun-frameserver` — Phase 3 Bun
  integration roadmap.
- The legacy `bugs/<id>-*.md` folder was deleted per ticket 0150
  (2026-05-02). Never recreate it.

### Docs (`/home/x/next/arcan/docs/`)

- `selfhost_plan.md` — zig-SH-fork self-host: detailed plan
- `auto_arch_plan.md` — auto-arch for zig-SH-fork self-host
- `selfhost_phase1_A.md` — stack overflow analysis: Phase 1-A
- `fossil_migration_report.md` — fossil VCS migration notes
  (2026-04-28)
- `hem_visual_agent/` — visual reasoning scaffold for hem
  builtins (manual.md, action_reference.md, shmif_native_guide.md,
  senseye-applied-plan.md)

### CLAUDE.md

Root file. Load-bearing: visibility rules (hem over Bash),
ARCAN_CONNPATH, ~/.arcan/ protection, BUILD_PROFILE=release on
Asahi, TS script locations, durian control verbs, hem_dev
cheat-sheet.

## 10. Critical Config & Runtime

| Item | Location | Notes |
|------|----------|-------|
| **Durian state** | `~/.arcan/arcan.sqlite` | Persistent config DB; first-run wizard if missing. DO NOT DELETE. |
| **Runtime dir** | `XDG_RUNTIME_DIR=/run/user/1000` | Shared-memory page connpath; shmif negotiation dir |
| **Default appl** | `ARCAN_CONNPATH=durian` | Engine boots this on startup; symlink to zig-out/share/arcan/appl/durian |
| **TS bindings** | `build_llvm/examples/arcan-shmif.ts` | Import for new afsrv_bun scripts; types + helpers (shmif, durian, host APIs) |
| **Bun invocation** | `bun <script.ts>` in hem | Resolves to `/home/x/next/arcan/zig-out/bin/afsrv_bun <script.ts>`; runs in separate shmif segment |

## Known Traps & Rules

1. **afsrv_bun is in build_llvm**, not the top-level build.zig.
   Selfhost-only builds won't see it.
2. **BUILD_PROFILE=release on Asahi** due to JSC strict-`<` ASSERT
   on 16K pages; do not relax.
3. **Don't delete ~/.arcan/ or arcan.sqlite** — resets durian
   config, forces first-run.
4. **Durian state is live in running arcan** — restart only for
   binary-level fixes; Lua reloads are preferable.
5. **posix_libc.zig is hand-written** (T46 @cImport sweep); if you
   see a posix_libc import error, check that module's source.
6. **hem verbs are higher-priority than Bash** per CLAUDE.md
   visibility rule. Use `find <dir>`, `read <file>`, `grep <pat>
   <file>` from hem cells so the user sees the result.
7. **Phase 3i.5 (hemParent.send) is broken** — use
   `hemSpawn(chain)` for sibling tiles instead.
8. **Subsegment support in afsrv_bun is disabled** pending durian
   SEGREQ→fetchfds fix (bug 0036 phase 3l).

## Quick Reference Cheat Sheet

| Task | Look Here |
|------|-----------|
| **Add a new hem verb** | `data/lash_builtins/hem_dev/*.lua`; `compile` verb as template; `zig build install` to propagate |
| **Find frameserver code** | `src/frameserver/<name>/` (afsrv_terminal, afsrv_decode, etc.) |
| **Inspect engine events** | `src/engine/arcan_event.zig`, `arcan_main.zig` event loop |
| **shmif protocol details** | `src/shmif/arcan_shmif.h` (C ABI), `shmif_types.zig` (Zig wrappers) |
| **a12 network protocol** | `src/a12/a12.zig` (mux), `a12_encode.zig` (pack), `a12_decode.zig` (parse) |
| **Durian menu/dispatch** | `reference/durian-upstream/durian/dispatch.lua` (upstream reference); running version at `zig-out/share/arcan/appl/durian/dispatch.lua` |
| **Lua→engine interface** | `src/engine/arcan_lua.zig` (Lua FFI layer) |
| **Zig build config** | `build.zig` (top-level), `build_llvm/build.zig` (LLVM targets) |
| **Auto-arch orchestration** | `tools/auto-arch/orchestrate.sh` + ticket schema in `tools/auto-arch/bootstrap_ticket_schema.sh` |
| **TS script templates** | `build_llvm/examples/arcan-shmif.ts` (import this), `durian-ls.ts`, `bun-spawns-lash.ts` (orchestration examples) |
| **Read bug tickets** | `bugs show <id>` in hem (fossil-backed; the bugs/ folder is gone) |
| **Check build status** | `status` hem verb (live spread), or `fossil log` / `fossil diff` |
| **View running state** | `engine introspect` or `engine watch *` (hem verbs) |
