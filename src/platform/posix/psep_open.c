/*
 * Copyright 2018, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: https://arcan-fe.com
 * Description: platform_open implementation that takes the option of
 * privilege separation into account.
 */
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <ctype.h>
#include <grp.h>
#include <sys/param.h>
#include <sys/ioctl.h>
#include <sys/uio.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__OpenBSD__) || defined(__FreeBSD__)
#include <sys/event.h>
/* wsdisplay_usl_io? */
#if defined(__FreeBSD__)
#include <termios.h>
#include <sys/consio.h>
#include <sys/kbio.h>
struct termios termios_tty;
#endif
#endif

#ifdef __LINUX
#include <linux/rtnetlink.h>
#include <linux/netlink.h>
#include <sys/inotify.h>
#include <sys/fsuid.h>
#include <linux/kd.h>
#include <linux/input.h>
#include <linux/vt.h>
#include <linux/major.h>
#endif

#include <assert.h>
#include <xf86drm.h>

#include "platform.h"

#ifndef KDSKBMUTE
#define KDSKBMUTE 0x4851
#endif

static int child_conn = -1;

enum command {
	NO_OP = 0,
	OPEN_DEVICE = 'o',
	RELEASE_DEVICE = 'r',
	OPEN_FAILED = '#',
	NEW_INPUT_DEVICE = 'i',
	DISPLAY_CONNECTOR_STATE = 'd',
	SYSTEM_STATE_RELEASE = '1',
	SYSTEM_STATE_ACQUIRE = '2',
	SYSTEM_STATE_TERMINATE = '3',
};

struct packet {
	enum command cmd_ch;
	int arg;
	char path[MAXPATHLEN];
};

enum device_mode {
/* Points to a single device, nothing fancy here */
	MODE_DEFAULT = 0,

/* Interpret the path as a prefix to whatever device the user wants to
 * open (assuming the device has a nice and wholesome name */
	MODE_PREFIX = 1,

/* This is an experimental-not-really-in-use mode where the device never
 * gets closed and we just lock/release the drmMaster if needed. */
	MODE_DRM = 2,

/* For tty devices, we track those that are opened and restore their state
 * when shutting down so that we don't risk leaving a broken tty. */
	MODE_TTY = 4,
};

struct whitelist {
	const char* const name;
	int fd;
	enum device_mode mode;
};

/*
 * Something of a hard choice here, the default setup for /dev/input do not
 * enforce exclusive access, meaning that other users with permissions on the
 * device can potentially access them. This includes another instance of arcan,
 * which is actually what we want in cases where we have multiple instances
 * sharing the same input. On the other hand, you can then spawn an arcan
 * instance with an appl that dumps the input events and there you go.
 */
