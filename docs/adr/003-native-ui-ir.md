# ADR 003 - Native UI IR

## Estado

Propuesta.

## Decision

El bridge no genera controles ni HTML. Entrega metadata semantica para que el cliente nativo cree una representacion intermedia propia.

## Contexto

La capa visual debe evitar WebView, HTML, CSS y JavaScript para conservar una experiencia nativa.

## Consecuencias

La interpretacion de XML de vistas y el render nativo quedan del lado del cliente WinUI futuro.
