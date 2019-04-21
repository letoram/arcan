/*
 * Copyright: 2017-2018, Björn Ståhl
 * Description: A12 protocol state machine, substream decoding routines
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://arcan-fe.com
 */
#include <arcan_shmif.h>
#include "a12_int.h"
#include "a12.h"

#ifdef LOG_FRAME_OUTPUT
#define STB_IMAGE_WRITE_STATIC
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#include "../../engine/external/stb_image_write.h"
#endif

bool a12int_buffer_format(int method)
{
	return
		method == POSTPROCESS_VIDEO_H264 ||
		method == POSTPROCESS_VIDEO_MINIZ ||
		method == POSTPROCESS_VIDEO_DMINIZ;
}

/*
 * performance wise we should check if the extra branch in miniz vs. dminiz
 * should be handled here or by inlining and copying
 */
static int video_miniz(const void* buf, int len, void* user)
{
	struct a12_state* S = user;
	struct video_frame* cvf = &S->channels[S->in_channel].unpack_state.vframe;
	struct arcan_shmif_cont* cont = S->channels[S->in_channel].cont;
	const uint8_t* inbuf = buf;

	if (!cont || len > cvf->expanded_sz){
		debug_print(1, "decompression resulted in data overcommit");
		return 0;
	}

/* we have a 1..4 byte spill from a previous call so we need to have
 * a 1-px buffer that we populate before packing */
	if (cvf->carry){
		while (cvf->carry < 3){
			cvf->pxbuf[cvf->carry++] = *inbuf++;
			len--;

/* and this spill can also be short */
			if (!len)
				return 1;
		}

/* and commit */
		if (cvf->postprocess == POSTPROCESS_VIDEO_DMINIZ)
			cont->vidp[cvf->out_pos++] ^=
				SHMIF_RGBA(cvf->pxbuf[0], cvf->pxbuf[1], cvf->pxbuf[2], 0xff);
		else
			cont->vidp[cvf->out_pos++] =
				SHMIF_RGBA(cvf->pxbuf[0], cvf->pxbuf[1], cvf->pxbuf[2], 0xff);

/* which can happen on a row boundary */
		cvf->row_left--;
		if (cvf->row_left == 0){
			cvf->out_pos -= cvf->w;
			cvf->out_pos += cont->pitch;
			cvf->row_left = cvf->w;
		}
		cvf->carry = 0;
	}

/* pixel-aligned fill/unpack, same as everywhere else */
	size_t npx = (len / 3) * 3;
	for (size_t i = 0; i < npx; i += 3){
		if (cvf->postprocess == POSTPROCESS_VIDEO_DMINIZ)
			cont->vidp[cvf->out_pos++] ^=
				SHMIF_RGBA(inbuf[i], inbuf[i+1], inbuf[i+2], 0xff);
		else
			cont->vidp[cvf->out_pos++] =
				SHMIF_RGBA(inbuf[i], inbuf[i+1], inbuf[i+2], 0xff);

			cvf->row_left--;
			if (cvf->row_left == 0){
				cvf->out_pos -= cvf->w;
				cvf->out_pos += cont->pitch;
				cvf->row_left = cvf->w;
			}
	}

/* we need to account for len bytes not aligning */
	if (len - npx){
		cvf->carry = 0;
		for (size_t i = 0; i < len - npx; i++){
			cvf->pxbuf[cvf->carry++] = inbuf[npx + i];
		}
	}

	cvf->expanded_sz -= len;
	return 1;
}

