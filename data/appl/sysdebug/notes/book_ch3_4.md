# Original book, chapters 3–4: extracted material

Coordinator notes — verbatim quotes and section summaries from
*Systemic Software Debugging* (Mellstrand & Ståhl 2012, CC-BY 3.0,
`/home/x/next/arcan/systemic-software-debugging.pdf`). Chapter 3
is the methodological core; quote-budget here can skew slightly
heavier than for other chapters. Chapter 4 covers tools.

---

## Chapter 3: Principal Debugging (pp. 71–117)

**Chapter overview.** Methodological core. Contrasts *analysis*
(understanding what causes unwanted behavior) from *debugging*
(fixing it). Establishes an iterative methodology centered on
**system views** and **analysis actions** — subdividing complex
systems, measuring behavior both static and dynamic, representing
findings intelligibly, and intervening to test hypotheses. Throughout,
the authors emphasize that analysis is experimental: the analyst
gains knowledge by direct interaction with a system, measuring
properties, and testing expectations against observable outcomes.

### 3.1 Why Analyze a System (p. 72)

Systems age and drift; new requirements demand changes;
understanding the system at hand becomes critical to safe
modification. The task is to **explain why a system behaves in a
certain way** at an appropriate level of abstraction, sufficient
for fixing without necessarily pointing to a particular line of
code. Analysis rediscovers forgotten secrets, identifies root
causes, devises fixes that address the problem rather than
symptoms.

> Those that previously possessed the knowledge of decisions made
> as to how the system was thought up (designed) and written
> (developed), may no longer be available, or their knowledge, in
> any form, may be inaccurate. (p. 72)

> We can say that it has been tightly integrated, or coupled, to
> its environment. (p. 72)

> To make these kinds of alterations, we need to understand the
> system at hand, not only to discover where to change something
> but also to determine potentially adverse consequences to such
> alteration. (p. 72)

**Hook:** the senseye visualization and hem spread model
externalize internal state as navigable representations, allowing
explanation at multiple levels of abstraction without source-code-
only views.

### 3.2 Software System Analysis (pp. 72–73)

Analysis requires explaining unwanted behavior at an
operationalizable level — a level useful for fixing — without
demanding a direct algorithmic prescription. The analyst constructs
an abstract method based on principal software properties.
Methodology is iterative and assumes the causal chain is in fact
connected to the system, and not trivial. Distinguishes static
sources (code, design docs, build artifacts: immutable, high
repeatability) from dynamic sources (execution traces, profiler
output: actual behavior but require careful interpretation).

> The real task that lies ahead of the analyst is to explain why a
> system behaves in a certain way, give this explanation at an
> appropriate, or operationalize-able, level of abstraction such
> that it – at least in theory – is useful for fixing the system.
> (p. 72)

> On realizing source code: large software systems are inherently
> too complex to understand by considering only source code and
> other static sources. (p. 75)

> While each and every software system is unique and has its very
> own dents and scratches, the way in which we develop software –
> the programming languages, the tools and the machines – are
> shared. (p. 75)

**Hook:** hem spreadsheet model + senseye multi-layered views
embody this — both static (source structure, symbol tables,
layout) and dynamic (execution flow, memory state, message
traces) made simultaneously intelligible. Analysts iterate between
views.

### 3.3 System Views and Analysis Actions (pp. 77–92) — the four-action core

A **system view** is the analyst's current mental model — what
aspects they consider relevant for the task at hand. Views change
as analysis progresses. Analysts combine **expectations**
(hypotheses), **measurements** (static and dynamic properties from
tools), and **representations** (ways to make measurements
intelligible). The methodology centers on four actions:

1. **Subdivide** — divide the system into manageable communicating
   subsystems
2. **Measure** — static (code, symbols, layout) and dynamic
   (execution, values, flow) properties
3. **Represent** — make measurements intelligible
4. **Intervene** — test hypotheses by interacting with the system,
   gain feedback about causality

