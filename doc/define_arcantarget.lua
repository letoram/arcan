-- define_arcantarget
-- @short:
-- @inargs: vid:vstore, string:type, vidtbl:vpipe, aidtbl:apipe, int:refresh
-- @outargs: bool
-- @longdescr: This function creates a rendertarget, binds its output to *vstore*
-- and then requests a server-side mapping of *type* to be created. A default
-- event-handler will be set, and upon receiving an accept or reject to the server
-- mapping, the _arcan_segment event handler will be invoked with a *source* that
-- corresponds to *vstore*.
-- By using ref:target_updatehandler on *vstore*, the default event loop will
-- be replaced.
-- @note: Valid types are: 'cursor', 'popup', 'icon', 'clipboard', 'titlebar',
-- 'debug', 'widget', 'accessibility', 'media', 'hmd-r', 'hmd-l'
-- @note: An invalid vstore or unsupported type is a terminal state transition.
-- @group: targetcontrol
-- @cfunction: arcanset
-- @related:
-- @flags: experimental
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