struct whitelist whitelist[] = {
#ifdef __LINUX
	{"/dev/input/", -1, MODE_PREFIX},
	{"/dev/dri/card0", -1, MODE_DRM},
	{"/dev/dri/card1", -1, MODE_DRM},
	{"/dev/dri/card2", -1, MODE_DRM},
	{"/dev/dri/card3", -1, MODE_DRM},
	{"/dev/dri/", -1, MODE_PREFIX},
	{"/sys/class/backlight/", -1, MODE_PREFIX},
	{"/sys/class/tty/", -1, MODE_PREFIX},
/* we need better patterns to deal with this one but it
 * is needed for backlight controls as backlight resolves here */
	{"/sys/devices/", -1, MODE_PREFIX},
	{"/dev/tty", -1, MODE_PREFIX | MODE_TTY},
#elif defined(__OpenBSD__)
	{"/dev/wsmouse", -1, MODE_DEFAULT},
	{"/dev/wsmouse0", -1, MODE_DEFAULT},
	{"/dev/wsmouse1", -1, MODE_DEFAULT},
	{"/dev/wsmouse2", -1, MODE_DEFAULT},
	{"/dev/wsmouse3", -1, MODE_DEFAULT},
	{"/dev/uhid0", -1, MODE_DEFAULT},
	{"/dev/uhid1", -1, MODE_DEFAULT},
	{"/dev/uhid2", -1, MODE_DEFAULT},
	{"/dev/uhid3", -1, MODE_DEFAULT},
	{"/dev/tty00", -1, MODE_DEFAULT},
	{"/dev/tty01", -1, MODE_DEFAULT},
	{"/dev/tty02", -1, MODE_DEFAULT},
	{"/dev/tty03", -1, MODE_DEFAULT},
	{"/dev/tty04", -1, MODE_DEFAULT},
	{"/dev/ttya", -1, MODE_DEFAULT},
	{"/dev/ttyb", -1, MODE_DEFAULT},
	{"/dev/ttyc", -1, MODE_DEFAULT},
	{"/dev/ttyd", -1, MODE_DEFAULT},
	{"/dev/wskbd", -1, MODE_DEFAULT},
	{"/dev/wskbd0", -1, MODE_DEFAULT},
	{"/dev/wskbd1", -1, MODE_DEFAULT},
	{"/dev/wskbd2", -1, MODE_DEFAULT},
	{"/dev/wskbd3", -1, MODE_DEFAULT},
	{"/dev/ttyC0", -1, MODE_DEFAULT},
	{"/dev/ttyC1", -1, MODE_DEFAULT},
	{"/dev/ttyC2", -1, MODE_DEFAULT},
	{"/dev/ttyC3", -1, MODE_DEFAULT},
	{"/dev/ttyC4", -1, MODE_DEFAULT},
	{"/dev/ttyC5", -1, MODE_DEFAULT},
	{"/dev/ttyC6", -1, MODE_DEFAULT},
	{"/dev/ttyC7", -1, MODE_DEFAULT},
	{"/dev/ttyD0", -1, MODE_DEFAULT},
	{"/dev/ttyE0", -1, MODE_DEFAULT},
	{"/dev/ttyF0", -1, MODE_DEFAULT},
	{"/dev/ttyG0", -1, MODE_DEFAULT},
	{"/dev/ttyH0", -1, MODE_DEFAULT},
	{"/dev/ttyI0", -1, MODE_DEFAULT},
	{"/dev/ttyJ0", -1, MODE_DEFAULT},
	{"/dev/pci", -1, MODE_DEFAULT},
	{"/dev/drm0", -1, MODE_DRM},
	{"/dev/drm1", -1, MODE_DRM},
	{"/dev/drm2", -1, MODE_DRM},
	{"/dev/drm3", -1, MODE_DRM},
	{"/dev/amdmsr", -1, MODE_DEFAULT}
#elif defined(__FreeBSD__)
	{"/dev/input/", -1, MODE_PREFIX},
	{"/dev/sysmouse", -1, MODE_DEFAULT},
	{"/dev/dri/card0", -1, MODE_DRM},
	{"/dev/dri/card1", -1, MODE_DRM},
	{"/dev/dri/card2", -1, MODE_DRM},
	{"/dev/dri/card3", -1, MODE_DRM},
	{"/dev/dri/card4", -1, MODE_DRM}
#else
	fatal_posix_psep_open_but_no_ostable
#endif
};

/*
 * All of the following (set/release tty, signal handlers etc) is to manage the
 * meta-modeset that is done on tty devices in addition to the normal modeset
 * to get control of graphics.
 *
 * The sequence is:
 *  a. privsep-child requests a device that is flagged as TTY, the first such
 *  request saves the current state of the device. We don't do the probing
 *  for a tty here as it is somewhat OS dependent and the client config
 *  might specify a different tty device to be used. These are needed when
 *  jumping in from something else than the normal CLI TTY, so a pty from
 *  a shell or script.
 *
 *  b. after the state is saved, we disable local keyboard input (or all input
 *  done in the UI will potentially be mirrored inside the TTY) and register
 *  three signal handlers. TERM, USR1 and USR2. All these just forward the
 *  type of the signal to the child.
 *
 *  c. when the user presses [some combination] that should indicate a tty-sw,
 *  it 'reopens' the tty device with an argument of the indicated number to
 *  switch to. The VT_ACTIVATE ioctl is used on the tty, telling the kernel
 *  that we want to switch.
 *
 *  d. the kernel sends a signal to release, which we forward to the client.
 *  the client, when in a safe state(!) will read this, release as much
 *  resources as possible and send a release on the tty device. the client
 *  goes into a sleep-loop, waiting for a signal that it can resume.
 *
 *  e. the release gets mapped to a corresponding VT_RELDISP which should
 *  prompt the kernel to allow the next TTY to take over.
 *
 *  f. the acquire signal gets forwarded, the client wakes from its loop,
 *  re-opens its terminal device and rebuilds its GPU state, while we send
 *  and ACKACQ to the tty that we have resumed control over the TTY.
 */
