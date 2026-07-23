# Contrato de subida de recursos académicos

## Estado

Contrato de base de datos implementado en la etapa 4B.2, refinado para la
orquestación Worker en la etapa 4B.6 y expuesto mediante un endpoint server-side
en la etapa 4B.7.

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
académico. El archivo no puede superar 10 000 000 bytes. Este límite corresponde a 10 MB decimales, no a 10 MiB.

Un examen, una solución y un anexo deben representarse como recursos separados
hasta que exista un modelo explícito para múltiples archivos.

El flujo no crea URLs públicas, no habilita acceso directo a R2 y no aprueba ni
publica recursos automáticamente.

## Endpoint HTTP de subida

La etapa 4B.7 expone únicamente del lado servidor:

```text
POST /api/resources/:resourceId/files
```

La petición usa `multipart/form-data` con:

- `file`: archivo PDF obligatorio;
- `comment`: texto opcional.

El endpoint:

1. rechaza solicitudes cross-origin antes de iniciar la subida;
2. exige una sesión autenticada;
3. valida el UUID del recurso;
4. exige exactamente el media type `multipart/form-data`;
5. limita el body HTTP antes de parsear completamente el multipart;
6. delega la validación del PDF y la orquestación de PostgreSQL/R2 al flujo
   server-side existente;
7. devuelve únicamente el `fileId` después de una finalización confirmada.

El archivo PDF mantiene el límite de 10 000 000 bytes. El body multipart tiene
un margen adicional de 65 536 bytes para boundaries, headers y campos de
formulario.

El endpoint no devuelve `storage_key`, no crea URLs públicas o firmadas y no
expone acceso directo a R2.

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
- distingue un fallo confirmado de un resultado de transporte desconocido;
- reintenta una vez la finalización cuando el resultado de transporte es
  desconocido, usando el mismo `file_id` y SHA-256;
- realiza compensación destructiva únicamente cuando la finalización PostgreSQL
  falló de forma conocida;
- conserva R2 y los metadatos PostgreSQL cuando el resultado de la finalización
  sigue siendo desconocido;
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
13. Un error de transporte no implica que la operación remota no haya sido
    confirmada; el Worker distingue fallos conocidos de resultados desconocidos.
14. Si el resultado de `finalize_resource_file_upload` permanece desconocido,
    el Worker no elimina el objeto R2 ni aborta la reserva PostgreSQL.
15. El reintento automático de finalización reutiliza exactamente el mismo
    `file_id` y SHA-256 y depende de la idempotencia definida por este contrato.

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

## RPC de almacenamiento

`mark_resource_file_stored` se conserva temporalmente por compatibilidad de
esquema, pero no es ejecutable por `authenticated`. La confirmación de un objeto
almacenado debe realizarse exclusivamente mediante
`finalize_resource_file_upload`, porque esa RPC actualiza atómicamente archivo,
storage, recurso y auditoría.

`mark_resource_file_failed` permanece ejecutable por `authenticated` para la
compensación server-side. El Worker la utiliza únicamente cuando el objeto fue
escrito en R2, la finalización PostgreSQL falló y la eliminación compensatoria
del objeto también falló.

Esta RPC conserva el archivo y el registro privado de almacenamiento, cambia
`uploading` a `failed`, registra `failure_reason` y emite `storage_failed`. Esto
preserva la referencia privada necesaria para una limpieza posterior.

`submit_academic_resource` permanece disponible para recursos sin archivo,
referencias bibliográficas y reenvíos explícitos.

## Compensación entre PostgreSQL y R2

PostgreSQL y R2 no comparten una transacción distribuida.

| Situación                                                                    | Acción del Worker                                                                         |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| La reserva PostgreSQL devuelve un fallo conocido                             | No escribir en R2                                                                         |
| La reserva PostgreSQL termina con resultado desconocido                      | No escribir en R2 ni intentar una compensación sin `file_id` confirmado                   |
| La escritura R2 falla o su resultado es desconocido                          | Intentar eliminar defensivamente la clave R2                                              |
| La eliminación defensiva R2 funciona                                         | Abortar la reserva PostgreSQL                                                             |
| La eliminación defensiva R2 también falla                                    | Conservar la reserva PostgreSQL y reportar fallo de compensación                          |
| La finalización PostgreSQL devuelve un fallo conocido                        | Intentar eliminar el objeto R2                                                            |
| La eliminación R2 funciona después de un fallo conocido de finalización      | Abortar la reserva PostgreSQL                                                             |
| La eliminación R2 también falla después de un fallo conocido de finalización | Marcar el storage como `failed` y conservar sus metadatos privados                        |
| La primera finalización termina con resultado desconocido                    | Reintentar una vez con el mismo `file_id` y SHA-256                                       |
| El reintento confirma la finalización                                        | Considerar la subida finalizada                                                           |
| El resultado de la finalización sigue siendo desconocido                     | No eliminar R2, no abortar PostgreSQL y preservar el estado para reconciliación posterior |

La etapa 4B no implementa todavía una tarea automática de limpieza ni de
reconciliación. Los resultados desconocidos se preservan deliberadamente para
evitar una compensación destructiva sobre una operación que podría haberse
confirmado remotamente.

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

Quedan fuera del alcance actual de la etapa 4B:

- activación de la suscripción R2;
- creación del bucket remoto;
- interfaz visual de subida;
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

Las pruebas unitarias de la orquestación Worker deben cubrir además:

- reserva con fallo conocido;
- reserva con resultado desconocido;
- fallo o resultado desconocido de escritura R2 y eliminación defensiva;
- finalización con fallo conocido;
- reintento idempotente después de un resultado de transporte desconocido;
- finalización con resultado todavía desconocido sin compensación destructiva;
- fallo de eliminación compensatoria;
- uso de `mark_resource_file_failed` únicamente después de un fallo conocido de
  finalización y un fallo de eliminación R2.

Las pruebas de la capa HTTP deben cubrir además:

- sesión no autenticada;
- origen cross-site;
- UUID de recurso inválido;
- media type incorrecto;
- multipart malformado;
- body multipart por encima del límite;
- ausencia del campo `file`;
- comentario no textual;
- errores seguros de validación del PDF;
- fallos deterministas y resultados desconocidos del orquestador;
- ausencia de detalles internos en errores inesperados.

El smoke test local debe comprobar como mínimo:

- `GET` al endpoint devuelve `405` con `Allow: POST`;
- `POST` same-origin sin sesión devuelve `401`;
- una petición cross-origin es rechazada;
- el endpoint carga correctamente bajo el runtime local de Cloudflare.
