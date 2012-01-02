-- helper script for a simple command- console
-- with some decent functions like autocomplete etc.

function string.insert(src, msg, ofs)
	return string.sub(src, 1,ofs-1) .. tostring(msg) .. string.sub(src, ofs, string.len(src));
end

function string.delete_at(src, ofs)
	return string.sub(src, 1, ofs-1) .. string.sub(src, ofs+1, string.len(src));
end

local function console_buffer_draw(self)
	if (BADID ~= self.bufferline) then
		delete_image(self.bufferline);
	end

--  Current edit-line
	local text = string.gsub( self.buffer, "\\", "\\\\" );
	self.bufferline = render_text( self.fontstr .. text );

	order_image(self.bufferline, 255);
	link_image(self.bufferline, self.console_window_inputbg);

	local pprops = image_surface_properties(self.console_window_inputbg);
	local props = image_surface_properties(self.bufferline);
	local xofs = 0;
	
	if (props.width > pprops.width) then
		xofs = 0 - (props.width - pprops.width);
	end
	
	move_image(self.bufferline, xofs, self.fontsize * 0.5 - 1, 0);
	image_clip_on(self.bufferline);
	show_image(self.bufferline);
end

local function console_show(self)
	reset_image_transform(self.console_window_border);
	hide_image(self.console_window_border, 0);
	move_image(self.console_window_border, self.x + self.width * 0.5, self.y + self.height * 0.5, 0);
	resize_image(self.console_window_border, 6, 6, 0);
	move_image(self.console_window_border, self.x, self.y, 10);
	resize_image(self.console_window_border, self.width, self.height, 10);
	blend_image(self.console_window_border, 0.95, 10);

	console_buffer_draw(self);
end

local function console_hide(self)
	reset_image_transform(self.console_window_border);
	blend_image(self.console_window_border, 0.0, 10);
	move_image(self.console_window_border, self.x + self.width * 0.5, self.y + self.height * 0.5, 0);
	resize_image(self.console_window_border, 6, 6, 0);
	move_image(self.console_window_border, self.x, self.y, 10);
	resize_image(self.console_window_border, self.width, self.height, 10);
	blend_image(self.console_window_border, 0.95, 10);
end

local function console_update_msgwin(self)
	msgcmd = self.fontstr;
	
	for i=1, self.nlines do
		local text = "";
		local cline = #self.linehistory - self.linehistoryofs - (self.nlines - i);
		if (cline > 0 and self.linehistory[ cline ] ~= nil) then
			text = string.gsub( self.linehistory[ cline ], "\\", "\\\\" ) .. "\\n\\r";
		else
		end
		
		msgcmd = msgcmd .. text;
	end

	delete_image(self.historywin);
	self.historywin = render_text( msgcmd );
	link_image(self.historywin, self.console_window);
	image_clip_on(self.historywin);
	move_image(self.historywin, 0, 0);
	order_image(self.historywin, 254);
	show_image(self.historywin);
end

local function console_addmsg(self, msg)
	table.insert(self.linehistory, msg);
end

local function console_clearbuffer(self)
	self.buffer = "";
	self.caretpos = 1;
	console_buffer_draw(self);
end

local function console_update_caret(self)
	instant_image_transform(self.caret);
	local editprop = image_surface_properties(self.bufferline);
	local xpos = 0;
	
	if (self.caretpos > 0) then 
		local msgstr = string.sub( self.buffer, 1, self.caretpos);
		editprop.width = self.fontsize;

		-- Figure out how wide the current message is (locate ofset)
		if (string.len(msgstr) > 0) then
			msgstr = string.gsub( msgstr, "\\", "\\\\" );
			local testimg  = render_text( self.fontstr .. msgstr );
			local testprop = image_surface_properties( testimg );
			xpos = testprop.width;
			delete_image(testimg);
		end
	end

	move_image(self.caret, xpos, 0, 5);
end

local function console_autocomplete(self)
	beg = 1;
	
	for i=self.caretpos,0,-1 do
		if string.sub(self.buffer, i, i) == " " then
			beg = i + 1;
			break;
		end
	end
	
	local prefix = string.sub( self.buffer, beg );
	local matchlist = {};
	if (string.len(prefix) == 0) then
		matchlist = self.autocomplete;
	else
		for i,v in pairs(matchlist) do
		
		end
	end
	
	return matchlist;
end

