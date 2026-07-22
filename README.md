# FC Academic Hub

FC Academic Hub es la base de una plataforma academica comunitaria de la Facultad de Ciencias. El objetivo es organizar cursos, examenes, apuntes, silabos y recursos relacionados con seguridad y bajo costo operativo.

La etapa actual implementa un catalogo academico publico y estatico con los cinco planes de estudios 2018 importados desde un paquete normalizado. No contiene documentos academicos reales, datos personales, login, conexion a Supabase, PostgreSQL, integracion con Cloudflare R2 ni URLs de descarga.

## Alcance actual

- Astro con TypeScript estricto.
- Adaptador de Cloudflare configurado para un futuro despliegue en Pages/Workers.
- Content Collections con datos JSON versionados en Git.
- Catalogo activo con 386 cursos, 556 relaciones curso-plan, 5 planes curriculares y 11 unidades academicas.
- Capa de consulta en `src/domain/catalog.ts` para aislar paginas y componentes del almacenamiento.
- Validaciones de integridad para duplicados, relaciones cruzadas, prerrequisitos, ciclos, silabos, fuentes y restricciones de storage.
- Paginas publicas para `/`, `/schools`, `/schools/[slug]`, `/courses`, `/courses/[slug]`, `/resources`, `/about` y 404.
- Endpoint JSON GET `/api/health` con version tomada de `package.json`.

## Requisitos

- Node.js >=22.12.0.
- npm con instalacion basada en lockfile.

## Instalacion

```sh
npm ci
npm run dev
```

## Controles de calidad

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
  content/          Datos activos del catalogo versionados en Git.
  domain/           Tipos, filtros, consultas y validaciones del catalogo.
  infrastructure/   Helpers de servidor, como el payload de health.
  layouts/          Shell compartido del documento y estilos globales.
  pages/            Rutas Astro y endpoints API.
data/
  import/           Paquetes staging usados para importaciones revisables.
docs/
  adr/              Registros de decision arquitectonica.
  architecture/     Documentos de arquitectura.
  data/             Modelo y guias para contenido del catalogo.
```

## Agregar contenido

Los registros activos se agregan editando JSON en `src/content/catalog/`, no componentes. Ver `docs/data/catalog-model.md`, `docs/data/adding-catalog-content.md` y `docs/data/plan-2018-import.md` antes de cambiar datos.

## Limites vigentes

- No instalar ni configurar Supabase todavia.
- No usar PostgreSQL todavia.
- No crear buckets, namespaces ni bindings Cloudflare nuevos.
- No implementar autenticacion, roles ni login ficticio.
- No implementar formularios de subida.
- No almacenar documentos, PDFs, TEX, binarios, libros comerciales ni registros reales de recursos.
- No commitear secretos. Mantener archivos `.env*` ignorados excepto `.env.example`.
- No desplegar sin autorizacion explicita.

## Cloudflare SESSION/KV

Con `@astrojs/cloudflare@14.1.4`, Astro muestra que habilita sesiones con KV `SESSION` si no hay driver de sesion configurado. FC Academic Hub no usa sesiones en esta etapa y `wrangler.jsonc` no declara KV. La decision esta documentada en `docs/adr/0002-static-academic-catalog.md` y debe revisarse antes de desplegar una etapa futura.
