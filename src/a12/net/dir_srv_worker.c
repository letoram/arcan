#include <arcan_shmif.h>
#include <arcan_shmif_server.h>

#include <ftw.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <stdlib.h>
#include <ctype.h>
#include <inttypes.h>
#include <stdint.h>
#include <signal.h>
#include <pthread.h>

#include "../a12.h"
#include "../a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"
#include "directory.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <dirent.h>
#include <fcntl.h>

static int shmifopen_flags =
			SHMIF_ACQUIRE_FATALFAIL |
			SHMIF_NOACTIVATE |
			SHMIF_NOAUTO_RECONNECT |
			SHMIF_NOREGISTER |
			SHMIF_SOCKET_PINGEVENT;

static struct arcan_shmif_cont shmif_parent_process;
static struct a12_state* active_client_state;
static struct appl_meta* pending_index;
static struct ioloop_shared* ioloop_shared;
static struct a12_state trace_state = {.tracetag = "worker"};
static uint8_t auth_pub_key[32];
static uint8_t pending_tunnel;

#define TRACE(...) do { \
	if (!(a12_trace_targets & A12_TRACE_DIRECTORY))\
		break;\
	struct a12_state* S = &trace_state;\
		a12int_trace(A12_TRACE_DIRECTORY, __VA_ARGS__);\
	} while (0);

static void parent_worker_event(
	struct a12_state* S, struct arcan_shmif_cont* C, struct arcan_event* ev);

static struct a12_bhandler_res srv_bevent(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag);

static void drop_evqueue_item(struct evqueue_entry* rep)
{
	if (!rep)
		return;

	if (arcan_shmif_descrevent(&rep->ev) && rep->ev.tgt.ioevs[0].iv > 0){
		TRACE("drop:queued_descriptor=%d", rep->ev.tgt.ioevs[0].iv);
		close(rep->ev.tgt.ioevs[0].iv);
	}
	rep->next = NULL;
	free(rep);
}

static struct evqueue_entry* run_evqueue(
	struct a12_state* S, struct arcan_shmif_cont* C, struct evqueue_entry* rep)
{
/* run until the last event and return that one */
	while (rep->next){
		struct evqueue_entry* cur = rep;
		parent_worker_event(S, C, &rep->ev);
		rep = rep->next;
		drop_evqueue_item(cur);
	}
	return rep;
}

static void drop_evqueue(struct evqueue_entry* rep){
	while (rep){
		struct evqueue_entry* cur = rep;
		rep = rep->next;
		drop_evqueue_item(cur);
	}
}

static int request_resource(
	struct a12_state* S, struct arcan_shmif_cont* C, int ns, char* res, int mode)
{
	struct evqueue_entry* rep = malloc(sizeof(struct evqueue_entry));
	bool status = dir_request_resource(C, ns, res, mode, rep);
	int fd = -1;

	if (status){
		rep = run_evqueue(S, C, rep);
		struct arcan_event ev = rep->ev;

		if (ev.tgt.kind != TARGET_COMMAND_REQFAIL){
			fd = arcan_shmif_dupfd(ev.tgt.ioevs[0].iv, -1, true);
			a12int_trace(A12_TRACE_DIRECTORY, "accepted:descriptor=%d", fd);
		}
		else
			a12int_trace(
				A12_TRACE_DIRECTORY, "rejected=%s", arcan_shmif_eventstr(&ev, NULL, 0));
	}
	else {
		drop_evqueue(rep);
	}

	return fd;
}

/* cont is actually wrong here as we haven't set a context for the channel
 * since it's not being used in the normal fashion - the actual connection
 * to the coordinating process is through the [tag] that is also a context */
