# Sourced only by explicitly requested Windows TeX setup. No top-level writes.
function Set-GlowTeXFontDirectories {
    param([Parameter(Mandatory=$true)][string]$BinRoot,
        [Parameter(Mandatory=$true)][string]$RunRoot,
        [Parameter(Mandatory=$true)][scriptblock]$RefreshCache)
    $root=Split-Path -Parent (Split-Path -Parent ([IO.Path]::GetFullPath($BinRoot)))
    $configRoot=Join-Path $root 'texmf-var\fonts\conf'
    $config=Join-Path $configRoot 'fonts.conf'
    $cache=Join-Path $BinRoot 'fc-cache.exe'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf) -or -not (Test-Path -LiteralPath $cache -PathType Leaf)) {
        return [pscustomobject]@{state='not_applicable';changed=$false}
    }
    # Use the standard local extension point; preserve the distribution's own
    # fonts.conf, including custom rules and relocation-generated content.
    [xml]$xml=[IO.File]::ReadAllText($config)
    $includes=@($xml.SelectNodes('/fontconfig/include')|Where-Object {$_.InnerText.Trim() -eq 'conf.d'})
    if ($includes.Count -eq 0) { return [pscustomobject]@{state='not_applicable';changed=$false} }
    $directories=@((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'),
        (Join-Path $root 'texmf-dist\fonts\opentype'),(Join-Path $root 'texmf-dist\fonts\truetype'))
    $directories=@($directories|Where-Object {Test-Path -LiteralPath $_ -PathType Container}|Select-Object -Unique)
    $marker='<!-- Neovide Glow: local TeX font directories v1 -->'
    $lines=@('<?xml version="1.0" encoding="UTF-8"?>',$marker,'<fontconfig>')
    foreach ($directory in $directories) {
        $lines+='  <dir>'+[Security.SecurityElement]::Escape($directory.Replace('\','/'))+'</dir>'
    }
    $lines+='</fontconfig>'
    $content=($lines -join "`n")+"`n"
    $destination=Join-Path $configRoot 'conf.d\99-neovide-glow-local-fonts.conf'
    $before=$null; $backup=$null
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $before=[IO.File]::ReadAllText($destination)
        if (-not $before.Contains($marker)) { throw ('Existing unowned font configuration preserved: '+$destination) }
    }
    $changed=$before -cne $content
    if ($changed) {
        $null=New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
        $null=New-Item -ItemType Directory -Path $RunRoot -Force
        if ($null -ne $before) {
            $backup=Join-Path $RunRoot ('fontconfig.before-'+[Guid]::NewGuid().ToString('N')+'.conf')
            Copy-Item -LiteralPath $destination -Destination $backup
        }
        $temporary=$destination+'.preparing-'+[Guid]::NewGuid().ToString('N')
        try {
            [IO.File]::WriteAllText($temporary,$content,(New-Object Text.UTF8Encoding($false)))
            if (Test-Path -LiteralPath $destination) {
                [IO.File]::Replace($temporary,$destination,[System.Management.Automation.Language.NullString]::Value)
            } else { [IO.File]::Move($temporary,$destination) }
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
        & $RefreshCache $cache
    }
    [pscustomobject]@{state='ready';changed=$changed;path=$destination;backup=$backup;directories=$directories;
        sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()}
}