static struct {
	bool active;
	unsigned long kbmode;
	int mode;
	int leds;
	int ind;
} got_tty;

/*
 * Next time client reaches video poll state, it will find these, switch to
	 * the relevant state and mark a release of the related tty device
 */
static void sigusr_acq(int sign, siginfo_t* info, void* ctx)
{
	if (-1 == write(child_conn,
		&(struct packet){.cmd_ch = SYSTEM_STATE_ACQUIRE}, sizeof(struct packet))){}
}

static void sigusr_rel(int sign, siginfo_t* info, void* ctx)
{
	if (-1 == write(child_conn,
		&(struct packet){.cmd_ch = SYSTEM_STATE_RELEASE}, sizeof(struct packet))){}
}

static void sigusr_term(int sign)
{
	if (-1 == write(child_conn,
		&(struct packet){.cmd_ch = SYSTEM_STATE_TERMINATE}, sizeof(struct packet))){}
}

static void set_tty(int i)
{
#ifdef __LINUX
/* This will (hopefully) make the kernel try and initiate the switch
 * related signals, taking care of release / acquire sequence */
	int dfd = whitelist[got_tty.ind].fd;
	if (-1 == dfd)
		return;

	if (i >= 0){
		ioctl(dfd, VT_ACTIVATE, i);
		return;
	}

/* already setup, client just reopened the device for some reason */
	if (got_tty.active){
		ioctl(dfd, VT_ACTIVATE, VT_ACKACQ);
		return;
	}
	got_tty.active = true;

/* one subtle note here, the LED controller for the keyboard LEDs assume that
 * we can access that property via the evdev path, since even though we do have
 * access to the tty fd in the child process, we don't have permissions to ioctl */
	ioctl(dfd, KDGETMODE, &got_tty.mode);
	ioctl(dfd, KDGETLED, &got_tty.leds);
	ioctl(dfd, KDGKBMODE, &got_tty.kbmode);
	ioctl(dfd, KDSETLED, 0);
	ioctl(dfd, KDSKBMUTE, 1);
	ioctl(dfd, KDSKBMODE, K_OFF);
	ioctl(dfd, KDSETMODE, KD_GRAPHICS);
#endif

/* register signal handlers that forward the desired action to the client,
 * and set the tty to try and signal acquire/release when a VT switch is
 * supposed to occur */

	sigaction(SIGTERM, &(struct sigaction){
		.sa_handler = sigusr_term
		}, NULL
	);

	sigaction(SIGUSR1, &(struct sigaction){
		.sa_sigaction = sigusr_acq,
		.sa_flags = SA_SIGINFO
		}, NULL
	);

	sigaction(SIGUSR2, &(struct sigaction){
		.sa_sigaction = sigusr_rel,
		.sa_flags = SA_SIGINFO
		}, NULL
	);

#ifdef __LINUX
	ioctl(dfd, VT_SETMODE, &(struct vt_mode){
		.mode = VT_PROCESS,
		.acqsig = SIGUSR1,
		.relsig = SIGUSR2
	});
#endif

/* this is treated special and is actually not triggered as part of the
 * whitelist (though there might be reason to add it) as we get the tty
 * from STDIN directly */
#ifdef __FreeBSD__
	tcgetattr(STDIN_FILENO, &termios_tty);
	ioctl(i, VT_SETMODE, &(struct vt_mode){
		.mode = VT_PROCESS,
		.acqsig = SIGUSR1,
		.relsig = SIGUSR2
	});
#endif
}

static void release_device(int i, bool shutdown)
{
	if (whitelist[i].fd == -1)
		return;

	if (whitelist[i].mode & MODE_DRM){
		drmDropMaster(whitelist[i].fd);

/* if we have a saved KMS mode, we could try and restore */
		if (!shutdown)
			return;
	}

/* will always be released on shutdown, so use that to restore */
	if (whitelist[i].mode & MODE_TTY){
#ifdef __LINUX
		if (shutdown){
			ioctl(whitelist[i].fd, KDSKBMUTE, 0);
			ioctl(whitelist[i].fd, KDSETMODE, KD_TEXT);
			ioctl(whitelist[i].fd, KDSKBMODE,
				got_tty.kbmode == K_OFF ? K_XLATE : got_tty.kbmode);
			ioctl(whitelist[i].fd, KDSETLED, got_tty.leds);
			close(whitelist[i].fd);
			whitelist[i].fd = -1;
		}
		else{
			ioctl(whitelist[i].fd, VT_RELDISP, 1);
		}
#endif
	}
}

