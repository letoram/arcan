function tracetest(argv)
	local img = fill_surface(64, 64, 255, 0, 0)
	show_image(img)
	move_image(img, 100, 100, 100)
	move_image(img, 0, 0, 100)
	image_transform_cycle(img, true)

	benchmark_enable(10,
	function(set)
		local sample_line =
		function(val, suffix)
		local ph = "I"
		if val.trigger == 1 then
			ph = "B"
		elseif val.trigger == 2 then
			ph = "E"
		end

		return string.format(
			[[{"name":"%s", "cat":"%s,%s", "ph":"%s","pid":"%s","tid":"%s","ts":%s,"args":["%s", "%s", "%s"]}%s]],
			val.subsystem, -- name
			val.system, val.path, -- cat
			ph, -- ph
			0, -- pid
			0, --tid
			tostring(val.timestamp), -- ts
			tostring(val.identifier), -- args 0
			val.message, -- args 1
			tostring(val.quantity), -- args 2
			suffix
		)
		end
		open_rawresource(argv[1] and argv[1] or "tracetest.json")
		write_rawresource("[")
		for i=1,#set-1 do
			write_rawresource(sample_line(set[i], ",\n"))
		end
		write_rawresource(sample_line(set[#set], "]"))
		close_rawresource()
	end)
end

function tracetest_clock_pulse()
	benchmark_tracedata("clock", tostring(CLOCK))
end
