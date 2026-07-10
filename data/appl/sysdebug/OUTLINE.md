# sysdebug — Outline

This is the canonical outline for the `sysdebug` arcan appl. The
appl mirrors the four-chapter structure of Mellstrand & Ståhl's
*Systemic Software Debugging* (2012, CC-BY 3.0) but applies it to
the four live arcan/zig sub-projects. This file is the contract
between the coordinator and the four (future) chapter-writing
agents — every section below names the original-book section it
mirrors, an epigraph candidate, the tickets it draws from, and the
seed verb-boxes the chapter must include.

The actual chapter prose is **not** written here. This is the map.
Future agents fill it in following CONTRACT.md and STYLE.md.

The original book is at `/home/x/next/arcan/systemic-software-
debugging.pdf`; pages cited below refer to it.

---

## Front matter

| File                        | Owner       | Contents                                  |
|-----------------------------|-------------|-------------------------------------------|
| `parts/00_foundations/preface.lua` | coordinator | Why this appl exists; the visibility-rule premise; how an appl differs from a PDF; CC-BY 3.0 attribution to Mellstrand & Ståhl. |
| `parts/00_foundations/glossary.lua` | coordinator | shmif, hem, hem_dev, durian, lash, senseye, viz_bus, payload key, sensor, spread, verbbox, frameserver, segment, subsegment, a12, sh-zig, afsrv_bun, posix_libc shim, fossil, ARCAN_CONNPATH, controller, .index, .monitor, .debug. |
| `parts/00_foundations/howto.lua`    | coordinator | How to navigate; key bindings; how Verb Boxes spawn hem cells; how to file a missing-verb ticket from inside the appl. |

Suggested cold-open epigraph for the preface:

> *"We dedicate this work to all ambitious requirement specification
> engineers and system architects who manage to keep up the good
> faith despite the fact that software produced with their work as
> input never ever functions as specified, intended or expected."*
> — Mellstrand & Ståhl 2012, dedication

Suggested closing line for the preface (in our own voice):

> An appl is an honest book. A PDF could only describe these verbs;
> here you can run them.

---

## Part I — Foundations

Coordinator-owned. Five chapters: a new Ch 0 (Architecture) plus
the four mirroring chapters. Part I's chapters do **not** dive into
domain detail; they frame the original-book material in the context
of this codebase, then hand off to Parts II–V.

### Ch 0 — Architecture (the codebase map) [NEW]

The original book has no architecture chapter — it is intentionally
generic. This codebase is not generic, and a reader landing in
`/home/x/next/arcan` for the first time needs a map before any of
the methodological chapters land.

**Why this chapter exists.** The arcan/hem/zig stack is dense in
file count and light in obvious organisation. A new agent that
opens `src/` cold will not find a single `main.c`. This chapter is
the map that prevents the next 90 minutes of `find . -name '*.zig'`
from happening.

**Sections (each ≤ 1 screen):**

| § | Title | What it covers |
|---|---|---|
| 0.1 | Top-level layout | The 10 directories at repo root, one line each. Special note on which ones are noise (`.zig-cache`, `.fossil`, `*.o` at root) and which are load-bearing. |
| 0.2 | The engine and shmif | `src/engine/arcan_main.zig` event loop; `src/shmif/arcan_shmif.h` C ABI; `src/shmif/shmif_types.zig` Zig wrappers; `libarcan_shmif.a` install location. |
| 0.3 | The frameservers | `src/frameserver/{terminal,decode,encode,net,bun,game,probe,avfeed}/`. Each gets a one-liner role. afsrv_bun's `default/` vs `embed/` split called out, with the build_llvm trap. |
| 0.4 | The a12 protocol | `src/a12/{a12.zig,a12_encode.zig,a12_decode.zig,a12_types.zig}`. Crypto shim, blake3, zstd. Note: a12 over Tailscale is the routing case, not a separate codepath. |
| 0.5 | The posix_libc shim | `src/platform/posix/libc.zig`. Why this exists (zig self-host, no @cImport). Connection to tickets 0100–0111. |
| 0.6 | The Lua side: appls | `data/appl/{welcome,console,callgraph,texttest,vktest,sysdebug}/` — one line each. `sysdebug` is this book. |
| 0.7 | The Lua side: lash + hem_dev | `data/lash/` shell; `data/lash_builtins/hem_dev/` verbs. Full verb roll-call grouped by family (system/debug, files/search, build/compile, code analysis, time/data, introspection, ts/js, internals). Each family ≤ 6 verbs with one-line each. |
| 0.8 | Reference durian | `reference/durian-upstream/durian/durian.lua`. The trap: it is reference, not running. The running version is at `zig-out/share/arcan/appl/durian/`, snapshotted by `zig build install`. |
| 0.9 | The build system | `build.zig` (top-level), `build.zig.zon`, `build_llvm/build.zig`, `build_llvm/build.zig.zon`. The decoupling rationale. The Asahi `BUILD_PROFILE=release` rule. |
| 0.10 | Tools | `tools/{auto-arch,refactor,selfhost,test,bun-shmif,screenshot.sh}/`. One-line each. |
| 0.11 | Vendored and external | `build_llvm/vendor/` (Bun, Qt, gamescope deps). `~/next/senseye/` as referenced material outside the repo. |
| 0.12 | The output tree | `zig-out/{bin,lib,share/arcan/appl/durian}/`. Where each binary lands; where the Lua sources end up. |
| 0.13 | Bugs and docs | `.fossil` (single ticket DB, ~103 tickets; numbered + status='draft' + dev-loop master tickets — the legacy `bugs/` folder was deleted 2026-05-02 per ticket 0150). `docs/{selfhost_plan,auto_arch_plan,fossil_migration_report,hem_visual_agent,repo-handles,screenshots}.md`. CLAUDE.md at root. |
| 0.14 | Critical config and runtime | `~/.arcan/arcan.sqlite` (DO NOT DELETE). `XDG_RUNTIME_DIR=/run/user/1000`. `ARCAN_CONNPATH=durian`. TS bindings at `build_llvm/examples/arcan-shmif.ts`. |
| 0.15 | Known traps | The 8-item list from the architecture survey: afsrv_bun outside top-level build; Asahi BUILD_PROFILE; ~/.arcan deletion; durian state liveness; posix_libc.zig hand-written; hem over Bash; Phase 3i.5 broken; subsegment SEGREQ disabled. |
| 0.16 | "If you have to find X" | The one-page cheat-sheet from the architecture survey: add a hem verb → here; find frameserver code → here; etc. |

