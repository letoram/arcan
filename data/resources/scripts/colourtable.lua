-- Just a table of some identifiers used by other supportscripts
-- if a theme just overloads this file all the dialog color/font/...
-- can be replaced in a whiff.

local colourtable = {};
colourtable.dialog_border = {r = 0x44, g = 0x44, b = 0xaa, a = 0.9};
colourtable.dialog_window = {r = 0x00, g = 0x00, b = 0xa4, a = 0.9};
colourtable.dialog_cursor = {r = 0xff, g = 0xff, b = 0xff, a = 0.5};

colourtable.font            = [[\ffonts/default.ttf,]]
colourtable.font_size = math.ceil( 8 * (VRESH / 320) );
colourtable.fontstr         = colourtable.font .. colourtable.font_size;
colourtable.label_fontstr   = colourtable.fontstr.. [[\b\#ffffff]];
colourtable.data_fontstr    = colourtable.fontstr .. [[\#ffffff]];
colourtable.hilight_fontstr = colourtable.fontstr .. [[\#00ff00]];
colourtable.alert_fontstr   = colourtable.fontstr .. [[\#ffff00]];
colourtable.notice_fontstr  = colourtable.fontstr .. [[\#00ff00]];

return colourtable;
