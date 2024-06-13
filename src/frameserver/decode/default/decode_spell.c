#include <arcan_shmif.h>
#include <hunspell/hunspell.h>

/* other input sources to consider :
 *
 * libanthy for japanese IME, librime for chinese the one used by
 * android/chrome/firefox is way too google-complex-complex.
 *
 * for IME/rime the question is also what to do with drawn input, but that is
 * likely better through ENCODE and OCR.
 *
 * Personal dictionary for suggestions which should come as a STATE transfer
 * and learn based on use. For that we need feedback about which spelling
 * that was actually used in the end.
 *
 * Ideally we should respect GEOHINT and switch dictionary, but since GEOHINT
 * comes in ISO-639-2 alpha 3 and 3166-1 alpha 3 that would need conversion
 * tables as hunspell expects 639-2 alpha 2 and 3166-1 alpha 2 to pick the file.
 *
 * ISO do provide some conversion tables CSVs that could be translated to a header.
 */
int decode_spell(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	struct arcan_event ev;
	cont->hints = SHMIF_RHINT_EMPTY;

	Hunhandle* hh = Hunspell_create(
		"/usr/share/hunspell/en_GB.aff",
		"/usr/share/hunspell/en_GB.dic");

	if (!hh){
		arcan_shmif_last_words(cont, "open hunspell dict failed");
		return EXIT_FAILURE;
	}

/* can drop privileges here to only shmif */

	while (arcan_shmif_wait(cont, &ev)){
		if (ev.category == EVENT_TARGET &&
			ev.tgt.kind == TARGET_COMMAND_MESSAGE){
			char** out = NULL;
			ssize_t ns = Hunspell_suggest(hh, &out, ev.tgt.message);
			if (ns > 0){
				for (size_t i = 0; i < ns && i < 64; i++){
					struct arcan_event outev =
						(struct arcan_event){.ext.kind = ARCAN_EVENT(MESSAGE)};
					snprintf((char*)outev.ext.message.data,
						sizeof(outev.ext.message.data), "%s", out[i]);

					arcan_shmif_enqueue(cont, &outev);
				}
				Hunspell_free_list(hh, &out, ns);
			}
			arcan_shmif_signal(cont, SHMIF_SIGVID);
		}
	}

	return EXIT_SUCCESS;
}

