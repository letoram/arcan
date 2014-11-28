--
-- No Copyright Claimed, Public Domain
--

-- Simple Colourpicker
--
-- colorpicker_new => table
--
-- Table Methods
-- show()
-- destroy()
-- input(label), label :- MENU_UP, MENU_LEFT, MENU_RIGHT, MENU_DOWN,
-- MENU_SELECT, returns {r,g,b] triplet on completion
--
-- Table Members
-- anchor (item positions)

local function hsc_c(h, s, c, m)
	local rv = {0, 0, 0};

	if (h < 0 or h > 360) then return rv; end
	if (s < 0 or s > 1  ) then return rv; end

	local hp = h / 60;
	local x  = c * (1 - math.abs(hp % 2 - 1));

	if (hp < 1) then
		rv[1] = c;
		rv[2] = x;
	elseif (hp < 2) then
		rv[1] = x;
		rv[2] = c;
	elseif (hp < 3) then
		rv[2] = c;
		rv[3] = x;
	elseif (hp < 4) then
		rv[2] = x;
		rv[3] = c;
	elseif (hp < 5) then
		rv[1] = x;
		rv[3] = c;
	else
		rv[1] = c;
		rv[3] = x;
	end

	rv[1] = math.floor(255 * (rv[1] + m));
	rv[2] = math.floor(255 * (rv[2] + m));
	rv[3] = math.floor(255 * (rv[3] + m));

	return rv;
end

function hsl(h, s, l)
	if (l < 0 or l > 1 ) then return {0, 0, 0} end
	local c = (1 - math.abs(2 * l - 1)) * s;
	local m = l - (0.5 * c);

	return hsc_c(h, s, c, m);
end

function hsv(h, s, v)
	local c = v * s;
	local m = v - c;

	return hsc_c(h, s, c, m);
end

local function build_colortable(anchor, rows, cols, w, h, spacing, order)
	local rv  = {};

	for i=1,rows do
		local row = {};
		local lv  = i * (1 / rows);

		for j=1,cols do
			local col = hsl(j * (360 / cols), 1.0, lv);

			col.vid = fill_surface(w, h, col[1], col[2], col[3]);
			link_image(col.vid, anchor);
			image_mask_clear(col.vid, MASK_OPACITY);
			move_image(col.vid, (i-1) * (w + spacing), (j-1) * (h + spacing));
			order_image(col.vid, order);
			show_image(col.vid);
			row[j] = col;
		end

		rv[i] = row;
	end

	return rv;
end

local function destroy(self)
	delete_image(self.anchor); -- rest will just cascade
	self.grid = nil;
	self.anchor = nil;
end

local function cursor_coord(self)
	local props = image_surface_properties(self.grid[self.cursor_col][self.cursor_row].vid);
	return (props.x - (self.spacing * 0.5)), (props.y - (self.spacing * 0.5));
end

local function cliprowcol(self)
	if (self.cursor_row > self.rows) then
		self.cursor_row = 1;
		self.cursor_col = self.cursor_col + 1;

	elseif (self.cursor_row < 1) then
		self.cursor_row = self.rows;
		self.cursor_col = self.cursor_col - 1;
	end

	if (self.cursor_col < 1) then
		self.cursor_col = self.cols;
	elseif (self.cursor_col > self.cols) then
		self.cursor_col = 1;
	end
end

local function steprow(self, step)
	self.cursor_row = self.cursor_row + step;
	cliprowcol(self);
	instant_image_transform(self.cursor_vid);

	local x,y = cursor_coord(self);
	move_image(self.cursor_vid, x, y, 2);

	local cell = self.grid[self.cursor_col][self.cursor_row];
	return {cell[1], cell[2], cell[3]};
end

local function stepcol(self, step)
	self.cursor_col = self.cursor_col + step;
	cliprowcol(self);
	instant_image_transform(self.cursor_vid);

	local x,y = cursor_coord(self);
	move_image(self.cursor_vid, x, y, 2);

	local cell = self.grid[self.cursor_col][self.cursor_row];
	return {cell[1], cell[2], cell[3]};
end

function colpicker_new(w, h, x, y, rows, cols)
	local restbl = {
		refresh = refresh,
		input = input,
		destroy = destroy,
		step_cursor_row = steprow,
		step_cursor_col = stepcol,
		cursor_row = 1,
		cursor_col = 1
	};

	local orderbase = max_current_image_order();

	restbl.anchor = fill_surface(1, 1, 0, 0, 0);
	move_image(restbl.anchor, x, y);
	image_tracetag(restbl.anchor, "colorpicker anchor");

	restbl.rows = rows;
	restbl.cols = cols;
	restbl.cellw = w;
	restbl.cellh = h;
	restbl.spacing = 4;

	restbl.grid   = build_colortable(restbl.anchor, rows, cols, w, h, restbl.spacing, orderbase + 1);
	restbl.cursor_vid = fill_surface(w + 4, h + 4, 255, 255, 255);

	order_image(restbl.cursor_vid, orderbase);
	link_image(restbl.cursor_vid, restbl.anchor);
	show_image(restbl.cursor_vid);
	image_mask_clear(restbl.cursor_vid, MASK_OPACITY);
	move_image(restbl.cursor_vid, -2, -2);

	return restbl;
end
