function awbwnd_listview(pwin, cell_w, cell_h, iconsz, datasel_fun, 
	scrollbar_icn, scrollcaret_icn, bardir, options)

	if (bardir == nil) then
		bardir = "r";
	end

	pwin.cell_w  = cell_w;
	pwin.cell_h  = cell_h;
	
	if (options) then
		for k,v in pairs(options) do
			pwin[k] = v;
		end
	end

	pwin.canvas.minw = cell_w;
	pwin.canvas.minh = cell_h;

	pwin.ofs       = 1;
	pwin.datasel   = datasel_fun;
	pwin.icons     = {};

	pwin.icon_bardir = bardir;
	pwin.scrollbar   = awbicon_setscrollbar;
	pwin.reposition  = awbicon_reposition;
	pwin.scrollcaret = scrollcaret_icn;

	image_tracetag(scrollbar_icn,   "awbwnd_listview.scrollbar");
	image_tracetag(scrollcaret_icn, "awbwnd_listview.scrollcaret_icn");

--
-- build scrollbar 
--
	local bartbl = pwin.dir[bardir];
	local newicn = bartbl:add_icon("fill", scrollbar_icn);

	link_image(scrollcaret_icn, newicn.vid);
	image_inherit_order(scrollcaret_icn, true);
	order_image(scrollcaret_icn, 1);
	show_image(scrollcaret_icn);
	resize_image(scrollcaret_icn, 
		pwin.dir["t"].size - 2, pwin.dir["t"].size - 2); 

	pwin.icon_resize = pwin.resize;
	pwin.resize = awbicon_resize;

	pwin:resize(pwin.w, pwin.h);
	return pwin;
end
