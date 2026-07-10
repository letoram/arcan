
pub fn vktest() void {
    var r = color_surface(200, 200, 255, 0, 0);
    move_image(r, 50, 50);
    show_image(r);
    var t = render_text("\\ffonts/default.ttf,24\\bVulkan Test");
    move_image(t, 50, 280);
    show_image(t);
    var g = color_surface(150, 150, 0, 255, 0);
    blend_image(g, 0.5);
    move_image(g, 100, 100);
    show_image(g);
    order_image(g, 2);
    var b = color_surface(100, 300, 0, 0, 255);
    move_image(b, 600, 50);
    show_image(b);
    var t2 = render_text("\\ffonts/default.ttf,18 Viewport / Scissor Test");
    move_image(t2, 50, 330);
    show_image(t2);
    var y = color_surface(50, 50, 255, 255, 0);
    move_image(y, 375, 275);
    show_image(y);
    order_image(y, 3);
    _G._vktest_counter = 0;
}

pub fn vktest_clock_pulse() V {
    _G._vktest_counter = _G._vktest_counter + 1;
    if (_G._vktest_counter == 120) {
        save_screenshot("vktest_output.png");
    }
    if (_G._vktest_counter == 125) {
        return shutdown("done", EXIT_SUCCESS);
    }
}
