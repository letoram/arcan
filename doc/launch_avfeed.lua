-- launch_avfeed
-- @short: Launch a customized frameserver
-- @inargs: *argstr*, *avmode*, *callback*
-- @outargs: vid, aid
-- @longdescr: launch_avfeed serves two purposes, over time it should be
-- the principal way to launch authoritative frameservers and unify the
-- others (load_movie etc.) and allow a quick and dirty interface for testing
-- and experimenting with custom ones through the AVFEED_LIBS AVFEED_SOURCES
-- compile time arguments. The global environment in FRAMESERVER_MODES
-- limits the possible arguments to avmode and is defined at compile time.
-- If *avmode* is not specified, it defaults to 'avfeed'.
-- @group: targetcontrol
-- @cfunction: setupavstream
-- @related: load_movie, launch_target, define_recordtarget, net_open, net_listen
function main()
#ifdef MAIN
#endif

#ifdef ERROR
#endif
end