static void release_devices()
{
	for (size_t i = 0; i < COUNT_OF(whitelist); i++)
		release_device(i, true);

/* For FreeBSD, we use the STDIN_FILENO and assume it is the tty */
#ifdef __FreeBSD__
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &termios_tty);
	ioctl(STDIN_FILENO, KDSETMODE, KD_TEXT);
	ioctl(STDIN_FILENO, KDSKBMODE, K_XLATE);
#endif
}

static int access_device(const char* path, int arg, bool release, bool* keep)
{
	struct stat devst;
	*keep = false;

/* special case, substitute TTY for the active tty device (if known) */
	if (strcmp(path, "TTY") == 0){
		if (!got_tty.active)
			return -1;
		path = whitelist[got_tty.ind].name;
		if (release && arg >= 0){
			set_tty(arg);
		}
	}

/* safeguard check against a whitelist, this would require an attack path that
 * goes from code exec inside arcan which is mostly a game over for the user,
 * but no need to make it easier to escalate further */
	for (size_t ind = 0; ind < COUNT_OF(whitelist); ind++){
		if (whitelist[ind].mode & MODE_PREFIX){
			if (0 != strncmp(
				whitelist[ind].name, path, strlen(whitelist[ind].name)))
				continue;

/* dumb traversal safeguard, we only accept printable and no . */
			size_t len = strlen(path);
			for (size_t i = 0; i < len; i++)
				if (!(isprint(path[i])) || path[i] == '.')
					return -1;

		}
		else if (strcmp(whitelist[ind].name, path) != 0)
			continue;

/* only allow character devices, with the exception of linux sysfs paths */
		if (stat(path, &devst) < 0 ||
			(strncmp(path, "/sys", 4) != 0 && !(devst.st_mode & S_IFCHR)))
			return -1;

/* already "open" (drm devices and ttys) */
		if (whitelist[ind].fd != -1){
			if (release){
				release_device(ind, false);
				return -1;
			}
			*keep = true;
			if (whitelist[ind].mode & MODE_DRM){
				drmSetMaster(whitelist[ind].fd);
			}
			return whitelist[ind].fd;
		}

/* recipient will set real flags, including cloexec etc. */
		int fd = open(path, O_RDWR);
		if (-1 == fd){
			fd = open(path, O_RDONLY);
			if (-1 == fd){
				return -1;
			}
		}

		if (whitelist[ind].fd != -1)
			close(whitelist[ind].fd);

		if (whitelist[ind].mode & MODE_TTY){
			whitelist[ind].fd = fd;
			got_tty.ind = ind;
			set_tty(arg);
			*keep = true;
			return fd;
		}

		if (whitelist[ind].mode & MODE_DRM){
			drmSetMaster(fd);
			whitelist[ind].fd = fd;
			*keep = true;
			return fd;
		}

		return fd;
	}

	/* path is not valid */
	return -1;
}

static int data_in(pid_t child)
{
	struct packet cmd;

	if (read(child_conn, &cmd, sizeof(cmd)) != sizeof(cmd))
		return -1;

	if (!(cmd.cmd_ch == OPEN_DEVICE || cmd.cmd_ch == RELEASE_DEVICE))
		return -1;

/* need to keep so we can release on VT sw */
	bool keep;
	int fd = access_device(cmd.path, cmd.arg, cmd.cmd_ch == RELEASE_DEVICE, &keep);
	if (-1 == fd){
		cmd.cmd_ch = OPEN_FAILED;
		write(child_conn, &cmd, sizeof(cmd));
	}
	else{
		write(child_conn, &cmd, sizeof(cmd));
		arcan_pushhandle(fd, child_conn);
	}
	if (!keep){
		close(fd);
		return -1;
	}
	return fd;
}