static void on_a12srv_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct ioloop_shared* I = tag;
	struct directory_meta* cbt = I->cbt;
	struct arcan_shmif_cont* C = cbt->C;

	if (ev->category != EVENT_EXTERNAL)
		return;

	if (ev->ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
/* if it is for output, we save the name and make the actual request when
 * the bstream transfer is initiated - as the namespace will be provided there. */
		if (!ev->ext.bchunk.input){
			TRACE("mark_pending=%s", arcan_shmif_eventstr(ev, NULL, 0));
			cbt->breq_pending = *ev;
			return;
		}

/* special-case debugging comes by the ".monitor" extension which we handle
 * similar to joining an appl so that it becomes a shmif segment we can
 * translate to / from MESSAGE events rather than as a binary transfer channel */
		if (strcmp((char*) ev->ext.bchunk.extensions, ".monitor") == 0){
			arcan_shmif_enqueue(C, ev);
			return;
		}

/* Request hosting the appl for a limited client that can't execute appls
 * locally */
		if (strcmp((char*) ev->ext.bchunk.extensions, ".applhost") == 0){
			struct arcan_event req = {
				.category = EVENT_EXTERNAL,
				.ext.kind = EVENT_EXTERNAL_MESSAGE
			};
			snprintf((char*)req.ext.message.data,
				COUNT_OF(req.ext.message.data),
				"a12:applhost:applid=%"PRIu64, ev->ext.bchunk.ns);
			arcan_shmif_enqueue(C, &req);
			return;
		}

/*
 * Request downloading the appl specifically? other requests should be routed
 * through the controller (if exists) before trying the appl specific
 * state-store. A security consideration here would be a downloaded appl first
 * requesting .index for the private store, enumerating and downloading each
 * file, then pushing it to the appl-store.
 *
 * There is a case for permitting accessing the private store, e.g. the durden
 * desktop, but that should be a manifest permission and rejected client side
 * unless permitted (when running as the outer desktop) and forcing any nested
 * appls to receive it through a bchunkreq or drag/drop).
 */
		int fd = request_resource(cbt->S,
					ioloop_shared->shmif.addr ? &ioloop_shared->shmif : C,
					ev->ext.bchunk.ns,
						ev->ext.bchunk.extensions[0] ?
						(char*) ev->ext.bchunk.extensions : ".appl", BREQ_LOAD
				);

		char empty_ext[16] = {0};

/* if it's a named request, just send that, otherwise go for appl+state */
		if (fd != -1 && ev->ext.bchunk.extensions[0]){
			a12_enqueue_bstream(cbt->S,
				fd, A12_BTYPE_BLOB, ev->ext.bchunk.identifier, false, 0, empty_ext);
			TRACE("close_tmp:descriptor=%d", fd);
			close(fd);
			I->userfd2 = a12_btransfer_outfd(I->S);
		}
		else if (fd != -1 && ev->ext.bchunk.ns){
			struct evqueue_entry* rep = malloc(sizeof(struct evqueue_entry));

			int state_fd =
				request_resource(cbt->S, C, ev->ext.bchunk.ns, ".state", BREQ_LOAD);

			if (state_fd != -1){
				a12_enqueue_bstream(cbt->S,
					state_fd, A12_BTYPE_STATE, ev->ext.bchunk.ns, false, 0, empty_ext);
				close(state_fd);
				I->userfd2 = a12_btransfer_outfd(I->S);
			}

			a12_enqueue_bstream(cbt->S,
				fd, A12_BTYPE_APPL, ev->ext.bchunk.ns, false, 0, empty_ext);
			I->userfd2 = a12_btransfer_outfd(I->S);
			TRACE("close_tmp:descriptor=%d", fd);
			close(fd);
		}
		else
			a12_channel_enqueue(cbt->S,
				&(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_REQFAIL,
					.tgt.ioevs[0].uiv = ev->ext.bchunk.identifier
			});
	}
/* Actual identity will be determined by the parent to make sure we don't have
 * any collisions or name changes after the first REGISTER. It will also tag
 * with the Kpub we have. */
	else if (ev->ext.kind == EVENT_EXTERNAL_REGISTER &&
		(a12_remote_mode(cbt->S) == ROLE_DIR ||
		a12_remote_mode(cbt->S) == ROLE_SOURCE ||
		a12_remote_mode(cbt->S) == ROLE_SINK)){
		arcan_event disc = {
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_NETSTATE,
			.ext.netstate = {
				.type = a12_remote_mode(cbt->S),
				.space = 5
			}
		};

/* truncate the identifier */
		snprintf(disc.ext.netstate.name, 16, "%s", ev->ext.registr.title);
		TRACE("source_register=%s", disc.ext.netstate.name);

		arcan_shmif_enqueue(C, &disc);
	}

/* signals that a streaming transfer is completed or broken, send it back to
 * ack that we got it and if the client has nothing else to do, can shut down. */
	else if (ev->ext.kind == EVENT_EXTERNAL_STREAMSTATUS){
		if (cbt->in_transfer && ev->ext.streamstat.identifier == cbt->transfer_id){
			cbt->in_transfer = false;
			cbt->breq_pending = (struct arcan_event){0};

/* This is where atomic swap goes on completion (see BCHUNKSTATE use) */
			a12_channel_enqueue(cbt->S, ev);
		}
		else
			TRACE("kind=error:streamstatus:status=unknown_stream");
	}

	else if (ev->ext.kind == EVENT_EXTERNAL_IDENT){
		TRACE("source_join=%s", ev->ext.message.data);
		arcan_shmif_enqueue(C, ev);
	}

/* by default messages are handled through dir_srv.c parent process, but
 * if we have been delegated a message handler and the reserved a12: prefix */
	else if (ev->ext.kind == EVENT_EXTERNAL_MESSAGE){
		struct arcan_shmif_cont* dst = C;

		if (ioloop_shared->shmif.addr){
			dst = &ioloop_shared->shmif;
		}

/* This does not handle multipart, though there aren't any control messages
 * right now that would require it. Debugging a controller is a bit special
 * in that we have joined, but not triggered as a join, and interrupts are
 * treated as a sideband as we don't have a signalling pathway. */
		if (strncmp((char*)ev->ext.message.data, "a12:", 4) == 0){
			dst = C;
		}

		arcan_shmif_enqueue(dst, ev);
	}
}

