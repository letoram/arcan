/*
 * Rather rough timing wise still, otherwise the big ticket item would be to
 * see if dmabuf could be added to v4l2-loopback,and support YUV* class
 * formats.
 *
 * We don't have control over setting up the node (need modprobe and root),
 * unless v4l2loopback_ctl_add is a possibility (requires /dev/v4l2loopback)
 *
 * Until then, some consumers (chrome) need announce_all_caps and a label
 */
#include <arcan_shmif.h>
#include <linux/videodev2.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>

extern void arcan_timesleep(unsigned long);
static int try_device(struct arcan_shmif_cont* C, int number, struct v4l2_format* fmt)
{
	char buf[sizeof("could not open /dev/videoNNN")];
	snprintf(buf, sizeof(buf), "/dev/video%d", number % 1000);
	int dev = open(buf, O_RDWR);

	if (-1 == dev){
		char msg[sizeof("could not open /dev/videoNNN")];
		snprintf(msg, sizeof(msg), "could not open %s", buf);
		arcan_shmif_last_words(C, msg);
		return -1;
	}

	*fmt = (struct v4l2_format){
		.type = V4L2_BUF_TYPE_VIDEO_OUTPUT
	};
	if (-1 == ioctl(dev, VIDIOC_G_FMT, fmt)){
		char msg[sizeof("probe failed on videoNNN")];
		snprintf(msg, sizeof(msg), "probe failed on %s", buf);
		arcan_shmif_last_words(C, msg);
		return -1;
	}

	arcan_shmif_last_words(C, "");
	return dev;
}

static void flush(int fd,
	uint8_t* outb, size_t outb_sz, struct arcan_shmif_cont* cont)
{
	size_t ofs = 0;
	size_t ntw = outb_sz;

	while (ntw){
		ssize_t nw = write(fd, &outb[ofs], ntw);
		if (-1 == write(fd, outb, outb_sz)){
			arcan_shmif_last_words(cont, "v4l-device rejected frame");
			arcan_shmif_drop(cont);
			exit(EXIT_FAILURE);
		}
		ntw -= nw;
		ofs += nw;
	}
}

static void repack_rgb24(int dfd, uint8_t* dst, struct arcan_shmif_cont* cont)
{
	size_t ofs = 0;

	for (size_t y = 0; y < cont->h; y++){
		shmif_pixel* vidp = &cont->vidp[y * cont->pitch];
		for (size_t x = 0; x < cont->w; x++){
			uint8_t r, g, b, a;
			SHMIF_RGBA_DECOMP(vidp[x], &r, &g, &b, &a);
			dst[ofs++] = r;
			dst[ofs++] = g;
			dst[ofs++] = b;
		}
	}

	if (-1 != dfd){
		flush(dfd, dst, ofs, cont);
	}
}

static void repack_bgr24(int dfd, uint8_t* dst, struct arcan_shmif_cont* cont)
{
	size_t ofs = 0;

	for (size_t y = 0; y < cont->h; y++){
		shmif_pixel* vidp = &cont->vidp[y * cont->pitch];
		for (size_t x = 0; x < cont->w; x++){
			uint8_t r, g, b, a;
			SHMIF_RGBA_DECOMP(vidp[x], &r, &g, &b, &a);
			dst[ofs++] = b;
			dst[ofs++] = g;
			dst[ofs++] = r;
		}
	}

	if (-1 != dfd)
		flush(dfd, dst, ofs, cont);
}

