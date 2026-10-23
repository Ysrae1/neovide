#requires -Version 5.1
<# Native Python-probe regression. Compile and run test-owned executables only;
   no Python/package installation, downloads, registry writes, user config or GUI.
   The receipt binds the actual source bytes under test. #>
param(
    [string]$SourceRoot=(Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory=$true)][string]$WorkRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This test requires native Windows PowerShell.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Use a fresh Python-probe WorkRoot.' }
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot)
$null=New-Item -ItemType Directory -Path $WorkRoot
$utf8=New-Object Text.UTF8Encoding($false)
$receipt=@{schema_version=1;state='running';checks=@();source=(Join-Path $SourceRoot 'portable\windows\Setup-Dependencies.ps1')}
$receipt.source_sha256=(Get-FileHash -LiteralPath $receipt.source -Algorithm SHA256).Hash.ToLowerInvariant()
function Save-Receipt {
    [IO.File]::WriteAllText((Join-Path $WorkRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 12),$utf8)
}
function Pass([string]$Name) {
    $receipt.checks+=@($Name)
    Save-Receipt
    Write-Output ('PASS '+$Name)
}
function Require([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Import-Definition([string]$Path,[string]$Name) {
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors|Out-String) }
    $definitions=@($ast.FindAll({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    },$true))
    if ($definitions.Count -ne 1) { throw ('Expected one trusted definition: '+$Name) }
    return $definitions[0].Extent.Text
}

# Import definitions only: the setup's candidate discovery, package helpers and
# top-level install path must never execute in this regression.
foreach ($name in @('Quote-Argument','Probe-Python','Assert-NotebookProbeKnown')) {
    . ([scriptblock]::Create((Import-Definition $receipt.source $name)))
}

