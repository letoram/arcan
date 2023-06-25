/*
 * Copyright 2012-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: struct arcan_event transformation routines
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>

#include "arcan_shmif.h"
#include "arcan_shmif_sub.h"

static const char* msub_to_lbl(int ind)
{
	switch(ind){
	case MBTN_LEFT_IND: return "left";
	case MBTN_RIGHT_IND: return "right";
	case MBTN_MIDDLE_IND: return "middle";
	case MBTN_WHEEL_UP_IND: return "wheel-up";
	case MBTN_WHEEL_DOWN_IND: return "wheel-down";
	default:
		return "unknown";
	}
}

/*
 * Tempoary 'bad idea' implementions, placeholders until a real packing format
 * is implemented, until then this is - of course - not at all portable. Right
 * now just prepend a checksum.
 */
ssize_t arcan_shmif_eventpack(
	const struct arcan_event* const aev, uint8_t* dbuf, size_t dbuf_sz)
{
	if (dbuf_sz < sizeof(struct arcan_event) + 2)
		return -1;

	uint16_t checksum = subp_checksum(
		(const uint8_t* const)aev, sizeof(struct arcan_event)) ^
		(uint16_t)((ASHMIF_VERSION_MAJOR << 2) | ASHMIF_VERSION_MINOR);

	memcpy(dbuf, &checksum, sizeof(uint16_t));
	memcpy(&dbuf[2], aev, sizeof(struct arcan_event));

	return sizeof(struct arcan_event) + 2;
}

ssize_t arcan_shmif_eventunpack(
	const uint8_t* const buf, size_t buf_sz, struct arcan_event* out)
{
	if (buf_sz < sizeof(struct arcan_event) + 2)
		return -1;

	uint16_t chksum_in;
	memcpy(&chksum_in, buf, sizeof(uint16_t));
	memcpy(out, &buf[2], sizeof(struct arcan_event));

	uint16_t chksum = subp_checksum((const uint8_t*)out,
		sizeof(struct arcan_event)) ^
		(uint16_t)((ASHMIF_VERSION_MAJOR << 2) | ASHMIF_VERSION_MINOR
	);

	if (chksum_in != chksum)
		return -1;

	return sizeof(struct arcan_event) + 2;
}

