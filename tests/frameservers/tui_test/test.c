struct tui_cbcfg {
	int hi;
};

extern void arcan_tui_setup(struct tui_cbcfg* cfg);

int main(int argc, char** argv)
{
	struct tui_cbcfg test = {.hi = 1};
	arcan_tui_setup(&test);
	return 0;
}
