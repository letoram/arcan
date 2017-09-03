static bool lookup(const char* const key,
	unsigned short ind, char** val, uintptr_t tag)
{
	if (val)
		*val = NULL;
	return false;
}

cfg_lookup_fun platform_config_lookup(uintptr_t* tag)
{
	if (!tag)
		return NULL;
	return lookup;
}
