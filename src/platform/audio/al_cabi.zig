// Hand-written replacement for openal.zig's POSIX @cImport block.
// The no-LLVM self-hosted fork can't run @cImport at all (needs libclang
// or aro with C codegen), so the original `@cImport({ AL/al.h, AL/alc.h,
// arcan_shmif.h, arcan_video.h, … })` is unusable.
//
// This file re-exports the arcan-internal types/constants from the
// existing hand-ported Zig modules (arcan_zig_types, shmif_types,
// posix_libc) under the same names the @cImport produced, plus the
// AL / ALC API: type aliases, constant values (from system headers),
// and `extern "c" fn` declarations that the linker resolves against the
// dl_openal.zig shim (runtime-loaded libopenal.so.1).

const arcan = @import("arcan");
const shmif_types = @import("shmif_types");
const posix_libc = @import("posix");

// ── AL/ALC primitive type aliases ───────────────────────────────────

pub const ALuint = c_uint;
pub const ALint = c_int;
pub const ALenum = c_int;
pub const ALfloat = f32;
pub const ALchar = u8;
pub const ALvoid = anyopaque;
pub const ALboolean = u8;
pub const ALsizei = c_int;

pub const ALCdevice = opaque {};
pub const ALCcontext = opaque {};
pub const ALCchar = u8;
pub const ALCint = c_int;
pub const ALCboolean = u8;
pub const ALCsizei = c_int;
pub const ALCuint = c_uint;
pub const ALCenum = c_int;

// ── AL / ALC constants (values from /usr/include/AL/*.h) ─────────────

pub const AL_NONE: ALenum = 0;
pub const AL_FALSE: ALboolean = 0;
pub const AL_TRUE: ALboolean = 1;
pub const AL_POSITION: ALenum = 0x1004;
pub const AL_VELOCITY: ALenum = 0x1006;
pub const AL_GAIN: ALenum = 0x100A;
pub const AL_ORIENTATION: ALenum = 0x100F;
pub const AL_SOURCE_STATE: ALenum = 0x1010;
pub const AL_PLAYING: ALenum = 0x1012;
pub const AL_BUFFERS_PROCESSED: ALenum = 0x1016;
pub const AL_NO_ERROR: ALenum = 0;
pub const AL_INVALID_NAME: ALenum = 0xA001;
pub const AL_INVALID_ENUM: ALenum = 0xA002;
pub const AL_INVALID_VALUE: ALenum = 0xA003;
pub const AL_INVALID_OPERATION: ALenum = 0xA004;
pub const AL_OUT_OF_MEMORY: ALenum = 0xA005;
pub const AL_FORMAT_MONO8: ALenum = 0x1100;
pub const AL_FORMAT_MONO16: ALenum = 0x1101;
pub const AL_FORMAT_STEREO8: ALenum = 0x1102;
pub const AL_FORMAT_STEREO16: ALenum = 0x1103;
pub const AL_SOURCE_SPATIALIZE_SOFT: ALenum = 0x1214; // AL_SOFT_source_spatialize

pub const ALC_FALSE: ALCenum = 0;
pub const ALC_TRUE: ALCenum = 1;
pub const ALC_FREQUENCY: ALCenum = 0x1007;
pub const ALC_CAPTURE_DEVICE_SPECIFIER: ALCenum = 0x310;
pub const ALC_CAPTURE_SAMPLES: ALCenum = 0x312;
pub const ALC_ALL_DEVICES_SPECIFIER: ALCenum = 0x1013;
pub const ALC_HRTF_SOFT: ALCenum = 0x1992; // ALC_SOFT_HRTF

// ── AL / ALC function declarations — linked against dl_openal.zig ────
// dl_openal.zig provides matching `export fn <name>() callconv(.c)` shims
// that resolve to the real library via zig_dlopen on first use.

pub extern "c" fn alGetError() ALenum;
pub extern "c" fn alGetEnumValue(name: [*c]const ALchar) ALenum;
pub extern "c" fn alGenBuffers(n: ALsizei, buffers: [*c]ALuint) void;
pub extern "c" fn alDeleteBuffers(n: ALsizei, buffers: [*c]const ALuint) void;
pub extern "c" fn alBufferData(buf: ALuint, fmt: ALenum, data: ?*const ALvoid, size: ALsizei, srate: ALsizei) void;
pub extern "c" fn alGenSources(n: ALsizei, sources: [*c]ALuint) void;
pub extern "c" fn alDeleteSources(n: ALsizei, sources: [*c]const ALuint) void;
pub extern "c" fn alSourcei(source: ALuint, param: ALenum, value: ALint) void;
pub extern "c" fn alSourcef(source: ALuint, param: ALenum, value: ALfloat) void;
pub extern "c" fn alSourcefv(source: ALuint, param: ALenum, values: [*c]const ALfloat) void;
pub extern "c" fn alSource3f(source: ALuint, param: ALenum, v1: ALfloat, v2: ALfloat, v3: ALfloat) void;
pub extern "c" fn alGetSourcei(source: ALuint, param: ALenum, out: [*c]ALint) void;
pub extern "c" fn alSourcePlay(source: ALuint) void;
pub extern "c" fn alSourceStop(source: ALuint) void;
pub extern "c" fn alSourceQueueBuffers(source: ALuint, nb: ALsizei, buffers: [*c]const ALuint) void;
pub extern "c" fn alSourceUnqueueBuffers(source: ALuint, nb: ALsizei, buffers: [*c]ALuint) void;
pub extern "c" fn alListenerf(param: ALenum, value: ALfloat) void;
pub extern "c" fn alListenerfv(param: ALenum, values: [*c]const ALfloat) void;
pub extern "c" fn alListener3f(param: ALenum, v1: ALfloat, v2: ALfloat, v3: ALfloat) void;

