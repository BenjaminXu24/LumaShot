#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef RuntimeArch
  #define RuntimeArch "x64"
#endif
#ifndef PublishDir
  #define PublishDir "..\..\build\windows\win-x64"
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\..\build\windows-releases"
#endif

[Setup]
AppId={{4FD0E4AC-A3AF-4D99-B83F-B9F1304E4CC3}
AppName=LumaShot
AppVersion={#AppVersion}
AppPublisher=BenjaminXu24
AppPublisherURL=https://github.com/BenjaminXu24/LumaShot
AppSupportURL=https://github.com/BenjaminXu24/LumaShot/issues
DefaultDirName={localappdata}\Programs\LumaShot
DefaultGroupName=LumaShot
PrivilegesRequired=lowest
MinVersion=10.0.19045
#if RuntimeArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
WizardStyle=modern
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
OutputDir={#ReleaseDir}
OutputBaseFilename=LumaShot-v{#AppVersion}-windows-{#RuntimeArch}-setup
SetupIconFile=..\LumaShot.Windows\Assets\AppIcon.ico
UninstallDisplayIcon={app}\LumaShot.exe
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no
AppMutex=Local\LumaShot.Windows

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\LumaShot"; Filename: "{app}\LumaShot.exe"
Name: "{autodesktop}\LumaShot"; Filename: "{app}\LumaShot.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "LumaShot"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\LumaShot.exe"; Description: "Launch LumaShot"; Flags: nowait postinstall skipifsilent
