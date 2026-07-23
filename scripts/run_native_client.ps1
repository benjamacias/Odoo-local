$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Exe = Join-Path $Root "native_client\OdooNativeClient\bin\Release\OdooNativeClient.exe"

if (-not (Test-Path $Exe)) {
    & (Join-Path $PSScriptRoot "build_native_client.ps1")
}

Start-Process -FilePath $Exe -WindowStyle Normal