**Verb boxes the chapter must include (≥ 3):**
- `builtin dev ||| status` — see what is happening right now
- `builtin dev ||| find /home/x/next/arcan/src zig` — list the engine sources
- `builtin dev ||| read /home/x/next/arcan/CLAUDE.md` — read the project rules

**Cross-links:**
- to Part I Ch 2 (the toolchain story for this codebase)
- to Part II Ch 0 if Agent A adds a Part-specific architecture sub-section

### Ch 1 — Introduction (mirrors original Ch 1)

Coordinator's job here is to set the stage so Parts II–V can drop
into their own Ch 1 without re-explaining what an anomaly or a
methodology is. Quote the original; then say "this is what each of
the next four parts will mean by it."

| § (mirrors original) | Pages | Epigraph candidate (verbatim) | Bridge content (≤ 1 screen each) |
|---|---|---|---|
| 1.1 Demarcation | pp. 3–8 | "The focus for this and coming chapters is primarily on dynamic analysis as a means for grasping and refining an understanding of the particulars of a given system…" (p. 5) | What this appl is and is not: a practitioner's companion to the canonical text, scoped to four live sub-projects, enforcing the visibility rule. |
| 1.2 Software and Software-Intensive Systems | pp. 9–22 | "We are now moving away from the realm of software-as-punch-cards and into software-intensive systems, where systems are composed of many different kinds of software, running on a variety of machines in close collaboration with other kinds of devices and processes both mechanical and human." (p. 10) | The arcan stack is exactly such a system: engine, frameservers, a12, durian lua, hem lua, TS via afsrv_bun, all coupling through shmif. |
| 1.3 Cause and/of Panic | pp. 15–22 | "A major part of software analysis and debugging is determining which factors involved caused a certain undesired effect to occur in order to feed this back into upcoming instances of the software, preferably by changing some offline artifact like source code." (p. 18) | Why fossil tickets and the auto-arch loop exist: feeding cause back into source artifacts. The 0036 visibility-rule ticket is itself an example. |
| 1.4 The Origin of Anomalies | pp. 23–33 | "The primal aim on the origin of anomalies is that each and every bug is simply an inconsideration on behalf of the developer." (p. 24) | The anomalies these four parts hunt: codegen miscompiles (Part II), shmif segment hangs (Part III), capability-derivation mistakes (Part IV), partition-time disagreements (Part V). |
| 1.5 Debugging Methodology | pp. 34–36 | "More often than not, there is some claim of scientific value in these methods, but given a closer examination the methods seem empty, irrelevant or trivial." (p. 36) | The methodology this appl proposes: every claim ends in a Verb Box. If you cannot make it visible, you cannot claim to understand it. |
| 1.6 Concluding Remarks | p. 36–37 | "A major question still lingers however: what is software?" (p. 36) | For us, software is what shmif passes between segments. Hand off to Ch 2. |

**Verb boxes (≥ 2):**
- `builtin dev ||| bugs show 0036-visibility-rule` — read the rule that anchors this appl
- `builtin dev ||| logwatch /home/x/.arcan/logs panic` — see what an anomaly looks like in this codebase

### Ch 2 — Software Demystified (mirrors original Ch 2)

The coordinator's job here is to walk the original's compile→link→
load→execute pipeline once for the canonical case (a C program on
Linux), then point at how each of the four Parts will do their own
walk for their own pipeline.

| § | Pages | Epigraph candidate | Bridge content |
|---|---|---|---|
| 2.1 Hello World | pp. 40–42 | "To determine the behavior a particular piece of software will present when executing, one must have an extensive knowledge about the system at hand." (p. 40) | Our four "hello worlds": `zig build` (II), `arcan welcome` (III), seL4 root task echo (IV), `arcan-net dd@ explain` (V). |
| 2.2 Transforming Source to Binary | pp. 43–44 | "The key principle for a toolchain is that a series of tools is to be applied where the output from one tool is the input to the next." (p. 43) | Sketch of the four pipelines side-by-side; Parts II–V each take one and walk it. |
| 2.3 Developer of High-Level Code | p. 44 | "There is no automated way to transform an informal description of a system into a formal description, and to do this task a developer must make a number of assumptions, generalizations and simplifications." (p. 44) | The developers in this codebase: their assumptions are encoded in CLAUDE.md, in hem_dev/_helpers.lua, in the build.zig comments. Read them. |
| 2.4 Source Code and the Compiler | pp. 45–47 | "No high-level language allows for unrestricted communication between its principal entities or communication as free as the actual machine code allows. Understanding the restrictions placed on high-level languages is essential when hijacking execution, which is a key to tracing and debugging complex software systems." (p. 46) | Zig's restrictions vs C's vs Lua's. Each Part will go further. |
| 2.5 Object Code and the Linker | pp. 48–53 | "In a modern tool chain the linker is the only tool that considers the entire system at once." (p. 51) | The linker as global lens. For us, the analogue is shmif — the only thing that sees every frameserver at once. Bridge to Ch 3 (information sources). |
| 2.6 Executable Binary and Loading | pp. 54–57 | "Self-contained executable files which can be loaded and executed without any external dependencies are called static executables or statically linked binaries. This type of executable system has a very limited ability to communicate with its environment." (p. 55) | The arcan engine is dynamic-by-necessity: shmif consumers are loaded at runtime via segment requests. seL4 (Part IV) inverts this. |
| 2.7 Executing Software and the Machine | pp. 58–62 | "Even though in the turing-complete world of computers every computation is theoretically possible with any turing-complete system, the efficiency and actual implementability depends on the underlying computational model." (p. 58) | Why Asahi BUILD_PROFILE=release matters: a JSC strict-`<` ASSERT on 16K-page systems IS the underlying computational model breaking the developer's assumption. |
| 2.8 Operating System and the Process | pp. 63–69 | "When the operating system loads a program into memory as a new process, it constructs a virtual address space in which that process is supposed to operate." (p. 65) | What the OS gives us (linux: process, fd, signal); what arcan adds (shmif segment, viz_bus event); what seL4 (Part IV) replaces it with (untyped, retype, install). |

**Verb boxes (≥ 2):**
- `builtin dev ||| disasm /home/x/next/arcan/zig-out/lib/libarcan_shmif.a` — see the linker's output
- `builtin dev ||| procfs $$ maps` — see the loader's output for this very cell

### Ch 3 — Principal Debugging (mirrors original Ch 3)

