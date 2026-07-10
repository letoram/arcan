# Original book, chapters 1–2: extracted material

Coordinator notes — verbatim quotes and section summaries from
*Systemic Software Debugging* (Mellstrand & Ståhl 2012, CC-BY 3.0,
`/home/x/next/arcan/systemic-software-debugging.pdf`). Use these
when picking epigraphs and bridge content; do not re-derive by
re-reading the PDF unless you are revising structure.

---

## Chapter 1: Introduction (pp. 1–37)

**Chapter overview.** Chapter 1 establishes the philosophical and
practical foundations for software debugging by defining the scope,
methodology, and core challenges of analyzing software systems. It
moves from definitional clarity through examination of real-world
failure cases (the Überlingen collision, the 2003 blackout) to
articulate how bugs originate from multiple sources and how
developers must reason about causality across complex,
interdependent systems. The chapter concludes by introducing a
structured taxonomy of effects and debugging methods as the
necessary bridge between casual observation and systematic
analysis.

### 1.1 Demarcation (pp. 3–8)

Establishes the scope of software analysis by defining which
analytical techniques (static, dynamic, automated) are appropriate
for debugging and system improvement, emphasizing that focus is on
understanding actual state during execution rather than
hypothetical behavior. Distinguishes between analysis applied
during development (where software is loosely coupled to
stakeholders) and analysis applied to deployed systems (where
changes carry high consequences), requiring different risk
tolerance and methodology. Argues that the technical challenge is
not merely methodological but contingent on understanding machine
limitations and program structure — tools assist humans in
reasoning about systems, not vice versa.

> The focus for this and coming chapters is primarily on dynamic
> analysis as a means for grasping and refining an understanding
> of the particulars of a given system and, to a lesser degree,
> how we can manipulate software during all stages of construction
> in order to ease future analysis. (p. 5)

> Static analysis can also be found as part of some formal
> development methods, in particular parts related to improving
> some supposed quality; examples include code, design,
> architectural and requirement reviews either made directly or
> through simulation. (p. 3)

> These are only tools to assist programmers, not the actual
> machines. No matter what abstractions one rely on, it is
> ultimately the limitations of the machine that will apply.
> (p. 6)

**Hook for arcan/zig:** the developer of a self-hosted zig fork or
a seL4-zig bootstrap must decide whether static analysis (compiler-
enforced safety properties) or dynamic instrumentation (runtime
tracing of malfunction) is appropriate at each stage, especially
since the compiled artifact will serve as both a diagnostic tool
and a runtime component that cannot be easily modified
post-deployment.

### 1.2 Software and Software-Intensive Systems (pp. 9–22)

Traces the historical transition from software-as-punch-cards
(discrete, isolated) to software-intensive systems (coupled,
interdependent, continuously deployed); introduces black-box
reasoning about subsystems with incomplete knowledge; uses the
2003 Northeast American Blackout as a case study showing how a
single SCADA logging bug cascades through operator and
infrastructure dependencies.

> At this point software has turned into a dynamic entity composed
> to a large degree of building blocks shared with other programs,
> capable of moving between machines and reshaping itself as a
> reaction to external stimuli. We are now moving away from the
> realm of software-as-punch-cards and into software-intensive
> systems, where systems are composed of many different kinds of
> software, running on a variety of machines in close
> collaboration with other kinds of devices and processes both
> mechanical and human. (p. 10)

> One aspect of our dealings with these kinds of systems is that
> of a black box. To clarify, on an individual basis there are
> parts of most systems which are somewhat foreign in that we do
> not know about (or choose to ignore) some of the inner workings
> but still focus on details of its possible application or
> function. (p. 12)

> Will anyone know what to do if – or rather when – a serious
> problem occurs? Currently abstractions, on adding new ones for
> that matter, will do little more than mislead while one is
> standing knee deep in cascade effects from some twenty year old
> low-level oddity. (p. 12)

