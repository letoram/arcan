# Arcan-TUI - lua Binding => attrtbls

# Introduction

These bindings expose the Arcan TUI API for creating text oriented
user-interfaces. This document merely describes the Lua exposed functions, not
how to embed the bindings into other projects. For that, in-source embed
the arcan/src/shmif/tui/tui\_lua.c implementation and call tui\_lua\_expose
on the context.

# Setting up a connection

You create a new connection with the following function:

    tui_open(title_string, identity_string, (handler_table)) => context_table

The title string is the immutable title of your application, while-as the
identity string can reflect some dynamic state, e.g. the name of a file being
edited, the current path for a shell and so on.

When the function call returns, you either have a connection represented by the
context table, or nil as an indication of failure.

The API is alsmost exclusively event-driven, the handler table supports a number
of entry points you can match to functions. The simplest pattern is thus:

    context = tui_open("", "")
    while context:process() do
    end

If the identity part has changed, due to the program opening some document
or external connection or something else that would distinguish it from other
instances of the same program, this can be updated with:

    context:update_ident("myfile.pdf")

The acccepted prototype for the process method looks like this:

    process(ctx) => bool
    process(ctx, timeout) => bool
    process(ctx, descriptor_table) => bool, state_table
    process(ctx, descriptor_table, timeout) => bool, state_table

If process ever returns 'false' it implies that the connection has died for
some user- or server- initiated reason. If there are any subwindows mapped
to the context (see the _subwindows_ section further below), those too will
be covered by the process call.

This function acts very much like a poll, and if there is data on the
connection itself, it is flushed into the event-loop. For each matching event
that is triggered, the corresponding callback in the handler table is
activated. These handlers covers information about the screen size changing,
updates to the color palette, user input and so on. The added poll behavior is
to allow multiplexing without exposing connection mechanism, and cover the
common usecase of reacting to some externally driven data flow, interpreting
and presenting it interactively without forcing in additional dependencies.

When finished working with a context, you deallocate it by calling the method
_close_ which takes an optional "last\_words" string that may tell the user
*why* you decided to close.

# Drawing

Drawing in the TUI API means picking 'attributes' one or several unicode
characters and writing them to a location. The process is simply that you
prepare all the changes you want to make, apply them using the appropriate
functions from the list below, and when you are finished, commit by calling
the 'refresh' method on the context. This will block processing until the
point where the server side has accepted your changes.

The 'location' is a cell on a rectangular grid, referenced using 'rows' (y
axis) and columns (x axis), thoough some functions take coordinates in x and y
format.

    mycontext:dimensions() => w, h

Drawing is targetting a currently active output abstract screen. The abstract
screen is a grid of cells that carry a character and optional formatting
attributes. The screen has a cursor, which is the current position output will
be written to unless the draw call used explicitly manipulates the cursor.

    write
    write_to
    insert_lines
    delete_lines
    insert_empty
    erase_cells
    erase_current_line
    erase_screen
    erase_cursor_to_screen
    erase_home_to_cursor
    erase_scrollback
    erase_region
    invalidate - force redraw the entire screen on next refresh

For any drawing, positioning and sizing operation - make special note if the
source call specifies an x,y position coordinate with 0,0 origo in the upper
left corner, or if it specifies in rows, cols. This is a very common pitfall.

## Specialized Attributes

When writing into a cell, both the data (character) and the formatting
attributes will be added to the contents of a cell. The attributes can be
specified explicitly or implicitly by setting a default attribute.

The default attribute can be set and retreived via:

    set_default_attr(attrtbl) => attrtbl

The attrtbl argument can be constructed via the global function:

    tui_attr(optional:context, optional:table) => attrtbl

If provided, the context argument _must_ point to a context retrieved from
tui\_open and will take its properties from the defaults in that context.
The accepted fields in \_table\_ are as follows:

    bold : bool
    underline : bool
    inverse : bool
    protect : bool
    strikethrough : bool
    fr : integer (0..255)
    fg : integer (0..255)
    fb : integer (0..255)
    br : integer (0..255)
    bg : integer (0..255)
    bb : integer (0..255)
    id : integer
    shape_break : integer

