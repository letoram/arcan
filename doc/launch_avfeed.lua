-- launch_avfeed
-- @short: Launch a customized frameserver
-- @inargs: *argstr*, *callback*
-- @outargs: vid, aid
-- @longdescr: This configures a frameserver to map to the frameserver/avfeed.c
-- skeleton, intended to use for customized input frameservers. An example
-- can be found in attic/avfeed_xiq.c for a quick- and dirty hack to map up
-- a third party camera API. This function is intended for specialized
-- projects where the feature-set from the other modes (decode, encode, network, libretro)
-- is insufficient.
-- @group: targetcontrol
-- @cfunction: setupavstream
-- @related: load_movie, launch_target, define_recordtarget, net_open, net_listen
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
