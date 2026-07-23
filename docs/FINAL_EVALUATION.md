# Evaluacion final

Estado: evaluacion parcial.

Esta entrega cubre conexion Odoo-proyecto, endpoints optimizados para carga lazy, Native UI IR inicial, snapshot index/materializado, defaults, name-search, onchange y CRUD basico.

El exito del producto debe evaluarse cuando exista un cliente Windows nativo que renderice al menos `res.partner` desde metadata real de Odoo.

Prueba parcial lograda:

- Odoo `18.0-20260609` responde `/native-ui/health`.
- Base `prueba` tiene 21 rutas `/native-ui/*` registradas.
- `res.partner` genera IR `form,list`.
- Smoke test lee 5 registros y ejecuta onchange.
