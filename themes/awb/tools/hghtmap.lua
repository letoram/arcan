local vshader = [[
	uniform mat4 modelview;
	uniform mat4 projection;
	uniform sampler2D map_diffuse;

	uniform float ampl;

	attribute vec2 texcoord;
	attribute vec4 vertex;

	varying vec2 texco;

	void main(){
		vec4 dv   = texture2D(map_diffuse, texcoord);
		vec4 vert = vertex;
		vert.y    = ampl * (dv.r + dv.g + dv.b) / 3.0;
		gl_Position = (projection * modelview) * vert;
		texco = texcoord;
	}
]];

local function update_display(self, newvid)
	image_tracetag(newvid, "heightmap_surface");
	local rvid = set_image_as_frame(self.vid, newvid, 0, FRAMESET_DETACH);
	if (rvid ~= nil and rvid ~= BADID) then
		delete_image(rvid);
	end

	image_shader(self.vid, self.shader);
end

local function update_ampl(self, val)
	shader_uniform(self.shader, "ampl", "f", PERSIST, val);
	self.ampl = val;
end

local function rebuild_mesh(model)
	local newmodel = build_3dplane(-2, -2, 2, 2, 0, model.subd, model.subd, 1);
	copy_image_transform(model.vid, newmodel);

--	local vid = set_image_as_frame(model.vid, 
	--	fill_surface(32,32,0,0,0), 0, FRAMESET_DETACH);

	set_image_as_frame(newmodel, 
		fill_surface(32, 32, 0, 0, 0), 0, FRAMESET_DETACH);
--	delete_image(model.vid);
	model.vid = newmodel;

	rendertarget_attach(model.owner.canvas.vid, model.vid, FRAMESET_DETACH);

	image_shader(model.vid, model.shader);
end

function spawn_hmap()
	local model = {};
	model.subd = 0.1;

	model.vid = build_3dplane(-2, -2, 2, 2, 0, model.subd, model.subd, 1);
	move3d_model(model.vid, 0, -1.0, 0);
	model.update_display = update_display;
	model.set_ampl = update_ampl;

	show_image(model.vid);

--
-- Inherit wnd and add buttons for controlling tesselation etc.
--
	local wnd = awbwman_modelwnd(menulbl("Height Map"), model);
	model.shader = build_shader(vshader, nil, "hmapn" .. wnd.wndid);
	if (wnd == nil) then
		return;
	end

	for i=#wnd.dir.tt.left,1,-1 do
		if (string.match(wnd.dir.tt.left[i].name, "light_%w+") ~= nil) then
			wnd.dir.tt.left[i]:destroy();
			table.remove(wnd.dir.tt.left, i);
		end
	end

	local cfg = awbwman_cfg();

--	wnd.dir.tt:add_icon("subdiv", "l", cfg.bordericns["subdivide"], function(self)
--		rebuild_mesh(model, model.subd * 0.5);
--	end);

--	wnd.dir.tt:add_icon("subdivneg","l",cfg.bordericns["subdivneg"],function(self)
--		rebuild_mesh(model, model.subd);
--	end);

	wnd.dir.tt:add_icon("ampl", "l", cfg.bordericns["amplitude"], function(self)
		wnd:focus();
		awbwman_popupslider(0.5, model.ampl, 4.0, function(val)
			model:set_ampl(val);
		end, {ref = self.vid});
	end);

	wnd.name = "heightmap";
	model.wndid = wnd.wndid;
	model.owner = wnd;

	model:set_ampl(2.0);
	model:update_display(fill_surface(32, 32, 20, 20, 20));
	return wnd;
end

local descrtbl = {
	name = "hghtmap",
	caption = "Heightmap",
	icon = "hghtmap",
	trigger = spawn_hmap
};

return descrtbl;