#ifdef __LINUX
static void check_netlink(pid_t child, int netlink)
{
	char buf[8192];
	char cred[CMSG_SPACE(sizeof(struct ucred))];

	struct iovec iov = {
		.iov_base = buf,
		.iov_len = sizeof(buf)
	};

	struct msghdr msg = {
		.msg_iov = &iov,
		.msg_iovlen = 1,
		.msg_control = cred,
		.msg_controllen = sizeof(cred),
	};

/* someone could possibly(?) spoof this message, though the only thing it would
 * trigger is the rate limited rescan on the client side, which isn't even a
 * DoS, just make sure to not use this for anything else */
	ssize_t buflen = recvmsg(netlink, &msg, 0);
	if (buflen < 0 || (msg.msg_flags & MSG_TRUNC))
		return;

/* buf should now contain @/ and changed and drm */
	if (!strstr(buf, "change@"))
		return;

	if (!strstr(buf, "drm/card"))
		return;

/* now we can finally write the message */
	struct packet pkg = {
		.cmd_ch = DISPLAY_CONNECTOR_STATE
	};

	write(child_conn, &pkg, sizeof(pkg));
}
#else
static void check_netlink(pid_t child, int netlink)
{
}
#endif

static void check_child(pid_t child, bool die)
{
	int st;

/* child dead? */
	if (waitpid(child, &st, WNOHANG) > 0){
		if (WIFEXITED(st) || WIFSIGNALED(st)){
			die = true;
		}
	}
/* or we want the child to soft-die? */
	else if (die)
		kill(SIGTERM, child);

	if (die){
		release_devices();
		_exit(WEXITSTATUS(st));
	}
}

#if defined(__OpenBSD__) || defined(__FreeBSD__)
static void parent_loop(pid_t child, int netlink)
{
	static bool init_kq;
	static int kq;
	static struct kevent ev[3];
	static int kused;

	if (!init_kq){
		init_kq = true;
		kq = kqueue();
		EV_SET(&ev[0], child_conn, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, 0);
#ifdef __OpenBSD__
		EV_SET(&ev[1], child, EVFILT_PROC, EV_ADD | EV_ENABLE, 0, 0, 0);
#else
		EV_SET(&ev[1], child, EVFILT_PROC,
			EV_ADD | EV_ENABLE | EV_ONESHOT, NOTE_EXIT, 0, 0);
#endif
		kused = 2;
	}

	struct kevent changed[kused];
	memset(changed, '\0', sizeof(struct kevent) * kused);
	ssize_t nret;
	if ((nret = kevent(kq, ev, kused, changed, kused, NULL)) < 0){
		return;
	}

	for (size_t i = 0; i < nret; i++){
		int st;
		if (changed[i].flags & EV_ERROR){
			check_child(child, true);
		}
		if (changed[i].ident == child){
			check_child(child, false);
		}
		else if (changed[i].ident == child_conn){
			int fd = data_in(child);
			if (-1 != fd){
#ifdef __OpenBSD__
				kused = 3;
				EV_SET(&ev[2], fd, EVFILT_DEVICE, EV_ADD | EV_ENABLE | EV_CLEAR, NOTE_CHANGE, 0, 0);
#endif
			}
		}
		else {
			struct packet pkg = {
				.cmd_ch = DISPLAY_CONNECTOR_STATE
			};
			write(child_conn, &pkg, sizeof(pkg));
		}
	}
}

#else
static void parent_loop(pid_t child, int netlink)
{
/*
 * Should really refactor / move both the TTY management and the inotify
 * monitoring over here as well to simplify the evdev.c implementation
 * but more ground work first.
 */

/* here is a decent place to actually track the DRM devices that are open
 * and restore their scanout status so that we will not risk leaving a broken
 * tty. */
	int st;
	check_child(child, false);

	struct pollfd pfd[2] = {
		{
			.fd = child_conn,
			.events = POLLIN | POLLERR | POLLHUP | POLLNVAL
		},
		{
			.fd = netlink,
			.events = POLLIN | POLLERR | POLLHUP | POLLNVAL
		}
	};

	int rv = poll(pfd, netlink == -1 ? 1 : 2, 1000);
	if (-1 == rv && (errno != EAGAIN && errno != EINTR))
		check_child(child, true); /* don't to stronger than this */

	if (rv == 0)
		return;

	if (pfd[0].revents & ~POLLIN)
		check_child(child, true);

	if (pfd[0].revents & POLLIN)
		data_in(child);

/* could add other commands here as well, but what we concern ourselves with
 * at the moment is only GPU changed events, these match the pattern:
 * changed@ ... drm/card */
		if (-1 == netlink || !(pfd[1].revents & POLLIN))
			return;

	check_netlink(child, netlink);
}
#endif

