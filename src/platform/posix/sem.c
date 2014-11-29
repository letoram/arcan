#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <sys/types.h>
#include <unistd.h>

#include PLATFORM_HEADER

int arcan_sem_post(sem_handle sem)
{
	return sem_post(sem);
}

int arcan_sem_unlink(sem_handle sem, char* key)
{
	return sem_unlink(key);
}

int arcan_sem_trywait(sem_handle sem)
{
	return sem_trywait(sem);
}

int arcan_sem_wait(sem_handle sem)
{
	return sem_wait(sem);
}

int arcan_sem_init(sem_handle* sem, unsigned val)
{
	if (*sem == NULL){
		*sem = malloc(sizeof(sem_t));
	}
	return sem_init(*sem, 0, val);
}

int arcan_sem_destroy(sem_handle sem)
{
	return sem_destroy(sem);
}