void a12int_decode_vbuffer(
	struct a12_state* S, struct video_frame* cvf, struct arcan_shmif_cont* cont)
{
	debug_print(1, "decode vbuffer, method: %d", cvf->postprocess);
	if (cvf->postprocess == POSTPROCESS_VIDEO_MINIZ ||
			cvf->postprocess == POSTPROCESS_VIDEO_DMINIZ){
		size_t inbuf_pos = cvf->inbuf_pos;
		tinfl_decompress_mem_to_callback(cvf->inbuf, &inbuf_pos, video_miniz, S, 0);
		free(cvf->inbuf);
		cvf->carry = 0;
		if (cvf->commit && cvf->commit != 255){
			arcan_shmif_signal(cont, SHMIF_SIGVID);
		}
		return;
	}
#ifdef WANT_H264_DEC
	else if (cvf->postprocess == POSTPROCESS_VIDEO_H264){
/* just keep it around after first time of use */
		static const AVCodec* codec;
		if (!codec){
			codec = avcodec_find_decoder(AV_CODEC_ID_H264);
			if (!codec){
				debug_print(1, "couldn't find h264 decoder");
/* missing: send a message to request that we don't get more h264 frames */
				goto out_h264;
			}
		}

/* since these are stateful, we need to tie them to the channel dynamically */
		if (!cvf->ffmpeg.context){
			cvf->ffmpeg.context = avcodec_alloc_context3(codec);
			if (!cvf->ffmpeg.context){
				debug_print(1, "couldn't setup h264 codec context");
				goto out_h264;
			}

/* got the context, but it needs to be 'opened' as well */
			if (avcodec_open2(cvf->ffmpeg.context, codec, NULL) < 0)
				goto out_h264;

			cvf->ffmpeg.parser = av_parser_init(codec->id);
			if (!cvf->ffmpeg.parser){
				debug_print(1, "couldn't find h264 parser");
/* missing: send a message to request that we don't get more h264 frames */
				goto out_h264;
			}

			cvf->ffmpeg.frame = av_frame_alloc();
			if (!cvf->ffmpeg.frame){
				debug_print(1, "couldn't alloc frame for h264 decode");
				av_parser_close(cvf->ffmpeg.parser);
				goto out_h264;
			}

/* packet is their chunking mechanism (research if this step can be avoided) */
			cvf->ffmpeg.packet = av_packet_alloc();
			if (!cvf->ffmpeg.packet){
				debug_print(1, "couldn't alloc packet for h264 decode");
				av_parser_close(cvf->ffmpeg.parser);
				av_frame_free(&cvf->ffmpeg.frame);
				cvf->ffmpeg.parser = NULL;
				cvf->ffmpeg.frame = NULL;
				goto out_h264;
			}

			debug_print(1, "ffmpeg state block allocated");
		}

		av_parser_parse2(cvf->ffmpeg.parser, cvf->ffmpeg.context,
			&cvf->ffmpeg.packet->data, &cvf->ffmpeg.packet->size,
			cvf->inbuf, cvf->inbuf_pos, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0
		);

/* ffmpeg packet buffering is similar to our own, but it seems slightly risky
 * to assume that and try to sidestep that layer - though it should be tried at
 * some point */
		if (!cvf->ffmpeg.packet->size)
			goto out_h264;

		debug_print(2, "ffmpeg packet size: %d", cvf->ffmpeg.packet->size);
		int ret = avcodec_send_packet(cvf->ffmpeg.context, cvf->ffmpeg.packet);

		while (ret >= 0){
			ret = avcodec_receive_frame(cvf->ffmpeg.context, cvf->ffmpeg.frame);
			debug_print(2, "ffmpeg_receive status: %d", ret);

			if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
				goto out_h264;

			debug_print(1, "rescale and commit %d, format: %d",
				cvf->commit, AV_PIX_FMT_YUV420P);
/* Quite possible that we should actually cache this context as well, but it
 * has different behavior to the rest due to resize. Since this all turns
 * ffmpeg into a dependency, maybe it belongs in the vframe setup on resize. */
			struct SwsContext* scaler =
				sws_getContext(cvf->w, cvf->h, AV_PIX_FMT_YUV420P,
					cvf->w, cvf->h, AV_PIX_FMT_BGRA, SWS_BILINEAR, NULL, NULL, NULL);

			uint8_t* const dst[] = {cont->vidb};
			int dst_stride[] = {cont->stride};

			sws_scale(scaler, (const uint8_t* const*) cvf->ffmpeg.frame->data,
				cvf->ffmpeg.frame->linesize, 0, cvf->h, dst, dst_stride);

			if (cvf->commit && cvf->commit != 255)
				arcan_shmif_signal(cont, SHMIF_SIGVID);

			sws_freeContext(scaler);
		}

out_h264:
		free(cvf->inbuf);
		cvf->carry = 0;
		return;
	}
#endif

