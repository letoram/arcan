function set3_3()
	symtable = system_load("scripts/symtable.lua")();
end

function set3_3_input(iotbl)
	if (iotbl.translated and iotbl.active == false) then
		print(symtable[iotbl.keysym]);
	end
end
