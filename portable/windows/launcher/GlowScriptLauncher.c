/* Device-local script entry: a GUI process must suppress the console at creation,
 * before powershell.exe can process -WindowStyle Hidden. Build with /MT and
 * /SUBSYSTEM:WINDOWS; the adjacent script continues to own runtime policy. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <wchar.h>

#ifndef GLOW_START_SCRIPT
#define GLOW_START_SCRIPT L"Start-Glow-ARM64.ps1"
#endif

#define CAPACITY 32768

static BOOL append(wchar_t *output, size_t *used, wchar_t c) {
    if (*used + 1 >= CAPACITY) return FALSE;
    output[(*used)++] = c;
    output[*used] = L'\0';
    return TRUE;
}

/* CommandLineToArgvW/CRT quoting: double backslashes before quotes and at the
 * closing quote. In particular, empty strings and trailing slashes survive. */
static BOOL quote(wchar_t *output, size_t *used, const wchar_t *argument) {
    size_t slashes = 0;
    if (*used && !append(output, used, L' ')) return FALSE;
    if (!append(output, used, L'"')) return FALSE;
    for (;;) {
        wchar_t c = *argument++;
        if (c == L'\\') { ++slashes; continue; }
        if (c == L'"' || !c) slashes *= 2;
        while (slashes) {
            if (!append(output, used, L'\\')) return FALSE;
            --slashes;
        }
        if (!c) return append(output, used, L'"');
        if (c == L'"' && !append(output, used, L'\\')) return FALSE;
        if (!append(output, used, c)) return FALSE;
    }
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous,
                   PWSTR raw_arguments, int show) {
    static wchar_t script[CAPACITY], powershell[CAPACITY], command[CAPACITY];
    const wchar_t *fixed[] = { L"-NoLogo", L"-NoProfile", L"-NonInteractive",
        L"-WindowStyle", L"Hidden", L"-ExecutionPolicy", L"Bypass", L"-File" };
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION child = {0};
    wchar_t **arguments = NULL, *separator;
    DWORD length, attributes, exit_code = 1;
    size_t used = 0, i;
    int count = 0;
    const wchar_t *error = L"Unable to start Glow.";
    (void)instance; (void)previous; (void)raw_arguments; (void)show;

    length = GetModuleFileNameW(NULL, script, CAPACITY);
    if (!length || length >= CAPACITY) goto failed;
    separator = wcsrchr(script, L'\\');
    if (!separator) goto failed;
    separator[1] = L'\0';
    if (wcslen(script) + wcslen(GLOW_START_SCRIPT) >= CAPACITY) goto failed;
    wcscat_s(script, CAPACITY, GLOW_START_SCRIPT);
    attributes = GetFileAttributesW(script);
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        error = L"The adjacent Start-Glow-ARM64.ps1 startup script is missing.";
        goto failed;
    }
    length = GetSystemDirectoryW(powershell, CAPACITY);
    if (!length || length >= CAPACITY - 48) goto failed;
    wcscat_s(powershell, CAPACITY, L"\\WindowsPowerShell\\v1.0\\powershell.exe");
    arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!arguments) goto failed;
    if (!quote(command, &used, powershell)) goto too_long;
    for (i = 0; i < sizeof(fixed) / sizeof(fixed[0]); ++i)
        if (!quote(command, &used, fixed[i])) goto too_long;
    if (!quote(command, &used, script)) goto too_long;
    for (i = 1; i < (size_t)count; ++i)
        if (!quote(command, &used, arguments[i])) goto too_long;
    LocalFree(arguments); arguments = NULL;

    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    /* NULL cwd/environment preserve the shortcut's working directory and the
     * parent environment. No handles or console are inherited. */
    if (!CreateProcessW(powershell, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, NULL, &startup, &child)) goto failed;
    CloseHandle(child.hThread);
    if (WaitForSingleObject(child.hProcess, INFINITE) == WAIT_OBJECT_0)
        GetExitCodeProcess(child.hProcess, &exit_code);
    CloseHandle(child.hProcess);
    if (!exit_code) return 0;
    error = L"The Glow startup script failed. The existing startup script and configuration have been preserved.";
    goto failed;
too_long:
    error = L"The Glow startup command exceeds the Windows command-line limit.";
failed:
    if (arguments) LocalFree(arguments);
    MessageBoxW(NULL, error, L"Neovide Glow", MB_OK | MB_ICONERROR);
    return (int)exit_code;
}
