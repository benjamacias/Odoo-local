param(
    [string] $Database = "prueba",
    [string] $DbHost = "db",
    [int] $DbPort = 5432,
    [string] $DbUser = "odoo",
    [string] $DbPassword = "change_me_postgres_password",
    [switch] $Upgrade
)

$ErrorActionPreference = "Stop"
$ModuleFlag = if ($Upgrade) { "-u" } else { "-i" }

docker compose exec odoo odoo `
    -c /etc/odoo/odoo.conf `
    -d $Database `
    $ModuleFlag native_ui_bridge `
    --stop-after-init `
    --no-http `
    --db_host=$DbHost `
    --db_port=$DbPort `
    --db_user=$DbUser `
    --db_password=$DbPassword

docker compose restart odoo
