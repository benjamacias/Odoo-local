# ADR 006 - Presupuesto de memoria

## Estado

Propuesta.

## Decision

El cliente nativo debe definir presupuestos medibles antes de ampliar pantallas y modulos.

## Contexto

El objetivo central es reducir RAM y CPU frente a Odoo Web.

## Consecuencias

El bridge limita cargas por llamada y evita metadata completa en startup. El cliente futuro debera medir RAM idle, coste por pestana y reapertura.
