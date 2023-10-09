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

static struct arcan_shmif_cont shmif_parent_process;
static struct a12_state* active_client_state;
static struct appl_meta* pending_index;

static void do_event(
	struct a12_state* S, struct arcan_shmif_cont* C, struct arcan_event* ev);

static int request_parent_resource(
	struct a12_state* S, struct arcan_shmif_cont *C, const char* id, bool out);

struct evqueue_entry;
struct evqueue_entry {
	struct arcan_event ev;
	struct evqueue_entry* next;
};

static void free_evqueue(struct evqueue_entry* first)
{
	struct evqueue_entry* cur = first;
	while (cur){
		struct evqueue_entry* last = cur;
		cur = cur->next;
		free(last);
	}
}

static struct evqueue_entry* run_evqueue(
	struct a12_state* S, struct arcan_shmif_cont* C, struct evqueue_entry* rep)
{
	while (rep->next){
		do_event(S, C, &rep->ev);
		if (arcan_shmif_descrevent(&rep->ev) && rep->ev.tgt.ioevs[0].iv > 0)
			close(rep->ev.tgt.ioevs[0].iv);
		rep = rep->next;
	}
	return rep;
}

/*
 * this only works due to our special relationship to the server side (us):
 *  send ev, wait for [kind] as a return and queue any messages.
 *  if other events start being used those would need to be queued as well.
 *
 *  the last entry in the reply->next->... chain is the actual response.
 *  return false on failure, meaning the context is in an invalid state and
 *  we should terminate.
 *
 * the utility is for synchronous requests to state store, key store etc.
 */
static bool shmif_block_synch_request(struct arcan_shmif_cont* C,
	struct arcan_event ev, struct evqueue_entry* reply, int kind_ok, int kind_fail)
{
	*reply = (struct evqueue_entry){0};
	arcan_shmif_enqueue(C, &ev);

	while (arcan_shmif_wait(C, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == kind_ok || ev.tgt.kind == kind_fail){
			reply->ev = ev;
			reply->next = NULL;
			return true;
		}

/* need to dup to queue descriptor-events as they are closed() on next call
 * into arcan_shmif_xxx. This assumes we can't get queued enough fdevents that
 * we would saturate our fd allocation */
		if (arcan_shmif_descrevent(&ev)){
			ev.tgt.ioevs[0].iv = arcan_shmif_dupfd(ev.tgt.ioevs[0].iv, -1, true);
		}

		reply->ev = ev;
		reply->next = malloc(sizeof(struct arcan_event));
		*(reply->next) = (struct evqueue_entry){0};
		reply = reply->next;
	}

	return false;
}

static struct a12_bhandler_res srv_bevent(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag);

/* cont is actually wrong here as we haven't set a context for the channel
 * since it's not being used in the normal fashion - the actual connection
 * to the coordinating process is through the [tag] that is also a context */
static void on_srv_event(
	struct arcan_shmif_cont* cont, int chid, struct arcan_event* ev, void* tag)
{
	struct ioloop_shared* I = tag;
	struct directory_meta* cbt = I->cbt;
	struct arcan_shmif_cont* C = cbt->C;

