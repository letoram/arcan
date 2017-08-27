int ffsll(long long mask)
{
	int ind = 0;
	if (mask == 0)
		return 0;
	for (ind = 0; !(mask & 1); ind++)
		mask = (unsigned long long) ind >> 1;
	return ind;
}
