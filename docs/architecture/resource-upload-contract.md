# Contrato de subida de recursos académicos

## Estado

Baseline implementado:

- Stage 4B.2 — contrato PostgreSQL de subida;
- Stage 4B.6 — orquestación Worker;
- Stage 4B.7 — endpoint HTTP server-side.

Evolución hacia `ResourceFile` genérico:

**Implementada en aplicación, dominio y HTTP por Stage 4C.2.**

Stage 4C.4 habilita operacionalmente la allowlist v1 completa: PDF, PNG, JPEG, Markdown, TeX, TXT y las extensiones source expresamente permitidas.

---

## Propósito

Este documento define las garantías observables del flujo de subida de archivos académicos.

Su responsabilidad principal es definir:

- quién puede iniciar una subida;
- cómo se reserva el archivo;
- cómo se coordina PostgreSQL con R2;
- cómo se finaliza una subida;
- cómo se compensan fallos;
- qué ocurre ante resultados de transporte desconocidos;
- qué información permanece privada;
- qué invariantes deben conservarse al generalizar de PDF a `ResourceFile`.

Este documento **no** define:

- qué usuarios pueden leer posteriormente un archivo;
- qué formatos exactos se aceptan;
- cómo debe mostrarse un archivo;
- la audiencia final de publicación.

Esas responsabilidades viven respectivamente en:

```text
docs/architecture/resource-access-contract.md
docs/architecture/resource-file-policy.md
docs/product/v1-product-contract.md
```

---

# 1. Relación entre documentos

Las fuentes normativas se dividen así.

## Decisiones arquitectónicas

```text
docs/adr/0010-resource-metadata-rbac.md
```

documenta el baseline introducido en 4A.

El ADR:

```text

docs/adr/0011-resource-files-access-and-external-identities.md

```

documenta las decisiones arquitectónicas de Stage 4C relativas a:

- `ResourceFile` genérico;
- nuevas audiencias;
- entitlements;
- identidades externas autorizadas;
- storage keys genéricas.

---

## Política de archivos

```text
docs/architecture/resource-file-policy.md
```

define:

- allowlist;
- `file_kind`;
- extensiones;
- límites;
- validación;
- MIME canónico;
- preview;
- hashing;
- layouts de storage.

---

## Política de acceso

```text
docs/architecture/resource-access-contract.md
```

define:

- identidad;
- roles;
- entitlements;
- `review_status`;
- `visibility`;
- `rights_status`;
- acceso a preview y download.

---

## Este contrato

Este documento define exclusivamente el **flujo transaccional de upload** y la coordinación:

```text
PostgreSQL
↕
Astro Worker
↕
Cloudflare R2
```

---

# 2. Fuente ejecutable y objetivo normativo

Para comportamiento ya implementado:

> las migraciones PostgreSQL aplicadas, las pruebas pgTAP y las pruebas TypeScript son la fuente ejecutable de verdad.

Para cambios de Stage 4C todavía no implementados:

> los contratos aceptados de Stage 4C representan el objetivo normativo.

La convergencia se realiza por etapas y únicamente sobre los artefactos que correspondan al alcance de cada una.

Stage:

```text
4C.0A
```

es exclusivamente documental.

Durante `4C.0A` no deben modificarse para implementar comportamiento nuevo:

```text
src/
supabase/migrations/
supabase/tests/
schema PostgreSQL
RLS
RPC
Cloudflare R2 layout operativo
```

Stage:

```text
4C.0B
```

inicia la realineación ejecutable de schema, autorización y almacenamiento necesaria para satisfacer los contratos aceptados.

A partir de `4C.0B`, cada cambio de comportamiento debe mantener alineados, según corresponda:

```text
código
migraciones
RLS
RPC
tests
documentación
```

La documentación puede describir comportamiento objetivo todavía no implementado únicamente cuando lo identifique explícitamente como pendiente.

No debe presentarse una capacidad de Stage 4C como implementada antes de que su etapa correspondiente haya sido completada y verificada.

---

# 3. Baseline 4B preservado

El pipeline genérico preserva el límite v1 de:

```text
máximo un archivo principal por recurso
```

Stage 4C.3 habilita PDF, PNG y JPEG, manteniendo para estas familias:

```text
maximum byte size = 10 000 000
```

y utiliza objetos R2 privados.

El baseline 4B:

- valida PDF;
- calcula SHA-256;
- reserva metadata PostgreSQL;
- escribe R2;
- finaliza PostgreSQL;
- compensa fallos conocidos;
- preserva resultados desconocidos;
- no devuelve `storage_key`;
- no publica automáticamente el recurso.

Este comportamiento debe mantenerse hasta que Stage 4C generalice expresamente el upload.

