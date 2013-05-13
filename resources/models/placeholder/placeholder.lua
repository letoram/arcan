local matprop = {};

matprop["placeholder"] = { col = {227, 68, 46} };

local model = load_model_generic("placeholder", false, matprop);

model.format_version = 0.1;
model.default_orientation = {roll = 0, pitch = -90, yaw = 0};

return model;
