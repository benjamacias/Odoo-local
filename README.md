# bm-odoo-suite

Instalacion base de Odoo Community con Docker Compose y PostgreSQL.

Esta entrega incluye el addon `native_ui_bridge`, que expone una conexion JSON ligera para un futuro cliente Windows nativo. Los addons propios se montan desde `custom_addons/` hacia `/mnt/extra-addons`, sin modificar el core de Odoo ni usar Odoo Enterprise.

## Requisitos

- Docker
- Docker Compose v2 (`docker compose`)

## Primer arranque

```sh
cp .env.example .env
docker compose up -d
```

Luego abre:

http://localhost:8069

En el primer ingreso, crea la base de datos desde el asistente web de Odoo. Si quieres usar los scripts de backup y restore sin pasar el nombre de la base manualmente, crea la base con el valor de `ODOO_DB` definido en `.env`.

La clave maestra inicial de Odoo esta definida en `config/odoo.conf` como un valor local de ejemplo: `change_me_master_password`. Cambiala antes de usar el entorno con datos reales.

## Odoo Native UI Bridge

El bridge se carga desde `custom_addons/native_ui_bridge` y expone endpoints `/native-ui/*` para que el cliente nativo pueda iniciar rapido y cargar metadata bajo demanda.

`/native-ui/health` se carga al iniciar Odoo mediante `server_wide_modules`. Los endpoints que leen sesion, menus, acciones, modelos o registros requieren instalar el addon en la base de datos Odoo que se va a usar.

Instalar o actualizar el bridge en la base definida para desarrollo:

```powershell
.\scripts\install_native_ui_bridge.ps1 -Database prueba
.\scripts\install_native_ui_bridge.ps1 -Database prueba -Upgrade
```

Flujo recomendado:

1. `POST /native-ui/health`
2. `POST /web/session/authenticate`
3. `POST /native-ui/session`
4. `POST /native-ui/snapshot/index`
5. Cargar acciones, campos, vistas y registros solo cuando haga falta.

Prueba de conexion:

```powershell
.\scripts\native_ui_probe.ps1 -Database odoo -Login admin -Password admin
```

Alternativa con Python:

```sh
python scripts/native_ui_probe.py --db odoo --login admin --password admin
```

Endpoints principales:

- `/native-ui/session`
- `/native-ui/snapshot/index`
- `/native-ui/snapshot/materialize`
- `/native-ui/apps`
- `/native-ui/menus`
- `/native-ui/action`
- `/native-ui/model/<model>/fields`
- `/native-ui/model/<model>/views`
- `/native-ui/model/<model>/ir`
- `/native-ui/model/<model>/permissions`
- `/native-ui/model/<model>/defaults`
- `/native-ui/model/<model>/name-search`
- `/native-ui/model/<model>/onchange`
- `/native-ui/model/<model>/records`
- `/native-ui/model/<model>/record/<id>`
- `/native-ui/model/<model>/create`
- `/native-ui/model/<model>/write`
- `/native-ui/model/<model>/unlink`
- `/native-ui/schema/<model>`

Smoke test sin depender del login web:

```powershell
Get-Content scripts\native_ui_smoke.py | docker compose exec -T odoo odoo shell -c /etc/odoo/odoo.conf -d prueba --no-http --db_host=db --db_port=5432 --db_user=odoo --db_password=change_me_postgres_password
```

Benchmark local:

```powershell
Get-Content scripts\native_ui_benchmark.py | docker compose exec -T odoo odoo shell -c /etc/odoo/odoo.conf -d prueba --no-http --db_host=db --db_port=5432 --db_user=odoo --db_password=change_me_postgres_password
```

Cliente visual minimo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\native_ui_lab_v2.ps1 -Database odoo -Login admin
```

El lab visual es una ventana Windows nativa temporal. No usa navegador, WebView, HTML, CSS ni JavaScript. Incluye una vista estatica configurable para conexion, snapshot, arbol completo de menus, resolucion de acciones, carga de Native UI IR por vista, cache de metadata por sesion, busqueda, paginacion, detalle lateral, permisos efectivos, guardado basico de campos editables, panel nativo minimo para Conversaciones y layout auto-ajustado al abrir.

## Configuracion inicial recomendada

Despues de copiar `.env.example` a `.env`, revisa estos valores locales antes de trabajar con datos reales:

```sh
POSTGRES_PASSWORD=change_me_postgres_password
ODOO_DB=odoo
```

Tambien cambia `admin_passwd` en `config/odoo.conf`. Ese valor es la clave maestra que Odoo solicita para crear, duplicar, respaldar o eliminar bases desde la interfaz web.

Convencion sugerida para desarrollo local:

- Base de datos: `odoo`
- Usuario PostgreSQL: `odoo`
- Addons propios: `custom_addons/`
- Backups locales: `backups/`

## Comandos utiles

Levantar los servicios:

```sh
docker compose up -d
# o
./scripts/start.sh
```

Detener los servicios sin borrar volumenes:

```sh
docker compose stop
# o
./scripts/stop.sh
```

Ver logs de Odoo:

```sh
docker compose logs -f odoo
# o
./scripts/logs.sh
```

Ver logs de todos los servicios:

```sh
./scripts/logs.sh db odoo
```

Ver una salida de logs sin seguir el stream:

```sh
./scripts/logs.sh --no-follow --tail=50 odoo
```

## Backups

Crear un backup de la base definida en `ODOO_DB`:

```sh
./scripts/backup.sh
```

Crear un backup indicando la base explicitamente:

```sh
./scripts/backup.sh nombre_base_odoo
```

Los archivos se guardan en `backups/` con formato SQL plano. Los backups generados estan ignorados por Git; solo se versiona `backups/.gitkeep`.

## Restore

Restaurar usando la base definida en `ODOO_DB`:

```sh
./scripts/restore.sh backups/nombre_base-YYYYMMDD-HHMMSS.sql
```

Restaurar indicando la base explicitamente:

```sh
./scripts/restore.sh backups/nombre_base-YYYYMMDD-HHMMSS.sql nombre_base_odoo
```

El restore detiene el contenedor de Odoo, recrea la base indicada en PostgreSQL, importa el SQL y vuelve a levantar Odoo.

## Estructura

```text
bm-odoo-suite/
  docker-compose.yml
  .env.example
  .gitignore
  config/odoo.conf
  custom_addons/README.md
  custom_addons/.gitkeep
  backups/.gitkeep
  custom_addons/native_ui_bridge/
  scripts/start.sh
  scripts/stop.sh
  scripts/logs.sh
  scripts/backup.sh
  scripts/restore.sh
  docs/
  README.md
```

## Notas

- Odoo se expone solo en `127.0.0.1:8069`.
- PostgreSQL y los datos de Odoo usan volumenes persistentes de Docker.
- `custom_addons/native_ui_bridge` contiene el bridge JSON usado por el cliente nativo.
- `.env` no debe versionarse porque contiene valores locales.
