#define EnvAppVersion GetEnv("EPUB_TOOLKIT_VERSION")
#define EnvArtifactSuffix GetEnv("EPUB_TOOLKIT_ARTIFACT_SUFFIX")

#if EnvAppVersion == ""
  #define MyAppVersion "1.0.5"
#else
  #define MyAppVersion EnvAppVersion
#endif

#if EnvArtifactSuffix == ""
  #define ArtifactSuffix "dev"
#else
  #define ArtifactSuffix EnvArtifactSuffix
#endif

#define MyAppName "EPUB 工具箱"
#define MyAppPublisher "EPUB Toolkit"
#define MyAppExeName "epub_gadget.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{8B8E3F17-66BE-4B89-9733-A6D20E9EF97E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\EPUB Toolkit
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=epub-toolkit-windows-{#ArtifactSuffix}-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
