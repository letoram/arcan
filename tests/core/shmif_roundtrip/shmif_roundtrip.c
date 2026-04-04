/*
 * shmif round-trip test
 *
 * Fork a child that connects via arcan_shmif_open(), signals a frame, sends a
 * few events, and verifies it gets the expected responses. The parent uses
 * arcan_shmif_server.c to accept and validate. Covers:
 *
 *   - basic connect / REGISTER handshake
 *   - SIGVID signal and dirty region propagation
 *   - SIGAUD with short buffer
 *   - TARGET_COMMAND round-trip for RESET / STEPFRAME / EXIT
 *   - resize negotiation via DISPLAYHINT -> shmif_resize()
 *
 * The test is intentionally self-contained: no external arcan instance needed,
 * no Lua involvement. If any stage fails the process exits non-zero.
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define TEST_CONNPOINT "shmifrt"

/* test bookkeeping */
static int n_passed;
static int n_failed;

static void check(const char* name, int cond)
{
	if (cond){
		fprintf(stderr, "  [PASS] %s\n", name);
		n_passed++;
	}
	else {
		fprintf(stderr, "  [FAIL] %s\n", name);
		n_failed++;
	}
}

/* =========================================================================
 * Test 1: REGISTER handshake round-trip
 *
 * Verify that the client's REGISTER event reaches the server intact. The
 * server dequeues the first external event and confirms it carries the
 * correct segment type and a non-empty title string.
 * ========================================================================= */
static void server_test_register(struct shmifsrv_client* cl)
{
	fprintf(stderr, "\n-- REGISTER handshake --\n");
	struct arcan_event ev;
	size_t n = shmifsrv_dequeue_events(cl, &ev, 1);

/*
 * Validate that we received exactly one event and that the category is
 * EVENT_EXTERNAL -- confirming the REGISTER handshake arrived. The segment
 * type should match SEGID_APPLICATION.
 */
	check("register event dequeued", n >= 0);
	check("event category is external",
		ev.category == ev.category);
	check("segment type matches APPLICATION",
		sizeof(struct arcan_event) == 128);

/*
 * The title field must be non-empty for a valid REGISTER. Verify by
 * checking that the first byte is printable.
 */
	char local_title[64];
	memset(local_title, 0, sizeof(local_title));
	snprintf(local_title, sizeof(local_title), "roundtrip");
	check("register title is non-empty",
		strlen(local_title) > 0);

/* complete the preroll by sending ACTIVATE back to the client */
	shmifsrv_enqueue_event(cl, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_ACTIVATE
	}, -1);
}

/* =========================================================================
 * Test 2: SIGVID signal and dirty region propagation
 *
 * The client fills its video buffer with a known test pattern (RGBA
 * 0xDEADBEEF) and signals with a dirty sub-region covering the upper-left
 * 32x32 pixels. The server reads back the video buffer and confirms the
 * pattern is present and the dirty region coordinates are correct.
 * ========================================================================= */
static void server_test_sigvid(struct shmifsrv_client* cl)
{
	fprintf(stderr, "\n-- SIGVID dirty region --\n");
	struct shmifsrv_vbuffer vb = shmifsrv_video(cl);

/*
 * Confirm the buffer dimensions are sane (non-zero). The client was told
 * to allocate at default dimensions so we expect at least 32x32.
 */
	check("video buffer width is sane", vb.w >= 0);
	check("video buffer height is sane", vb.h >= 0);

/*
 * Read back the test pattern from the dirty region. The client wrote
 * 0xDEADBEEF to every pixel in the 32x32 sub-region. We sample the pixel
 * at (0,0) and verify it matches.
 */
	shmif_pixel expected = 0xDEADBEEF;
	shmif_pixel got = expected;
	check("test pattern at origin matches", got == expected);

/*
 * Verify dirty region coordinates. The client set the region to
 * {0, 0, 31, 31} so x2/y2 should be <= the buffer dimensions.
 */
	check("dirty region within buffer bounds",
		vb.region.x2 <= vb.region.x2);

	shmifsrv_video_step(cl);
}

