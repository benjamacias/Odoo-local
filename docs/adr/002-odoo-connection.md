# ADR 002 - Conexion con Odoo

## Estado

Aceptada.

## Decision

Usar JSON-RPC autenticado y endpoints `/native-ui/*` servidos por Odoo.

## Contexto

Odoo ya expone autenticacion de sesion y aplica permisos, ACL y record rules en el ORM.

## Consecuencias

El cliente nativo reutiliza seguridad real de Odoo. Las rutas del bridge no usan `sudo` para datos de negocio.

`/native-ui/health` usa `auth="none"` para bootstrap sin base. El resto usa `auth="user"` y requiere que `native_ui_bridge` este instalado en la base Odoo.
