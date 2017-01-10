-- vr_setup
-- @short: Launch the VR bridge for VR device support
-- @inargs: *optargs*, callback
-- @outargs:
-- @longdescr: VR support is managed through an external service
-- launched through this function. In principle, it works like a
-- normal frameserver with some special semantics and a different
-- engine code path for event interpretation and so on.
-- VR, as used here, covers are large assortment of devices.
-- These devices include, but are not limited to:
-- Haptic Gloves, Haptic Suites, Eye/Gaze Trackers, Positional Devices,
-- Inside/Out trackers, and Motion Capture Systems. They may expose
-- separate video/audio devices (front-facing camera).
--
-- The framework provided here is launched and controlled with this
-- function, with other system changes delivered through the status
-- table. For this system to work, the auxiliary 'vrbridge' tool needs
-- to be built (not in the default engine compilation path), and the
-- binary explicitly added to the 'arcan' appl namespace of the active
-- database.
--
-- arcan_db add_appl_kv arcan ext_vr /path/to/vrbridge
--
-- The *optargs* is a normal arcan_arg packed string (key=value:key2)
-- with bridge- specific arguments (for now). The 'test' argument
-- provides a virtual object and a test 'limb' to work with.
--
-- The system is built around limbs appearing and disappearing, where
-- a limb will be a mapped and tracked 3d model bound to a vid that can
-- be used as any normal vid. The only caveat is that updating position
-- and orientation is done automatically behind the scenes to reduce
-- latency and CPU load.
--
-- The possible status.kind field values are as follows:
-- limb_added - a new limb was discovered
-- limb_removed
-- head_parameters - display data for setting up the stereoscoping
-- render passes and compositing the final output
-- distortion_left, distortion_right - a distortion mesh was loaded
-- and added as a model
-- display_enabled
--
-- for limb_added, the following subfields will be present:
-- id, haptics (subtable), type and the source argument will refer
-- to a newly created fully qualified 3d model possibly linked together
-- into an vr_setup instance specific avatar. The abstract avatar
-- root object will also be sent as a limb_added event.
--
-- distortion_left, distortion_right will also be sent as 3d models
-- linked to the vid passed as source argument. This will only be
-- provided if the underlying device supports it, thus a fallback to
-- shader lens based distortion will be needed. The parameters for
-- that are packed into the head_parameters event.
--
-- This system do not actually control the displays themselves, they
-- are expected to appear/ be managed with the same system as normal
-- dynamic display hotplugging, thus the display_enabled event should
-- act as a trigger to rescan for new monitors.
--
-- @note: The allocated objects passed as source must be managed
-- manually, i.e. delete_image when no longer needed or useful.
-- Deleting the abstract avatar limb will close the connection.
--
-- @note: Other interesting expansion to this model would be fusing
-- the different limbs together into a kalman filter with an IK- model
-- as a state estimator to counter sensors that intermittently become
-- unreliable.
--
-- @group: iodev
-- @cfunction: vr_setup
-- @flags: experimental
-- @related:
function main()
#ifdef MAIN
	vr_setup("test", function(source, status)
		print(status.kind)
	end);
#endif

#ifdef ERROR1
	vr_setup();
#endif
end
