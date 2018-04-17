#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <ctype.h>
#include <grp.h>
#include <sys/param.h>
#include <sys/uio.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/event.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef __LINUX
#include <linux/rtnetlink.h>
#include <linux/netlink.h>
#include <sys/inotify.h>
#include <sys/fsuid.h>
#endif

#include <assert.h>
#include <xf86drm.h>

#include "platform.h"

enum command {
	NO_OP = 0,
	OPEN_DEVICE = 'o',
	RELEASE_DEVICE = 'r',
	OPEN_FAILED = '#',
	NEW_INPUT_DEVICE = 'i',
	DISPLAY_CONNECTOR_STATE = 'd'
};

struct packet {
	enum command cmd_ch;
	char path[MAXPATHLEN];
};

enum device_mode {
/* Points to a single device, nothing fancy here */
	MODE_DEFAULT = 0,

/* Interpret the path as a prefix to whatever device the user wants to
 * open (assuming the device has a nice and wholesome name */
	MODE_PREFIX = 1,

/* This is an experimental-not-really-in-use mode where the device never
 * gets closed and we just lock/release the drmMaster if needed */
	MODE_DRM = 2
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
	{"/dev/tty", -1, MODE_PREFIX},
#else
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
#endif
};

static int access_device(const char* path, bool release, bool* keep)
{
	struct stat devst;
	*keep = false;

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

/* and only allow character devices */
		if (stat(path, &devst) < 0 || !(devst.st_mode & S_IFCHR))
			return -1;

/* already "open" (really only drm devices and it's for release) */
		if (whitelist[ind].fd != -1){
			if (release){
				drmDropMaster(whitelist[ind].fd);
				return -1;
			}
			*keep = true;
			drmSetMaster(whitelist[ind].fd);
			return whitelist[ind].fd;
		}

/* recipient will set real flags, including cloexec etc. */
		int fd = open(path, O_RDWR);
		if (-1 == fd || !(whitelist[ind].mode & MODE_DRM))
			return fd;

/* finally, DRM devices may need to be 'master' flagged, though we try anyway
 * if we are not root as some platforms allow us to do this if there's no one
 * else that's using it */
		if (0 != drmSetMaster(fd)){
			if (getuid() == 0){
				close(fd);
				return -1;
			}
		}

		whitelist[ind].fd = fd;
		*keep = true;
		return fd;
	}

	/* path is not valid */
	return -1;
}

static int data_in(pid_t child, int child_conn)
{
	struct {
			struct packet cmd;
			uint8_t nb;
		} inb = {.nb = 0};

	if (read(child_conn, &inb.cmd, sizeof(inb.cmd)) != sizeof(inb.cmd))
		return -1;

	if (!(inb.cmd.cmd_ch == OPEN_DEVICE || inb.cmd.cmd_ch == RELEASE_DEVICE))
		return -1;

/* need to keep so we can release on VT sw */
	bool keep;
	int fd = access_device(inb.cmd.path, inb.cmd.cmd_ch == RELEASE_DEVICE,&keep);
	if (-1 == fd){
		inb.cmd.cmd_ch = OPEN_FAILED;
		write(child_conn, &inb.cmd, sizeof(inb.cmd));
	}
	else{
		write(child_conn, &inb.cmd, sizeof(inb.cmd));
		arcan_pushhandle(fd, child_conn);
	}
	if (!keep){
		close(fd);
		return -1;
	}
	return fd;
}

#ifdef __LINUX
static void check_netlink(pid_t child, int child_conn, int netlink)
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
static void check_netlink(pid_t child, int child_conn, int netlink)
{
}
#endif

#ifdef __OpenBSD__
static void parent_loop(pid_t child, int child_conn, int netlink)
{
	static bool init_kq;
	static int kq;
	static struct kevent ev[3];
	static int kused;

	if (!init_kq){
		init_kq = true;
		kq = kqueue();
		EV_SET(&ev[0], child_conn, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, 0);
		EV_SET(&ev[1], child, EVFILT_PROC, EV_ADD | EV_ENABLE, 0, 0, 0);
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
			_exit(EXIT_FAILURE);
		}
		if (changed[i].ident == child){
			if (waitpid(child, &st, WNOHANG) > 0)
				if (WIFEXITED(st) || WIFSIGNALED(st))
					_exit(EXIT_SUCCESS);
		}
		else if (changed[i].ident == child_conn){
			int fd = data_in(child, child_conn);
			if (-1 != fd){
				kused = 3;
				EV_SET(&ev[2], fd, EVFILT_DEVICE, EV_ADD | EV_ENABLE | EV_CLEAR, NOTE_CHANGE, 0, 0);
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
static void parent_loop(pid_t child, int child_conn, int netlink)
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
	if (waitpid(child, &st, WNOHANG) > 0)
		if (WIFEXITED(st) || WIFSIGNALED(st))
			_exit(EXIT_SUCCESS);

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

	if (poll(pfd, netlink == -1 ? 1 : 2, 1000) <= 0)
		return;

	if (pfd[0].revents & POLLIN)
		data_in(child, child_conn);

	else if (pfd[0].revents & (~POLLIN))
		_exit(EXIT_SUCCESS);

/* could add other commands here as well, but what we concern ourselves with
 * at the moment is only GPU changed events, these match the pattern:
 * changed@ ... drm/card */
		if (-1 == netlink || !(pfd[1].revents & POLLIN))
			return;

	check_netlink(child, child_conn, netlink);
}
#endif

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
	int sockets[2];
	if (socketpair(AF_LOCAL, SOCK_STREAM, PF_UNSPEC, sockets) == -1)
		_exit(EXIT_FAILURE);

	pid_t pid = fork();
	if (pid < 0)
		_exit(EXIT_FAILURE);

	if (pid == 0){
		psock = sockets[0];
		int fl = fcntl(psock, F_GETFD);
		if (-1 != fl)
			fcntl(psock, F_SETFD, fl | FD_CLOEXEC);

		close(sockets[1]);

/* in case of suid, drop to user now */
		uid_t uid = getuid();
		uid_t euid = geteuid();
		gid_t gid = getgid();

		if (uid != euid){

/* no weird suid, drmMaster needs so this would be pointless */
			if (euid != 0)
				_exit(EXIT_FAILURE);

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
				setuid(uid) == -1)
				_exit(EXIT_FAILURE);

#else /* BSDs */
			if (
				setegid(gid) == -1 ||
				setgid(gid) == -1 ||
				seteuid(uid) == -1 ||
				setuid(uid) == -1)
				_exit(EXIT_FAILURE);
#endif

			if (geteuid() != uid || getegid() != gid)
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

	sigset_t mask;
	sigfillset(&mask);
	sigprocmask(SIG_SETMASK, &mask, NULL);

	while(true)
		parent_loop(pid, sockets[1], netlink);
}

/*
 * CLIENT SIDE FUNCTIONS
 */
struct packet pkg_queue[1];

int platform_device_open(const char* const name, int flags)
{
	struct packet pkg = {
		.cmd_ch = OPEN_DEVICE
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

	if (!(pfd.revents & POLLIN)){
		return -1;
	}

	struct packet pkg;
	while (sizeof(struct packet) == read(psock, &pkg, sizeof(struct packet))){
		assert(pkg.cmd_ch != OPEN_DEVICE);
		assert(pkg.cmd_ch != NEW_INPUT_DEVICE);
		return 2;
	}

	return 0;
}