/* S, cbt isn't guaranteed here if it happens during the activation stage */
static void bchunk_event(struct a12_state *S,
	struct directory_meta* cbt, struct arcan_shmif_cont *C, struct arcan_event* ev)
{
	a12int_trace(A12_TRACE_DIRECTORY, "bchunk_in:%s", arcan_shmif_eventstr(ev, NULL, 0));

/* the index is packed as shmif argstrs line-separated */
	if (strcmp(ev->tgt.message, ".appl-index") == 0){
		struct appl_meta* first = dir_unpack_index(ev->tgt.ioevs[0].iv);
		if (!S || S == &trace_state)
			pending_index = first;
		else
			a12int_set_directory(S, first);
	}
/*
 * we have a new tunnel, track it and then (next message) send the reply and
 * attach the processing thread. Track pending_tunnel as global state so the
 * reply to command_diropened can forward it in the feedback.
 */
	else if (strcmp(ev->tgt.message, ".tun") == 0){
		pending_tunnel = a12_alloc_tunnel(S);
		if (pending_tunnel){
			a12_set_tunnel_sink(S, pending_tunnel,
				arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, false));
			anet_directory_tunnel_thread(ioloop_shared, pending_tunnel);
		}
	}
/* Joining an appl-group through a controller process is different from
 * NEWSEGMENT as the mempage is acquired over the segment - fake a named
 * connection with the descriptor from newsegment by having SOCKIN_FD without
 * ARCAN_SOCKIN_MEMFD */
	else if (strncmp(ev->tgt.message, ".appl-", 6) == 0 ||
		strcmp(ev->tgt.message, ".monitor") == 0){

		if (ioloop_shared->shmif.addr)
			arcan_shmif_drop(&ioloop_shared->shmif);

		int fd = arcan_shmif_dupfd(ev->tgt.ioevs[0].iv, -1, true);
		char sockval[16];
		snprintf(sockval, 16, "%d", fd);

		setenv("ARCAN_SOCKIN_FD", sockval, true);
		ioloop_shared->shmif =
			arcan_shmif_open(SEGID_NETWORK_CLIENT, shmifopen_flags, NULL);

		if (!ioloop_shared->shmif.addr){
			a12int_trace(A12_TRACE_DIRECTORY, "kind=error:appl_runner_channel");
			return;
		}

		if (strncmp(ev->tgt.message, ".appl-", 6) == 0){
			const char* applname = (const char*) &ev->tgt.message[6];

			struct arcan_event joinev = (struct arcan_event){
				.category = EVENT_EXTERNAL,
				.ext.kind = EVENT_EXTERNAL_NETSTATE
			};

/* just H(kPub | applname) to give a persistent identifier for the ctrl
 * connection without giving the ctrl unnecessary information (kPub). */
			blake3_hasher hash;
			blake3_hasher_init(&hash);
			blake3_hasher_update(&hash, auth_pub_key, 32);
			blake3_hasher_update(&hash, applname, strlen(applname));
			blake3_hasher_finalize(&hash, joinev.ext.netstate.pubk, 32);

			arcan_shmif_enqueue(&ioloop_shared->shmif, &joinev);
		}

		a12int_trace(A12_TRACE_DIRECTORY,
			"kind=status:appl_runner:join:%s", ev->tgt.message);
	}
}

static bool wait_for_activation(
	struct a12_context_options* aopt, struct arcan_shmif_cont* C)
{
	struct directory_meta* cbt = C->user;
	struct arcan_event ev;

	while (arcan_shmif_wait(C, &ev)){
		TRACE("activation:event=%s", arcan_shmif_eventstr(&ev, NULL, 0));

		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_BCHUNK_IN){
			bchunk_event(&trace_state, cbt, C, &ev);
		}
/* the authentication secret need to be set in the S->opts before
 * proceeding with the protocol decoding leading to the key authentication
 * part */
		else if (ev.tgt.kind == TARGET_COMMAND_MESSAGE){
			struct arg_arr* stat = arg_unpack(ev.tgt.message);
			if (!stat)
				continue;

			const char* secret = NULL;
			if (arg_lookup(stat, "secret", 0, &secret) && secret){
				snprintf(aopt->secret, 32, "%s", secret);
			}

			arg_cleanup(stat);
		}
		else if (ev.tgt.kind == TARGET_COMMAND_ACTIVATE){
			return true;
		}

		TRACE("event:kind=%s", arcan_shmif_eventstr(&ev, NULL, 0));
	}

	return false;
}

