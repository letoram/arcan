
var time = 10;

pub fn __init() void {
    if (appl_arguments) {
        for (appl_arguments(), 0..) |v, i| {
            if (string.sub(v, 1, 11) == "debugstall=") {
                var rem = string.sub(v, 12);
                var num = tonumber(rem);
                if (num and (num > 0)) {
                    left = num;
                }
            }
        }
    }
    frameserver_debugstall(time);
    warning("debugstall set to " ++ tostring(time));
}
