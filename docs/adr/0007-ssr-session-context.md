# ADR 0007: Contexto SSR de sesion con Astro.locals

## Estado

Aceptada

## Contexto

ADR 0006 dejo listas las fabricas Supabase para navegador y servidor, pero la aplicacion aun no tenia un punto unico para validar la identidad de cada request SSR. La etapa 3A.2B debe poblar `Astro.locals` sin crear login visible, OAuth, endpoints de callback, paginas privadas ni administracion de roles.

La aplicacion sigue ejecutandose con `@astrojs/cloudflare` y `output: 'server'`. El entorno Supabase puede no estar configurado durante build, prerender o desarrollo local, y esa ausencia no debe crear clientes invalidos ni romper rutas publicas.

## Decision

Crear `src/middleware.ts` con `defineMiddleware`. En cada request el middleware crea un `Headers` nuevo para la respuesta, construye un cliente Supabase server mediante la fabrica existente y entrega explicitamente `Request`, `AstroCookies` y `Headers` como contexto obligatorio por request.

Cuando Supabase no esta configurado, `Astro.locals.auth` queda en estado `unconfigured`, con `user: null` y `supabase: null`, y la request continua. Cuando el cliente existe, la identidad se valida con `supabase.auth.getUser()`. Una sesion ausente se interpreta como `anonymous`; un usuario validado queda como `authenticated`; un error inesperado de `getUser` queda como `error`.

El middleware no usa `auth.getSession()` como autoridad, no llama `getClaims`, no consulta roles, no autoriza rutas y no dispara login, logout ni OAuth. Despues de `next()`, propaga a la respuesta final los `Set-Cookie` y headers de seguridad escritos por Supabase, incluyendo `Cache-Control` y `Pragma`.

Los `locals` expuestos son:

```ts
auth: {
  status: 'unconfigured' | 'anonymous' | 'authenticated' | 'error';
  user: { id: string; email: string | null } | null;
  supabase: SupabaseServerClient | null;
}
```

No se guardan tokens, sesiones completas, claves ni roles en `Astro.locals`.

## Seguridad

La publishable key puede llegar al navegador porque no otorga privilegios administrativos. La seguridad real depende de RLS, permisos de PostgreSQL y validacion del servidor. La llave `service_role` no se declara ni se usa en Astro.

PostgreSQL sigue siendo la autoridad de roles. Esta etapa no autoriza mediante metadata JWT, `localStorage`, cookies sin validar, usuarios ficticios ni roles enviados por el navegador.

Los errores de configuracion o autenticacion no imprimen URL, claves ni valores de entorno. Las rutas publicas no se bloquean mientras el proyecto no tenga flujos de autenticacion visibles.

## Consecuencias

- Todas las requests SSR tienen un contexto de autenticacion tipado y minimo.
- Un entorno Supabase ausente produce un estado explicito `unconfigured` sin romper build ni prerender.
- Cada request obtiene su propio cliente server y su propio contenedor de headers; no hay singleton de servidor.
- Las futuras etapas pueden leer `Astro.locals.auth`, pero deben seguir validando autorizacion en el servidor y en PostgreSQL.
- Cloudflare continua como adaptador; no se agrega `@astrojs/node` ni otro runtime.

## Alternativas Consideradas

- Usar `auth.getSession()` como autoridad: rechazado porque solo lee la sesion local y no valida el usuario contra Supabase.
- Poblar roles en `Astro.locals`: rechazado porque la autoridad de roles sigue en PostgreSQL y no hay decisiones de autorizacion en esta etapa.
- Crear un singleton server: rechazado porque mezclaria cookies y estado entre requests.
- Bloquear rutas publicas ante errores de Supabase: rechazado porque 3A.2B aun no define rutas privadas ni flujos de login.