static void do_external_event(
	struct directory_meta* cbt,
	struct a12_state* S, struct arcan_shmif_cont* C, struct arcan_event* ev)
{
	switch (ev->ext.kind){
	case EVENT_EXTERNAL_MESSAGE:
		a12_channel_enqueue(cbt->S, ev);
	break;

	case EVENT_EXTERNAL_NETSTATE:{
		size_t i = 0;

		if (a12_remote_mode(S) == ROLE_SOURCE){
			a12int_trace(A12_TRACE_DIRECTORY, "open_to_src");

			struct a12_dynreq dynreq = (struct a12_dynreq){0};
			snprintf(dynreq.authk, 12, "%s", cbt->secret);
			memcpy(dynreq.pubk, ev->ext.netstate.name, 32);

			if (pending_tunnel){
				a12int_trace(A12_TRACE_DIRECTORY, "diropen:tunnel_src");
				dynreq.proto = 4;
				snprintf(dynreq.host, COUNT_OF(dynreq.host), "%d", pending_tunnel);
				anet_directory_tunnel_thread(ioloop_shared, pending_tunnel);
				pending_tunnel = 0;
			}

			a12_supply_dynamic_resource(S, dynreq);
			return;
		}

		for (; i < COUNT_OF(ev->ext.netstate.name); i++){
			if (ev->ext.netstate.name[i] == ':'){
				ev->ext.netstate.name[i] = '\0';
				i++;
				break;
			}
		}

		if (i > COUNT_OF(ev->ext.netstate.name) - 32){
			a12int_trace(A12_TRACE_DIRECTORY,
				"kind=einval:netstate_name=%s", ev->ext.netstate.name);
			return;
		}

		a12int_trace(A12_TRACE_DIRECTORY, "notify:name=%s", ev->ext.netstate.name);
		a12int_notify_dynamic_resource(S,
			ev->ext.netstate.name, (uint8_t*)&ev->ext.netstate.name[i],
			ev->ext.netstate.type, ev->ext.netstate.state, ev->ext.netstate.ns);
	}
	break;
	default:
	break;
	}
}

static void parent_worker_event(
	struct a12_state* S, struct arcan_shmif_cont* C, struct arcan_event* ev)
{
	struct directory_meta* cbt = C->user;

	if (ev->category == EVENT_EXTERNAL)
		return do_external_event(cbt, S, C, ev);

/* Parent process responsible for verifying and tagging name with petname:kpub.
 * the NETSTATE associated with diropen is part of the on_directory event
 * handler and doesn't reach this point. */
	if (ev->category != EVENT_TARGET)
		return;

	if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_IN){
		bchunk_event(S, cbt, C, ev);
	}
	else if (ev->tgt.kind == TARGET_COMMAND_MESSAGE){
		struct arg_arr* stat = arg_unpack(ev->tgt.message);

/* Would only be sent to us if the parent a. thinks we're in a specific APPL
 * via IDENT b. the ruleset tells us to message. Inject into a12_state
 * verbatim. The parent would also need to ensure that the client can't inject
 * the a12: tag into the MESSAGE or we have a weird form of 'Packets in
 * Packets'. */
		if (!stat || !arg_lookup(stat, "a12", 0, NULL)){
			a12_channel_enqueue(S, ev);
			if (stat)
				arg_cleanup(stat);
			return;
		}

		const char* tmp;
		if (arg_lookup(stat, "drop_tunnel", 0, &tmp)){
			a12int_trace(A12_TRACE_DIRECTORY, "kind=drop_tunnel:id=%s", tmp);
			a12_drop_tunnel(S, 1);
		}
		else if (arg_lookup(stat, "dir_secret", 0, &tmp) && tmp){
			free(cbt->secret);
			cbt->secret = strdup(tmp);
		}

/* reserved for other messages */
		arg_cleanup(stat);
	}
}

static void on_appl_shmif(struct ioloop_shared* S, bool ok)
{
	struct arcan_event ev;
	int pv;

/* most of these behave just like on_shmif, it is just a different sender */
	while ((pv = arcan_shmif_poll(&S->shmif, &ev)) > 0){
		TRACE("to_appl=%s", arcan_shmif_eventstr(&ev, NULL, 0));

		a12_channel_enqueue(active_client_state, &ev);
	}

/* if the worker group we are part of dies, shutdown. this isn't entirely
 * necessary, it could be that it can recover, but that is something to
 * consider later when everything is more mature. */
	if (-1 == pv || !ok){
		arcan_shmif_drop(&S->shmif);
		S->shutdown = true;
	}
}

static void on_bstream_out(struct ioloop_shared* S, bool ok)
{
/* just make sure we are synched to the latest queued one, ioloop will
 * try and flush if there is anything */
	S->userfd2 = a12_btransfer_outfd(S->S);
}

