#ifndef MyAppName
  #define MyAppName "暖邻"
#endif

#ifndef MyAppVersion
  #define MyAppVersion "5.0.0"
#endif

#ifndef MyAppPublisher
  #define MyAppPublisher "Publisher"
#endif

#ifndef MyAppExeName
  #define MyAppExeName "customer.exe"
#endif

#ifndef MyAppId
  #define MyAppId "{{89A2F9B1-0F59-4D9A-8D55-E7E2E35A1B25}"
#endif

#ifndef SourceDir
  ; Forward slashes avoid ISPP treating "\x64" / "\r" as C-style escapes.
  #define SourceDir "../../build/windows/x64/runner/Release"
#endif

#ifndef OutputDir
  #define OutputDir "../../dist/windows-installer"
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "NuanLin-Windows-Setup-" + MyAppVersion
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=../runner/resources/app_icon.ico
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional tasks:"; Flags: unchecked

[Files]
Source: "{#SourceDir}/*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCR; Subkey: "onechat"; ValueType: string; ValueName: ""; ValueData: "URL:OneChat Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "onechat"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "onechat\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "onechat\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent
