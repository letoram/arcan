-- input_capabilities
-- @short: query platform layer for input capabilities
-- @inargs:
-- @outargs: captbl, ident
-- @longdescr: Depending on the system that arcan runs on, the knowledge
-- about which specific input devices are available may be fixed or change
-- as a response to external actions. This function tries to populate a
-- table identifying different kinds of input events that may appear in
-- an _input(iotbl) handler. The use for this function is primarily to judge
-- if some device capabilities are missing or not, e.g. translated inputs
-- for applications that cannot provide a useful fallback. The returned
-- table is in the a key=bool form.
-- @group: iodev
-- @cfunction: inputcap
-- @related:
function main()
#ifdef MAIN
	for k,v in pairs(input_capabilities()) do
		print(k, v);
	end
#endif
end
