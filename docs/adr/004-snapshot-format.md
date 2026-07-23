# ADR 004 - Snapshot inicial

## Estado

Aceptada para la primera entrega.

## Decision

El snapshot inicial es un indice JSON con manifiesto y menus visibles, no una materializacion completa de todas las vistas.

## Contexto

La prioridad es arranque rapido y bajo consumo.

## Consecuencias

El cliente carga campos, vistas y registros por demanda. El formato binario queda pendiente hasta tener mediciones.
