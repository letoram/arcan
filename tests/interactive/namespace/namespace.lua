-- testing user namespaces
function namespace()
	local list = glob_resource(":namespaces")
	for i, v in ipairs(list) do
		print(i, v)
	end
end
