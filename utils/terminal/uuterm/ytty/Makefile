
YTTY_HEXDRAW = $(YTTY_BASE)../hexdraw.sh
YTTY_UCFCOMP = $(YTTY_BASE)ucfcomp.host

YTTY_TARGET = $(YTTY_BASE)ytty.ucf

YTTY_DRAW_SRCS = $(patsubst %,$(YTTY_BASE)%,\
	base \
	enclose \
	math punct diacr geom arrows boxdraw braille \
	latin greek cyrillic runic hebrew \
	devanagari kannada thai tibetan \
	tech curr abbrev symbols \
	hangul kana widelatin \
	)

YTTY_HEX_SRCS = $(YTTY_BASE)kanji.hex

CLEAN := $(CLEAN)  $(YTTY_TARGET) $(YTTY_UCFCOMP)

$(YTTY_TARGET): $(YTTY_DRAW_SRCS) $(YTTY_HEX_SRCS) $(YTTY_UCFCOMP)
	( cat $(YTTY_DRAW_SRCS) | $(YTTY_HEXDRAW) ; cat $(YTTY_HEX_SRCS) ) \
	| $(YTTY_UCFCOMP) > $@ || ( rm -f $@ ; exit 1 )

$(YTTY_BASE)ucfcomp.host: $(YTTY_BASE)../ucfcomp.c
	$(HOSTCC) -o $@ $<
