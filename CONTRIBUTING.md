# Contribuir

## Flujo De Desarrollo

- Trabajar en ramas de feature, no directamente en main.
- Mantener cambios acotados y alineados con los limites de la etapa actual.
- Preferir tipos de dominio y componentes pequenos sobre logica improvisada dentro de paginas.
- No agregar dependencias sin documentar por que son necesarias.

## Controles Locales

Antes de abrir un pull request, ejecutar:

```sh
npm run ci
```

Este comando ejecuta formato, lint, chequeo de Astro/TypeScript, pruebas unitarias y build de produccion.

## Datos Y Seguridad

- No agregar secretos, tokens, passwords ni credenciales reales.
- No agregar datos personales.
- No agregar documentos academicos reales en etapa 1.
- No confiar en roles enviados por el navegador en trabajos futuros de autorizacion.
- Mantener archivos .env ignorados excepto .env.example.

## Documentacion

Actualizar README o docs cuando cambien comportamiento, arquitectura o setup. Las decisiones arquitectonicas importantes deben registrarse en docs/adr/.
