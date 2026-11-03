#define AppName "ThermoSaver"
#define AppVersion "0.1.2"
[Setup]
AppId={{38AC09A6-FB03-41AC-9588-6DDCB3BA1AD5}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=ThermoSaver
LicenseFile=..\LICENSE
DefaultDirName={autopf}\ThermoSaver
DefaultGroupName=ThermoSaver
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
OutputDir=..\dist
OutputBaseFilename=ThermoSaver-Setup-0.1.2
SetupIconFile=..\assets\ThermoSaver.ico
UninstallDisplayIcon={app}\assets\ThermoSaver.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
Uninstallable=yes
[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
[Files]
Source: "Prepare-Upgrade.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "..\build\payload\*"; DestDir: "{app}"; Excludes: "config.json"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\payload\config.json"; DestDir: "{app}"; Flags: onlyifdoesntexist
[Icons]
Name: "{group}\ThermoSaver - stan ochrony"; Filename: "{app}\Status.cmd"; IconFilename: "{app}\assets\ThermoSaver.ico"
Name: "{group}\ThermoSaver - włącz ochronę"; Filename: "{app}\Enable.cmd"; IconFilename: "{app}\assets\ThermoSaver.ico"
Name: "{group}\ThermoSaver - wyłącz ochronę"; Filename: "{app}\Disable.cmd"; IconFilename: "{app}\assets\ThermoSaver.ico"
Name: "{group}\ThermoSaver - wyłącz tryb testowy"; Filename: "{app}\Normal-Thresholds.cmd"; IconFilename: "{app}\assets\ThermoSaver.ico"
Name: "{group}\Odinstaluj ThermoSaver"; Filename: "{uninstallexe}"; IconFilename: "{app}\assets\ThermoSaver.ico"
[UninstallRun]
Filename: "{app}\runtime\pwsh.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\Uninstall-ThermoSaver.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "ThermoSaverTasks"
[Code]
var UpgradePrepared, UpgradeCompleted: Boolean;

function RunUpgradeHelper(Restore: Boolean): Boolean;
var ResultCode: Integer; Arguments: String;
begin
  Arguments := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Prepare-Upgrade.ps1') + '" -StatePath "' + ExpandConstant('{tmp}\ThermoSaver-upgrade-state.json') + '"';
  if Restore then Arguments := Arguments + ' -Restore';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Arguments, ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if Result then Result := ResultCode = 0;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if Pos('/VERIFYONLY', Uppercase(GetCmdTail)) > 0 then Exit;
  ExtractTemporaryFile('Prepare-Upgrade.ps1');
  if RunUpgradeHelper(False) then UpgradePrepared := True
  else Result := 'Nie udało się bezpiecznie zatrzymać ThermoSaver przed aktualizacją.';
end;

procedure DeinitializeSetup();
begin
  if UpgradePrepared and not UpgradeCompleted then RunUpgradeHelper(True);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var ResultCode: Integer; Arguments: String;
begin
  if CurStep = ssPostInstall then begin
    Arguments := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\Install-ThermoSaver.ps1') + '"';
    if Pos('/VERIFYONLY', Uppercase(GetCmdTail)) > 0 then
      Arguments := Arguments + ' -ValidateOnly';
    if not Exec(ExpandConstant('{app}\runtime\pwsh.exe'), Arguments, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      RaiseException('Nie udało się skonfigurować ochrony ThermoSaver.');
    if ResultCode <> 0 then
      RaiseException('Konfiguracja ochrony nie powiodła się. Sprawdź sterownik PawnIO i połączenie Flydigi BS3 Pro.');
    UpgradeCompleted := True;
  end;
end;