---

# 4. Objetivo Stage 4C

Stage 4C generaliza:

```text
ResourcePdf
```

hacia:

```text
ResourceFile
```

sin reescribir las garantías transaccionales de 4B.

El flujo objetivo admite únicamente formatos definidos en:

```text
docs/architecture/resource-file-policy.md
```

y continúa admitiendo:

```text
máximo un archivo principal por recurso
```

en v1.

---

# 5. Principio de preservación de 4B

La generalización de formatos no debe eliminar ni debilitar:

- reserva PostgreSQL previa;
- storage privado;
- SHA-256;
- atomicidad PostgreSQL;
- idempotencia de finalización;
- compensación;
- tratamiento de resultados desconocidos;
- auditoría;
- un archivo por recurso;
- no exposición de `storage_key`;
- ausencia de `service_role`.

Stage 4C debe evolucionar el contrato de archivo, no reconstruir innecesariamente el pipeline.

---

# 6. Endpoint HTTP

El endpoint de subida permanece:

```text
POST /api/resources/:resourceId/files
```

El path ya es genérico y no necesita cambiar al incorporar nuevos formatos.

---

# 7. Estado actual del endpoint

El contrato del handler y del orquestador es `ResourceFile` genérico. Stage 4C.4 registra operacionalmente la allowlist v1 completa en el mismo endpoint y PostgreSQL impone su matriz canónica cerrada y los límites por familia.

---

# 8. Request multipart objetivo

La petición utiliza:

```text
multipart/form-data
```

con:

```text
file
```

como archivo principal obligatorio.

Puede conservar:

```text
comment
```

como campo textual opcional cuando corresponda al workflow existente.

El cliente no proporciona de forma autoritativa:

- `file_kind`;
- `normalized_extension`;
- MIME canónico;
- SHA-256;
- `storage_key`;
- `storage_key_version`;
- `uploaded_by`;
- estado de storage.

Estos valores son determinados por componentes confiables del sistema.

---

# 9. Precondiciones HTTP

Antes de iniciar una subida, el endpoint debe:

1. rechazar requests cross-origin no permitidas;
2. exigir una sesión autenticada;
3. validar `resourceId`;
4. exigir el media type HTTP esperado;
5. limitar el body antes de procesarlo completamente;
6. rechazar multipart malformado;
7. exigir exactamente el archivo requerido;
8. validar campos auxiliares antes de iniciar operaciones persistentes.

---

# 10. Autorización para subir

Subir un archivo requiere como mínimo:

```text
authenticated
+
account_status = active
+
Contributor o capacidad equivalente
+
ownership del recurso editable
```

El entitlement:

```text
privileged_material.read
```

no concede capacidad de upload.

Una identidad:

```text
external_authorized
```

no puede subir archivos en v1.

Las identidades externas son exclusivamente lectoras y no pueden recibir el rol `contributor` ni otra capacidad editorial interna.

Si una persona externa necesita aportar material, debe coordinar su entrega fuera de la plataforma con un Contributor institucional, quien realiza la creación y subida del recurso.

---

# 11. Estados editables

Una nueva subida solo puede realizarse sobre un recurso propio que se encuentre en un estado editable compatible con el workflow.

El baseline v1 utiliza:

```text
draft
rejected
```

como estados desde los que puede iniciarse o corregirse una contribución.

Una subida no puede utilizarse para modificar directamente un recurso:

```text
approved
```

ni para saltarse el workflow de revisión.

---

# 12. Derechos antes del almacenamiento

Un archivo no debe almacenarse definitivamente mientras el recurso carezca de una base de derechos que permita conservar ese archivo.

En v1, los estados que pueden permitir archivo almacenado son:

```text
own-work
authorized
institutional
open-license
public-domain
```

según sus respectivas condiciones.

No permiten almacenar el archivo principal:

```text
pending
bibliographic-reference-only
copyright-restricted
```

---

## `pending`

`rights_status = pending` significa que la base de derechos todavía no ha sido establecida.

El recurso puede existir como metadata dentro del workflow, pero no debe completar una subida binaria almacenada hasta disponer de un estado de derechos compatible.

---

## `bibliographic-reference-only`

Permite representar metadata o una referencia bibliográfica.

No permite almacenar el archivo principal.

---

## `copyright-restricted`

No permite almacenar el archivo principal bajo la política v1.

---

# 13. `authorized`

`authorized` permite almacenar el archivo cuando existe una autorización explícita documentada.

Esto no significa automáticamente que posteriormente pueda publicarse como:

```text
public
```

El alcance final de publicación se revisa durante moderación según:

```text
resource-access-contract.md
```

