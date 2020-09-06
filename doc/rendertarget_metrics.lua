-- rendertarget_metrics
-- @short: Retrieve statistics about the state of a rendertarget pipeline
-- @inargs: vid:rtgt
-- @outargs: table
-- @longdescr: At times you might want to make a decision based on the generic state of
-- a pipeline. A common case is post processing filters that are too expensive to apply
-- on every frame. The easiest approach then has been to attach it to a lower refresh
-- clock, but that creates visible latency in the effect that might be quite visible
-- and might still update redundantly.
--
-- The other option is to have a preframe handler that determines if it is worthwhile to
-- add more work to the queue or not, and in order to make such a heuristic some input is
-- needed. This function can be used to retrieve some information about what is going on
-- in a render pipeline without forcing manual tracking.
--
-- The fields in the returned table are:
-- *int:dirty* - how many times the dirty counter has been incremented since last render pass.
-- *int:transfers* - the number of external uploads since last render pass.
-- *int:updates* - the number of ongoing transforms.
-- *int:time_move* - the relative clock of the last move transform.
-- *int:time_scale* - the relative clock of the last scale transform.
-- *int:time_rotate* - the relative clock of the last rotate transform.
-- *int:time_blend* - the relative clock of the last blend transform.
--
-- @group: targetcontrol
-- @cfunction: rendertargetmetrics
-- @related:
function main()
#ifdef MAIN
	local anim = fill_surface(32, 32, 255, 0, 0)
	show_image(anim, 100)
	move_image(anim, 100, 100, 200)

	_G[APPLID .. "_preframe_pulse"] = function()
		for k,v in pairs(rendertarget_metrics(WORLDID)) do
			print(k, v)
		end
	end
#endif

#ifdef ERROR1
#endif
end
