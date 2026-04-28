-- target_fonthint
-- @short: Send font drawing hints to target frameserver.
-- @inargs: vid:dst, string:font, number:size_mm, int:hint
-- @inargs: vid:dst, string:font, number:size_mm, int:hint, int:cont
-- @inargs: vid:dst, number:size_mm, int:hint
-- @inargs: vid:dst, number:size_mm, int:hint, int:cont
-- @outargs: int:cellw, int:cellh, bool:state
-- @longdescr: The target_fonthint function sends a hint (and
-- optionally a descriptor to the specified font resource in the
-- ARCAN_SYS_FONT namespace) about how frameserver rendered text should be
-- drawn into the specified segment. The *size_mm* argument sets the desired
-- 'normal' font size (in mm). Use ref:target_displayhint to handle changes
-- in underlying display pixel density. *strength* hints to anti-aliasing
-- like this (0: disabled, 1: monospace, 2: weak, 3: medium, 4:strong) and
-- if bit 8 is set (+ 256) try and apply subpixel hinting.
-- It is still up to the renderer in the receiving frameserver to respect
-- these flags and to match any rendering properties with corresponding
-- displayhints in order for sizes to match.
-- If the *cont* option is set to 1, this font is intended to be chained as a
-- fallback in the case of missing glyphs in previously supplied fonts.
-- The function returns the estimated cell width/height that will currently
-- be used for size calculations of server-side text in monospaced form with
-- the supplied fonts, followed by a boolean *state* indicating whether the
-- font was found and forwarded correctly to the client. The cell dimensions
-- are returned even when *state* is false (in which case both will be 0,
-- 0); having them first matches the natural reading order when the values
-- are wanted by callers that pre-size cell-based UI before knowing if the
-- font hint was actually accepted.
-- @note: If -1 is used for *size_mm* and/or *strength*, the recipient
-- should keep the currently hinted size.
-- @note: To translate from the Postscript 'point size' to
-- millimeter, multiply with the constant FONT_PT_SZ.
-- @note: The actual font size will also vary with the density of the
-- output segment. The density can be expressed via the ref:target_displayhint
-- function.
-- @note: .default is a reserved name for propagating the font that is
-- currently set as the default (using ref:system_defaultfont)
-- @since: 0.9.1 (return order changed -- old form was state, cellw,
-- cellh; new form puts cell dimensions first to match the natural
-- destructure pattern. Out-of-tree code reading the old shape will
-- silently bind cellw to *state* on the first return slot, which is
-- a real footgun -- audit destructures.)
-- @stability: FROZEN
-- @group: targetcontrol
-- @cfunction: targetfonthint
-- @related: system_defaultfont
function main()
	local fsrv = launch_avfeed(function(source, status)
	end);
#ifdef MAIN
	local cw, ch, ok = target_fonthint(fsrv, "default.ttf", 10, 1);
	target_fonthint(fsrv, 1, 0);
#endif

#ifdef MAIN2
-- Cell-metric preview: hint a monospaced font and use the returned
-- cell dimensions to pre-size a debug overlay before pushing any
-- text. Each line in the corpus is rendered into one (cw, ch)
-- glyph cell on the receiving frameserver and is short enough to
-- fit within typical 80-cell terminal widths after wrap.
	local farnsworth_corpus = {
		"Good news, everyone! I've taught the toaster to feel love.",
		"Good news, everyone! There's a report on TV with some very bad news.",
		"Good news, everyone! We're going on a highly controversial mission.",
		"Good news, everyone! I've decided to make all of you part of",
		"  my Death Squad! Gold-plated Death Squad. Diamond-encrusted",
		"  Death Squad. Death Squad with a death-ray. Death Squad with",
		"  a death-ray AND go-go boots.",
		"I don't want to live on this planet anymore.",
		"Sweet zombie Jesus!",
	};

	local cw, ch, ok = target_fonthint(fsrv, "mono.ttf", 10, 2);
	if ok and cw > 0 and ch > 0 then
		for _, line in ipairs(farnsworth_corpus) do
			print(string.format("preview: %dx%d %q", cw, ch, line));
		end
	end
#endif

#ifdef ERROR1
	target_fonthint(WORLDID);
#endif
end