The methodological core. Coordinator establishes the four-action
spine (Subdivide → Measure → Represent → Intervene) and the three
imperatives (Fail Early/Often/Hard); each Part lands them in their
own domain.

| § | Pages | Epigraph candidate | Bridge content |
|---|---|---|---|
| 3.1 Why Analyze a System | p. 72 | "To make these kinds of alterations, we need to understand the system at hand, not only to discover where to change something but also to determine potentially adverse consequences to such alteration." (p. 72) | Why ticket 0036 was written *before* the bun frameserver work began: not finding where to change, but predicting consequences. |
| 3.2 Software System Analysis | pp. 72–73 | "On realizing source code: large software systems are inherently too complex to understand by considering only source code and other static sources." (p. 75) | Source alone never tells you why durian's segment_request hangs — only the live shmif event log does. The visibility rule is the corollary. |
| 3.3 System Views and Analysis Actions (the four-action core) | pp. 77–92 | "The principal advantage of using an experimental approach is that one works with the actual behavior of the target system. This enables the analyst to establish a feedback chain where he or she measures properties inside the system he or she manipulates." (p. 76) | The four actions, mapped onto hem once: **Subdivide** = open a new spread per subsystem; **Measure** = `metrics`, `procfs`, `engine watch`; **Represent** = the spread itself + senseye-applied-plan layer 5; **Intervene** = `edit`, `write`, `durian.send`, `hemSpawn`. |
| 3.4 Information Sources | pp. 93–104 | "Source code is the first formal description that has enough precision to either directly – or through some transformation – form each individual component of the intended system." (p. 95) | The pre/in/post-execution split, mapped: pre = `read`, `find`, `grep`, `sym`, `disasm` on .o; in = `monitor`, `engine watch`, `metrics`, `logwatch`; post = `cores list`, `cores bt`, crash dumps via `arcan-net --get-file .report`. |
| 3.5 The Software Analysis Conundrum | pp. 105–109 | "Snapshots and crash dumps are the central sources for information at a post-execution systemic state. They spring into place from different, but similar mechanisms." (p. 105) | Why the auto-arch loop runs in fossil branches: each round is a snapshot, replayable. The conundrum is exactly what the loop is built to solve. |
| 3.6 Analysis Imperatives (Fail Early/Often/Hard) | pp. 110–117 | "The longer it takes from something failing to the failure being discovered the harder it is to find out what happened." (p. 110) | **Fail Early:** zig comptime, eval gates in tools/auto-arch. **Fail Often:** the test_suite.sh + hem runners. **Fail Hard:** ARCAN_SHMIF_MONITOR + the orphan-watchdog story; the rule that durian state is live so a clean crash beats silent corruption. |

**Verb boxes (≥ 4):**
- `builtin dev ||| status` — Subdivide: see all subsystems at once
- `builtin dev ||| metrics` — Measure: live resource use as a spread
- `builtin dev ||| hilbert` — Represent: the build graph as a spatial view
- `builtin dev ||| edit /home/x/next/arcan/CLAUDE.md "FOO" "BAR"` — Intervene: an edit visible to the user (don't actually change CLAUDE.md; the verbbox demonstrates the verb shape)

### Ch 4 — Tools of the Trade (mirrors original Ch 4)

Coordinator's job: introduce the hem_dev verb roll-call as the
debugger / tracer / profiler trio for this codebase, then hand off
to Parts II–V to demonstrate them on real subsystems.

| § | Pages | Epigraph candidate | Bridge content |
|---|---|---|---|
| 4.1 Layout of this Chapter | p. 119 | "The developer, just like other craftsmen, has an extensive array of tools at his disposal." (p. 119) | The hem_dev verb roll-call (system/debug, files/search, build/compile, code analysis, time/data, introspection). One paragraph each family. |
| 4.2 Debugger | pp. 120–131 | "A debugger assist with debugging by allowing manipulation, the intervention, of execution flow and exploring of the state… One important attribute that can be deduced from this description is that a debugger is a dynamic tool working on an executing system." (p. 120) | Our debugger isn't gdb. It's `bugs show <id>` to get the ticket-bound session; `engine introspect` for live state; `cores info <id>` for post-mortem; the `bun` verb for live JS-driven introspection of running shmif segments. Ticket 0117 is the open work to make `engine introspect` true peer of gdb-attach. |
| 4.3 Tracer | pp. 131–138 | "The kernel call trace – creates a log of the communication between its target and the operating system kernel." (p. 85, ch 3) | Our tracer is `monitor CLIENT` over the durian control socket; `logwatch` with bucketing; the hem `time` builtin (C.1) for time-bucketed event aggregation; the auto-arch loop's per-round event log. |
| 4.4 Profiler | pp. 138–141 | (no clean direct quote available in extracted material; coordinator draws on the section summary: "balance accuracy against overhead") | Our profiler is `metrics`; the hilbert build-graph for compile-time profiling; the auto-arch fitness score per round (a domain-specific profiler that measures compiler progress, not CPU time). |
| 4.5 (NEW) Visualizer | — | (this section has no analogue in the original; introduce it as our addition) | The senseye-applied substrate: spreads as cells, payload-key contract, viz_bus, hilbert, disasm, trigram (deferred). The point: the original had no Visualizer chapter because in 2012 the tooling did not exist. We have it now and it changes the answers to 4.2–4.4. |

**Verb boxes (≥ 5):**
- `builtin dev ||| bugs show 0117` — read the ticket that defines our gdb-attach equivalent
- `builtin dev ||| engine introspect` — see what is currently introspectable
- `builtin dev ||| monitor CLIENT` — start the tracer
- `builtin dev ||| metrics` — start the profiler
- `builtin dev ||| dashboard` — open the visualizer composition

---

## Part II — The Self-Hosted Zig Fork

**Owner:** Agent A. **Pages:** ~40 screens (≈1500–2500 lines of Lua
across the four chapter modules).

**Domain in one paragraph.** The arcan project maintains a fork of
the Zig compiler ("sh-zig") that compiles arcan with a self-hosted
backend, no LLVM. The fork drives the entire selfhost arc; bugs in
its codegen, in its setSignedness, in its alignment, in its panic
paths, ARE the project's debugging surface for months at a time.
Part II is the practitioner's chapter for that work.

**Tickets to draw from:**
- `0001-sh-codegen-stack-overflow`
- `0002-sh-setSignedness-small-size-assert`
- `0003-arcan-fsrv-pushevent-intcast-truncate`
- `0007-statesnap-vcontext-stack-miscompile`
- `0008-lua-close-alignment-panic`
- `0102-refactor-extern-fn`
- `draft-d001-panic-select-zig-13053-body`
- `draft-d002-error-thread-zig-439-cannot`
- `draft-d003-compile-fail-zig`
- `draft-d004-panic-select-zig-10124-body`
- `dev-loop06-disasm-llvm-vs-sh`

**Verb domain:** `zigbuild`, `compile`, `selfhost`, `disasm`,
`hilbert`, `sym`, `dwarf`, `dietree`, `diegraph`, `cores list`,
`cores info`, `cores bt`, the `compile.errors` spread.

**Sensors published on `viz_bus`:** `compile.units`,
`compile.errors`, `selfhost.errors`, `auto-arch.round`, `hilbert`.

**Per-chapter outline:**

### Part II Ch 1 — Introduction (sh-zig)

Mirrors original Ch 1. Each section gets one paragraph from
Agent A applying the original's principle to the sh-zig domain.

- 1.1 Demarcation: what counts as "this domain" — codegen, link,
  selfhost loop. What's out of scope — LLVM-zig (live as
  comparison via `dev-loop06`), runtime arcan (Part III).
