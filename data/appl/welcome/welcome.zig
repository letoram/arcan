
pub fn welcome() void {
    var symfun = system_load("builtin/keyboard.lua");
    if (symfun != null) {
        symtable = symfun();
    }
    titlestr = render_text("\\ffonts/default.ttf,18\\bWelcome to ARCAN!");
    move_image(titlestr, VRESW * 0.5 - (0.5 * image_surface_properties(titlestr).width));
    show_image(titlestr);
    var vid = load_image("images/icons/arcanicon.png");
    if (valid_vid(vid)) {
        resize_image(vid, 64, 64);
        move_image(vid, VRESW - 64, 0);
        show_image(vid);
        nudge_image(vid, 0, VRESH - 64, 100, INTERP_EXPIN);
        move_image(vid, VRESW - 64, 0, 100, INTERP_EXPOUT);
        image_transform_cycle(vid, 1);
    }
    intrstr = render_text("\\ffonts/default.ttf,12\\bUsage:\n\\!b arcan <cmdline arguments> applname <appl arguments>");
    move_image(intrstr, VRESW * 0.5 - (0.5 * image_surface_properties(intrstr).width), 24);
    show_image(intrstr);
    welcomestr = "\\n\\r\n\t\\ffonts/default.ttf,14\\bPoints of reference:\\!b\\n\\r\\ffonts/default.ttf,12\n\thttp://www.arcan-fe.com - Main Site\\n\\r\n\thttps://github.com/letoram/arcan - Github Page\\n\\r\n\tcontact@arcan-fe.com - E-mail contact\\n\\r\n\t\\ffonts/default.ttf,14\\b\\n\\nDetected settings:\\!b\\n\\r";
    left_inf = render_text(welcomestr);
    var st = .{};
    table.insert(st, string.format("Resolution:\\t\\t%d x %d", VRESW, VRESH));
    table.insert(st, string.format("Clock:\\t\\t%d Hz", CLOCKRATE));
    table.insert(st, string.format("GL Version:\\t\\t%s", GL_VERSION));
    table.insert(st, string.format("Build:\\t\\t%s", API_ENGINE_BUILD));
    right_inf = render_text(table.concat(st, "\\n\\r"));
    move_image(right_inf, image_surface_properties(left_inf).width + 10, 38);
    argwindow = render_text("\\n\\r\\ffonts/default.ttf,14\\t\\bCommand-Line Arguments:\\!b\n\\n\\r\\ffonts/default.ttf,12\n-w\\t--width       \\tdesired canvas width (default: 640)\\n\\r\n-h\\t--height      \\tdesired canvas height (default: 480)\\n\\r\n-f\\t--fullscreen  \\ttoggle fullscreen mode ON (default: off)\\n\\r\n-m\\t--conservative\\ttoggle conservative memory management (default: off)\\n\\r\n-q\\t--timedump    \\twait n ticks, dump snapshot to resources/logs/timedump\\n\\r\n-s\\t--windowed    \\ttoggle borderless window mode\\n\\r\n-p\\t--rpath          \\tchange default searchpath for shared resources\\n\\r\n-B\\t--binpath     \\tchange default searchpath and base for arcan_framesever\\n\\r\n-t\\t--applpath    \\tchange default searchpath for applications\\n\\r\n-b\\t--fallback    \\tset a recovery/fallback application if appname crashes\\n\\r\n-d\\t--database    \\tsqlite database (default: arcandb.sqlite)\\n\\r\n-g\\t--debug       \\tincrement debug level (events, coredumps, etc.)\\n\\r\n-S\\t--nosound     \\tdisable audio output (set gain to 0dB) \\n\\n\n");
    appl_list = glob_resource("*", SYS_APPL_RESOURCE);
    if (@intCast(appl_list.len) > 0) {
        var lst = .{ "\\bPossible <applname>:\\!b\\n\\r" };
        for (appl_list, 0..) |v, k| {
            var item = string.gsub(v, "\\", "\\\\");
            if ((k % 5) == 0) {
                item = item ++ "\\n\\r";
            }
            table.insert(lst, item);
        }
        lst = table.concat(lst, " ");
        img = render_text(lst);
        move_image(img, 0, image_surface_properties(argwindow).height + 48);
        show_image(img);
    }
    move_image(argwindow, 10, 38);
    show_image(argwindow);
}

var tick_counter = 500;
pub fn welcome_clock_pulse() V {
    tick_counter = tick_counter - 1;
    if (tick_counter == 0) {
        return shutdown("timeout");
    }
}

pub fn welcome_input(inputtbl: anytype) void {
    if ((inputtbl.kind == "digital") and inputtbl.translated and inputtbl.active) {
        if (symtable[inputtbl.keysym] == "ESCAPE") {
            shutdown();
        }
    }
}

pub fn welcome_display_state(state: []const u8) void {
    if (state == "reset") {
        resize_video_canvas(VRESW, VRESH);
    }
}
