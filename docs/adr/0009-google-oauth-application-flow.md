# ADR 0009: Flujo de aplicacion para Google OAuth con PKCE

## Estado

Aceptada, pendiente de configurar el proveedor remoto en 3B.2B.

## Contexto

ADR 0006 preparo las fabricas Supabase para navegador y servidor. ADR 0007 agrego `Astro.locals.auth` con identidad validada por request. ADR 0008 conecto `auth.users` con `public.profiles` y dejo PostgreSQL como autoridad para validar dominios institucionales exactos.

La etapa 3B.2A debe agregar el flujo de aplicacion para iniciar Google OAuth y procesar el callback PKCE, pero sin crear credenciales reales, proyecto Supabase remoto, configuracion del proveedor, rutas privadas ni reglas nuevas de autorizacion.

Supabase Auth puede devolver `provider_token` y `provider_refresh_token` junto con la sesion tras intercambiar el codigo OAuth. `auth-js` persiste la sesion adquirida antes de que la ruta Astro reciba el resultado. Por ello, ignorar esos campos en el callback no evita que se escriban en el almacenamiento SSR. La aplicacion no necesita llamar APIs de Google y no debe conservar esos tokens.

## Decision

### Pagina de acceso

Crear una pagina GET `/auth/sign-in` que muestra un unico formulario para continuar con Google. La pagina acepta `next` solo como destino interno validado, muestra mensajes genericos mediante codigos controlados y redirige a usuarios ya autenticados a un destino interno seguro. Cuando Supabase esta sin configurar, la pagina sigue renderizando y muestra un estado controlado.

Los destinos posteriores a autenticacion no pueden apuntar a `/auth` ni a sus subrutas. Esto evita bucles y reentrada accidental en login, callback o logout.

### Inicio OAuth

Crear POST `/auth/google` como unica entrada para iniciar OAuth. El endpoint:

- valida `Origin` cuando el navegador lo envia;
- evita reiniciar OAuth si `Astro.locals.auth.status` ya es `authenticated`;
- usa `Astro.locals.auth.supabase`;
- rechaza entornos sin cliente Supabase;
- valida `next` como destino interno posterior a autenticacion;
- construye `redirectTo` con el origin efectivo de la request y `/auth/callback`;
- llama a `auth.signInWithOAuth({ provider: 'google', options: { redirectTo } })`.

La URL final de autorizacion la entrega Supabase Auth. La aplicacion no construye manualmente URLs de Google, no agrega scopes, no solicita APIs de Google y no usa metadata OAuth para autorizacion.

### Callback PKCE

Crear GET `/auth/callback` para el callback de Supabase Auth hacia Astro. El endpoint:

- procesa `code`;
- trata `error` y `error_description` sin reflejar valores no confiables;
- valida `next`;
- exige cliente Supabase configurado;
- ejecuta `auth.exchangeCodeForSession(code)`;
- valida despues la identidad mediante `auth.getUser()`;
- no usa `getSession()` como autoridad;
- limpia la sesion local de forma best-effort si el intercambio tuvo exito pero la validacion posterior del usuario falla;
- redirige finalmente sin conservar `code` ni errores del proveedor en la URL.

### No persistencia de tokens de Google

Crear `src/infrastructure/supabase/provider-token-redaction.ts` como adaptador de `fetch` para los clientes Supabase. El adaptador solo reescribe respuestas exitosas y JSON del endpoint exacto `/auth/v1/token` del mismo origin configurado. Antes de que `auth-js` procese la respuesta, elimina recursivamente las propiedades `provider_token` y `provider_refresh_token`.

Las fabricas server y browser inyectan este adaptador mediante `global.fetch`. La garantia de no conservar tokens del proveedor depende de eliminarlos antes de que la sesion llegue a `auth-js`. No se confia en opciones de serializacion de cookies para esta propiedad.

La redaccion conserva los tokens propios de Supabase necesarios para la sesion (`access_token` y `refresh_token`). No registra ni expone valores eliminados.

### Logout

