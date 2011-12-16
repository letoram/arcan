#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>

int main(int argc, char** argv){
	uint64_t* ptr = (uint64_t*) 0xdeadbeef;
	printf(" ptr: %lli \n", ptr);
	ptr = ptr + 1;
	printf(" ptr: %lli \n", ptr);
	return 0;
}

