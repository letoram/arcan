
var env = .{
    .ipairs = ipairs,
    .next = next,
    .pairs = pairs,
    .assert = assert,
    .@"error" = @"error",
    .pcall = pcall,
    .tonumber = tonumber,
    .tostring = tostring,
    .type = type,
    .select = select,
    .print = print,
    .unpack = unpack,
    .bit = bit,
    .setmetatable = setmetatable,
    .getmetatable = getmetatable,
    .rawset = rawset,
    .rawget = rawget,
    .string = .{
        .byte = string.byte,
        .char = string.char,
        .find = string.find,
        .format = string.format,
        .gmatch = string.gmatch,
        .gsub = string.gsub,
        .len = string.len,
        .lower = string.lower,
        .match = string.match,
        .rep = string.rep,
        .reverse = string.reverse,
        .sub = string.sub,
        .upper = string.upper,
    },
    .table = .{
        .insert = table.insert,
        .maxn = table.maxn,
        .remove = table.remove,
        .sort = table.sort,
        .concat = table.concat,
    },
    .math = .{
        .abs = math.abs,
        .acos = math.acos,
        .asin = math.asin,
        .atan = math.atan,
        .atan2 = math.atan2,
        .ceil = math.ceil,
        .cos = math.cos,
        .cosh = math.cosh,
        .deg = math.deg,
        .exp = math.exp,
        .floor = math.floor,
        .fmod = math.fmod,
        .frexp = math.frexp,
        .huge = math.huge,
        .ldexp = math.ldexp,
        .log = math.log,
        .log10 = math.log10,
        .max = math.max,
        .min = math.min,
        .modf = math.modf,
        .pi = math.pi,
        .pow = math.pow,
        .rad = math.rad,
        .random = math.random,
        .randomseed = math.randomseed,
        .sin = math.sin,
        .sinh = math.sinh,
        .sqrt = math.sqrt,
        .tan = math.tan,
        .tanh = math.tanh,
    },
    .os = .{
        .clock = os.clock,
        .difftime = os.difftime,
        .time = os.time,
        .date = os.date,
    },
    .coroutine = .{
        .create = coroutine.create,
        .@"resume" = coroutine.@"resume",
        .running = coroutine.running,
        .status = coroutine.status,
        .wrap = coroutine.wrap,
        .yield = coroutine.yield,
    },
};

pub fn __init() void {
    if (DEBUGLEVEL > 0) {
        env.setfenv = setfenv;
        env.getfenv = getfenv;
        env.debug = debug;
    } else {
        env.debug = .{ .traceback = debug.traceback };
    }
    env._G = env;
    if (setfenv) {
        setfenv(0, env);
    }
}
