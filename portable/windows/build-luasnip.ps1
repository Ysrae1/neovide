# Build-worker only. clang-cl emits an x64 MSVC-ABI DLL against bundled LuaJIT.
# The frozen LuaSnip loader intentionally names that PE DLL with a .so suffix.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Neovim
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$Source = (Resolve-Path -LiteralPath $Source).Path
$Neovim = (Resolve-Path -LiteralPath $Neovim).Path
$compiler = (Get-Command clang-cl -ErrorAction Stop).Source
$dumpbin = (Get-Command dumpbin -ErrorAction Stop).Source
$librarian = (Get-Command lib.exe -ErrorAction Stop).Source
if ($env:VSCMD_ARG_TGT_ARCH -and $env:VSCMD_ARG_TGT_ARCH -ne 'x64') { throw 'LuaSnip requires an x64 MSVC developer environment.' }
$nvimExe = Join-Path $Neovim 'bin/nvim.exe'
$luaDll = Join-Path $Neovim 'bin/lua51.dll'
$include = Join-Path $Source 'deps/lua51_include'
$regexp = Join-Path $Source 'deps/jsregexp'
foreach ($path in @($nvimExe, $luaDll, (Join-Path $include 'lua.h'), (Join-Path $regexp 'jsregexp.c'), (Join-Path $regexp 'jsregexp.lua'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Frozen LuaSnip build input is missing: $path" }
}
$build = Join-Path $Source ('deps/.windows-jsregexp-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $build | Out-Null
$savedSource = $env:GLOW_LUASNIP_SOURCE
try {
    $headers = & $dumpbin /nologo /headers $luaDll
    if ($LASTEXITCODE -ne 0 -or -not (($headers -join "`n") -match '(?im)\b8664\s+machine')) { throw 'Bundled LuaJIT DLL is not an x64 PE image.' }
    $listing = & $dumpbin /nologo /exports $luaDll
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the bundled LuaJIT exports.' }
    $exports = @($listing | ForEach-Object {
        if ($_ -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(lua(?:L)?_[A-Za-z0-9_]+)\b') { $Matches[1] }
    } | Sort-Object -Unique)
    foreach ($required in @('lua_gettop', 'lua_newuserdata', 'lua_objlen', 'lua_pcall', 'luaL_register')) {
        if ($exports -notcontains $required) { throw "Bundled LuaJIT does not export the required Lua 5.1 ABI: $required" }
    }
    $definition = Join-Path $build 'lua51.def'
    $importLibrary = Join-Path $build 'lua51.lib'
    @('LIBRARY lua51.dll', 'EXPORTS') + $exports | Set-Content -LiteralPath $definition -Encoding Ascii
    & $librarian /nologo /machine:x64 ("/def:" + $definition) ("/out:" + $importLibrary)
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the LuaJIT import library from its real exports.' }
    $objects = @()
    foreach ($relative in @('jsregexp.c', 'libregexp/cutils.c', 'libregexp/libregexp.c', 'libregexp/libunicode.c')) {
        $file = Join-Path $regexp $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Frozen jsregexp source is missing: $relative" }
        $object = Join-Path $build (($relative -replace '[/\\]', '-') + '.obj')
        & $compiler /nologo /c /TC /std:c11 /O2 /MT /D_CRT_SECURE_NO_WARNINGS /Dstrdup=_strdup /Dalloca=_alloca /FImalloc.h ("/I" + $include) ("/Fo" + $object) $file
        if ($LASTEXITCODE -ne 0) { throw "Windows jsregexp compilation failed: $relative" }
        $objects += $object
    }
    $temporaryDll = Join-Path $build 'luasnip-jsregexp.so'
    & $compiler /nologo /LD /MT @objects $importLibrary /link /MACHINE:X64 /EXPORT:luaopen_jsregexp_core ("/OUT:" + $temporaryDll) ("/IMPLIB:" + (Join-Path $build 'jsregexp.lib'))
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryDll -PathType Leaf)) { throw 'Windows jsregexp DLL linking failed.' }
    Copy-Item -LiteralPath $temporaryDll -Destination (Join-Path $Source 'deps/luasnip-jsregexp.so')
    Copy-Item -LiteralPath (Join-Path $regexp 'jsregexp.lua') -Destination (Join-Path $Source 'lua/luasnip-jsregexp.lua')
    $smoke = Join-Path $build 'smoke.lua'
    @'
vim.opt.runtimepath:append(assert(vim.env.GLOW_LUASNIP_SOURCE))
local compile = require('luasnip.util.jsregexp')
assert(type(compile) == 'function', 'Frozen jsregexp PE DLL did not load through the actual LuaSnip loader')
local expression = assert(compile('(?<word>glow)', 'i'))
local match = assert(expression:match('Glow'))
assert(match[0] == 'Glow' and match.groups.word == 'Glow', 'Windows jsregexp capture semantics failed')
local invalid = compile('(', '')
assert(invalid == nil, 'Invalid regex must return a safe compile error')
print('Native Windows LuaSnip jsregexp ABI and named captures passed')
vim.cmd('qa!')
'@ | Set-Content -LiteralPath $smoke -Encoding Ascii
    $env:GLOW_LUASNIP_SOURCE = $Source
    & $nvimExe --headless --noplugin -u NONE -i NONE -l $smoke
    if ($LASTEXITCODE -ne 0) { throw 'Bundled Neovim could not load the compiled Windows LuaSnip module.' }
    Write-Output 'Built lua/luasnip-jsregexp.lua and deps/luasnip-jsregexp.so (native Windows x64 PE DLL).'
}
finally {
    $env:GLOW_LUASNIP_SOURCE = $savedSource
    if (Test-Path -LiteralPath $build) { Remove-Item -LiteralPath $build -Recurse -Force }
}