	if (ev->ext.kind == EVENT_EXTERNAL_BCHUNKSTATE){
/* sweep the directory, and when found: */
		if (!isdigit(ev->ext.bchunk.extensions[0])){
			a12int_trace(A12_TRACE_DIRECTORY, "event=bchunkstate:error=invalid_id");
			return;
		}

/* automatically probe .state as well */
		uint16_t extid = (uint16_t)
			strtoul((char*)ev->ext.bchunk.extensions, NULL, 10);

		int fd = request_parent_resource(
			cbt->S, C, (char*) ev->ext.bchunk.extensions, false);

/* if the appl exist, first try the state blob, then the appl */
		if (fd != -1){
			char buf[COUNT_OF(ev->ext.message.data)];
			char empty_ext[16] = {0};

			snprintf(buf, sizeof(buf), "%d.state", (int) extid);
			int state_fd = request_parent_resource(cbt->S, C, buf, false);
			if (state_fd != -1){
				a12_enqueue_bstream(cbt->S,
					state_fd, A12_BTYPE_STATE, extid, false, 0, empty_ext);
				close(state_fd);
			}
			a12_enqueue_bstream(cbt->S,
				fd, A12_BTYPE_BLOB, extid, false, 0, empty_ext);
			close(fd);
		}
		else
			a12_channel_enqueue(cbt->S,
				&(struct arcan_event){
					.category = EVENT_TARGET,
					.tgt.kind = TARGET_COMMAND_REQFAIL,
					.tgt.ioevs[0].uiv = extid
			});
	}
/* Actual identity will be determined by the parent to make sure we don't have
 * any collisions or name changes after the first REGISTER. It will also tag
 * with the Kpub we have. */
	else if (ev->ext.kind == EVENT_EXTERNAL_REGISTER &&
		a12_remote_mode(cbt->S) == ROLE_SOURCE){
		arcan_event disc = {
			.category = EVENT_EXTERNAL,
			.ext.kind = EVENT_EXTERNAL_NETSTATE,
			.ext.netstate = {
				.type = ROLE_SOURCE,
				.space = 5
			}
		};

/* truncate the identifier */
		snprintf(disc.ext.netstate.name, 16, "%s", ev->ext.registr.title);
		a12int_trace(A12_TRACE_DIRECTORY,
			"source_register=%s", disc.ext.netstate.name);
		arcan_shmif_enqueue(C, &disc);
	}
}

static void unpack_index(
	struct a12_state *S, struct arcan_shmif_cont *C, struct arcan_event* ev)
{
	a12int_trace(A12_TRACE_DIRECTORY, "new_index");
	FILE* fpek = fdopen(ev->tgt.ioevs[0].iv, "r");
	if (!fpek){
		a12int_trace(A12_TRACE_DIRECTORY, "error=einval_fd");
		return;
	}

	struct appl_meta* first = NULL;
	struct appl_meta** cur = &first;

	while (!feof(fpek)){
		char line[256];
		size_t n = 0;

/* the .index is trusted, but to ease troubleshooting there is some light basic
 * validation to help if the format is updated / extended */
		char* res = fgets(line, sizeof(line), fpek);
		if (!res)
			continue;

		n++;
		struct arg_arr* entry = arg_unpack(line);
		if (!entry){
			a12int_trace(A12_TRACE_DIRECTORY, "error=malformed_entry:index=%zu", n);
			continue;
		}

		const char* kind;
		if (!arg_lookup(entry, "kind", 0, &kind) || !kind){
			a12int_trace(A12_TRACE_DIRECTORY, "error=malformed_entry:index=%zu", n);
			arg_cleanup(entry);
			continue;
		}

/* We re-use the same a12int_ interface for the directory entries for marking a
 * source or directory entry, just with a different type identifier so that the
 * implementation knows to package the update correctly. Actual integrity of the
 * directory is guaranteed by the parent process. Avoiding collisions and so on
 * is done in the parent, as is enforcing permissions. */
		const char* name = NULL;
		arg_lookup(entry, "name", 0, &name);

		*cur = malloc(sizeof(struct appl_meta));
		**cur = (struct appl_meta){0};
		snprintf((*cur)->appl.name, 18, "%s", name);

		const char* tmp;
		if (arg_lookup(entry, "categories", 0, &tmp) && tmp)
			(*cur)->categories = (uint16_t) strtoul(tmp, NULL, 10);

		if (arg_lookup(entry, "size", 0, &tmp) && tmp)
			(*cur)->buf_sz = (uint32_t) strtoul(tmp, NULL, 10);

		if (arg_lookup(entry, "id", 0, &tmp) && tmp)
			(*cur)->identifier = (uint16_t) strtoul(tmp, NULL, 10);

		if (arg_lookup(entry, "hash", 0, &tmp) && tmp){
			union {
				uint32_t val;
				uint8_t u8[4];
			} dst;

			dst.val = strtoul(tmp, NULL, 16);
			memcpy((*cur)->hash, dst.u8, 4);
		}

		if (arg_lookup(entry, "timestamp", 0, &tmp) && tmp){
			(*cur)->update_ts = (uint64_t) strtoull(tmp, NULL, 10);
		}

		cur = &(*cur)->next;
		arg_cleanup(entry);
	}

