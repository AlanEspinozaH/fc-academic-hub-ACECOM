# FC Academic Hub

FC Academic Hub es una plataforma académica comunitaria para organizar cursos, exámenes, apuntes, sílabos y otros recursos de la Facultad de Ciencias.

El proyecto prioriza:

* seguridad;
* moderación;
* derechos sobre los recursos;
* bajo costo operativo;
* mantenimiento simple.

## Estado actual

El proyecto utiliza:

* Astro con TypeScript estricto;
* Cloudflare Workers como runtime SSR;
* Supabase Auth con Google OAuth;
* PostgreSQL y RLS para identidad, roles, metadatos y autorización;
* Cloudflare R2 privado para almacenamiento de archivos;
* Content Collections/JSON para el catálogo académico actual.

La infraestructura implementada incluye:

* catálogo académico público;
* autenticación Google OAuth;
* sesiones SSR;
* perfiles y roles PostgreSQL;
* RLS y RPC transaccionales;
* metadatos de recursos académicos;
* workflow `draft -> pending -> approved | rejected`;
* almacenamiento privado de archivos;
* endpoint server-side de subida PDF;
* SHA-256;
* compensación PostgreSQL/R2;
* auditoría de operaciones relevantes.

El endpoint de subida actual es:

```text
POST /api/resources/:resourceId/files
```

La implementación operativa de 4B continúa siendo PDF-only.

Stage 4C está siendo diseñado para incorporar:

* acceso `public`, `restricted` y `privileged`;
* lectura, preview y download server-side;
* `ResourceFile` genérico;
* PNG/JPEG;
* Markdown, TeX, TXT y source code allowlisted;
* identidades externas preautorizadas;
* entitlements de acceso privilegiado.

Estas capacidades no deben considerarse implementadas hasta que sus respectivas etapas de 4C hayan sido completadas.

## Arquitectura

```text
Browser
   │
   ▼
Astro / Cloudflare Worker
   │
   ├── Supabase Auth
   │
   ▼
PostgreSQL / RLS
   │
   └── autorización y metadatos
   │
   ▼
private Cloudflare R2
```

PostgreSQL es la autoridad de autorización.

R2 almacena objetos privados y no decide:

* roles;
* ownership;
* revisión;
* audiencia;
* derechos.

## Documentación normativa

Antes de modificar recursos académicos, consultar:

* `docs/product/v1-product-contract.md`
* `docs/architecture/resource-access-contract.md`
* `docs/architecture/resource-file-policy.md`
* `docs/architecture/resource-upload-contract.md`
* `docs/architecture/authentication-and-authorization.md`
* `docs/security/role-model.md`
* `docs/adr/`

`AGENTS.md` contiene las instrucciones de trabajo para Codex.

## Requisitos

* Node.js >= 22.12.0
* npm
* Docker para Supabase local cuando se ejecuten pruebas de base de datos

## Instalación

```sh
npm ci
```

Crear configuración local:

```sh
cp .env.example .env.local
```

Configurar únicamente los valores públicos requeridos por el entorno local.

No versionar:

* Client Secrets;
* passwords;
* JWT secrets;
* tokens;
* cookies;
* credenciales de infraestructura.

Iniciar desarrollo:

```sh
npm run dev
```

## Supabase local

El proyecto utiliza Supabase local para migraciones y pruebas PostgreSQL.

```sh
npx --yes supabase@2.109.1 start
npx --yes supabase@2.109.1 db reset
npx --yes supabase@2.109.1 test db
npx --yes supabase@2.109.1 db lint --local
npx --yes supabase@2.109.1 stop
```

Las operaciones contra un proyecto remoto, incluyendo `login`, `link` o `db push`, deben realizarse únicamente de forma intencional y después de verificar el proyecto y las migraciones involucradas.

## Calidad

Ejecutar el pipeline completo:

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

Antes de finalizar un cambio deben pasar los controles aplicables y revisarse:

```sh
git status
git diff
```

## Estructura

```text
src/
  components/        Componentes Astro.
  config/            Configuración de aplicación.
  content/           Catálogo académico versionado.
  domain/            Reglas y tipos de dominio.
  application/       Casos de uso y orquestación.
  infrastructure/    Supabase, R2 y adaptadores externos.
  http/              Lógica HTTP server-side.
  layouts/           Layouts compartidos.
  pages/             Páginas y endpoints Astro.

data/
  import/            Datos staging para importaciones.

docs/
  adr/               Architecture Decision Records.
  architecture/      Contratos técnicos.
  product/           Contratos de producto.
  operations/        Procedimientos operativos.
  data/              Documentación del catálogo.
  security/          Roles y políticas de seguridad.

supabase/
  migrations/        Migraciones PostgreSQL.
  tests/database/    Pruebas pgTAP.
```

## Catálogo académico

Los datos académicos actualmente versionados se mantienen en:

```text
src/content/catalog/
```

Antes de modificarlos consultar:

* `docs/data/catalog-model.md`
* `docs/data/adding-catalog-content.md`
* `docs/data/plan-2018-import.md`

Las páginas y componentes no deben convertirse en la fuente de datos del catálogo.

## Seguridad

Reglas fundamentales:

* no usar `service_role` en el runtime normal de Astro;
* no confiar en roles o permisos enviados por el navegador;
* no exponer `storage_key`;
* mantener R2 privado;
* validar uploads server-side;
* no ejecutar ni compilar archivos aportados por usuarios;
* aplicar mínimo privilegio;
* no ampliar formatos, roles, entitlements o audiencias fuera de los contratos aceptados;
* no desplegar ni modificar infraestructura remota sin autorización explícita.

## Limitaciones actuales

Mientras Stage 4C no esté implementado completamente:

* la subida operativa continúa siendo PDF-only;
* no existe todavía preview/download general de archivos;
* los nuevos formatos definidos por el contrato todavía no están habilitados;
* `privileged` y los entitlements asociados todavía requieren implementación;
* las identidades externas preautorizadas forman parte del diseño objetivo, no del baseline actual;
* no existen múltiples archivos por recurso;
* no se ejecutan ni compilan uploads;
* no se habilitan URLs públicas directas de R2.

## Desarrollo incremental

Las capacidades de 4C deben implementarse en cambios pequeños y verificables.

No debe implementarse todo Stage 4C como un único cambio.

Cada etapa debe mantener alineados:

```text
contracts
+
database
+
application
+
tests
+
documentation
```
