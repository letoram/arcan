--
-- Recorder Built-in Tool
-- Some regular configuration popups, e.g. resolution, framerate, 
-- and a drag-n-drop composition canvas
--

function spawn_vidrec()
	local wnd = awbwman_spawn();

	if (wnd == nil) then 
		return;
	end

-- add ttbar, icons for; 
-- resolution (popup, change vidres, preset values)
-- framerate
-- codec
-- vcodec
-- muxer
-- possibly name
-- start recording (purge all icons, close button stops.)

--
-- For drag and drop, attach the data to the canvas and
-- use it there in scaled down form and let the user drag/move or scale
-- 
end
