#include <arcan_shmif.h>
#include <pthread.h>
#include "platform/shmif_platform.h"
#include "shmif_privint.h"

void shmifint_drop_initial(struct arcan_shmif_cont* c)
{
	if (!(c && c->priv && c->priv->valid_initial))
		return;
	struct arcan_shmif_initial* init = &c->priv->initial;

	if (-1 != init->render_node){
		close(init->render_node);
		init->render_node = -1;
	}

	for (size_t i = 0; i < COUNT_OF(init->fonts); i++)
		if (-1 != init->fonts[i].fd){
			close(init->fonts[i].fd);
			init->fonts[i].fd = -1;
		}

	c->priv->valid_initial = false;
}

bool shmifint_preroll_loop(struct arcan_shmif_cont* cont, bool resize)
{
	arcan_event ev;
	struct arcan_shmif_initial def = {
		.country = {'G', 'B', 'R', 0},
		.lang = {'E', 'N', 'G', 0},
		.text_lang = {'E', 'N', 'G', 0},
		.latitude = 51.48,
		.longitude = 0.001475,
		.render_node = -1,
		.density = ARCAN_SHMPAGE_DEFAULT_PPCM,
		.fonts = {
			{
				.fd = -1,
				.size_mm = 3.527780
			}, {.fd = -1}, {.fd = -1}, {.fd = -1}
		}
	};

	size_t w = 640;
	size_t h = 480;
	size_t font_ind = 0;

	while (arcan_shmif_wait(cont, &ev)){
		if (ev.category != EVENT_TARGET){
			continue;
		}

		switch (ev.tgt.kind){
		case TARGET_COMMAND_ACTIVATE:
			cont->priv->valid_initial = true;
			if (resize)
				arcan_shmif_resize(cont, w, h);
			cont->priv->initial = def;
			return true;
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev.tgt.ioevs[0].iv)
				w = ev.tgt.ioevs[0].iv;
			if (ev.tgt.ioevs[1].iv)
				h = ev.tgt.ioevs[1].iv;
			if (ev.tgt.ioevs[4].fv > 0.0001)
				def.density = ev.tgt.ioevs[4].fv;
			if (ev.tgt.ioevs[5].iv)
				def.cell_w = ev.tgt.ioevs[5].iv;
			if (ev.tgt.ioevs[6].iv)
				def.cell_h = ev.tgt.ioevs[6].iv;
		break;
		case TARGET_COMMAND_OUTPUTHINT:
			if (ev.tgt.ioevs[0].iv)
				def.display_width_px = ev.tgt.ioevs[0].iv;
			if (ev.tgt.ioevs[1].iv)
				def.display_height_px = ev.tgt.ioevs[1].iv;
			if (ev.tgt.ioevs[2].iv)
				def.rate = ev.tgt.ioevs[2].iv;
		break;

		case TARGET_COMMAND_GRAPHMODE:{
			bool bg = (ev.tgt.ioevs[0].iv & 256) > 0;
			int slot = ev.tgt.ioevs[0].iv & (~256);
			def.colors[1].bg[0] = 255;
			def.colors[1].bg_set = true;

			if (slot >= 0 && slot < COUNT_OF(def.colors)){
				uint8_t* dst = def.colors[slot].fg;
				if (bg){
					def.colors[slot].bg_set = true;
					dst = def.colors[slot].bg;
				}
				else
					def.colors[slot].fg_set = true;
				dst[0] = ev.tgt.ioevs[1].fv;
				dst[1] = ev.tgt.ioevs[2].fv;
				dst[2] = ev.tgt.ioevs[3].fv;
			}
		}
		break;

		case TARGET_COMMAND_DEVICE_NODE:
/* alt-con will be updated automatically, due to normal wait handler */
			if (ev.tgt.ioevs[0].iv != -1){
				def.render_node = arcan_shmif_dupfd(
					ev.tgt.ioevs[0].iv, -1, true);
			}
		break;
/* not 100% correct - won't reset if font+font-append+font
 * pattern is set but not really a valid use */
		case TARGET_COMMAND_FONTHINT:
			def.fonts[font_ind].hinting = ev.tgt.ioevs[3].iv;

/* protect against a bad value there, disabling the size isn't permitted */
			if (ev.tgt.ioevs[2].fv > 0)
				def.fonts[font_ind].size_mm = ev.tgt.ioevs[2].fv;
			if (font_ind < 3){
				if (ev.tgt.ioevs[0].iv != -1){
					def.fonts[font_ind].fd = arcan_shmif_dupfd(
						ev.tgt.ioevs[0].iv, -1, true);
					font_ind++;
				}
			}
		break;

/* allow remapping of stdin but don't CLOEXEC it */
		case TARGET_COMMAND_BCHUNK_IN:
			if (strcmp(ev.tgt.message, "stdin") == 0)
				shmif_platform_dupfd_to(ev.tgt.ioevs[0].iv, STDIN_FILENO, 0, 0);
		break;

/* allow remapping of stdout but don't CLOEXEC it */
		case TARGET_COMMAND_BCHUNK_OUT:
			if (strcmp(ev.tgt.message, "stdout") == 0)
				shmif_platform_dupfd_to(ev.tgt.ioevs[0].iv, STDOUT_FILENO, 0, 0);
		break;

		case TARGET_COMMAND_GEOHINT:
			def.latitude = ev.tgt.ioevs[0].fv;
			def.longitude = ev.tgt.ioevs[1].fv;
			def.elevation = ev.tgt.ioevs[2].fv;
			if (ev.tgt.ioevs[3].cv[0])
				memcpy(def.country, ev.tgt.ioevs[3].cv, 3);
			if (ev.tgt.ioevs[4].cv[0])
				memcpy(def.lang, ev.tgt.ioevs[3].cv, 3);
			if (ev.tgt.ioevs[5].cv[0])
				memcpy(def.text_lang, ev.tgt.ioevs[4].cv, 3);
			def.timezone = ev.tgt.ioevs[5].iv;
		break;
		default:
		break;
		}
	}

/* this will only be called during first setup, so the _drop is safe here
 * as the mutex lock it performs have not been exposed to the user */
	debug_print(FATAL, cont, "no-activate event, connection died/timed out");
	cont->priv->valid_initial = true;
	arcan_shmif_drop(cont);
	return false;
}
