# Contrato de subida de recursos académicos

## Estado

Propuesto para la etapa 4B.2.

## Propósito

Este documento define las garantías observables del flujo de subida de archivos
académicos. No sustituye al ADR 0010 ni replica la implementación SQL.

La relación entre documentos es:

- `docs/adr/0010-resource-metadata-rbac.md` registra la decisión arquitectónica.
- este documento define invariantes, estados y responsabilidades;
- las migraciones PostgreSQL implementan el contrato;
- las pruebas pgTAP demuestran que el contrato se conserva.

Si existe una contradicción, la migración aplicada y sus pruebas son la fuente
ejecutable de verdad. Este documento debe corregirse dentro del mismo pull
request.

## Alcance inicial

La primera versión admite como máximo un archivo PDF privado por recurso
académico.

Un examen, una solución y un anexo deben representarse como recursos separados
hasta que exista un modelo explícito para múltiples archivos.

El flujo no crea URLs públicas, no habilita acceso directo a R2 y no aprueba ni
publica recursos automáticamente.

## Responsabilidades

### PostgreSQL

PostgreSQL:

- autentica al actor mediante `auth.uid()`;
- comprueba perfil activo, rol y propiedad;
- reserva metadatos de archivo y almacenamiento;
- controla las transiciones de estado;
- finaliza o aborta la reserva;
- registra eventos append-only;
- impide modificaciones directas de estados protegidos.

### Worker de Astro

El Worker:

- valida el archivo antes de almacenarlo;
- calcula SHA-256;
- escribe el objeto privado en R2;
- llama a las RPC PostgreSQL;
- elimina el objeto de R2 cuando debe compensar una finalización fallida;
- no usa `service_role`.

### Cloudflare R2

R2 almacena el objeto binario privado. No decide roles, propiedad, revisión ni
publicación.

PostgreSQL no puede comprobar directamente que un objeto exista en R2. El estado
`stored` significa que el Worker recibió confirmación de R2 antes de solicitar
la finalización.

## Estados involucrados

### Recurso académico

Para una subida nueva:

```text
draft o rejected
        |
        | finalize_resource_file_upload
        v
      pending
```

La finalización no puede producir `approved`.

### Objeto de almacenamiento

```text
uploading
   | \
   |  \ abort_resource_file_upload
   |   \
   v    v
stored  reserva eliminada
```

Una reserva histórica en `failed` también puede ser abortada.

## Invariantes

1. Solo un usuario autenticado con perfil activo y rol `contributor` o superior
   puede operar sobre un recurso propio editable.
2. Un recurso admite como máximo un archivo en esta etapa.
3. `storage_key` permanece exclusivamente en
   `private.resource_storage_objects`.
4. Los clientes no cambian directamente `review_status` ni `storage_status`.
5. La finalización cambia archivo, storage, recurso y auditoría dentro de una
   sola transacción PostgreSQL.
6. Si la finalización falla, PostgreSQL no puede quedar parcialmente actualizado.
7. El aborto elimina los metadatos de archivo y storage, pero conserva el recurso
   académico editable.
8. Los eventos de revisión y almacenamiento son append-only.
9. Finalizar una segunda vez con el mismo hash puede ser idempotente.
10. Finalizar con un hash diferente al ya confirmado debe fallar.
11. Las operaciones concurrentes usan el orden de bloqueo:
    recurso, archivo y objeto de almacenamiento.
12. Ninguna operación de subida aprueba o publica el recurso.

## Reserva

La RPC existente:

```text
register_resource_file_upload
```

crea conjuntamente:

- `public.resource_files`;
- `private.resource_storage_objects` en estado `uploading`.

La implementación 4B.2 debe bloquear primero el recurso y volver a comprobar que
continúa editable antes de insertar la reserva.

Una restricción única en `resource_files.resource_id` evita dos reservas
simultáneas para el mismo recurso.

## Finalización atómica

La RPC:

```text
finalize_resource_file_upload(
  file_id uuid,
  sha256 text,
  comment text default null
)
```

debe:

1. bloquear recurso, archivo y storage;
2. comprobar identidad, rol, propiedad, derechos y estados;
3. validar SHA-256;
4. guardar el hash confirmado;
5. cambiar storage de `uploading` a `stored`;
6. establecer `stored_at`;
7. cambiar el recurso de `draft` o `rejected` a `pending`;
8. establecer `submitted_at` y limpiar revisión previa;
9. registrar `storage_stored`;
10. registrar `submit`;
11. confirmar todo en una sola transacción.

Una repetición es idempotente solamente cuando:

- storage ya está `stored`;
- el recurso está `pending`;
- el hash coincide.

No debe repetir eventos ni timestamps.

## Aborto

La RPC:

```text
abort_resource_file_upload(
  file_id uuid,
  reason text default null
)
```

debe:

1. bloquear recurso, archivo y storage;
2. comprobar identidad, rol, propiedad y estado editable;
3. aceptar storage `uploading` o `failed`;
4. registrar `storage_aborted`;
5. eliminar `resource_files`;
6. eliminar el storage asociado mediante cascada;
7. conservar el recurso en su estado editable.

Un archivo `stored` no puede abortarse mediante esta RPC.

## RPC heredadas

Las funciones siguientes pueden conservarse temporalmente para compatibilidad de
esquema, pero dejan de ser ejecutables por `authenticated`:

```text
mark_resource_file_stored
mark_resource_file_failed
```

`submit_academic_resource` permanece disponible para recursos sin archivo,
referencias bibliográficas y reenvíos explícitos.

## Compensación entre PostgreSQL y R2

PostgreSQL y R2 no comparten una transacción distribuida.

| Fallo                                         | Compensación                                   |
| --------------------------------------------- | ---------------------------------------------- |
| La reserva PostgreSQL falla                   | No escribir en R2                              |
| R2 rechaza la escritura                       | Abortar la reserva PostgreSQL                  |
| R2 escribe y la finalización PostgreSQL falla | Eliminar el objeto R2 y abortar la reserva     |
| La eliminación compensatoria de R2 falla      | Registrar el incidente para limpieza posterior |

La etapa 4B no implementa todavía una tarea automática de limpieza.

## Seguridad

- No usar `service_role` en Astro.
- No devolver `storage_key` al navegador.
- No aceptar un `storage_key` proporcionado libremente por el cliente final.
- No crear URLs firmadas ni públicas en esta etapa.
- Las funciones `SECURITY DEFINER` deben usar `SET search_path = ''` y nombres
  completamente calificados.
- Los permisos deben concederse por firma exacta de función.
- Los errores no deben revelar claves privadas ni datos de otros propietarios.

## Fuera de alcance

Quedan fuera de 4B.2:

- activación de la suscripción R2;
- creación del bucket remoto;
- interfaz de subida;
- descarga de archivos;
- revisión y aprobación visual;
- múltiples archivos por recurso;
- limpieza programada de reservas vencidas;
- eliminación de objetos ya almacenados;
- URLs públicas o directas.

## Verificación mínima

Las pruebas pgTAP deben cubrir:

- existencia y privilegios de las nuevas RPC;
- revocación de las RPC heredadas;
- un archivo máximo por recurso;
- finalización válida;
- atomicidad ante error;
- idempotencia con el mismo hash;
- rechazo de hash conflictivo;
- rechazo de usuario sin rol;
- rechazo de propietario incorrecto;
- rechazo de estado inválido;
- aborto de `uploading`;
- aborto de `failed`;
- rechazo de aborto para `stored`;
- conservación del recurso después del aborto;
- auditoría append-only;
- ausencia de acceso directo a `storage_key`.
