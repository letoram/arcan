# Random Speed Test

This is to test the speed of the random number generation. The test hardness 
is from the PRNG shootout at https://prng.di.unimi.it/

Machine:
vendor_id	: GenuineIntel
cpu family	: 6
model		: 142
model name	: Intel(R) Core(TM) i7-8565U CPU @ 1.80GHz
stepping	: 12

Results:
$ ./random_speed 10000000
./random_speed: 3.410 s, 0.023 GB/s, 0.003 words/ns, 340.961 ns/word

