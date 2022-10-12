#ifndef _HAVE_LABELHINT
#define _HAVE_LABELHINT

struct labelent {
	const char* lbl;
	const char* descr;
	uint8_t vsym[5];
	bool(*ptr)(void*);
	uint16_t initial;
	uint16_t modifiers;
};

static struct labelent* lent_table;

static void labelhint_table(struct labelent* tbl)
{
	lent_table = tbl;
}

static void labelhint_announce(struct arcan_shmif_cont* c)
{
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(LABELHINT),
		.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
	};

	struct labelent* cur = lent_table;
	size_t lbl_sz = sizeof(ev.ext.labelhint.label) / sizeof(ev.ext.labelhint.label[0]);
	size_t dsc_sz = sizeof(ev.ext.labelhint.descr) / sizeof(ev.ext.labelhint.descr[0]);

/* reset */
	arcan_shmif_enqueue(c, &ev);

/* announce each individual */
	while (cur && cur->lbl){
		if (cur->ptr){
			snprintf(ev.ext.labelhint.label, lbl_sz, "%s", cur->lbl);
			snprintf(ev.ext.labelhint.descr, dsc_sz, "%s", cur->descr);
			snprintf((char*)ev.ext.labelhint.vsym, 5, "%s", cur->vsym);
			ev.ext.labelhint.subv = 0;
			ev.ext.labelhint.modifiers = cur->modifiers;
			arcan_shmif_enqueue(c, &ev);
		}
		cur++;
	}
}

static bool labelhint_consume(arcan_ioevent* ioev, void* tag)
{
	const struct labelent* cur = lent_table;

/* early-out untagged */
	if (!ioev->label[0])
		return false;

	while (cur && cur->lbl){
		if (strcmp(ioev->label, cur->lbl) == 0){
			if (cur->ptr)
				return cur->ptr(tag);
			return true;
		}
		cur++;
	}
	return false;
}

#endif
