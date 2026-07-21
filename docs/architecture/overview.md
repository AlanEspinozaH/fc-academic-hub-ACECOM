# Resumen De Arquitectura

## Proposito

FC Academic Hub organizara cursos, examenes, apuntes, silabos y recursos para la comunidad de la Facultad de Ciencias. El sistema objetivo debe ser seguro, de bajo costo y mantenible por administradores estudiantes.

## Arquitectura De Etapa 1

La implementacion actual es una aplicacion Astro con TypeScript estricto y adaptador de Cloudflare. Incluye paginas publicas, endpoint de health y datos ficticios de cursos de demostracion.

```text
Navegador
  -> Paginas y rutas API de Astro
  -> Modulos de dominio/configuracion en src/
  -> Adaptador Cloudflare para futuro runtime Pages/Workers
```

No hay integracion activa con productos externos en etapa 1.

## Limites De Codigo Fuente

- src/domain/ contiene conceptos academicos como Course y AcademicTerm, mas registros ficticios de demostracion.
- src/config/ contiene metadatos generales y navegacion.
- src/components/ y src/layouts/ contienen presentacion.
- src/infrastructure/ contiene helpers de servidor que no son conceptos de dominio.
- src/pages/ contiene rutas Astro y endpoints API.

## Integraciones Futuras

Supabase Auth/PostgreSQL y storage privado en Cloudflare R2 quedan para etapas posteriores. La autorizacion debe validarse en servidor, no inferirse desde roles enviados por el navegador.

## Controles Operativos

CI instala dependencias con npm ci y ejecuta formato, lint, astro check, pruebas unitarias y build. El despliegue no es automatico en esta etapa.