	fclose(fpek);
	if (!S)
		pending_index = first;
	else
		a12int_set_directory(S, first);
}

/* S, cbt isn't guaranteed here if it happens during the activation stage */
static void bchunk_event(struct a12_state *S,
	struct directory_meta* cbt, struct arcan_shmif_cont *C, struct arcan_event* ev)
{
/* the index is packed as shmif argstrs line-separated */
	if (strcmp(ev->tgt.message, ".index") == 0){
		unpack_index(S, C, ev);
	}
}

static bool wait_for_activation(
	struct a12_context_options* aopt, struct arcan_shmif_cont* C)
{
	struct directory_meta* cbt = C->user;
	struct arcan_event ev;

	while (arcan_shmif_wait(C, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_BCHUNK_IN){
			bchunk_event(NULL, cbt, C, &ev);
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

		a12int_trace(A12_TRACE_DIRECTORY,
			"event:kind=%s", arcan_shmif_eventstr(&ev, NULL, 0));
	}

	return false;
}

static void do_event(
	struct a12_state* S, struct arcan_shmif_cont* C, struct arcan_event* ev)
{
	struct directory_meta* cbt = C->user;

/* parent process responsible for verifying and tagging name with petname:kpub */
	if (ev->category == EVENT_EXTERNAL &&
		ev->ext.kind == EVENT_EXTERNAL_NETSTATE){
		size_t i = 0;

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

		a12int_notify_dynamic_resource(S,
			ev->ext.netstate.name, (uint8_t*)&ev->ext.netstate.name[i],
			ev->ext.netstate.type, ev->ext.netstate.type != 0
		);
	}

	if (ev->category != EVENT_TARGET)
		return;

	if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_IN){
		bchunk_event(S, cbt, C, ev);
	}
	else if (ev->tgt.kind == TARGET_COMMAND_MESSAGE){
		struct arg_arr* stat = arg_unpack(ev->tgt.message);

/* Would only be sent to us if the parent a. thinks we're in a specific APPL
 * via IDENT b. the ruleset tells us to message. Inject into a12_state
 * verbatim. THe parent would also need to ensure that the client can't inject
 * the a12: tag into the MESSAGE or we have a weird form of 'Packets in
 * Packets'. */
		if (!stat || !arg_lookup(stat, "a12", 0, NULL)){
			a12_channel_enqueue(S, ev);
			if (stat)
				arg_cleanup(stat);
			return;
		}

/* reserved for other messages */
		arg_cleanup(stat);
	}
}

/* split out into a do_event due to sharing processing with the aftermath
 * of calling shmif_block_synch_request */
static void on_shmif(struct ioloop_shared* S, bool ok)
{
	struct arcan_shmif_cont* C = S->cbt->C;
	struct arcan_event ev;

	while (arcan_shmif_poll(C, &ev) > 0){
		do_event(S->S, C, &ev);
	}
}

/* We come in here after wait_for_activation is complete but don't have a good
 * mechanism for sending the actual key. Encode it as base64 in a regular message
 * with kpub=%s and wait for kpriv or fail. Re-keying doesn't need this as we
 * just generate new keys locally.
 */