- 1.2 Software-intensive: the fork is intensive — it compiles
  itself, then compiles arcan, then compiles hem; three layers
  each can drift independently.
- 1.3 Cause/Panic: the recursion problem. A miscompile in stage 1
  produces a stage-2 binary that miscompiles stage 3. The
  proximal/distal cause framing applied here.
- 1.4 Origin of anomalies in codegen: the four ticket clusters
  (0001 stack overflow; 0002 signedness; 0003 intcast; 0007
  miscompile). Each ticket gets one paragraph; lead with what the
  developer's "inconsideration" was.
- 1.5 Methodology: the auto-arch loop is our methodology. Round =
  hypothesis. Eval gate = test. Fitness = predicted improvement.
  Merge-on-pass = adopted answer.
- 1.6 Concluding: hand off to Ch 2 (the pipeline you need to walk).

**Verb boxes (≥ 2):**
- `builtin dev ||| selfhost` — start a selfhost round
- `builtin dev ||| bugs show 0001-sh-codegen-stack-overflow`

### Part II Ch 2 — Software Demystified (sh-zig)

The sh-zig pipeline, walked. One section per stage; each stage
ends in a verbbox that opens the live state of that stage.

- 2.1 Source: the fork's own zig source tree, where it differs
  from upstream
- 2.2 Tokens / AST: where the fork still matches upstream
- 2.3 AIR: the analyzed-intermediate representation; the first
  stage where divergences from llvm-zig appear
- 2.4 MIR: machine-intermediate; the codegen wedge
- 2.5 Object: ELF emission; the place 0003 (intcast-truncate)
  lives
- 2.6 Linker: zig's own linker for sh-zig output; the alignment
  story (ticket 0008)
- 2.7 Loaded binary: stage-2 selfhost — the binary that compiles
  arcan
- 2.8 Comparison: the dev-loop06 disasm spread that puts llvm-zig
  output and sh-zig output side by side

**Verb boxes (≥ 4):**
- `builtin dev ||| zigbuild` — start a build, watch the spread
- `builtin dev ||| disasm /home/x/next/arcan/zig-out/bin/arcan` — post-link inspection
- `builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan name=main` — symbol table
- `builtin dev ||| dwarf` — addr → DIE for crash traces

### Part II Ch 3 — Principal Debugging (sh-zig)

Apply the four actions and three imperatives to the sh-zig domain.

- 3.1 Why analyse: not finding where to fix, but predicting how
  the fix will affect stage 2 and stage 3 outputs.
- 3.2 The static/dynamic split for compilers: static = the
  fork's source diff against upstream; dynamic = the actual
  codegen output of stage N.
- 3.3 The four actions:
  - Subdivide: per compile-unit; the units spread does this.
  - Measure: the `compile.errors` spread; build_dur_ms; build_state
  - Represent: hilbert build-graph (the senseye-applied layer 5
    instance for compilation).
  - Intervene: edit the fork's codegen; rebuild; re-run auto-arch.
- 3.4 Information sources: pre = source diff, IR dumps; in =
  zigbuild stream (ticket 0023 made it visible); post = cores +
  the panic-line auto-drafted ticket (drafts d001–d004).
- 3.5 The conundrum: a miscompile in stage 1 only shows up at
  stage 3 runtime. Auto-arch's round-as-snapshot model is the
  answer.
- 3.6 Imperatives: Fail Early via the eval gate before merge;
  Fail Often via the auto-arch round cadence; Fail Hard via
  zig's panic on UB rather than miscompile-and-continue.

**Verb boxes (≥ 4):**
- `builtin dev ||| status` — see the round in flight
- `builtin dev ||| hilbert` — the build-graph senseye view
- `builtin dev ||| cores list` — every recent crash
- `builtin dev ||| selfhost --gate` — eval-only run

### Part II Ch 4 — Tools of the Trade (sh-zig)

The hem_dev verbs, retold as a debugger story for the compiler.

- 4.1 Roll-call for compiler verbs.
- 4.2 Debugger: the live `compile.errors` spread is the debugger
  for a still-running build. `cores info <id>` is the post-
  mortem.
- 4.3 Tracer: `zigbuild` itself is the tracer (per ticket 0023's
  stream-step events). `time` builtin buckets the events.
- 4.4 Profiler: `auto-arch.round.fitness` IS the profiler — but
  it measures compiler-correctness progress, not wall time. The
  hilbert spread is the build-time profiler.
- 4.5 Visualizer: the `dietree` and `diegraph` spreads (D.2,
  E.5) — DWARF DIE-tree and relation graph as senseye views.

**Verb boxes (≥ 5):**
- `builtin dev ||| compile`
- `builtin dev ||| disasm <obj>`
- `builtin dev ||| dietree`
- `builtin dev ||| diegraph`
- `builtin dev ||| auto-arch round-summary`

---

## Part III — Zig-based arcan (afsrv_bun + posix_libc shim)

**Owner:** Agent B. **Pages:** ~40 screens.

**Domain in one paragraph.** Arcan itself is being moved to zig
piece by piece. The active wedge is `afsrv_bun` (bug 0036,
multi-phase, mostly landed). Underneath it the posix_libc shim work
(0100–0111) is unblocking zig self-host backend for shmif/a12/
keystore. Part III walks both: the live frameserver as the worked
example, and the shim as the structural enabler.

