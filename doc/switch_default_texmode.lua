-- switch_default_texmode
-- @short: Switch how the associated texture storage should treat coordinates outside the [0..1] range.
-- @inargs: mode_s, mode_t, *optvid*
-- @longdescr: If *optvid* isn't set, the global default value for newly allocated textures will be switched.
-- @note: Accepted values for mode_(s,t) are TEX_REPEAT, TEX_CLAMP
-- @group: vidsys
-- @cfunction: settexmode

