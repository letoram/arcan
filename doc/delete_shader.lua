-- delete_shader
-- @short: Deallocate the resources tied to a shid
-- @inargs: shid
-- @outargs:
-- @longdescr: Though shaders themselves doesn't cost much in terms of
-- dynamic resources (kilobytes of data), over time uniform groups and
-- similar side features may eventually saturate some resources. For this
-- purpose, delete_shader can be used to discard shader related resources.
-- Using this on a *shid* that is already bound will cause owning objects
-- to fall back to the default ones.
-- @group: vidsys
-- @cfunction: deleteshader
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
