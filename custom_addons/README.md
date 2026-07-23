# custom_addons

Carpeta reservada para modulos personalizados de Odoo.

Reglas:

- No modificar el core de Odoo.
- Crear cada modulo en una carpeta propia dentro de `custom_addons/`.
- Usar nombres tecnicos en minusculas y con guiones bajos, por ejemplo `bm_sales_extension`.
- Mantener un `__manifest__.py` por modulo.
- Declarar dependencias reales en `depends`.
- Separar modelos, vistas, seguridad, datos y tests cuando el modulo lo requiera.
- No guardar secretos, dumps ni archivos generados dentro de los modulos.

Estructura sugerida para un modulo futuro:

```text
custom_addons/
  bm_example_module/
    __init__.py
    __manifest__.py
    models/
      __init__.py
    views/
    security/
      ir.model.access.csv
    data/
    tests/
```

Instalacion futura:

1. Crear el modulo dentro de `custom_addons/`.
2. Reiniciar Odoo si el modulo es nuevo.
3. Activar modo desarrollador en Odoo.
4. Actualizar la lista de Apps.
5. Buscar e instalar el modulo.

## Modulos incluidos

### native_ui_bridge

Expone endpoints JSON `/native-ui/*` para conectar Odoo con el futuro cliente nativo.

El modulo esta cargado en `config/odoo.conf` mediante:

```ini
server_wide_modules = base,web,native_ui_bridge
```

Esto permite que las rutas esten disponibles al iniciar Odoo, manteniendo la seguridad de sesion, ACL y record rules de Odoo.
