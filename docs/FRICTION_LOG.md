# Friction Log

## Problema

El objetivo completo pide una aplicacion WinUI/C++ y un runtime nativo completo, pero el repositorio existente solo contiene una instalacion Docker de Odoo.

## Que intentamos

Implementar el minimo funcional que conecte Odoo con el proyecto y prepare carga lazy de UI.

## Por que fallo o se limito

No existe todavia un proyecto C++/WinUI, solucion de Visual Studio ni baseline local documentado de Windows App SDK.

## Solucion

Crear primero el `native_ui_bridge` en Odoo, con endpoints estables para que el cliente nativo pueda consumir sesion, menus, acciones, campos, vistas y registros bajo demanda.

## Severidad

5

## Categoria

Arquitectura / Odoo / Implementacion