Side effects of measurement (especially dynamic) must be understood
and minimized — the act of measuring can distort.

> We use the term system view to describe all aspects of a system
> the analyst actively considers (and considers relevant) for the
> particular task at hand. This will include many different
> aspects of the system and change significantly as the analysis
> progresses. (p. 77)

> The principal advantage of using an experimental approach is
> that one works with the actual behavior of the target system.
> This enables the analyst to establish a feedback chain where he
> or she measures properties inside the system he or she
> manipulates. This is a large advantage over, and in stark
> contrast to, methods that consider only source code and/or other
> properties of a system. (p. 76)

> While there is no way of guaranteeing a successful analysis for
> any methodology, we argue for an experimental approach to
> software analysis in general and for our methodology in
> particular. (p. 76)

**Action 1 — Subdivide** (pp. 80–81):
Central to analyzing a complex system is dividing it into
analyzable communicating subsystems. Subdivision focuses analysis
and permits instrumentation at borders.

> We can, due to the way software is constructed, always divide a
> software system into one or more system of subsystems and
> partitioning a system in ways befitting of the particular
> problem at hand is one of the primary challenges for an analyst
> to deal with. (p. 80)

**Action 2 — Measure** (pp. 82–88):
Substantial part of analysis: measuring different properties.
Static measurement requires reverse path through compilation/
linking back to source. Dynamic measurement is harder because
behavior is itself dynamic.

> Measuring a static aspect of a software system at an
> operationalizable level of abstraction (i.e., where it is
> feasible for someone) means that the analyst must follow a
> reverse path through the compilation and linking process to the
> original source code. (p. 83)

> What makes dynamic properties so important is that every type of
> software behavior is a dynamic property, and thus the actual
> unwanted behavior that should be explained is a dynamic
> property. What makes dynamic properties so difficult is that
> there is no way to directly create them. (p. 85)

**Action 3 — Represent** (pp. 89–91):
No human can directly understand raw measurements. Finding a
representation makes data understandable.

> There is no way for a human analyst to directly understand
> measurements from a software system. No human analyst has a
> sense for bad tree balancing, incorrect parameters or the use of
> NULL pointers. To understand measurements from a software
> system, the analyst must find some way to read, visualize or
> project the data such that it makes sense. (p. 89)

**Action 4 — Intervene** (pp. 91–92):
Provides strong feedback. Compare actual behavior with and without
modification.

> Intervening with a system is the real core business of
> experimentation and provides strong feedback to the analyst.
> When intervening, the actual behavior of the system with and
> without some modification can be studied and compared. Because
> of the comparably high reproducibility of unwanted behavior in
> software and the possibility of subdividing a system into
> smaller parts, intervening with a system can be used at many
> different levels of abstraction and provide the feedback
> required for the analysis to progress. (p. 91)

> We argue that the same principal borders that are used in a
> system when measuring dynamic data can be used to intervene with
> the executing system. (p. 92)

**Hook:** hem + senseye + viz_bus directly implement these four
actions: spreadsheet subdivision (Subdivide), instrumented views
(Measure), navigable tables and visualizations (Represent), state
modification or flow redirection at subsystem boundaries
(Intervene).

### 3.4 Information Sources (pp. 93–104)

Information sources by phase:
- **Pre-Execution**: source code, design documents, build systems,
  compilers, linkers — static and deterministic
- **In-Execution**: external I/O, entry points, system calls,
  contrast material — require active control and measurement
- **Post-Execution**: crash dumps, snapshots — passive but reveal
  final system state at failure

Each source has limitations: compile-time information may be
incomplete or lost during linking; in-execution measurement risks
side effects; post-execution analysis may occur too late to recover
intermediate states. The analyst must develop facility with the
**transformation toolchain** (compiler → linker → loader →
runtime) and understand which information persists or is lost at
each stage.