	debug_print(1, "unhandled unpack method %d", cvf->postprocess);
/* NOTE: should we send something about an undesired frame format here as
 * well in order to let the source re-send the frame in another format?
 * that could offset the need to 'negotiate' */
}

void a12int_unpack_vbuffer(struct a12_state* S,
	struct video_frame* cvf, struct arcan_shmif_cont* cont)
{
/* raw frame types, the implementations and variations are so small that
 * we can just do it here - no need for the more complex stages like for
 * 264, ... */
	if (cvf->postprocess == POSTPROCESS_VIDEO_RGBA){
		for (size_t i = 0; i < S->decode_pos; i += 4){
			cont->vidp[cvf->out_pos++] = SHMIF_RGBA(
				S->decode[i+0], S->decode[i+1], S->decode[i+2], S->decode[i+3]);
			cvf->row_left--;
			if (cvf->row_left == 0){
				cvf->out_pos -= cvf->w;
				cvf->out_pos += cont->pitch;
				cvf->row_left = cvf->w;
			}
		}
	}
	else if (cvf->postprocess == POSTPROCESS_VIDEO_RGB){
		for (size_t i = 0; i < S->decode_pos; i += 3){
			cont->vidp[cvf->out_pos++] = SHMIF_RGBA(
				S->decode[i+0], S->decode[i+1], S->decode[i+2], 0xff);
			cvf->row_left--;
			if (cvf->row_left == 0){
				cvf->out_pos -= cvf->w;
				cvf->out_pos += cont->pitch;
				cvf->row_left = cvf->w;
			}
		}
	}
	else if (cvf->postprocess == POSTPROCESS_VIDEO_RGB565){
		static const uint8_t rgb565_lut5[] = {
			0,     8,  16,  25,  33,  41,  49,  58,  66,   74,  82,  90,  99, 107,
			115, 123, 132, 140, 148, 156, 165, 173, 181, 189,  197, 206, 214, 222,
			230, 239, 247, 255
		};

		static const uint8_t rgb565_lut6[] = {
			0,     4,   8,  12,  16,  20,  24,  28,  32,  36,  40,  45,  49,  53,  57,
			61,   65,  69,  73,  77,  81,  85,  89,  93,  97, 101, 105, 109, 113, 117,
			121, 125, 130, 134, 138, 142, 146, 150, 154, 158, 162, 166, 170, 174,
			178, 182, 186, 190, 194, 198, 202, 206, 210, 215, 219, 223, 227, 231,
			235, 239, 243, 247, 251, 255
		};

		for (size_t i = 0; i < S->decode_pos; i += 2){
			uint16_t px;
			unpack_u16(&px, &S->decode[i]);
			cont->vidp[cvf->out_pos++] =
				SHMIF_RGBA(
					rgb565_lut5[ (px & 0xf800) >> 11],
					rgb565_lut6[ (px & 0x07e0) >>  5],
					rgb565_lut5[ (px & 0x001f)      ],
					0xff
				);
			cvf->row_left--;
			if (cvf->row_left == 0){
				cvf->out_pos -= cvf->w;
				cvf->out_pos += cont->pitch;
				cvf->row_left = cvf->w;
			}
		}
	}

	cvf->inbuf_sz -= S->decode_pos;
	if (cvf->inbuf_sz == 0){
		debug_print(2, "video frame completed, commit:%"PRIu8, cvf->commit);
		if (cvf->commit){
			arcan_shmif_signal(cont, SHMIF_SIGVID);
		}
	}
	else {
		debug_print(3, "video buffer left: %"PRIu32, cvf->inbuf_sz);
	}
}