/* split out into a parent_worker_event due to sharing processing with the
 * aftermath of calling shmif_block_synch_request */
static void on_shmif(struct ioloop_shared* S, bool ok)
{
	struct arcan_shmif_cont* C = S->cbt->C;
	struct arcan_event ev;
	int pv;

	while ((pv = arcan_shmif_poll(C, &ev)) > 0){
		parent_worker_event(S->S, C, &ev);
	}

/* Something is wrong with the parent connection, shutdown. This is a point
 * where we could go into crash recover and retain the a12 connection if we
 * wish. */
	if (pv == -1 || !ok){
		S->shutdown = true;
	}
}

/* We come in here after wait_for_activation is complete but don't have a good
 * mechanism for sending the actual key. Encode it as base64 in a regular message
 * with kpub=%s and wait for kpriv or fail. Re-keying doesn't need this as we
 * just generate new keys locally.
 */
static struct pk_response key_auth_worker(
	struct a12_state* S, uint8_t pk[static 32], void* tag)
{
	struct pk_response reply = {0};
	struct arcan_event req = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_MESSAGE
	};

/* package the pubk as base-64 in shmif-pack format, set the a12 key
 * as an indicator (blocked from other MESSAGE forwarding) and wait
 * for the two keys in return (or a fail). */
	size_t outl;
	unsigned char* b64 = a12helper_tob64(pk, 32, &outl);
	snprintf((char*)req.ext.message.data,
		COUNT_OF(req.ext.message.data), "a12:pubk=%s", b64);
	free(b64);

/* Can't do anything else before authentication so blocking here is fine.
 * the keys are larger than what fits in one message so we need to split,
 * one for session, one for pubk. */
	arcan_shmif_enqueue(&shmif_parent_process, &req);
	struct arcan_event rep;
	size_t count = 2;

	while (count && arcan_shmif_wait(&shmif_parent_process, &rep) > 0){
		if (rep.category != EVENT_TARGET || rep.tgt.kind != TARGET_COMMAND_MESSAGE){
			TRACE(
				"kind=auth:status=unexpected_event:message=%s",
				arcan_shmif_eventstr(&rep, NULL, 0)
			);
			continue;
		}

		struct arg_arr* stat = arg_unpack(rep.tgt.message);
		if (!stat){
			arg_cleanup(stat);
			TRACE("kind=auth:status=broken:message=%s", rep.tgt.message);
			break;
		}

		b64 = NULL;
		if (!arg_lookup(stat, "a12", 0, NULL)){
			arg_cleanup(stat);
			TRACE("kind=auth:status=broken:message=missing a12 key");
			break;
		}

		const char* inkey;
		if (arg_lookup(stat, "fail", 0, NULL)){
			TRACE("kind=auth:status=rejected");
			arg_cleanup(stat);
			break;
		}

		if (arg_lookup(stat, "pub", 0, &inkey)){
			a12helper_fromb64((uint8_t*) inkey, 32, reply.key_pub);
			count--;
		}
		else if (arg_lookup(stat, "ss", 0, &inkey)){
			a12helper_fromb64((uint8_t*) inkey, 32, reply.key_session);
			count--;
		}

		arg_cleanup(stat);
	}

/* keep the public key for join requests to a ctrl in order to give it
 * a salted identifier for persistence */
	if (count == 0){
		reply.authentic = true;
		memcpy(auth_pub_key, pk, 32);
	}

	reply.authentic = count == 0;

	return reply;
}

static bool dirsrv_req_open(struct a12_state* S,
		uint8_t ident_req[static 32],
		uint8_t mode,
		struct a12_dynreq* out, void* tag)
{
	struct directory_meta* cbt = tag;

	size_t outl;
	unsigned char* req_b64 = a12helper_tob64(ident_req, 32, &outl);
	if (!req_b64){
		a12int_trace(A12_TRACE_SYSTEM, "diropen:bad_pubk");
		return false;
	}

	a12int_trace(A12_TRACE_DIRECTORY, "diropen:req_pubk=%s", req_b64);

	arcan_event reqmsg = {
		.category = EVENT_EXTERNAL,
		.ext.kind = EVENT_EXTERNAL_MESSAGE
	};
	snprintf((char*)reqmsg.ext.message.data,
		COUNT_OF(reqmsg.ext.message.data),
			"a12:diropen:%spubk=%s", mode == 4 ? "tunnel:" : "", req_b64);
	free(req_b64);
	arcan_shmif_enqueue(cbt->C, &reqmsg);

