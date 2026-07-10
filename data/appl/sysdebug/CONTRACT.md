# sysdebug chapter module contract

A chapter is a single Lua file that returns a table. The renderer
under `views/chapter.lua` consumes that table and lays out the page.
Stay inside this contract and your chapter will compose with every
other chapter the four sub-agents produce.

## File location

```
data/appl/sysdebug/parts/<NN_part>/ch<N>_<slug>.lua
```

Example: `parts/02_zig_fork/ch3_principal_debugging.lua`.

## Return value

```lua
return {
  -- Required ----------------------------------------------------------
  title       = "Principal Debugging",
  subtitle    = "Self-Hosted Zig Fork",            -- usually the Part name
  part_id     = 2,                                 -- 0..5
  chapter_id  = 3,                                 -- 1..4

  -- The chapter body is an ordered list of blocks (see "Block kinds"
  -- below). Order is the layout order on the page.
  body = {
    { kind = "epigraph",
      body = "We dedicate this work to all ambitious requirement "
          .. "specification engineers ...",
      cite = "Mellstrand & Ståhl 2012, dedication" },
    { kind = "h2", body = "Demarcation" },
    { kind = "text", body = "For years compiling a compiler has been ..." },
    { kind = "verbbox",
      label  = "see the units spread",
      chain  = "builtin dev ||| status",
      note   = "Lists all compile units, last-touched, error count." },
    -- ... etc
  },

  -- Optional ----------------------------------------------------------

  -- Cross-links rendered in the sidebar; format "PP_part:ch<N>".
  cross_links = { "00_foundations:ch3", "03_zig_arcan:ch3" },

  -- viz_bus event published on chapter open. Coordinator wires this.
  bus_publish = {
    sensor  = "sysdebug.read",
    payload = { part = 2, chapter = 3 },
  },

  -- Tickets cited in the chapter; rendered as a "References" section.
  -- Each entry is the bug_slug as it appears in fossil's `ticket`
  -- table (column `bug_slug`). Format: e.g. "0036-afsrv-bun-frameserver".
  -- Per ticket 0150 (2026-05-02) the old bugs/<id>-<slug>.md folder
  -- is gone; tickets live in fossil only.
  tickets = { "0001-sh-codegen-stack-overflow",
              "0002-sh-setSignedness-small-size-assert",
              "draft-d001-panic-select-zig-13053-body" },
}
```

## Block kinds

Every entry in `body` MUST be one of these kinds. The renderer
ignores unknown kinds — but use a known one or your text disappears.