$fakeSource=@'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class GlowPythonProbeFixture {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    private struct StartupInfo {
        public int cb;
        public string reserved, desktop, title;
        public int x, y, xSize, ySize, xChars, yChars, fill, flags;
        public short show, reservedBytes;
        public IntPtr reservedPointer, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInfo {
        public IntPtr process, thread;
        public int processId, threadId;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateProcess(
        string app, StringBuilder command, IntPtr processAttributes,
        IntPtr threadAttributes, bool inheritHandles, uint flags,
        IntPtr environment, string directory, ref StartupInfo startup,
        out ProcessInfo info);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetStdHandle(int number);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
    private static string Json(string value) {
        return "\""+value.Replace("\\", "\\\\").Replace("\"", "\\\"")+"\"";
    }
    private static void Ready(string self, string mode) {
        string directory=Path.GetDirectoryName(self);
        string version=mode=="incompatible" ? "[3,11,9]" : (mode=="arm-ready" ? "[3,14,8]" : "[3,12,8]");
        string platform=mode.StartsWith("arm-") ? "win-arm64" : "win-amd64";
        string missing=mode=="missing" ? "[\"pynvim\"]" : "[]";
        string importsChecked=mode=="incompatible" || mode=="arm-unvalidated" ? "false" : "true";
        Console.Out.WriteLine("{\"python\":"+Json(self)+",\"version\":"+version+
            ",\"implementation\":\"cpython\",\"platform\":"+Json(platform)+",\"bits\":64,\"missing\":"+missing+
            ",\"imports_checked\":"+importsChecked+
            ",\"jupytext\":"+Json(Path.Combine(directory,"jupytext.exe"))+
            ",\"latex2text\":"+Json(Path.Combine(directory,"latex2text.exe"))+"}");
        Console.Out.Flush();
    }
    private static void HoldOutputHandles(string self) {
        StartupInfo startup=new StartupInfo();
        startup.cb=Marshal.SizeOf(typeof(StartupInfo));
        startup.flags=0x100;
        startup.input=GetStdHandle(-10);
        startup.output=GetStdHandle(-11);
        startup.error=GetStdHandle(-12);
        ProcessInfo child;
        if (!CreateProcess(self,new StringBuilder("\""+self+"\" --hold"),
                IntPtr.Zero,IntPtr.Zero,true,0x08000000,IntPtr.Zero,
                Path.GetDirectoryName(self),ref startup,out child)) {
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        try {
            File.WriteAllText(Path.Combine(Path.GetDirectoryName(self),"orphan-child.pid"),child.processId.ToString());
        } finally {
            CloseHandle(child.thread);
            CloseHandle(child.process);
        }
    }
    public static int Main(string[] args) {
        string self=Assembly.GetExecutingAssembly().Location;
        if (args.Length==1 && args[0]=="--hold") {
            Thread.Sleep(60000);
            return 0;
        }
        string mode=Path.GetFileNameWithoutExtension(self);
        Console.Error.WriteLine("probe fixture stderr: "+mode);
        Console.Error.Flush();
        if (mode=="timeout") {
            Console.Out.WriteLine("probe fixture before timeout");
            Console.Out.Flush();
            Thread.Sleep(60000);
            return 0;
        }
        if (mode=="exit") {
            Console.Out.WriteLine("probe fixture nonzero evidence");
            Console.Out.Flush();
            return 7;
        }
        if (mode=="invalid") {
            Console.Out.WriteLine("invalid probe fixture JSON");
            return 0;
        }
        Ready(self,mode);
        if (mode=="orphan") { HoldOutputHandles(self); }
        return 0;
    }
}
'@

function Invoke-ProbeCase([string]$Name,[Nullable[int]]$TimeoutSeconds=$null) {
    $script:PythonProbeDiagnostics=@()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    if ($null -eq $TimeoutSeconds) {
        $selected=Probe-Python (Join-Path $WorkRoot ($Name+'.exe'))
        $expectedBudget=60
    } else {
        $selected=Probe-Python (Join-Path $WorkRoot ($Name+'.exe')) -TimeoutSeconds $TimeoutSeconds
        $expectedBudget=[int]$TimeoutSeconds
    }
    $watch.Stop()
    Require ($script:PythonProbeDiagnostics.Count -eq 1) ($Name+': expected exactly one diagnostic.')
    $diagnostic=$script:PythonProbeDiagnostics[0]
    foreach ($field in @('status','pid','exit_code','timed_out','timeout_seconds','seconds','error','stdout','stderr','output_drain_complete','python')) {
        Require ([bool]$diagnostic.PSObject.Properties[$field]) ($Name+': missing diagnostic field '+$field)
    }
    Require ($diagnostic.pid -gt 0) ($Name+': lost the native process identity.')
    Require ($diagnostic.timeout_seconds -eq $expectedBudget) ($Name+': configured timeout budget was not recorded accurately.')
    Require ($diagnostic.seconds -ge 0 -and $diagnostic.seconds -le ($expectedBudget+15)) ($Name+': invalid or unbounded recorded duration.')
    Require ($watch.Elapsed.TotalSeconds -le ($expectedBudget+15)) ($Name+': probe exceeded the bounded deadline.')
    Require ($diagnostic.stderr -like ('*probe fixture stderr: '+$Name+'*')) ($Name+': lost standard-error evidence.')
    [IO.File]::WriteAllText((Join-Path $WorkRoot ($Name+'.json')),($diagnostic|ConvertTo-Json -Depth 10),$utf8)
    return [pscustomobject]@{selected=$selected;diagnostic=$diagnostic;seconds=$watch.Elapsed.TotalSeconds}
}
function New-SyntheticDiagnostic([string]$Status) {
    return [pscustomobject]@{status=$Status;pid=0;exit_code=$null;timed_out=$false;timeout_seconds=60;seconds=0;
        error='Controlled synthetic probe state';stdout='';stderr='';output_drain_complete=$true;
        python=(Join-Path $WorkRoot 'synthetic-python.exe')}
}
function Invoke-GuardedSyntheticInstall($Selected,[bool]$Requested) {
    Assert-NotebookProbeKnown $Selected $Requested
    # A counter stands in for a mutating install path. No install helper is loaded.
    $script:SyntheticInstallTouches++
}
function Stop-OwnedOrphan {
    if ($receipt.ContainsKey('orphan_cleanup')) { return }
    $pidFile=Join-Path $WorkRoot 'orphan-child.pid'
    if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) { return }
    $childId=[int]([IO.File]::ReadAllText($pidFile).Trim())
    $child=Get-Process -Id $childId -ErrorAction SilentlyContinue
    if (-not $child) { $receipt.orphan_cleanup='test-owned-child-already-exited'; return }
    try {
        $expected=[IO.Path]::GetFullPath((Join-Path $WorkRoot 'orphan.exe'))
        Require ([string]::Equals($child.MainModule.FileName,$expected,[StringComparison]::OrdinalIgnoreCase)) 'Refusing to stop a process outside the orphan fixture.'
        $child.Kill()
        Require ($child.WaitForExit(5000)) 'Test-owned orphan did not exit within cleanup deadline.'
        $receipt.orphan_cleanup='terminated-test-owned-child'
    } finally { $child.Dispose() }
}

