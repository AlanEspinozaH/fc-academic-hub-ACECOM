# ADR 0006: Fundamento de clientes Supabase para Astro SSR

## Estado

Aceptada

## Contexto

La etapa 3A.1 dejo listas las bases locales de PostgreSQL para roles, auditoria y RLS, pero la aplicacion Astro aun no tenia una forma tipada y revisable de construir clientes Supabase. La etapa 3A.2A debe preparar esa base sin activar login visible, OAuth, middleware, endpoints de callback ni renovacion automatica de sesiones.

El despliegue objetivo sigue siendo Cloudflare Pages/Workers con `@astrojs/cloudflare` y `output: 'server'`. No se deben crear proyectos remotos, buckets R2, secretos ni credenciales reales.

## Decision

Instalar unicamente `@supabase/supabase-js` y `@supabase/ssr`. La configuracion de entorno queda limitada a `PUBLIC_SUPABASE_URL` y `PUBLIC_SUPABASE_PUBLISHABLE_KEY`, documentadas con placeholders en `.env.example` y pensadas para valores reales locales en `.env.local`.

Crear `src/infrastructure/supabase/config.ts` con una funcion pura que valida existencia, URL `http`/`https`, placeholders y uso accidental de una llave secreta en el lugar de la llave publicable. La funcion no imprime valores sensibles en errores y devuelve un objeto congelado.

Crear `src/infrastructure/supabase/browser.ts` con una fabrica lazy basada en `createBrowserClient`. El modulo no crea clientes al importarse, no ejecuta login ni consultas, y reutiliza una instancia en el navegador.

Crear `src/infrastructure/supabase/server.ts` con una fabrica por request basada en `createServerClient`. La fabrica recibe `Request`, `AstroCookies` y `Headers` explicitamente: lee todas las cookies desde el header `Cookie` mediante `parseCookieHeader`, escribe con `AstroCookies.set` usando `setAll`, conserva las opciones de cookie que entrega Supabase y propaga headers de respuesta obligatoriamente. No hay singleton de servidor.

## Seguridad

La publishable key identifica el proyecto y esta disenada para estar disponible en el navegador. No otorga privilegios administrativos por si sola. La seguridad real para datos y metadatos depende de RLS, permisos de PostgreSQL y validaciones del servidor.

Las llaves secretas quedan fuera del runtime de Astro y del repositorio. No se declara variable de entorno para ellas en esta etapa. PostgreSQL sigue siendo la autoridad de roles; los clientes de navegador no son fuente confiable de autorizacion.

## Consecuencias

- Las futuras paginas y endpoints SSR tendran una base comun para construir clientes sin repetir lectura de entorno ni manejo de cookies.
- La etapa no cambia el catalogo estatico, migraciones SQL ni politicas RLS.
- La renovacion de sesion en middleware, llamadas a `getUser`/`getClaims` y flujos OAuth pertenecen a 3A.2B o etapas posteriores.
- Cloudflare continua como adaptador; no se agrega `@astrojs/node` ni otro runtime.

## Alternativas Consideradas

- Usar auth helpers obsoletos: rechazado porque `@supabase/ssr` expone la interfaz recomendada `getAll`/`setAll`.
- Crear middleware ahora: rechazado porque esta etapa solo prepara fabricas y entorno.
- Usar una llave secreta en el servidor Astro: rechazado porque ampliaria privilegios del runtime y podria omitir RLS.
- Leer roles desde `localStorage`: rechazado porque el navegador no es autoridad de autorizacion.
