# FC Academic Hub — instrucciones para Codex

## Propósito

Construir una plataforma académica comunitaria para organizar cursos,
exámenes, apuntes, sílabos y recursos de la Facultad de Ciencias.

El sistema será administrado por estudiantes, pero debe poder atender
a toda la Facultad con seguridad, bajo costo y mantenimiento razonable.

## Arquitectura objetivo

- Astro con TypeScript estricto.
- Despliegue sobre Cloudflare Pages/Workers.
- Supabase Auth y PostgreSQL para identidad, roles y metadatos.
- Cloudflare R2 privado para archivos.
- Autorización validada siempre en el servidor.
- GitHub para código, documentación y revisión técnica.

Supabase y R2 se incorporarán en etapas posteriores.

## Restricciones de la etapa 1

- No conectar Supabase.
- No crear buckets R2.
- No implementar autenticación ficticia.
- No almacenar documentos reales.
- No introducir secretos.
- No usar datos personales.
- No desplegar sin solicitar autorización.

## Reglas de ingeniería

- TypeScript debe permanecer en modo estricto.
- Evitar `any`, salvo justificación documentada.
- Mantener componentes pequeños y accesibles.
- Separar dominio, presentación e infraestructura.
- No introducir dependencias sin justificar su necesidad.
- No desactivar validaciones para lograr que el build pase.
- Toda funcionalidad debe incluir pruebas razonables.
- Ejecutar formato, lint, pruebas y build antes de finalizar.
- Documentar decisiones arquitectónicas importantes como ADR.
- No modificar directamente la rama main.
- Mostrar un resumen del diff al terminar.

## Seguridad

- Nunca agregar claves, tokens o contraseñas al repositorio.
- Mantener `.env*` ignorados, excepto `.env.example`.
- No confiar en roles enviados por el navegador.
- No exponer futuras URLs permanentes de archivos privados.
- Validar entradas en el servidor.
- Aplicar principio de mínimo privilegio.

## Criterio de finalización

Una tarea solo está terminada cuando:

1. La aplicación compila.
2. Las pruebas pasan.
3. El chequeo de tipos pasa.
4. No existen secretos.
5. La documentación relevante está actualizada.
6. Codex informa archivos modificados y comandos ejecutados.