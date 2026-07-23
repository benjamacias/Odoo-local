# ADR 009 - Publicacion de UI

## Estado

Propuesta.

## Decision

La primera entrega usa `/native-ui/snapshot/index` como indice publicable minimo. La publicacion atomica de snapshots queda para una etapa posterior.

## Contexto

Todavia no existe materializador de Native UI IR ni runtime WinUI.

## Consecuencias

El cliente puede arrancar con menus y cargar por demanda. Versionado, staging y rollback se implementaran cuando exista snapshot persistente real.
