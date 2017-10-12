-- vr_setup
-- @short: Launch the VR bridge for VR device support
-- @inargs: string:args, func:callback
-- @inargs: func:callback
-- @outargs:
-- @longdescr: VR support is managed through an external service
-- launched through this function. In principle, it works like a
-- normal frameserver with some special semantics and a different
-- engine code path for event interpretation and so on.
-- VR, as used here, covers ae large assortment of devices.
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
-- provides a virtual object and a test 'limb' to work with. Note that
-- the user arcan is running as will need to be able to access USB
-- devices for most real hardware backends to work.
--
-- The system is built around limbs appearing and disappearing, where
-- a limb will be a mapped and tracked 3d model bound to a vid that can
-- be used as any normal vid. The only caveat is that updating position
-- and orientation is done automatically behind the scenes to reduce
-- latency and CPU load.
--
-- The possible status.kind field values are as follows:
-- limb_added - a new limb was discovered
-- limb_removed - a previously added limb was lost (device failure)
--
-- for limb_added and limb_removed, the following subfields are present:
-- id, name. id is a value to be used with ref:vr_map_limb while name
-- is a textual representation of the limb slot that was consumed.
-- The possible values for 'name' are: (person, neck, eye-[left,right],
-- shoulder-[left,right], elbow-[left,right], wrist-[left,right],
-- [thumb,pointer,middle,ring,pinky]-[proximal,middle,distal]-[left,right],
-- hip-[left,right], knee-[left,right], ankle-[left,right], tool-[left,right]
--
-- the limb for the neck actually represents the head mounted device
-- itself. When this limb has appeared, it is safe to query display
-- properties via ref:hmd_metadata. In contrast to other limbs, this
-- slot can be mapped twice in order to account for both viewpoints
-- needed when seting up the pipe. Unmapping the limb by setting it
-- to BADID will drop both slots.
--
-- the limb for the abstract 'person' defines the coordinate system
-- that the others will reference, and is typically important when there
-- is a positional tracking system. The reason this isn't bound to the
-- limb- skeleton as such is to keep the cost down for resolving hierarchies.
--
-- This system do not actually control the displays themselves, they
-- are expected to appear/ be managed with the same system as normal
-- dynamic display hotplugging, thus the display_enabled event should
-- act as a trigger to rescan for new monitors.
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
