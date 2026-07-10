# arcan cross-platform build & run plan

**Goal:** from a single **aarch64 Linux** host (this Asahi/Fedora box), produce
and run/test `arcan` for **Linux, macOS, and Windows**. All builds originate on
this Linux box; the toolchain differs per target.

## Targets, toolchains, run paths

| Target  | Binary triple          | Build toolchain (on this Linux host)                 | Backend | Run / test                                             | Status |
|---------|------------------------|------------------------------------------------------|---------|--------------------------------------------------------|--------|
| Linux   | `aarch64-linux-musl`   | `giz` (aarch64), native                              | self-hosted | native on this box                                 | ✅ done, green |
| macOS   | `aarch64-macos`        | `giz` (aarch64), cross-compile                       | LLVM    | `humboldt` (M2 Ultra, macOS 26.3) over ssh             | ✅ done; `welcome` + `durden` both run |
| Windows | `x86_64-windows-gnu`   | `giz` (aarch64), **cross-compile** (like macOS)      | LLVM    | **Proton (wine) under FEX** on this box, GPU Vulkan via FEX thunk | 🚧 **links** (x86_64 + aarch64 PE); run-phase next |

### Windows build: aarch64-giz cross-compile (FEX is run-only)
- **The aarch64 `giz` cross-compiles `x86_64-windows-gnu` directly** (rc=0,
  82MB PE32+ x86-64). The LLVM-backend varargs `@compileError("disabled due to
  miscompilations")` wall we feared lives only in the **frameserver
  chainloader / afsrv_* / a12-net** subsystems — all gated off on windows
  (windows uses `CreateProcess`, not the posix fork/exec model). The compositor
  path has no such varargs bodies. **No x86_64-zig-under-FEX toolchain, no
  C-shims.** `aarch64-windows-gnu` also links (PE32+ ARM64), kept as secondary.
- FEX/muvm/Proton is the **run** path only: the native **x86_64-windows** PE
  runs under **Proton (wine) on FEX** x86-64 emulation, FEX's Vulkan guest-thunk
  (`/usr/share/fex-emu/GuestThunks/libvulkan-guest.so`) giving **GPU** Vulkan
  against the host Asahi driver. **No QEMU/Windows-VM needed.**

## Cross-cutting principles (all targets)
- **dlopen everything, never link subsystem libraries directly.** Only the OS
  base is referenced: `libc`(Linux) / `libSystem`(macOS) / `kernel32`(Windows).
  Everything else — Vulkan loader, window system (xcb / Cocoa / user32+gdi32),
  sockets — is resolved at runtime via the per-OS `zig_dlopen` backend
  (`zig_dlopen_{linux,macos,windows}.zig`) → `LoadLibrary`/`dlopen`.
- **Every OS difference is `comptime`-gated** so each target folds out the other
  targets' code (and their symbol references).
- **LLP64**: Windows `c_long` is 32-bit on every Windows arch. The pointer-width
  fixes (bitcast intermediates, `ptrdiff_t`/`size_t` typedefs, `size_t`-family
  extern decls) are arch-independent and already landed; LP64-neutral (Linux
  verified green).

## Per-target work

### Linux — ✅ done
Native `giz build`. Self-hosted backend. Ships.

### macOS — ✅ done: `welcome` + `durden` both run (OSX agent)
- Done: full Cocoa/CAMetalLayer + `VK_KHR_metal_surface` path, vulkan-1 loader
  (`.dylib` names), shaderc loader (`.dylib` names), giz `shmifPanicEmit`
  Windows/OS-safe, ABI gating.
- FIXED + merged (5510b1fe): SIGSYS (shmemop.zig memfd_create→shm_open on
  non-linux), and the durden font probe (arcan_main.zig: add `default.ttf`
  candidate; SYS_FONT already resolves binary-relative via unix_find).
- FIXED + merged: **font-fd double-close** (`arcan_ttf.zig` e6b89b37) —
  `TTF_OpenFontFD` recorded an fd `TTF_OpenFontIndexRW(freesrc=1)` had already
  `fclose`d; the recycled number was later closed again, killing the live
  default-font fd → `fstat(EBADF)` → the load-bearing `do_fstat_fd` panic
  (untouched). Store an independent `dup` (also un-breaks `TTF_ReplaceFont`).
  And **0×0 Metal texture** (`vk.zig` bbde6ea4) — a freshly-spawned
  frameserver's 0×0 store made MoltenVK hard-assert on a zero-extent `VkImage`;
  clamp to 1×1 + skip zero-byte upload (all Vulkan backends, not os-gated).
  Both were **general engine bugs** macOS surfaced first.
- `welcome` + `durden` both reach the run loop and render on humboldt.

### Windows — 🚧 x86_64, built under FEX, run under Proton (Windows agent)
Build:
1. **Toolchain under FEX**: obtain an **x86_64 zig 0.15.2** that runs under
   `FEXBash`/`muvm` (stock x86_64 zig, or an x86_64 build of giz, or patch the
   fork's varargs `@compileError`). Build `x86_64-windows-gnu` with it.
2. **Substrate** (dlopen-based, via `zig_dlopen_windows`): mmap→CreateFileMapping,
   pthread→Win32 threads, poll→WSAPoll, sockets→Winsock, socketpair→loopback,
   fd-passing→DuplicateHandle. `fork` = stub for a first `welcome` boot
   (welcome spawns no frameservers). Reference `/home/x/cosmopolitan`.
3. Remaining build errors: `vk.zig` pointer-constant, fd-as-HANDLE (route
   `std.posix` fd-ops → int-fd libc), residual `c_ulong/c_long`, `void` std.c
   networking types. Prioritize the **compositor** path (no a12/net needed).
4. Win32 window + `VK_KHR_win32_surface` + `vulkan-1.dll` loader — scaffolding
   already written and compiling.

Run:
5. Install **Proton** (via the Asahi `fex-steam` launcher / Steam bootstrap, or
   standalone Proton). `muvm` + `FEXBash` present at `/usr/bin`.
6. `FEXBash -c 'wine <prefix>/…/arcan.exe -w 1280 -h 720 welcome'` (under `muvm`
   if 4K-page issues). Confirm `welcome` reaches the run loop and renders; GPU
   Vulkan via the FEX thunk (software `vulkan-1`/lavapipe fallback in the prefix
   if the guest ICD is absent).

QEMU Windows-on-ARM64 VM: **retired to fallback** (kept documented under
`/home/x/win11-arm64/`). Proton+FEX is the primary run path.

## Agent structure (parallel, I coordinate)
- **OSX agent** — worktree; fixes the two durden bugs; builds+deploys+tests on humboldt.
- **Windows agent** — worktree; x86_64-windows build under FEX toolchain + Proton run.
- **(retiring) QEMU agent** — leaves a documented fallback VM, then stops.
- **Me** — coordinate, **merge both worktrees** (mostly disjoint: macOS-gated vs
  windows-gated; watch `paths.zig` overlap), talk to the user.

## Open risks
- Does the arcan tree build with a **stock** x86_64 zig (fork-std features), or
  must we build/patch an x86_64 giz? (Windows agent to determine.)
- Proton not yet installed (Steam not bootstrapped).
- Whether Proton+FEX gives GPU or only software Vulkan for arcan's compositor.

## Current source state
WIP committed locally at `595c2666` (not pushed): windows scaffolding + macOS
shaderc/loader fixes; Linux/macOS green, Windows target incomplete. Both agents
branch worktrees from this commit.
