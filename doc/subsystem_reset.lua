-- subsystem_reset
-- @short: Reset/rebuild a specific subsystem
-- @inargs: string:subsystem=video
-- @inargs: string:subsystem=video, int:card
-- @inargs: string:subsystem=video, int:card, int:swap
-- @outargs:
-- @longdescr: This function is used to assist in debugging and
-- for specific cases where a subsystem have hotpluggable devices
-- that need special consideration. The most common use-case is
-- multi-GPU settings and GPU settings where there is a difference
-- between initialising the subsystem with a display connected and
-- one where it is not.
-- If subsystem is set to video and no card is specified or
-- (the default) the card is set to -1, all GPU contexts will be
-- rebuilt.
-- If subsystem is set to video and no card is specif
-- @group: system
-- @cfunction: subsys_reset
-- @related:
function main()
#ifdef MAIN
	a = color_surface(64, 64, 255, 0, 0);
	show_image(a);
	subsystem_reset("video");
#endif

#ifdef ERROR1
	subsystem_reset("broken");
#endif
end