All of these, except for id and shape\_break, directly control the text drawing
routine. Id is a custom number tag that can be used to associate with
application specific metadata, as a way of mapping to more complex types.

Shape break is used to control text hinting engines for non-monospace
rendering. Though this goes against the traditional cell-grid structure, it is
useful for internationalisation and for ligature substitutions (where a
specific sequence of characters may map to an entirely different
representation.

## Colors

There is an event handler with the name 'recolor' which provides no arguments.
When activated, this indicates that the server provided palette have
changed. Though you explicitly set linear 8-bit rgb values to indicate color,
these _should_ be taken from a table of semantic indices.

There are two context- relative accessor functions for the palette:

    get_color(index) => r, g, b
    set_color(index, r, g, b)

The possible values for index are provided in the global lookup table
'tui\_color' and are thus accessed like:

    attrtbl.fr, attrtbl.fg, attrtbl.fb = get_color(tui_color.label)
    attrtbl.br, attrtbl.bg, attrtbl.bb = get_color(tui_color.background)
    set_default_attr(attrtbl)

The available semantic labels in the global tui\_color table are:

    text - expected color for generic 'text'
    background - expected color to match text background
    highlight - color to use for dynamic emphasis rather than bold attribute
    label - color to indicate some non-modifiable UI element or hint
    inactive - color to indicate an element that might be interactive normally
               but is for some reason not active or used
    warning - color to indicate some subtle danger
    error - color to indicate something that is dangerous or broken
    alert - color to indicate something that needs immediate attention
    primary - primary color for normal output, can be used to pick matching
              schemes.
    secondary - secondary to indicate a separate group from normal test.
    cursor - the currently set color of the cursor, this is handled internally
    altcursor - the currently set color in alt- scrolling mode, this is handled
                internally

Note that it is your responsibility to update on recolor events, the backend
does not track the semantic label associated with some cell. This is one of the
reasons you have access to a custom-set id as cell attribute.

## Cursor Control

The following functions are used to explicitly control the cursor position:

    cursor_to(x, y)
    cursor_tab(dt)
    cursor_step_col(dx)
    cursor_step_row(dy)

The cursor position is also automatically incremented with write calls relative
to the number of cells consumed and based on the state the screen is currently
in.

## Scrolling

In normal mode, the drawing engine can usually figure out if the contents move
uniformly in one direction and another. Depending on underlying user
preferences, this contents can then be drawn in gradually, reducing eyestrain
when having large cell sizes. Be sure to indicate 'margin' areas in normal mode
where there is rows at the edges that should be ignored.

In alternate mode, this is more difficult as the engine has to perform pattern
analysis that may be prone to errors. In such cases, you are encouraged to
manually hint that the next time refresh is called, the contents have shifted a
number rows and columns. This is done via the following context call:

    scroll_hint(x1, y1, x2, y2, dx, dy)

This can be called multiple times, though invalid values (x1 > x2, y1 > y2, and
will make the next _refresh_ call block for longer as the soft scroll is
performed. This will be interpreted as 'treat the region x1 to x2, y1 to y2 as
a scroll of dx steps horizontally, and dy steps vertically with negative values
towards origo in the upper left corner. Thus, the same amount of rows/columns
should have changed at the relevant cell location.

## Screen State

The active screen has a number of additional states (flags) that can be set
which change its appearance and response to input and processing. The most
important such flag is switching from _normal_ mode to _alternate_.

A screen can be in one out of two modes, 'normal' and 'alternate'. The 'normal'
mode has the idea of a history and is typically line-oriented. As data arrives
that you want to present, you format it and send it out as a line. When those
lines exceed the size of the screen, they get preserved and added to a history
that you can scroll back to. This is suitable for a line-oriented workflow with
a data set that incrementally grows, and is the more common mode people are
familiar with.

By contrast, the alternate screen is fixed and is treated more as a user
interface and old 'full screen' applications operated with terminals in a
similar fashion. There is no scrollback history, the management and sizing
behavior is simpler and so on. The main difference here in regards to legacy
text user interfaces is that we encourage the use of subwindows for
segmentation that can be managed by some outer windowing or display system
rather than manually faking borders and so on.

Other flags are more of a convenience, e.g.

RELATIVE\_ORIGIN - respects margins
INSERT\_MODE - when writing into the screen, items on the current line will
move to the right
AUTO\_WRAP - when the cursor overflows the end of the screen in its writing
direction, it will wrap to the next logical row or column.
ALTERNATE - set alternate mode

## Screen Resizing

It is not uncommon for an outer display system to communicate that the current
output dimensions have changed for whatever reason. When that occurs, the
contents of the current screen is invalidate entirely in a screen that is in
alternate mode, while populated with contents from the scrollback buffer in
normal mode.

You are always expected to be able to handle any non-negative, non-zero amount
of rows and columns.

# Subwindows

While it is entirely possible to open additional tui connections that will act
independent of eachother, it is also possible to create special subconnections
that operate under slightly different circumstances.

These requests are asynchronous as they require feedback from the outer display
system which can take a lot of time. To create a subwindow, you first need to
have an event handler for the _subwindow_ event.

Then you can use the following function to request a new window to be created:

    new_window(optional:type) => bool

Where type is one of (default) "tui", "popup", "handover". It returns true or
false depending on the number of permitted subwindows and pending requests.

When a subwindow has arrived, the special event handler "subwindow" is called
with its first argument being either nil or a new context that reflects the
subwindow to be used.

## Force-Push

There is also the chance that the outer server can decide and push a window
without a pending request in beforehand as a means of requesting/negotiating
capability. There are two cases where this is relevant.

1. Accessibility - If you receive a subwindow with the type 'accessibility' it
   is an indication that the user wants data provided here in a linear and
   text-to-speech accessible form. Lines that are written on this subwindow
   will be forwarded in order. You can think of it more of a streaming output
   device with low bandwidth than as a 'screen' as such.

2. Debug - This window requests a debug representation of the contents of the
   context it is pushed into. This encourages a separation between 'error'
   outputs and 'debug' outputs and tries to deal away with command-line debug
   arguments to try and squeeze more information out of your program.

## Tui subwindow

This act as just another window, but with its life-span, processing and refresh
cycle tied to that of its parent and thus needs no extra work for multiplexing.

It also gets another hinting feature,

    spatial_hint(direction)

where direction is one of the 8 corners (n, nw, w, sw, s, se, e, ne) and is a
hint to the outer window management system (if any) that relative window
positioning should be biased in that direction.

## Popup subwindow

The "popup" subwindow is a more common occurence where you want to show some
direct- feedback visuals related to the current menu, either with input focus
or without. When mapped, you get access to another context function:

    anchor(x, y, ref_y, input_grab)

This hints that the popup should be anchored to cell @ x, y and
sized/positioned so that it does not occlude the content row at ref\_y.

## Handover subwindow

The "handover" subwindow type is special and is used to create a connection to
the display system that has a trust relationship to the requester, but the
actual behavior is outside the scope and definition of this API. The primary
purpose is to be able to write a TUI application that act as a shell that need
to spawn a detachable process.

# Input

A lot of the work involved is retrieving and reacting to inputs from the user.
The following input event handlers are present:

    utf8 (char) : bool
    key (subid, keysym, scancode, modifiers)
    mouse_motion (relative, x, y, modifiers)
    mouse_button (subid, x, y, modifiers)
    label() : bool
    alabel()
    query_label() : bool

Some of these act as a chain with an early out and flow from a high-level of
abstraction to a low one. Your handler is expected to return 'true' if the event
was consumed and further processing should be terminated.

Note that key events are not treated with a rising/falling edge for keyboard
input, repeats/ on-release triggers have been deliberately excluded from this
model.

For text input, the most relevant is 'utf8' which implies that the a single
unicode codepoint has been provided in a utf8 encoded string and you likely
always want to handle this event.

For all the event handlers where there is a modifiers argument supplied, you
have access to both a global tuimods(modifiers) function that gives you a
textual representation of the active set of modifiers when the event was
triggered.

## Symbols

For working with raw key inputs, you have a number of options in the key event
handler, but the most important is likely the subid and the modifiers combined.

To decode some meaning out of subid, you have a global table called 'tuik'
which can translate both from a textual representation of a key to a numeric,
and from a numeric to a textual one.

## Labels

As a response to a change in language settings or at the initial startup, the
'query\_label' callback will be invoked. A label is a string tag that takes
priority over other forms of inputs, and comes with a user targeted short
description about its use, along with information about its suggested default
symbol and modifier binding. This is provided as a means of making the physical
inputs more discoverable, letting the outer display system provide options for
binding, override and visual feedback.

When this callback is invoked, you are expected to return 0 or 4 values though
the pattern can be condensed like this:

    local mybindings = {
    -- other supported languages like this
      swe = {
        {'SOME_LABEL', 'Beskrivning till anvandaren', TUIK_A, TUIM_CTRL}
      }

    -- and default (english)
      {'SOME_LABEL', 'Description for the user', TUIK_A, TUIM_CTRL}
    }

    function myhandler(ctx, displang, index)
      btbl = mybindings[displang] and mybindings[displang] or mybindings
        if (mybindings[index]) then
            return table.unpack(mybindings[index])
        end
    end

This covers communicating all available bindings for the requested language,
which is also a hint as to the output language.

## Mouse Controls

By default, the inner implementation of TUI takes care of mouse input and uses
it to manage select-to-copy and scrolling without any intervention. You can
disable this behavior and receive mouse input yourself with:

    mouse_forward(bool)

When set, the corresponding mouse\_motion and mouse\_button events will be
delivered to your set of event handlers.

# Data Transfers

Another part of expected application behavior is to deal with anciliary data
transfers, where the more common one is the more familiar, the clipboard.

## State-in/State-out

A feature addition that has not been part of traditional TUI API designs is
that we explicitly provide a serialization helper. This is activated by first
providing a serialization state size estimate, where the upper bounds may be
enforced by the outer display system.

    mycontext:state_size(4096)

The outer display system is then free, at any time, to provide an event to a
state\_in event handler or a state\_out event handler, expecting you to
pack/unpack enough state to be able to revert to an earlier state.
Implementing this properly unlocks a number of desired features, e.g. device
mobility, crash recovery, data mobility and so on.

You can also disable the feature after enabling it by setting the size to 0.

## Clipboard

Though technically these can be seen as inputs, the special relationship is
that they are used for larger block- or streaming- transfers.

Three event handlers deal with clipboard contents. Those are:

1. paste(str) - a string with utf8- encoded text contents.
2. vpaste(vh) - a pixel buffer transfer - [special]
3. apaste(ah) - an audio buffer transfer - [special]
4. bchunk(bh) - a generic binary blob transfer

Where the most common one, paste, is similar to a bounded set of utf8 inputs.

Bchunk comes as a generic 'here is a stream of bytes, do something with it',
possible as a response to an announcement that your application understands
a certain extension pattern:

    mycontext:bchunk_support({"png", "bmp"}, {"png, bmp"})

These are to be understood as convenience features for the outer display system
to integrate with some kind of data import/export path (like a file manager).
The decision to opt for an extension rather than some MIME-like notion of type
is simply the stance that it is always dangerous to believe or assume that a
a metadata type tag authenticates its data, integrity and origin. Parsers should
always assume broken data first, and respond aggressively - in contrast to the
often adopted doctrine of 'Postel's Principle'.

vpaste and apaste are special as they also need to be bundled with functions
that can encode/decode/present this data - unless your application has specific
provisions for it already.

# System

The last category is about other system integration related features.

## Reset

The event handler named 'reset(level)' indicates that the user, directly or
indirectly, wants the application to revert to some program- defined initial
state, where the level of severity (number argument) goes from:

0. User-initated, soft.
1. User-initated, hard.
2. Crash-recovery, wm- state lost.
3. Crash-recovery, system-state lost.

The third level is also used if the underlying display system has been remapped
to some other device, local or non-local.

## Timers

There is a course grained monotonic timer that can be accessed which is also
aligned with the blink- behavior of the cursor. To get access to it, you simply
make sure there is a _tick_ function in your set of event handlers and it will
be activated.
