# Comparacion de rendimiento

Todavia no hay cliente WinUI para comparar contra Odoo Web.

## Baseline disponible

El bridge aplica estas decisiones desde la primera entrega:

- Carga inicial limitada a manifiesto y menus.
- Snapshot index con acciones y modelos sin materializar todos los XML.
- Metadata de campos y vistas bajo demanda.
- Native UI IR bajo demanda por modelo/vista.
- Registros con paginacion.
- Limite maximo de 500 registros por llamada.
- Sin duplicacion deliberada de datos en el servidor.

## Medicion local inicial

Base `prueba`, Odoo `18.0-20260609`.

| Operacion | Min | Mediana | Max |
| --- | ---: | ---: | ---: |
| menus | 0.02 ms | 0.02 ms | 11.78 ms |
| snapshot_index | 1.33 ms | 1.91 ms | 17.74 ms |
| res.partner fields | 0.06 ms | 0.07 ms | 3.18 ms |
| res.partner IR | 3.60 ms | 3.81 ms | 25.67 ms |
| res.partner records limit 80 | 0.56 ms | 0.90 ms | 3.59 ms |

## Medicion despues del lab v2

Base local de prueba, Odoo `18.0-20260609`, bridge con resolucion de acciones concretas y soporte de IR por vista de accion.

| Operacion | Min | Mediana | Max |
| --- | ---: | ---: | ---: |
| menus | 0.10 ms | 0.15 ms | 35.87 ms |
| snapshot_index | 20.70 ms | 21.72 ms | 543.97 ms |
| res.partner fields | 0.06 ms | 0.09 ms | 5.46 ms |
| res.partner IR | 6.04 ms | 6.90 ms | 86.50 ms |
| res.partner records limit 80 | 0.66 ms | 0.95 ms | 4.41 ms |

El cliente visual mantiene cache en memoria por sesion para campos, permisos e IR, por lo que la apertura repetida de un modelo no vuelve a descargar esa metadata.

## Pendiente

Medir contra Odoo Web cuando exista el cliente nativo:

- RAM idle.
- CPU idle.
- startup.
- apertura de primer modelo.
- 10, 25 y 50 pestanas.
- trafico de red.