**Hook:** arcan must navigate the black-box problem with legacy
client toolkits, X11 protocol stubs, OS-level resources without
full visibility into subsystem state. A zig-based rewrite benefits
from understanding that each external subsystem boundary
introduces assumptions that must be validated dynamically, not
merely documented.

### 1.3 Cause and/of Panic (pp. 15–22)

Distinguishes proximal vs distal causes via the Rube Goldberg
metaphor; introduces multicausality (modern concurrent systems
have no single root cause); uses Überlingen and the 2003 blackout
as case studies showing software bugs are entangled with human
factors, organizational procedures, and physical infrastructure.

> To ease this somewhat, we can study behavior in terms of
> proximal and distal causes. The proximal cause for the Goldberg
> machine would be the trigger that starts the machinery. The
> distal or ultimate cause is whatever event initiated the trigger
> in the first place. This is just an overlay subdivision when
> looking for explanations whilst unwinding some undesired effect
> in systems we do not fully comprehend. (p. 17)

> A major part of software analysis and debugging is determining
> which factors involved caused a certain undesired effect to
> occur in order to feed this back into upcoming instances of the
> software, preferably by changing some offline artifact like
> source code. (p. 18)

> These factors can be further refined into sub factors
> highlighting many underlying technical and managerial problems,
> but suffice it to say that if any one of the major factors had
> been removed the collision could have been avoided. (p. 21)

**Hook:** debugging a12 over Tailscale spans Zig-layer resource
leaks, Tailscale packet reordering, remote frame buffer protocol
misinterpretation, and misaligned assumptions about network
latency. Resist single-cause attribution.

### 1.4 The Origin of Anomalies (pp. 23–33)

Defines an anomaly as deviation between expected and observed
behavior — only contextually a "bug" when stakeholders deem it
undesirable. Catalogs sources: developer inconsideration; flawed
assumptions about subsystem internals; environment drift. Catalogs
common effect types: data corruption, terminal state, inadequate
performance, race conditions, deadlocks, buffer/heap/stack
overflows, dangling pointers, protocol/type mismatches, resource
leaks.

> An anomaly, or the deviation between expected or intended
> behavior and actual (or rather observed) behavior, is somewhat
> more complex than we initially depicted in the first paragraph
> of the introductory text; all other entries describe something
> awry rather than unexpected. By itself, an anomaly is neither
> positive nor negative but may be established as one or the other
> after evaluation. (p. 23)

> The primal aim on the origin of anomalies is that each and every
> bug is simply an inconsideration on behalf of the developer. As
> a developer there are literally hundreds of protocols,
> conventions and interfaces within the machine, language and
> execution environment that, to a variety of degrees, need to be
> followed. (p. 24)

> Buffer overflows are reasonably easy to find and deal with when
> looking at performance. A special case of buffer overflow is the
> off-by-one where an array incorrectly is asserted to be one
> element too large. (p. 30)

**Hook:** Zig's memory safety model addresses inconsideration for
buffer overflows and type mismatches. A self-hosted zig fork must
document which protocol assumptions are enforced at compile time
vs runtime.

### 1.5 Debugging Methodology (pp. 34–36)

Contrasts "find the cause and fix it" (naive) with the
hypothetico-deductive method (gather → hypothesize → predict →
test → iterate) and shows the latter is also incomplete for
multicausal systems. Argues debugging is craft requiring judgment
about tools, abstraction levels, and isolation strategies.

> A method, or simple instructions for getting something done, is
> in some cases a useful tool when trying to avoid repeating
> mistakes others have made in the past. Methods come in a variety
> of shapes at different levels of abstraction. Some methods for
> dealing with trivial problems, such as troubleshooting a washing
> machine, can be overly complex and detailed. Other methods –
> perhaps for dealing with very complex problems – are too vague
> to be of any real-world problem. (p. 34)

> This method suffers from several problems. Firstly, it says
> nothing about how data is to be collected (i.e., how to actually
> observe software behavior) but seems to leave this up to the
> investigator. (p. 35)