local function console_input(self, iotbl)
	if (iotbl.kind == "digital" and iotbl.translated and iotbl.active) then
		symres = self.symtbl[ iotbl.keysym ];
		
		if (symres == nil and iotbl.utf8 == "") then
			return false;
		end

		if (symres == "UP" or symres == "DOWN") then
			self.historypos = (symres == "UP" and self.historypos + 1) or (self.historypos - 1);

			if (self.historypos >= #self.history) then
				self.historypos = #self.history - 1;
			end

			if (self.historypos >= 0 and self.history[ #self.history - self.historypos] ) then
				self.buffer = self.history[ # self.history - self.historypos ];
				self.caretpos = string.len( self.buffer );
			else
				self.historypos = -1;
				self.caretpos = 0;
				self.buffer = "";
			end

			console_buffer_draw(self);
			console_update_caret(self);
			
		elseif (symres == "HOME") then
			self.caretpos = 0;
			console_update_caret(self);
			
		elseif (symres == "END") then
			self.caretpos = string.len( self.buffer );
			console_update_caret(self);
			
		elseif (symres == "LEFT") then
			self.caretpos = self.caretpos - 1 >= 0 and self.caretpos - 1 or 0;
			console_update_caret(self);
			
		elseif (symres == "RIGHT") then
			self.caretpos = self.caretpos + 1 > string.len(self.buffer) and self.caretpos or self.caretpos + 1;
			console_update_caret(self);
			
		elseif (symres == "BACKSPACE") then
			if (self.caretpos > 0) then
				self.buffer = string.delete_at(self.buffer, self.caretpos);
				self.caretpos = self.caretpos - 1 < 0 and 0 or self.caretpos - 1;
				console_buffer_draw(self);
				console_update_caret(self);
			end
			
		elseif (symres == "DELETE") then
			self.buffer = string.delete_at(self.buffer, self.caretpos + 1);
			console_buffer_draw(self);
			console_update_caret(self);
			
		elseif (symres == "TAB") then

			local matchlist = console_autocomplete(self);

			if ( #matchlist == 1) then
				self.buffer = string.insert(self.buffer, matchlist[1], self.caretpos+1);
				self.caretpos = self.caretpos + string.len( matchlist[1] );

				console_buffer_draw(self);
				console_update_caret(self);
			elseif (#matchlist > 1) then 
				for i, v in pairs( matchlist ) do
					console_addmsg(self, v);
				end

				console_update_msgwin(self);
			end
			
		elseif (symres == "ESCAPE") then
-- should really be filtered beforehand, oh well.
			
		elseif (symres == "RETURN") then
			table.insert(self.history, self.buffer);
			console_addmsg(self, self.buffer);
			self.historypos = -1;
			
			console_clearbuffer(self);
			self.caretpos = 0;
			console_update_caret(self);
			console_update_msgwin(self);
		else
			local keych = iotbl.utf8;

			if (self.shortcut[ symres ] ~= nil) then
				keych = self.shortcut[ symres ];
			elseif keych == nil then
				return false;
			end

			self.buffer = string.insert(self.buffer, keych, self.caretpos+1);
			self.caretpos = self.caretpos + string.len( keych );
			
			console_buffer_draw(self);
			console_update_caret(self);
		end

		return true;
	end

	return false;
end

local function console_move(self, newx, newy, time)
	move_image(self.console_window_border, newx, newy, time);
end

function create_console(w, h, font, fontsize)
	local symfun = system_load("scripts/symtable.lua");
	local newtbl = {
		history = {},
		linehistory = {},
		linehistoryofs = 0,
		position =  1,
		buffer = "",
		historypos = -1,
		width = w,
		height = h,
		x = 10,
		y = 10,
		caretpos = 0,
		symtbl = symfun(),
		input = console_input,
		move = console_move,
		nlines = math.floor( ( h / (fontsize + 4) ) - 1 ),
		autocomplete = {},
		shortcut = {},
		bufferline = BADID,
		historywin = BADID
	};

	if (newtbl.nlines <= 0) then
		return false;
	end
	
	newtbl.fontstr = [[\f]] .. font .. "," .. tostring(fontsize) .. " ";
	newtbl.fontsize = fontsize;

--  assert, width > 6f
	newtbl.inputbg_height = fontsize + (0.5 * fontsize);
	newtbl.console_window_border  = fill_surface(w, h, 128, 128, 128);
	newtbl.console_window         = fill_surface(w - 6, h - 6, 32, 32, 32);
	newtbl.console_window_inputbg = fill_surface(w - 6, newtbl.inputbg_height, 48, 48, 48);
	newtbl.caret = fill_surface(2, newtbl.inputbg_height, 200, 200, 200);
	props = image_surface_properties(newtbl.console_window);

	link_image(newtbl.console_window, newtbl.console_window_border);
	link_image(newtbl.console_window_inputbg, newtbl.console_window);
	link_image(newtbl.caret, newtbl.console_window_inputbg);
	
	move_image(newtbl.console_window, 3, 3, NOW);
	move_image(newtbl.console_window_inputbg, 0, h - newtbl.inputbg_height - 6, NOW);
	move_image(newtbl.caret, 0, 0, NOW);

	image_clip_on(newtbl.console_window_inputbg);
	image_clip_on(newtbl.caret);
	
	order_image(newtbl.console_window_border, 250);
	order_image(newtbl.console_window, 251);
	order_image(newtbl.console_window_inputbg, 252);
	order_image(newtbl.caret, 253);
	
	show_image(newtbl.console_window);
	show_image(newtbl.console_window_inputbg);
	show_image(newtbl.caret);
	
	newtbl.show = console_show;
	newtbl.auto_completion = function( self, list )
		if (list ~= nil) then
			self.autocomplete = list;
		else
			self.history = {};
		end
	end

	newtbl.shortcuts = function( self, list )
		if (list ~= nil) then
			self.shortcut = list;
		else
			self.shortcut = {};
		end
	end
	
	return newtbl;
end
