# ADR 0001: Arquitectura Inicial

## Estado

Aceptada

## Contexto

FC Academic Hub necesita una base mantenible antes de introducir identidad, almacenamiento de metadatos o almacenamiento privado de archivos. La etapa 1 debe evitar Supabase, R2, autenticacion ficticia, documentos reales y datos personales.

## Decision

Usar Astro con TypeScript estricto y el adaptador de Cloudflare como base de aplicacion. Mantener tipos de dominio en src/domain/, presentacion en componentes/layouts Astro, metadatos compartidos en src/config/ y helpers de servidor en src/infrastructure/.

Exponer solo paginas publicas informativas, cursos ficticios de demostracion y un endpoint GET /api/health cuya version proviene de package.json.

Los controles de calidad son Prettier, ESLint, astro check, Vitest y astro build, reflejados en GitHub Actions con npm ci.

## Consecuencias

- El repositorio tiene un lugar claro para reglas de dominio antes de crear una base de datos.
- La aplicacion puede compilar para Cloudflare sin provisionar servicios externos.
- Los datos demo son explicitos y seguros para reemplazo futuro.
- El trabajo futuro de Supabase y R2 necesitara ADRs separados para autenticacion, autorizacion, storage y politicas de acceso a datos.

## Alternativas Consideradas

- Agregar Supabase de inmediato: rechazado porque etapa 1 prohibe integrar identidad y base de datos externas.
- Implementar login simulado: rechazado porque podria normalizar confiar en roles enviados por el navegador.
- Almacenar documentos de ejemplo: rechazado porque etapa 1 prohibe documentos reales y storage de archivos.
