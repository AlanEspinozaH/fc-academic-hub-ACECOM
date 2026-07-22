# Registro de riesgos de dependencias

## DR-001: sharp transitive via Miniflare

Fecha: 2026-07-22

Estado: aceptado temporalmente para desarrollo local.

Dependencia vulnerable reportada: `sharp@0.34.5`.

Severidad reportada: `high` por `npm audit --omit=dev`, asociada a vulnerabilidades heredadas de libvips en `sharp <0.35.0`.

Arbol reportado:

```text
@astrojs/cloudflare@14.1.4
└─ @cloudflare/vite-plugin@1.45.1
   ├─ wrangler@4.112.0
   │  └─ miniflare@4.20260714.0
   │     └─ sharp@0.34.5
   └─ miniflare@4.20260714.0
      └─ sharp@0.34.5
```

Tooling afectado: adaptador Cloudflare, plugin Vite de Cloudflare, Wrangler y Miniflare usados para build, preview y tooling local. No pertenece al dominio academico ni a la matriz de permisos.

Exposicion runtime: no demostrada. `npm run build` aprobo y la inspeccion de `dist` con `rg -n "miniflare|sharp" dist` no encontro coincidencias. Tras migrar el proyecto SSR a Cloudflare Workers, `wrangler deploy --dry-run --outdir` es una validacion aplicable del bundle y de la configuracion sin desplegar ni modificar recursos remotos.

Correccion disponible: no existe actualmente una actualizacion normal compatible que elimine `sharp@0.34.5`. `wrangler@4.113.0` depende de `miniflare@4.20260721.0`, y `miniflare@4.20260721.0` todavia declara `sharp@0.34.5`.

Restricciones de mitigacion: no usar `overrides`, no ejecutar `npm audit fix` ni `npm audit fix --force`. El fix sugerido por npm implicaria un downgrade incompatible de Wrangler o del adaptador.

Revision obligatoria: reevaluar este registro al actualizar `@astrojs/cloudflare`, `@cloudflare/vite-plugin`, `wrangler` o `miniflare`. La revision debe ejecutar `npm audit --omit=dev`, `npm explain sharp`, `npm explain miniflare`, `npm explain wrangler`, `npm run ci` e inspeccion de `dist`.
