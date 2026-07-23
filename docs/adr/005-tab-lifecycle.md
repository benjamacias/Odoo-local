# ADR 005 - Ciclo de vida de pestanas

## Estado

Propuesta.

## Decision

El cliente nativo debera guardar estado de navegacion y datos minimos, no arboles visuales completos para cada pestana.

## Contexto

El objetivo del producto es permitir muchas pestanas con bajo consumo.

## Consecuencias

El bridge ya evita cargas masivas; el cliente debera implementar estados HOT, WARM y COLD.