| kind         | required keys       | optional keys      | what it does |
|--------------|---------------------|--------------------|--------------|
| `text`       | `body`              |                    | Prose paragraph. Wraps. |
| `h2`         | `body`              |                    | Section heading (the original book's `2.1`-style headers). |
| `h3`         | `body`              |                    | Subsection. |
| `epigraph`   | `body`, `cite`      |                    | Italicised pull-quote, indented, with citation. Use for original-book quotes. |
| `quote`      | `body`, `cite`      |                    | Block quote with citation. For arcan-fe.com / external quotes. |
| `code`       | `body`              | `lang`, `caption`  | Pre-formatted code sample. Not runnable. |
| `verbbox`    | `chain`             | `note`             | The visibility-rule artefact: a runnable hem verb chain. Renderer numbers it `[N]`; in v1 the user copy-pastes; v2 will key-bind digits to spawn a sibling cell. `chain` is exactly what gets passed as `CAT9_INIT_CMD`. |
| `fileref`    | `path`              | `note`             | Open this file in hem (`read <abs path>`). Renderer numbers it `[fN]`. |
| `articleref` | `slug`              | `title`            | Link to a long-form article under `articles/<slug>.lua`. Renderer numbers it `[aN]`. |
| `ticketref`  | `id`                | `note`             | Inline reference to a bug ticket; renders as `[tN] → ticket: <id>`. The id is the fossil `bug_slug` (e.g. `0036-afsrv-bun-frameserver`). |
| `crosslink`  | `target`            |                    | Link to another chapter/article in this appl. `target` is `"<part_dir>:<chapter_slug>"`. |
| `bridge`     | `body`              |                    | Italic connective sentence that hands off to the next section. Use sparingly. |
| `rule`       |                     |                    | Horizontal divider. |
| `diagram`    | `caption`, `paint`  |                    | A shmif-painted figure (v2; ignored in v1 renderer). |

## Visibility rule (mandatory)

Every chapter MUST have at least **one** `verbbox` block. This is
load-bearing. If you write a paragraph that names an information
source, a tool, a verb, a spread, or anything observable, you owe
the reader a `verbbox` they can click and see.

The renderer lints this at load time: a chapter without a verbbox
is rendered with a red `MISSING-VERBBOX` ribbon across the top.

Verb chains follow the hem `|||` separator convention. Examples:

```
"builtin dev ||| status"
"builtin dev ||| bugs show 0036-afsrv-bun-frameserver"
"builtin dev ||| bugs show 0036"
"builtin dev ||| zigbuild"
"builtin dev ||| disasm /home/x/next/arcan/zig-out/lib/libarcan_shmif.a"
"builtin dev ||| hilbert"
"builtin dev ||| grep panic /home/x/next/arcan/src"
```

You can chain more than two: `builtin dev ||| status ||| bugs`.

## Length

Target ~40 screens per Part (≈1500–2500 lines of Lua across the
four chapters of your Part). Shorter is fine if the prose is dense.
Padding is forbidden; the hem spread metaphor is the standard —
every line load-bearing, no scrollback waste.

## Naming the chapter file

Use the original book's chapter slug:

```
ch1_introduction.lua
ch2_software_demystified.lua
ch3_principal_debugging.lua
ch4_tools_of_the_trade.lua
```

Within each file, mirror the original's section titles where the
analogue is real, and rename where it is not. Examples that work
well in this codebase:

- Original `1.1 Demarcation` → kept; rephrase the *content* for
  your domain.
- Original `2.5 Object Code and the Linker` → for a12-tailscale
  becomes `Frame Encoding and the Wire`; for sel4-zig becomes
  `ELF Loading and the Rootserver`.

Do not bend the chapter count. Four chapters, mirroring the four
in the original. If you want to add material that doesn't fit, file
a ticket and add it later as Part VI.

## Citations

Block quotes from the original book go through `epigraph` or
`quote` kinds, with `cite` like `"Mellstrand & Ståhl 2012, p. 23"`
or `"... §3.4, p. 95"`. The licence line lives once in the appl
footer (`views/nav.lua`); do not repeat it inline.

Block quotes from arcan-fe.com posts cite `"Ståhl, arcan-fe.com,
2024-09-16"` (date of the post). Inline mentions can use a short
form: `"as the lash#hem post puts it, ..."`.

Tickets cite by slug: `"see ticket 0036-afsrv-bun-frameserver"` in
prose, or via the `ticketref` block kind for a structured reference.

## What to read before writing

- `data/appl/sysdebug/STYLE.md` — voice rules and samples
- `/home/x/next/arcan/systemic-software-debugging.pdf` — the
  chapter you are mirroring (read your matching chapter in full)
- `/home/x/next/arcan/CLAUDE.md` — project rules, visibility rule,
  hem_dev verb cheat-sheet
- `bugs show <slug>` (or `fossil sql "SELECT comment FROM ticket
  WHERE bug_slug = '...'"`) — the tickets your Part draws from
  (listed in your agent brief). Per ticket 0150 the old bugs/
  folder is gone.
- `/home/x/next/arcan/data/lash_builtins/hem_dev/_helpers.lua` —
  viz_bus contract; payload keys; sensor naming
- `/home/x/next/arcan/docs/hem_visual_agent/senseye-applied-plan.md`
  — the layer-5 substrate your verbboxes plug into
