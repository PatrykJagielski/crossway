/*
 * SPDX-License-Identifier: MIT
 * Based on notpop/steam-on-m1-wine (MIT).
 *
 * Steam's CEF (Chromium 126) paints a black window under Wine on Apple
 * Silicon: ANGLE cannot query the DXGI adapter, falls back to GLES 2.0,
 * disables the GPU and renders its transparent window as black. Running
 * the helper with --disable-gpu --single-process keeps rendering on the
 * CPU inside one process (and keeps TLS out of a separate NetworkService).
 *
 * Install: rename Steam's steamwebhelper.exe to steamwebhelper_real.exe
 * and put this wrapper in its place. Build:
 *   zig cc -target x86_64-windows-gnu -municode -O2 -Wl,--subsystem,windows -o steamwebhelper.exe steamwebhelper-wrapper.c
 */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

#define EXTRA_FLAGS L"--disable-gpu --single-process"
#define REAL_BINARY L"steamwebhelper_real.exe"

/* Arguments Steam passed, without the wrapper's own path. */
static const wchar_t *args_tail(void)
{
    const wchar_t *cmd = GetCommandLineW();
    int in_quotes = 0;
    if (!cmd) return L"";
    while (*cmd) {
        if (*cmd == L'"') in_quotes = !in_quotes;
        else if (*cmd == L' ' && !in_quotes) break;
        ++cmd;
    }
    while (*cmd == L' ') ++cmd;
    return cmd;
}

int wmain(void)
{
    wchar_t real[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, real, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) return 1;
    wchar_t *slash = wcsrchr(real, L'\\');
    if (!slash || (size_t)(slash - real) + 1 + wcslen(REAL_BINARY) >= MAX_PATH) return 1;
    wcscpy(slash + 1, REAL_BINARY);

    const wchar_t *tail = args_tail();
    size_t cap = wcslen(real) + wcslen(EXTRA_FLAGS) + wcslen(tail) + 8;
    wchar_t *cmdline = calloc(cap, sizeof(wchar_t));
    if (!cmdline) return 1;
    _snwprintf(cmdline, cap, L"\"%ls\" %ls %ls", real, EXTRA_FLAGS, tail);

    STARTUPINFOW si = { .cb = sizeof(si) };
    PROCESS_INFORMATION pi = { 0 };
    if (!CreateProcessW(real, cmdline, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
        free(cmdline);
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    free(cmdline);
    return (int)code;
}