Upload y publication son decisiones diferentes.

---

# 14. Validación del archivo

El Worker valida el archivo antes de escribirlo en R2.

La validación debe cumplir:

```text
docs/architecture/resource-file-policy.md
```

La operación conceptual es:

```text
validateResourceFile(...)
```

que puede delegar en validadores especializados.

Ejemplo:

```text
ResourceFile dispatcher
        │
        ├── PDF validator
        ├── PNG validator
        ├── JPEG validator
        └── UTF-8 text validator
```

La implementación especializada existente para PDF debe conservarse siempre que siga cumpliendo el nuevo contrato.

---

# 15. Metadata canónica

Después de validar un archivo, el servidor dispone conceptualmente de metadata confiable:

```text
display_filename
file_kind
normalized_extension
content_type
byte_size
sha256
```

Estos valores no deben aceptarse como autoridad simplemente porque los proporcione el navegador.

---

# 16. MIME del cliente

El MIME declarado por el cliente es información no confiable.

Puede utilizarse como señal diagnóstica cuando sea útil, pero no debe determinar la clasificación final.

Por ejemplo:

```text
dijkstra.py
client MIME = application/octet-stream
```

puede ser aceptado si satisface la política de source code.

El servidor almacena posteriormente:

```text
file_kind = source
content_type = text/plain
```

---

# 17. SHA-256

SHA-256 debe calcularse sobre:

```text
los bytes exactos que serán escritos en R2
```

La aplicación no debe:

- normalizar line endings antes de hash;
- eliminar BOM antes de hash;
- transformar el archivo antes de hash.

Conceptualmente:

```text
uploaded bytes
=
validated bytes
=
hashed bytes
=
stored bytes
```

---

# 18. Límite HTTP

El archivo individual más grande admitido en v1 es:

```text
10 000 000 bytes
```

para:

- PDF;
- PNG;
- JPEG.

Por ello, el endpoint puede conservar un límite HTTP global basado en:

```text
10 000 000 bytes
+
multipart overhead acotado
```

El baseline actual utiliza:

```text
65 536 bytes
```

de margen multipart.

Stage 4C puede conservar este margen mientras siga siendo suficiente y esté cubierto por pruebas.

---

# 19. Límites por familia

El límite HTTP global no determina la validez final del archivo.

Después del parsing, se aplican los límites específicos definidos en la política de archivos.

Actualmente aceptados:

```text
PDF        10 000 000
PNG        10 000 000
JPEG       10 000 000
text-like   2 000 000
```

Por tanto:

```text
source.py = 8 000 000 bytes
```

puede encontrarse por debajo del máximo HTTP global y aun así debe ser rechazado.

---

# 20. Responsabilidades PostgreSQL

PostgreSQL es responsable de:

- identificar al actor mediante `auth.uid()`;
- comprobar account status;
- comprobar roles/capacidades;
- comprobar ownership;
- comprobar estado editable;
- comprobar derechos requeridos;
- reservar metadata;
- reservar estado de almacenamiento;
- controlar transiciones;
- finalizar;
- abortar;
- registrar eventos;
- mantener invariantes;
- proteger metadata privada.

PostgreSQL no valida magic bytes ni UTF-8 del archivo.

Esas validaciones pertenecen al Worker antes de escribir R2.

---

# 21. Responsabilidades del Worker

El Worker:

1. valida HTTP;
2. obtiene el archivo;
3. valida formato y contenido;
4. calcula SHA-256;
5. solicita reserva PostgreSQL;
6. deriva la clave R2 correspondiente;
7. escribe el objeto privado;
8. solicita finalización PostgreSQL;
9. compensa únicamente cuando el resultado es suficientemente conocido;
10. preserva estados ambiguos cuando la operación remota puede haberse completado.

El Worker no utiliza:

```text
service_role
```

para ejecutar este flujo.

---

# 22. Responsabilidades de R2

Cloudflare R2:

- almacena bytes;
- devuelve éxito/fallo de operaciones de object storage.

R2 no determina:

- identidad;
- roles;
- ownership;
- `review_status`;
- `visibility`;
- derechos;
- audiencia.

R2 permanece privado.

---

# 23. Estados del recurso durante upload

Para una subida nueva:

```text
draft o rejected
        │
        │ finalize_resource_file_upload
        ▼
      pending
```

La finalización de upload:

```text
NO
```

puede producir directamente:

```text
approved
```

La publicación es un proceso editorial posterior.

---

# 24. Estado del objeto

El flujo principal de storage conserva:

```text
uploading
   │
   ├── successful finalization
   │        ↓
   │      stored
   │
   └── abort
            ↓
      reservation removed
```