try {
    Save-Receipt
    $fixture=Join-Path $WorkRoot 'ready.exe'
    Add-Type -TypeDefinition $fakeSource -Language CSharp -OutputAssembly $fixture -OutputType ConsoleApplication
    foreach ($name in @('missing','incompatible','arm-ready','arm-unvalidated','exit','invalid','timeout','orphan')) {
        Copy-Item -LiteralPath $fixture -Destination (Join-Path $WorkRoot ($name+'.exe'))
    }
    foreach ($name in @('jupytext.exe','latex2text.exe')) {
        [IO.File]::WriteAllText((Join-Path $WorkRoot $name),'Existing helper fixture; never executed.',$utf8)
    }

    $ready=Invoke-ProbeCase 'ready'
    Require ([bool]$ready.selected -and $ready.selected.ready -and $ready.selected.compatible) 'Complete compatible Python no longer passes.'
    Require ($ready.diagnostic.status -eq 'ready' -and $ready.diagnostic.exit_code -eq 0 -and -not $ready.diagnostic.timed_out -and $ready.diagnostic.output_drain_complete) 'Complete Python diagnostic changed.'
    Require ($ready.diagnostic.timeout_seconds -eq 60 -and $ready.selected.imports_checked -and $ready.diagnostic.imports_checked) 'Default probe budget or completed-import evidence changed.'
    Require ($ready.selected.python -eq (Join-Path $WorkRoot 'ready.exe') -and $ready.selected.version -eq '3.12.8' -and @($ready.selected.missing).Count -eq 0) 'Complete Python lost its selection fields.'
    Require ($ready.selected.jupytext -eq (Join-Path $WorkRoot 'jupytext.exe') -and $ready.selected.latex2text -eq (Join-Path $WorkRoot 'latex2text.exe')) 'Complete Python lost its helper paths.'
    Pass 'ready Python retains selection fields and complete diagnostics'

    $arm=Invoke-ProbeCase 'arm-ready'
    Require ([bool]$arm.selected -and $arm.selected.ready -and $arm.selected.platform -eq 'win-arm64' -and $arm.selected.version -eq '3.14.8') 'Validated native ARM64 Python profile was rejected or lost its architecture.'
    $armOther=Invoke-ProbeCase 'arm-unvalidated'
    Require ([bool]$armOther.selected -and -not $armOther.selected.compatible -and $armOther.diagnostic.status -eq 'incompatible') 'An unvalidated ARM64 version was treated as a ready provider.'
    Pass 'validated ARM64 profile passes while other ARM versions remain explicit incompatible results'

    $missing=Invoke-ProbeCase 'missing'
    Require ([bool]$missing.selected -and $missing.selected.compatible -and -not $missing.selected.ready) 'Known missing modules changed the compatible-base behavior.'
    Require ($missing.diagnostic.status -eq 'missing' -and @($missing.selected.missing).Count -eq 1 -and $missing.selected.missing[0] -eq 'pynvim') 'Known missing modules were not reported accurately.'
    Pass 'known missing module remains a compatible base'

    $incompatible=Invoke-ProbeCase 'incompatible'
    Require ([bool]$incompatible.selected -and -not $incompatible.selected.compatible -and -not $incompatible.selected.ready -and $incompatible.diagnostic.status -eq 'incompatible') 'Known incompatible Python was not distinguished from unknown.'
    Require (-not $incompatible.selected.imports_checked -and -not $incompatible.diagnostic.imports_checked) 'Incompatible Python was incorrectly reported as having checked imports.'
    Pass 'incompatible Python remains a known result'

    foreach ($name in @('exit','invalid')) {
        $unknown=Invoke-ProbeCase $name
        Require (-not $unknown.selected -and $unknown.diagnostic.status -eq 'unknown' -and [bool]$unknown.diagnostic.error -and $unknown.diagnostic.output_drain_complete) ($name+': failed probe was treated as missing or lost the error.')
        if ($name -eq 'exit') {
            Require ($unknown.diagnostic.exit_code -eq 7 -and $unknown.diagnostic.stdout -like '*probe fixture nonzero evidence*') 'Nonzero probe lost its exit code or stdout.'
        } else {
            Require ($unknown.diagnostic.exit_code -eq 0 -and $unknown.diagnostic.stdout -like '*invalid probe fixture JSON*') 'Invalid JSON lost its successful exit or stdout evidence.'
        }
        Pass ($name+' probe records unknown status and original evidence')
    }

    $timeout=Invoke-ProbeCase 'timeout' -TimeoutSeconds 2
    Require (-not $timeout.selected -and $timeout.diagnostic.status -eq 'unknown' -and $timeout.diagnostic.timed_out -and [bool]$timeout.diagnostic.error) 'Timed-out Python was treated as missing or lost its timeout evidence.'
    Require ($timeout.seconds -ge 1.8 -and $timeout.seconds -le 20 -and $timeout.diagnostic.timeout_seconds -eq 2 -and $timeout.diagnostic.stdout -like '*probe fixture before timeout*') 'The explicit 2-second timeout lost partial output, its budget or the bounded deadline.'
    Pass 'explicit 2-second Python timeout is bounded and retains partial output'

    $orphan=Invoke-ProbeCase 'orphan'
    Require (Test-Path -LiteralPath (Join-Path $WorkRoot 'orphan-child.pid')) 'Orphan fixture failed to create its inherited-handle child.'
    Require (-not $orphan.selected -and $orphan.diagnostic.status -eq 'unknown' -and -not $orphan.diagnostic.output_drain_complete -and -not $orphan.diagnostic.timed_out) 'An exited parent with held output handles did not produce an unknown drain result.'
    Require ($orphan.seconds -le 15 -and $orphan.diagnostic.exit_code -eq 0 -and $orphan.diagnostic.stdout.Contains('"version":[3,12,8]')) 'Held output handles blocked the probe or lost the parent output/exit code.'
    Stop-OwnedOrphan
    Pass 'exited parent with inherited output handles returns within drain deadline'

    $script:SyntheticInstallTouches=0
    $script:PythonProbeDiagnostics=@((New-SyntheticDiagnostic 'missing'),(New-SyntheticDiagnostic 'unknown'))
    $blocked=$false
    try { Invoke-GuardedSyntheticInstall $null $true } catch { $blocked=$true }
    Require ($blocked -and $script:SyntheticInstallTouches -eq 0) 'Unknown existing Python did not block installation before mutation.'
    $script:PythonProbeDiagnostics=@((New-SyntheticDiagnostic 'missing'))
    Invoke-GuardedSyntheticInstall $null $true
    Require ($script:SyntheticInstallTouches -eq 1) 'Known missing Python unexpectedly blocked the install path.'
    $script:PythonProbeDiagnostics=@((New-SyntheticDiagnostic 'unknown'))
    Invoke-GuardedSyntheticInstall $ready.selected $true
    Require ($script:SyntheticInstallTouches -eq 2) 'An already-ready environment did not take precedence over an unknown candidate.'
    Invoke-GuardedSyntheticInstall $null $false
    Require ($script:SyntheticInstallTouches -eq 3) 'Read-only detection incorrectly raised the install guard.'
    Pass 'unknown blocks synthetic mutation while missing, ready selection and read-only detection remain allowed'

    $receipt.state='passed'
} catch {
    $receipt.state='failed'
    $receipt.error=$_.Exception.Message
    throw
} finally {
    try { Stop-OwnedOrphan }
    catch { $receipt.state='failed'; $receipt.error=$_.Exception.Message; throw }
    finally { Save-Receipt }
}
