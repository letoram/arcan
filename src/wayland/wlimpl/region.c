static void free_region(struct surface_region* reg)
{
	struct surface_region* last = reg;

	while (last){
		struct surface_region* next = last->next;
		last->next = NULL;
		free(last);
		last = next;
	}
}

static void region_destroy(struct wl_client* client, struct wl_resource* res)
{
	trace(TRACE_REGION, "region_destroy");
	free_region(wl_resource_get_user_data(res));
}

static struct surface_region* duplicate_region(struct surface_region* reg)
{
	struct surface_region* res = malloc(sizeof(struct surface_region));
	if (!res)
		return NULL;

	memcpy(res, reg, sizeof(struct surface_region));

	while (reg->next){
		res->next = malloc(sizeof(struct surface_region));
		if (!res->next)
			return res;

		memcpy(res->next, reg->next, sizeof(struct surface_region));
		reg = reg->next;
	}

	return res;
}

static struct region* find_free_region_slot(
	struct surface_region* reg, size_t max_depth)
{
	for (size_t i = 0; i < max_depth; i++){
		for (size_t j = 0; j < COUNT_OF(reg->regions); j++){
			if (reg->regions[j].op == REGION_OP_IGNORE)
				return &reg->regions[j];
		}

		if (!reg->next && i < max_depth - 1){
			struct surface_region* nr = malloc(sizeof(struct surface_region));
			*nr = (struct surface_region){0};
			reg->next = nr;
		}

		reg = reg->next;
	}

	return NULL;
}

/* protocol unspecified with negative width, negative height - more ambitious
 * would be the sort/merge/split set of operations to make intersect/union/...
 * more bearable */
static void coord_to_reg(struct region* reg,
	int32_t x, int32_t y, int32_t width, int32_t height)
{
	size_t x1 = x;
	size_t y1 = y;
	size_t x2 = x + width;
	size_t y2 = y + height;

	if (width < 0){
		x2 = x;
		x1 = x + width;
	}

	if (height < 0){
		y2 = y;
		y1 = y + height;
	}
	reg->x1 = x1;
	reg->x2 = x2;
	reg->y1 = y1;
	reg->y2 = y2;
}

static void region_add(struct wl_client* client,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_REGION,
		"region_add(%"PRId32", %"PRId32", +%"PRId32", +%"PRId32")", x, y, width, height);
	struct surface_region* reg = wl_resource_get_user_data(res);
	struct region* nr = find_free_region_slot(reg, 4);
	if (!nr)
		return;

	coord_to_reg(nr, x, y, width, height);
	nr->op = REGION_OP_ADD;
}

static void region_sub(struct wl_client* client,
	struct wl_resource* res, int32_t x, int32_t y, int32_t width, int32_t height)
{
	trace(TRACE_REGION,
		"region_sub(%"PRId32", %"PRId32", +%"PRId32", +%"PRId32")", x, y, width, height);
	struct surface_region* reg = wl_resource_get_user_data(res);
	struct region* nr = find_free_region_slot(reg, 4);
	if (!nr)
		return;

	coord_to_reg(nr, x, y, width, height);
	nr->op = REGION_OP_SUB;
}