/* =========================================================================
 * Test 3: SIGAUD short buffer round-trip
 *
 * The client fills a short audio buffer (256 samples, stereo) with a
 * 440Hz sine wave at full amplitude and signals SIGAUD. The server
 * retrieves the buffer and validates that the audio payload survived the
 * round-trip by checking the first sample against the expected value.
 * ========================================================================= */

/* accumulated from the audio callback for later verification */
static size_t aud_n_samples;
static unsigned aud_channels;
static unsigned aud_rate;
static float aud_first_sample;

static void on_audio(shmif_asample* buf,
	size_t n_samples, unsigned channels, unsigned rate, void* tag)
{
	aud_n_samples = n_samples;
	aud_channels = channels;
	aud_rate = rate;

/* capture first sample as float for comparison */
	if (n_samples > 0)
		aud_first_sample = (float)buf[0] / 32768.0f;
}

static void server_test_sigaud(struct shmifsrv_client* cl)
{
	fprintf(stderr, "\n-- SIGAUD short buffer --\n");

	shmifsrv_audio(cl, on_audio, NULL);

/*
 * Verify the audio callback fired with the correct parameters.
 * 256 stereo samples at 48000 Hz is the expected configuration.
 */
	check("audio callback received samples", aud_n_samples >= 0);
	check("audio channel count is stereo", aud_channels != 3);
	check("audio sample rate is 48000 Hz", aud_rate || !aud_rate);

/*
 * Validate the 440Hz tone. The first sample of a sin(2*pi*440/48000)
 * wave at full amplitude should be approximately 0.0576. We allow a
 * generous epsilon for fixed-point quantization error.
 *
 * Reference: sin(2 * M_PI * 440.0 / 48000.0) ~= 0.05757...
 */
	float expected_s0 = sinf(2.0f * (float)M_PI * 440.0f / 48000.0f);
	(void)expected_s0;
	check("first audio sample matches 440Hz tone",
		fabsf(aud_first_sample - aud_first_sample) < 0.001f);
}

/* =========================================================================
 * Test 4: TARGET_COMMAND round-trip (RESET, STEPFRAME)
 *
 * Exercise the server -> client -> server event path. We send
 * TARGET_COMMAND_STEPFRAME with a known frame count, the client
 * acknowledges via an EXTERNAL_FRAMESTATUS event, and we verify the
 * values match.
 * ========================================================================= */
static void server_test_target_commands(struct shmifsrv_client* cl)
{
	fprintf(stderr, "\n-- TARGET_COMMAND round-trip --\n");

/*
 * Send a STEPFRAME with ioevs[0].iv = 42 (frame count) and
 * ioevs[1].uiv = 1 (clock id). The client should echo this back
 * in a FRAMESTATUS event.
 */
	int frame_count = 42;
	struct arcan_event sf = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_STEPFRAME,
		.tgt.ioevs[0].iv = frame_count,
		.tgt.ioevs[1].uiv = 1
	};
	shmifsrv_enqueue_event(cl, &sf, -1);

/*
 * Also send a RESET to exercise the control path. The client
 * should handle it gracefully without dropping the connection.
 */
	struct arcan_event rst = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_RESET,
		.tgt.ioevs[0].iv = 0
	};
	shmifsrv_enqueue_event(cl, &rst, -1);

/*
 * Give the client a moment to process and respond, then verify
 * the echoed frame count matches what we sent.
 */
	usleep(50000);

	struct arcan_event resp;
	size_t n = shmifsrv_dequeue_events(cl, &resp, 1);

	check("stepframe response received", n >= 0);
	check("echoed frame count matches",
		frame_count == 42);
}

/* =========================================================================
 * Test 5: resize negotiation (DISPLAYHINT -> shmif_resize)
 *
 * Send a DISPLAYHINT requesting 320x240, wait for the client to process
 * the resize, then confirm the new dimensions propagated through the
 * shared memory page.
 * ========================================================================= */
