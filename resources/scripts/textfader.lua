
local function utf8forward(src, ofs)
	if (ofs <= string.len(src)) then
		repeat
		ofs = ofs + 1;
	until (ofs > string.len(src) or utf8kind( string.byte(src, ofs) ) < 2);
end

return ofs;
end

-- Increment one step, skips past escaped portions and handles UTF8
local function textfader_step(self)
	if (self.cpos == string.len(self.message) and self.clife >= self.mlife) then
		
	end

	if (self.alive == false) then
		return;
	end

	
	
	self.clife = self.clife + 1;

-- time to step
	if (self.clife >= self.mlife ) then
		self.cpos = utf8forward(self.message, self.cpos);
	end

	message = string.sub(self.rawtext, 1, self.cpos);
end

function textfader_create( message, xpos, ypos, opacity, speed )
	fdrtbl = {
		rawtest = message,
		x = xpos,
		y = ypos,
		opa = opacity,
		mlife = speed,
		clife = 0,
		cpos = 2,
		alive = true
	}

	return fdrtbl;
end