static bool drop_privileges()
{
/* in case of suid, drop to user now */
	uid_t uid = getuid();
	uid_t euid = geteuid();
	gid_t gid = getgid();

	if (uid == euid)
		return true;

/* no weird suid, drmMaster needs so this would be pointless */
	if (euid != 0)
		return false;

	setsid();
/* ugly tradeof here, setting the supplementary groups to only the gid
 * would subtly break certain sudo configurations in terminals spawned
 * from the normal privileged process, the best?! thing we can do is
 * likely to filter out the egid out of the groups list and replace
 * with just the gid -- and yes setgroups is a linux/BSD extension */
	int ngroups = getgroups(0, NULL);
	gid_t groups[ngroups];
	gid_t egid = getegid();
	if (getgroups(ngroups, groups)){
		for (size_t i = 0; i < ngroups; i++){
			if (groups[i] == egid)
				groups[i] = gid;
		}
		setgroups(ngroups, groups);
	}

#ifdef __LINUX
/* more diligence would take the CAPABILITIES crapola into account as well */
	if (
		setegid(gid) == -1 ||
		setgid(gid) == -1 ||
		setfsgid(gid) == -1 ||
		setfsuid(uid) == -1 ||
		seteuid(uid) == -1 ||
		setuid(uid) == -1
	)
		return false;

#else /* BSDs */
	if (
		setegid(gid) == -1 ||
		setgid(gid) == -1 ||
		seteuid(uid) == -1 ||
		setuid(uid) == -1
	)
		return false;
#endif

	if (geteuid() != uid || getegid() != gid)
		return false;

	return true;
}

/*
 * PARENT SIDE FUNCTIONS, we split even if there is no root- state (i.e. a
 * system with user permissions on devices) in order to have the same interface
 * code for hotplug.
 *
 * Note that this is slightly hairy due to the fact that if we are root, we
 * can't be allowed to use the get_config class of functions tas they can
 * trivially be used to escalate. This affects evdev when it comes to the
 * 'scandir', which needs to be encoded into the device_list as well then.
 *
 * This is primarily a concern when building very custom systems where you
 * can presumably control uid/gid allocation better anyhow.
 */
static int psock = -1;
void platform_device_init()
{
/*
 * Nothing of this is needed if we need to chain into an arcan_lwa as
 * there is already an arcan instance running (or at least we think so)
 */
	if (getenv("ARCAN_CONNPATH")){
		drop_privileges();
		return;
	}

	int sockets[2];
	if (socketpair(AF_LOCAL, SOCK_STREAM, PF_UNSPEC, sockets) == -1)
		_exit(EXIT_FAILURE);

/*
 * The 'low-priv' side of arcan does this as well, but since we want to be
 * able to restore should that crash, we need to do something about that
 * here and before fork so we don't race.
 */
#ifdef __FreeBSD__
	set_tty(STDIN_FILENO);
#endif

	pid_t pid = fork();
	if (pid < 0)
		_exit(EXIT_FAILURE);

	if (pid == 0){
		psock = sockets[0];
		int fl = fcntl(psock, F_GETFD);
		if (-1 != fl)
			fcntl(psock, F_SETFD, fl | FD_CLOEXEC);

		arcan_process_title("device manager");

		close(sockets[1]);

		if (!drop_privileges()){
			_exit(EXIT_FAILURE);
		}

/* privsep child can have STDOUT/STDERR, but prevent it from cascading */
		int flags = fcntl(STDOUT_FILENO, F_GETFD);
		if (-1 != flags)
			fcntl(STDOUT_FILENO, F_SETFD, flags | FD_CLOEXEC);
		flags = fcntl(STDERR_FILENO, F_GETFD);
		if (-1 != flags)
			fcntl(STDERR_FILENO, F_SETFD, flags | FD_CLOEXEC);
		return;
	}

#ifdef __LINUX
/* bind netlink for display event detection */
	struct sockaddr_nl sa = {
		.nl_family = AF_NETLINK,
		.nl_groups = RTMGRP_LINK | RTMGRP_IPV4_IFADDR
	};
	int netlink = socket(AF_NETLINK, SOCK_RAW, NETLINK_KOBJECT_UEVENT);
	if (netlink >= 0){
		if (bind(netlink, (struct sockaddr*)&sa, sizeof(sa))){
			close(netlink);
			netlink = -1;
		}
	}

	close(sockets[0]);

#else
	int netlink = -1;
#endif

#ifdef __OpenBSD__
	if (-1 == pledge("stdio drm sendfd proc rpath wpath", NULL)){
		fprintf(stderr, "couldn't pledge\n");
		_exit(EXIT_FAILURE);
	}
#endif

	int sigset[] = {
		SIGHUP, SIGINT, SIGQUIT, SIGILL, SIGABRT, SIGFPE,
		SIGPIPE, SIGALRM, SIGTERM, SIGUSR1, SIGUSR2, SIGCHLD,
		SIGCONT, SIGSTOP, SIGTSTP, SIGTTIN, SIGTTOU};
	for (size_t i = 0; i < COUNT_OF(sigset); i++)
		sigaction(sigset[i], &(struct sigaction){.sa_handler = SIG_IGN}, NULL);
	child_conn = sockets[1];

	while(true){
		parent_loop(pid, netlink);
	}
}

