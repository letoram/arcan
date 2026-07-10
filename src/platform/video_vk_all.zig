// Aggregate root for the vk-display video platform object. Lives at
// src/platform/ so video.zig's relative ../agp/*.zig imports stay inside the
// module path (mirrors plat_all.zig).
comptime {
    _ = @import("vk-display/video.zig");
}