static struct pk_response key_auth_worker(uint8_t pk[static 32])
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
			a12int_trace(
				A12_TRACE_DIRECTORY,
				"kind=auth:status=unexpected_event:message=%s",
				arcan_shmif_eventstr(&rep, NULL, 0)
			);
			continue;
		}

		struct arg_arr* stat = arg_unpack(rep.tgt.message);
		if (!stat){
			arg_cleanup(stat);
			a12int_trace(
				A12_TRACE_DIRECTORY,
				"kind=auth:status=broken:message=%s", rep.tgt.message);
			break;
		}

		b64 = NULL;
		if (!arg_lookup(stat, "a12", 0, NULL)){
			arg_cleanup(stat);
			a12int_trace(
				A12_TRACE_DIRECTORY,
				"kind=auth:status=broken:message=missing a12 key");
			break;
		}

		const char* inkey;
		if (arg_lookup(stat, "fail", 0, NULL)){
			a12int_trace(A12_TRACE_DIRECTORY, "kind=auth:status=rejected");
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
	reply.authentic = count == 0;

	return reply;
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
	a12int_trace(A12_TRACE_DIRECTORY, "notice:directory-ready:pid=%d", getpid());

	shmif_parent_process =
		arcan_shmif_open(
			SEGID_NETWORK_SERVER,
			SHMIF_ACQUIRE_FATALFAIL |
			SHMIF_NOACTIVATE |
			SHMIF_DISABLE_GUARD |
			SHMIF_NOREGISTER,
			&args
		);

/* Now that we have the shmif context, all we need is stdio and descriptor
	 passing. The rest - keystore, state access, everything is done elsewhere.

	 For meaningful access the attacker would have to get local code-exec,
	 infoleak the shmpage, find a vuln in either the BCHUNKSTATE event handling
	 code or the simplified use of shmif in the parent process with
	 stdio/fdpassing level of syscalls.
*/
	struct shmif_privsep_node* paths[] = {NULL};
	arcan_shmif_privsep(&shmif_parent_process, "minimalfd", paths, 0);

/* Flush out the event loop before starting as that is likely to update our
 * list of active directory entries as well as configure our a12_ctx_opts. this
 * will also block until ACTIVATE is received due to the NOACTIVATE _open. */
	if (!wait_for_activation(netopts, &shmif_parent_process)){
		a12int_trace(A12_TRACE_DIRECTORY, "error=control_channel");
		return;
	}
	struct a12_state* S = a12_server(netopts);
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

	struct ioloop_shared ioloop = {
		.S = S,
		.fdin = fdin,
		.fdout = fdout,
		.userfd = shmif_parent_process.epipe,
		.on_event = on_srv_event,
		.on_userfd = on_shmif,
		.lock = PTHREAD_MUTEX_INITIALIZER,
		.cbt = &cbt,
	};

/* this will loop until client shutdown */
	anet_directory_ioloop(&ioloop);
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

static int request_parent_resource(
	struct a12_state* S, struct arcan_shmif_cont *C, const char* id, bool out)
{
	struct evqueue_entry* rep = malloc(sizeof(struct evqueue_entry));
	struct arcan_event ev = (struct arcan_event){
		.ext.kind = EVENT_EXTERNAL_BCHUNKSTATE
	};

	int kind;
	if (out){
		kind = TARGET_COMMAND_BCHUNK_OUT; /* we want something to output into */
		ev.ext.bchunk.input = false;
	}
	else {
		kind = TARGET_COMMAND_BCHUNK_IN; /* we want input from .. */
		ev.ext.bchunk.input = true;
	}

	snprintf((char*)ev.ext.bchunk.extensions, COUNT_OF(ev.ext.bchunk.extensions), "%s", id);
	int fd = -1;
	a12int_trace(A12_TRACE_DIRECTORY, "request_parent:%s", ev.ext.bchunk.extensions);

	if (shmif_block_synch_request(C, ev, rep, kind, TARGET_COMMAND_REQFAIL)){
		struct evqueue_entry* cur = run_evqueue(S, C, rep);

		if (cur->ev.tgt.kind == kind){
			fd = arcan_shmif_dupfd(cur->ev.tgt.ioevs[0].iv, -1, true);
			a12int_trace(A12_TRACE_DIRECTORY, "accepted");
		}
		else
			a12int_trace(A12_TRACE_DIRECTORY, "rejected");
	}

	free_evqueue(rep);
	return fd;
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
	struct appl_meta* meta = find_identifier(S->directory, M.identifier);

/* the one case where it is permitted to use a non-identifier to reference a
 * server-side resource is for appl-push */
	if (!meta)
		return res;

/* There might be transfers going that are 'uninteresting' i.e. we are sending
 * a file. For others, mainly uploads, there is a need to know the completion
 * status in order for other events and notifications to propagate. This is why
 * in_transfer and transfer_id are tracked. */
	switch (M.state){
	case A12_BHANDLER_COMPLETED:
		a12int_trace(
			A12_TRACE_DIRECTORY, "kind=status:completed:identifier=%"PRIu16, M.identifier);
		if (cbt->in_transfer && M.identifier == cbt->transfer_id){
			cbt->in_transfer = false;
			arcan_shmif_enqueue(cbt->C,
					&(struct arcan_event){
						.category = EVENT_EXTERNAL,
						.ext.kind = EVENT_EXTERNAL_STREAMSTATUS,
						.ext.streamstat = {
							.completion = 1.0,
							.identifier = M.identifier
						}
					}
				);
		}
	break;
	case A12_BHANDLER_CANCELLED:
		if (cbt->in_transfer && M.identifier == cbt->transfer_id){
			cbt->in_transfer = false;
			arcan_shmif_enqueue(cbt->C,
				&(struct arcan_event){
					.category = EVENT_EXTERNAL,
					.ext.kind = EVENT_EXTERNAL_STREAMSTATUS,
					.ext.streamstat = {
						.completion = -1,
						.identifier = M.identifier
					}
				}
			);
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
			char buf[5 + sizeof(".state")];
			snprintf(buf, sizeof(buf), "%"PRIu16".state", M.identifier);
			res.fd = request_parent_resource(S, cbt->C, buf, true);
			if (-1 != res.fd){
				cbt->in_transfer = true;
				cbt->transfer_id = M.identifier;
			}
		}
		else if (M.type == A12_BTYPE_CRASHDUMP){
			char buf[5 + sizeof(".debug")];
			snprintf(buf, sizeof(buf), "%"PRIu16".debug", M.identifier);
			res.fd = request_parent_resource(S, cbt->C, buf, true);
		}
/* blob is (currently) not used for anything, a possibility would be form
 * like uploads for the server end of the appl to be able to process. That
 * can be hooked up when the [controller] slot has been filled and the
 * client explicitly join appl participation via IDENT. */
		else if (M.type == A12_BTYPE_BLOB){
		}
/* the rest are default-reject that must be manually enabled for the server
 * as they provide incrementally dangerous capabilities (adding shared media
 * with piracy and content policy concerns, adding code running on client
 * devices to adding code running on plaintext client messaging). */
/* swap out, update or create a new */
#ifndef STATIC_DIRECTORY_SERVER
		else if (M.type == A12_BTYPE_APPL_RESOURCE){
		}
		else if (M.type == A12_BTYPE_APPL){
			char buf[16 + sizeof(".appl")];

/* We treat update (existing identifier) different to add-new. It doesn't have
 * any special semantics right now, but is relevant if two clients has a
 * different world-view, i.e. one-added another updated without the change
 * having propagated. The use cases are slightly different as someone might be
 * using the existing and need to synch / migrate in the case of update. */
			if (M.extid[0])
				snprintf(buf, sizeof(buf), "%s.appl", M.extid);
			else
				snprintf(buf, sizeof(buf), "%"PRIu32".appl", M.identifier);

			res.fd = request_parent_resource(S, cbt->C, buf, true);
			if (-1 != res.fd){
				cbt->in_transfer = true;
				cbt->transfer_id = M.extid[0] ? 65535 : M.identifier;
			}
		}
		else if (M.type == A12_BTYPE_APPL_CONTROLLER){
		}
#endif
		break;
	}

	if (-1 != res.fd)
		res.flag = A12_BHANDLER_NEWFD;
	return res;
}