Los estados adicionales necesarios para fallos y reconciliación deben conservar la semántica ya introducida por 4B.

---

# 25. Invariantes principales

1. Solo un actor autorizado puede subir a un recurso propio editable.
2. Un recurso admite como máximo un archivo principal.
3. El archivo debe cumplir la allowlist antes de R2.
4. Los derechos deben permitir almacenamiento.
5. `storage_key` permanece privado.
6. El navegador no decide metadata canónica.
7. El cliente no modifica directamente estados protegidos.
8. PostgreSQL finaliza metadata, storage, resource y auditoría atómicamente.
9. Una finalización fallida no puede dejar una transacción PostgreSQL parcialmente aplicada.
10. Los eventos de auditoría relevantes son append-only.
11. La segunda finalización con el mismo identificador/hash puede ser idempotente.
12. Un hash distinto del ya confirmado debe producir fallo.
13. Las operaciones concurrentes deben mantener un orden de locking estable.
14. Upload nunca aprueba ni publica.
15. Un timeout no demuestra que la operación remota haya fallado.
16. Una operación ambigua no debe provocar compensación destructiva automáticamente.
17. Un nuevo objeto posterior a la migración de layout usa `generic_v2`.
18. Los objetos legacy continúan siendo compatibles.

---

# 26. Reserva

La operación de reserva crea de manera coordinada metadata equivalente a:

```text
public.resource_files
```

y:

```text
private.resource_storage_objects
```

en estado:

```text
uploading
```

La reserva debe bloquear primero el recurso y volver a comprobar:

- ownership;
- estado editable;
- permisos;
- ausencia de un archivo ya reservado;
- derechos compatibles.

---

# 27. Un archivo por recurso

La restricción:

```text
one resource -> at most one resource_file
```

debe mantenerse en v1.

Debe existir una garantía PostgreSQL que impida dos reservas concurrentes válidas para un mismo recurso.

No basta con comprobarlo únicamente en TypeScript.

---

# 28. Metadata objetivo de reserva

Stage 4C debe permitir persistir de manera canónica información equivalente a:

```text
resource_id
uploaded_by
display_filename
file_kind
normalized_extension
content_type
byte_size
sha256
storage_key_version
```

El diseño SQL exacto puede adaptarse durante implementación, pero la información crítica de formato no debe depender exclusivamente de volver a analizar `display_filename`.

---

# 29. `storage_key_version`

Stage 4C introduce conceptualmente:

```text
legacy_pdf_v1
generic_v2
```

Una vez implementada la migración correspondiente de Stage 4C, los nuevos uploads utilizan:

```text
generic_v2
```

Antes de esa migración, el pipeline operativo debe preservar el comportamiento 4B existente.

La versión/layout debe quedar determinada por el servidor o PostgreSQL.

Nunca por input arbitrario del usuario.

---

# 30. Storage key legacy

Los objetos anteriores pueden usar:

```text
resources/<resource_id>/<file_id>.pdf
```

y no deben renombrarse únicamente por la generalización.

Se consideran:

```text
legacy_pdf_v1
```

---

# 31. Storage key genérica

Después de implementarse la migración `generic_v2`, los nuevos archivos utilizan:

```text
resources/<resource_id>/<file_id>
```

sin extensión.

Esto incluye los nuevos PDFs creados después de dicha migración.

Antes de esa migración debe preservarse el layout operativo 4B existente.

Por tanto:

```text
nuevo PDF
```

no necesita una key terminada en:

```text
.pdf
```

La información de formato vive en metadata canónica.

---

# 32. `storage_key` privado

La clave concreta continúa almacenada como información privada de infraestructura.

No debe:

- devolverse en la respuesta HTTP;
- exponerse en una API pública;
- convertirse en identificador de dominio;
- aceptarse desde el navegador;
- utilizarse para autorización.

---

# 33. Resultado de reserva

La operación de reserva debe devolver al Worker únicamente la información estrictamente necesaria para continuar el flujo.

El contrato público del endpoint termina devolviendo:

```text
fileId
```

después de una finalización confirmada.

No debe devolver:

```text
storage_key
```

al navegador.

---

# 34. Derivación de key

Para objetos nuevos, el Worker puede derivar la key determinísticamente mediante:

```text
resource_id
file_id
storage_key_version
```

siguiendo:

```text
resource-file-policy.md
```

Esto evita necesitar revelar la clave privada al cliente.

---

# 35. Escritura R2

La escritura utiliza únicamente:

- storage key derivada internamente;
- bytes ya validados;
- content type canónico.

No debe usar como autoridad:

```text
raw client MIME
```

para `httpMetadata`.

---

# 36. Finalización atómica

