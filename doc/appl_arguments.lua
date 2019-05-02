-- appl_arguments
-- @short: Retrieve the (arguments) used with the appl- entrypoint
-- @inargs:
-- @outargs: strtbl
-- @longdescr: Normally, one would only need to do argument passing to
-- the appl on when switching using ref:system_collapse or at first launch.
-- However, this prevents passing arguments that can be interpreted by
-- post-hook scripts. To support such a case, this function returns the
-- last table used to call the applname(arguments) entrypoint.
-- @group: system
-- @cfunction: getapplarguments
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
