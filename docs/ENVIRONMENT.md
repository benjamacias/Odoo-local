# Entorno

## Proyecto

- Carpeta: `bm-odoo-suite`
- Odoo: imagen Docker `odoo:18.0`
- PostgreSQL: imagen Docker `postgres:15`
- Addons propios: `custom_addons/`
- Configuracion Odoo: `config/odoo.conf`

## Bridge nativo

El addon `native_ui_bridge` se monta en `/mnt/extra-addons/native_ui_bridge` dentro del contenedor de Odoo.

`config/odoo.conf` incluye:

```ini
server_wide_modules = base,web,native_ui_bridge
```

Con esto, las rutas `/native-ui/*` se cargan al iniciar Odoo.

`/native-ui/health` queda disponible sin base ni sesion. Los endpoints protegidos por usuario requieren instalar el addon en cada base:

```powershell
.\scripts\install_native_ui_bridge.ps1 -Database prueba
.\scripts\install_native_ui_bridge.ps1 -Database prueba -Upgrade
```

## Comprobacion manual

Levantar Odoo:

```sh
docker compose up -d
```

Probar la conexion:

```powershell
.\scripts\native_ui_probe.ps1 -Database odoo -Login admin -Password admin
```

Alternativa con Python:

```sh
python scripts/native_ui_probe.py --db odoo --login admin --password admin
```

Si la base, usuario o password son distintos, ajustar esos argumentos.

## Cliente visual minimo disponible

El entorno actual no expone Visual Studio Build Tools, `cl`, `msbuild` ni `vswhere`. Si se instala Visual Studio con C++/WinRT y Windows App SDK, el siguiente paso natural es crear el cliente WinUI 3 formal.

Mientras tanto, el proyecto incluye un lab visual nativo en PowerShell WinForms:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\native_ui_lab_v2.ps1 -Database odoo -Login admin
```

El lab no usa HTML, CSS, JavaScript, navegador ni WebView. Consume `/native-ui/*`, carga snapshot, apps visibles, `res.partner` paginado, busqueda, detalle lateral y formulario simple generado desde metadata.
