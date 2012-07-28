testlines_normal = {
	[[\fdefault.ttf,14\#ffffffTest1:Backslash:\\]],
	[[Test2:\#ff00ffMulti_\#ff0000c\#00ff00o\#0000ffl\#ff00ffo\#ffffffr]],
	[[Multiline_test\nMultiline_test]],
	[[Multiline_test\n\rShould_be_CR]],
	[[TwoTabs\t\tTwoTabs]],
	[[Multiline_test\n\n\rTwo empty lines]],
	[[Multi\nLine\test]],
	[[Multi\ffonts/default.ttf,28Sizes\nSizes2\ffonts/default.ttf,32Sizes3]],
	[[Multi\ffonts/default.ttf,16Size and \pfonttest.ico, \ticon]],
--	[[differently\pfonttest.ico,12,12, sized \pfonttest.ico,16,16, icons]],
	[[\n\n\n]]	
};

testlines_error = {
	[[\ffonts/missing.ttf]],
	[[\ffonts/missing.ttf,a]],
	[[\ffonts/default.ttf,1000000]],
	[[\p,badimg,]],
	[[\p12,a,badimg,]],
	[[\p14,10000,fonttest.ico,]],
	[[\#badcolour]],
	[[\t\a\b\c\d\e\f]]
};

function fonttest()
	yofs = 0;
	
	for i=1,#testlines_normal do
		print("(" ..i .. ")" .. testlines_normal[i]);
		print(testlines_normal);
				
		vid, lines = render_text(testlines_normal[i]);
		for j=1,#lines do
			print(lines[j]);
		end
		
		show_image(vid);
		move_image(vid, 0, yofs, 0);
		props = image_surface_properties(vid);
		yofs = yofs + props["height"];
	end
	
end

function fonttest_input(inputbl)
end
