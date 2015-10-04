-- input_samplebase
-- @short: Change coordinate system origo for a device
-- @inargs: devid, *base_x*, *base_y*, *base_z*
-- @outargs:
-- @longdescr: This is primarily needed for mouse devices when working absolute
-- coordinates from a device in cases where it doesn't suffice to just offset
-- where a cursor is drawn. The perhaps easiest case where this might be needed
-- is where mouse input should be locked to a surface and the internal
-- tracking of the device should be shifted if it tries to go outside said
-- surface.
-- @group: iodev
-- @cfunction: inputbase
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
