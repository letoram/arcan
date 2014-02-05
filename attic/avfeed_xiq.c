#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>

#include <m3api/xiApi.h>

#include "../arcan_shmpage_if.h"
#include "frameserver.h"

void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
{
/*	struct arg_arr* args = arg_unpack(resource); */
	struct frameserver_shmcont shmcont = frameserver_getshm(keyfile, true);
	struct arcan_evctx inevq;
	struct arcan_evctx outevq;
	arcan_event ev;

	if (-1 == arcan_sem_wait(shmcont.asem) ||
		-1 == arcan_sem_wait(shmcont.vsem))
	return;

	XI_IMG image;
	DWORD ndev = 0;
	xiGetNumberDevices(&ndev);
	printf("got %d devices\n", ndev);

	HANDLE xiH = NULL;
	int res = xiOpenDevice(0, &xiH);
	if (res != XI_OK){
		printf("couldn't open device\n");
	}

/* other parameters:
 * _EXPOSURE
 * _GAIN 
 * _DOWNSAMPLING
 * _FRAMERATE (HZ)
 * _AVAILABLE_BANDWIDTH
 * _ACQ_TIMING_MODE
 * _WIDTH
 * _HEIGHT
 * _XI_PRM_BUFFERS_QUEUE_SIZE
 */
	res = xiSetParamInt(xiH, XI_PRM_EXPOSURE, 10000);
	if (res != XI_OK){
		printf("couldn't set exposure\n");
	}

	frameserver_shmpage_setevqs(shmcont.addr, shmcont.esem, 
		&inevq, &outevq, false);

	if (!frameserver_shmpage_resize(&shmcont, 640, 480)){
		return;
	} 

/* useful fields:
 * frm : XI_IMG_FORMAT
 * width : w
 * height: h
 * nframe: n
 * tsSec
 * tsUSec
 * bp (raw buffer)
 * bp_size)
 */

	uint32_t* vidp;
	uint16_t* audp;
	
	frameserver_shmpage_calcofs(shmcont.addr, (uint8_t**) &vidp, (uint8_t**)&audp);
	xiStartAcquisition(xiH);

	while (1){
		while (1 == arcan_event_poll(&inevq, &ev)){}
		res = xiGetImage(xiH, 5000, &image);
		if (res != XI_OK){
			printf("couldn't acquire image\n");
			goto cleanup;
		} 
		else{
/* FORMAT:
 * XI_MONO8, XI_MONO16, XI_RGB24, XI_RGB32, XI_RGB_PLANAR, XI_RAW8, XI_RAW16 
 */
			uint32_t* bptr = vidp;
			uint8_t* iptr = (uint8_t*) image.bp;

			for (int i = 0; i < image.width * image.height; i++){
				*bptr++ = 0xff << 24 | (*iptr) << 16 | (*iptr) << 8 | (*iptr);
				iptr++;
			}	
		}

		shmcont.addr->vready = true;
		arcan_sem_wait(shmcont.vsem);
	}

cleanup:
	xiCloseDevice(xiH);
}