**Tickets to draw from:**
- `0036-afsrv-bun-frameserver` (all phases)
- `0036-visibility-rule` (the rule we obey)
- `0034-shmif-native-guide-for-external-agents`
- `0100-refactor-posix-libc` and 0101–0111 (the full stack)
- `0102-refactor-extern-fn`
- `0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach`
- `0118-epic-host-shell-debug-toolkit-to-hem-native-primitives`
- `0035-bun-shmif-native-plugin` (retired predecessor)
- `0033-claude-code-shmif-bridge-in-afsrv-terminal` (retired)

**Verb domain:** `bun <script.ts>`, the shmif paint primitives via
TS, `durian.send` (Lua-side), `monitor CLIENT`, `engine
introspect/watch`, `procfs`, `proc`, the `metrics` spread, the
`bugs show` verb.

**Sensors:** `build.atlas` (bug 0024), `fossil.*` (bug 0025),
`edit.*`, `ticket.*`, plus the parent-control `hemParent.send`
SOH-prefix protocol from 0036 Phase 3i.5.

**Per-chapter outline:**

### Part III Ch 1 — Introduction (zig-arcan)

- 1.1 Demarcation: what's "zig-arcan" — afsrv_bun, the shim work,
  the engine's gradual zig migration. What's out — durian lua
  (still lua), upstream arcan (mirrored, not authored).
- 1.2 The system is intensive: shmif as the IPC fabric across
  engine + frameservers + Lua appls + TS modules.
- 1.3 Cause/Panic: the user-visible vs hidden faults split. A
  segment_request hang (Phase 3l of 0036) is a hidden fault that
  user only feels as "the Bun window never opens." The visibility
  rule was filed *because* hidden faults are unactionable.
- 1.4 Origin of anomalies in this domain: protocol races (shmif
  buffer signal/wait), assumption mismatches (durian's fetchfds
  expecting an fd Bun never sends), build profile mistakes (the
  Asahi JSC strict-`<` ASSERT — exactly the "machine limitation"
  framing of original 1.1).
- 1.5 Methodology: the visibility rule itself is the chapter
  methodology. Quote ticket 0036-visibility-rule verbatim here.
- 1.6 Concluding: the shmif story (Ch 2) and the engine
  introspection story (Ch 3) are what the rest of Part III is.

**Verb boxes (≥ 2):**
- `builtin dev ||| bugs show 0036-afsrv-bun-frameserver`
- `builtin dev ||| bugs show 0036-visibility-rule`

### Part III Ch 2 — Software Demystified (zig-arcan)

The shmif/frameserver pipeline, walked.

- 2.1 Source: arcan/src/{engine,frameserver,shmif,a12}/
- 2.2 The shmif page: layout, ring buffer, signal/wait dance
- 2.3 Frameserver lifecycle: spawn → preroll → activate
- 2.4 Segment request: SEGREQ → fetchfds → activated subsegment
  (with the Phase 3l caveat)
- 2.5 The TS layer: how `bun foo.ts` resolves to
  `afsrv_bun foo.ts` and how host bindings (shmif, durian, host)
  attach
- 2.6 The C glue: `src/frameserver/bun/embed/arcan_afsrv_bun_init.c`
  and `host_bindings.cpp`
- 2.7 The posix_libc shim: where it sits, what it replaces, why
  it unblocks self-host (tickets 0100–0111 walked layer by layer)
- 2.8 Engine + Lua: the full path from a Lua `valid_vid()` call
  down to a shmif buffer signal

**Verb boxes (≥ 4):**
- `builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/echo.ts`
- `builtin dev ||| read /home/x/next/arcan/src/shmif/arcan_shmif.h`
- `builtin dev ||| find /home/x/next/arcan/src/posix_libc`
- `builtin dev ||| disasm /home/x/next/arcan/zig-out/bin/afsrv_bun`

### Part III Ch 3 — Principal Debugging (zig-arcan)

- 3.1 Why analyse: predicting whether a shmif protocol change
  will break durian's segment routing.
- 3.2 The static/dynamic split: static = the source + ticket
  trail; dynamic = `monitor CLIENT` + `engine watch *`.
- 3.3 Four actions in this domain:
  - Subdivide: per frameserver. `procfs <pid>` for each.
  - Measure: `metrics`, `engine watch`, the durian control
    socket (`durian.send "monitor CLIENT"`).
  - Represent: the metrics spread; the build.atlas long-line
    spread; the hemParent.send SOH protocol that lets a child
    cell render structured output back to the parent.
  - Intervene: `durian.send`, `edit`, `write`, the bun host
    bindings (paint pixels, send messages).
- 3.4 Information sources: pre = the bug ticket trail
  (`bugs show <id>`, `bugs all`, `fossil sql ...`); in = monitor +
  engine; post = `cores list`, the orphan-watchdog log
  (ticket 0114).
- 3.5 The conundrum: a frameserver crash leaves orphans
  (ticket 0113); the watchdog (0114) tries to clean up but
  has known false positives (0114-watchdog-false-orphan).
  Walking from a crash dump back to "what segment was being
  requested" is the chapter's worked example.
- 3.6 Imperatives: Fail Early = ARCAN_SHMIF_MONITOR;
  Fail Often = the hem_workflow_runner.sh harness;
  Fail Hard = engine asserts on shmif protocol violation
  rather than continuing with corrupt segment.

**Verb boxes (≥ 4):**
- `builtin dev ||| monitor CLIENT`
- `builtin dev ||| engine introspect`
- `builtin dev ||| metrics`
- `builtin dev ||| logwatch /home/x/.arcan/logs orphan`

### Part III Ch 4 — Tools of the Trade (zig-arcan)

- 4.1 Roll-call: the hem_dev verbs that target shmif/durian/
  bun. Group by what subsystem each illuminates.
- 4.2 Debugger: `bugs show <id>` is the ticket-bound debugger
  session (the bug record IS the breakpoint). `engine
  introspect` is the live state inspector. Open ticket 0117
  asks for true gdb-attach equivalent.
- 4.3 Tracer: `monitor CLIENT` writes to the durian control
  socket; `logwatch panic|atlas|font|orphan` buckets the engine
  log; `bun poll-test.ts` is the per-event tracer for shmif.
- 4.4 Profiler: `metrics` for live; `atlas` for build-time
  long-line tracking (0024); the `time` bucket builtin for any
  emitter.
