# FC Academic Hub

FC Academic Hub es la base de etapa 1 para una plataforma academica comunitaria de la Facultad de Ciencias. El objetivo es organizar cursos, examenes, apuntes, silabos y recursos relacionados con seguridad y bajo costo operativo.

Esta etapa no contiene documentos academicos reales, datos personales, login, conexion a Supabase ni integracion con Cloudflare R2.

## Alcance Actual

- Astro con TypeScript estricto.
- Adaptador de Cloudflare configurado para un futuro despliegue en Pages/Workers.
- Layout accesible con cabecera, navegacion, contenido principal y pie.
- Paginas para /, /courses, /about y 404 personalizada.
- Endpoint JSON GET /api/health con version tomada de package.json.
- Tipos iniciales de dominio para Course y AcademicTerm.
- Dos cursos ficticios marcados claramente como datos de demostracion.
- Scripts de formato, lint, astro check, pruebas unitarias y build.

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

El script npm run deploy queda reservado para un flujo futuro con autorizacion explicita. No desplegar sin aprobacion.

## Estructura

```text
src/
  components/       Componentes Astro reutilizables.
  config/           Configuracion general del sitio.
  domain/           Tipos academicos y datos ficticios de demostracion.
  infrastructure/   Helpers de servidor, como el payload de health.
  layouts/          Shell compartido del documento y estilos globales.
  pages/            Rutas Astro y endpoints API.
docs/
  adr/              Registros de decision arquitectonica.
  architecture/     Documentos de arquitectura.
```

## Limites De Etapa 1

- No instalar ni configurar Supabase todavia.
- No crear buckets ni bindings de Cloudflare R2 todavia.
- No implementar autenticacion ficticia.
- No almacenar documentos, registros reales de cursos ni datos personales.
- No commitear secretos. Mantener archivos .env ignorados excepto .env.example.
