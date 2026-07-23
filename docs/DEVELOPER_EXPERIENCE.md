# Developer Experience

## 001 - Odoo Native UI Bridge

Objetivo:

Crear una conexion ligera entre Odoo y el futuro cliente nativo.

Archivos principales:

- `custom_addons/native_ui_bridge/__manifest__.py`
- `custom_addons/native_ui_bridge/controllers/main.py`
- `custom_addons/native_ui_bridge/services/native_ir.py`
- `custom_addons/native_ui_bridge/services/snapshot.py`
- `scripts/native_ui_probe.py`
- `scripts/native_ui_smoke.py`
- `scripts/native_ui_benchmark.py`
- `scripts/native_ui_lab_v2.ps1`
- `config/odoo.conf`

Pasos:

1. Crear addon Odoo.
2. Exponer endpoints JSON.
3. Cargar el addon como `server_wide_modules`.
4. Agregar script de prueba con `urllib` y cookies de sesion.
5. Agregar script PowerShell para instalar el bridge por base Odoo.
6. Agregar Native UI IR.
7. Agregar snapshot materializado.
8. Agregar defaults, name-search, onchange y CRUD.
9. Medir baseline local.
10. Crear lab visual nativo v2 con layout operativo, busqueda, paginacion y guardado basico.
11. Ajustar lab v2 para arranque proporcionado, splitters automaticos, grilla estilizada y detalle legible.

Dificultad:

4 = relativamente facil.

Notas:

- Se evita `sudo` para preservar seguridad y reglas de Odoo.
- Se evita descargar vistas y campos durante el arranque.
- El endpoint de snapshot es un indice inicial, no una materializacion completa.
- En Odoo 18, `auth="none"` es necesario para que `/native-ui/health` exista sin base seleccionada.
- En Odoo 18, `check_access_rights` esta deprecado; se usa `check_access` con fallback.
- `load_menus` puede devolver hijos como IDs; el normalizador resuelve contra el indice devuelto por Odoo.
- `res.partner.display_name` no es ordenable en SQL; el bridge filtra `order` a campos almacenados y el lab usa `name`.
