# ADR 008 - Permission Overlay

## Estado

Aceptada para el bridge.

## Decision

No usar `sudo` en endpoints de datos de negocio.

## Contexto

La UI publicada no es autoridad de seguridad. Odoo debe validar grupos, ACL y record rules.

## Consecuencias

Los menus y registros visibles dependen del usuario autenticado. El cliente nativo debera aplicar una capa visual adicional, pero no confiar en ella como seguridad.
