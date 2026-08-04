#define EnvAppVersion GetEnv("EPUB_TOOLKIT_VERSION")
#define EnvArtifactSuffix GetEnv("EPUB_TOOLKIT_ARTIFACT_SUFFIX")

#if EnvAppVersion == ""
  #define MyAppVersion "1.2.5"
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
RestartIfNeededByRun=no

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
; 仅在系统未安装 WebView2 Runtime 时才运行引导器（避免每次升级都联网下载）。
; 引导器未提权运行时默认安装 per-user，不弹 UAC；
; 若此处失败，应用首次使用「网页推送」时会自带安装流程并给出明确提示。
Filename: "{app}\MicrosoftEdgeWebView2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "正在安装网页推送组件…"; Flags: waituntilterminated skipifdoesntexist; Check: not WebView2RuntimeInstalled
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
// 检测 WebView2 Runtime 是否已安装（pv 注册表键，官方文档位置）：
//   per-machine（64 位 Windows）：HKLM\SOFTWARE\WOW6432Node\...（32 位视图）
//   per-machine（32 位 Windows）：HKLM\SOFTWARE\...
//   per-user：                     HKCU\Software\...
function WebView2RuntimeInstalled(): Boolean;
var
  Value: String;
begin
  Result := False;

  // 32 位视图（x64 上即 WOW6432Node，兼容 32/64 位 Windows）
  if RegQueryStringValue(
      HKLM32,
      'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'pv', Value) then
    if (Value <> '') and (Value <> '0.0.0.0') then
      Result := True;

  // 64 位视图（部分机器的 EdgeUpdate 以 64 位注册）
  if not Result then
    if RegQueryStringValue(
        HKLM64,
        'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'pv', Value) then
      if (Value <> '') and (Value <> '0.0.0.0') then
        Result := True;

  // per-user 安装
  if not Result then
    if RegQueryStringValue(
        HKCU,
        'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
        'pv', Value) then
      if (Value <> '') and (Value <> '0.0.0.0') then
        Result := True;
end;