	struct evqueue_entry* rep = malloc(sizeof(struct evqueue_entry));
	bool rv;

/* just fill-out the dynreq with our connection info. some of this, mainly the
 * shared secret, this is delivered as a message re-using the session shared
 * secret that was used in authentication. */
retry_block:
	if ((rv = dir_block_synch_request(cbt->C,
		reqmsg, rep,
		EVENT_EXTERNAL, EVENT_EXTERNAL_NETSTATE,
		EVENT_TARGET, TARGET_COMMAND_REQFAIL))){
		a12int_trace(A12_TRACE_DIRECTORY, "diropen:got_reply");

		rep = run_evqueue(cbt->S, cbt->C, rep);
		arcan_event repev = rep->ev;

/* if it's not the netstate we're looking for, try again */
		if (repev.ext.netstate.space == 5){
			drop_evqueue_item(rep);
			rep = malloc(sizeof(struct evqueue_entry));
			goto retry_block;
		}

		struct a12_dynreq rq = {
			.port = 6680,
			.proto = 1
		};

/* split out the port */
		if (repev.ext.netstate.port)
			rq.port = repev.ext.netstate.port;

		if (cbt->secret)
			snprintf(rq.authk, 12, "%s", cbt->secret);

		_Static_assert(sizeof(rq.host) == 46, "wrong host-length");

	/* if there is a tunnel pending (would arrive as a bchunkstate during
	 * block_synch_request) tag the proto accordingly and spawn our feeder with
	 * the src descriptor already being set in the thread. */
		if (pending_tunnel){
			a12int_trace(A12_TRACE_DIRECTORY, "diropen:tunnel_sink");
			rq.proto = 4;
			snprintf(rq.host, COUNT_OF(rq.host), "%d", pending_tunnel);
			*out = rq;
			pending_tunnel = 0;
			return rv;
		}

/* truncation intended */
		strncpy(rq.host, repev.ext.netstate.name, 45);
		*out = rq;
	}
	else {
		a12int_trace(A12_TRACE_DIRECTORY, "diropen:kind=rejected");
		rep = run_evqueue(cbt->S, cbt->C, rep);
	}

	drop_evqueue_item(rep);

	return rv;
}

void anet_directory_srv(
	struct a12_context_options* netopts, struct anet_dirsrv_opts opts, int fdin, int fdout)
{
/* Swap out authenticator for one that forwards pubkey to parent and waits for
 * the derived session key back. This also lets the parent process worker
 * tracking thread track pubkey identity for state store. */
	netopts->pk_lookup = key_auth_worker;
	struct anet_dirsrv_opts diropts = {};
	struct arg_arr* args;

	TRACE("notice=directory-ready:pid=%d", getpid());

	shmif_parent_process = arcan_shmif_open(SEGID_NETWORK_SERVER, shmifopen_flags, &args);

/* Not all arguments are passed via command-line */
	const char* val;
	if (arg_lookup(args, "rekey", 0, &val) && val){
		TRACE("notice=set_rekey:bytes=%s", val);
		netopts->rekey_bytes = strtoul(val, NULL, 10);
	}

	TRACE("notice=directory-parent-ok");

/* Now that we have the shmif context, all we should need is stdio and
   descriptor passing. The rest - keystore, state access, everything is done
   elsewhere.

   For meaningful access the attacker would have to get local code-exec,
   infoleak the shmpage, find a vuln in either the BCHUNKSTATE event handling
   code or the simplified use of shmif in the parent process with
   stdio/fdpassing level of syscalls.

	 This can be switched to minimalfd now post shmif refactor.
 */
	struct shmif_privsep_node* paths[] =
	{
		&(struct shmif_privsep_node){.path = "/tmp", .perm = "rwc"},
		NULL
	};
	arcan_shmif_privsep(&shmif_parent_process, SHMIF_PLEDGE_PREFIX ,paths, 0);/* */
	TRACE("notice=prisep-set");

/* Flush out the event loop before starting as that is likely to update our
 * list of active directory entries as well as configure our a12_ctx_opts. this
 * will also block until ACTIVATE is received due to the NOACTIVATE _open. */
	if (!wait_for_activation(netopts, &shmif_parent_process)){
		TRACE("error=control_channel");
		return;
	}

	TRACE("notice=activated");

/*
 * Complex paths can be disabled entirely at compile time to have a simple
 * isolated directory server without any runtime defaults, just state store,
 * rendezvous and source/sink hosting.
 */
#ifndef STATIC_DIRECTORY_SERVER
	netopts->allow_directory_link = true;
#endif

	struct a12_state* S = a12_server(netopts);
	a12_trace_tag(S, "dir_worker");
	active_client_state = S;
	if (pending_index)
		a12int_set_directory(S, pending_index);
	pending_index = NULL;

	struct directory_meta cbt = {
		.S = S
	};

	cbt.C = &shmif_parent_process;
	shmif_parent_process.user = &cbt;

	char* msg = NULL;
	if (!anet_authenticate(S, fdin, fdout, &msg)){
		a12int_trace(A12_TRACE_SYSTEM, "authentication failed: %s", msg);
	}
	else {
	}

