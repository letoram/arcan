/*
 * Copyright: 2017-2018, Björn Ståhl
 * Description: A12 protocol state machine, substream decoding routines
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://arcan-fe.com
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <inttypes.h>
#include <string.h>
#include <math.h>

#include "a12.h"
#include "a12_int.h"
#include "zstd.h"

#ifdef LOG_FRAME_OUTPUT
#define STB_IMAGE_WRITE_STATIC
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#include "../../engine/external/stb_image_write.h"
#endif

static void drain_video(struct a12_channel* ch, struct video_frame* cvf)
{
	cvf->commit = 0;
	if (ch->active == CHANNEL_RAW){
		a12int_trace(A12_TRACE_VIDEO,
			"kind=drain:dest=user:ts=%llu", arcan_timemillis());

		if (ch->raw.signal_video){
			ch->raw.signal_video(cvf->x, cvf->y,
				cvf->x + cvf->w, cvf->y + cvf->h, ch->raw.tag);
		}
		return;
	}

	a12int_trace(A12_TRACE_VIDEO,
		"kind=drain:dest=%"PRIxPTR":ts=%llu", (uintptr_t) ch->cont, arcan_timemillis());
	arcan_shmif_signal(ch->cont, SHMIF_SIGVID);
}

bool a12int_buffer_format(int method)
{
	return
		method == POSTPROCESS_VIDEO_H264 ||
		method == POSTPROCESS_VIDEO_TZSTD ||
		method == POSTPROCESS_VIDEO_ZSTD ||
		method == POSTPROCESS_VIDEO_DZSTD;
}

static int video_miniz(const void* buf, int len, void* user)
{
	struct a12_state* S = user;
	struct video_frame* cvf = &S->channels[S->in_channel].unpack_state.vframe;
	struct arcan_shmif_cont* cont = S->channels[S->in_channel].cont;
	const uint8_t* inbuf = buf;

	if (!cont || len > cvf->expanded_sz){
		a12int_trace(A12_TRACE_SYSTEM, "decompression resulted in data overcommit");
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
		if (cvf->postprocess == POSTPROCESS_VIDEO_DZSTD){
			uint8_t r, g, b, a;
			SHMIF_RGBA_DECOMP(cont->vidp[cvf->out_pos], &r, &g, &b, &a);

			cont->vidp[cvf->out_pos++] = SHMIF_RGBA(
				cvf->pxbuf[0] ^ r,
				cvf->pxbuf[1] ^ g,
				cvf->pxbuf[2] ^ b,
				0xff
			);
		}
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

/* tpack is easier, just write into vidb, ensure that we don't exceed
 * the size from a missed resize_ call and the rest is done consumer side */
	if (cvf->postprocess == POSTPROCESS_VIDEO_TZSTD){
		memcpy(&cont->vidb[cvf->out_pos], inbuf, len);
		cvf->out_pos += len;
		cvf->expanded_sz -= len;
		return 1;
	}

