# FC Academic Hub

FC Academic Hub es la base de una plataforma academica comunitaria de la Facultad de Ciencias. El objetivo es organizar cursos, examenes, apuntes, silabos y recursos relacionados con seguridad y bajo costo operativo.

La etapa actual implementa un catalogo academico publico y estatico con una primera muestra controlada de cursos reales migrados desde Drive FC. No contiene documentos academicos reales, datos personales, login, conexion a Supabase, PostgreSQL, integracion con Cloudflare R2 ni URLs de descarga.

## Alcance Actual

- Astro con TypeScript estricto.
- Adaptador de Cloudflare configurado para un futuro despliegue en Pages/Workers.
- Content Collections con datos JSON versionados en Git.
- Catalogo versionado con unidades academicas, planes, cursos, relaciones curriculares, periodos y recursos.
- Capa de consulta en `src/domain/catalog.ts` para aislar paginas y componentes del almacenamiento.
- Validaciones de integridad para duplicados, relaciones cruzadas, terminos, prerrequisitos y restricciones de storage.
- Paginas publicas para `/`, `/schools`, `/schools/[slug]`, `/courses`, `/courses/[slug]`, `/resources`, `/about` y 404.
- Modo oscuro con `prefers-color-scheme`, boton accesible y persistencia local.
- Endpoint JSON GET `/api/health` con version tomada de `package.json`.
- Scripts de formato, lint, Astro check, pruebas unitarias y build.

## Requisitos

- Node.js >=22.12.0.
- npm con instalacion basada en lockfile.

## Instalacion

Instalar dependencias de forma reproducible:

```sh
npm ci
```

Iniciar el servidor local:

```sh
npm run dev
```

## Controles De Calidad

Ejecutar el pipeline local completo:

```sh
npm run ci
```

Controles individuales:

```sh
npm run format:check
npm run lint
npm run check
npm run test
npm run build
```

El script `npm run deploy` queda reservado para un flujo futuro con autorizacion explicita. No desplegar sin aprobacion.

## Estructura

```text
src/
  components/       Componentes Astro reutilizables.
  config/           Configuracion general del sitio.
  content/          Datos del catalogo versionados en Git.
  domain/           Tipos, filtros, consultas y validaciones del catalogo.
  infrastructure/   Helpers de servidor, como el payload de health.
  layouts/          Shell compartido del documento y estilos globales.
  pages/            Rutas Astro y endpoints API.
docs/
  adr/              Registros de decision arquitectonica.
  architecture/     Documentos de arquitectura.
  data/             Modelo y guias para contenido del catalogo.
```

## Agregar Contenido

Los registros se agregan editando JSON en `src/content/catalog/`, no componentes:

- `academic-units.json`
- `curricula.json`
- `curriculum-courses.json`
- `academic-terms.json`
- `courses.json`
- `resources.json`

Ver `docs/data/catalog-model.md` y `docs/data/adding-catalog-content.md` antes de agregar contenido.

## Limites De Etapa 2

- No instalar ni configurar Supabase todavia.
- No usar PostgreSQL todavia.
- No crear buckets, namespaces ni bindings Cloudflare nuevos.
- No implementar autenticacion, roles ni login ficticio.
- No implementar formularios de subida.
- No almacenar documentos, PDFs, TEX, binarios, libros comerciales ni registros reales de cursos.
- No commitear secretos. Mantener archivos `.env*` ignorados excepto `.env.example`.
- No desplegar sin autorizacion explicita.

## Cloudflare SESSION/KV

Con `@astrojs/cloudflare@14.1.4`, Astro muestra que habilita sesiones con KV `SESSION` si no hay driver de sesion configurado. FC Academic Hub no usa sesiones en etapa 2 y `wrangler.jsonc` no declara KV. La decision esta documentada en `docs/adr/0002-static-academic-catalog.md` y debe revisarse antes de desplegar una etapa futura.