const char* arcan_shmif_eventstr(arcan_event* aev, char* dbuf, size_t dsz)
{
	static char evbuf[256];
	if (!aev)
		return "";

	struct arcan_event ev = *aev;

	char* work;
	if (dbuf){
		work = dbuf;
	}
	else{
		work = evbuf;
		dsz = sizeof(evbuf);
	}

	if (ev.category == EVENT_EXTERNAL){
		switch (ev.ext.kind){
		case EVENT_EXTERNAL_MESSAGE:
			snprintf(work, dsz,"EXT:MESSAGE(%s):%d",
				(char*)ev.ext.message.data, ev.ext.message.multipart);
		break;
		case EVENT_EXTERNAL_COREOPT:
			snprintf(work, dsz,"EXT:COREOPT(%s)", (char*)ev.ext.message.data);
		break;
		case EVENT_EXTERNAL_IDENT:
			snprintf(work, dsz,"EXT:IDENT(%s)", (char*)ev.ext.message.data);
		break;
		case EVENT_EXTERNAL_FAILURE:
			snprintf(work, dsz,"EXT:FAILURE()");
		break;
		case EVENT_EXTERNAL_BUFFERSTREAM:
			snprintf(work, dsz,"EXT:BUFFERSTREAM(%zu, w*h: %zu*%zu, fmt: %d, "
				"stride: %zu, offset: %zu, mod(lo,hi): %"PRIu32",%"PRIu32")",
				(size_t)ev.ext.bstream.left,
				(size_t)ev.ext.bstream.width, (size_t)ev.ext.bstream.height,
				(int)ev.ext.bstream.format,
				(size_t)ev.ext.bstream.stride,
				(size_t)ev.ext.bstream.offset,
				(uint32_t)ev.ext.bstream.mod_lo,
				(uint32_t)ev.ext.bstream.mod_hi
			);
		break;
		case EVENT_EXTERNAL_FRAMESTATUS:
			snprintf(work, dsz,"EXT:FRAMESTATUS(DEPRECATED)");
		break;
		case EVENT_EXTERNAL_STREAMINFO:
			snprintf(work, dsz,"EXT:STREAMINFO(id: %d, kind: %d, lang: %c%c%c%c",
				ev.ext.streaminf.streamid, ev.ext.streaminf.datakind,
				ev.ext.streaminf.langid[0], ev.ext.streaminf.langid[1],
				ev.ext.streaminf.langid[2], ev.ext.streaminf.langid[3]);
		break;
		case EVENT_EXTERNAL_STATESIZE:
			snprintf(work, dsz, "EXT:STATESIZE(size: %"PRIu32", type: %"PRIu32")",
				ev.ext.stateinf.size, ev.ext.stateinf.type);
		break;
		case EVENT_EXTERNAL_FLUSHAUD:
			snprintf(work, dsz,"EXT:FLUSHAUD()");
		break;
		case EVENT_EXTERNAL_SEGREQ:
			snprintf(work, dsz,"EXT:SEGREQ(id: %"PRIu32", dimensions: %"PRIu16
				"*%"PRIu16"+" "%"PRId16",%"PRId16", kind: %d)",
				ev.ext.segreq.id, ev.ext.segreq.width, ev.ext.segreq.height,
				ev.ext.segreq.xofs, ev.ext.segreq.yofs, ev.ext.segreq.kind);
		break;
		case EVENT_EXTERNAL_CURSORHINT:
			snprintf(work, dsz,"EXT:CURSORHINT(%s)", ev.ext.message.data);
		break;
		case EVENT_EXTERNAL_VIEWPORT:
			snprintf(work, dsz,"EXT:VIEWPORT(frame: %"PRIu64", "
				"id: %"PRIu32" parent: %"PRIu32" "
				"@x,y+w,h: +%"PRId32",%"PRId32"+%"PRIu16",%"PRIu16
				", border: %d,%d,%d,%d embed: %d focus: %d, invisible: %d, "
				"anchor-edge: %d, anchor-pos: %d, edge: %d, z: %d)",
				ev.ext.frame_id,
				ev.ext.viewport.ext_id,
				ev.ext.viewport.parent,
				ev.ext.viewport.x, ev.ext.viewport.y,
				(unsigned short) ev.ext.viewport.w,
				(unsigned short) ev.ext.viewport.h,
				(int)ev.ext.viewport.border[0], (int)ev.ext.viewport.border[1],
				(int)ev.ext.viewport.border[2], (int)ev.ext.viewport.border[3],
				(int)ev.ext.viewport.embedded,
				(int)ev.ext.viewport.focus,
				(int)ev.ext.viewport.invisible,
				(int)ev.ext.viewport.anchor_edge,
				(int)ev.ext.viewport.anchor_pos,
				(int)ev.ext.viewport.edge,
				(int)ev.ext.viewport.order
			);
		break;
		case EVENT_EXTERNAL_CONTENT:
			snprintf(work, dsz,"EXT:CONTENT(x: %f/%f, y: %f/%f, wh: %f/%f)",
				ev.ext.content.x_pos, ev.ext.content.x_sz,
				ev.ext.content.y_pos, ev.ext.content.y_sz,
				ev.ext.content.width, ev.ext.content.height
			);
		break;
		case EVENT_EXTERNAL_LABELHINT:
			snprintf(work, dsz,"EXT:LABELHINT(label: %.16s, default: %d, descr: %.58s, "
				"i-alias: %d, i-type: %d)",
				ev.ext.labelhint.label, ev.ext.labelhint.initial,
				ev.ext.labelhint.descr, ev.ext.labelhint.subv,
				ev.ext.labelhint.idatatype);
		break;
		case EVENT_EXTERNAL_REGISTER:
			snprintf(work, dsz,"EXT:REGISTER(title: %.64s, kind: %d, %"
				PRIx64":%"PRIx64")",
				ev.ext.registr.title, ev.ext.registr.kind,
				ev.ext.registr.guid[0], ev.ext.registr.guid[1]);
		break;
		case EVENT_EXTERNAL_ALERT:
			snprintf(work, dsz,"EXT:ALERT(%s):%d",
				(char*)ev.ext.message.data, ev.ext.message.multipart);
		break;
		case EVENT_EXTERNAL_CLOCKREQ:
			snprintf(work, dsz,"EXT:CLOCKREQ(rate: %"PRIu32", id: %"PRIu32", "
				"dynamic: %"PRIu8", once: %"PRIu8")",
				ev.ext.clock.rate, ev.ext.clock.id,
				ev.ext.clock.dynamic, ev.ext.clock.once);
		break;
		case EVENT_EXTERNAL_BCHUNKSTATE:
			snprintf(work, dsz,"EXT:BCHUNKSTATE(size: %"PRIu64", hint: %"
			PRIu8", input: %"PRIu8", stream: %"PRIu8" ext: %.68s)",
				ev.ext.bchunk.size, ev.ext.bchunk.hint, ev.ext.bchunk.input,
				ev.ext.bchunk.stream, ev.ext.bchunk.extensions);
		break;
		case EVENT_EXTERNAL_STREAMSTATUS:
			snprintf(work, dsz,"EXT:STREAMSTATUS(#%"PRIu32" %.9s / %.9s, comp: %f, "
			"streaming: %"PRIu8")", ev.ext.streamstat.frameno,
				(char*)ev.ext.streamstat.timestr,
				(char*)ev.ext.streamstat.timelim,
				ev.ext.streamstat.completion, ev.ext.streamstat.streaming);
		break;
		case EVENT_EXTERNAL_NETSTATE:
			snprintf(work, dsz,"EXT:NETSTATE(space=%"PRIu8":state=%"
				PRIu8":type=%"PRIu8":name=%s",
				ev.ext.netstate.space,
				ev.ext.netstate.state,
				ev.ext.netstate.type,
				ev.ext.netstate.name
			);
		break;
		case EVENT_EXTERNAL_PRIVDROP:
			snprintf(work, dsz,"EXT:PRIVDROP(level=%d)", (int)ev.tgt.ioevs[0].iv);
		break;
		default:
			snprintf(work, dsz,"EXT:UNKNOWN(%d)", (int)ev.ext.kind);
		break;
		}
	}
	else if (ev.category == EVENT_TARGET){
		switch (ev.tgt.kind){
		case TARGET_COMMAND_EXIT: snprintf(work, dsz,"TGT:EXIT"); break;
		case TARGET_COMMAND_FRAMESKIP:
			snprintf(work, dsz,"TGT:FRAMESKIP(%d)", (int) ev.tgt.ioevs[0].iv);
		break;
		case TARGET_COMMAND_STEPFRAME:
			snprintf(work, dsz,"TGT:STEPFRAME(#%d, ID: %d, sec: %u, frac: %u)",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].uiv,
				ev.tgt.ioevs[3].uiv);
		break;
		case TARGET_COMMAND_COREOPT:
			snprintf(work, dsz,"TGT:COREOPT(%d=%s)", ev.tgt.code, ev.tgt.message);
		break;
		case TARGET_COMMAND_STORE:
			snprintf(work, dsz,"TGT:STORE(fd)");
		break;
		case TARGET_COMMAND_RESTORE:
			snprintf(work, dsz,"TGT:RESTORE(fd)");
		break;
		case TARGET_COMMAND_BCHUNK_IN:
			snprintf(work, dsz,"TGT:BCHUNK-IN(%"PRIu64"b)",
				(uint64_t) ev.tgt.ioevs[1].iv | ((uint64_t)ev.tgt.ioevs[2].iv << 32));
		break;
		case TARGET_COMMAND_BCHUNK_OUT:
			snprintf(work, dsz,"TGT:BCHUNK-OUT(%"PRIu64"b)",
				(uint64_t) ev.tgt.ioevs[1].iv | ((uint64_t)ev.tgt.ioevs[2].iv << 32));
		break;
		case TARGET_COMMAND_RESET:
			snprintf(work, dsz,"TGT:RESET(%s)",
				ev.tgt.ioevs[0].iv == 0 ? "soft" :
					ev.tgt.ioevs[0].iv == 1 ? "hard" :
						ev.tgt.ioevs[0].iv == 2 ? "recover-rst" :
							ev.tgt.ioevs[0].iv == 3 ? "recover-recon" : "bad-value");
		break;
		case TARGET_COMMAND_PAUSE:
			snprintf(work, dsz,"TGT:PAUSE()");
		break;
		case TARGET_COMMAND_UNPAUSE:
			snprintf(work, dsz,"TGT:UNPAUSE()");
		break;
		case TARGET_COMMAND_SEEKCONTENT:
			if (ev.tgt.ioevs[0].iv == 0){
				snprintf(work, dsz,"TGT:SEEKCONTENT(relative: x(+%d), y(+%d))",
					ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].iv);
			}
			else if (ev.tgt.ioevs[0].iv == 1){
				snprintf(work, dsz,"TGT:SEEKCONTENT(absolute: x(%f), y(%f)",
					ev.tgt.ioevs[1].fv, ev.tgt.ioevs[2].fv);
			}
			else
				snprintf(work, dsz,"TGT:SEEKCONTENT(BROKEN)");
			break;
		case TARGET_COMMAND_SEEKTIME:
			snprintf(work, dsz,"TGT:SEEKTIME(%s: %f)",
				ev.tgt.ioevs[0].iv != 1 ? "relative" : "absolute",
				ev.tgt.ioevs[1].fv);
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			snprintf(work, dsz,
			"TGT:DISPLAYHINT(%d*%d, ppcm: %f, flags: %s%s%s%s%s%s, cell: %d, %d, tgt: %u",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv, ev.tgt.ioevs[4].fv,
				(ev.tgt.ioevs[2].iv & 1) ? "drag-sz " : "",
				(ev.tgt.ioevs[2].iv & 2) ? "invis " : "",
				(ev.tgt.ioevs[2].iv & 4) ? "unfocus " : "",
				(ev.tgt.ioevs[2].iv & 8) ? "maximized " : "",
				(ev.tgt.ioevs[2].iv & 16) ? "minimized " : "",
				(ev.tgt.ioevs[2].iv & 32) ? "detached " : "",
				ev.tgt.ioevs[5].iv, ev.tgt.ioevs[6].iv,
				ev.tgt.ioevs[7].uiv
			);
		break;
		case TARGET_COMMAND_ANCHORHINT:
			snprintf(work, dsz,
				"TGT:ANCHORHINT(relxyz=%d,%d,%d:sref=%"PRIu32":dref=%"PRIu32,
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].iv,
				ev.tgt.ioevs[3].uiv, ev.tgt.ioevs[4].uiv);
		break;
		case TARGET_COMMAND_SETIODEV:
			snprintf(work, dsz,"TGT:IODEV(DEPRECATED)");
		break;
		case TARGET_COMMAND_STREAMSET:
			snprintf(work, dsz,"TGT:STREAMSET(%d)", ev.tgt.ioevs[0].iv);
		break;
		case TARGET_COMMAND_ATTENUATE:
			snprintf(work, dsz,"TGT:ATTENUATE(%f)", ev.tgt.ioevs[0].fv);
		break;
		case TARGET_COMMAND_AUDDELAY:
			snprintf(work, dsz,"TGT:AUDDELAY(aud +%d ms, vid +%d ms)",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
		break;
		case TARGET_COMMAND_NEWSEGMENT:
			snprintf(work, dsz,"TGT:NEWSEGMENT(cookie:%u, direction: %s, type: %d)",
				ev.tgt.ioevs[3].uiv, ev.tgt.ioevs[1].iv ? "read" : "write",
				ev.tgt.ioevs[2].iv);
		break;
		case TARGET_COMMAND_REQFAIL:
			snprintf(work, dsz,"TGT:REQFAIL(cookie:%d)", ev.tgt.ioevs[0].iv);
		break;
		case TARGET_COMMAND_BUFFER_FAIL:
			snprintf(work, dsz,"TGT:BUFFER_FAIL()");
		break;
		case TARGET_COMMAND_DEVICE_NODE:
			if (ev.tgt.ioevs[0].iv == 1)
				snprintf(work, dsz,"TGT:DEVICE_NODE(render-node)");
			else if (ev.tgt.ioevs[0].iv == 2)
				snprintf(work, dsz,"TGT:DEVICE_NODE(connpath: %s)", ev.tgt.message);
			else if (ev.tgt.ioevs[0].iv == 3)
				snprintf(work, dsz,"TGT:DEVICE_NODE(remote: %s)", ev.tgt.message);
			else if (ev.tgt.ioevs[0].iv == 4)
				snprintf(work, dsz,"TGT:DEVICE_NODE(alt: %s)", ev.tgt.message);
			else if (ev.tgt.ioevs[0].iv == 5)
				snprintf(work, dsz,"TGT:DEVICE_NODE(auth-cookie)");
		break;
		case TARGET_COMMAND_GRAPHMODE:
			snprintf(work, dsz,"TGT:GRAPHMODE(group: %d, value: %.0f, %.0f, %.0f)",
				ev.tgt.ioevs[0].iv,
				ev.tgt.ioevs[1].fv, ev.tgt.ioevs[2].fv, ev.tgt.ioevs[3].fv);
		break;
		case TARGET_COMMAND_MESSAGE:
			snprintf(work,
				dsz,"TGT:MESSAGE(continued: %d, message: %s)", ev.tgt.ioevs[0].iv, ev.tgt.message);
		break;
		case TARGET_COMMAND_FONTHINT:
			snprintf(work, dsz,"TGT:FONTHINT("
				"type: %d, size: %f mm, hint: %d, chain: %d)",
				ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].fv, ev.tgt.ioevs[3].iv,
				ev.tgt.ioevs[4].iv
			);
		break;
		case TARGET_COMMAND_GEOHINT:
			snprintf(work, dsz,"TGT:GEOHINT("
				"lat: %f, long: %f, elev: %f, country/lang: %s/%s/%s, ts: %d)",
				ev.tgt.ioevs[0].fv, ev.tgt.ioevs[1].fv, ev.tgt.ioevs[2].fv,
				ev.tgt.ioevs[3].cv, ev.tgt.ioevs[4].cv, ev.tgt.ioevs[5].cv,
				ev.tgt.ioevs[6].iv
			);
		break;
		case TARGET_COMMAND_OUTPUTHINT:
			snprintf(work, dsz,"OUTPUTHINT("
				"maxw/h: %d/%d, rate: %d, minw/h: %d/%d, id: %d",
				ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv, ev.tgt.ioevs[2].iv,
				ev.tgt.ioevs[3].iv, ev.tgt.ioevs[4].iv, ev.tgt.ioevs[5].iv
			);
		break;
		case TARGET_COMMAND_ACTIVATE:
			snprintf(work, dsz,"TGT:ACTIVATE()");
		break;
		default:
			snprintf(work, dsz,"TGT:UNKNOWN(!)");
		break;
	}
	}
	else if (ev.category == EVENT_IO){
	switch (ev.io.datatype){
	case EVENT_IDATATYPE_TRANSLATED:
		snprintf(work, dsz,"IO:(%s)[kbd(%d):%s] %d:mask=%d,sym:%d,code:%d,utf8:%s",
			ev.io.label,
			ev.io.devid, ev.io.input.translated.active ? "pressed" : "released",
			(int)ev.io.subid, (int)ev.io.input.translated.modifiers,
			(int)ev.io.input.translated.keysym,
			(int)ev.io.input.translated.scancode,
			ev.io.input.translated.utf8
		);
	break;
	case EVENT_IDATATYPE_ANALOG:
		snprintf(work, dsz,"IO:(%s)[%s(%d):%d] rel: %s, v(%d){%d, %d, %d, %d}",
			ev.io.label,
			ev.io.devkind == EVENT_IDEVKIND_MOUSE ? "mouse" : "analog",
			ev.io.devid, ev.io.subid,
			ev.io.input.analog.gotrel ? "yes" : "no",
			(int)ev.io.input.analog.nvalues,
			(int)ev.io.input.analog.axisval[0],
			(int)ev.io.input.analog.axisval[1],
			(int)ev.io.input.analog.axisval[2],
			(int)ev.io.input.analog.axisval[3]
		);
	break;
	case EVENT_IDATATYPE_EYES:
		snprintf(work, dsz,"EYE:(%s)[eye(%d)] %d: head:%f,%f,%f ang: %f,%f,%f"
			"gaze_1: %f,%f gaze_2: %f,%f",
			ev.io.label,
			ev.io.devid,
			ev.io.subid,
			ev.io.input.eyes.head_pos[0],
			ev.io.input.eyes.head_pos[1],
			ev.io.input.eyes.head_pos[2],
			ev.io.input.eyes.head_ang[0],
			ev.io.input.eyes.head_ang[1],
			ev.io.input.eyes.head_ang[2],
			ev.io.input.eyes.gaze_x1,
			ev.io.input.eyes.gaze_y1,
			ev.io.input.eyes.gaze_x2,
			ev.io.input.eyes.gaze_y2
		);
	break;
	case EVENT_IDATATYPE_TOUCH:
		snprintf(work, dsz,"IO:(%s)[touch(%d)] %d: @%d,%d pressure: %f, size: %f",
			ev.io.label,
			ev.io.devid,
			ev.io.subid,
			(int) ev.io.input.touch.x,
			(int) ev.io.input.touch.y,
			ev.io.input.touch.pressure,
			ev.io.input.touch.size
		);
	break;
	case EVENT_IDATATYPE_DIGITAL:
		if (ev.io.devkind == EVENT_IDEVKIND_MOUSE)
			snprintf(work, dsz,"IO:[mouse(%d):%d], %s:%s", ev.io.devid,
				ev.io.subid, msub_to_lbl(ev.io.subid),
				ev.io.input.digital.active ? "pressed" : "released"
			);
		else
			snprintf(work, dsz,"IO:[digital(%d):%d], %s", ev.io.devid,
				ev.io.subid, ev.io.input.digital.active ? "pressed" : "released");
	break;
	default:
		snprintf(work, dsz,"IO:[unhandled(%d)]", ev.io.datatype);
	break;
	}
	}

	return work;
}
