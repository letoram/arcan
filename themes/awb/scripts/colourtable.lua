local colourtable = {};

colourtable.dialog_border = {r = 225,  g = 225,  b = 225,  a = 1.0}; 
colourtable.dialog_window = {r = 0,    g = 84,   b = 169,  a = 1.0};
colourtable.dialog_cursor = {r = 0xff, g = 0xff, b = 0xff, a = 0.5};
colourtable.dialog_caret  = {r = 253,  g = 130,  b = 10,   a = 1.0};
colourtable.dialog_sbar   = {r = 255,  g = 255,  b = 255,  a = 1.0}; 
colourtable.bgcolor       = {r = 0,    g = 85,   b = 169,  a = 1.0};

colourtable.font            = [[\ffonts/default.ttf,]]
colourtable.font_size = math.ceil( 8 * (VRESH / 320) );
colourtable.fontstr         = colourtable.font .. colourtable.font_size;
colourtable.label_fontstr   = colourtable.fontstr .. [[\b\#ffffff]];
colourtable.data_fontstr    = colourtable.fontstr .. [[\#ffffff]];
colourtable.hilight_fontstr = colourtable.fontstr .. [[\#00ff00]];
colourtable.alert_fontstr   = colourtable.fontstr .. [[\#ffff00]];
colourtable.notice_fontstr  = colourtable.fontstr .. [[\#00ff00]];

return colourtable;
