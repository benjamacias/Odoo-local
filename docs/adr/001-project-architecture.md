# ADR 001 - Arquitectura inicial

## Estado

Aceptada.

## Decision

Comenzar por un bridge JSON dentro de Odoo antes de crear el cliente WinUI.

## Contexto

El repositorio actual contiene Odoo con Docker Compose y no contiene una solucion C++/WinUI.

## Consecuencias

El proyecto obtiene una conexion real y testeable. El cliente nativo puede avanzar sin depender de scraping, HTML, WebView ni metadata descargada en bloque.