La operación equivalente a:

```text
finalize_resource_file_upload(
  file_id,
  sha256,
  comment
)
```

debe continuar siendo atómica en PostgreSQL.

Conceptualmente debe:

1. bloquear resource;
2. bloquear file;
3. bloquear storage;
4. comprobar actor;
5. comprobar ownership;
6. comprobar estados;
7. comprobar derechos;
8. verificar SHA-256;
9. persistir hash confirmado;
10. cambiar storage a `stored`;
11. establecer timestamps;
12. mover el recurso a `pending`;
13. registrar eventos;
14. confirmar todo en una única transacción.

La firma SQL exacta puede evolucionar si Stage 4C necesita metadata adicional.

Las garantías no deben debilitarse.

---

# 37. Idempotencia

Una repetición de finalización puede considerarse idempotente únicamente cuando:

- se refiere al mismo `file_id`;
- storage ya está confirmado;
- resource se encuentra en el estado esperado;
- SHA-256 coincide.

No debe:

- duplicar eventos;
- cambiar timestamps innecesariamente;
- aceptar un hash diferente.

---

# 38. Aborto

La operación de aborto debe conservar la semántica existente.

Conceptualmente:

```text
abort_resource_file_upload(
  file_id,
  reason
)
```

puede eliminar una reserva no finalizada cuando:

- el actor conserva autorización;
- el recurso sigue siendo editable;
- el storage se encuentra en un estado abortable.

El aborto:

- elimina metadata de la reserva;
- elimina el registro de storage mediante la relación correspondiente;
- conserva el recurso académico.

Un archivo ya:

```text
stored
```

no se elimina mediante esta operación ordinaria de aborto.

---

# 39. PostgreSQL y R2 no comparten transacción

No existe una transacción distribuida ACID que abarque simultáneamente:

```text
PostgreSQL
+
Cloudflare R2
```

Por ello el Worker implementa una saga pequeña de coordinación y compensación.

Este principio continúa siendo válido independientemente del formato del archivo.

---

# 40. Fallo conocido vs resultado desconocido

El sistema debe distinguir:

```text
known failure
```

de:

```text
unknown outcome
```

Un error de transporte como:

- timeout;
- conexión interrumpida;
- respuesta perdida;

no demuestra necesariamente que la operación remota no haya ocurrido.

---

# 41. Reserva PostgreSQL

## Fallo conocido

Si la reserva devuelve un fallo confirmado:

```text
no escribir R2
```

---

## Resultado desconocido

Si la reserva no confirma si ocurrió:

```text
no escribir R2
```

cuando no existe un `file_id` confirmado con el que continuar de forma segura.

No debe intentarse compensación destructiva sobre una operación cuya existencia no puede identificarse.

---

# 42. Escritura R2

Si R2 devuelve fallo conocido o resultado desconocido durante escritura:

```text
attempt defensive delete
```

sobre la key derivada.

La finalidad es evitar conservar un objeto que PostgreSQL todavía considera `uploading`.

---

# 43. Eliminación defensiva exitosa

Si la eliminación R2 se confirma:

```text
abort PostgreSQL reservation
```

---

# 44. Eliminación defensiva fallida

Si no puede eliminarse el objeto:

```text
preserve metadata
report compensation failure
```

No debe perderse la única referencia que permita reconciliar posteriormente el objeto.

---

# 45. Fallo conocido de finalización PostgreSQL

Si R2 confirmó escritura pero PostgreSQL confirma que la finalización falló:

```text
attempt R2 delete
```

---

# 46. Delete R2 exitoso después de fallo de finalización

Entonces:

```text
abort PostgreSQL reservation
```

---

# 47. Delete R2 fallido después de fallo de finalización

Debe conservarse suficiente metadata para reconciliación y marcarse el fallo de storage según el contrato existente.

No debe ocultarse que puede existir un objeto huérfano.

---

# 48. Resultado desconocido de finalización

Si la primera llamada de finalización tiene outcome desconocido:

```text
retry once
```

utilizando exactamente:

```text
same file_id
same SHA-256
```

---

# 49. Reintento confirmado

Si el reintento confirma la finalización:

```text
upload successful
```

---

# 50. Reintento también desconocido

Si continúa sin conocerse el resultado:

```text
DO NOT delete R2
DO NOT abort PostgreSQL
```

La operación se conserva para reconciliación posterior.

Esta regla es crítica.

Una compensación destructiva podría borrar un objeto correspondiente a una finalización PostgreSQL que sí se ejecutó pero cuya respuesta se perdió.

---

# 51. Matriz de compensación

| Situación                                                               | Acción                                                   |
| ----------------------------------------------------------------------- | -------------------------------------------------------- |
| Reserva PostgreSQL falla de forma conocida                              | No escribir R2                                           |
| Reserva PostgreSQL tiene resultado desconocido sin `file_id` confirmado | No escribir R2                                           |
| Escritura R2 falla o queda desconocida                                  | Intentar delete defensivo                                |
| Delete defensivo R2 confirma éxito                                      | Abortar reserva PostgreSQL                               |
| Delete defensivo R2 falla                                               | Preservar reserva y reportar fallo                       |
| Finalización PostgreSQL falla de forma conocida                         | Intentar delete R2                                       |
| Delete R2 confirma éxito                                                | Abortar reserva PostgreSQL                               |
| Delete R2 falla                                                         | Preservar metadata y marcar fallo                        |
| Primera finalización queda desconocida                                  | Reintentar una vez con mismo id/hash                     |
| Reintento confirma finalización                                         | Éxito                                                    |
| Reintento permanece desconocido                                         | Preservar R2 y PostgreSQL; no compensar destructivamente |

---

# 52. `mark_resource_file_stored`

La confirmación ordinaria de una subida no debe dividirse en varias operaciones públicas que permitan estados parciales.

La finalización atómica sigue siendo la vía autoritativa.

Si una RPC histórica como:

```text
mark_resource_file_stored
```

permanece por compatibilidad, no debe convertirse nuevamente en el camino ordinario para usuarios authenticated.

---

# 53. `mark_resource_file_failed`

Una operación equivalente puede mantenerse para registrar un fallo de compensación que requiera reconciliación posterior.

Debe utilizarse únicamente bajo condiciones claramente definidas.

No debe ser una vía para que un cliente final marque arbitrariamente archivos ajenos como fallidos.

Las comprobaciones internas de actor, ownership y estado siguen siendo obligatorias aunque exista `EXECUTE` para un rol PostgreSQL amplio como `authenticated`.

---

# 54. `submit_academic_resource`

Puede continuar existiendo para recursos sin archivo cuando el producto lo permita.

Ejemplos:

```text
bibliographic-reference-only
```

o workflows explícitos que no necesiten binario.

No debe utilizarse para saltarse las validaciones requeridas cuando sí existe un archivo.

---

# 55. Respuesta HTTP exitosa

Después de una finalización confirmada, el endpoint devuelve únicamente información pública mínima.

Como mínimo:

```text
fileId
```

No devuelve:

- `storage_key`;
- bucket name;
- internal R2 URL;
- signed URL;
- secretos;
- detalles privados de PostgreSQL.

---

# 56. Errores HTTP

Los errores deben permitir al usuario corregir problemas normales sin revelar detalles internos.

Ejemplos aceptables:

```text
Unsupported file type
File exceeds maximum size
Invalid PDF file
Invalid PNG file
File must contain valid UTF-8
Resource cannot accept an upload
```

No deben revelar:

- storage keys;
- SQL interno;
- UUID de otros propietarios;
- stack traces productivos;
- secretos;
- credenciales.

---

# 57. Seguridad

El upload debe mantener:

- same-origin enforcement en operaciones sensibles;
- bounded request body;
- server-side validation;
- autorización PostgreSQL;
- private R2;
- safe filenames;
- canonical MIME;
- hashing;
- mínimo privilegio;
- auditabilidad.

---

# 58. No `service_role`

Astro no utiliza:

```text
service_role
```

para upload.

Esto se mantiene incluso si una operación sería más sencilla con acceso privilegiado.

Las capacidades necesarias deben modelarse mediante:

- RLS;
- grants;
- RPC seguras;
- identidad real del usuario.

---

# 59. No storage key del cliente

El endpoint nunca debe aceptar:

```text
storage_key
```

como input libre del navegador.

La clave es derivada o asignada por componentes confiables.

---

# 60. No publicación durante upload

Una subida exitosa termina como:

```text
pending
```

no:

```text
approved
```

y no convierte automáticamente un recurso en:

```text
public
restricted
privileged
```

como recurso consumible.

La decisión editorial pertenece al Moderator durante aprobación.

---

# 61. Audiencia propuesta

El Contributor puede haber propuesto una:

```text
visibility
```

antes del upload.

Esta propuesta no determina el resultado final.

Upload únicamente preserva el recurso para revisión.

El Moderator selecciona la audiencia final según:

```text
resource-access-contract.md
```

---

# 62. Rights vs upload

La autorización para almacenar y la autorización para publicar no son equivalentes.

Ejemplo:

```text
rights_status = institutional
```

puede permitir guardar y someter el archivo a revisión.

Eso no autoriza posteriormente:

```text
visibility = public
```