> It is tempting to accept the notion that all information
> available at this stage is both necessary and sufficient to
> determine and adjust everything that could ever be known about –
> or happen to – a system. But already during the dawn of the
> theoretical foundations to computing, the ultimately undecidable
> problem of determining if a program will ever finish was
> described, a problem which also correlates to determining other
> states using program code alone, and the view of a computer
> program when these ideas were coined was far more simplistic
> than the software intensive systems that we are forced to deal
> with. (p. 94)

> Source code is the first formal description that has enough
> precision to either directly – or through some transformation –
> form each individual component of the intended system. (p. 95)

> Post-execution analysis may be one of the most beneficial
> sources of information given some fairly common circumstances,
> and for many situations, it is the only one available. (p. 103)

**Hook:** arcan's separation into afsrv components (pre-execution
artifacts), runtime event tracing via senseye (in-execution), and
post-mortem crash analysis (post-execution) mirrors the three-phase
information-source architecture. hem spreads can reference
pre-execution artifacts (symbol tables, source line mappings)
while displaying in-execution measurements from viz_bus and
post-execution state from crash dumps.

### 3.5 The Software Analysis Conundrum (pp. 105–109)

Post-mortem faces a fundamental problem: snapshots and crash dumps
reveal state at failure but provide incomplete information about
the causal chain. Analyst reconstructs execution path and state
transitions backwards with incomplete data. Compounded by state
space explosion. Conundrum is about repeatability and exploration:
crashes are often rare and context-dependent yet analysis demands
reproducibility.

> Snapshots and crash dumps are the central sources for
> information at a post-execution systemic state. They spring into
> place from different, but similar mechanisms. A snapshot is
> generated upon some external request whereas a crash dump is
> generated as a reaction to some event that renders the system
> terminal. (p. 105)

> If the system is damaged to the degree that it crashes, chances
> are high that there may be a proximate-onset-proximate-cause
> type scenario in play: close to the crash point (at a low level,
> code pointed by by the program counter), there will be clear
> signs of the immediate cause of the crash and by backtracking
> changes (at a low level, unwinding stack) to the relevant state
> and location from where these changes were initiated, it is
> likely that the culprit will be within the reach of a few
> instructions. (p. 105)

> Throughout this chain of thought, there's been the underlying
> assumptions that a) by using the input of a core dump from a
> crashed system we can deduce what the immediate cause was (as
> shown, we can!), b) we can restart (or rather, create a new
> instance of the same system) and determine that we're about to
> step into the condition from the first point listed (we can!)
> and draw the conclusion that this could be repeated iteratively
> until we reach the ultimate cause. (p. 109)

**Hook:** arcan can capture state snapshots (senseye snapshots),
replay execution segments (a12 over Tailscale with recorded event
streams), and reconstruct causal chains through subsystem
instrumentation. Treat the arcan display server as a distributed
state machine with event replay capabilities. The auto-arch loop's
round-as-snapshot model is the operational form of this argument.

### 3.6 Analysis Imperatives (pp. 110–117)

Three imperatives:

- **Fail Early**: the sooner a failure is detected, the less time
  is lost and less evidence is destroyed; pre-execution detection
  (compiler, static analysis) preferred; in-execution via
  assertions next; post-execution via crash dumps fallback.
- **Fail Often**: making bugs reproducible and frequent is critical;
  testing and instrumentation should surface failures reliably so
  causal chains can be explored without rare race conditions
  confounding analysis.
- **Fail Hard**: when failure is detected, halt execution
  decisively (crashing cleanly, not silently corrupting state) so
  the analyst can inspect state at the moment of failure;
  graceful degradation may hide bugs.

> The longer it takes from something failing to the failure being
> discovered the harder it is to find out what happened. As time
> elapses important evidence from the system is lost, but also the
> people working with the particular something that failed forget
> about the assumptions they made and their possible implications.
> (p. 110)

> Analyzing a bug is typically far more time consuming than fixing
> it. Thus, the results from an analysis are a poor input when
> deciding what to fix and what to ignore. (p. 115)

