-- define_rendertarget
-- @short: Create an offscreen rendering pipeline (render to texture).
-- @inargs: dstvid, vidary, detacharg, scalearg
-- @outargs:
-- @longdescr: This function creates a separate rendering pipeline populated with the set of VIDs passed as the table *vidary*. *detacharg* can be set to either RENDERTARGET_DETACH or RENDERTARGET_NODETACH and controls if the VIDs in *vidary* should be disconnected from the standard output pipeline or not. Lastly *scalearg* can be set to either RENDERTARGET_SCALE or RENDERTARGET_NOSCALE which comes into play when the standard output dimensions (VRESW, VRESH) are different from the VID that will be renderered to. With RENDERTARGET_SCALE set, the pipeline transform will be changed to scale all objects to fit, otherwise clipping may be applied.
-- @group: targetcontrol
-- @cfunction: arcan_lua_renderset
-- @note: There is a delay of at least one frame from creation up until the dstvid storage is updated. Rendertarget_forceupdate can be used to perform an additional rendering pass for the specific target alone. This is mostly useful for functions that rely on rendertarget readback, e.g. save_screenshot
-- @related: define_recordtarget, fill_surface
-- @flags:
#ifdef MAIN
-- this function creates two intermediate surfaces that applies
-- horiz-vert separated gaussian blur along with regular texture filtering

function setupblur(targetw, targeth)
    local blurshader_h = load_shader("shaders/fullscreen/default.vShader",
 "shaders/fullscreen/gaussianH.fShader",
"blur_horiz", {});

    local blurshader_v = load_shader("shaders/fullscreen/default.vShader",
"shaders/fullscreen/gaussianV.fShader",
"blur_vert", {});

    local blurw = targetw * 0.4;
    local blurh = targeth * 0.4;

    shader_uniform(blurshader_h, "blur", "f", PERSIST, 1.0 / blurw);
    shader_uniform(blurshader_v, "blur", "f", PERSIST, 1.0 / blurh);
    shader_uniform(blurshader_h, "ampl", "f", PERSIST, 1.2);
    shader_uniform(blurshader_v, "ampl", "f", PERSIST, 1.4);

    local blur_hbuf = fill_surface(blurw, blurh, 1, 1, 1, blurw, blurh);
    local blur_vbuf = fill_surface(targetw, targeth, 1, 1, 1, blurw, blurh);

    image_shader(blur_hbuf, blurshader_h);
    image_shader(blur_vbuf, blurshader_v);

    show_image(blur_hbuf);
    show_image(blur_vbuf);

    return blur_hbuf, blur_vbuf;
end

function main()
local blurw, blurh = setupblur(VRESW, VRESH);

-- load an image, create a copy of it and attach as input to the first blur pass
source = load_image("fullscreen.png");
resize_image(source, VRESW, VRESH);
show_image(source);
define_rendertarget(blurw, {instance_image(source)}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- then apply the output from that one to a second blur pass
define_rendertarget(blurh, {blurw}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- and finally draw it as an overlay to the input image
blend_image(blurh, 0.99);
force_image_blend(blurh, BLEND_ADD);
order_image(blurh, max_current_image_order() + 1);
end
#endif
