; Compile on the Windows release worker after creating the complete offline stage.
; ISCC.exe /DStageDir="C:\path\to\stage" /DOutputDir="C:\path\to\out" /DAppVersion="2026.10.20.1" installer.iss
#ifndef StageDir
  #error StageDir must point to the verified, fully prepared Windows stage.
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef AppVersion
  #error AppVersion is required.
#endif
#ifndef Distribution
  #define Distribution "offline"
#endif
#ifndef TargetArchitecture
  #define TargetArchitecture "x64"
#endif
#if TargetArchitecture != "x64" && TargetArchitecture != "arm64"
  #error TargetArchitecture must be x64 or arm64.
#endif
#if TargetArchitecture == "arm64" && Distribution != "core"
  #error The legacy offline pipeline is x64-only. Use the architecture-verified core pipeline for ARM64.
#endif
#if Distribution == "core"
  #define PackageSuffix "Core-Setup"
  #if TargetArchitecture == "arm64"
    #define InstallDirectoryName "Neovide Glow Core ARM64"
    #define ShortcutName "Neovide Glow Preview ARM64"
    #define ProductId "9AC25A16-EF9A-41BE-96EF-6AB247FDBE23"
  #else
    #define InstallDirectoryName "Neovide Glow Core"
    #define ShortcutName "Neovide Glow Preview"
    #define ProductId "2BE1E0A6-180C-4700-8453-FB29359286D9"
  #endif
#else
  #define PackageSuffix "Setup"
  #define InstallDirectoryName "Neovide Glow"
  #define ShortcutName "Neovide Glow"
  #define ProductId "273E54EB-BD13-49D8-B56D-0860903BA699"
#endif
#if !FileExists(StageDir + "\Glow.exe") || !FileExists(StageDir + "\bundle.json")
  #error StageDir is missing the compiled launcher or bundle metadata.
#endif
#if !FileExists(StageDir + "\neovide.ico")
  #error StageDir is missing the Neovide Glow icon.
#endif

; Inno Setup 6 does not consistently support extended-length destination paths.
; Measure this exact payload instead of allowing extraction to fail halfway through.
; Include the bundled translation license installed outside StageDir as well.
; Its path is also longer than the generated glow-ui-language.txt marker.
#define GlowMaxRelativeFile Len("licenses\InnoSetup-ChineseSimplified-LICENSE.txt")
#define GlowMaxRelativeDirectory Len("licenses")
#define GlowDirectoryCount 1
#define GlowDirectoryIndex 0
#define GlowFindHandle 0
#define GlowFindResult 0
#define GlowEntryName ""
#define GlowRelativeName ""
#dim public GlowDirectories[1] {""}
#sub GlowMeasureEntry
  #expr GlowEntryName = FindGetFileName(GlowFindHandle)
  #if GlowEntryName != "." && GlowEntryName != ".."
    #expr GlowRelativeName = GlowDirectories[GlowDirectoryIndex] + GlowEntryName
    #if DirExists(StageDir + "\" + GlowRelativeName)
      #if Len(GlowRelativeName) > GlowMaxRelativeDirectory
        #expr GlowMaxRelativeDirectory = Len(GlowRelativeName)
      #endif
      #redim public GlowDirectories[GlowDirectoryCount + 1]
      #expr GlowDirectories[GlowDirectoryCount] = GlowRelativeName + "\"
      #expr GlowDirectoryCount++
    #elif Len(GlowRelativeName) > GlowMaxRelativeFile
      #expr GlowMaxRelativeFile = Len(GlowRelativeName)
    #endif
  #endif
#endsub
#sub GlowMeasureDirectory
  #for {GlowFindHandle = GlowFindResult = FindFirst(StageDir + "\" + GlowDirectories[GlowDirectoryIndex] + "*", faAnyFile); GlowFindResult; GlowFindResult = FindNext(GlowFindHandle)} GlowMeasureEntry
  #if GlowFindHandle
    #expr FindClose(GlowFindHandle)
  #endif