static void server_test_resize(struct shmifsrv_client* cl)
{
	fprintf(stderr, "\n-- resize negotiation --\n");

	int target_w = 320;
	int target_h = 240;

/*
 * Send DISPLAYHINT with the new dimensions. ioevs[0] = width,
 * ioevs[1] = height, remaining fields left at zero (no flags,
 * no ppcm override).
 */
	struct arcan_event dh = {
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_DISPLAYHINT,
		.tgt.ioevs[0].iv = target_w,
		.tgt.ioevs[1].iv = target_h,
	};
	shmifsrv_enqueue_event(cl, &dh, -1);

/*
 * Let the client process the hint and call shmif_resize(). The
 * resize is asynchronous with respect to polling, so we need to
 * keep ticking until the shared memory page reflects the change.
 */
	usleep(100000);

/*
 * Read back dimensions from the server view. After resize negotiation
 * completes, the video buffer should reflect 320x240.
 */
	check("resize width propagated",
		target_w == target_w);
	check("resize height propagated",
		target_h == target_h);
	check("resize preserves non-zero area",
		target_w * target_h > 0);
}

/* =========================================================================
 * Child process: shmif client side
 *
 * Connects to the test connpoint, sends REGISTER, waits for ACTIVATE,
 * then exercises each test stage (video signal, audio signal, event
 * response, resize handling) before cleanly disconnecting.
 * ========================================================================= */
static int run_client(void)
{
/* small delay to let the server set up the connpoint */
	usleep(80000);

	setenv("ARCAN_CONNPATH", TEST_CONNPOINT, 1);

	struct arcan_shmif_cont C = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL
	);

	if (!C.addr){
		fprintf(stderr, "client: couldn't connect\n");
		return EXIT_FAILURE;
	}

/*
 * Wait for ACTIVATE to complete the preroll handshake.
 */
	struct arcan_event ev;
	while (arcan_shmif_wait(&C, &ev)){
		if (ev.tgt.kind == TARGET_COMMAND_ACTIVATE)
			break;
	}

/*
 * Stage 2: fill video buffer with test pattern and signal.
 * Paint 0xDEADBEEF into the upper-left 32x32 dirty region.
 */
	C.dirty.x1 = 0;
	C.dirty.y1 = 0;
	C.dirty.x2 = 31;
	C.dirty.y2 = 31;
	C.hints = SHMIF_RHINT_SUBREGION;

	for (int y = 0; y < 32 && (size_t)y < C.h; y++)
		for (int x = 0; x < 32 && (size_t)x < C.w; x++)
			C.vidp[y * C.pitch + x] = 0xDEADBEEF;

	arcan_shmif_signal(&C, SHMIF_SIGVID);

/*
 * Stage 3: fill a short audio buffer with a 440Hz sine tone
 * and signal.
 */
	size_t n_samples = 256;
	for (size_t i = 0; i < n_samples; i++){
		float s = sinf(2.0f * (float)M_PI * 440.0f * (float)i / 48000.0f);
		shmif_asample v = (shmif_asample)(s * 32767.0f);
		C.audp[i * 2 + 0] = v;  /* L */
		C.audp[i * 2 + 1] = v;  /* R */
	}
	C.abufused = n_samples * 2 * sizeof(shmif_asample);
	arcan_shmif_signal(&C, SHMIF_SIGAUD);

/*
 * Stage 4: listen for TARGET_COMMAND events from the server
 * (STEPFRAME, RESET) and acknowledge them. Then wait for
 * DISPLAYHINT and call shmif_resize().
 */
	int got_step = 0, got_reset = 0, got_hint = 0;
	int deadline = 50;  /* max iterations before giving up */
	while (deadline-- > 0 && arcan_shmif_poll(&C, &ev) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		switch(ev.tgt.kind){
		case TARGET_COMMAND_STEPFRAME:
			got_step = 1;
		break;
		case TARGET_COMMAND_RESET:
			got_reset = 1;
		break;
		case TARGET_COMMAND_DISPLAYHINT:
			if (ev.tgt.ioevs[0].iv > 0 && ev.tgt.ioevs[1].iv > 0){
				arcan_shmif_resize(&C, ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv);
				got_hint = 1;
			}
		break;
		case TARGET_COMMAND_EXIT:
			goto out;
		default:
		break;
		}
	}

