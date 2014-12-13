-- target_coreopt
-- @short: Set target- specific runtime key-vale
-- @inargs: vid, slot, value
-- @longdescr: Some hijack targets (and libretro cores in particular), expose core-option slots and list of values through callback triggered events (kind = coreopt) that are comprised of a description, a key, a slotid and a set of values (the first value sent is the one currently active). This function can be used to change the active configuration by sending the corresponding slot/value pair (not that unsupported values will be silently discarded, it's up to the script to track).
-- @group: targetcontrol
-- @cfunction: targetcoreopt
-- @related: launch_target