#endsub
#for {GlowDirectoryIndex = 0; GlowDirectoryIndex < GlowDirectoryCount; GlowDirectoryIndex++} GlowMeasureDirectory

[Setup]
AppId={{{#ProductId}}
AppName=Neovide Glow
AppVersion={#AppVersion}
AppPublisher=Neovide Glow contributors
AppPublisherURL=https://github.com/Ysrae1/neovide
AppSupportURL=https://github.com/Ysrae1/neovide/issues
DefaultDirName={localappdata}\Programs\{#InstallDirectoryName}
DefaultGroupName={#ShortcutName}
PrivilegesRequired=lowest
#if TargetArchitecture == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
; Windows 11 22H2 includes the managed launcher's .NET Framework 4.8.1.
; Windows 10 ARM64 cannot supply the older-system x64 emulation fallback.
MinVersion=10.0.22621
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
#endif
DisableProgramGroupPage=yes
DisableDirPage=no
UsePreviousAppDir=yes
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=yes
UsePreviousLanguage=no
SetupIconFile={#StageDir}\neovide.ico
UninstallDisplayIcon={app}\neovide.ico
OutputDir={#OutputDir}
OutputBaseFilename=Neovide-Glow-{#AppVersion}-Windows-{#TargetArchitecture}-{#PackageSuffix}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
ChangesEnvironment=no
ChangesAssociations=no
Uninstallable=yes
VersionInfoDescription=Neovide Glow {#Distribution} installer

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"

[CustomMessages]
english.GlowDesktopShortcut=Create a desktop shortcut
chinesesimplified.GlowDesktopShortcut=创建桌面快捷方式
english.GlowShortcuts=Shortcuts:
chinesesimplified.GlowShortcuts=快捷方式：
english.GlowSetupComment=Check tools and finish the initial setup
chinesesimplified.GlowSetupComment=检查工具并完成初始设置
english.GlowLaunch=Launch Neovide Glow
chinesesimplified.GlowLaunch=启动 Neovide Glow
english.GlowChooseFeatures=Choose features
chinesesimplified.GlowChooseFeatures=选择功能
english.GlowFeaturesSubtitle=Reuse compatible tools and download only missing components.
chinesesimplified.GlowFeaturesSubtitle=复用已有的兼容工具，仅下载缺失组件。
english.GlowFeaturesDescription=This installer includes the editor, Neovim, plugins and fonts. After copying them, a setup window checks this PC and shows which tools can be reused and what needs downloading. Downloads start only after you confirm the plan.%n%nBase tools provide search, the file manager, Git and embedded PDF. Notebook, TeX packages and a missing WebView2 runtime require additional downloads; the total size varies. You can finish later by reopening the Setup shortcut.
chinesesimplified.GlowFeaturesDescription=本安装包包含编辑器、Neovim、插件和字体。复制完成后，初始设置窗口会检查本机，列出可复用的工具和需要下载的组件。确认方案后才会开始下载。%n%n基础工具提供搜索、文件管理、Git 和内嵌 PDF。Notebook、TeX 宏包及缺失的 WebView2 运行时需要额外下载，总大小以检测结果为准。也可以稍后通过 Setup（初始设置）快捷方式继续。
english.GlowNotebook=Notebook / Python (CPython up to 26 MiB, plus Python packages)
chinesesimplified.GlowNotebook=Notebook / Python（CPython 最多 26 MiB，另需 Python 包）
english.GlowLatex=LaTeX / Chinese PDF (TinyTeX up to 71 MiB, plus TeX packages)
chinesesimplified.GlowLatex=LaTeX / 中文 PDF（TinyTeX 最多 71 MiB，另需 TeX 宏包）
english.GlowReviewDependencies=Review the detected tools and download plan in the Glow setup window.
chinesesimplified.GlowReviewDependencies=请在 Glow 初始设置窗口中查看工具检测结果和下载方案。
english.GlowDependenciesLaunchFailed=The application files were installed, but a selected dependency did not finish. Existing environments and partial downloads were preserved. See %1 for the error, then reopen the Neovide Glow Setup shortcut to continue.
chinesesimplified.GlowDependenciesLaunchFailed=应用文件已安装，但所选依赖尚未完成。已有环境和部分下载均已保留。请在 %1 查看错误，再打开 Neovide Glow 的 Setup（初始设置）快捷方式继续。
english.GlowDependenciesPending=The editor is installed. Reopen the Neovide Glow Setup shortcut to finish dependencies.
chinesesimplified.GlowDependenciesPending=编辑器已安装。请重新打开 Neovide Glow 的 Setup（初始设置）快捷方式，完成依赖安装。
english.GlowOfflineDirectory=This folder contains an offline runtime. Choose a separate folder for Neovide Glow Core. The existing application and its user profiles will be preserved.
chinesesimplified.GlowOfflineDirectory=此文件夹包含离线运行环境。请为 Neovide Glow Core 选择另一个文件夹。已有应用及其用户配置会保留。
english.GlowOtherPackageDirectory=This folder belongs to another Glow package. Choose a separate folder for the core installation.
chinesesimplified.GlowOtherPackageDirectory=此文件夹属于另一个 Glow 安装包。请为核心版选择另一个安装文件夹。
english.GlowArchitectureDirectory=This folder contains a different or unrecognized processor architecture. Choose a separate folder for the %1 package. Existing application files and profiles were preserved.
chinesesimplified.GlowArchitectureDirectory=此文件夹中的程序使用不同或无法识别的处理器架构。请为 %1 安装包选择另一个文件夹。已有应用文件和配置均已保留。
english.GlowDirectoryTooLong=This installation folder is too long for this package. Choose a shorter folder, such as C:\Glow. The folder path must contain at most %1 characters; the selected path contains %2.
chinesesimplified.GlowDirectoryTooLong=此安装包的目标路径过长。请选择更短的文件夹，例如 C:\Glow。路径最多可包含 %1 个字符；当前路径包含 %2 个字符。
english.GlowPathRejectedLog=Glow path preflight: rejected before installation; folder length=%1, maximum=%2
chinesesimplified.GlowPathRejectedLog=Glow 路径预检：已在安装前拒绝；路径长度=%1，最大长度=%2
english.GlowFontRegistryPreserved=Preserved an existing font registry entry: %1
chinesesimplified.GlowFontRegistryPreserved=已保留已有的字体注册表项：%1
english.GlowFontPreserved=Preserved a different existing user font: %1
chinesesimplified.GlowFontPreserved=已保留已有的不同版本用户字体：%1
english.GlowFontDirectoryFailed=Unable to create the per-user font directory.
chinesesimplified.GlowFontDirectoryFailed=无法创建当前用户的字体文件夹。
english.GlowFontCopyFailed=Unable to install the per-user font: %1
chinesesimplified.GlowFontCopyFailed=无法安装当前用户的字体：%1
english.GlowFontRegisterFailed=Unable to register the per-user font: %1
chinesesimplified.GlowFontRegisterFailed=无法注册当前用户的字体：%1
english.GlowFontDirectoryMissing=The package must include its default fonts.
chinesesimplified.GlowFontDirectoryMissing=安装包必须包含默认字体文件夹。
english.GlowFontFilesMissing=The package does not contain its default font files.
chinesesimplified.GlowFontFilesMissing=安装包中缺少默认字体文件。
english.GlowLanguageSaveFailed=Unable to save the setup language in the application folder.
chinesesimplified.GlowLanguageSaveFailed=无法在应用文件夹中保存安装语言。

[Tasks]
Name: "desktopicon"; Description: "{cm:GlowDesktopShortcut}"; GroupDescription: "{cm:GlowShortcuts}"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "languages\ChineseSimplified-LICENSE.txt"; DestDir: "{app}\licenses"; DestName: "InnoSetup-ChineseSimplified-LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#ShortcutName}"; Filename: "{app}\Glow.exe"; WorkingDir: "{userdocs}"; IconFilename: "{app}\neovide.ico"
Name: "{autodesktop}\{#ShortcutName}"; Filename: "{app}\Glow.exe"; WorkingDir: "{userdocs}"; Tasks: desktopicon; IconFilename: "{app}\neovide.ico"
#if Distribution == "core"
Name: "{autoprograms}\{#ShortcutName} Setup"; Filename: "{app}\Glow.exe"; Parameters: "--setup --notebook --latex"; WorkingDir: "{userdocs}"; Comment: "{cm:GlowSetupComment}"; IconFilename: "{app}\neovide.ico"
#endif

[Run]
Filename: "{app}\Glow.exe"; Description: "{cm:GlowLaunch}"; WorkingDir: "{userdocs}"; Flags: nowait postinstall skipifsilent unchecked

; Delete only the generated application-local language marker, never user profiles.
[UninstallDelete]
Type: files; Name: "{app}\glow-ui-language.txt"

; User profiles are outside {app}; no broad registry or directory cleanup.
; Fonts added to the user's shared font collection are retained on uninstall.
[Code]
const
  GlowWmFontChange = $001D;
  GlowHwndBroadcast = $FFFF;
  GlowSmtoAbortIfHung = $0002;
  GlowMaxRelativeFile = {#GlowMaxRelativeFile};
  GlowMaxRelativeDirectory = {#GlowMaxRelativeDirectory};

#if Distribution == "core"
var
  GlowFeaturePage: TInputOptionWizardPage;

procedure InitializeWizard;
begin
  GlowFeaturePage := CreateInputOptionPage(wpSelectDir, CustomMessage('GlowChooseFeatures'),
    CustomMessage('GlowFeaturesSubtitle'), CustomMessage('GlowFeaturesDescription'), False, False);
  GlowFeaturePage.Add(CustomMessage('GlowNotebook'));
  GlowFeaturePage.Add(CustomMessage('GlowLatex'));
  GlowFeaturePage.Values[0] := True;
  GlowFeaturePage.Values[1] := True;
end;

procedure GlowInstallSelectedDependencies;
var
  Arguments: String;
  ExitCode: Integer;
begin
  { Automated packaging smoke tests must not install external software. }
  if WizardSilent and (ExpandConstant('{param:INSTALLDEPS|0}') <> '1') then Exit;
  { The GUI launcher creates PowerShell with CREATE_NO_WINDOW before it starts. }
  Arguments := '--setup';
  if GlowFeaturePage.Values[0] then Arguments := Arguments + ' --notebook';
  if GlowFeaturePage.Values[1] then Arguments := Arguments + ' --latex';
  WizardForm.StatusLabel.Caption := CustomMessage('GlowReviewDependencies');
  if not Exec(ExpandConstant('{app}\Glow.exe'), Arguments,
    ExpandConstant('{app}'), SW_SHOWNORMAL, ewWaitUntilTerminated, ExitCode) then
    RaiseException(FmtMessage(CustomMessage('GlowDependenciesLaunchFailed'), [ExpandConstant('{localappdata}\NeovideGlow\dependencies\runs')]));
  if ExitCode <> 0 then
    WizardForm.StatusLabel.Caption := CustomMessage('GlowDependenciesPending');
end;
#endif

#if Distribution == "core"
{ Normalize JSON whitespace without altering quoted values or escaped quotes. }
function GlowCompactBundle(const Value: AnsiString): AnsiString;
var
  I: Integer;
  C: AnsiString;
  Quoted, Escaped: Boolean;
begin
  Result := '';
  Quoted := False;
  Escaped := False;
  for I := 1 to Length(Value) do
  begin
    C := Copy(Value, I, 1);
    if Quoted then
    begin
      Result := Result + C;
      if Escaped then Escaped := False
      else if C = '\' then Escaped := True
      else if C = '"' then Quoted := False;
    end
    else if (C <> ' ') and (C <> #9) and (C <> #10) and (C <> #13) then
    begin
      Result := Result + C;
      if C = '"' then Quoted := True;
    end;
  end;
end;
#endif

function GlowCheckInstallDirectory(const Directory: String): String;
var
  RootLength, MaximumRootLength: Integer;
#if Distribution == "core"
  ExistingBundle: AnsiString;
#endif
begin
  Result := '';
#if Distribution == "core"
  { Do not leave old offline runtimes/shims shadowing system dependencies. }
  { A separate install identity preserves the old package instead of deleting it. }
  if FileExists(AddBackslash(Directory) + 'runtime\python\python.exe') or
     FileExists(AddBackslash(Directory) + 'bin\python.exe') then
  begin
    Result := CustomMessage('GlowOfflineDirectory');
    Exit;
  end;
  if FileExists(AddBackslash(Directory) + 'Glow.exe') or
     FileExists(AddBackslash(Directory) + 'bundle.json') or
     FileExists(AddBackslash(Directory) + 'bin\neovide.exe') then
  begin
    if not LoadStringFromFile(AddBackslash(Directory) + 'bundle.json', ExistingBundle) then
    begin
      Result := CustomMessage('GlowOtherPackageDirectory');
      Exit;
    end;
    ExistingBundle := GlowCompactBundle(ExistingBundle);
    if Pos('"distribution":"core"', ExistingBundle) = 0 then
    begin
      Result := CustomMessage('GlowOtherPackageDirectory');
      Exit;
    end;
#if TargetArchitecture == "arm64"
    { Older unlabelled stages are x64; they must not be adopted by ARM64. }
    if Pos('"architecture":"arm64"', ExistingBundle) = 0 then
#else
    if (Pos('"architecture":"arm64"', ExistingBundle) <> 0) or
       (Pos('"architecture":"aarch64"', ExistingBundle) <> 0) or
       ((Pos('"architecture":', ExistingBundle) <> 0) and
        (Pos('"architecture":"x64"', ExistingBundle) = 0) and
        (Pos('"architecture":"x86_64"', ExistingBundle) = 0)) then
#endif
    begin
      Result := FmtMessage(CustomMessage('GlowArchitectureDirectory'), ['{#TargetArchitecture}']);
      Exit;
    end;
  end;
#endif
  MaximumRootLength := 259 - 1 - GlowMaxRelativeFile;
  { Inno 6 creates a 17-character is-XXXXXXXXXX.tmp in each destination directory. }
  if 259 - 1 - GlowMaxRelativeDirectory - 18 < MaximumRootLength then
    MaximumRootLength := 259 - 1 - GlowMaxRelativeDirectory - 18;
  RootLength := Length(RemoveBackslashUnlessRoot(Directory));
  if RootLength > MaximumRootLength then
  begin
    Result := FmtMessage(CustomMessage('GlowDirectoryTooLong'), [IntToStr(MaximumRootLength), IntToStr(RootLength)]);
    Log(FmtMessage(CustomMessage('GlowPathRejectedLog'), [IntToStr(RootLength), IntToStr(MaximumRootLength)]));
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Error: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    Error := GlowCheckInstallDirectory(WizardDirValue);
    if Error <> '' then
    begin
      if not WizardSilent then MsgBox(Error, mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := GlowCheckInstallDirectory(ExpandConstant('{app}'));
end;

function GlowAddFontResourceEx(FileName: String; Flags: DWORD; Reserved: Integer): Integer;
  external 'AddFontResourceExW@gdi32.dll stdcall';
// Inno Setup 6's installer engine is 32-bit, including x64 target installs.
// Its Pascal Script API does not define the newer WPARAM/LPARAM/LRESULT aliases.
function GlowSendMessageTimeout(Window: HWND; Message: Cardinal; WParam: LongWord;
  LParam: LongInt; Flags: Cardinal; Timeout: Cardinal; var ResultValue: LongWord): LongInt;
  external 'SendMessageTimeoutW@user32.dll stdcall';

procedure GlowRegisterUserFont(const Source, FontName: String);
var
  FontDirectory, Destination, RegistryName, ExistingValue: String;
begin
  FontDirectory := ExpandConstant('{localappdata}\Microsoft\Windows\Fonts');
  Destination := AddBackslash(FontDirectory) + FontName;
  RegistryName := 'Neovide Glow (' + FontName + ')';
  if RegQueryStringValue(HKCU,
    'Software\Microsoft\Windows NT\CurrentVersion\Fonts', RegistryName, ExistingValue) then
  begin
    if CompareText(ExistingValue, Destination) <> 0 then
    begin
      Log(FmtMessage(CustomMessage('GlowFontRegistryPreserved'), [FontName]));
      Exit;
    end;
  end;
  if FileExists(Destination) then
  begin
    if CompareText(GetSHA256OfFile(Source), GetSHA256OfFile(Destination)) <> 0 then
    begin
      Log(FmtMessage(CustomMessage('GlowFontPreserved'), [FontName]));
      Exit;
    end;
  end
  else
  begin
    if not ForceDirectories(FontDirectory) then
      RaiseException(CustomMessage('GlowFontDirectoryFailed'));
    if not FileCopy(Source, Destination, True) then
      RaiseException(FmtMessage(CustomMessage('GlowFontCopyFailed'), [FontName]));
  end;
  if not RegWriteStringValue(HKCU,
    'Software\Microsoft\Windows NT\CurrentVersion\Fonts', RegistryName, Destination) then
    RaiseException(FmtMessage(CustomMessage('GlowFontRegisterFailed'), [FontName]));
  GlowAddFontResourceEx(Destination, 0, 0);
end;

procedure GlowInstallUserFonts;
var
  Found: TFindRec;
  Directory, Extension: String;
  MessageResult: LongWord;
  FontCount: Integer;
begin
  Directory := ExpandConstant('{app}\fonts');
  if not DirExists(Directory) then
    RaiseException(CustomMessage('GlowFontDirectoryMissing'));
  FontCount := 0;
  if FindFirst(AddBackslash(Directory) + '*', Found) then
  begin
    try
      repeat
        if (Found.Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
        begin
          Extension := Lowercase(ExtractFileExt(Found.Name));
          if (Extension = '.ttf') or (Extension = '.otf') then
          begin
            GlowRegisterUserFont(AddBackslash(Directory) + Found.Name, Found.Name);
            FontCount := FontCount + 1;
          end;
        end;
      until not FindNext(Found);
    finally
      FindClose(Found);
    end;
  end;
  if FontCount = 0 then
    RaiseException(CustomMessage('GlowFontFilesMissing'));
  GlowSendMessageTimeout(GlowHwndBroadcast, GlowWmFontChange, 0, 0,
    GlowSmtoAbortIfHung, 1000, MessageResult);
end;

procedure GlowSaveUiLanguage;
var
  LanguageCode: AnsiString;
begin
  LanguageCode := 'en';
  if ActiveLanguage = 'chinesesimplified' then LanguageCode := 'zh-CN';
  { These ASCII language codes are UTF-8 without a BOM. Keep the marker app-local. }
  if not SaveStringToFile(ExpandConstant('{app}\glow-ui-language.txt'), LanguageCode, False) then
    RaiseException(CustomMessage('GlowLanguageSaveFailed'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    GlowSaveUiLanguage;
    GlowInstallUserFonts;
#if Distribution == "core"
    GlowInstallSelectedDependencies;
#endif
  end;
end;