- 4.5 Visualizer: the hem `dashboard` builtin (auto-arch
  layer-6) composing every spread in one workspace; senseye-
  applied-plan as the wider context.

**Verb boxes (≥ 5):**
- `builtin dev ||| dashboard`
- `builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/poll-test.ts`
- `builtin dev ||| cores list`
- `builtin dev ||| atlas`
- `builtin dev ||| time`

---

## Part IV — seL4 Bootstrapping in Zig

**Owner:** Agent C. **Pages:** ~40 screens. Note: this domain is
*early*. Part IV is half practitioner's chapter, half roadmap.
Agent C owes a missing-verb ticket draft for any tool the chapter
needs that does not yet exist.

**Domain in one paragraph.** The medium-term bet is that the arcan
desktop will boot directly on seL4 with a Zig rootserver. Today
that means `src/sel4-zig/kernel/*.zig` + a handful of draft tickets
(d006, d012) capturing the early failures. Part IV documents what
exists, the framing the canonical book offers for a capability
system, and what hem_dev verbs would have to be filed to bring
this domain into the visibility rule.

**Tickets to draw from:**
- `draft-d006-tool-t0-invalid-input-sel4-kernel`
- `draft-d012-tool-multi-sel4-kernel-parse-skip`
- `0117-inside-arcan-agent-needs-engine-introspection-equivalent-of-gdb-attach`
  (the framing applies — only the host changes)
- The ticket Agent C must DRAFT: a `caps <pid|cspace>` hem verb
  for capability inspection. File via `tools/auto-arch/draft_ticket.sh` or `fossil ticket add`; suggested slug `hem-caps-builtin`.

**Verb domain:** today: `read`, `grep`, `find` against
`src/sel4-zig/`; `disasm` and `sym` against the rootserver ELF;
`logwatch` against serial console output. Tomorrow (filed by
Agent C): `caps`, `untyped`, `cspace`, a `boot-stage` hilbert,
a `fault-event` spread.

**Sensors (proposed):** `sel4.boot`, `sel4.fault`, `sel4.cap`.

**Per-chapter outline:**

### Part IV Ch 1 — Introduction (seL4-zig)

- 1.1 Demarcation: kernel + rootserver + the first user task. Out
  of scope: full arcan-on-seL4 (years away).
- 1.2 Software-intensive in a microkernel: the fewer subsystems,
  the more each one matters. The shim story is inverted —
  almost no shim, lots of explicit capability passing.
- 1.3 Cause/Panic on a cap-system: every fault is a missing or
  miscast capability. "Panic" in seL4 is structurally different
  from "panic" in Linux — quote draft-d006's InvalidInput trace.
- 1.4 Origin of anomalies: capability derivation mistakes;
  rootserver bringup ordering; missing untyped retypes. Each
  draft ticket gets a paragraph.
- 1.5 Methodology: the same four actions as Ch 1 III, but the
  Measure step is structurally constrained — no `procfs`, no
  `metrics`. You measure by reading capability state at known
  IPC boundaries.
- 1.6 Concluding: hand off to Ch 2 with the boot-pipeline
  sketch.

**Verb boxes (≥ 2):**
- `builtin dev ||| bugs show 0143-tool-t0-invalid-input-sel4-kernel`
- `builtin dev ||| find /home/x/next/arcan/src/sel4-zig`

### Part IV Ch 2 — Software Demystified (seL4-zig)

- 2.1 Source: `src/sel4-zig/kernel/*.zig` plus the upstream seL4
  C kernel
- 2.2 Bootinfo: the page seL4 hands the rootserver
- 2.3 Untyped: the raw memory pool
- 2.4 Retype: turning untyped into specific kernel objects
  (CNode, TCB, Page, Endpoint)
- 2.5 CSpace + VSpace construction: the rootserver's first job
- 2.6 ELF loading: how the first user task gets installed
- 2.7 IPC: the synchronous fast path; how it differs from shmif
- 2.8 Where Zig's allocator story interacts with retype
  (Agent C: the open question)

**Verb boxes (≥ 3):**
- `builtin dev ||| read /home/x/next/arcan/src/sel4-zig/kernel/main.zig`
- `builtin dev ||| disasm /path/to/rootserver.elf`
- `builtin dev ||| sym /path/to/rootserver.elf`

### Part IV Ch 3 — Principal Debugging (seL4-zig)

- 3.1 Why analyse: predicting whether a capability-derivation
  change will leave the rootserver unbootable.
- 3.2 Static/dynamic split: static = the source + capability
  schema; dynamic = serial console + (proposed) caps spread.
- 3.3 Four actions, with the missing primitives flagged:
  - Subdivide: per kernel object class.
  - Measure: today: serial console, qemu monitor commands,
    gdb-stub. Tomorrow: a `caps` hem verb. **Agent C files
    the ticket.**
  - Represent: today: text dumps. Tomorrow: a boot-stage
    hilbert, a fault-event spread, a cspace-tree senseye view.
    **Agent C files the tickets.**
  - Intervene: edit the rootserver source; rebuild; reboot
    qemu; replay.
- 3.4 Information sources: pre = source + capability schema;
  in = serial console (`logwatch`-able) + qemu monitor
  (`bun`-wrappable); post = qemu coredump. Agent C maps each.
- 3.5 The conundrum: each iteration is a full reboot. The
  auto-arch loop pattern (round-as-snapshot) applies but is
  much slower per round.
- 3.6 Imperatives: Fail Early = compile-time capability typing
  (Zig comptime can do a lot here); Fail Often = boot-test
  matrix; Fail Hard = panic-on-UB even at boot.

**Verb boxes (≥ 3):**
- `builtin dev ||| logwatch /tmp/sel4-serial.log`
- `builtin dev ||| bun /home/x/next/arcan/build_llvm/examples/qemu-monitor.ts` (Agent C: this script does not exist; the verbbox itself is the ticket)
- `builtin dev ||| caps <pid>` (Agent C: this verb does not exist; the verbbox itself is the ticket)

### Part IV Ch 4 — Tools of the Trade (seL4-zig)

- 4.1 Roll-call: today (qemu, gdb-stub, serial console) vs
  tomorrow (caps spread, fault spread, boot-stage hilbert).
- 4.2 Debugger: gdb-stub via qemu's gdb-server; the
  `bugs show draft-d006` ticket-as-debugger pattern.
- 4.3 Tracer: serial console dump → `logwatch` with seL4
  fault-pattern bucketing.
