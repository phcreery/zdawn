// crt_stubs.c
//
// The Dawn prebuilt (webgpu_dawn.lib) was compiled with MSVC and links
// against the MSVC C++ runtime (msvcprt.lib / vcruntime.lib). Those
// libraries reference CRT initialization stubs (__vcrt_initialize,
// __acrt_initialize, etc.) that MSVC's link.exe resolves automatically
// via /ALTERNATENAME mappings to no-op stubs in msvcrt.lib.
//
// lld-link (used by Zig) does NOT apply these mappings automatically.
// We embed them here via #pragma comment(linker, ...), which places
// /ALTERNATENAME directives in the object's .drectve section — the
// standard MSVC mechanism for passing linker directives.
//
// Without this, lld-link reports 11 undefined symbols:
// __vcrt_initialize, __vcrt_uninitialize, __vcrt_uninitialize_critical,
// __vcrt_thread_attach, __vcrt_thread_detach, _is_c_termination_complete,
// __acrt_initialize, __acrt_uninitialize, __acrt_uninitialize_critical,
// __acrt_thread_attach, __acrt_thread_detach.

#pragma comment(linker, "/alternatename:__acrt_initialize=__scrt_stub_for_acrt_initialize")
#pragma comment(linker, "/alternatename:__acrt_uninitialize=__scrt_stub_for_acrt_uninitialize")
#pragma comment(linker, "/alternatename:__acrt_uninitialize_critical=__scrt_stub_for_acrt_uninitialize_critical")
#pragma comment(linker, "/alternatename:__acrt_thread_attach=__scrt_stub_for_acrt_thread_attach")
#pragma comment(linker, "/alternatename:__acrt_thread_detach=__scrt_stub_for_acrt_thread_detach")
#pragma comment(linker, "/alternatename:_is_c_termination_complete=__scrt_stub_for_is_c_termination_complete")
#pragma comment(linker, "/alternatename:__vcrt_initialize=__scrt_stub_for_acrt_initialize")
#pragma comment(linker, "/alternatename:__vcrt_uninitialize=__scrt_stub_for_acrt_uninitialize")
#pragma comment(linker, "/alternatename:__vcrt_uninitialize_critical=__scrt_stub_for_acrt_uninitialize_critical")
#pragma comment(linker, "/alternatename:__vcrt_thread_attach=__scrt_stub_for_acrt_thread_attach")
#pragma comment(linker, "/alternatename:__vcrt_thread_detach=__scrt_stub_for_acrt_thread_detach")
// POSIX function names used by Dawn/libraw are underscore-prefixed in MSVC.
#pragma comment(linker, "/ALTERNATENAME:swab=_swab")
#pragma comment(linker, "/ALTERNATENAME:stricmp=_stricmp")
#pragma comment(linker, "/ALTERNATENAME:strnicmp=_strnicmp")

// SetDefaultDllDirectories must be called before any LoadLibraryExW with
// LOAD_LIBRARY_SEARCH_DEFAULT_DIRS, or it returns Error 87. MSVC's CRT
// normally handles this, but our ALTERNATENAME stubs skip CRT init.
// Register a .CRT$XCU initializer that runs before main.
#include <windows.h>
static void __cdecl _init_default_dll_dirs(void) {
    SetDefaultDllDirectories(0x100 | 0x800 | 0x400);
}
#pragma section(".CRT$XCU", read)
__declspec(allocate(".CRT$XCU"))
static void (__cdecl *const _init_dll_dirs_ptr)(void) = _init_default_dll_dirs;