> Our point with this example and the discussion on debugging
> methods and methodologies is that there exists a plethora of
> guides and descriptions (often cited methods) for software
> debugging. More often than not, there is some claim of
> scientific value in these methods, but given a closer
> examination the methods seem empty, irrelevant or trivial.
> (p. 36)

**Hook:** developers building zig-based arcan or self-hosted
bootstrap face choice of diagnostic tools (instrumentation vs
static analysis, replay vs live observation). The chapter's
insight motivates modular composable tooling — different
strategies for different subsystems.

### 1.6 Concluding Remarks (pp. 36–37)

Recaps; emphasises that "what is software?" is the foundational
open question; bridges to Chapter 2.

> A major question still lingers however: what is software?
> (p. 36)

**Hook:** Zig's comptime and reflection blur source/runtime;
self-hosted-zig developers must reason about software in the
presence of staged computation and metaprogramming.

---

## Chapter 2: Software Demystified (pp. 39–69)

**Chapter overview.** Walks the full pipeline of software
construction: from source code, through compilation and linking,
to executable binaries loaded into RAM and executed on hardware
with OS mediation. Demystifies each stage — compiler parsing,
object code generation, linker symbol resolution, loader setup,
runtime execution — showing how properties of code manifest as
machine behavior and how each stage introduces constraints and
opportunities for debugging.

### 2.1 Hello, World. Is This a Bug? (pp. 40–42)

Presents a minimal C program with intentional bugs (missing return
type, undefined argv behavior, potential NULL dereference in
sprintf) to illustrate that even trivial code hides deep questions
about compilation, toolchain, environment, machine state. Raises
four diagnostic questions: will it compile? is argv used
correctly? are snprintf parameters correct? are printf parameters
correct? Each requires knowledge of compiler behavior, library
semantics, machine architecture, runtime environment.

> To determine the behavior a particular piece of software will
> present when executing, one must have an extensive knowledge
> about the system at hand. This includes knowledge of the
> particular piece of software being inspected, as well as
> knowledge about adjacent software which constitutes the
> execution environment for the part being inspected. In addition
> to knowledge of the system as such, one must also understand
> how the high-level description is transformed into the
> machine-readable entity, which is where the bug actually
> manifests itself. (p. 40)

> To answer the second and third questions, information about the
> larger system and how it behaves during execution in regard to
> certain situations is needed. (p. 41)

**Hook:** for afsrv_bun or zig-based arcan, even minimal startup
involves zig→machine code, OS loader segment mapping, calling
convention assumptions. Trace artifacts through the entire
pipeline rather than reason locally.

### 2.2 Transforming Source Code into an Executable Binary (pp. 43–44)

Outlines the toolchain (source → compiler → object → linker →
binary). Each tool consumes the previous tool's output. Modular
construction allows replacing one component without rewrites.

> A few years ago there were still simple software systems where a
> single source code file was either compiled or interpreted and
> constituted the entire software part of a larger system. For
> such a case, there is a straightforward connection between
> source code and the end output. For essentially all modern
> systems, there is a large set of tools involved in the
> transformation from human-readable high-level source code to the
> executable binary which a CPU can execute. (p. 43)

> The key principle for a toolchain is that a series of tools is
> to be applied where the output from one tool is the input to the
> next. The initial input is what the developer has written, and
> the final output is something which can be loaded and executed
> by a CPU. This layout enables the flexible construction of
> toolchains where one component can be replaced without vastly
> affecting other tools and other parts of the chain. (p. 43)

**Hook:** for self-hosted zig fork, understanding the toolchain is
foundational. Zig's compiler (in the upstream path) generates LLVM
IR; the sh-zig fork takes a different path. For seL4-zig
bootstrapping or custom loader work, developers must instrument or
patch the toolchain at the appropriate level.

### 2.3 Developer and Development of High-Level Code (p. 44)

