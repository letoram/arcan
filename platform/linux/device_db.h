/*
 * patch this to add a static, device specific, decoder
 * which can also be used to either forcibly disable
 * devices we handle poorly or that misbehave or only
 * allow devices we've verified in beforehand (though
 * the identity is rather weak and spoofable).
 */

enum devnode_type {
	DEVNODE_SENSOR = 0,
	DEVNODE_GAME,
	DEVNODE_MOUSE,
	DEVNODE_TOUCH,
	DEVNODE_KEYBOARD,
	DEVNODE_MISSING
};

typedef void (*devnode_decode_cb)(struct arcan_evctx*, struct arcan_devnode*);

struct evhandler {
	const char* name;
	enum devnode_type type;
	devnode_decode_cb handler;
};

static struct evhandler device_db[] = {
	{
	.name = NULL,
	.type = DEVNODE_MISSING,
	.handler = NULL
	},
};

static void defhandler_kbd(struct arcan_evctx*, struct arcan_devnode*);
static void defhandler_mouse(struct arcan_evctx*, struct arcan_devnode*);
static void defhandler_game(struct arcan_evctx*, struct arcan_devnode*);
static void defhandler_null(struct arcan_evctx*, struct arcan_devnode*);

static devnode_decode_cb defhandlers[] = {
	defhandler_null,
	defhandler_game,
	defhandler_mouse,
	defhandler_null,
	defhandler_kbd,
	defhandler_null
};

static struct evhandler lookup_dev_handler(const char* idstr)
{
	struct evhandler* cur = device_db;

	size_t ind = 0;
	while(cur[ind].name != NULL){
		if (strcmp(idstr, cur[ind].name) == 0)
			return cur[ind];
		ind++;
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
