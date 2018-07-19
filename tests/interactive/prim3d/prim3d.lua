function prim3d()
	local cube_1 = build_3dbox(1, 1, 1);
	show_image(cube_1);
	move3d_model(cube_1, 1, -1, 0);
end