Developers translate informal requirements (diagrams, prose) into
formal source. There is no automated path; developers make
assumptions, generalizations, simplifications. Many bugs originate
here.

> There is no automated way to transform an informal description
> of a system into a formal description, and to do this task a
> developer must make a number of assumptions, generalizations and
> simplifications. Many bugs in software originate from incorrect
> assumptions in this phase and for the successful diagnosis of a
> software system it is vital to understand how a developer
> reasoned when he or she wrote a specific piece of code. (p. 44)

**Hook:** when porting arcan to Zig or bootstrapping a seL4-zig
runtime, every assumption (memory layout, concurrency model, error
handling) is a potential anomaly source. Documentation of
developer reasoning (comments, invariants, type signatures)
becomes a diagnostic resource.

### 2.4 Source Code and the Compiler (pp. 45–47)

Source code is a formal language with syntactic and semantic
rules. Compilers parse and analyze; produce object code.
Distinguishes static analysis (operating on source) from dynamic
(measuring during execution); most dev tools are static.
Highlights interfaces, imported/exported entities, calling
conventions as the bridge.

> A programming language is a formal language (as opposed to a
> natural language such as Swedish) which implies that for a
> source code file to be valid for a particular language a number
> of formal requirements must be met. These requirements are often
> divided into two categories: syntactical and semantical. (p. 45)

> No high-level language allows for unrestricted communication
> between its principal entities or communication as free as the
> actual machine code allows. Understanding the restrictions
> placed on high-level languages is essential when hijacking
> execution, which is a key to tracing and debugging complex
> software systems. (p. 46)

**Hook:** Zig's strong type system and explicit error handling
are stricter than C, looser than some FP languages. When building
zig-based arcan, developers benefit from understanding how Zig's
restrictions translate into machine code and calling conventions,
especially when interfacing with C or OS services.

### 2.5 Object Code and the Linker (pp. 48–53)

Object code = compiler output: compiled functions, constants, data
sections with symbolic references. Linker combines object files,
resolves symbolic references. The linker is the only tool that
sees the entire system at once. Compiler sees only one source file
at a time. Describes name mangling, trampolines, machine
constraints.

> In a modern tool chain the linker is the only tool that
> considers the entire system at once. The compiler considers only
> one single source code file at a time, possibly together with
> some header files, but never the entire system. Similarly, a
> loader considers only parts that actually are loaded and ignores
> secondary information such as debugging information that may be
> embedded into a system. The principal function for a linker – to
> bind the software together – requires that the entire system is
> considered as a single large chunk. (p. 51)

> It is important that one understands this fundamental difference
> between the linker and other components in a building tool chain
> when diagnosing the system. This is to both to understand what
> can be done with the linker and perhaps more importantly what
> cannot or should not be done with a compiler or preprocessor.
> (p. 51)

> C and, more importantly, its ideas on how execution should be
> managed play a large role as structural glue between components
> of many different programming languages and is as such a de
> facto standard in software interoperability. (p. 53)

**Hook:** for zig-based arcan or afsrv_bun, the linker is a
diagnostic and instrumentation point. Use linker capabilities to
inject tracing stubs, verify symbol visibility across module
boundaries, or apply global optimizations (dead-code elimination
for resource-constrained targets like seL4 bootstrapping).

### 2.6 Executable Binary and Loading (pp. 54–57)

Executable binary = file on disk with code, data, metadata.
Loading copies sections to RAM at specified addresses. Static vs
dynamic executables: static = self-contained, all symbols resolved
at link time; dynamic = symbol references resolved at runtime by
runtime linker.

> The executable binary file is the principal output from the
> linker and the system in its final, static form. The linker has
> translated the executable binary as far as possible meaning that
> symbol names and references have been replaced with addresses
> which can be handled by a CPU. Despite being translated to a
> format close to the machine, an executable file cannot be
> executed as is. For a CPU to actually execute the file, it must
> be directly addressable in memory. (p. 54)

