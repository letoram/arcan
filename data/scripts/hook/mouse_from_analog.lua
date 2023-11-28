local ep = _G[APPLID .. "_input"]

if not ep then
    return
end

-- Mouse position state
local cursor_x, cursor_y = 0, 0

-- Sensitivity factor for analog-to-mouse speed conversion
local sensitivity = 5

-- Setup a cursor
local cursor = fill_surface(8, 8, 0, 127, 0)
image_mask_set(cursor, MASK_UNPICKABLE)
show_image(cursor)
order_image(cursor, 65535)

-- Function to handle analog input and convert to mouse events
_G[APPLID .. "_input"] = function(iotbl, ...)
    -- Check if the input is analog and meant for mouse emulation
    if iotbl.analog and iotbl.mouse_emulation then
        -- Update cursor position based on analog stick data
        cursor_x = cursor_x + (iotbl.samples[1] * sensitivity)
        cursor_y = cursor_y + (iotbl.samples[2] * sensitivity)

        -- Clamp cursor position to screen bounds
        cursor_x = math.max(0, math.min(VRESW, cursor_x))
        cursor_y = math.max(0, math.min(VRESH, cursor_y))

        -- Move cursor image
        move_image(cursor, cursor_x, cursor_y)
    end

    -- Check for digital inputs that represent mouse clicks
    if iotbl.digital and iotbl.mouse_emulation then
        if iotbl.active then
            -- Map the button to a mouse click event (left, right, etc.)
            -- This part depends on how you map your buttons to mouse clicks
            local mouse_event = map_button_to_mouse_event(iotbl.subid)
            trigger_mouse_click(mouse_event) -- Function to handle click event
        end
    end

    -- Pass other events to the original handler
    return ep(iotbl, ...)
end

-- Helper function to map gamepad buttons to mouse events
function map_button_to_mouse_event(button_id)
    -- Example mapping
    if button_id == 1 then
        return "left_click"
    elseif button_id == 2 then
        return "right_click"
    end
    -- Add more mappings as needed
end

-- Helper function to trigger mouse click events
function trigger_mouse_click(event)
    -- Implement mouse click based on the event type
    -- This could be interfacing with an OS-level mouse driver or a custom handler
end