La política de publicación se evalúa separadamente.

---

# 63. Fuera de alcance del upload v1

Quedan fuera de este contrato:

- múltiples archivos por recurso;
- ZIP/proyectos;
- multipart con varios documentos;
- uploads directos navegador → R2;
- public bucket;
- signed URLs como flujo principal;
- resumable uploads;
- chunked multi-part object uploads;
- ejecución del contenido;
- compilación;
- conversiones de formato;
- thumbnails;
- OCR;
- antivirus server-side;
- publicación automática;
- ACL por archivo.

---

# 64. Verificación PostgreSQL

Las pruebas pgTAP deben conservar y ampliar como mínimo cobertura para:

- privilegios de las RPC;
- un archivo máximo;
- actor sin capacidad de upload;
- owner incorrecto;
- cuenta no activa;
- estado no editable;
- derechos incompatibles;
- reserva válida;
- finalización válida;
- atomicidad;
- idempotencia;
- hash conflictivo;
- aborto;
- concurrencia;
- auditoría append-only;
- ausencia de acceso directo a `storage_key`.

---

# 65. Tests de derechos para upload

Stage 4C debe demostrar como mínimo:

```text
own-work + valid file
-> upload allowed
```

```text
authorized + valid file
-> upload allowed
```

```text
institutional + valid file
-> upload allowed
```

```text
open-license + valid file
-> upload allowed
```

```text
public-domain + valid file
-> upload allowed
```

```text
pending + file upload
-> denied
```

```text
bibliographic-reference-only + file
-> denied
```

```text
copyright-restricted + file
-> denied
```

---

# 66. Tests Worker

Las pruebas de orquestación deben cubrir:

- validación antes de R2;
- reserva con éxito;
- reserva con fallo conocido;
- reserva con outcome desconocido;
- escritura R2 exitosa;
- escritura R2 fallida;
- escritura R2 con outcome desconocido;
- delete defensivo;
- finalización exitosa;
- finalización con fallo conocido;
- reintento idempotente;
- finalización persistentemente desconocida;
- compensación;
- fallo de compensación;
- preservación de estado para reconciliación.

---

# 67. Tests de formatos

Los tests específicos de:

- PDF;
- PNG;
- JPEG;
- Markdown;
- TeX;
- TXT;
- source;

pertenecen principalmente a:

```text
resource-file-policy.md
```

El upload debe demostrar que utiliza esa política central y no una allowlist paralela.

---

# 68. Tests HTTP

La capa HTTP debe cubrir como mínimo:

```text
GET endpoint
-> 405 + Allow: POST
```

```text
POST without authenticated session
-> unauthorized
```

```text
cross-origin request
-> rejected
```

```text
invalid resource UUID
-> rejected
```

```text
incorrect request media type
-> rejected
```

```text
malformed multipart
-> rejected
```

```text
body over global HTTP limit
-> rejected before expensive processing
```

```text
missing file field
-> rejected
```

```text
non-text comment
-> rejected
```

y errores seguros del validador.

---

# 69. Tests de límites por familia

Deben existir casos donde el request esté dentro del máximo HTTP global pero el archivo exceda su máximo específico.

Por ejemplo:

```text
8 MB .py
```

debe producir rechazo aunque:

```text
8 MB < global multipart maximum
```

porque:

```text
source max = 2 MB
```

---

# 70. Tests de metadata confiable

Debe comprobarse que valores manipulados por cliente no puedan forzar:

```text
file_kind
content_type
normalized_extension
storage_key
storage_key_version
sha256
```

La metadata final debe derivar de componentes confiables.

---

# 71. Tests de storage layout

Stage 4C debe demostrar:

```text
new PDF
-> generic_v2
-> resources/<resource>/<file>
```

```text
new PNG
-> generic_v2
-> resources/<resource>/<file>
```

```text
new source
-> generic_v2
-> resources/<resource>/<file>
```

El formato del archivo no modifica la key v2.

---

# 72. Compatibilidad legacy

El cambio de upload no exige mover los objetos existentes.

La lectura futura debe continuar siendo compatible con:

```text
legacy_pdf_v1
```

según:

```text
resource-file-policy.md
```

---

# 73. Invariantes normativas

## RU-01 — Authorized uploader

Solo un actor activo y autorizado puede subir a un recurso propio editable.

## RU-02 — One file

Un recurso admite como máximo un archivo principal.

## RU-03 — Rights before storage

Un archivo solo puede almacenarse cuando `rights_status` permite almacenamiento.

## RU-04 — Validate before R2

La validación del archivo ocurre antes de escribir el objeto.

## RU-05 — Canonical metadata

La metadata final del archivo se determina server-side.

