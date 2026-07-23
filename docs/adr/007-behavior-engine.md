# ADR 007 - Behavior Engine

## Estado

Propuesta.

## Decision

La logica empresarial debe seguir ejecutandose en Odoo. El cliente nativo solo aplica presentacion, estado visual y respuestas del servidor.

## Contexto

Readonly, invisible, required, onchange, domains y validaciones dependen de reglas de Odoo.

## Consecuencias

El bridge expone metadata y datos, pero no reimplementa reglas de negocio en Python ni en el cliente.