/*
 * CLIENT SIDE FUNCTIONS
 */
struct packet pkg_queue[1];

void platform_device_release(const char* const name, int ind)
{
	struct packet pkg = {
		.cmd_ch = RELEASE_DEVICE,
		.arg = ind
	};

	snprintf(pkg.path, sizeof(pkg.path), "%s", name);
	write(psock, &pkg, sizeof(pkg));
}

int platform_device_open(const char* const name, int flags)
{
	struct packet pkg = {
		.cmd_ch = OPEN_DEVICE,
		.arg = -1
	};

	snprintf(pkg.path, sizeof(pkg.path), "%s", name);
	if (-1 == write(psock, &pkg, sizeof(pkg)))
		return -1;

	while (sizeof(struct packet) == read(psock, &pkg, sizeof(struct packet))){
/* there might be other command events that we need to respect as there can be
 * both explicit open requests and implicit open requests depending on what
 * kind of device manager that is running on the other side, so we need to
 * queue here */
		if (pkg.cmd_ch == OPEN_FAILED)
			return -1;

		else if (pkg.cmd_ch == OPEN_DEVICE){
			int fd = arcan_fetchhandle(psock, true);
			if (-1 == fd)
				return -1;
			fcntl(fd, F_SETFD, FD_CLOEXEC);
			fcntl(fd, F_SETFL, flags);
			return fd;
		}

		else if (pkg.cmd_ch == DISPLAY_CONNECTOR_STATE)
			pkg_queue[0] = pkg;

		assert(pkg.cmd_ch != NEW_INPUT_DEVICE);
	}
/*
 * When we move the inotify- behavior from evdev additional care needs to
 * be taken here to handle the input device discovery part as the devices
 * received needs to be queued until the engine is in a state to handle
 * them.
 */

	return 0;
}

int platform_device_pollfd()
{
	return psock;
}

int platform_device_poll(char** identifier)
{
	if (pkg_queue[0].cmd_ch == DISPLAY_CONNECTOR_STATE){
		pkg_queue[0] = (struct packet){};
		return 2;
	}

	struct pollfd pfd = {.fd = psock,
		.events = POLLIN | POLLERR | POLLHUP | POLLNVAL};

	if (poll(&pfd, 1, 0) <= 0)
		return 0;

	if ((pfd.revents & ~POLLIN)){
		return -1;
	}

/* translate from the visible command format to the internal one */
	struct packet pkg;
	while (sizeof(struct packet) == read(psock, &pkg, sizeof(struct packet))){
		switch(pkg.cmd_ch){
		case NEW_INPUT_DEVICE:
/* not properly handled right now as we have other hotplug mechanisms in place
 * via inotify in the evdev layer, the problem is that we need to cache new
 * input names until we get a call where there's an identifier provided */
		break;
		case DISPLAY_CONNECTOR_STATE:
			return 2;
		break;
		case SYSTEM_STATE_RELEASE:
			return 3;
		break;
		case SYSTEM_STATE_ACQUIRE:
			return 4;
		break;
		case SYSTEM_STATE_TERMINATE:
			return 5;
		break;
		default:
			return 0;
		break;
		}
	}

	return 0;
}