	a12_set_bhandler(S, srv_bevent, &cbt);

	a12_set_destination_raw(S, 0,
		(struct a12_unpack_cfg){
			.directory_open = dirsrv_req_open,
			.tag = &cbt
		}, sizeof(struct a12_unpack_cfg)
	);

	struct ioloop_shared ioloop = {
		.S = S,
		.fdin = fdin,
		.fdout = fdout,
		.userfd = shmif_parent_process.epipe,
		.userfd2 = -1,
		.on_event = on_a12srv_event,
		.on_userfd = on_shmif,
		.on_userfd2 = on_bstream_out,
		.on_shmif = on_appl_shmif,
		.lock = PTHREAD_MUTEX_INITIALIZER,
		.cbt = &cbt,
	};

	ioloop_shared = &ioloop;

/* this will loop until client shutdown */
	anet_directory_ioloop(&ioloop);
	if (ioloop.shmif.addr){
		arcan_shmif_drop(&ioloop.shmif);
	}
	arcan_shmif_drop(&shmif_parent_process);
}

static struct appl_meta* find_identifier(struct appl_meta* base, unsigned id)
{
	while (base){
		if (base->identifier == id)
			return base;
		base = base->next;
	}
	return NULL;
}

static void pair_enqueue(
	struct a12_state* S, struct arcan_shmif_cont *C, struct arcan_event ev)
{
	struct evqueue_entry* rep = malloc(sizeof(struct evqueue_entry));

/* if this fails we are going to shutdown/exit soon enough anyway as the
 * parent connection has terminated for some reason */
	if (dir_block_synch_request(C, ev, rep,
		EVENT_EXTERNAL,
		EVENT_EXTERNAL_STREAMSTATUS,
		EVENT_EXTERNAL,
		EVENT_EXTERNAL_STREAMSTATUS)){
			rep = run_evqueue(S, C, rep);
			drop_evqueue_item(rep);
	}
	else
		drop_evqueue_item(rep);

	a12_channel_enqueue(S, &ev);
}

/* NOTES:
 * if M.identifier doesn't match,
 *    there is the option to create a new one (name?)
 *    or substitute dynamically
 *    or substitute statically
 */
static struct a12_bhandler_res srv_bevent(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag)
{
	struct a12_bhandler_res res = {
		.fd = -1,
		.flag = A12_BHANDLER_DONTWANT
	};

