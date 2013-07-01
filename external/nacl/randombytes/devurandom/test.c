#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

/* it's really stupid that there isn't a syscall for this */

static int fd = -1;

void randombytes(unsigned char *x,unsigned long long xlen)
{
  int i;

  if (fd == -1) {
    for (;;) {
      fd = open("/dev/urandom",O_RDONLY);
      if (fd != -1) break;
      sleep(1);
    }
  }

  while (xlen > 0) {
    if (xlen < 1048576) i = xlen; else i = 1048576;

    i = read(fd,x,i);
    if (i < 1) {
      sleep(1);
      continue;
    }

    x += i;
    xlen -= i;
  }
}
#include "randombytes-impl.h"

unsigned char x[65536];
unsigned long long freq[256];

int main()
{
  unsigned long long i;

  randombytes(x,sizeof x);
  for (i = 0;i < 256;++i) freq[i] = 0;
  for (i = 0;i < sizeof x;++i) ++freq[255 & (int) x[i]];
  for (i = 0;i < 256;++i) if (!freq[i]) return 111;
  return 0;
}
