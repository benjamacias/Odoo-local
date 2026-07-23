# Arquitectura inicial del Odoo Native UI Engine

Esta entrega implementa el minimo funcional del producto: una conexion real entre Odoo y el proyecto mediante un bridge JSON ligero.

## Componentes

- `native_ui_bridge`: addon Odoo montado desde `custom_addons/`.
- `server_wide_modules`: carga `/native-ui/health` al arrancar Odoo para detectar el bridge sin sesion.
- `scripts/native_ui_probe.py`: prueba de conexion, autenticacion y carga perezosa de metadata.

## Flujo de carga

El cliente nativo no debe descargar toda la metadata de Odoo al iniciar.

1. Consultar `/native-ui/health`.
2. Autenticar contra `/web/session/authenticate`.
3. Consultar `/native-ui/session`.
4. Consultar `/native-ui/snapshot/index`.
5. Cargar acciones, campos, vistas y registros solo cuando el usuario abre un modulo o modelo.

## Endpoints

Todos los endpoints de datos usan la sesion y permisos reales de Odoo.

- `POST /native-ui/health`: estado del bridge y capacidades.
- `POST /native-ui/session`: usuario, base, version y capacidades.
- `POST /native-ui/snapshot/index`: manifiesto y arbol de menus visible.
- `POST /native-ui/snapshot/materialize`: indice materializado y, opcionalmente, IR por modelo.
- `POST /native-ui/apps`: apps principales visibles.
- `POST /native-ui/menus`: arbol de menus visible.
- `POST /native-ui/action`: accion por referencia.
- `POST /native-ui/action/<id>`: accion por id.
- `POST /native-ui/model/<model>/fields`: metadata de campos.
- `POST /native-ui/model/<model>/views`: vistas solicitadas.
- `POST /native-ui/model/<model>/ir`: Native UI IR compacto derivado de las vistas.
- `POST /native-ui/model/<model>/permissions`: permisos efectivos del usuario.
- `POST /native-ui/model/<model>/defaults`: valores por defecto.
- `POST /native-ui/model/<model>/name-search`: busqueda lazy para many2one.
- `POST /native-ui/model/<model>/onchange`: onchange ejecutado por Odoo.
- `POST /native-ui/model/<model>/records`: lectura paginada.
- `POST /native-ui/model/<model>/record/<id>`: lectura de registro.
- `POST /native-ui/model/<model>/create`: creacion.
- `POST /native-ui/model/<model>/write`: escritura.
- `POST /native-ui/model/<model>/unlink`: eliminacion.
- `POST /native-ui/schema/<model>`: campos y vistas de un modelo.

## Politica de rendimiento

- Startup: solo manifiesto y menus.
- Vistas: carga bajo demanda por accion o modelo.
- Registros: `search_read` paginado.
- Limite por defecto: 80 registros.
- Limite maximo por llamada: 500 registros.
- Sin `sudo`: Odoo conserva ACL, grupos y record rules.
- Onchange y defaults se ejecutan en Odoo, no en el cliente.
- Many2one usa `name_search` remoto con limite.

## Native UI IR

El endpoint `/native-ui/model/<model>/ir` transforma XML de vistas Odoo en nodos semanticos compactos.

Tipos iniciales soportados:

- `Form`
- `List`
- `Search`
- `Group`
- `Section`
- `Notebook`
- `Tab`
- `Field`
- `Label`
- `Button`
- `Separator`
- `Spacer`

Los widgets no soportados se reportan en `unsupported` para priorizar compatibilidad sin fallar silenciosamente.

## Benchmarks

Ejecutar:

```powershell
Get-Content scripts\native_ui_benchmark.py | docker compose exec -T odoo odoo shell -c /etc/odoo/odoo.conf -d prueba --no-http --db_host=db --db_port=5432 --db_user=odoo --db_password=change_me_postgres_password
```

Baseline medido en `prueba`:

| Operacion | Mediana |
| --- | ---: |
| menus | 0.02 ms |
| snapshot_index | 1.91 ms |
| res.partner fields | 0.07 ms |
| res.partner IR | 3.81 ms |
| res.partner records limit 80 | 0.90 ms |

## Instalacion por base

Odoo 18 solo carga las rutas con `auth="user"` cuando el addon esta instalado en la registry de la base. Por eso el bridge se instala por base con:

```powershell
.\scripts\install_native_ui_bridge.ps1 -Database prueba
.\scripts\install_native_ui_bridge.ps1 -Database prueba -Upgrade
```

## Proximo componente

El siguiente paso es crear el cliente Windows nativo que consuma estos endpoints:

- `OdooConnection`
- `OdooSession`
- `OdooClient`
- pantalla `Connection Lab`
- cargador lazy de `snapshot/index`

## Native UI Lab temporal

Hasta tener tooling C++/WinUI instalado, `scripts/native_ui_lab_v2.ps1` funciona como cliente visual minimo:

- Ventana Windows nativa con WinForms.
- Autenticacion contra `/web/session/authenticate`.
- Carga `/native-ui/session` y `/native-ui/snapshot/index`.
- Lista apps visibles.
- Construye el arbol completo de menus.
- Abre modelos desde acciones `ir.actions.act_window`.
- Resuelve acciones por modelo concreto antes que por `ir.actions.actions` generico.
- Expone `domain_native` y `context_native` evaluados de forma segura por Odoo cuando la accion lo permite.
- Usa las vistas especificas de cada accion para pedir Native UI IR de `list` y `form`.
- Cachea campos, permisos e IR por modelo/vista durante la sesion del lab.
- Carga registros con paginacion.
- Busca por dominio remoto cuando el modelo lo permite.
- Genera columnas y formulario simple desde Native UI IR, con fallback por metadata.
- Renderiza formularios laterales por secciones y tabs cuando el IR trae `Notebook`/`Tab`.
- Usa controles nativos por tipo para campos simples: texto, texto largo, booleano y seleccion.
- Incluye una capa visual de producto: sidebar sin lineas antiguas, cabeceras de modulo y detalle, estado de conexion, grilla con espaciado moderno y titulo de ventana por vista.
- Respeta permisos efectivos para habilitar o deshabilitar crear/guardar.
- Guarda campos editables mediante `/native-ui/model/<model>/write`.
- Renderiza `Conversaciones` como vista nativa minima sobre `discuss.channel` y mensajes recientes de `mail.message`.
- Muestra acciones `ir.actions.act_url` como panel con enlace abrible.
- Limpia la pantalla para acciones no representables o errores de apertura, evitando mostrar datos anteriores.

No es el cliente final, pero permite validar el contrato visual y la carga lazy sin tecnologias web.
