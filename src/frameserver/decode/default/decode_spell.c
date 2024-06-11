#include <arcan_shmif.h>
/* include hunspell */

int decode_spell(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
/* GEOHINT to switch language */
	struct arcan_event ev;
	cont->hints = SHMIF_RHINT_EMPTY;

	while (arcan_shmif_wait(cont, &ev)){
		if (ev.category == EVENT_TARGET &&
			ev.tgt.kind == TARGET_COMMAND_MESSAGE){
			arcan_shmif_enqueue(cont, &(struct arcan_event){
					.category = EVENT_EXTERNAL,
					.ext.kind = ARCAN_EVENT(MESSAGE),
					.ext.message.data = "placeholder",
			});
			arcan_shmif_signal(cont, SHMIF_SIGVID);
		}
	}

	return EXIT_SUCCESS;
}