pub extern "c" fn alcOpenDevice(name: [*c]const ALCchar) ?*ALCdevice;
pub extern "c" fn alcCreateContext(device: ?*ALCdevice, attrs: [*c]const ALCint) ?*ALCcontext;
pub extern "c" fn alcMakeContextCurrent(ctx: ?*ALCcontext) ALCboolean;
pub extern "c" fn alcDestroyContext(ctx: ?*ALCcontext) void;
pub extern "c" fn alcGetCurrentContext() ?*ALCcontext;
pub extern "c" fn alcGetIntegerv(device: ?*ALCdevice, param: ALCenum, size: ALCsizei, out: [*c]ALCint) void;
pub extern "c" fn alcGetProcAddress(device: ?*ALCdevice, name: [*c]const ALCchar) ?*anyopaque;
pub extern "c" fn alcGetString(device: ?*ALCdevice, param: ALCenum) [*c]const ALCchar;
pub extern "c" fn alcIsExtensionPresent(device: ?*ALCdevice, name: [*c]const ALCchar) ALCboolean;
pub extern "c" fn alcCaptureOpenDevice(name: [*c]const ALCchar, freq: ALCuint, fmt: ALCenum, bufsize: ALCsizei) ?*ALCdevice;
pub extern "c" fn alcCaptureCloseDevice(device: ?*ALCdevice) ALCboolean;
pub extern "c" fn alcCaptureStart(device: ?*ALCdevice) void;
pub extern "c" fn alcCaptureStop(device: ?*ALCdevice) void;
pub extern "c" fn alcCaptureSamples(device: ?*ALCdevice, buf: ?*ALCvoid, samples: ALCsizei) void;

pub const ALCvoid = anyopaque;

// ── arcan types / constants (re-exported) ────────────────────────────

pub const arcan_aobj_id = arcan.arcan_aobj_id;
pub const arcan_vobj_id = arcan.arcan_vobj_id;
pub const arcan_errc = arcan.arcan_errc;
pub const arcan_vobject = arcan.arcan_vobject;
pub const data_source = arcan.data_source;
pub const map_region = arcan.map_region;

// struct_arcan_event / _evctx come out of @cImport as `struct T` spellings;
// mirror that here so existing `c.struct_arcan_event` usage compiles.
pub const struct_arcan_event = shmif_types.arcan_event;
pub const struct_arcan_evctx = arcan.struct_arcan_evctx;

// `struct platform_audio_cfg` — defined in audio_platform.h. Layout must
// match the C struct (1 + 1 + 6 pad + 8 = 16 bytes).
pub const struct_platform_audio_cfg = extern struct {
    hrtf: bool,
    scan: bool,
    out: [*c]const u8,
};

pub const ARCAN_OK = arcan.ARCAN_OK;
pub const ARCAN_ERRC_NO_SUCH_OBJECT = arcan.ARCAN_ERRC_NO_SUCH_OBJECT;
pub const ARCAN_ERRC_BAD_RESOURCE = arcan.ARCAN_ERRC_BAD_RESOURCE;
// arcan_zig_types doesn't export ARCAN_ERRC_NOTREADY (yet); value matches
// arcan_general.h. Fold this back into arcan_zig_types when convenient.
pub const ARCAN_ERRC_NOTREADY: arcan.arcan_errc = -10;
pub const ARCAN_ERRC_OUT_OF_SPACE = arcan.ARCAN_ERRC_OUT_OF_SPACE;

pub const ARCAN_VIDEO_WORLDID = arcan.ARCAN_VIDEO_WORLDID;
pub const ARCAN_EID = arcan.ARCAN_EID;
pub const BADFD = arcan.BADFD;

pub const ARCAN_SHMIF_ABUFC_LIM = shmif_types.ARCAN_SHMIF_ABUFC_LIM;
pub const ARCAN_SHMIF_ACHANNELS = shmif_types.ARCAN_SHMIF_ACHANNELS;
pub const ARCAN_SHMIF_SAMPLERATE = shmif_types.ARCAN_SHMIF_SAMPLERATE;

pub const ARCAN_MEM_ABUFFER = arcan.ARCAN_MEM_ABUFFER;
pub const ARCAN_MEM_ATAG = arcan.ARCAN_MEM_ATAG;
pub const ARCAN_MEM_BZERO = arcan.ARCAN_MEM_BZERO;
pub const ARCAN_MEM_SENSITIVE = arcan.ARCAN_MEM_SENSITIVE;
pub const ARCAN_MEM_STRINGBUF = arcan.ARCAN_MEM_STRINGBUF;
pub const ARCAN_MEMALIGN_NATURAL = arcan.ARCAN_MEMALIGN_NATURAL;
pub const ARCAN_MEMALIGN_PAGE = arcan.ARCAN_MEMALIGN_PAGE;

// AOBJ_* — kind enum values from arcan_audioint.h
pub const AOBJ_INVALID: c_int = 0;
pub const AOBJ_STREAM: c_int = 1;
pub const AOBJ_SAMPLE: c_int = 2;
pub const AOBJ_FRAMESTREAM: c_int = 3;
pub const AOBJ_CAPTUREFEED: c_int = 4;

pub const EVENT_AUDIO = shmif_types.EVENT_AUDIO;
pub const EVENT_AUDIO_PLAYBACK_FINISHED: c_int = 0; // arcan_shmif_event.h enum
pub const EVENT_AUDIO_OBJECT_GONE: c_int = 1;

// ── libc ────────────────────────────────────────────────────────────

pub const strdup = posix_libc.strdup;
