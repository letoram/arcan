
pub fn texttest() void {
    var red = color_surface(100, 30, 255, 0, 0);
    move_image(red, 10, 10);
    show_image(red);
    var green = color_surface(100, 30, 0, 255, 0);
    move_image(green, 10, 50);
    show_image(green);
    var blue = color_surface(100, 30, 0, 0, 255);
    move_image(blue, 10, 90);
    show_image(blue);
    var t1 = render_text("\\ffonts/default.ttf,24\\bHello World");
    if (t1 and (t1 != 0)) {
        move_image(t1, 120, 10);
        show_image(t1);
    }
    var t2 = render_text("\\ffonts/default.ttf,16 The quick brown fox");
    if (t2 and (t2 != 0)) {
        move_image(t2, 120, 50);
        show_image(t2);
    }
    var t3 = render_text("\\ffonts/default.ttf,12 Small text with spaces");
    if (t3 and (t3 != 0)) {
        move_image(t3, 120, 80);
        show_image(t3);
    }
    var bg = color_surface(350, 40, 30, 30, 30);
    move_image(bg, 120, 130);
    show_image(bg);
    var t4 = render_text("\\ffonts/default.ttf,18\\#ffffff Alpha blend test");
    if (t4 and (t4 != 0)) {
        move_image(t4, 125, 135);
        show_image(t4);
    }
    var t5 = render_text("\\ffonts/default.ttf,14 word1 word2 word3 word4 word5");
    if (t5 and (t5 != 0)) {
        move_image(t5, 120, 180);
        show_image(t5);
    }
    _G._counter = 0;
}

pub fn texttest_clock_pulse() V {
    _G._counter = _G._counter + 1;
    if (_G._counter == 300) {
        return shutdown("text test complete", 0);
    }
}

pub fn texttest_input(iotbl: anytype) V {
    if ((iotbl.kind == "digital") and iotbl.active) {
        return shutdown("input received, exiting", 0);
    }
}
