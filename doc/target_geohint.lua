-- target_geohint
-- @short: Hint desired contents locale.
-- @inargs: vid:tgt, number:latitude, number:longitude, number:elevation, string:country, string:spoken, string:written, number:timezone
-- @outargs:
-- @longdescr:
-- In order for clients to properly generate contents that depends on user preferences
-- when it comes to output and input languages as well as geolocation, it needs to be told
-- what those are. The *latitude* and *longitude* values, *elevation* is in meters.
-- The *country* is specified in the ISO-3166-1-alpha3 format and a length ~= 3 is a terminal
-- state transition. The *spoken* and *written* language is in ISO-639-2-alpha 3 code, and a
-- length ~= 3 is a terminal state transition. The *timezone* is expressed as an offset from
-- GMT.
-- @note: Using a vid for *tgt* that is not connected to a frameserver is a terminal state transition.
-- @group: targetcontrol
-- @cfunction: targetgeohint
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