> Closely related to failing early to avoid damaging important
> state and failing often to get usable statistics is failing hard
> to make sure the few scarce clues that aid system analysis
> aren't lost in some log never to be read or even piped to
> /dev/null by a sinister system administrator. While political
> considerations may mandate the use of other methods than system
> termination, always make sure information about system failures
> reaches the analysis department. (p. 116)

> Certain problems, which are likely to cause unwanted behavior,
> are visible already in source, object or binary code.
> Preferably, such issues should be automatically identified by
> the toolchain as it transforms the software. (p. 111)

> Software executes at a tremendous speed: state changes, data
> moves around and there is no way for a human analyst to observe
> everything that goes on. When things go wrong, the analyst wants
> to know what went wrong, typically at a very low level of
> abstraction. In order to find this out, it is important that the
> software does not continue to execute, as doing so will change
> the state and move data around thus making it harder to find out
> what actually went wrong with the software. (p. 112)

**Hook:** arcan's separation into isolated segments (afsrv_bun for
sandboxed scripts, seL4-zig for verified isolation) implements all
three imperatives: Fail Early via static type checking in Zig,
Fail Often via comprehensive event logging in senseye, Fail Hard
via cleanly crashing subsystems with crash dumps available for
post-mortem via hem.

---

## Chapter 4: Tools of the Trade (pp. 119–143)

**Chapter overview.** Shifts from methodology to implementation.
Surveys **debuggers** (intervene in execution and examine state),
**tracers** (record execution flow and data movement), and
**profilers** (measure performance and resource usage). Rather
than catalog tools, focuses on how these instruments work at
different levels of abstraction. Emphasizes fundamental tradeoffs
between intervention (can alter behavior) and observation
(passive but requires careful interpretation).

### 4.1 Layout of this Chapter (p. 119)

High-level: debugger features (breakpoints, watchpoints, stack
inspection, source/machine state representation); debugger problems
(state-sensitive instruction decoding, instruction length
ambiguity, undocumented behavior, backwards disassembly); tracer
and profiler sections follow same structure.

> The developer, just like other craftsmen, has an extensive array
> of tools at his disposal. In Software Demystified, the
> cooperation between tools (like compilers, linkers and loaders)
> that piece software together was covered to the point where a
> description had turned into an executing software, and now the
> time has come for the selection of tools specifically created
> for studying and tweaking running targets. Although knowledge on
> the usage of, for instance, debuggers is fairly well known, the
> mechanics on which they rely may be a bit more shrouded in
> mystery. (p. 119)

**Hook:** by building debugging and tracing into the native
architecture (senseye, hem, viz_bus), arcan avoids the impedance
mismatches of retrofitting generic debuggers — work at the
abstraction level natural to the problem.

### 4.2 Debugger (pp. 120–131)

Debugger = dynamic tool working on an executing system.
Manipulates execution state (breakpoints, watchpoints, stepping)
and explores state (registers, memory, stack unwinding) by
intervening through hardware breakpoints, kernel interrupts, OS
process control. Achieves **representation** by mapping machine
state back to source-level constructs using debug metadata (DWARF,
PDB). Core challenges: state-sensitive instruction decoding,
instruction length ambiguity, undocumented instructions.

> The term Debugger has unfortunately already turned into an
> ambiguous one. The most frequent use seems to be that of a
> source-level debugger, probably because it is one of the tools
> closest to the larger majority of developers; most larger IDEs
> and tool suites integrates one or several sorts of source-level
> debuggers. (p. 120)

> A debugger assist with debugging by allowing manipulation, the
> intervention, of execution flow and exploring of the state. The
> idea of source-level debugging denotes a form of representation
> where commands and measurements are mapped to source code. One
> important attribute that can be deduced from this description is
> that a debugger is a dynamic tool working on an executing
> system. (p. 120)

