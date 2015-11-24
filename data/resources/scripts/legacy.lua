-- implementation of functions that have been deprecated in
-- upstream arcan, so it depends on engine version
--

if (API_VERSION_MAJOR >= 0 and API_VERSION_MINOR >= 10) then
function target_pointsize(vid, num)
	target_graphmode(vid, 4, num);
end

function target_linewidth(vid, num)
	target_graphmode(vid, 5, num);
end

POSTFILTER_NTSC = 100;
POSTFILTER_OFF = 10;
function target_postfilter(vid, num)
	if (num == POSTFILTER_NTSC) then
		target_graphmode(vid, 2);
	elseif (num == POSTFILTER_OFF) then
		target_graphmode(vid, 1);
	end
end

function target_postfilter_args(vid, group, v1, v2, v3)
	target_graphmode(vid, 3, group, v1, v2, v3);
end
end

