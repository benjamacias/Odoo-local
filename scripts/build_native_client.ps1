param(
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Root "native_client\OdooNativeClient\Program.cs"
$OutDir = Join-Path $Root "native_client\OdooNativeClient\bin\$Configuration"
$OutFile = Join-Path $OutDir "OdooNativeClient.exe"
$Csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path $Csc)) {
    throw "No se encontro csc.exe en $Csc. Instala .NET SDK o .NET Framework Developer Pack."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $Csc `
    /nologo `
    /optimize+ `
    /target:winexe `
    /out:$OutFile `
    /reference:System.dll `
    /reference:System.Core.dll `
    /reference:System.Data.dll `
    /reference:System.Drawing.dll `
    /reference:System.Net.Http.dll `
    /reference:System.Web.Extensions.dll `
    /reference:System.Windows.Forms.dll `
    $Source

if ($LASTEXITCODE -ne 0) {
    throw "Fallo la compilacion del cliente nativo."
}

Write-Host $OutFile
