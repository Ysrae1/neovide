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
#if !FileExists(StageDir + "\Glow.exe") || !FileExists(StageDir + "\bundle.json")
  #error StageDir is missing the compiled launcher or bundle metadata.
#endif

; Inno Setup 6 does not consistently support extended-length destination paths.
; Measure this exact payload instead of allowing extraction to fail halfway through.
#define GlowMaxRelativeFile 0
#define GlowMaxRelativeDirectory 0
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
AppId={{273E54EB-BD13-49D8-B56D-0860903BA699}
AppName=Neovide Glow
AppVersion={#AppVersion}
AppPublisher=Neovide Glow contributors
AppPublisherURL=https://github.com/Ysrae1/neovide
AppSupportURL=https://github.com/Ysrae1/neovide/issues
DefaultDirName={localappdata}\Programs\Neovide Glow
DefaultGroupName=Neovide Glow
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
DisableProgramGroupPage=yes
DisableDirPage=no
UsePreviousAppDir=yes
UninstallDisplayIcon={app}\Glow.exe
OutputDir={#OutputDir}
OutputBaseFilename=Neovide-Glow-{#AppVersion}-Windows-x64-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
ChangesEnvironment=no
ChangesAssociations=no
Uninstallable=yes
VersionInfoDescription=Neovide Glow offline installer

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Neovide Glow"; Filename: "{app}\Glow.exe"; WorkingDir: "{userdocs}"
Name: "{autodesktop}\Neovide Glow"; Filename: "{app}\Glow.exe"; WorkingDir: "{userdocs}"; Tasks: desktopicon

[Run]
Filename: "{app}\Glow.exe"; Description: "Launch Neovide Glow"; WorkingDir: "{userdocs}"; Flags: nowait postinstall skipifsilent unchecked

; User profiles are outside {app}; no UninstallDelete or broad registry cleanup.
; Fonts added to the user's shared font collection are retained on uninstall.
[Code]
const
  GlowWmFontChange = $001D;
  GlowHwndBroadcast = $FFFF;
  GlowSmtoAbortIfHung = $0002;
  GlowMaxRelativeFile = {#GlowMaxRelativeFile};
  GlowMaxRelativeDirectory = {#GlowMaxRelativeDirectory};

function GlowCheckInstallDirectory(const Directory: String): String;
var
  RootLength, MaximumRootLength: Integer;
begin
  Result := '';
  MaximumRootLength := 259 - 1 - GlowMaxRelativeFile;
  { Inno 6 creates a 17-character is-XXXXXXXXXX.tmp in each destination directory. }
  if 259 - 1 - GlowMaxRelativeDirectory - 18 < MaximumRootLength then
    MaximumRootLength := 259 - 1 - GlowMaxRelativeDirectory - 18;
  RootLength := Length(RemoveBackslashUnlessRoot(Directory));
  if RootLength > MaximumRootLength then
  begin
    Result := 'This installation folder is too long for the complete offline package. ' +
      'Choose a shorter folder, such as C:\Glow. The folder path must contain at most ' +
      IntToStr(MaximumRootLength) + ' characters; the selected path contains ' +
      IntToStr(RootLength) + '.';
    Log('Glow path preflight: rejected before installation; folder length=' +
      IntToStr(RootLength) + ', maximum=' + IntToStr(MaximumRootLength));
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
      Log('Preserved an existing font registry entry: ' + FontName);
      Exit;
    end;
  end;
  if FileExists(Destination) then
  begin
    if CompareText(GetSHA256OfFile(Source), GetSHA256OfFile(Destination)) <> 0 then
    begin
      Log('Preserved a different existing user font: ' + FontName);
      Exit;
    end;
  end
  else
  begin
    if not ForceDirectories(FontDirectory) then
      RaiseException('Unable to create the per-user font directory.');
    if not FileCopy(Source, Destination, True) then
      RaiseException('Unable to install the per-user font: ' + FontName);
  end;
  if not RegWriteStringValue(HKCU,
    'Software\Microsoft\Windows NT\CurrentVersion\Fonts', RegistryName, Destination) then
    RaiseException('Unable to register the per-user font: ' + FontName);
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
    RaiseException('The complete offline package must include its default fonts.');
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
    RaiseException('The offline package does not contain its default font files.');
  GlowSendMessageTimeout(GlowHwndBroadcast, GlowWmFontChange, 0, 0,
    GlowSmtoAbortIfHung, 1000, MessageResult);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then GlowInstallUserFonts;
end;
