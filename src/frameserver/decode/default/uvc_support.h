#ifndef HAVE_UVC_SUPPORT
/*
 * A number of interesting parameters here (not all implemented in uvc,
 * or at least marked as todo in spec - it's a complex specification to follow):
 *
 *  [scanning mode: interlaced or progressive (uvc_xxx_scanning_mode]]
 *  [auto-exposure mode: manual / auto / shutter / aperture uvc_xxx_ae_mode]
 *  [auto-exposure priority: tradeoff framerate vs exposure]
 *  [exposure time: abs / rel, affects framerate]
 *  [focus distance: abs / rel optimal focus distance, uvc_xxx_focus_abs/rel]
 *  [focus range: auto focus control]
 *  [iris: abs / rel]
 *  [zoom]
 *  [pan/tilt]
 *  [roll]
 *  [privacy]
 *  [digital window: for cropping?]
 *  [backlight compensation]
 *  [contrast]
 *  [brightness]
 *  [gain]
 *  [power line frequence, for filtering?]
 *  [hue]
 *  [saturation]
 *  [sharpness]
 *  [gamma]
 *  [white balance]
 *  [digital multiplier]
 *  [analog video standard]
 *  [input select]
 *  + the option to use extra device specific controls (needed for VR HMDs)
 */

/*
 * Takes precedence over the libvlc- or other decoding facilities, return true
 * if the control loop was taken over (and exited) by the uvc support
 */
bool uvc_support_activate(struct arcan_shmif_cont* cont, struct arg_arr* args);

/*
 * Just add text help output for the UVC specific arguments
 */
void uvc_append_help(FILE*);

#endif
