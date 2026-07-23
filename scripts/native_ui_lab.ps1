param(
    [string] $Url = "http://127.0.0.1:8069",
    [string] $Database = "odoo",
    [string] $Login = "admin",
    [string] $Password = ""
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$script:Snapshot = $null
$script:PartnerFields = $null
$script:PartnerRecords = @()

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
    } | ConvertTo-Json -Depth 80

    $Response = Invoke-RestMethod `
        -Uri (($Url.TrimEnd("/")) + $Path) `
        -Method Post `
        -WebSession $script:Session `
        -ContentType "application/json" `
        -Body $Body

    if ($Response.error) {
        throw (($Response.error | ConvertTo-Json -Depth 32))
    }

    return $Response.result
}

function Set-Status {
    param([string] $Text)
    $StatusLabel.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

function Add-FieldRow {
    param(
        [System.Windows.Forms.TableLayoutPanel] $Table,
        [string] $Name,
        $Meta,
        $Value
    )

    $Row = $Table.RowCount
    $Table.RowCount = $Row + 1
    $Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = if ($Meta.string) { $Meta.string } else { $Name }
    $Label.AutoSize = $true
    $Label.Margin = New-Object System.Windows.Forms.Padding(0, 7, 8, 4)

    $Control = $null
    switch ($Meta.type) {
        "boolean" {
            $Control = New-Object System.Windows.Forms.CheckBox
            $Control.Checked = [bool]$Value
        }
        "selection" {
            $Control = New-Object System.Windows.Forms.ComboBox
            $Control.DropDownStyle = "DropDownList"
            foreach ($Item in @($Meta.selection)) {
                if ($Item -is [array] -and $Item.Count -ge 2) {
                    [void]$Control.Items.Add($Item[1])
                }
            }
            if ($Value) { $Control.Text = [string]$Value }
        }
        default {
            $Control = New-Object System.Windows.Forms.TextBox
            $Control.Text = if ($null -eq $Value) { "" } elseif ($Value -is [array]) { ($Value -join " - ") } else { [string]$Value }
            if ($Meta.type -eq "text") {
                $Control.Multiline = $true
                $Control.Height = 56
                $Control.ScrollBars = "Vertical"
            }
        }
    }

    $Control.Dock = "Fill"
    $Control.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    $Control.Enabled = -not [bool]$Meta.readonly

    $Table.Controls.Add($Label, 0, $Row)
    $Table.Controls.Add($Control, 1, $Row)
}

function Load-PartnerForm {
    param($Record)

    $FormPanel.Controls.Clear()
    $Table = New-Object System.Windows.Forms.TableLayoutPanel
    $Table.Dock = "Top"
    $Table.AutoSize = $true
    $Table.ColumnCount = 2
    $Table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 150)))
    $Table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    $Preferred = @("name", "email", "phone", "mobile", "company_id", "street", "city", "country_id", "vat", "website")
    foreach ($FieldName in $Preferred) {
        $MetaProperty = $script:PartnerFields.PSObject.Properties[$FieldName]
        if (-not $MetaProperty) { continue }
        $RecordProperty = $Record.PSObject.Properties[$FieldName]
        $Value = if ($RecordProperty) { $RecordProperty.Value } else { $null }
        Add-FieldRow -Table $Table -Name $FieldName -Meta $MetaProperty.Value -Value $Value
    }

    $FormPanel.Controls.Add($Table)
}

function Load-Contacts {
    Set-Status "Cargando metadata de res.partner..."
    $FieldResult = Invoke-OdooJson -Path "/native-ui/model/res.partner/fields" -Params @{
        attributes = @("string", "type", "readonly", "required", "relation", "selection")
    }
    $script:PartnerFields = $FieldResult.fields

    Set-Status "Cargando IR y registros paginados..."
    [void](Invoke-OdooJson -Path "/native-ui/model/res.partner/ir" -Params @{
        views = @(@{type = "list"}, @{type = "form"})
    })

    $RecordResult = Invoke-OdooJson -Path "/native-ui/model/res.partner/records" -Params @{
        fields = @("name", "display_name", "email", "phone", "mobile", "company_id", "street", "city", "country_id", "vat", "website")
        limit = 80
        count = $true
    }
    $script:PartnerRecords = @($RecordResult.records)

    $Grid.Rows.Clear()
    foreach ($Record in $script:PartnerRecords) {
        [void]$Grid.Rows.Add($Record.id, $Record.display_name, $Record.email, $Record.phone)
    }

    if ($script:PartnerRecords.Count -gt 0) {
        Load-PartnerForm -Record $script:PartnerRecords[0]
    }

    Set-Status "Contactos cargados: $($script:PartnerRecords.Count) de $($RecordResult.total)"
}

function Connect-NativeUi {
    Set-Status "Probando bridge..."
    $Health = Invoke-OdooJson -Path "/native-ui/health"

    Set-Status "Autenticando..."
    $Auth = Invoke-OdooJson -Path "/web/session/authenticate" -Params @{
        db = $DatabaseBox.Text
        login = $LoginBox.Text
        password = $PasswordBox.Text
    }

    if (-not $Auth.uid) {
        throw "No se pudo autenticar."
    }

    Set-Status "Cargando snapshot..."
    $SessionInfo = Invoke-OdooJson -Path "/native-ui/session"
    $script:Snapshot = Invoke-OdooJson -Path "/native-ui/snapshot/index"

    $AppsList.Items.Clear()
    foreach ($App in @($script:Snapshot.menus.children)) {
        [void]$AppsList.Items.Add($App.name)
    }

    $InfoBox.Text = "Bridge $($Health.bridge_version) | Odoo $($Health.odoo_version) | Usuario $($SessionInfo.user.name) | DB $($SessionInfo.database)"
    Set-Status "Conectado. Apps: $($AppsList.Items.Count)"
    Load-Contacts
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$Window = New-Object System.Windows.Forms.Form
$Window.Text = "Odoo Native UI Lab"
$Window.Width = 1180
$Window.Height = 760
$Window.StartPosition = "CenterScreen"
$Window.MinimumSize = New-Object System.Drawing.Size(980, 620)

$Root = New-Object System.Windows.Forms.TableLayoutPanel
$Root.Dock = "Fill"
$Root.RowCount = 3
$Root.ColumnCount = 1
$Root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 72)))
$Root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$Root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
$Window.Controls.Add($Root)

$Top = New-Object System.Windows.Forms.TableLayoutPanel
$Top.Dock = "Fill"
$Top.ColumnCount = 9
$Top.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 6)
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 64)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 35)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 96)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 35)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 80)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 30)))
$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 118)))
$Root.Controls.Add($Top, 0, 0)

$UrlLabel = New-Object System.Windows.Forms.Label
$UrlLabel.Text = "Servidor"
$UrlLabel.AutoSize = $true
$UrlLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 4, 0)
$Top.Controls.Add($UrlLabel, 0, 0)

$UrlBox = New-Object System.Windows.Forms.TextBox
$UrlBox.Text = $Url
$UrlBox.Dock = "Fill"
$UrlBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
$Top.Controls.Add($UrlBox, 1, 0)

$DbLabel = New-Object System.Windows.Forms.Label
$DbLabel.Text = "DB"
$DbLabel.AutoSize = $true
$DbLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 4, 0)
$Top.Controls.Add($DbLabel, 2, 0)

$DatabaseBox = New-Object System.Windows.Forms.TextBox
$DatabaseBox.Text = $Database
$DatabaseBox.Dock = "Fill"
$DatabaseBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
$Top.Controls.Add($DatabaseBox, 3, 0)

$LoginLabel = New-Object System.Windows.Forms.Label
$LoginLabel.Text = "Login"
$LoginLabel.AutoSize = $true
$LoginLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 4, 0)
$Top.Controls.Add($LoginLabel, 4, 0)

$LoginBox = New-Object System.Windows.Forms.TextBox
$LoginBox.Text = $Login
$LoginBox.Dock = "Fill"
$LoginBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
$Top.Controls.Add($LoginBox, 5, 0)

$PasswordLabel = New-Object System.Windows.Forms.Label
$PasswordLabel.Text = "Clave"
$PasswordLabel.AutoSize = $true
$PasswordLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 4, 0)
$Top.Controls.Add($PasswordLabel, 6, 0)

$PasswordBox = New-Object System.Windows.Forms.TextBox
$PasswordBox.Text = $Password
$PasswordBox.UseSystemPasswordChar = $true
$PasswordBox.Dock = "Fill"
$PasswordBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
$Top.Controls.Add($PasswordBox, 7, 0)

$ConnectButton = New-Object System.Windows.Forms.Button
$ConnectButton.Text = "Conectar"
$ConnectButton.Dock = "Fill"
$ConnectButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
$Top.Controls.Add($ConnectButton, 8, 0)

$InfoBox = New-Object System.Windows.Forms.TextBox
$InfoBox.ReadOnly = $true
$InfoBox.Dock = "Fill"
$InfoBox.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$Top.SetColumnSpan($InfoBox, 9)
$Top.Controls.Add($InfoBox, 0, 1)

$Main = New-Object System.Windows.Forms.SplitContainer
$Main.Dock = "Fill"
$Main.SplitterDistance = 220
$Root.Controls.Add($Main, 0, 1)

$LeftPanel = New-Object System.Windows.Forms.Panel
$LeftPanel.Dock = "Fill"
$LeftPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$Main.Panel1.Controls.Add($LeftPanel)

$AppsLabel = New-Object System.Windows.Forms.Label
$AppsLabel.Text = "Apps visibles"
$AppsLabel.Dock = "Top"
$AppsLabel.Height = 24
$LeftPanel.Controls.Add($AppsLabel)

$AppsList = New-Object System.Windows.Forms.ListBox
$AppsList.Dock = "Fill"
$LeftPanel.Controls.Add($AppsList)

$RightSplit = New-Object System.Windows.Forms.SplitContainer
$RightSplit.Dock = "Fill"
$RightSplit.Orientation = "Horizontal"
$RightSplit.SplitterDistance = 300
$Main.Panel2.Controls.Add($RightSplit)

$Grid = New-Object System.Windows.Forms.DataGridView
$Grid.Dock = "Fill"
$Grid.AllowUserToAddRows = $false
$Grid.AllowUserToDeleteRows = $false
$Grid.ReadOnly = $true
$Grid.SelectionMode = "FullRowSelect"
$Grid.MultiSelect = $false
$Grid.AutoSizeColumnsMode = "Fill"
[void]$Grid.Columns.Add("id", "ID")
[void]$Grid.Columns.Add("display_name", "Contacto")
[void]$Grid.Columns.Add("email", "Email")
[void]$Grid.Columns.Add("phone", "Telefono")
$Grid.Columns["id"].Width = 70
$RightSplit.Panel1.Controls.Add($Grid)

$FormPanel = New-Object System.Windows.Forms.Panel
$FormPanel.Dock = "Fill"
$FormPanel.AutoScroll = $true
$FormPanel.Padding = New-Object System.Windows.Forms.Padding(12)
$RightSplit.Panel2.Controls.Add($FormPanel)

$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Text = "Listo."
$StatusLabel.Dock = "Fill"
$StatusLabel.TextAlign = "MiddleLeft"
$StatusLabel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$Root.Controls.Add($StatusLabel, 0, 2)

$ConnectButton.Add_Click({
    try {
        $script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $script:Url = $UrlBox.Text
        Connect-NativeUi
    } catch {
        Set-Status "Error"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Odoo Native UI Lab", "OK", "Error") | Out-Null
    }
})

$Grid.Add_SelectionChanged({
    if ($Grid.SelectedRows.Count -eq 0) { return }
    $Index = $Grid.SelectedRows[0].Index
    if ($Index -ge 0 -and $Index -lt $script:PartnerRecords.Count) {
        Load-PartnerForm -Record $script:PartnerRecords[$Index]
    }
})

$Window.Add_Shown({
    if ($PasswordBox.Text) {
        $ConnectButton.PerformClick()
    }
})

[void]$Window.ShowDialog()
