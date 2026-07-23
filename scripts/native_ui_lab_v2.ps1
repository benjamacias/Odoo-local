param(
    [string] $Url = "http://127.0.0.1:8069",
    [string] $Database = "odoo",
    [string] $Login = "admin",
    [string] $Password = ""
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:BaseUrl = $Url
$script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$script:PartnerFields = $null
$script:PartnerRecords = @()
$script:CurrentModel = "res.partner"
$script:CurrentModelName = "Contactos"
$script:CurrentFields = $null
$script:CurrentIr = $null
$script:CurrentPermissions = $null
$script:CurrentRecords = @()
$script:CurrentListFields = @("display_name", "email", "phone", "mobile")
$script:CurrentDetailFields = @("name", "email", "phone", "mobile", "company_id", "street", "city", "country_id", "vat", "website")
$script:CurrentDetailSections = @()
$script:CurrentRecord = $null
$script:IsReadOnlyModel = $false
$script:CurrentDomain = @()
$script:Offset = 0
$script:Limit = 30
$script:Total = 0
$script:FormControls = @{}
$script:FieldCache = @{}
$script:IrCache = @{}
$script:PermissionsCache = @{}
$script:SnapshotRoot = $null
$script:SuppressMenuOpen = $false
$script:IsLoading = $false
$script:LoadingText = ""
$script:LoadingFrame = 0
$script:LoadingFrames = @("|", "/", "-", "\")
$script:EditableFields = @("name", "email", "phone", "mobile", "street", "city", "vat", "website")
$script:VisibleFields = @("name", "email", "phone", "mobile", "company_id", "street", "city", "country_id", "vat", "website")

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
    } | ConvertTo-Json -Depth 100

    $Response = Invoke-RestMethod `
        -Uri (($script:BaseUrl.TrimEnd("/")) + $Path) `
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

function Start-Loading {
    param([string] $Text)
    $script:IsLoading = $true
    $script:LoadingText = $Text
    $script:LoadingFrame = 0
    if ($LoadingBar) {
        $LoadingBar.Visible = $true
        $LoadingBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        $LoadingBar.MarqueeAnimationSpeed = 35
    }
    if ($LoadingTimer) {
        $LoadingTimer.Start()
    }
    if ($Window) {
        $Window.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    }
    Set-Status "$($script:LoadingFrames[0]) $Text"
}

function Stop-Loading {
    param([string] $Text = "")
    $script:IsLoading = $false
    if ($LoadingTimer) {
        $LoadingTimer.Stop()
    }
    if ($LoadingBar) {
        $LoadingBar.Visible = $false
        $LoadingBar.MarqueeAnimationSpeed = 0
    }
    if ($Window) {
        $Window.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    if ($Text) {
        Set-Status $Text
    }
}

function Step-Loading {
    if (-not $script:IsLoading) { return }
    $script:LoadingFrame = ($script:LoadingFrame + 1) % $script:LoadingFrames.Count
    $StatusLabel.Text = "$($script:LoadingFrames[$script:LoadingFrame]) $script:LoadingText"
}

function Get-FriendlyError {
    param($ErrorRecord)
    $Message = $ErrorRecord.Exception.Message
    try {
        $Payload = $Message | ConvertFrom-Json
        if ($Payload.data.message) { return $Payload.data.message }
        if ($Payload.message) { return $Payload.message }
    } catch {
    }
    return $Message
}

$script:ColorBackground = [System.Drawing.ColorTranslator]::FromHtml("#F3F6FA")
$script:ColorSurface = [System.Drawing.ColorTranslator]::FromHtml("#FFFFFF")
$script:ColorPanel = [System.Drawing.ColorTranslator]::FromHtml("#F8FAFC")
$script:ColorMuted = [System.Drawing.ColorTranslator]::FromHtml("#E9EEF5")
$script:ColorBorder = [System.Drawing.ColorTranslator]::FromHtml("#D6DEE9")
$script:ColorText = [System.Drawing.ColorTranslator]::FromHtml("#172033")
$script:ColorSubtleText = [System.Drawing.ColorTranslator]::FromHtml("#667085")
$script:ColorAccent = [System.Drawing.ColorTranslator]::FromHtml("#714B67")
$script:ColorAccentDark = [System.Drawing.ColorTranslator]::FromHtml("#5A3B52")
$script:ColorAccentSoft = [System.Drawing.ColorTranslator]::FromHtml("#F2EAF0")
$script:ColorFocus = [System.Drawing.ColorTranslator]::FromHtml("#2563EB")

function Set-FlatButton {
    param(
        [System.Windows.Forms.Button] $Button,
        [bool] $Primary = $false
    )
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = if ($Primary) { $script:ColorAccent } else { $script:ColorBorder }
    $Button.FlatAppearance.MouseOverBackColor = if ($Primary) { $script:ColorAccentDark } else { $script:ColorPanel }
    $Button.FlatAppearance.MouseDownBackColor = if ($Primary) { $script:ColorAccentDark } else { $script:ColorMuted }
    $Button.BackColor = if ($Primary) { $script:ColorAccent } else { $script:ColorSurface }
    $Button.ForeColor = if ($Primary) { [System.Drawing.Color]::White } else { $script:ColorText }
    $Button.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
}

function Set-InputStyle {
    param([System.Windows.Forms.Control] $Control)
    $Control.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $Control.BackColor = $script:ColorSurface
    $Control.ForeColor = $script:ColorText
    if ($Control -is [System.Windows.Forms.TextBox]) {
        $Control.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    }
    if ($Control -is [System.Windows.Forms.ComboBox]) {
        $Control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    }
}

function Set-FieldLabelStyle {
    param([System.Windows.Forms.Label] $Label)
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $Label.ForeColor = $script:ColorSubtleText
}

function Set-ModernGrid {
    param([System.Windows.Forms.DataGridView] $GridControl)
    $GridControl.BackgroundColor = $script:ColorSurface
    $GridControl.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $GridControl.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $GridControl.GridColor = $script:ColorMuted
    $GridControl.EnableHeadersVisualStyles = $false
    $GridControl.ColumnHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None
    $GridControl.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#EEF2F7")
    $GridControl.ColumnHeadersDefaultCellStyle.ForeColor = $script:ColorText
    $GridControl.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $GridControl.ColumnHeadersHeight = 36
    $GridControl.RowTemplate.Height = 32
    $GridControl.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $GridControl.DefaultCellStyle.SelectionBackColor = $script:ColorFocus
    $GridControl.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $GridControl.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
    $GridControl.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#FAFBFD")
    $GridControl.RowHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None
}

function Apply-LabLayout {
    if (-not $Main -or -not $ContentSplit) { return }
    if ($Main.Width -gt 900) {
        $MainDistance = [Math]::Min(340, [Math]::Max(300, [int]($Main.Width * 0.21)))
        $Main.SplitterDistance = [Math]::Min($MainDistance, $Main.Width - 620)
    }
    if ($ContentSplit.Width -gt 920) {
        $DetailWidth = [Math]::Min(420, [Math]::Max(360, [int]($ContentSplit.Width * 0.28)))
        $Distance = $ContentSplit.Width - $DetailWidth
        $ContentSplit.SplitterDistance = [Math]::Min([Math]::Max(560, $Distance), $ContentSplit.Width - 340)
    }
}

function Get-RecordValue {
    param($Record, [string] $FieldName)
    if (-not $Record) { return $null }
    $Property = $Record.PSObject.Properties[$FieldName]
    if ($Property) { return $Property.Value }
    return $null
}

function Format-OdooValue {
    param($Value)
    if ($null -eq $Value -or $false -eq $Value) { return "" }
    if ($Value -is [array]) { return ($Value -join " - ") }
    return [string]$Value
}

function Convert-HtmlToPlainText {
    param($Html)
    if (-not $Html) { return "" }
    $Text = [string]$Html
    $Text = $Text -replace '(?i)<br\s*/?>', "`r`n"
    $Text = $Text -replace '(?i)</p>', "`r`n"
    $Text = $Text -replace '<[^>]+>', ''
    return ([System.Net.WebUtility]::HtmlDecode($Text)).Trim()
}

function Get-FieldMeta {
    param([string] $FieldName)
    if (-not $script:CurrentFields) { return $null }
    $Property = $script:CurrentFields.PSObject.Properties[$FieldName]
    if ($Property) { return $Property.Value }
    return $null
}

function Test-FieldExists {
    param([string] $FieldName)
    if ($FieldName -eq "display_name") { return $true }
    return $null -ne (Get-FieldMeta $FieldName)
}

function Test-TruthyViewValue {
    param($Value)
    if ($null -eq $Value -or $false -eq $Value) { return $false }
    $Text = ([string]$Value).Trim()
    return $Text -in @("1", "true", "True", "TRUE")
}

function Test-ListFieldType {
    param([string] $FieldName)
    if ($FieldName -eq "display_name") { return $true }
    $Meta = Get-FieldMeta $FieldName
    if (-not $Meta) { return $false }
    return $Meta.type -in @("char", "text", "phone", "url", "email", "many2one", "selection", "boolean", "integer", "float", "monetary", "date", "datetime")
}

function Test-DetailFieldType {
    param([string] $FieldName)
    if ($FieldName -eq "display_name") { return $true }
    $Meta = Get-FieldMeta $FieldName
    if (-not $Meta) { return $false }
    return $Meta.type -in @("char", "text", "html", "phone", "url", "email", "many2one", "selection", "boolean", "integer", "float", "monetary", "date", "datetime")
}

function Add-IrFieldName {
    param(
        [System.Collections.ArrayList] $Fields,
        [string] $FieldName
    )
    if (-not $FieldName) { return }
    if (-not (Test-FieldExists $FieldName)) { return }
    if (-not $Fields.Contains($FieldName)) {
        [void]$Fields.Add($FieldName)
    }
}

function Add-IrFieldsRecursive {
    param(
        $Node,
        [System.Collections.ArrayList] $Fields,
        [ValidateSet("list", "detail")] [string] $Purpose
    )
    if (-not $Node) { return }

    $Props = $Node.properties
    if ($Node.type -eq "Field" -and $Props -and -not (Test-TruthyViewValue $Props.invisible)) {
        $Name = [string]$Props.name
        if (($Purpose -eq "list" -and (Test-ListFieldType $Name)) -or ($Purpose -eq "detail" -and (Test-DetailFieldType $Name))) {
            Add-IrFieldName -Fields $Fields -FieldName $Name
        }
    }

    foreach ($Child in @($Node.children)) {
        Add-IrFieldsRecursive -Node $Child -Fields $Fields -Purpose $Purpose
    }
}

function Test-SkipDetailNode {
    param($Node)
    if (-not $Node) { return $true }
    $Props = $Node.properties
    if ($Props -and (Test-TruthyViewValue $Props.invisible)) { return $true }
    if ($Node.type -in @("Header", "Footer", "Button")) { return $true }
    if ($Node.tag -in @("chatter", "header", "footer", "button")) { return $true }
    if ($Props -and $Props.class) {
        $ClassText = [string]$Props.class
        if ($ClassText -match "alert|oe_button_box|o_stat_info|oe_stat_button") { return $true }
    }
    if ($Props -and $Props.widget) {
        $Widget = [string]$Props.widget
        if ($Widget -match "statinfo|activity|x2many_buttons|many2many_tags|mail_") { return $true }
    }
    return $false
}

function Add-DetailFieldsFromNode {
    param(
        $Node,
        [System.Collections.ArrayList] $Fields,
        [bool] $StopAtTabs = $false
    )
    if (Test-SkipDetailNode $Node) { return }
    if ($StopAtTabs -and $Node.type -in @("Notebook", "Tab")) { return }

    $Props = $Node.properties
    if ($Node.type -eq "Field" -and $Props) {
        $Name = [string]$Props.name
        if ((Test-DetailFieldType $Name) -and -not $Fields.Contains($Name)) {
            [void]$Fields.Add($Name)
        }
    }

    foreach ($Child in @($Node.children)) {
        Add-DetailFieldsFromNode -Node $Child -Fields $Fields -StopAtTabs $StopAtTabs
    }
}

function Add-DetailTabSectionsFromNode {
    param(
        $Node,
        [System.Collections.ArrayList] $Sections,
        [System.Collections.Hashtable] $SeenFields
    )
    if (Test-SkipDetailNode $Node) { return }

    if ($Node.type -eq "Tab") {
        $Fields = New-Object System.Collections.ArrayList
        Add-DetailFieldsFromNode -Node $Node -Fields $Fields -StopAtTabs:$false
        $VisibleFields = @()
        foreach ($FieldName in @($Fields | Select-Object -First 14)) {
            if ($SeenFields.ContainsKey($FieldName)) { continue }
            $SeenFields[$FieldName] = $true
            $VisibleFields += $FieldName
        }
        if ($VisibleFields.Count -gt 0) {
            $Title = if ($Node.properties.string) { [string]$Node.properties.string } elseif ($Node.properties.name) { [string]$Node.properties.name } else { "Detalle" }
            [void]$Sections.Add([pscustomobject]@{ title = $Title; fields = $VisibleFields })
        }
        return
    }

    foreach ($Child in @($Node.children)) {
        Add-DetailTabSectionsFromNode -Node $Child -Sections $Sections -SeenFields $SeenFields
    }
}

function Get-DetailSections {
    $Sections = New-Object System.Collections.ArrayList
    $SeenFields = @{}
    $FormDoc = $null
    if ($script:CurrentIr) {
        $Property = $script:CurrentIr.PSObject.Properties["form"]
        if ($Property) { $FormDoc = $Property.Value }
    }

    if ($FormDoc -and $FormDoc.root) {
        $MainFields = New-Object System.Collections.ArrayList
        Add-DetailFieldsFromNode -Node $FormDoc.root -Fields $MainFields -StopAtTabs:$true
        $VisibleMain = @()
        foreach ($FieldName in @($MainFields | Select-Object -First 14)) {
            if ($SeenFields.ContainsKey($FieldName)) { continue }
            $SeenFields[$FieldName] = $true
            $VisibleMain += $FieldName
        }
        if ($VisibleMain.Count -gt 0) {
            [void]$Sections.Add([pscustomobject]@{ title = "General"; fields = $VisibleMain })
        }

        Add-DetailTabSectionsFromNode -Node $FormDoc.root -Sections $Sections -SeenFields $SeenFields
    }

    if ($Sections.Count -eq 0) {
        $FallbackFields = @(Get-IrFieldNames -ViewType "form" -Purpose "detail" -Limit 18)
        if ($FallbackFields.Count -gt 0) {
            [void]$Sections.Add([pscustomobject]@{ title = "General"; fields = $FallbackFields })
        }
    }

    return @($Sections)
}

function Get-IrFieldNames {
    param(
        [string] $ViewType,
        [ValidateSet("list", "detail")] [string] $Purpose,
        [int] $Limit
    )

    $Fields = New-Object System.Collections.ArrayList
    $Doc = $null
    if ($script:CurrentIr) {
        $Property = $script:CurrentIr.PSObject.Properties[$ViewType]
        if ($Property) { $Doc = $Property.Value }
    }
    if ($Doc -and $Doc.root) {
        Add-IrFieldsRecursive -Node $Doc.root -Fields $Fields -Purpose $Purpose
    }
    return @($Fields | Select-Object -First $Limit)
}

function Get-RenderableViews {
    param([array] $Views)

    $Renderable = New-Object System.Collections.ArrayList
    $SeenTypes = @{}
    foreach ($View in @($Views)) {
        $ViewId = $false
        $ViewType = ""

        if ($View -is [array] -and $View.Count -ge 2) {
            $ViewId = $View[0]
            $ViewType = [string]$View[1]
        } elseif ($View -and $View.PSObject.Properties["type"]) {
            $ViewId = if ($View.PSObject.Properties["id"]) { $View.id } else { $false }
            $ViewType = [string]$View.type
        }

        if ($ViewType -eq "tree") { $ViewType = "list" }
        if ($ViewType -notin @("list", "form", "search")) { continue }
        if ($SeenTypes.ContainsKey($ViewType)) { continue }

        $SeenTypes[$ViewType] = $true
        [void]$Renderable.Add(@{
            id = if ($ViewId -and "$ViewId" -ne "False") { [int]$ViewId } else { $false }
            type = $ViewType
        })
    }

    foreach ($RequiredType in @("list", "form")) {
        if (-not $SeenTypes.ContainsKey($RequiredType)) {
            [void]$Renderable.Add(@{ id = $false; type = $RequiredType })
        }
    }
    return @($Renderable)
}

function Get-ViewsCacheKey {
    param(
        [string] $ModelName,
        [array] $Views
    )
    $Parts = @()
    foreach ($View in @($Views)) {
        $Parts += "$($View.type):$($View.id)"
    }
    return "$ModelName|" + ($Parts -join ",")
}

function Get-NativeDomainTerms {
    param($Domain)

    $Terms = @()
    foreach ($Term in @($Domain)) {
        if ($null -eq $Term -or $false -eq $Term) { continue }
        if ($Term -is [array] -and $Term.Count -eq 0) { continue }
        $Terms += ,$Term
    }
    return $Terms
}

function Get-PreferredListFields {
    param([string] $ModelName)
    $IrFields = @(Get-IrFieldNames -ViewType "list" -Purpose "list" -Limit 7)
    if ($IrFields.Count -gt 0) { return $IrFields }

    $Candidates = @(
        "display_name",
        "name",
        "email",
        "phone",
        "mobile",
        "partner_id",
        "channel_type",
        "member_count",
        "state",
        "date_order",
        "amount_total",
        "default_code",
        "list_price",
        "qty_available"
    )
    $Fields = @()
    foreach ($Candidate in $Candidates) {
        if ((Test-FieldExists $Candidate) -and -not ($Fields -contains $Candidate)) {
            $Fields += $Candidate
        }
    }
    if ($Fields.Count -eq 0) { return @("display_name") }
    return $Fields | Select-Object -First 5
}

function Get-PreferredDetailFields {
    param([string] $ModelName)
    $IrFields = @(Get-IrFieldNames -ViewType "form" -Purpose "detail" -Limit 18)
    if ($IrFields.Count -gt 0) { return $IrFields }

    $Candidates = @(
        "name",
        "display_name",
        "email",
        "phone",
        "mobile",
        "partner_id",
        "channel_type",
        "description",
        "member_count",
        "company_id",
        "state",
        "date_order",
        "amount_total",
        "street",
        "city",
        "country_id",
        "vat",
        "website",
        "default_code",
        "list_price",
        "qty_available"
    )
    $Fields = @()
    foreach ($Candidate in $Candidates) {
        if ((Test-FieldExists $Candidate) -and -not ($Fields -contains $Candidate)) {
            $Fields += $Candidate
        }
    }
    return $Fields | Select-Object -First 14
}

function Get-FieldTitle {
    param([string] $FieldName)
    if ($FieldName -eq "display_name") { return "Nombre" }
    $Meta = Get-FieldMeta $FieldName
    if ($Meta -and $Meta.string) { return $Meta.string }
    return $FieldName
}

function Test-SearchableField {
    param([string] $FieldName)
    if ($FieldName -eq "display_name") { return $true }
    $Meta = Get-FieldMeta $FieldName
    if (-not $Meta) { return $false }
    return $Meta.type -in @("char", "text", "html", "phone", "url", "email", "many2one", "selection")
}

function Update-CentralSearchFields {
    if (-not $SearchFieldBox) { return }

    $Previous = if ($SearchFieldBox.SelectedItem) { [string]$SearchFieldBox.SelectedItem.Value } else { "__all__" }
    $Options = New-Object System.Collections.ArrayList
    [void]$Options.Add([pscustomobject]@{ Value = "__all__"; Label = "Todo visible" })

    $CandidateFields = @("display_name") + @($script:CurrentListFields) + @($script:CurrentDetailFields)
    foreach ($FieldName in @($CandidateFields | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-SearchableField $FieldName) {
            [void]$Options.Add([pscustomobject]@{ Value = $FieldName; Label = (Get-FieldTitle $FieldName) })
        }
    }

    $SearchFieldBox.DisplayMember = "Label"
    $SearchFieldBox.ValueMember = "Value"
    $SearchFieldBox.DataSource = $Options
    $SearchFieldBox.SelectedValue = $Previous
    if ($SearchFieldBox.SelectedIndex -lt 0) {
        $SearchFieldBox.SelectedIndex = 0
    }
}

function Normalize-SearchText {
    param([string] $Text)
    if (-not $Text) { return "" }
    $Normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $Builder = New-Object System.Text.StringBuilder
    foreach ($Char in $Normalized.ToCharArray()) {
        $Category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($Char)
        if ($Category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$Builder.Append($Char)
        }
    }
    return ($Builder.ToString().Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ').Trim()
}

function Get-SearchTokens {
    param([string] $Query)
    $Normalized = Normalize-SearchText $Query
    if (-not $Normalized) { return @() }
    return @($Normalized -split '\s+' | Where-Object { $_ })
}

function Test-MenuMatchesFilter {
    param(
        $Menu,
        [array] $Tokens,
        [string] $Path = ""
    )
    if (-not $Menu) { return $false }
    if (-not $Tokens -or $Tokens.Count -eq 0) { return $true }

    $CurrentPath = if ($Path) { "$Path $($Menu.name)" } else { [string]$Menu.name }
    $Haystack = Normalize-SearchText "$CurrentPath $($Menu.xmlid)"
    $MatchedAll = $true
    foreach ($Token in @($Tokens)) {
        if ($Haystack.IndexOf($Token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $MatchedAll = $false
            break
        }
    }
    if ($MatchedAll) { return $true }

    foreach ($Child in @($Menu.children)) {
        if (Test-MenuMatchesFilter -Menu $Child -Tokens $Tokens -Path $CurrentPath) { return $true }
    }
    return $false
}

function Add-MenuNode {
    param(
        [System.Windows.Forms.TreeNodeCollection] $Nodes,
        $Menu,
        [array] $Tokens = @(),
        [string] $Path = "",
        [int] $Depth = 0
    )
    if (-not $Menu -or -not $Menu.name) { return }
    if (-not (Test-MenuMatchesFilter -Menu $Menu -Tokens $Tokens -Path $Path)) { return }

    $Node = New-Object System.Windows.Forms.TreeNode($Menu.name)
    $Node.Tag = $Menu
    $CurrentPath = if ($Path) { "$Path / $($Menu.name)" } else { [string]$Menu.name }
    $Node.ToolTipText = $CurrentPath
    if ($Depth -eq 0) {
        $Node.NodeFont = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    }
    foreach ($Child in @($Menu.children)) {
        if (-not $Tokens -or $Tokens.Count -eq 0 -or (Test-MenuMatchesFilter -Menu $Child -Tokens $Tokens -Path $CurrentPath)) {
            Add-MenuNode -Nodes $Node.Nodes -Menu $Child -Tokens $Tokens -Path $CurrentPath -Depth ($Depth + 1)
        }
    }
    [void]$Nodes.Add($Node)
}

function New-StaticConnectionMenu {
    return [pscustomobject]@{
        id = "__native_connection"
        name = "Conexion"
        xmlid = "native.static.connection"
        static_view = "connection"
        children = @()
    }
}

function Rebuild-AppsTree {
    param([string] $Query = "")
    $Tokens = @(Get-SearchTokens $Query)
    $script:SuppressMenuOpen = $true
    $AppsTree.BeginUpdate()
    try {
        $AppsTree.Nodes.Clear()
        Add-MenuNode -Nodes $AppsTree.Nodes -Menu (New-StaticConnectionMenu) -Tokens $Tokens
        if ($script:SnapshotRoot) {
            foreach ($App in @($script:SnapshotRoot.children)) {
            Add-MenuNode -Nodes $AppsTree.Nodes -Menu $App -Tokens $Tokens
            }
        }
        if ($Tokens.Count -gt 0) {
            $AppsTree.ExpandAll()
        } else {
            $AppsTree.CollapseAll()
        }
        if ($NavCountLabel) {
            $DynamicCount = if ($script:SnapshotRoot) { @($script:SnapshotRoot.children).Count } else { 0 }
            $Text = if ($Tokens.Count -eq 0) { "$DynamicCount apps visibles" } else { "$($AppsTree.GetNodeCount($true)) coincidencias para '$Query'" }
            $NavCountLabel.Text = $Text
        }
    } finally {
        $AppsTree.EndUpdate()
        $script:SuppressMenuOpen = $false
    }
}

function Show-DynamicView {
    if ($StaticHost) { $StaticHost.Visible = $false }
    if ($ContentSplit) {
        $ContentSplit.Visible = $true
        $ContentSplit.BringToFront()
    }
}

function Show-ConnectionView {
    if ($Window) { $Window.Text = "Odoo Native UI - Conexion" }
    if ($ContentSplit) { $ContentSplit.Visible = $false }
    if ($StaticHost) {
        $StaticHost.Visible = $true
        $StaticHost.BringToFront()
    }
    if ($NavCountLabel -and -not $script:SnapshotRoot) {
        $NavCountLabel.Text = "Configura la conexion"
    }
    Set-Status "Vista estatica de conexion lista para configurar."
}

function Test-MenuHasUsableAction {
    param($Menu)
    if (-not $Menu -or -not $Menu.action) { return $false }
    if ($Menu.action.endpoint -and $Menu.action.id -and [int]$Menu.action.id -gt 0) { return $true }
    if ($Menu.action.raw -and ([string]$Menu.action.raw) -match ',\\d+$') { return $true }
    return $false
}

function Find-FirstActionMenu {
    param($Menu)
    if (-not $Menu) { return $null }
    if (Test-MenuHasUsableAction $Menu) { return $Menu }
    foreach ($Child in @($Menu.children)) {
        $Match = Find-FirstActionMenu $Child
        if ($Match) { return $Match }
    }
    return $null
}

function Show-UnsupportedAction {
    param(
        [string] $Title,
        [string] $ActionType,
        [string] $Message,
        [string] $StatusText = ""
    )

    Show-DynamicView
    $script:CurrentModel = ""
    $script:CurrentModelName = $Title
    $script:CurrentRecords = @()
    $script:CurrentRecord = $null
    $script:FormControls = @{}
    $script:IsReadOnlyModel = $true
    if ($ListTitle) { $ListTitle.Text = $Title }
    if ($ListSubtitle) { $ListSubtitle.Text = $ActionType }

    $Grid.Rows.Clear()
    $Grid.Columns.Clear()
    [void]$Grid.Columns.Add("message", "Estado")
    $Grid.Columns["message"].FillWeight = 100
    [void]$Grid.Rows.Add($Message)

    $DetailBody.Controls.Clear()
    $DetailTitle.Text = $Title
    if ($DetailSubtitle) { $DetailSubtitle.Text = $ActionType }

    $Notice = New-Object System.Windows.Forms.Label
    $Notice.Dock = "Top"
    $Notice.AutoSize = $true
    $Notice.MaximumSize = New-Object System.Drawing.Size(360, 0)
    $Notice.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $Notice.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $Notice.ForeColor = $script:ColorText
    $Notice.Text = $Message
    $DetailBody.Controls.Add($Notice)

    $PageLabel.Text = "0-0 de 0"
    if ($SearchFieldBox) { $SearchFieldBox.Enabled = $false }
    $SearchButton.Enabled = $false
    $ReloadButton.Enabled = $false
    $PrevButton.Enabled = $false
    $NextButton.Enabled = $false
    $NewButton.Enabled = $false
    $SaveButton.Enabled = $false
    $CancelButton.Enabled = $false
    if ($StatusText) {
        Set-Status $StatusText
    } else {
        Set-Status "Vista no disponible en modo nativo: $Title [$ActionType]"
    }
}

function Show-UrlAction {
    param(
        [string] $Title,
        $Action
    )

    $Url = [string]$Action.url
    Show-UnsupportedAction `
        -Title $Title `
        -ActionType $Action.type `
        -Message "Esta accion abre un recurso externo o web de Odoo.`r`n$Url" `
        -StatusText "Accion URL detectada: $Title"

    if (-not $Url) { return }

    $OpenButton = New-Object System.Windows.Forms.Button
    $OpenButton.Text = "Abrir enlace"
    $OpenButton.Width = 140
    $OpenButton.Height = 32
    $OpenButton.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
    Set-FlatButton $OpenButton $true
    $OpenButton.Tag = $Url
    $OpenButton.Add_Click({
        param($Sender, $EventArgs)
        try {
            Start-Process ([string]$Sender.Tag)
        } catch {
            Set-Status "No se pudo abrir el enlace: $(Get-FriendlyError $_)"
        }
    })
    $DetailBody.Controls.Add($OpenButton)
    $OpenButton.BringToFront()
}

function Open-ClientAction {
    param(
        $Action,
        [string] $Title
    )

    $ActionPath = [string]$Action.path
    $ActionName = [string]$Action.name
    if ($ActionPath -eq "discuss" -or $ActionName -like "*Convers*") {
        Load-Model -ModelName "discuss.channel" -Title "Conversaciones" -ViewMode "list,form" -ReadOnly
        Set-Status "Conversaciones cargadas desde discuss.channel."
        return
    }

    if ([string]$Action.tag -in @("mail.discuss_notification_settings_action", "mail.discuss_call_settings_action")) {
        Show-UnsupportedAction `
            -Title $Title `
            -ActionType $Action.type `
            -Message "Este menu abre un dialogo de configuracion del cliente web de Odoo. El laboratorio nativo lo detecta y evita mezclar datos anteriores; falta construir el renderer especifico de este panel." `
            -StatusText "Panel cliente pendiente: $Title"
        return
    }

    Show-UnsupportedAction `
        -Title $Title `
        -ActionType $Action.type `
        -Message "Esta accion de cliente todavia no tiene renderer nativo en el laboratorio. Se limpio la vista para evitar mostrar datos anteriores." `
        -StatusText "Panel cliente pendiente: $Title"
}

function Open-MenuNode {
    param($Menu)
    if (-not $Menu) { return }
    if ($Menu.PSObject.Properties["static_view"] -and $Menu.static_view -eq "connection") {
        Show-ConnectionView
        return
    }
    $ActionMenu = Find-FirstActionMenu $Menu
    if (-not $ActionMenu -or -not (Test-MenuHasUsableAction $ActionMenu)) {
        Set-Status "Menu sin accion directa: $($Menu.name)"
        return
    }

    $ActionParams = @{}
    if ($ActionMenu.action.raw) {
        $ActionParams.action_ref = [string]$ActionMenu.action.raw
    } elseif ($ActionMenu.action.id) {
        $ActionParams.action_id = [int]$ActionMenu.action.id
    }

    $Action = if ($ActionParams.Count -gt 0) {
        Invoke-OdooJson -Path "/native-ui/action" -Params $ActionParams
    } else {
        Invoke-OdooJson -Path $ActionMenu.action.endpoint
    }

    if ($Action.type -eq "ir.actions.client") {
        Open-ClientAction -Action $Action -Title $ActionMenu.name
        return
    }

    if ($Action.type -eq "ir.actions.act_url") {
        Show-UrlAction -Title $ActionMenu.name -Action $Action
        return
    }

    if ($Action.type -ne "ir.actions.act_window" -or -not $Action.res_model) {
        $Target = if ($Action.url) { " URL: $($Action.url)" } elseif ($Action.path) { " Ruta: $($Action.path)" } else { "" }
        Show-UnsupportedAction `
            -Title $ActionMenu.name `
            -ActionType $Action.type `
            -Message "Esta accion no se puede representar como vista nativa todavia.$Target"
        return
    }

    $ActionDomain = Get-NativeDomainTerms $Action.domain_native
    $ActionViews = if ($Action.views) { @($Action.views) } else { @() }
    Load-Model -ModelName $Action.res_model -Title $ActionMenu.name -ViewMode $Action.view_mode -Domain $ActionDomain -Views $ActionViews
}

function Add-DetailField {
    param(
        [System.Windows.Forms.TableLayoutPanel] $Table,
        [string] $FieldName,
        $Meta,
        $Value
    )

    $Row = $Table.RowCount
    $Table.RowCount = $Row + 1
    [void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = if ($Meta.string) { $Meta.string } else { $FieldName }
    $Label.AutoSize = $true
    $Label.Margin = New-Object System.Windows.Forms.Padding(0, 8, 10, 4)
    $Label.ForeColor = $script:ColorText
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)

    $FieldType = [string]$Meta.type
    $CanEditType = $FieldType -in @("char", "text", "html", "phone", "url", "email", "boolean", "selection")
    $CanEdit = $CanEditType -and -not [bool]$Meta.readonly -and $FieldName -ne "display_name" -and -not $script:IsReadOnlyModel

    if ($FieldType -eq "selection" -and $Meta.selection) {
        $Control = New-Object System.Windows.Forms.ComboBox
        $Control.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $Control.Enabled = $CanEdit
        $Control.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $Control.BackColor = $script:ColorSurface
        $Control.ForeColor = $script:ColorText

        $Items = New-Object System.Collections.ArrayList
        foreach ($Option in @($Meta.selection)) {
            if ($Option -is [array] -and $Option.Count -ge 2) {
                [void]$Items.Add([pscustomobject]@{ Value = $Option[0]; Label = [string]$Option[1] })
            }
        }
        $Control.DisplayMember = "Label"
        $Control.ValueMember = "Value"
        $Control.DataSource = $Items
        if ($null -ne $Value -and $false -ne $Value) {
            $Control.SelectedValue = $Value
        } else {
            $Control.SelectedIndex = -1
        }
    } elseif ($FieldType -eq "boolean") {
        $Control = New-Object System.Windows.Forms.CheckBox
        $Control.Checked = [bool]$Value
        $Control.Enabled = $CanEdit
        $Control.AutoSize = $true
        $Control.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)
        $Control.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $Control.ForeColor = $script:ColorText
        $Control.BackColor = $script:ColorSurface
    } else {
        $Control = New-Object System.Windows.Forms.TextBox
        $Control.Text = Format-OdooValue $Value
        $Control.ReadOnly = -not $CanEdit
        if ($FieldType -in @("text", "html")) {
            $Control.Multiline = $true
            $Control.ScrollBars = "Vertical"
            $Control.Height = 78
        }
        Set-InputStyle $Control
        if ($Control.ReadOnly) {
            $Control.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#F1F5F9")
            $Control.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#64748B")
        }
    }

    $Control.Dock = "Fill"
    $Control.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)

    if ($Control -is [System.Windows.Forms.TextBox] -and $FieldName -in @("street", "website")) {
        $Control.Height = 42
    }

    $Table.Controls.Add($Label, 0, $Row)
    $Table.Controls.Add($Control, 1, $Row)
    if ($CanEdit) {
        $script:FormControls[$FieldName] = $Control
    }
}

function Add-DetailWideText {
    param(
        [System.Windows.Forms.TableLayoutPanel] $Table,
        [string] $Text,
        [bool] $Strong = $false
    )

    $Row = $Table.RowCount
    $Table.RowCount = $Row + 1
    [void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = $Text
    $Label.AutoSize = $true
    $Label.MaximumSize = New-Object System.Drawing.Size(360, 0)
    $Label.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)
    $Label.ForeColor = $script:ColorText
    $Style = if ($Strong) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $Label.Font = New-Object System.Drawing.Font("Segoe UI", 9, $Style)

    $Table.Controls.Add($Label, 0, $Row)
    $Table.SetColumnSpan($Label, 2)
}

function Add-DiscussMessages {
    param(
        [System.Windows.Forms.TableLayoutPanel] $Table,
        $Channel
    )

    $ChannelId = [int](Get-RecordValue $Channel "id")
    if ($ChannelId -le 0) { return }

    Add-DetailWideText -Table $Table -Text "Mensajes recientes" -Strong $true
    try {
        $Result = Invoke-OdooJson -Path "/native-ui/model/mail.message/records" -Params @{
            domain = @(
                @("model", "=", "discuss.channel"),
                @("res_id", "=", $ChannelId)
            )
            fields = @("body", "date", "author_id")
            offset = 0
            limit = 8
            count = $true
            order = "date desc"
        }

        if (-not $Result.records -or @($Result.records).Count -eq 0) {
            Add-DetailWideText -Table $Table -Text "Sin mensajes para este canal."
            return
        }

        foreach ($Message in @($Result.records)) {
            $AuthorValue = Get-RecordValue $Message "author_id"
            $Author = if ($AuthorValue -is [array] -and $AuthorValue.Count -gt 1) { $AuthorValue[1] } else { Format-OdooValue $AuthorValue }
            $Date = Format-OdooValue (Get-RecordValue $Message "date")
            $Body = Convert-HtmlToPlainText (Get-RecordValue $Message "body")
            Add-DetailWideText -Table $Table -Text "$Author - $Date`r`n$Body"
        }
    } catch {
        Add-DetailWideText -Table $Table -Text "No se pudieron cargar los mensajes: $(Get-FriendlyError $_)"
    }
}

function New-DetailTable {
    $Table = New-Object System.Windows.Forms.TableLayoutPanel
    $Table.Dock = "Top"
    $Table.AutoSize = $true
    $Table.ColumnCount = 2
    $Table.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 10)
    $Table.BackColor = $script:ColorSurface
    [void]$Table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 140)))
    [void]$Table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    return $Table
}

function Add-DetailFieldsToTable {
    param(
        [System.Windows.Forms.TableLayoutPanel] $Table,
        $Record,
        [array] $Fields
    )

    foreach ($FieldName in @($Fields)) {
        $Meta = Get-FieldMeta $FieldName
        if ($FieldName -eq "display_name") {
            $Meta = [pscustomobject]@{ string = "Nombre"; type = "char"; readonly = $true }
        }
        if (-not $Meta) { continue }
        Add-DetailField -Table $Table -FieldName $FieldName -Meta $Meta -Value (Get-RecordValue $Record $FieldName)
    }
}

function Focus-FirstEditableField {
    foreach ($Preferred in @("name", "email", "phone")) {
        if ($script:FormControls.ContainsKey($Preferred)) {
            $script:FormControls[$Preferred].Focus()
            if ($script:FormControls[$Preferred] -is [System.Windows.Forms.TextBox]) {
                $script:FormControls[$Preferred].SelectAll()
            }
            return
        }
    }

    foreach ($FieldName in @($script:FormControls.Keys)) {
        $script:FormControls[$FieldName].Focus()
        if ($script:FormControls[$FieldName] -is [System.Windows.Forms.TextBox]) {
            $script:FormControls[$FieldName].SelectAll()
        }
        return
    }
}

function Load-Detail {
    param($Record)

    $script:CurrentRecord = $Record
    $script:FormControls = @{}
    $DetailBody.Controls.Clear()

    if (-not $Record) {
        $DetailTitle.Text = "Sin registro"
        if ($DetailSubtitle) { $DetailSubtitle.Text = "" }
        return
    }

    $DetailTitle.Text = Format-OdooValue (Get-RecordValue $Record "display_name")
    if ($DetailSubtitle) {
        $DetailSubtitle.Text = "$script:CurrentModel  |  ID $(Get-RecordValue $Record "id")"
    }

    if ($script:CurrentDetailSections.Count -gt 1) {
        $Tabs = New-Object System.Windows.Forms.TabControl
        $Tabs.Dock = "Fill"
        $Tabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)

        foreach ($Section in @($script:CurrentDetailSections)) {
            $Tab = New-Object System.Windows.Forms.TabPage
            $Tab.Text = [string]$Section.title
            $Tab.BackColor = $script:ColorSurface

            $ScrollPanel = New-Object System.Windows.Forms.Panel
            $ScrollPanel.Dock = "Fill"
            $ScrollPanel.AutoScroll = $true
            $ScrollPanel.Padding = New-Object System.Windows.Forms.Padding(8)
            $ScrollPanel.BackColor = $script:ColorSurface

            $Table = New-DetailTable
            Add-DetailFieldsToTable -Table $Table -Record $Record -Fields @($Section.fields)
            if ($script:CurrentModel -eq "discuss.channel" -and $Section.title -eq $script:CurrentDetailSections[0].title) {
                Add-DiscussMessages -Table $Table -Channel $Record
            }
            $ScrollPanel.Controls.Add($Table)
            $Tab.Controls.Add($ScrollPanel)
            [void]$Tabs.TabPages.Add($Tab)
        }
        $DetailBody.Controls.Add($Tabs)
        return
    }

    $Fields = if ($script:CurrentDetailSections.Count -eq 1) { @($script:CurrentDetailSections[0].fields) } else { @($script:CurrentDetailFields) }
    $SingleTable = New-DetailTable
    Add-DetailFieldsToTable -Table $SingleTable -Record $Record -Fields $Fields
    if ($script:CurrentModel -eq "discuss.channel") {
        Add-DiscussMessages -Table $SingleTable -Channel $Record
    }
    $DetailBody.Controls.Add($SingleTable)
}

function Load-CurrentPage {
    param(
        [int] $Offset = $script:Offset,
        [int] $SelectId = 0,
        [string] $Order = ""
    )
    Load-ModelPage -Offset $Offset -SelectId $SelectId -Order $Order
}

function Load-ModelPage {
    param(
        [int] $Offset = $script:Offset,
        [int] $SelectId = 0,
        [string] $Order = ""
    )

    Start-Loading "Cargando $script:CurrentModelName..."
    try {
    $script:Offset = [Math]::Max(0, $Offset)
    $Query = $SearchBox.Text.Trim()
    $Domain = @()
    foreach ($Term in @($script:CurrentDomain)) {
        if ($null -eq $Term -or $false -eq $Term) { continue }
        $Domain += ,$Term
    }
    if ($Query) {
        $SelectedSearchField = if ($SearchFieldBox -and $SearchFieldBox.SelectedItem) { [string]$SearchFieldBox.SelectedItem.Value } else { "__all__" }
        if ($SelectedSearchField -and $SelectedSearchField -ne "__all__" -and (Test-SearchableField $SelectedSearchField)) {
            $Domain += ,@($SelectedSearchField, "ilike", $Query)
        } else {
            $SearchFields = @("display_name") + @($script:CurrentListFields)
            $SearchFields = @($SearchFields | Where-Object { $_ -and (Test-SearchableField $_) } | Select-Object -Unique | Select-Object -First 5)
            if ($SearchFields.Count -le 1) {
                $Field = if ($SearchFields.Count -eq 1) { $SearchFields[0] } elseif (Test-FieldExists "name") { "name" } else { "display_name" }
                $Domain += ,@($Field, "ilike", $Query)
            } else {
                for ($i = 0; $i -lt ($SearchFields.Count - 1); $i++) {
                    $Domain += ,"|"
                }
                foreach ($Field in $SearchFields) {
                    $Domain += ,@($Field, "ilike", $Query)
                }
            }
        }
    }

    $ReadFields = @("display_name") + @($script:CurrentListFields) + @($script:CurrentDetailFields)
    $ReadFields = @($ReadFields | Where-Object { $_ } | Select-Object -Unique)

    $RecordResult = Invoke-OdooJson -Path "/native-ui/model/$script:CurrentModel/records" -Params @{
        domain = $Domain
        fields = $ReadFields
        offset = $script:Offset
        limit = $script:Limit
        count = $true
        order = if ($Order) { $Order } elseif (Test-FieldExists "name") { "name" } else { "id" }
    }

    $script:Total = [int]$RecordResult.total
    $script:CurrentRecords = @($RecordResult.records)
    $script:PartnerRecords = $script:CurrentRecords
    $Grid.Rows.Clear()
    $Grid.Columns.Clear()

    [void]$Grid.Columns.Add("id", "ID")
    $Grid.Columns["id"].FillWeight = 12
    foreach ($FieldName in $script:CurrentListFields) {
        [void]$Grid.Columns.Add($FieldName, (Get-FieldTitle $FieldName))
        $Grid.Columns[$FieldName].FillWeight = if ($FieldName -eq "display_name" -or $FieldName -eq "name") { 42 } else { 24 }
    }

    foreach ($Record in $script:CurrentRecords) {
        $Values = New-Object System.Collections.ArrayList
        [void]$Values.Add($Record.id)
        foreach ($FieldName in $script:CurrentListFields) {
            [void]$Values.Add((Format-OdooValue (Get-RecordValue $Record $FieldName)))
        }
        [void]$Grid.Rows.Add($Values.ToArray())
    }

    $RangeStart = if ($script:Total -eq 0) { 0 } else { $script:Offset + 1 }
    $RangeEnd = [Math]::Min($script:Offset + $script:CurrentRecords.Count, $script:Total)
    $PageLabel.Text = "$RangeStart-$RangeEnd de $script:Total"
    if ($ListTitle) { $ListTitle.Text = $script:CurrentModelName }
    if ($ListSubtitle) { $ListSubtitle.Text = "$script:CurrentModel  |  $($PageLabel.Text)" }
    $PrevButton.Enabled = $script:Offset -gt 0
    $NextButton.Enabled = ($script:Offset + $script:Limit) -lt $script:Total

    if ($script:CurrentRecords.Count -gt 0) {
        $SelectedIndex = 0
        if ($SelectId -gt 0) {
            for ($Index = 0; $Index -lt $script:CurrentRecords.Count; $Index++) {
                if ([int](Get-RecordValue $script:CurrentRecords[$Index] "id") -eq $SelectId) {
                    $SelectedIndex = $Index
                    break
                }
            }
        }
        $Grid.ClearSelection()
        $Grid.Rows[$SelectedIndex].Selected = $true
        $Grid.CurrentCell = $Grid.Rows[$SelectedIndex].Cells[0]
        Load-Detail $script:CurrentRecords[$SelectedIndex]
    } else {
        Load-Detail $null
    }

    Stop-Loading "$script:CurrentModelName cargado: $($PageLabel.Text)"
    } catch {
        Stop-Loading
        throw
    }
}

function Load-Model {
    param(
        [string] $ModelName,
        [string] $Title,
        [string] $ViewMode = "",
        [array] $Domain = @(),
        [array] $Views = @(),
        [switch] $ReadOnly
    )

    Start-Loading "Preparando $Title..."
    try {
    Show-DynamicView
    if ($Window) {
        $Window.Text = "Odoo Native UI - $Title"
    }
    $script:CurrentModel = $ModelName
    $script:CurrentModelName = if ($Title) { $Title } else { $ModelName }
    $script:IsReadOnlyModel = [bool]$ReadOnly
    $script:CurrentDomain = @($Domain)

    if ($script:FieldCache.ContainsKey($ModelName)) {
        $script:CurrentFields = $script:FieldCache[$ModelName]
    } else {
        $FieldResult = Invoke-OdooJson -Path "/native-ui/model/$ModelName/fields" -Params @{
            attributes = @("string", "type", "readonly", "required", "relation", "selection", "store")
        }
        $script:CurrentFields = $FieldResult.fields
        $script:FieldCache[$ModelName] = $script:CurrentFields
    }

    $script:PartnerFields = $script:CurrentFields

    $RequestedViews = @(Get-RenderableViews -Views $Views)
    $IrCacheKey = Get-ViewsCacheKey -ModelName $ModelName -Views $RequestedViews
    if ($script:IrCache.ContainsKey($IrCacheKey)) {
        $script:CurrentIr = $script:IrCache[$IrCacheKey]
    } else {
        $IrResult = Invoke-OdooJson -Path "/native-ui/model/$ModelName/ir" -Params @{
            views = $RequestedViews
        }
        $script:CurrentIr = $IrResult.ir
        $script:IrCache[$IrCacheKey] = $script:CurrentIr
    }

    if ($script:PermissionsCache.ContainsKey($ModelName)) {
        $script:CurrentPermissions = $script:PermissionsCache[$ModelName]
    } else {
        $PermissionResult = Invoke-OdooJson -Path "/native-ui/model/$ModelName/permissions"
        $script:CurrentPermissions = $PermissionResult.permissions
        $script:PermissionsCache[$ModelName] = $script:CurrentPermissions
    }

    $CanCreate = -not $script:IsReadOnlyModel -and [bool]$script:CurrentPermissions.create
    $CanWrite = -not $script:IsReadOnlyModel -and [bool]$script:CurrentPermissions.write
    if ($ListTitle) { $ListTitle.Text = $script:CurrentModelName }
    if ($ListSubtitle) { $ListSubtitle.Text = "$script:CurrentModel  |  cargando..." }
    if ($SearchFieldBox) { $SearchFieldBox.Enabled = $true }
    $SearchButton.Enabled = $true
    $ReloadButton.Enabled = $true
    $NewButton.Enabled = $CanCreate
    $SaveButton.Enabled = $CanWrite
    $CancelButton.Enabled = $CanWrite

    $script:CurrentListFields = @(Get-PreferredListFields $ModelName)
    $script:CurrentDetailSections = @(Get-DetailSections)
    if ($script:CurrentDetailSections.Count -gt 0) {
        $script:CurrentDetailFields = @(
            foreach ($Section in @($script:CurrentDetailSections)) {
                foreach ($FieldName in @($Section.fields)) { $FieldName }
            }
        ) | Select-Object -Unique
    } else {
        $script:CurrentDetailFields = @(Get-PreferredDetailFields $ModelName)
        $script:CurrentDetailSections = @([pscustomobject]@{ title = "General"; fields = $script:CurrentDetailFields })
    }
    Update-CentralSearchFields
    $DetailTitle.Text = $script:CurrentModelName
    Stop-Loading "Preparado $script:CurrentModelName."
    Load-ModelPage 0
    } catch {
        Stop-Loading
        throw
    }
}

function Load-Metadata {
    Load-Model -ModelName "res.partner" -Title "Contactos"
}

function Get-ControlWriteValue {
    param([System.Windows.Forms.Control] $Control)
    if ($Control -is [System.Windows.Forms.CheckBox]) {
        return [bool]$Control.Checked
    }
    if ($Control -is [System.Windows.Forms.ComboBox]) {
        if ($null -eq $Control.SelectedValue) { return $false }
        return $Control.SelectedValue
    }
    return $Control.Text
}

function Connect-NativeUi {
    Start-Loading "Conectando con Odoo..."
    try {
    $script:BaseUrl = $UrlBox.Text
    $script:Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    Set-Status "Probando bridge..."
    $Health = Invoke-OdooJson -Path "/native-ui/health"

    Set-Status "Autenticando..."
    $Auth = Invoke-OdooJson -Path "/web/session/authenticate" -Params @{
        db = $DatabaseBox.Text
        login = $LoginBox.Text
        password = $PasswordBox.Text
    }
    if (-not $Auth.uid) { throw "No se pudo autenticar." }

    Set-Status "Cargando snapshot..."
    $SessionInfo = Invoke-OdooJson -Path "/native-ui/session"
    $Snapshot = Invoke-OdooJson -Path "/native-ui/snapshot/index"

    $script:SnapshotRoot = $Snapshot.menus
    if ($NavSearchBox) { $NavSearchBox.Text = "" }
    Rebuild-AppsTree

    $InfoBox.Text = "Conectado  |  Odoo $($Health.odoo_version)  |  $($SessionInfo.user.name)  |  DB $($SessionInfo.database)  |  Bridge $($Health.bridge_version)"
    $ConnectButton.Text = "Reconectar"
    if ($ConnectSettingsButton) { $ConnectSettingsButton.Text = "Reconectar" }
    if ($ConnectionSubtitle) {
        $ConnectionSubtitle.Text = "Conectado a $($SessionInfo.database). Esta vista sigue siendo fija para cambios de conexion."
    }
    Stop-Loading "Conectado a $($SessionInfo.database)."
    if ($StayOnConnectionBox -and $StayOnConnectionBox.Checked) {
        Show-ConnectionView
        Set-Status "Conectado a $($SessionInfo.database). La vista estatica queda fija."
    } else {
        Load-Metadata
    }
    } catch {
        Stop-Loading
        throw
    }
}

function Save-CurrentRecord {
    if ($script:IsReadOnlyModel) {
        Set-Status "Vista de solo lectura."
        return
    }
    if (-not $script:CurrentRecord) { return }
    $Values = @{}
    foreach ($FieldName in @($script:FormControls.Keys)) {
        $Values[$FieldName] = Get-ControlWriteValue $script:FormControls[$FieldName]
    }

    if ($Values.Count -eq 0) {
        Set-Status "No hay campos editables en esta vista."
        return
    }

    $Id = [int](Get-RecordValue $script:CurrentRecord "id")
    Start-Loading "Guardando registro $Id..."
    try {
    [void](Invoke-OdooJson -Path "/native-ui/model/$script:CurrentModel/write" -Params @{
        ids = @($Id)
        values = $Values
    })
    Stop-Loading "Registro $Id guardado."
    Load-CurrentPage $script:Offset -SelectId $Id
    } catch {
        Stop-Loading
        throw
    }
}

function New-CurrentRecord {
    if ($script:IsReadOnlyModel) {
        Set-Status "Vista de solo lectura."
        return
    }
    $Values = @{
        name = "Nuevo registro"
    }
    if (-not (Test-FieldExists "name")) {
        [System.Windows.Forms.MessageBox]::Show("Este modelo no tiene campo name para crear un registro minimo.", "Odoo Native UI Lab v2", "OK", "Information") | Out-Null
        return
    }
    Start-Loading "Creando registro..."
    try {
        $Result = Invoke-OdooJson -Path "/native-ui/model/$script:CurrentModel/create" -Params @{
            values = $Values
        }
        Stop-Loading "Registro creado: $($Result.id)"
        $SearchBox.Text = ""
        Load-CurrentPage 0 -SelectId ([int]$Result.id) -Order "id desc"
        Focus-FirstEditableField
    } catch {
        Stop-Loading
        throw
    }
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$Window = New-Object System.Windows.Forms.Form
$Window.Text = "Odoo Native UI Lab v2"
$Window.Width = 1440
$Window.Height = 820
$Window.StartPosition = "CenterScreen"
$Window.MinimumSize = New-Object System.Drawing.Size(1080, 680)
$Window.BackColor = $script:ColorBackground
$Window.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$Root = New-Object System.Windows.Forms.TableLayoutPanel
$Root.Dock = "Fill"
$Root.BackColor = $script:ColorBackground
$Root.RowCount = 3
$Root.ColumnCount = 1
[void]$Root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 48)))
[void]$Root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$Root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28)))
$Window.Controls.Add($Root)

$Top = New-Object System.Windows.Forms.TableLayoutPanel
$Top.Dock = "Fill"
$Top.BackColor = $script:ColorSurface
$Top.ColumnCount = 3
$Top.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
[void]$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 116)))
[void]$Top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 126)))
$Root.Controls.Add($Top, 0, 0)

$InfoBox = New-Object System.Windows.Forms.TextBox
$InfoBox.ReadOnly = $true
$InfoBox.Dock = "Fill"
$InfoBox.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 0)
$InfoBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$InfoBox.BackColor = $script:ColorAccentSoft
$InfoBox.ForeColor = $script:ColorAccentDark
$InfoBox.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$InfoBox.Text = "Sin conectar  |  Abrir Conexion para configurar servidor, base y usuario."
$Top.Controls.Add($InfoBox, 0, 0)

$ConnectionViewButton = New-Object System.Windows.Forms.Button
$ConnectionViewButton.Text = "Conexion"
$ConnectionViewButton.Dock = "Fill"
$ConnectionViewButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
Set-FlatButton $ConnectionViewButton $false
$Top.Controls.Add($ConnectionViewButton, 1, 0)

$ConnectButton = New-Object System.Windows.Forms.Button
$ConnectButton.Text = "Conectar"
$ConnectButton.Dock = "Fill"
$ConnectButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
Set-FlatButton $ConnectButton $true
$Top.Controls.Add($ConnectButton, 2, 0)

$Main = New-Object System.Windows.Forms.SplitContainer
$Main.Dock = "Fill"
$Main.FixedPanel = "Panel1"
$Main.Panel1MinSize = 300
$Main.BackColor = $script:ColorBackground
$Main.Panel1.BackColor = $script:ColorPanel
$Main.Panel2.BackColor = $script:ColorBackground
$Root.Controls.Add($Main, 0, 1)

$NavPanel = New-Object System.Windows.Forms.TableLayoutPanel
$NavPanel.Dock = "Fill"
$NavPanel.Padding = New-Object System.Windows.Forms.Padding(14, 12, 10, 10)
$NavPanel.BackColor = $script:ColorPanel
$NavPanel.RowCount = 3
$NavPanel.ColumnCount = 1
[void]$NavPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$NavPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
[void]$NavPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$Main.Panel1.Controls.Add($NavPanel)

$NavHeader = New-Object System.Windows.Forms.TableLayoutPanel
$NavHeader.Dock = "Fill"
$NavHeader.BackColor = $script:ColorPanel
$NavHeader.RowCount = 2
$NavHeader.ColumnCount = 1
[void]$NavHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 58)))
[void]$NavHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 42)))
$NavPanel.Controls.Add($NavHeader, 0, 0)

$AppsLabel = New-Object System.Windows.Forms.Label
$AppsLabel.Text = "Aplicaciones"
$AppsLabel.Dock = "Fill"
$AppsLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$AppsLabel.ForeColor = $script:ColorText
$AppsLabel.TextAlign = "BottomLeft"
$NavHeader.Controls.Add($AppsLabel, 0, 0)

$NavCountLabel = New-Object System.Windows.Forms.Label
$NavCountLabel.Text = "Sin conectar"
$NavCountLabel.Dock = "Fill"
$NavCountLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$NavCountLabel.ForeColor = $script:ColorSubtleText
$NavCountLabel.TextAlign = "TopLeft"
$NavHeader.Controls.Add($NavCountLabel, 0, 1)

$NavSearchBox = New-Object System.Windows.Forms.TextBox
$NavSearchBox.Dock = "Fill"
$NavSearchBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 6)
$NavSearchBox.Tag = "nav-search"
Set-InputStyle $NavSearchBox
$PlaceholderProperty = $NavSearchBox.GetType().GetProperty("PlaceholderText")
if ($PlaceholderProperty) {
    $PlaceholderProperty.SetValue($NavSearchBox, "Buscar menu...", $null)
}
$NavPanel.Controls.Add($NavSearchBox, 0, 1)

$AppsTree = New-Object System.Windows.Forms.TreeView
$AppsTree.Dock = "Fill"
$AppsTree.HideSelection = $false
$AppsTree.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$AppsTree.BackColor = $script:ColorPanel
$AppsTree.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$AppsTree.ItemHeight = 26
$AppsTree.Indent = 18
$AppsTree.Scrollable = $true
$AppsTree.FullRowSelect = $true
$AppsTree.ShowLines = $false
$AppsTree.ShowRootLines = $false
$AppsTree.ShowPlusMinus = $false
$AppsTree.ForeColor = $script:ColorText
$AppsTree.DrawMode = [System.Windows.Forms.TreeViewDrawMode]::OwnerDrawText
$NavPanel.Controls.Add($AppsTree, 0, 2)

$ContentSplit = New-Object System.Windows.Forms.SplitContainer
$ContentSplit.Dock = "Fill"
$ContentSplit.FixedPanel = "Panel2"
$ContentSplit.Panel1MinSize = 560
$ContentSplit.BackColor = $script:ColorBackground
$ContentSplit.Panel1.BackColor = $script:ColorBackground
$ContentSplit.Panel2.BackColor = $script:ColorSurface
$Main.Panel2.Controls.Add($ContentSplit)

$StaticHost = New-Object System.Windows.Forms.Panel
$StaticHost.Dock = "Fill"
$StaticHost.BackColor = $script:ColorBackground
$StaticHost.Visible = $false
$Main.Panel2.Controls.Add($StaticHost)

$ConnectionView = New-Object System.Windows.Forms.TableLayoutPanel
$ConnectionView.Dock = "Fill"
$ConnectionView.BackColor = $script:ColorBackground
$ConnectionView.ColumnCount = 1
$ConnectionView.RowCount = 4
$ConnectionView.Padding = New-Object System.Windows.Forms.Padding(28, 24, 28, 24)
[void]$ConnectionView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 72)))
[void]$ConnectionView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 184)))
[void]$ConnectionView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
[void]$ConnectionView.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$StaticHost.Controls.Add($ConnectionView)

$ConnectionHeader = New-Object System.Windows.Forms.TableLayoutPanel
$ConnectionHeader.Dock = "Fill"
$ConnectionHeader.BackColor = $script:ColorBackground
$ConnectionHeader.ColumnCount = 1
$ConnectionHeader.RowCount = 2
[void]$ConnectionHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 58)))
[void]$ConnectionHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 42)))
$ConnectionView.Controls.Add($ConnectionHeader, 0, 0)

$ConnectionTitle = New-Object System.Windows.Forms.Label
$ConnectionTitle.Text = "Conexion"
$ConnectionTitle.Dock = "Fill"
$ConnectionTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 18)
$ConnectionTitle.ForeColor = $script:ColorText
$ConnectionTitle.TextAlign = "BottomLeft"
$ConnectionHeader.Controls.Add($ConnectionTitle, 0, 0)

$ConnectionSubtitle = New-Object System.Windows.Forms.Label
$ConnectionSubtitle.Text = "Vista estatica configurable. Es el unico panel fijo; las apps de Odoo se cargan bajo demanda."
$ConnectionSubtitle.Dock = "Fill"
$ConnectionSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$ConnectionSubtitle.ForeColor = $script:ColorSubtleText
$ConnectionSubtitle.TextAlign = "TopLeft"
$ConnectionHeader.Controls.Add($ConnectionSubtitle, 0, 1)

$ConnectionForm = New-Object System.Windows.Forms.TableLayoutPanel
$ConnectionForm.Dock = "Fill"
$ConnectionForm.BackColor = $script:ColorBackground
$ConnectionForm.ColumnCount = 2
$ConnectionForm.RowCount = 4
$ConnectionForm.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
[void]$ConnectionForm.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 130)))
[void]$ConnectionForm.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
for ($RowIndex = 0; $RowIndex -lt 4; $RowIndex++) {
    [void]$ConnectionForm.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
}
$ConnectionView.Controls.Add($ConnectionForm, 0, 1)

$UrlLabel = New-Object System.Windows.Forms.Label
$UrlLabel.Text = "Servidor"
$UrlLabel.Dock = "Fill"
$UrlLabel.TextAlign = "MiddleLeft"
Set-FieldLabelStyle $UrlLabel
$ConnectionForm.Controls.Add($UrlLabel, 0, 0)

$UrlBox = New-Object System.Windows.Forms.TextBox
$UrlBox.Text = $Url
$UrlBox.Dock = "Fill"
$UrlBox.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
Set-InputStyle $UrlBox
$ConnectionForm.Controls.Add($UrlBox, 1, 0)

$DbLabel = New-Object System.Windows.Forms.Label
$DbLabel.Text = "Base de datos"
$DbLabel.Dock = "Fill"
$DbLabel.TextAlign = "MiddleLeft"
Set-FieldLabelStyle $DbLabel
$ConnectionForm.Controls.Add($DbLabel, 0, 1)

$DatabaseBox = New-Object System.Windows.Forms.TextBox
$DatabaseBox.Text = $Database
$DatabaseBox.Dock = "Fill"
$DatabaseBox.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
Set-InputStyle $DatabaseBox
$ConnectionForm.Controls.Add($DatabaseBox, 1, 1)

$LoginLabel = New-Object System.Windows.Forms.Label
$LoginLabel.Text = "Usuario"
$LoginLabel.Dock = "Fill"
$LoginLabel.TextAlign = "MiddleLeft"
Set-FieldLabelStyle $LoginLabel
$ConnectionForm.Controls.Add($LoginLabel, 0, 2)

$LoginBox = New-Object System.Windows.Forms.TextBox
$LoginBox.Text = $Login
$LoginBox.Dock = "Fill"
$LoginBox.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
Set-InputStyle $LoginBox
$ConnectionForm.Controls.Add($LoginBox, 1, 2)

$PasswordLabel = New-Object System.Windows.Forms.Label
$PasswordLabel.Text = "Clave"
$PasswordLabel.Dock = "Fill"
$PasswordLabel.TextAlign = "MiddleLeft"
Set-FieldLabelStyle $PasswordLabel
$ConnectionForm.Controls.Add($PasswordLabel, 0, 3)

$PasswordBox = New-Object System.Windows.Forms.TextBox
$PasswordBox.Text = $Password
$PasswordBox.UseSystemPasswordChar = $true
$PasswordBox.Dock = "Fill"
$PasswordBox.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
Set-InputStyle $PasswordBox
$ConnectionForm.Controls.Add($PasswordBox, 1, 3)

$ConnectionActions = New-Object System.Windows.Forms.TableLayoutPanel
$ConnectionActions.Dock = "Fill"
$ConnectionActions.BackColor = $script:ColorBackground
$ConnectionActions.ColumnCount = 3
[void]$ConnectionActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$ConnectionActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 168)))
[void]$ConnectionActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 140)))
$ConnectionView.Controls.Add($ConnectionActions, 0, 2)

$AutoConnectBox = New-Object System.Windows.Forms.CheckBox
$AutoConnectBox.Text = "Conectar automaticamente al abrir si hay clave"
$AutoConnectBox.Checked = $true
$AutoConnectBox.Dock = "Fill"
$AutoConnectBox.ForeColor = $script:ColorText
$AutoConnectBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$AutoConnectBox.Margin = New-Object System.Windows.Forms.Padding(0, 10, 12, 0)
$ConnectionActions.Controls.Add($AutoConnectBox, 0, 0)

$StayOnConnectionBox = New-Object System.Windows.Forms.CheckBox
$StayOnConnectionBox.Text = "Mantener esta vista al conectar"
$StayOnConnectionBox.Checked = $false
$StayOnConnectionBox.Dock = "Fill"
$StayOnConnectionBox.ForeColor = $script:ColorText
$StayOnConnectionBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$StayOnConnectionBox.Margin = New-Object System.Windows.Forms.Padding(0, 10, 10, 0)
$ConnectionActions.Controls.Add($StayOnConnectionBox, 1, 0)

$ConnectSettingsButton = New-Object System.Windows.Forms.Button
$ConnectSettingsButton.Text = "Conectar"
$ConnectSettingsButton.Dock = "Fill"
$ConnectSettingsButton.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
Set-FlatButton $ConnectSettingsButton $true
$ConnectionActions.Controls.Add($ConnectSettingsButton, 2, 0)

$ConnectionHint = New-Object System.Windows.Forms.Label
$ConnectionHint.Dock = "Top"
$ConnectionHint.AutoSize = $true
$ConnectionHint.MaximumSize = New-Object System.Drawing.Size(760, 0)
$ConnectionHint.Padding = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
$ConnectionHint.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$ConnectionHint.ForeColor = $script:ColorSubtleText
$ConnectionHint.Text = "Esta vista no depende de Odoo ni cambia al navegar. Usa estos datos para autenticar, y luego abre cualquier modulo desde el panel izquierdo."
$ConnectionView.Controls.Add($ConnectionHint, 0, 3)

$ListPanel = New-Object System.Windows.Forms.TableLayoutPanel
$ListPanel.Dock = "Fill"
$ListPanel.BackColor = $script:ColorBackground
$ListPanel.RowCount = 4
$ListPanel.ColumnCount = 1
[void]$ListPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
[void]$ListPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
[void]$ListPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$ListPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))
$ContentSplit.Panel1.Controls.Add($ListPanel)

$ListHeader = New-Object System.Windows.Forms.TableLayoutPanel
$ListHeader.Dock = "Fill"
$ListHeader.BackColor = $script:ColorBackground
$ListHeader.ColumnCount = 1
$ListHeader.RowCount = 2
$ListHeader.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 0)
[void]$ListHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 58)))
[void]$ListHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 42)))
$ListPanel.Controls.Add($ListHeader, 0, 0)

$ListTitle = New-Object System.Windows.Forms.Label
$ListTitle.Text = "Contactos"
$ListTitle.Dock = "Fill"
$ListTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 14)
$ListTitle.ForeColor = $script:ColorText
$ListTitle.TextAlign = "BottomLeft"
$ListHeader.Controls.Add($ListTitle, 0, 0)

$ListSubtitle = New-Object System.Windows.Forms.Label
$ListSubtitle.Text = "res.partner"
$ListSubtitle.Dock = "Fill"
$ListSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$ListSubtitle.ForeColor = $script:ColorSubtleText
$ListSubtitle.TextAlign = "TopLeft"
$ListHeader.Controls.Add($ListSubtitle, 0, 1)

$SearchPanel = New-Object System.Windows.Forms.TableLayoutPanel
$SearchPanel.Dock = "Fill"
$SearchPanel.BackColor = $script:ColorBackground
$SearchPanel.ColumnCount = 4
$SearchPanel.Padding = New-Object System.Windows.Forms.Padding(10, 2, 10, 4)
[void]$SearchPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
[void]$SearchPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$SearchPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
[void]$SearchPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 92)))
$ListPanel.Controls.Add($SearchPanel, 0, 1)

$SearchFieldBox = New-Object System.Windows.Forms.ComboBox
$SearchFieldBox.Dock = "Fill"
$SearchFieldBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$SearchFieldBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
Set-InputStyle $SearchFieldBox
$SearchPanel.Controls.Add($SearchFieldBox, 0, 0)

$SearchBox = New-Object System.Windows.Forms.TextBox
$SearchBox.Dock = "Fill"
$SearchBox.Margin = New-Object System.Windows.Forms.Padding(0, 4, 8, 0)
Set-InputStyle $SearchBox
$SearchPanel.Controls.Add($SearchBox, 1, 0)

$SearchButton = New-Object System.Windows.Forms.Button
$SearchButton.Text = "Buscar"
$SearchButton.Dock = "Fill"
$SearchButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 8, 0)
Set-FlatButton $SearchButton $false
$SearchPanel.Controls.Add($SearchButton, 2, 0)

$ReloadButton = New-Object System.Windows.Forms.Button
$ReloadButton.Text = "Recargar"
$ReloadButton.Dock = "Fill"
$ReloadButton.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
Set-FlatButton $ReloadButton $false
$SearchPanel.Controls.Add($ReloadButton, 3, 0)

$Grid = New-Object System.Windows.Forms.DataGridView
$Grid.Dock = "Fill"
$Grid.AllowUserToAddRows = $false
$Grid.AllowUserToDeleteRows = $false
$Grid.ReadOnly = $true
$Grid.RowHeadersVisible = $false
$Grid.SelectionMode = "FullRowSelect"
$Grid.MultiSelect = $false
$Grid.AutoSizeColumnsMode = "Fill"
Set-ModernGrid $Grid
[void]$Grid.Columns.Add("id", "ID")
[void]$Grid.Columns.Add("display_name", "Contacto")
[void]$Grid.Columns.Add("email", "Email")
[void]$Grid.Columns.Add("phone", "Telefono")
[void]$Grid.Columns.Add("mobile", "Movil")
$Grid.Columns["id"].FillWeight = 12
$Grid.Columns["display_name"].FillWeight = 42
$Grid.Columns["email"].FillWeight = 26
$Grid.Columns["phone"].FillWeight = 20
$Grid.Columns["mobile"].FillWeight = 20
$Grid.Margin = New-Object System.Windows.Forms.Padding(10, 2, 10, 0)
$ListPanel.Controls.Add($Grid, 0, 2)

$Pager = New-Object System.Windows.Forms.TableLayoutPanel
$Pager.Dock = "Fill"
$Pager.BackColor = $script:ColorBackground
$Pager.ColumnCount = 4
$Pager.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)
[void]$Pager.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90)))
[void]$Pager.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90)))
[void]$Pager.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$Pager.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 104)))
$ListPanel.Controls.Add($Pager, 0, 3)

$PrevButton = New-Object System.Windows.Forms.Button
$PrevButton.Text = "Anterior"
$PrevButton.Dock = "Fill"
$PrevButton.Enabled = $false
Set-FlatButton $PrevButton $false
$Pager.Controls.Add($PrevButton, 0, 0)

$NextButton = New-Object System.Windows.Forms.Button
$NextButton.Text = "Siguiente"
$NextButton.Dock = "Fill"
$NextButton.Enabled = $false
Set-FlatButton $NextButton $false
$Pager.Controls.Add($NextButton, 1, 0)

$PageLabel = New-Object System.Windows.Forms.Label
$PageLabel.Text = "0-0 de 0"
$PageLabel.Dock = "Fill"
$PageLabel.TextAlign = "MiddleCenter"
$PageLabel.ForeColor = $script:ColorText
$PageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$Pager.Controls.Add($PageLabel, 2, 0)

$NewButton = New-Object System.Windows.Forms.Button
$NewButton.Text = "Nuevo"
$NewButton.Dock = "Fill"
Set-FlatButton $NewButton $false
$Pager.Controls.Add($NewButton, 3, 0)

$DetailPanel = New-Object System.Windows.Forms.TableLayoutPanel
$DetailPanel.Dock = "Fill"
$DetailPanel.BackColor = $script:ColorSurface
$DetailPanel.RowCount = 3
$DetailPanel.ColumnCount = 1
$DetailPanel.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 12)
[void]$DetailPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 64)))
[void]$DetailPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$DetailPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
$ContentSplit.Panel2.Controls.Add($DetailPanel)

$DetailHeader = New-Object System.Windows.Forms.TableLayoutPanel
$DetailHeader.Dock = "Fill"
$DetailHeader.BackColor = $script:ColorSurface
$DetailHeader.ColumnCount = 1
$DetailHeader.RowCount = 2
[void]$DetailHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 62)))
[void]$DetailHeader.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 38)))
$DetailPanel.Controls.Add($DetailHeader, 0, 0)

$DetailTitle = New-Object System.Windows.Forms.Label
$DetailTitle.Text = "Detalle"
$DetailTitle.Dock = "Fill"
$DetailTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
$DetailTitle.TextAlign = "BottomLeft"
$DetailTitle.ForeColor = $script:ColorText
$DetailHeader.Controls.Add($DetailTitle, 0, 0)

$DetailSubtitle = New-Object System.Windows.Forms.Label
$DetailSubtitle.Text = ""
$DetailSubtitle.Dock = "Fill"
$DetailSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$DetailSubtitle.TextAlign = "TopLeft"
$DetailSubtitle.ForeColor = $script:ColorSubtleText
$DetailHeader.Controls.Add($DetailSubtitle, 0, 1)

$DetailBody = New-Object System.Windows.Forms.Panel
$DetailBody.Dock = "Fill"
$DetailBody.AutoScroll = $true
$DetailBody.BackColor = $script:ColorSurface
$DetailPanel.Controls.Add($DetailBody, 0, 1)

$DetailButtons = New-Object System.Windows.Forms.TableLayoutPanel
$DetailButtons.Dock = "Fill"
$DetailButtons.BackColor = $script:ColorSurface
$DetailButtons.ColumnCount = 2
[void]$DetailButtons.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$DetailButtons.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$DetailPanel.Controls.Add($DetailButtons, 0, 2)

$SaveButton = New-Object System.Windows.Forms.Button
$SaveButton.Text = "Guardar"
$SaveButton.Dock = "Fill"
$SaveButton.Margin = New-Object System.Windows.Forms.Padding(0, 4, 6, 0)
Set-FlatButton $SaveButton $true
$DetailButtons.Controls.Add($SaveButton, 0, 0)

$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Text = "Revertir"
$CancelButton.Dock = "Fill"
$CancelButton.Margin = New-Object System.Windows.Forms.Padding(6, 4, 0, 0)
Set-FlatButton $CancelButton $false
$DetailButtons.Controls.Add($CancelButton, 1, 0)

$StatusPanel = New-Object System.Windows.Forms.TableLayoutPanel
$StatusPanel.Dock = "Fill"
$StatusPanel.BackColor = $script:ColorBackground
$StatusPanel.ColumnCount = 2
$StatusPanel.RowCount = 1
[void]$StatusPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$StatusPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
$Root.Controls.Add($StatusPanel, 0, 2)

$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Text = "Listo."
$StatusLabel.Dock = "Fill"
$StatusLabel.TextAlign = "MiddleLeft"
$StatusLabel.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$StatusLabel.BackColor = $script:ColorBackground
$StatusLabel.ForeColor = $script:ColorSubtleText
$StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$StatusPanel.Controls.Add($StatusLabel, 0, 0)

$LoadingBar = New-Object System.Windows.Forms.ProgressBar
$LoadingBar.Dock = "Fill"
$LoadingBar.Margin = New-Object System.Windows.Forms.Padding(4, 7, 10, 7)
$LoadingBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$LoadingBar.MarqueeAnimationSpeed = 0
$LoadingBar.Visible = $false
$StatusPanel.Controls.Add($LoadingBar, 1, 0)

$LoadingTimer = New-Object System.Windows.Forms.Timer
$LoadingTimer.Interval = 120
$LoadingTimer.Add_Tick({ Step-Loading })

function Invoke-ConnectFromUi {
    try { Connect-NativeUi } catch {
        Set-Status "Error"
        [System.Windows.Forms.MessageBox]::Show((Get-FriendlyError $_), "Odoo Native UI Lab v2", "OK", "Error") | Out-Null
    }
}

$ConnectButton.Add_Click({ Invoke-ConnectFromUi })
$ConnectSettingsButton.Add_Click({ Invoke-ConnectFromUi })
$ConnectionViewButton.Add_Click({ Show-ConnectionView })

$SearchButton.Add_Click({ try { Load-CurrentPage 0 } catch { Set-Status (Get-FriendlyError $_) } })
$ReloadButton.Add_Click({ try { Load-CurrentPage $script:Offset } catch { Set-Status (Get-FriendlyError $_) } })
$PrevButton.Add_Click({ try { Load-CurrentPage ($script:Offset - $script:Limit) } catch { Set-Status (Get-FriendlyError $_) } })
$NextButton.Add_Click({ try { Load-CurrentPage ($script:Offset + $script:Limit) } catch { Set-Status (Get-FriendlyError $_) } })
$NewButton.Add_Click({ try { New-CurrentRecord } catch { Set-Status (Get-FriendlyError $_) } })
$SaveButton.Add_Click({ try { Save-CurrentRecord } catch { Set-Status (Get-FriendlyError $_) } })
$CancelButton.Add_Click({ Load-Detail $script:CurrentRecord })

$SearchFieldBox.Add_SelectedIndexChanged({
    if ($SearchBox -and $SearchBox.Text.Trim()) {
        try { Load-CurrentPage 0 } catch { Set-Status (Get-FriendlyError $_) }
    }
})

$SearchBox.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Load-CurrentPage 0
    }
})

$Grid.Add_SelectionChanged({
    if ($Grid.SelectedRows.Count -eq 0) { return }
    $Index = $Grid.SelectedRows[0].Index
    if ($Index -ge 0 -and $Index -lt $script:CurrentRecords.Count) {
        Load-Detail $script:CurrentRecords[$Index]
    }
})

$NavSearchBox.Add_TextChanged({
    Rebuild-AppsTree -Query $NavSearchBox.Text
})

$NavSearchBox.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $_.SuppressKeyPress = $true
        $NavSearchBox.Text = ""
        return
    }
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        if ($AppsTree.Nodes.Count -gt 0) {
            $Node = $AppsTree.Nodes[0]
            $ActionMenu = Find-FirstActionMenu $Node.Tag
            if ($ActionMenu) {
                $Stack = New-Object System.Collections.Stack
                $Stack.Push($Node)
                while ($Stack.Count -gt 0) {
                    $Candidate = $Stack.Pop()
                    if ($Candidate.Tag -and $Candidate.Tag.id -eq $ActionMenu.id) {
                        $Node = $Candidate
                        break
                    }
                    for ($i = $Candidate.Nodes.Count - 1; $i -ge 0; $i--) {
                        $Stack.Push($Candidate.Nodes[$i])
                    }
                }
            }
            $AppsTree.SelectedNode = $Node
            $Node.EnsureVisible()
            Open-MenuNode $Node.Tag
        }
    }
})

$AppsTree.Add_DrawNode({
    param($Sender, $EventArgs)

    $Node = $EventArgs.Node
    if (-not $Node) { return }

    $FullBounds = New-Object System.Drawing.Rectangle(0, $EventArgs.Bounds.Y, $Sender.Width, $Sender.ItemHeight)
    $Selected = (($EventArgs.State -band [System.Windows.Forms.TreeNodeStates]::Selected) -eq [System.Windows.Forms.TreeNodeStates]::Selected)

    $BackColor = if ($Selected) { $script:ColorAccent } else { $script:ColorPanel }
    $ForeColor = if ($Selected) {
        [System.Drawing.Color]::White
    } elseif ($Node.Level -eq 0) {
        $script:ColorAccentDark
    } else {
        $script:ColorText
    }

    $Brush = New-Object System.Drawing.SolidBrush($BackColor)
    $EventArgs.Graphics.FillRectangle($Brush, $FullBounds)
    $Brush.Dispose()

    $Font = if ($Node.NodeFont) { $Node.NodeFont } else { $Sender.Font }
    $TextBounds = New-Object System.Drawing.Rectangle($EventArgs.Bounds.X, $EventArgs.Bounds.Y, [Math]::Max(10, $Sender.Width - $EventArgs.Bounds.X - 8), $Sender.ItemHeight)
    $Flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    [System.Windows.Forms.TextRenderer]::DrawText($EventArgs.Graphics, $Node.Text, $Font, $TextBounds, $ForeColor, $Flags)
})

$AppsTree.Add_AfterSelect({
    if ($script:SuppressMenuOpen) { return }
    try {
        Open-MenuNode $_.Node.Tag
    } catch {
        $Message = Get-FriendlyError $_
        Show-UnsupportedAction `
            -Title $_.Node.Text `
            -ActionType "error" `
            -Message "No se pudo abrir este menu.`r`n$Message" `
            -StatusText "No se pudo abrir el menu seleccionado."
    }
})

$Window.Add_Shown({
    Rebuild-AppsTree
    Apply-LabLayout
    Show-ConnectionView
    if ($AutoConnectBox.Checked -and $PasswordBox.Text) {
        $ConnectButton.PerformClick()
    }
})

$Window.Add_Resize({
    Apply-LabLayout
})

[void]$Window.ShowDialog()
