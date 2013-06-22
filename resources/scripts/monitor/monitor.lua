function monitor()
	warning("monitor callback running");
end

function sample(sampletbl)
	print("sample\n");
	for key, val in pairs(sampletbl.display) do
		print(key .. ":" .. tostring(val));
	end

	print("first context:\n");
	for key, val in pairs(sampletbl.vcontexts[1].vobjs[1]) do
		print(key .. ":" .. tostring(val));
	end

	print("/sample\n");
end