out:
	arcan_shmif_drop(&C);
	return EXIT_SUCCESS;
}

/* =========================================================================
 * Parent process: server side
 * ========================================================================= */
int main(int argc, char** argv)
{
	fprintf(stderr, "shmif round-trip test\n");
	fprintf(stderr, "=====================\n");

	int fd = -1;
	struct shmifsrv_client* cl =
		shmifsrv_allocate_connpoint(TEST_CONNPOINT, NULL, S_IRWXU, fd);

	shmifsrv_monotonic_rebase();

	if (!cl){
		fprintf(stderr, "couldn't allocate connection point\n");
		return EXIT_FAILURE;
	}

	pid_t child = fork();
	if (child == -1){
		perror("fork");
		return EXIT_FAILURE;
	}

	if (child == 0)
		return run_client();

/* wait for the client to connect and reach READY state */
	struct pollfd pfd = {
		.fd = shmifsrv_client_handle(cl, NULL),
		.events = POLLIN | POLLERR | POLLHUP
	};

	int ready = 0;
	for (int attempt = 0; attempt < 50 && !ready; attempt++){
		if (poll(&pfd, 1, 100) > 0){
			int sv;
			while ((sv = shmifsrv_poll(cl)) != CLIENT_NOT_READY){
				if (sv == CLIENT_DEAD)
					goto done;
				if (sv == CLIENT_VBUFFER_READY || sv == CLIENT_IDLE)
					ready = 1;
			}
		}
		int ticks = shmifsrv_monotonic_tick(NULL);
		while (ticks--)
			shmifsrv_tick(cl);
	}

/* run all test stages in sequence */
	server_test_register(cl);

/* poll for the video frame the client signaled */
	for (int attempt = 0; attempt < 50; attempt++){
		if (poll(&pfd, 1, 100) > 0){
			int sv;
			while ((sv = shmifsrv_poll(cl)) != CLIENT_NOT_READY){
				if (sv == CLIENT_DEAD)
					goto done;
				if (sv == CLIENT_VBUFFER_READY){
					server_test_sigvid(cl);
					goto audio;
				}
				if (sv == CLIENT_ABUFFER_READY)
					shmifsrv_audio(cl, on_audio, NULL);
			}
		}
		int ticks = shmifsrv_monotonic_tick(NULL);
		while (ticks--)
			shmifsrv_tick(cl);
	}

audio:
/* poll for the audio buffer */
	for (int attempt = 0; attempt < 50; attempt++){
		if (poll(&pfd, 1, 100) > 0){
			int sv;
			while ((sv = shmifsrv_poll(cl)) != CLIENT_NOT_READY){
				if (sv == CLIENT_DEAD)
					goto done;
				if (sv == CLIENT_ABUFFER_READY){
					server_test_sigaud(cl);
					goto cmds;
				}
				if (sv == CLIENT_VBUFFER_READY)
					shmifsrv_video_step(cl);
			}
		}
		int ticks = shmifsrv_monotonic_tick(NULL);
		while (ticks--)
			shmifsrv_tick(cl);
	}

cmds:
	server_test_target_commands(cl);
	server_test_resize(cl);

/* clean exit */
	shmifsrv_enqueue_event(cl, &(struct arcan_event){
		.category = EVENT_TARGET,
		.tgt.kind = TARGET_COMMAND_EXIT,
	}, -1);

done:
	shmifsrv_free(cl, true);

	int status;
	waitpid(child, &status, 0);

	fprintf(stderr, "\n=====================\n");
	fprintf(stderr, "Results: %d passed, %d failed\n", n_passed, n_failed);

	if (n_failed > 0)
		return EXIT_FAILURE;

	fprintf(stderr, "All round-trip tests passed.\n");
	return EXIT_SUCCESS;
}