> Manipulating Execution State – This is a necessary feature for a
> debugger. As stated in the chapter entitled Principal Debugging,
> a large problem with a dynamic and executing target is the state
> and particularly the rate at which the state changes. (p. 120)

> Exploring the State – On the other side of the coin, there is
> state exploration. While merely altering execution state may
> have some merits as an intervention, it is better to attach some
> sort of meaning to the fact that an interruption in the
> execution flow has occurred. (p. 120)

> Call It a Stack – A debugger can show which instructions lie at,
> in front of, and possibly also before a particular breakpoint.
> It can also provide information on the register state and about
> whatever is being stored in certain memory locations when such a
> breakpoint has been triggered. If the locations in question are
> covered by data extracted from a debug information format, the
> connection can also be expanded to specific lines in source code
> at the involved declarations and statements – if the information
> provided is accurate, that is. All of these are various levels
> to show where we are in execution at that very moment. (p. 129)

**Hook:** arcan's senseye implements debugger-like intervention
and state exploration at the subsystem level: breakpoint-like
pausing of subsystem execution at message boundaries or named
events in the afsrv protocol; state exploration through senseye's
table-based views; representation mapping through hem's
symbol-to-address and source-line-to-instruction translation.

### 4.3 Tracer (pp. 131–138, partial extracted)

A tracer records exact execution flow without pre-set breakpoints.
Operates at lower overhead than debuggers when comprehensive flow
is needed, but requires storage and post-processing. Tracers
produce a **log of executed instructions** rather than pausing for
interactive inspection; log can be replayed, searched, analyzed
offline. Output must be translated (disassembled) back to source
level. Volume can be enormous; requires filtering and
summarization.

> The kernel call trace – creates a log of the communication
> between its target and the operating system kernel. (p. 85,
> from Ch 3 information-sources discussion)

**Hook:** senseye's event recording and replay function as a
tracer: by logging all state-changing events in arcan and
subsystems, analysts reconstruct execution flows post-hoc without
real-time breakpoints, enabling analysis of intermittent failures
and race conditions difficult to trigger reliably with traditional
debugging.

### 4.4 Profiler (pp. 138–141, partial extracted)

A profiler measures performance and resource usage (CPU time,
memory allocation, cache misses) by sampling or instrumenting.
Answers "where does the system spend time or resources?" Balances
accuracy (fine-grained measurement) against overhead (the
profiler's own cost can distort measurements). Output aggregated
and summarized (call graphs, hot spots, allocation histograms) to
be useful.

**Hook:** arcan's built-in performance monitoring (message queue
depths, frame timing, memory usage per subsystem) serves the
profiler role, allowing identification of bottlenecks and resource
contention without external profiling tools that might impose
unacceptable overhead in a real-time system.

---

## Synthesis: alignment with arcan's architecture

The methodological core of Chapter 3 — **system views,
subdivisions, measurements, representations, interventions** —
maps directly onto arcan's distributed subsystem model:

1. **System Views** = hem spreadsheet panes, each showing a
   different aspect of the same arcan instance.
2. **Subdivision** = natural boundaries between afsrv components,
   zig-based service implementations, seL4-verified microkernels;
   hem lets the analyst focus on one subsystem while keeping
   others in context.
3. **Measurement** = senseye's dynamic probes, viz_bus queries
   into subsystem state, symbol tables from the Zig compiler.
4. **Representation** = hem cell formatting and graph rendering,
   transforming raw byte values into intelligible structures.
5. **Intervention** = ability to pause subsystems at message
   boundaries, inject faults, modify state through hem write
   operations, implemented safely via subsystem isolation
   (seL4-zig).

Chapter 4's emphasis on understanding tool mechanics justifies
arcan's choice to build debugging and analysis facilities natively
rather than relying on external tools that may not understand
arcan's concurrency model, IPC semantics, or real-time
constraints. By making **analysis a first-class concern** in the
architecture — with senseye, hem, viz_bus as native facilities —
the system achieves the experimental approach the original
authors advocate.
