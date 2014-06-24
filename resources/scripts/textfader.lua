
-- take one step forward, counting escape sequences and format values.
local function utf8forward(src, ofs, steps)
	while (steps > 0) do
		if (ofs <= string.len(src)) then
			repeat
				ofs = ofs + 1;
			until (ofs > string.len(src) or utf8kind( string.byte(src, ofs) ) < 2);
		end

		steps = steps - 1;
	end

	return ofs;
end

local function formatskip(str, ofs)
	repeat
		local ch = string.sub(str, ofs, ofs);
		local ofs2 = utf8forward(str, ofs, 1);
		local ch2 = string.sub( str, ofs2, ofs2);

		if (ch ~= "\\") then
			break;
		end

-- proper escaping for backslasht
		if (ch2 == "\\") then
			break;
		end

-- skip #RRGGBB
		if (ch2 == "#") then
			ofs = utf8forward(str, ofs, 8);
			break;
		end

-- font, scan for , then first non-digit
		if (ch2 == "f") then
			ofs = utf8forward(str, ofs, 3);

			while ( string.sub(str, ofs, ofs) ~= "," ) do
				ofs = utf8forward(str, ofs, 1);
			end

			ofs = utf8forward(str, ofs, 1);

			while ( tonumber( string.sub(str, ofs, ofs) ) ~= nil ) do
				ofs = utf8forward(str, ofs, 1);
			end
		elseif (ch2 == "!") then
			ofs = utf8forward(str, ofs, 2);
		else
			ofs = utf8forward(str, ofs, 1);
		end

	until true;

	return ofs;
end

-- Increment one step, skips past escaped portions and handles UTF8
local function textfader_step(self)
	if (self.cpos == string.len(self.message) and self.clife >= self.mlife) then
		self.alive = false;
	end

	if (self.alive == false) then
		return;
	end

	self.clife = self.clife + 1;

-- time to step
	if (self.clife >= self.mlife ) then
-- now we have formatting strings to consider as well
		self.last = self.cpos;
		self.cpos = formatskip(self.message, self.cpos)
		if (self.cpos == self.last) then
			self.cpos = formatskip(self.message, utf8forward(self.message, self.cpos, 1) );
		end

		self.clife = 0;
		self.smessage = string.sub(self.message, 1, self.cpos);

		if (self.rmsg ~= BADID) then
			delete_image(self.rmsg);
		end

		self.rmsg = render_text(self.smessage);
		move_image(self.rmsg, self.x, self.y, NOW);
		blend_image(self.rmsg, self.opa, NOW);
	end
end

function textfader_create( rawtext, xpos, ypos, opacity, speed )
	fdrtbl = {
		message = rawtext,
		x = xpos,
		y = ypos,
		opa = opacity,
		mlife = speed,
		clife = speed,
		alive = true,
		rmsg = BADID
	};

	assert(0 < speed);

	fdrtbl.step = textfader_step;
	fdrtbl.cpos = 1;
	return fdrtbl;
end