	struct directory_meta* cbt = tag;

/* if an appl identifier is specified, check that it match one we know about,
 * this mainly saves the roundtrip just to be rejected by the parent */
	if (M.identifier){
		struct appl_meta* meta = find_identifier(S->directory, M.identifier);

/* -1 is used to signify unallocated slot */
		if (!meta && M.identifier != (uint16_t) -1)
			return res;
	}

/* There might be transfers going that are 'uninteresting' i.e. we are sending
 * a file. For others, mainly uploads, there is a need to know the completion
 * status in order for other events and notifications to propagate. This is why
 * in_transfer and transfer_id are tracked. */
	switch (M.state){
	case A12_BHANDLER_COMPLETED:
		a12int_trace(
			A12_TRACE_DIRECTORY, "kind=status:completed:identifier=%"PRIu16, M.identifier);

/* Before sending the completion notification, make sure the server side has the
 * key that should match the contents of the transfer. No verification is done in
 * this process as we don't have the privilege for that */
		if (cbt->in_transfer && M.identifier == cbt->transfer_id){
			struct arcan_event skey = (struct arcan_event){
				.category = EVENT_EXTERNAL,
				.ext.kind = EVENT_EXTERNAL_MESSAGE
			};
			uint8_t signkey[32];
			a12_get_sign_pubkey(S, signkey);
			unsigned char* b64 = a12helper_tob64(signkey, 32, &(size_t){0});
			snprintf((char*)skey.ext.message.data,
				COUNT_OF(skey.ext.message.data), "a12:signkey=%s", b64);
			arcan_shmif_enqueue(cbt->C, &skey);

			struct arcan_event sack = (struct arcan_event){
				.category = EVENT_EXTERNAL,
				.ext.kind = EVENT_EXTERNAL_STREAMSTATUS,
				.ext.streamstat = {
					.completion = 1.0,
					.identifier = M.streamid
				}
			};

	/* for multiple queued items in the bstream could have an interleaving problem
	 * on the client side if multiple BCHUNKSTATEs are sent before a previous one has
	 * been completed or rejected, as the new one would overwrite the old one THEN we
	 * receive the first initialised binary channel on the segment OR multiple channels
	 * queueing transfers interleaved. Right now this isn't a concern as the arcan-net
	 * tooling does not, but when mapping this to Lua scripting space, this could
	 * be a footgun, but also solveable on the arcan-net layer. This is better as it
	 * keeps complexity away from here, which is a more exposed surface. */
			if (cbt->breq_pending.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE &&
					cbt->breq_pending.ext.bchunk.ns == M.identifier){
				a12int_trace(A12_TRACE_DIRECTORY,
					"kind=status:completed_pending:identifier=%"PRIu16, M.identifier);
				cbt->breq_pending = (struct arcan_event){0};
			}

/* with low enough latency and high enough server load this enqueue can be triggered
 * while the event is still in flight, and we shut down before the parent gets to ack
 * the update. */
			cbt->in_transfer = false;
			pair_enqueue(cbt->S, cbt->C, sack);
		}
	break;
	case A12_BHANDLER_CANCELLED:
		if (cbt->in_transfer && M.identifier == cbt->transfer_id){
			struct arcan_event sack = (struct arcan_event){
				.category = EVENT_EXTERNAL,
				.ext.kind = EVENT_EXTERNAL_STREAMSTATUS,
				.ext.streamstat = {
					.completion = -1,
					.identifier = M.streamid
				}
			};
			cbt->in_transfer = false;
			if (cbt->breq_pending.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE &&
					cbt->breq_pending.ext.bchunk.ns == M.identifier){
				cbt->breq_pending = (struct arcan_event){0};
			}

			a12int_trace(
				A12_TRACE_DIRECTORY, "kind=status:btransfer:cancelled_remote");
			pair_enqueue(cbt->S, cbt->C, sack);
		}
		else
			a12int_trace(
				A12_TRACE_DIRECTORY, "kind=error:btransfer:cancel_unknown");

	break;
	case A12_BHANDLER_INITIALIZE:
/* the easiest path now is to BCHUNKSTATE immediately for either the state,
 * crash or blobstore and wait for the parent to respond with a decriptor and
 * fail. This is a pipelineing stall for a few ms. */
		if (M.type == A12_BTYPE_STATE){
			res.fd = request_resource(S, cbt->C, M.identifier, ".state", BREQ_STORE);
			if (-1 != res.fd){
				cbt->in_transfer = true;
				cbt->transfer_id = M.identifier;
			}
		}
		else if (M.type == A12_BTYPE_CRASHDUMP){
			res.fd = request_resource(S, cbt->C, M.identifier, ".debug", BREQ_STORE);

			if (-1 != res.fd){
				cbt->in_transfer = true;
				cbt->transfer_id = M.identifier;
			}
		}

/* Client wants to upload a generic file. This MUST be preceeded by a
 * BCHUNKSTATE or we reject it outright. The original event is kept until
 * cancelled or completed. */
		else if (M.type == A12_BTYPE_BLOB){
			a12int_trace(
					A12_TRACE_DIRECTORY, "kind=status:btransfer:blob:id=%d:pending=%d",
					(int)M.identifier,
					cbt->breq_pending.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE
			);

			if (cbt->breq_pending.ext.kind == EVENT_EXTERNAL_BCHUNKSTATE &&
					cbt->breq_pending.ext.bchunk.ns == M.identifier){

/* If the client has joined an applgroup with a controller, it's the
 * responsibility of those scripts to map resources */
				res.fd = request_resource(S,
						ioloop_shared->shmif.addr ? &ioloop_shared->shmif : cbt->C,
						M.identifier,
						(char*) cbt->breq_pending.ext.bchunk.extensions, BREQ_STORE);

/*
 * Truncate the store, this is a rather crude workaround as we really want
 * to provide both an atomic swap on completion AND verification, and the
 * ability to start at an offset in order to provide resume- support.
 */
				if (-1 != res.fd){
					ftruncate(res.fd, 0);
					cbt->in_transfer = true;
					cbt->transfer_id = M.identifier;
					a12int_trace(A12_TRACE_DIRECTORY, "binary_transfer_initiated");
				}
				else
					a12int_trace(
						A12_TRACE_DIRECTORY, "kind=status:btransfer_rejected_parent");
			}
		}
/* the rest are default-reject that must be manually enabled for the server
 * as they provide incrementally dangerous capabilities (adding shared media
 * with piracy and content policy concerns, adding code running on client
 * devices to adding code running on plaintext client messaging). */
/* swap out, update or create a new */
#ifndef STATIC_DIRECTORY_SERVER
		else if (M.type == A12_BTYPE_APPL_RESOURCE){
		}
		else if (M.type == A12_BTYPE_APPL || M.type == A12_BTYPE_APPL_CONTROLLER){
			char* restype = M.type == A12_BTYPE_APPL ? ".appl" : ".ctrl";
			res.fd = request_resource(S, cbt->C, M.identifier, restype, BREQ_STORE);

			if (-1 != res.fd){
				cbt->in_transfer = true;
				cbt->transfer_id = M.identifier;
			}
		}
#endif
		break;
	}

	if (-1 != res.fd)
		res.flag = A12_BHANDLER_NEWFD;
	return res;
}
