# sysdebug style guide

Read this once before you start. It is short on purpose.

## Audience and form

Audience: Ariel. One person, who is building this stack and uses
this appl to remember where things are and to keep moving. Not "a
generic future agent." Address Ariel directly when the prose calls
for it; otherwise use first-person plural.

Form: link-heavy. Per-chapter token budget is ~2.5–3k. That means
prose is connective tissue between filerefs (open this in hem),
verbboxes (run this in hem), and ticketrefs. A chapter that reads
like a textbook is too long; a chapter that reads like an index
with one-paragraph headers per item is about right.

When the topic earns long-form prose — a story, a design rationale,
a tangent that does not compress — write an article instead. Drop
it under `articles/<slug>.lua`; reference it from chapters via an
`articleref` block. Article token budget is ~3k, longer if the
topic warrants. Articles use the arcan-fe.com post form: dated,
opinionated, occasional `h3`-tagged tangent sidebars, ending with a
who-am-i / what-is-this / where-am-i block.

## Whose voice

Write in the voice of Björn Ståhl's posts on arcan-fe.com and Per
Mellstrand & Ståhl's *Systemic Software Debugging* (2012). The two
voices are siblings: pragmatic, dryly irreverent, philosophy-first,
allergic to corporate gloss. Ståhl is one of the book authors and
the blog author, so they fit naturally together.

## Voice samples to emulate

These are the cadence and register. Match the *shape*, not the
specific phrases.

> I have spent thousands of hours staring at the GDB CLI prompt,
> and hated nearly every second of it.
> — *A Spreadsheet and a Debugger walk into a Shell*, 2024-09-16

> Many years ago, I grew tired of the unnecessarily large
> codebases, crazy dependencies, vast attack surfaces and general
> Rube-Goldbergness of the software tools I had to use.
> — *I wrote a Lua programmable display-server...*, 2016-05-27

> Senseye, which is targeted towards the more rugged of computing
> travellers; the reverse engineers, the security 'enthusiasts'.
> — *Next Experiment, Senseye*, 2015-02-08

> I am mostly a hapless twit who default to repeating the same
> things hoping for different outcomes.
> — *Whipping up a new Shell – Lash#Hem*, 2022-10-15

> 'Transparency' is evaluated from the perspective of the user; it
> is not even desirable for the underlying layers to operate
> identically locally versus across networks.
> — *A12 – Advancing Network Transparency on the Desktop*, 2020-10-28

And from the book:

> We simply consider a bug to be unwanted system behavior
> (according to some actor) with the typical restriction that it's
> non-trivial to explain why the system behaves as it does.
> — *Systemic Software Debugging*, p. ix

> The sentence 'a debugger debugged the bug using a debugger'
> suggests that there might be some work left in this regard and
> that the alphabet is, perhaps, not leveraged to its full
> potential.
> — *Systemic Software Debugging*, p. xi

## Voice rules

1. **Lead with the problem.** "For years X has been awful because…"
   is the canonical opener. Then the mechanism. Then the verb that
   does it.

2. **Direct, dry, occasionally self-deprecating.** No corporate
   enthusiasm, no "we're excited to introduce", no "leverages",
   no "best-in-class", no exclamation marks for emphasis.

3. **Philosophy first, then mechanism, then the verb that does it.**
   A chapter section that opens with a verbbox before establishing
   *why* the verb matters is doing it backward.

4. **Quote the original book where it speaks well; otherwise
   build forward.** Do not paraphrase wholesale. If the original
   author already nailed it in two sentences, quote them in two
   sentences and move on. CC-BY 3.0 makes this easy and correct.

5. **No second-person imperatives.** "You should" sounds like a
   tutorial; sysdebug is a reference. Use first-person plural
   ("we look at the metrics spread when...") or stage-direction
   third-person ("the metrics spread, when opened, ...").

6. **Idiom is welcome where it earns its keep.** "Rube-Goldberg",
   "rugged", "load-bearing", "harness is emergency-only", "clip
   is shipped" all fit. Do not parody.

7. **No emoji. Ever.**

## Visibility rule (load-bearing — repeated from CONTRACT.md)

Every chapter MUST include at least one `verbbox` block. Concretely:
if you write a paragraph that names an information source, a tool,
a verb, a spread, or anything observable, you owe the reader a
runnable verb chain.

This is not a courtesy. The reason this book is an arcan appl and
not a PDF is so the reader can run the verb the moment they read
about it. A chapter that talks about the disasm spread without a
verbbox to open the disasm spread has wasted both the reader's
time and the appl's reason for existing.

## Length

~40 screens per Part. Roughly 1500–2500 lines of Lua across your
four chapter files. Shorter is fine if the prose is dense. Padding
is forbidden — the hem spread metaphor is the standard. Every line
should be load-bearing.

## Self-test

Before you submit a chapter, take one of your paragraphs and one
from the original book on the same topic. Read them back to back.
If a stranger could not say which one is yours and which is the
book's *except by topic*, you are in voice. If your paragraph reads
like the book's only with the words "buffer" and "compiler"
swapped, you have paraphrased — re-quote instead.