> Self-contained executable files which can be loaded and executed
> without any external dependencies are called static executables
> or statically linked binaries. This type of executable system
> has a very limited ability to communicate with its environment.
> (p. 55)

> On a conceptual level a dynamic executable is very similar to a
> static executable. It is a file which can be loaded into RAM by
> a loader and executed by a CPU. In contrast to a static
> executable, the dynamic is not entirely self-contained but may
> contain dependencies to other dynamic executables, unknown even
> to the linker, and which must be combined on the loading process
> to form an entity in RAM which can actually be executed. (p. 56)

**Hook:** for seL4-zig bootstrapping or embedded arcan targets,
static vs dynamic linking is consequential. Static reduces runtime
complexity and dependency risks (good for microkernel bootstrap).
Dynamic enables modularity (good for full arcan compositor).
Understanding loading mechanics is essential for debugging
misaligned memory regions, missing symbols, unexpected shared-
library behavior.

### 2.7 Executing Software and the Machine (pp. 58–62)

Marriage between loaded code and hardware: CPU fetches
instructions from PC, decodes, modifies state (registers, memory,
flags). Execution behavior depends on instruction set, privilege
levels, protection mechanisms (MMU, interrupts, exceptions). From
the machine's perspective there is no "intended" vs "unintended"
behavior — the machine executes as specified. Anomalies are
defined only from the human perspective.

> The core of a software system is the executable composed of a
> sequence of instructions that will be executed by some
> processor. When a processor executes instructions, each
> instruction modifies the state of the processor in some way. The
> accumulation of these state modifications is what constitutes
> the behavior of the executing software. (p. 58)

> Even though in the turing-complete world of computers every
> computation is theoretically possible with any turing-complete
> system, the efficiency and actual implementability depends on
> the underlying computational model. In the real world, not all
> computations are equally feasible given the constraints. In
> these cases the developer may face a considerable challenge in
> working around the processor limitations or may have to trade
> off between different implementation approaches. (p. 58)

**Hook:** for zig-based arcan running on diverse hardware (ARM,
x86, embedded via seL4), understanding machine execution is
critical. Zig's multi-target compilation and platform-specific
calling conventions help, but developers must reason about how
Zig code maps to instructions, especially in time-sensitive
rendering loops or interrupt handlers. The Asahi
BUILD_PROFILE=release rule is exactly this section's principle in
action.

### 2.8 Operating System and the Process (pp. 63–69)

Process = OS abstraction for isolated execution; virtual address
space per process; MMU mediation. OS scheduler multiplexes the
CPU. OS manages resource allocation and arbitration. From the
process's perspective it appears to have exclusive use of the
machine; debugging reveals concurrent OS activity, interrupt
handlers, other processes.

> When the operating system loads a program into memory as a new
> process, it constructs a virtual address space in which that
> process is supposed to operate. The virtual address space is a
> level of abstraction which allows the kernel to control how the
> process allocates and accesses the physical memory. (p. 65)

> The operating system in its broadest sense is tasked with
> providing a set of services to programs or processes that are
> running on the physical hardware. Among the most important of
> these services are memory management and process/thread
> scheduling. Further services include but are not limited to
> interrupt handling, exception handling, inter-process
> communication, file system management, and device driver
> management. (p. 65)

> The scheduler is the part of the kernel responsible for deciding
> which process should be allowed to run at a given point in time.
> The mechanism by which the scheduler operates in most systems is
> through preemption: the process running on the CPU is
> interrupted (typically through a timer interrupt) and control is
> returned to the kernel, which then selects another process to
> run. (p. 66)

**Hook:** for a12 over Tailscale or zig-based arcan, the OS
abstraction is strength and bug source. Virtual address spaces and
preemption simplify reasoning locally but introduce timing-
dependent anomalies across network boundaries or multi-threaded
rendering pipelines. Use system call tracing, TLS, IPC mechanisms
to diagnose behavior emerging only in full system context.