/* pixel-aligned fill/unpack, same as everywhere else */
	size_t npx = (len / 3) * 3;
	for (size_t i = 0; i < npx; i += 3){
		if (cvf->postprocess == POSTPROCESS_VIDEO_DZSTD){
			uint8_t r, g, b, a;
			SHMIF_RGBA_DECOMP(cont->vidp[cvf->out_pos], &r, &g, &b, &a);

			cont->vidp[cvf->out_pos++] = SHMIF_RGBA(
				inbuf[i+0] ^ r,
				inbuf[i+1] ^ g,
				inbuf[i+2] ^ b,
				0xff
			);
		}
		else{
			cont->vidp[cvf->out_pos++] =
				SHMIF_RGBA(inbuf[i], inbuf[i+1], inbuf[i+2], 0xff);
		}

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

#ifdef WANT_H264_DEC

void ffmpeg_decode_pkt(
	struct a12_state* S, struct video_frame* cvf, struct arcan_shmif_cont* cont)
{
	a12int_trace(A12_TRACE_VIDEO,
		"ffmpeg:packet_size=%d", cvf->ffmpeg.packet->size);
	int ret = avcodec_send_packet(cvf->ffmpeg.context, cvf->ffmpeg.packet);
	if (ret < 0){
		a12int_trace(A12_TRACE_VIDEO, "ffmpeg:packet_status=decode_fail");
		a12_vstream_cancel(S, S->in_channel, STREAM_CANCEL_DECODE_ERROR);
		return;
	}

	while (ret >= 0){
		ret = avcodec_receive_frame(cvf->ffmpeg.context, cvf->ffmpeg.frame);
		if (ret == AVERROR(EAGAIN) || ret == AVERROR(EOF)){
			a12int_trace(A12_TRACE_VIDEO, "ffmpeg:avcodec=again|eof:value=%d", ret);
			return;
		}
		else if (ret != 0){
			a12int_trace(A12_TRACE_SYSTEM, "ffmpeg:avcodec=fail:code=%d", ret);
			a12_vstream_cancel(S, S->in_channel, STREAM_CANCEL_DECODE_ERROR);
			return;
		}

		a12int_trace(A12_TRACE_VIDEO,
			"ffmpeg:kind=convert:commit=%d:format=yub420p", cvf->commit);
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

/* Mark that we should send a ping so the other side can update the drift wnd */
		if (cvf->commit && cvf->commit != 255){
			drain_video(&S->channels[S->in_channel], cvf);
		}

		sws_freeContext(scaler);
	}
}

static bool ffmpeg_alloc(struct a12_channel* ch, int method)
{
	bool new_codec = false;

	if (!ch->videnc.codec){
		ch->videnc.codec = avcodec_find_decoder(method);
		if (!ch->videnc.codec){
			a12int_trace(A12_TRACE_SYSTEM, "couldn't find h264 decoder");
			return false;
		}
		new_codec = true;
	}

	if (!ch->videnc.encdec){
		ch->videnc.encdec = avcodec_alloc_context3(ch->videnc.codec);
		if (!ch->videnc.encdec){
			a12int_trace(A12_TRACE_SYSTEM, "couldn't setup h264 codec context");
			return false;
		}
	}

/* got the context, but it needs to be 'opened' as well */
	if (new_codec){
		if (avcodec_open2(ch->videnc.encdec, ch->videnc.codec, NULL ) < 0)
			return false;
	}

	if (!ch->videnc.parser){
		ch->videnc.parser = av_parser_init(ch->videnc.codec->id);
		if (!ch->videnc.parser){
			a12int_trace(A12_TRACE_SYSTEM, "kind=ffmpeg_alloc:status=parser_alloc fail");
			return false;
		}
	}

	if (!ch->videnc.frame){
		ch->videnc.frame = av_frame_alloc();
		if (!ch->videnc.frame){
			a12int_trace(A12_TRACE_SYSTEM, "kind=ffmpeg_alloc:status=frame_alloc fail");
			return false;
		}
	}

/* packet is their chunking mechanism (research if this step can be avoided) */
	if (!ch->videnc.packet){
		ch->videnc.packet = av_packet_alloc();
		if (!ch->videnc.packet){
			return false;
		}
	}

	if (new_codec){
		a12int_trace(A12_TRACE_VIDEO, "kind=ffmpeg_alloc:status=new_codec:id=%d", method);
	}

	return true;
}
#endif

void a12int_decode_drop(struct a12_state* S, int chid, bool failed)
{
	if (S->channels[chid].unpack_state.vframe.zstd){
		ZSTD_freeDCtx(S->channels[chid].unpack_state.vframe.zstd);
		S->channels[chid].zstd = NULL;
	}

#if defined(WANT_H264_ENC) || defined(WANT_H264_DEC)
	if (!S->channels[chid].videnc.encdec)
		return;

#endif
}

bool a12int_vframe_setup(struct a12_channel* ch, struct video_frame* dst, int method)
{
	*dst = (struct video_frame){};

	if (method == POSTPROCESS_VIDEO_H264){
#ifdef WANT_H264_DEC
		if (!ffmpeg_alloc(ch, AV_CODEC_ID_H264))
			return false;

/* parser, context, packet, frame, scaler */
		dst->ffmpeg.context = ch->videnc.encdec;
		dst->ffmpeg.packet = ch->videnc.packet;
		dst->ffmpeg.frame = ch->videnc.frame;
		dst->ffmpeg.parser = ch->videnc.parser;
		dst->ffmpeg.scaler = ch->videnc.scaler;

#else
		return false;
#endif
	}
	return true;
}

void a12int_decode_vbuffer(struct a12_state* S,
	struct a12_channel* ch, struct video_frame* cvf, struct arcan_shmif_cont* cont)
{
	a12int_trace(A12_TRACE_VIDEO, "decode vbuffer, method: %d", cvf->postprocess);
	if ( cvf->postprocess == POSTPROCESS_VIDEO_DZSTD
		|| cvf->postprocess == POSTPROCESS_VIDEO_ZSTD
		|| cvf->postprocess == POSTPROCESS_VIDEO_TZSTD)
	{
		uint64_t content_sz = ZSTD_getFrameContentSize(cvf->inbuf, cvf->inbuf_pos);

/* repeat and compare, don't le/gt */
		if (content_sz == cvf->expanded_sz){
			if (!ch->unpack_state.vframe.zstd &&
				!(ch->unpack_state.vframe.zstd = ZSTD_createDCtx())){
				a12int_trace(A12_TRACE_SYSTEM,
					"kind=alloc_error:zstd_context_alloc");
			}
/* actually decompress */
			else {
				void* buffer = malloc(content_sz);
				if (buffer){
					uint64_t decode =
						ZSTD_decompressDCtx(ch->unpack_state.vframe.zstd,
							buffer, content_sz, cvf->inbuf, cvf->inbuf_pos);
					a12int_trace(A12_TRACE_VIDEO, "kind=zstd_state:%"PRIu64, decode);
					video_miniz(buffer, content_sz, S);
					free(buffer);
				}
			}
		}
		else {
			a12int_trace(A12_TRACE_SYSTEM,
				"kind=decode_error:in_sz=%zu:exp_sz=%zu:message=size mismatch",
				(size_t) content_sz, (size_t) cvf->expanded_sz
			);
		}

		free(cvf->inbuf);
		cvf->inbuf = NULL;
		cvf->carry = 0;

/* this is a junction where other local transfer strategies should be considered,
 * i.e. no-block and defer process on the next stepframe or spin on the vready */
		if (cvf->commit && cvf->commit != 255){
			drain_video(ch, cvf);
		}
		return;
	}
#ifdef WANT_H264_DEC
	else if (cvf->postprocess == POSTPROCESS_VIDEO_H264){
/* just keep it around after first time of use */
/* since these are stateful, we need to tie them to the channel dynamically */
		a12int_trace(A12_TRACE_VIDEO,
			"kind=ffmpeg_state:parser=%"PRIxPTR
			":context=%"PRIxPTR
			":inbuf_size=%zu",
			(uintptr_t)cvf->ffmpeg.parser,
			(uintptr_t)cvf->ffmpeg.context,
			(size_t)cvf->inbuf_pos
		);

#define DUMP_COMPRESSED
#ifdef DUMP_COMPRESSED
		static FILE* outf;
		if (!outf)
			outf = fopen("raw.h264", "w");
		fwrite(cvf->inbuf, cvf->inbuf_pos, 1, outf);
#endif

/* parser_parse2 can short-read */
		ssize_t ofs = 0;
		while (cvf->inbuf_pos - ofs > 0){
			int ret =
				av_parser_parse2(cvf->ffmpeg.parser, cvf->ffmpeg.context,
				&cvf->ffmpeg.packet->data, &cvf->ffmpeg.packet->size,
				&cvf->inbuf[ofs], cvf->inbuf_pos - ofs, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0
			);

			if (ret < 0){
				a12int_trace(A12_TRACE_VIDEO, "kind=ffmpeg_state:parser=broken:code=%d", ret);
				cvf->commit = 255;
				goto out_h264;
			}
			a12int_trace(A12_TRACE_VDETAIL, "kind=parser:return=%d:"
				"packet_sz=%d:ofset=%zd", ret, cvf->ffmpeg.packet->size, ofs);

			ofs += ret;
			if (cvf->ffmpeg.packet->data){
				ffmpeg_decode_pkt(S, cvf, cont);
			}
		}

out_h264:
		free(cvf->inbuf);
		cvf->inbuf = NULL;
		cvf->carry = 0;
		return;
	}
#endif

	a12int_trace(A12_TRACE_SYSTEM, "unhandled unpack method %d", cvf->postprocess);
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
		a12int_trace(A12_TRACE_VIDEO,
			"video frame completed, commit:%"PRIu8, cvf->commit);
		a12int_stream_ack(S, S->in_channel, cvf->id);
		if (cvf->commit){
			arcan_shmif_signal(cont, SHMIF_SIGVID);
		}
	}
	else {
		a12int_trace(A12_TRACE_VDETAIL, "video buffer left: %"PRIu32, cvf->inbuf_sz);
	}
}