Crear POST `/auth/sign-out` como unica ruta de logout. El endpoint valida `Origin` cuando esta presente, ignora cualquier identificador o token enviado por formulario, ejecuta `auth.signOut({ scope: 'local' })` cuando hay cliente SSR y redirige con 303 a un destino interno seguro. Logout es idempotente desde la perspectiva de la aplicacion.

### Cookies y middleware

El middleware de ADR 0007 conserva la responsabilidad de propagar cookies individuales `Set-Cookie` y headers anticache escritos por Supabase SSR. Los endpoints no copian sesiones, tokens ni roles a `Astro.locals` ni a respuestas propias.

## Callbacks

Existen dos callbacks distintos:

1. Google -> Supabase Auth: callback administrada por Supabase Auth y configurada en Google/Supabase durante 3B.2B.
2. Supabase Auth -> aplicacion Astro: `/auth/callback`, implementada en 3B.2A para completar el intercambio PKCE en el cliente SSR.

La configuracion real del proveedor Google, credenciales, allow-list remota de redirects y proyecto Supabase pertenecen a 3B.2B.

## Autoridad de dominio y roles

Google OAuth confirma identidad ante Supabase Auth, pero no es autoridad del dominio institucional. La aplicacion no confia en `hd`, emails mostrados por el navegador, `raw_user_meta_data`, `app_metadata` ni metadata del proveedor. Los triggers PostgreSQL existentes siguen validando que el email de `auth.users` pertenezca exactamente a un dominio habilitado.

Completar OAuth no asigna roles. PostgreSQL sigue siendo la autoridad de roles y las paginas del catalogo continuan publicas en esta etapa.

## Manejo de errores

Los errores de Google, Supabase y PostgreSQL se traducen a codigos controlados de aplicacion. No se reflejan descripciones del proveedor, mensajes SQL, tokens, codigos de intercambio ni detalles internos.

## Pruebas

Las pruebas unitarias no realizan llamadas reales. Cubren:

- validacion de destinos internos y rechazo de rutas `/auth`;
- inicio OAuth y construccion de `redirectTo`;
- rechazo de `Origin` externo;
- usuario ya autenticado;
- callback sin codigo, errores de proveedor e intercambio fallido;
- orden `exchangeCodeForSession` -> `getUser`;
- limpieza local si falla la validacion posterior;
- logout solo por POST y validacion de origen;
- redaccion de tokens de proveedor antes de entregar la respuesta a Supabase;
- configuracion segura de las fabricas browser y server.

## Consecuencias

- La aplicacion tiene rutas de login, callback y logout revisables sin credenciales reales.
- El flujo PKCE depende del cliente server de `@supabase/ssr`, que configura `flowType: 'pkce'` y maneja cookies mediante el middleware existente.
- Los tokens propios de Google no llegan al almacenamiento administrado por `auth-js`.
- Las rutas privadas, administracion de roles y configuracion real de Google quedan fuera de esta etapa.
- Una actualizacion futura de `@supabase/ssr` o `@supabase/supabase-js` debe volver a verificar la forma de la respuesta `/auth/v1/token` y la persistencia de sesion.

## Alternativas consideradas

- Iniciar OAuth con GET: rechazado porque inicia una operacion autenticadora y dificulta controles contra solicitudes involuntarias.
- Construir manualmente una URL de Google: rechazado porque Supabase Auth debe administrar proveedor, estado y PKCE.
- Confiar en `hd` o metadata OAuth para dominio institucional: rechazado porque PostgreSQL ya es la autoridad reproducible.
- Usar `getSession()` como autoridad en el callback: rechazado porque no valida al usuario contra Supabase.
- Ignorar `provider_token` despues de `exchangeCodeForSession`: rechazado porque `auth-js` ya puede haber persistido la sesion.
- Confiar en `cookies.encode = 'tokens-only'`: rechazado como garantia; esa opcion separa el objeto usuario, pero no demuestra que elimine tokens del proveedor ubicados en la sesion.
- Implementar logout por GET: rechazado porque facilita ejecuciones no intencionales.
