-- Creates two global functions: a function that traces function calls
-- and returns, and another function to turn it off.
--
-- Usage:
-- require('calltrace')
-- Trace() -- Turns on tracing.
-- Untrace() -- Turns off tracing.
-- The current depth of the stack (nil when not tracing):
local Depth
-- Returns a string naming the function at StackLvl; this string will
-- include the function's current line number if WithLineNum is true. A
-- sensible string will be returned even if a name or line numbers
-- can't be found.
local function GetInfo(StackLvl, WithLineNum)
-- StackLvl is reckoned from the caller's level:
  StackLvl = StackLvl + 1
  local Ret
  local Info = debug.getinfo(StackLvl, "nlS")
  if Info then
    local Name, What, LineNum, ShortSrc =
    Info.name, Info.what, Info.currentline, Info.short_src
    if What == "tail" then
      Ret = "overwritten stack frame"
    else
      if not Name then
        if What == "main" then
          Name = "chunk"
        else
          Name = What .. "function"
        end
      end
      
      if Name == "C function" then
        Ret = Name
      else
        -- Only use real line numbers:
        LineNum = LineNum >= 1 and LineNum
        if WithLineNum and LineNum then
          Ret = Name .. " (" .. ShortSrc .. ", line " .. LineNum .. ")"
        else
          Ret = Name .. " (" .. ShortSrc .. ")"
        end
      end
    end
  else
    -- Below the bottom of the stack:
    Ret = "nowhere"
  end
  return Ret
end

-- Returns a string of N spaces:
local function Indent(N)
  return string.rep(" ", N)
end

-- The hook function set by Trace:
local function Hook(Event)
  -- Info for the running function being called or returned from:
  local Running = GetInfo(2)
  -- Info for the function that called that function:
  local Caller = GetInfo(3, true)
  if not string.find(Running..Caller, "modules") then
    if Event == "call" then
      Depth = Depth + 1
      io.stderr:write(Indent(Depth), "calling ", Running, " from ",Caller, "\n")
    else
      local RetType
      if Event == "return" then
        RetType = "returning from "
      elseif Event == "tail return" then
        RetType = "tail-returning from "
      end
--(uncomment to trace returns)      io.stderr:write(Indent(Depth), RetType, Running, " to ", Caller,"\n")
      Depth = Depth - 1
    end
  end
end

-- Sets a hook function that prints (to stderr) a trace of function
-- calls and returns:
function Trace()
  if not Depth then
    -- Before setting the hook, make an iterator that calls
    -- debug.getinfo repeatedly in search of the bottom of the stack:
    Depth = 1
    for Info in
      function()
      return debug.getinfo(Depth, "n")
      end
    do
      Depth = Depth + 1
    end
    
    -- Don't count the iterator itself or the empty frame counted at
    -- the end of the loop:
    Depth = Depth - 2
    debug.sethook(Hook, "cr")
  else
    -- Do nothing if Trace() is called twice.
  end
end

-- Unsets the hook function set by Trace:
function Untrace()
  debug.sethook()
  Depth = nil
end
