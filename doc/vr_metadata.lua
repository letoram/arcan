-- vr_metadata
-- @short: retrieve metadata from a vr bridge
-- @inargs: vid:id
-- @outargs: strtbl or nil
-- @longdescr: In order to setup a useful 3d pipeline for working with HMDs,
-- you need access to some metadata. This function is used to retrieve a table
-- of the relevant parameters needed for creating a distortion mesh or a barrel
-- distortion shader that tmach the specified vr device.
-- The currently available keys in *strtbl* are:
-- [width : display horizontal resolution in pixels],
-- [height : display vertical resolution in pixels],
-- [center : distance from edge to center, (m)],
-- [horizontal : display horizontal physical size, in m],
-- [vertical : display vertical physical size, in m],
-- [eye_display : distance from eyes to display, in m],
-- [ipd : interpupillary distance, in m],
-- [distortion : subtable of 4 floats with lens distortion data],
-- [abberation : subtable of 4 floats with lens distortion data]
-- If the metadata couldn't be accessed at this time due to some problem with the
-- internal state of the vr bridge, or if ref:id doesn't refer to a valid vrbridge
-- instance, the function will return nil. The best indicator for if the bridge
-- metadata has been available or not is after a 'limb_added' event.
-- @group: iodev
-- @cfunction: vr_getmeta
-- @related: vr_setup, vr_maplimb
function main()
#ifdef MAIN
	local bridge = vr_setup("test",
	function(source, status)
		if (status.kind == "limb_added") then
			local tbl = vr_metadata(source);
			if (tbl) then
				print(string.format(
					"test-hmd values:\nwidthxheight - %f x %f\n" ..
					"horiz, vert, center: %f , %f , %f\n" ..
					"eye_display, ipd: %f ,  %f\n",
						tbl.width, tbl.height, tbl.center, tbl.horizontal,
						tbl.vertical, tbl.eye_display, tbl.ipd)
				);
			end
			shutdown();
		end
	end);
#endif

#ifdef ERROR1
	vr_metadata(WORLDID);
#endif
end
