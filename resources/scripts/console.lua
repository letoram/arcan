-- helper script for a simple command- console
-- with some decent functions like autocomplete etc.


function console_input(self, iotbl)
-- KEYUP,    replace buffer with historyline
-- KEYDOWN,  clear buffer
-- KEYLEFT,  insert offset in buffer is moved to the left
-- KEYRIGHT, insert offset in buffer is moved to the right
-- KEYTAB,   input buffer against preset list and replace with least common denominator
-- KEYENTER, submit, return buffer
end

function console_buffer_draw(self)
	if (BADID ~= self.bufferline) then
		delete_image(self.bufferline);
	end
	
	self.bufferline = render_text( newtbl.fontstr .. self.buffer );
	order_image(self.bufferline, 255);
	link_image(self.bufferline, newtbl.console_window);
	image_mask_set(newtbl.bufferline, MASK_POSITION);
	move_image(self.bufferline, self.height);
	image_clip_on(self.bufferline);
	show_image(self.bufferline);
end

function create_console(width, height, font, fontsize)
	local newtbl = {};
	
	newtbl.input = console_input;
	newtbl.history = {};
	newtbl.buffer = "";
	newtbl.position = 1;
	newtbl.historyofs = 0;
	newtbl.width = width;
	newtbl.height = height;
	newtbl.fontstr = [[\f]] .. font .. "," .. tostring(fontsize);
	newtbl.buffer = "";
	newtbl.bufferline = BADID;

-- should really be a prefix- tree .. 
	newtbl.autocomplete = {};

--  assert, width > 6
	newtbl.console_window_border = fill_surface(width, height, 255, 255, 255);
	newtbl.console_window = fill_surface(width - 6, height - 6, 0, 0, 0);
	link_image(newtbl.console_window, newtbl.console_window_border);
	move_image(newtbl.console_window, 3, 3, NOW);
--	image_clip_on(newtbl.console_window);
	order_image(newtbl.console_window_border, 253);
	order_image(newtbl.console_window, 254);
	show_image(newtbl.console_window);
	show_image(newtbl.console_window_border);
	
--	resize_image(newtbl.console_window_border, width, 6, NOW);
--	resize_image(newtbl.console_window_border, width, height, 20);
	
	return newtbl;
end