## RU-06 — Exact-byte hash

SHA-256 representa exactamente los bytes almacenados.

## RU-07 — Private R2

Todos los uploads se almacenan en R2 privado.

## RU-08 — Private key

`storage_key` nunca se expone al cliente final.

## RU-09 — Server-selected layout

El cliente no selecciona el layout o storage key.

## RU-10 — Generic new objects

Nuevos objetos posteriores a la migración correspondiente usan `generic_v2`.

## RU-11 — PostgreSQL atomicity

La finalización PostgreSQL es atómica.

## RU-12 — No automatic publication

Upload nunca produce `approved`.

## RU-13 — Known vs unknown outcome

Los fallos conocidos y resultados desconocidos se tratan de forma distinta.

## RU-14 — Safe compensation

No se realiza compensación destructiva cuando una finalización puede haber ocurrido.

## RU-15 — Idempotent retry

El reintento de finalización reutiliza el mismo `file_id` y SHA-256.

## RU-16 — Auditability

Las transiciones relevantes quedan auditadas.

## RU-17 — No service role

El runtime ordinario de Astro no utiliza `service_role`.

## RU-18 — File policy authority

Los formatos y límites proceden de `resource-file-policy.md`; upload no inventa una allowlist independiente.

---

# 74. Relación con Stage 4C

La evolución se divide en etapas explícitas para evitar mezclar decisiones normativas con implementación.

## Stage 4C.0A — contratos y documentación

Stage 4C.0A define y alinea exclusivamente el contrato normativo.

Puede modificar documentación como:

```text
docs/product/
docs/adr/
docs/architecture/
docs/security/
docs/operations/
AGENTS.md
README.md
```

No introduce:

```text
migraciones PostgreSQL
cambios RLS
nuevas RPC
cambios productivos TypeScript
cambios operativos del layout R2
nuevos formatos habilitados
```

El pipeline operativo al finalizar 4C.0A continúa siendo el baseline PDF de 4B.

---

## Stage 4C.0B — realineación ejecutable

Stage 4C.0B implementa la base necesaria para que código y base de datos puedan representar los contratos aceptados.

Incluye, según el diseño final:

```text
identity_kind
external preauthorization
privileged_material.read
visibility = privileged
rights_status alignment
Moderator final audience
file metadata alignment
storage_key_version
generic_v2 migration
RLS alignment
RPC alignment
auditability
```

Debe incluir las migraciones y pruebas correspondientes.

PDF puede continuar siendo el único formato operativo de upload al finalizar esta etapa.

La migración de storage layout debe realizarse de forma coordinada; no debe cambiarse únicamente TypeScript o únicamente PostgreSQL.

---

## Stage 4C.1 — lectura PDF

Añadir:

```text
PDF read
PDF preview
PDF download
```

mediante acceso server-side y autorización previa a `R2.get`.

Esta etapa prueba el flujo completo de lectura privada sin generalizar todavía todos los formatos de upload.

---

## Stage 4C.2 — upload genérico

Generalizar el pipeline desde:

```text
PDF-only
```

hacia el modelo:

```text
ResourceFile
```

preservando todas las invariantes `RU-*`.

En esta etapa el dispatcher, el orquestador y el handler adoptan el contrato genérico, pero sólo el validador PDF queda registrado operacionalmente. La guarda PostgreSQL PDF-only permanece intencionalmente activa. PNG/JPEG se habilitan en 4C.3 y las familias de texto/source en 4C.4, conforme a:

```text
docs/architecture/resource-file-policy.md
```

---

## Stage 4C.3 — imágenes

Habilita operacionalmente:

```text
PNG
JPEG
```

con las validaciones ya definidas en la política de archivos.

---

## Stage 4C.4 — texto y source

Habilita operacionalmente:

```text
Markdown
TeX
TXT
source code allowlisted
```

como contenido textual no ejecutable.

---

## Stage 4C.5 — interfaz

Incorporar progresivamente las interfaces de Contributor, revisión, moderación, preview y download necesarias para exponer las capacidades anteriores.

Ninguna etapa posterior debe reinterpretar `4C.0A` como autorización para implementar anticipadamente funcionalidades fuera de su alcance.

---

# 75. Regla para implementación

Codex debe tratar las garantías de 4B como inversión que se preserva.

No debe sustituir la orquestación existente por un flujo más simple que elimine:

- reserva;
- compensación;
- idempotencia;
- unknown-outcome handling;
- privacidad de storage;
- atomicidad;
- auditoría.

La generalización de formatos debe producir el menor cambio estructural posible compatible con:

```text
ResourceFile
```

y con las políticas normativas aceptadas para Stage 4C.