- 4.4 Profiler: boot-time as fitness; iteration count to
  reach a stable rootserver as the metric.
- 4.5 Visualizer: the proposed cspace-tree spread; the
  proposed boot-stage hilbert. **Agent C: file the tickets.**

**Verb boxes (≥ 3):**
- `builtin dev ||| qemu-system-aarch64 -kernel ... -s -S` (the actual command; verbbox makes it copy-pasteable)
- `builtin dev ||| logwatch /tmp/sel4-serial.log fault`
- `builtin dev ||| bugs show draft-d012-tool-multi-sel4-kernel-parse-skip`

---

## Part V — a12 in Zig over Tailscale

**Owner:** Agent D. **Pages:** ~40 screens.

**Domain in one paragraph.** a12 is the arcan network protocol.
Today it ships as part of arcan; tomorrow it runs zig-native (the
posix_libc shim work is the gating dep — see ticket 0100). Once the
zig path is clean, the production deployment is "a12 over
Tailscale": every device the user owns runs an a12 endpoint and a
directory mediates discovery. Part V documents debugging when the
fault may be on the other side of the Tailnet.

**Tickets to draw from:**
- `0100-refactor-posix-libc` (the zig-a12 unblocker, with
  its 13-file consumer enumeration)
- The arcan-fe.com a12 articles (2020-10-28 and 2023-11-18) and
  the 2026-01-26 "Weaving a Different Web" article
- The `0034-shmif-native-guide-for-external-agents` ticket
  for the protocol model
- Agent D files: a `.monitor` hem builtin wrapping `arcan-net`'s
  monitor stream. File via `tools/auto-arch/draft_ticket.sh "missing:hem:monitor" sysdebug` (writes status=draft to fossil).

**Verb domain:** today: `arcan-net <directory> <appl>`, `arcan-net
keystore`, `arcan-net --get-file .report`, `procfs <pid> fd` for
socket inspection, `time` for event bucketing. Tomorrow: a
`.monitor` hem verb; an `anet_session` capture browser.

**Sensors:** `a12.session`, `a12.handshake`, `a12.frame`,
`a12.directory`.

**Per-chapter outline:**

### Part V Ch 1 — Introduction (a12)

- 1.1 Demarcation: the protocol, its directory rendezvous, the
  Tailscale carriage. Out of scope: replacing Tailscale.
- 1.2 Software-intensive across the wire: the shmif segment now
  has a network counterpart; the analyst's mental model must
  include partition tolerance.
- 1.3 Cause/Panic across the wire: rendering glitches that look
  like a renderer bug but are packet reordering; auth failures
  that look like config bugs but are clock skew. Quote the
  2020 a12 article on transparency-from-the-user.
- 1.4 Origin of anomalies: protocol-version drift (one side
  upgraded, the other did not); key-trust assumptions
  (TOFU bypassed); directory misconfig.
- 1.5 Methodology: the four actions, but Subdivide gets a new
  meaning — subdivide across the wire.
- 1.6 Concluding: hand off to Ch 2 (the protocol walked).

**Verb boxes (≥ 2):**
- `builtin dev ||| bugs show 0100-refactor-posix-libc`
- `builtin dev ||| arcan-net keystore | head` (note: this opens the keystore for the current user; do not run blindly in agent docs — wrap with caution copy)

### Part V Ch 2 — Software Demystified (a12)

- 2.1 Source: src/a12/{a12,a12_encode,a12_decode,a12_types}.zig
  plus crypto_shim.
- 2.2 The handshake: TOFU, public-key trust, role negotiation
  (Source / Sink / Directory).
- 2.3 Frame encoding: video / audio / blob channels; how
  shmif's segment-event model is mapped to frames.
- 2.4 The directory: rendezvous, hosted appls, the LIST
  command, the [notify] flag.
- 2.5 The package: signed appl bundles, manifest, state slots.
- 2.6 The wire to Tailscale: arcan-net binds a regular TCP
  socket; Tailscale provides the Tailnet routing transparently.
- 2.7 Server-side controllers: appl_load / appl_store hooks
  (per the "Weaving a Different Web" controller story); how
  they shape what travels.
