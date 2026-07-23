# ADR 010 - Renderizado hibrido

## Estado

Propuesta.

## Decision

El orden futuro de resolucion sera: vista nativa optimizada, vista generada si demuestra ventaja medida, y renderer dinamico como base.

## Contexto

La estrategia de producto exige comparar objetivamente generated native contra dynamic native.

## Consecuencias

El bridge no asume un renderer. Entrega la metadata necesaria para que el cliente elija la estrategia mas eficiente por modelo o vista.
