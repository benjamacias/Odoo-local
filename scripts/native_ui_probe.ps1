param(
    [string] $Url = "http://127.0.0.1:8069",
    [Parameter(Mandatory = $true)]
    [string] $Database,
    [Parameter(Mandatory = $true)]
    [string] $Login,
    [Parameter(Mandatory = $true)]
    [string] $Password,
    [string] $Model = "res.partner"
)

$ErrorActionPreference = "Stop"
$Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Invoke-OdooJson {
    param(
        [string] $Path,
        [hashtable] $Params = @{}
    )

    $Body = @{
        jsonrpc = "2.0"
        method = "call"
        params = $Params
        id = 1
    } | ConvertTo-Json -Depth 64

    $Response = Invoke-RestMethod `
        -Uri (($Url.TrimEnd("/")) + $Path) `
        -Method Post `
        -WebSession $Session `
        -ContentType "application/json" `
        -Body $Body

    if ($Response.error) {
        throw (($Response.error | ConvertTo-Json -Depth 32))
    }

    return $Response.result
}

$Health = Invoke-OdooJson -Path "/native-ui/health"
$Auth = Invoke-OdooJson -Path "/web/session/authenticate" -Params @{
    db = $Database
    login = $Login
    password = $Password
}

if (-not $Auth.uid) {
    throw "Authentication failed."
}

$NativeSession = Invoke-OdooJson -Path "/native-ui/session"
$Snapshot = Invoke-OdooJson -Path "/native-ui/snapshot/index"
$Fields = Invoke-OdooJson -Path "/native-ui/model/$Model/fields" -Params @{
    attributes = @("string", "type", "required", "readonly", "relation")
}
$Records = Invoke-OdooJson -Path "/native-ui/model/$Model/records" -Params @{
    fields = @("display_name")
    limit = 5
}

Write-Host "Native UI Bridge OK"
Write-Host "Odoo: $($Health.odoo_version)"
Write-Host "User: $($NativeSession.user.name) ($($NativeSession.database))"
Write-Host "Snapshot hash: $($Snapshot.manifest.content_hash)"
Write-Host "Top-level apps: $($Snapshot.menus.children.Count)"
Write-Host "$Model fields: $($Fields.field_count)"
Write-Host "$Model sample rows: $($Records.count)"