- 2.8 The future: zig-native a12 (ticket 0100's enabling work);
  what changes for the consumer.

**Verb boxes (≥ 3):**
- `builtin dev ||| read /home/x/next/arcan/src/a12/a12.zig`
- `builtin dev ||| sym /home/x/next/arcan/zig-out/bin/arcan-net`
- `builtin dev ||| find /home/x/next/arcan/src/a12`

### Part V Ch 3 — Principal Debugging (a12)

- 3.1 Why analyse: predicting whether a protocol change will
  break the (other) side of the Tailnet.
- 3.2 Static/dynamic split: static = the protocol spec + zig
  source; dynamic = the live session capture (anet_session
  files at repo root are evidence the practice exists).
- 3.3 Four actions across the wire:
  - Subdivide: per channel, per role. Local Source vs remote
    Sink vs Directory.
  - Measure: socket fd via `procfs <pid> fd`; frame timing
    via the `time` bucket; (proposed) `.monitor` stream
    surfacing a12-internal state — Agent D files the verb.
  - Represent: the `anet_session` capture browser as a spread
    (proposed); session-replay via `arcan-net --replay`.
  - Intervene: tunneled hem sessions over a12 — pair-debug
    by joining the same directory.
- 3.4 Information sources: pre = ticket trail + protocol
  source; in = `.monitor` (proposed) + procfs fd; post = the
  `.report` slot retrieved via `arcan-net --get-file .report`.
- 3.5 The conundrum: a remote crash report comes back as a Lua
  script you can replay (per the "Weaving a Different Web"
  developer story). Walk this through end-to-end.
- 3.6 Imperatives: Fail Early = key-pinning at first contact;
  Fail Often = the appl_store hook can record every session;
  Fail Hard = a signature mismatch is fatal, not warned.

**Verb boxes (≥ 4):**
- `builtin dev ||| procfs $(pidof arcan-net) fd`
- `builtin dev ||| time`
- `builtin dev ||| arcan-net --get-file .report - somedir@`
- `builtin dev ||| ps name=arcan-net`

### Part V Ch 4 — Tools of the Trade (a12)

- 4.1 Roll-call: arcan-net's CLI; the directory-side
  config.lua hooks; the `.monitor` / `.debug` / `.index`
  reserved binary slots.
- 4.2 Debugger: `arcan-net` as the canonical debugger CLI;
  the open `.monitor` verb proposal.
- 4.3 Tracer: anet_session captures; `time` builtin
  bucketing the captures.
- 4.4 Profiler: per-frame timing; bandwidth per channel;
  directory-side queue depths.
- 4.5 Visualizer: the proposed `.index` browser as a spread;
  per-session frame heatmaps via shmif `fillRect`. The
  "running this very sysdebug appl over Tailscale" worked
  example: pull from a second sink to validate the
  visibility rule survives transport.

**Verb boxes (≥ 4):**
- `builtin dev ||| arcan-net somedir@ sysdebug` (the recursive case: the appl reading itself over a12)
- `builtin dev ||| arcan-net --sign-tag dev --push-appl sysdebug somedir@`
- `builtin dev ||| arcan-net keystore`
- `builtin dev ||| logwatch /home/x/.arcan/logs net`

---

## Back matter

| File                              | Owner       | Contents |
|-----------------------------------|-------------|----------|
| `parts/00_foundations/refs.lua`   | coordinator | Bibliography: original book full citation; arcan-fe.com article URLs (the 6 catalogued ones plus 2026-01-26 "Weaving a Different Web"); senseye repo; relevant RFCs (TLS, blake3, zstd). |
| `parts/00_foundations/tickets.lua`| coordinator | Auto-generated from `fossil sql "SELECT bug_id, bug_slug, status FROM ticket"`: id, slug, status, which Part chapter cites it. Renderable as a spread; clickable rows publish `payload.bug_id` on viz_bus. |
| `parts/00_foundations/verbs.lua`  | coordinator | Auto-generated index of every verbbox across the appl; clickable rows spawn the hem cell with the chain. |
| `parts/00_foundations/xref.lua`   | coordinator | Cross-reference table: every original-book section → which sysdebug section mirrors it, in which Parts. |

---

## Cross-cutting deliverables checklist

For the coordinator BEFORE any chapter-writing agent is launched:

- [x] `data/appl/sysdebug/sysdebug.lua` — entry point
- [ ] `data/appl/sysdebug/sysdebug_load.lua` — init (rolled into entry point — separate file unnecessary in v1)
- [x] `data/appl/sysdebug/views/render.lua` — block renderer
      (text, h2, h3, epigraph, quote, code, verbbox, ticketref,
      fileref, articleref, crosslink, bridge, rule). `diagram`
      kind reserved for v2; v1 returns "" for it.
- [ ] `data/appl/sysdebug/views/verbbox.lua` — clickable + key
      bound spawn (1-9 launch on current page) — v2; v1 renders
      verbboxes as inline numbered text the reader copy-pastes.
- [ ] `data/appl/sysdebug/views/nav.lua` — index, back/next,
      cross-link follow, footer (rolled into sysdebug.lua and
      render.lua in v1; separate file unnecessary).
- [x] `data/appl/sysdebug/controller.lua` — annotation store +
      `.index` search hook (v1: stub)
- [x] `data/appl/sysdebug/assets/epigraphs.lua` — every quote
      from the original book (v1: empty placeholder; chapters
      currently inline. Migration pattern documented in the file)
- [x] Lint: a chapter without a verbbox renders with a
      `MISSING-VERBBOX` ribbon (in render.lua's lint_visibility)

For each chapter-writing agent, in their brief:

- [x] STYLE.md path + their domain's voice samples
- [x] CONTRACT.md path + the chapter return-table contract
- [x] OUTLINE.md path + the per-chapter section list above
- [x] List of tickets they cite (from the per-Part section above)
- [x] List of verbboxes they MUST include (above the minimum
      counts in each chapter section)
- [ ] Their isolation: a worktree under
      `data/appl/sysdebug/parts/0N_<part>/` so parallel writes
      don't collide — n/a for the single-coordinator workflow
      that wrote Parts II–V here.

For verification (after all four agents return):

- [x] All 21 chapter modules load (5 in Part I + 4×4 in Parts
      II–V): verified via real engine boot and per-chapter
      navigation 2026-05-02
- [x] Every chapter renders without a `MISSING-VERBBOX` ribbon
      (every chapter has 5–13 verbboxes, well above the 2–5
      OUTLINE minimums)
- [x] Every verbbox `chain` parses (no obvious typos) — visual
      spot-check
- [x] Every `tickets` entry resolves to a real file under
      fossil — all referenced slugs verified to exist via `fossil sql`
- [ ] Every `epigraph.cite` page number is in the correct range
      for its claimed chapter section — sourced from OUTLINE.md
      candidates but not formally cross-checked against the PDF
- [ ] Voice spot-check: 3 random paragraphs per Part read
      against a same-topic paragraph from the original (manual
      review still owed)
- [x] `arcan sysdebug` boots — verified via LWA mode
      (`ARCAN_CONNPATH=durian ./zig-out/bin/arcan sysdebug`).
      Standalone mode (no CONNPATH) panics on missing default
      font — engine-side issue tracked separately in bug 0125.
- [ ] `/global/open/sysdebug` from durian — menu entry not
      registered (separate durian config item)
- [ ] `arcan-net --sign-tag sysdebug-dev --push-appl sysdebug
      syslocal@` packages cleanly — not exercised
- [ ] Pull from a second sink; visibility rule survives
      transport (Part V's recursive worked example) — not
      exercised

## v1→v2 follow-on tickets

Items above marked `[ ]` that warrant their own bug tickets
(rather than blocking v1 release):

- v2 verbbox key-bound spawn — needs an appl→hem IPC channel
  for "spawn a fresh hem cell with this CAT9_INIT_CMD"; closest
  existing primitive is the bun TS-side `hemSpawn` in
  build_llvm/examples/arcan-shmif.ts (per CLAUDE.md). File a
  ticket: "sysdebug: appl-side hem cell spawn primitive".
- Standalone-mode default font init — bug 0125 third entry-point
  fix (the vk-display struct mismatch landed 2026-05-02 in this
  session) but no parallel fix exists for the no-CONNPATH path.
  Likely needs a `system_defaultfont` call in the engine bringup
  before any appl runs. File a ticket.
- /global/open/sysdebug — durian menu entry. Trivial config
  change in durian's lash menu; out of scope for this appl.
- a12 packaging + recursive Part V test — exercises the appl
  end-to-end across the wire; useful but requires a second sink
  to pull from.
- Migrate inline epigraphs to assets/epigraphs.lua — mechanical
  refactor; do once when the duplication actually starts to bite.