int v4l2_run(struct arg_arr* args, struct arcan_shmif_cont cont)
{
	int devno = 0;
	float fps = 60.0;

	struct v4l2_format fmt = {
		.type = V4L2_BUF_TYPE_VIDEO_OUTPUT
	};

/* sweep until there are no more video devices */
	if (devno < 0){
		devno = 0;
		for(;;){
			char buf[sizeof("/dev/videoNNN")];
			struct stat inf;
			snprintf(buf, sizeof(buf), "/dev/video%d", devno);
			if (stat(buf, &inf) != -1){
				if ((devno = try_device(&cont, devno++, &fmt)) != -1)
					break;
			}	else {
				arcan_shmif_last_words(&cont, "no v4l2-loopback device found");
				arcan_shmif_drop(&cont);
				return EXIT_FAILURE;
			}
		}
	}
	else {
		if (-1 == (devno = try_device(&cont, devno, &fmt))){
			arcan_shmif_drop(&cont);
			return EXIT_FAILURE;
		}
	}

	fmt.fmt.pix.width = cont.w;
	fmt.fmt.pix.height = cont.h;
	fmt.fmt.pix.field = V4L2_FIELD_NONE;
	fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_RGB24;
	fmt.fmt.pix.colorspace = V4L2_COLORSPACE_SRGB;
	fmt.fmt.pix.sizeimage = cont.w * cont.h * 3;
	fmt.fmt.pix.bytesperline = cont.w * 3;

	void (*repack_fun)(int dfd, uint8_t*, struct arcan_shmif_cont*) = repack_rgb24;

	const char* kind = NULL;
	if (arg_lookup(args, "format", 0, &kind) && kind){
/* there are a lot of formats that should/could have representation here, and
 * since we have a dependency on swscale already that should be easy but
 * swscale is not happy about unaligned src/dst while v4l2-loopback seem to
 * have a lot of trouble with padding or planar representations it gets much
 * less fun fast. */
/* if strcmp(kind, "nv12") == 0){} */
/* needed as some consumers have endianness issues */
		if (strcmp(kind, "bgr") == 0){
			repack_fun = repack_bgr24;
		}
		else if (strcmp(kind, "rgb") == 0){
		}
		else {
			arcan_shmif_last_words(&cont, "unknown format arg");
			arcan_shmif_drop(&cont);
			return EXIT_FAILURE;
		}
	}

	if (arg_lookup(args, "fps", 0, &kind) && kind){
		fps = (float) strtoul(kind, NULL, 10);
		fps = fps < 1.0 || fps > 1000.0 ? 25.0 : fps;
	}

	bool mmapped = true;
	if (arg_lookup(args, "fdout", 0, &kind) && kind){
		mmapped = false;
	}

	if (-1 == ioctl(devno, VIDIOC_S_FMT, &fmt)){
		arcan_shmif_last_words(&cont, "v4l2-device rejected format");
		arcan_shmif_drop(&cont);
		return EXIT_FAILURE;
	}

	size_t bufcount = 2;
	struct v4l2_requestbuffers breq = {
		.count = bufcount,
		.type = V4L2_BUF_TYPE_VIDEO_OUTPUT,
		.memory = V4L2_MEMORY_MMAP
	};
	struct v4l2_buffer buffers[bufcount];
	uint8_t* outb[bufcount];

	if (mmapped){
/* buffers just rejected outright? fallback to writing */
		if (-1 == ioctl(devno, VIDIOC_REQBUFS, &breq)){
			mmapped = false;
		}
		else {
/* might be a way to squeeze in dmabuf here */
			bufcount = breq.count;
			for (size_t i = 0; i < bufcount; i++){
				buffers[i].index = i;
				buffers[i].type = breq.type;
				buffers[i].memory = breq.memory;
				if (-1 == ioctl(devno, VIDIOC_QUERYBUF, &buffers[i])){
					arcan_shmif_last_words(&cont, "buffer request rejected");
					arcan_shmif_drop(&cont);
					return EXIT_FAILURE;
				}
				outb[i] = mmap(NULL, buffers[i].length,
					PROT_WRITE, MAP_SHARED, devno, buffers[i].m.offset);
				if (outb[i] == MAP_FAILED){
					arcan_shmif_last_words(&cont, "mapping buffer failed");
					arcan_shmif_drop(&cont);
					return EXIT_FAILURE;
				}
			}
		}
	}

	if (!mmapped){
		outb[0] = malloc(fmt.fmt.pix.sizeimage);
		memset(outb[0], '\0', fmt.fmt.pix.sizeimage);
	}
	if (!outb[0]){
		arcan_shmif_last_words(&cont, "repack buffer alloc failed");
		arcan_shmif_drop(&cont);
		return EXIT_FAILURE;
	}

	uint64_t last = arcan_timemillis();
	bool first = true;
	size_t bufind = 0;

	struct arcan_event ev;
	while (arcan_shmif_wait(&cont, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;

		switch(ev.tgt.kind){
		case TARGET_COMMAND_STEPFRAME:{

/* the timing here is poor, still waiting for explicit fencing to be wired
 * throughout, and for shmif to respect our desired pts and try to set enc
 * based on that */
			while(!cont.addr->vready){}
			int64_t elapsed = arcan_timemillis() - last;
			last = arcan_timemillis();
			int64_t step = 0.8 * (1.0 / (float)fps * 1000.0);
			step -= elapsed;

			if (step > 0)
				arcan_timesleep(step);

/* both mmap and repack code does mostly the same work, with mmap disabled
 * we need to chunk into a number of write calls which is rather poor */
			if (mmapped){
				struct v4l2_buffer deq = {
					.type = V4L2_BUF_TYPE_VIDEO_OUTPUT,
					.memory = V4L2_MEMORY_MMAP
				};

				repack_fun(-1, outb[bufind], &cont);
				ioctl(devno, VIDIOC_QBUF, &buffers[bufind]);
				if (first){
					ioctl(devno, VIDIOC_STREAMON, &fmt.type);
					first = false;
				}
				if (-1 == ioctl(devno, VIDIOC_DQBUF, &deq)){
					arcan_shmif_last_words(&cont, "dequeue buffer failed");
					arcan_shmif_drop(&cont);
					return EXIT_FAILURE;
				}
				else
					bufind = deq.index;
			}
			else {
				repack_fun(devno, outb[0], &cont);
			}
			cont.addr->vready = false;
		}
		default:
		break;
		}
	}

	close(devno);
	arcan_shmif_last_words(&cont, NULL);
	arcan_shmif_drop(&cont);
	return EXIT_SUCCESS;
}
