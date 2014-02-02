/*
 * Failed attempt at a workaround for some of the issues
 * experienced with sem_timedwait before reverting to
 * guardthread + sem_wait and wakeup set
 */

int arcan_sem_timedwait_ks(sem_handle semaphore, 
	int msecs, volatile int8_t* ks)
{
	static int8_t broken_timedwait;
	static struct timespec ts = {
		.tv_sec = 0,
		.tv_nsec = 1000000000
	};

	return sem_trywait(semaphore);

	while(*ks && sem_trywait(semaphore) != 0);
	return 0;

/*
 * We wait "forever" but that means checking back on
 * the ks regularly. The reason for this rather contrived 
 * solution is the lack of "less messy" and portable approaches
 * to interprocess-named-condition variables
 * (OSX doesn't even provide sem_timedwait) 
 */
	long long start = arcan_timemillis();

	while(*ks == 1){
		if (!broken_timedwait){
			if (-1 == sem_timedwait(semaphore, &ts)){
				switch(errno){
				case ETIMEDOUT:
					fprintf(stderr, "timedout\n");
					if (msecs > 0){
						msecs -= 10;
						if (msecs <= 0)
							return -1;
					}
				break;

				case EINTR:
					fprintf(stderr, "eintr\n");
				break;

				case EINVAL:
					fprintf(stderr, "einval\n");
				broken_timedwait = 1;
				continue;

				default:
				fprintf(stderr, "uknown (%d)\n", errno);
				}
			}
			else
				return 0;
		}
/* spinlock and hope, but break out as soon as possible */
		else {
			if (sem_trywait(semaphore) == 0)
				return 0;
			
			if (msecs > 0){
				long long cur = arcan_timemillis();
				if (cur - start >= msecs)
					return -1;
			}
		}
	}

	return -1;
}


