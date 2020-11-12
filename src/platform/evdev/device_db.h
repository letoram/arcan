/*
 * Copyright 2014, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

/*
 * This unit is rather ill-designed in that most things actually contain
 * most things these days and the very idea of static databases vs. user-
 * controlled typeset + calibration is terrible. Higher layers (e.g. Lua)
 * mostly deals away with the notion outside the idevtype of a sample
 * (i.e. digital, analog, touch) but it is still a mess.
 *
 * Most of the 'design' here should be viewed from a complete embedded
 * platform where you can have a static tuning / calibration phase, and
 * for the generic case, the keyboard/game/touch separation is usually
 * 'good enough'..
 */
enum devnode_type {
	DEVNODE_KEYBOARD = 0,
	DEVNODE_MOUSE,
	DEVNODE_GAME,
	DEVNODE_TOUCH,
	DEVNODE_SENSOR,
	DEVNODE_SWITCH,
	DEVNODE_MISSING
};

typedef void (*devnode_decode_cb)(struct arcan_evctx*, struct devnode*);

struct evhandler {
	const char* name;
	enum devnode_type type;
	devnode_decode_cb handler;

/*
 * (not used by all subtypes)
 * if corresponding bit is set for axis_mask or button_mask vs.
 * event-code, the event will be dropped. It can be used to get rid of
 * specific axis values for broken devices that spam events or are stuck.
 */
	uint64_t axis_mask;
	uint64_t button_mask;
};

static void defhandler_kbd(struct arcan_evctx*, struct devnode*);
static void defhandler_mouse(struct arcan_evctx*, struct devnode*);
static void defhandler_game(struct arcan_evctx*, struct devnode*);
static void defhandler_null(struct arcan_evctx*, struct devnode*);

/* as with the other input.c, we should probably just move this out into
 * the virtual filesystem and have the path indicate decoder type as this
 * will just get worse and worse. See these entries as examples :-) */
static struct evhandler device_db[] = {
	{
	.name = "Microsoft X-Box 360 pad",
	.type = DEVNODE_GAME,
	.handler = defhandler_game,
	},
	{
	.name = "ckb1",
	.type = DEVNODE_KEYBOARD,
	.handler = defhandler_kbd
	}
};

/*
 * matching devnode_type enum, this is somewhat of a misnomer in that device
 * detection can often just resolve to the first three types and especially
 * gamedev because the range available today covers pretty much everything
 */
static devnode_decode_cb defhandlers[] = {
	defhandler_kbd,
	defhandler_mouse,
	defhandler_game,
	defhandler_null,
	defhandler_null,
	defhandler_null,
	defhandler_null
};

static struct evhandler lookup_dev_handler(const char* idstr)
{
/* enumerate key */
	uintptr_t tag;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	char* dst;
	unsigned short ind = 0;

	while (get_config("evdev_keyboard", ind++, &dst, tag)){
		if (strcasecmp(dst, idstr) == 0){
			free(dst);
/* mapping the idstr is safe here as it is tied to the lifespan
 * of the node it will be used for and not separately allocated */
			return (struct evhandler){
				.handler = defhandler_kbd,
				.type = DEVNODE_KEYBOARD,
				.name = idstr
			};
		}
		free(dst);
	}

	ind = 0;
	while (get_config("evdev_mouse", ind++, &dst, tag)){
		if (strcasecmp(dst, idstr) == 0){
			free(dst);
			return (struct evhandler){
				.handler = defhandler_mouse,
				.type = DEVNODE_MOUSE,
				.name = idstr
			};
		}
		free(dst);
	}

	ind = 0;
	while (get_config("evdev_game", ind++, &dst, tag)){
		if (strcasecmp(dst, idstr) == 0){
			free(dst);
			return (struct evhandler){
				.handler = defhandler_game,
				.type = DEVNODE_GAME,
				.name = idstr
			};
		}
		free(dst);
	}

	for (size_t ind = 0; ind < sizeof(device_db)/sizeof(device_db[0]); ind++){
		if (strcmp(idstr, device_db[ind].name) == 0)
			return device_db[ind];
	}

#ifdef ARCAN_EVENT_WHITELIST
	struct evhandler def = {
		.name = "whitelist",
		.type = DEVNODE_MISSING,
		.handler = defhandler_null
	};
#else
	struct evhandler def = {0};
#endif

	return def;
}
