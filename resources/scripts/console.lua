-- helper script for a simple command- console
-- with some decent functions like autocomplete etc.
--
-- Input will come from IO events, which are UTF-8, which, of course, LUA doesn't support by default
-- the utf8kind function is hacked into arcan_lua.c
--
-- Outstanding issues:
-- No scrolling for the messagewin
-- Just sanity check for dimensions ( too large a input is considered a fatal misuse of render_text )
-- Select text (affect delete / insert)
-- Copy + Paste in selectbuffer
-- Popup window for browsing match namespace / Autocomplete (by word, by line),
-- Template completion (mark words for replacement, stepping in completion word)
-- Limit on line-history
--

function string.utf8back(src, ofs)
	if (ofs > 1 and string.len(src)+1 >= ofs) then
		ofs = ofs - 1;
		while (ofs > 1 and utf8kind(string.byte(src,ofs) ) == 2) do
			ofs = ofs - 1;
		end
	end

	return ofs;
end

function string.utf8forward(src, ofs)
	if (ofs <= string.len(src)) then
		repeat
			ofs = ofs + 1;
		until (ofs > string.len(src) or utf8kind( string.byte(src, ofs) ) < 2);
	end

	return ofs;
end

function string.translateofs(src, ofs, beg)
	local i = beg;
	local eos = string.len(src);

	-- scan for corresponding UTF-8 position
	while ofs > 1 and i <= eos do
		local kind = utf8kind( string.byte(src, i) );
		if (kind < 2) then
			ofs = ofs - 1;
		end

		i = i + 1;
	end

	return i;
end

function string.utf8len(src, ofs)
	local i = 0;
	local rawlen = string.len(src);
	ofs = ofs < 1 and 1 or ofs

	while (ofs <= rawlen) do
		local kind = utf8kind( string.byte(src, ofs) );
		if (kind < 2) then
			i = i + 1;
		end

		ofs = ofs + 1;
	end

	return i;
end

function string.insert(src, msg, ofs, limit)
	local xlofs = src:translateofs(ofs, 1);
	assert(limit > 0);

	if ofs + string.len(msg) > limit then
		msg = string.sub(msg, 1, limit - ofs);

-- align to the last possible UTF8 char..
		while (string.len(msg) > 0 and utf8kind( string.byte(msg, string.len(msg))) == 2) do
			msg = string.sub(msg, 1, string.len(msg) - 1);
		end
	end

	return string.sub(src, 1, xlofs - 1) .. msg .. string.sub(src, xlofs, string.len(src)), string.len(msg);
end

function string.delete_at(src, ofs)
	local fwd = string.utf8forward(src, ofs);
	if (fwd ~= ofs) then
		return string.sub(src, 1, ofs - 1) .. string.sub(src, fwd, string.len(src));
	end

	return src;
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
	move_image(self.console_window_border, self.width, self.width, 10);
	resize_image(self.console_window_border, 1, 1, 10);
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

	if (self.caretpos > 1) then
		local msgstr = string.sub( self.buffer, 1,
			string.utf8back(self.buffer, self.caretpos) );

		editprop.width = self.fontsize;

		-- Figure out how wide the current message is (locate ofset)
		if (string.len(msgstr) > 0) then
			msgstr = string.gsub( msgstr, "\\", "\\\\" );
			local w, h = text_dimensions( self.fontstr .. msgstr );
			xpos = w;
		end
	end

	instant_image_transform(self.caret);
	move_image(self.caret, xpos, 0, 2);
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
	local rval = "";

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
			self.caretpos = string.utf8back(self.buffer, self.caretpos);
			console_update_caret(self);

		elseif (symres == "RIGHT") then
			self.caretpos = string.utf8forward(self.buffer, self.caretpos);
			console_update_caret(self);

		elseif (symres == "BACKSPACE") then
			if (self.caretpos > 0) then
				self.caretpos = string.utf8back(self.buffer, self.caretpos);
				self.buffer = string.delete_at(self.buffer, self.caretpos);
				console_buffer_draw(self);
				console_update_caret(self);
			end

		elseif (symres == "DELETE") then
			self.buffer = string.delete_at(self.buffer, self.caretpos);
			console_buffer_draw(self);
			console_update_caret(self);

		elseif (symres == "TAB") then

			local matchlist = console_autocomplete(self);

			if ( #matchlist == 1) then
				self.buffer, nch = string.insert(self.buffer, matchlist[1], self.caretpos+1, self.nchars);
				self.caretpos = self.caretpos + nch;

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
			rval = self.buffer;
			console_clearbuffer(self);
			self.caretpos = 1;
			console_update_caret(self);
			console_update_msgwin(self);
		else
			local keych = iotbl.utf8;

			if (self.shortcut[ symres ] ~= nil) then
				keych = self.shortcut[ symres ];
			elseif keych == nil then
				return rval;
			end

			self.buffer, nch = string.insert(self.buffer, keych, self.caretpos, self.nchars);
			self.caretpos = self.caretpos + nch;

			console_buffer_draw(self);
			console_update_caret(self);
		end

		return rval;
	end

	return rval;
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
		x = 0,
		y = 0,
		caretpos = 1,
		symtbl = symfun(),
		input = console_input,
		move = console_move,
		nlines = math.floor( ( h / (fontsize + 4) ) - 1 ),
		nchars = math.floor( ( w / (fontsize * 0.3) )),
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

	newtbl.hide = console_hide;
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
