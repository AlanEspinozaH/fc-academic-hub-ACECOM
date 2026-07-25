# ADR 0011: Archivos de recursos, audiencias e identidades externas

## Estado

Aceptada

## Contexto

ADR 0010 estableció el baseline de metadatos, RBAC, RLS y almacenamiento privado para recursos académicos.

Las etapas posteriores implementaron el pipeline de subida especializado en PDF y la coordinación entre PostgreSQL, Astro y Cloudflare R2.

Stage 4C debe evolucionar ese baseline para soportar distintos tipos de archivos académicos y nuevas necesidades de autorización sin reemplazar las garantías ya construidas.

En particular, FC Academic Hub necesita:

* generalizar el concepto de archivo desde PDF hacia un `ResourceFile`;
* mantener Cloudflare R2 privado independientemente de la audiencia lógica;
* distinguir audiencia pública, institucional y privilegiada;
* admitir determinadas identidades externas de manera explícita;
* separar identidad, roles y privilegios especiales de lectura;
* separar derechos de distribución de audiencia de publicación;
* preservar compatibilidad con los objetos PDF existentes;
* tratar todos los uploads como datos no confiables.

Los detalles exactos de autorización, formatos y flujo de upload pertenecen a contratos especializados y no se duplican en este ADR.

## Decisión

### `ResourceFile` genérico

El concepto de archivo de recurso se generaliza hacia:

```text
ResourceFile
```

Un recurso académico continúa admitiendo como máximo un archivo principal en v1.

Los formatos concretos permitidos, sus límites y sus validaciones se definen en:

```text
docs/architecture/resource-file-policy.md
```

### Storage privado

Cloudflare R2 permanece privado para todos los archivos.

La audiencia lógica de un recurso:

```text
public
restricted
privileged
private
```

no modifica la visibilidad física del objeto almacenado.

La autorización se resuelve antes de recuperar el objeto desde R2.

`storage_key` continúa siendo metadata privada de infraestructura y no forma parte del contrato público del cliente.

### Audiencias

Stage 4C adopta las audiencias:

```text
public
restricted
privileged
private
```

`private` representa estado interno o de workflow y no una audiencia final de publicación.

Un recurso aprobado debe terminar con una audiencia final:

```text
public
restricted
privileged
```

Las reglas exactas de acceso pertenecen a:

```text
docs/architecture/resource-access-contract.md
```

### Identidad persistente

La autorización runtime distingue persistentemente:

```text
identity_kind = institutional
identity_kind = external_authorized
```

El email participa en autenticación y admisión, pero no se utiliza como mecanismo ordinario de autorización durante cada request.

Una identidad externa requiere preautorización explícita.

No existe admisión automática de cualquier cuenta Gmail u otro dominio externo.

### Identidades externas en v1

En v1:

```text
external_authorized
```

es una identidad exclusivamente lectora.

No puede recibir roles internos:

```text
student
contributor
reviewer
moderator
administrator
```

Puede recibir explícitamente:

```text
privileged_material.read
```

La preautorización de una identidad externa y la concesión de dicho entitlement son decisiones distintas.

### Roles y entitlements

FC Academic Hub mantiene separados:

```text
identity
role
entitlement
resource audience
```

Los roles representan responsabilidades dentro del workflow.

Los entitlements representan privilegios explícitos independientes de esos roles.

El entitlement definido para v1 es:

```text
privileged_material.read
```

No se debe conceder un rol editorial únicamente para resolver una necesidad de lectura privilegiada.

### `restricted`

La audiencia:

```text
restricted
```

se deriva de una identidad institucional activa.

No depende del rol:

```text
student
```

El concepto histórico:

```text
restricted_material.read
```

deja de ser la fuente normativa de acceso institucional durante Stage 4C.

### `privileged`

La audiencia:

```text
privileged
```

requiere una cuenta activa con:

```text
privileged_material.read
```

El entitlement puede pertenecer a una identidad institucional o a una identidad externa autorizada.

Poseerlo no concede capacidades editoriales.

### Derechos y audiencia

`rights_status` y `visibility` son dimensiones distintas.

`rights_status` expresa qué distribución está jurídicamente o institucionalmente permitida.

`visibility` expresa a qué audiencia decide publicar FC Academic Hub.

La audiencia final nunca puede exceder los derechos aplicables.

PostgreSQL debe imponer las restricciones que puedan determinarse utilizando datos estructurados.

Cuando el alcance permitido dependa de evidencia documental que v1 no representa estructuralmente, corresponde al Moderator verificar esa evidencia antes de aprobar.

### Autoridad editorial y administrativa

`Moderator` representa la autoridad editorial ordinaria.

Entre sus responsabilidades se encuentra determinar la audiencia final de un recurso durante aprobación.

`Administrator` representa la autoridad administrativa de la aplicación.

Entre sus responsabilidades se encuentran gestión de cuentas, roles, entitlements y admisión externa.

El flujo editorial ordinario no debe sustituir Moderator por Administrator.

### Administración de aplicación e infraestructura

El concepto:

```text
App Administrator
```

no es equivalente conceptualmente a:

```text
Infrastructure Custodian
```

La custodia de infraestructura puede comprender sistemas externos como:

```text
GitHub
Cloudflare
Supabase
deployment
secrets
```

Una misma persona puede ejercer ambas responsabilidades, especialmente durante las primeras etapas del proyecto, pero la arquitectura no depende de que permanezcan unidas.

La asignación organizacional concreta de estas responsabilidades queda fuera de este ADR.

### Storage layouts

Los objetos creados por el pipeline PDF anterior pueden conservar:

```text
resources/<resource_id>/<file_id>.pdf
```

Este layout se identifica conceptualmente como:

```text
legacy_pdf_v1
```

Después de implementar la migración correspondiente de Stage 4C, los nuevos uploads utilizan:

```text
resources/<resource_id>/<file_id>
```

sin extensión.

Este layout se identifica como:

```text
generic_v2
```

Los objetos legacy no se renombran únicamente para adoptar el nuevo modelo.

La implementación debe poder resolver ambos layouts explícitamente.

### Uploads no confiables

Todo archivo aportado por usuarios se considera:

```text
untrusted input
```

La aplicación debe validar server-side el formato antes de almacenarlo.

El MIME enviado por el navegador no constituye autoridad.

El servidor determina metadata canónica y calcula SHA-256 sobre los bytes que serán almacenados.

### No ejecución

Aceptar un archivo significa únicamente que FC Academic Hub puede:

```text
validarlo
almacenarlo
mostrarlo de forma segura
permitir su descarga
```

No significa que pueda ejecutarlo.

V1 no ejecuta código, no compila código, no compila LaTeX y no interpreta contenido aportado por usuarios como HTML activo.

## Compatibilidad con ADR 0010

ADR 0010 continúa representando el baseline histórico de Stage 4A.

ADR 0011 modifica o amplía específicamente las siguientes decisiones de ese baseline:

* `restricted` pasa a derivarse de identidad institucional activa y no del rol `student`;
* se incorpora la audiencia `privileged`;
* se incorpora `identity_kind`;
* se incorpora admisión externa explícita;
* se incorpora `privileged_material.read`;
* el modelo de archivo evoluciona hacia `ResourceFile`;
* aparecen `legacy_pdf_v1` y `generic_v2`;
* los derechos y la audiencia quedan explícitamente separados.

Las garantías de seguridad que no resulten contradichas por este ADR permanecen vigentes.

En particular se conservan:

* PostgreSQL como autoridad de autorización;
* RLS;
* ausencia de `service_role` en el runtime normal de Astro;
* `storage_key` privado;
* funciones controladas para cambios sensibles;
* auditoría;
* almacenamiento R2 privado.

## Consecuencias

* La autorización deja de depender de una jerarquía de roles para determinar audiencias de lectura.
* Una identidad institucional activa puede consumir contenido `restricted` sin poseer `student`.
* Una identidad externa puede ser admitida sin convertirse en institucional.
* La lectura privilegiada puede concederse sin otorgar capacidades editoriales.
* Los nuevos formatos pueden incorporarse detrás de una política común de `ResourceFile`.
* El pipeline existente puede evolucionar incrementalmente en lugar de reescribirse.
* PostgreSQL y R2 continúan separados por una frontera explícita de autorización.
* Los objetos PDF existentes pueden continuar funcionando sin migración física obligatoria.
* La arquitectura permite separar en el futuro administración de aplicación y custodia de infraestructura.

## Alternativas consideradas

### Hacer públicos los objetos R2 de recursos `public`

Rechazado.

La audiencia es una propiedad del recurso y no del bucket. Mantener R2 privado reduce vías alternativas de acceso y conserva una única política de autorización.

### Utilizar roles para representar todas las audiencias

Rechazado.

Roles editoriales y audiencias de consumo representan conceptos diferentes. Utilizar Contributor, Reviewer o Moderator para conceder lectura privilegiada produciría acoplamiento innecesario.

### Mantener `student` como requisito para `restricted`

Rechazado.

La pertenencia a la audiencia institucional se representa mediante identidad institucional activa, no mediante una responsabilidad de workflow.

### Autorizar identidades externas mediante dominio o email durante cada request

Rechazado.

La admisión puede evaluar la identidad autenticada, pero la autorización runtime utiliza información persistente controlada por el sistema.

### Permitir roles internos a identidades externas en v1

Rechazado.

V1 limita `external_authorized` a lectura para reducir complejidad de gobierno, RLS, auditoría y recuperación de cuentas.

### Crear ACL individuales por recurso

Rechazado para v1.

La versión inicial utiliza una única audiencia privilegiada global mediante:

```text
privileged_material.read
```

### Introducir un `rights_scope` estructurado adicional

Rechazado para v1.

Algunas restricciones pueden imponerse mediante datos estructurados, mientras el alcance documental de determinadas autorizaciones permanece bajo revisión editorial humana.

### Renombrar todos los objetos PDF legacy

Rechazado.

La compatibilidad entre:

```text
legacy_pdf_v1
generic_v2
```

es suficiente y evita una migración física sin necesidad funcional.

### Confiar en el MIME enviado por el navegador

Rechazado.

Los archivos son datos no confiables. La clasificación se determina mediante extensión admitida, validación del contenido y metadata canónica server-side.

### Ejecutar o compilar archivos aportados

Rechazado para v1.

FC Academic Hub funciona como repositorio académico y no como entorno de ejecución.

## Contratos relacionados

Las reglas normativas detalladas se encuentran en:

```text
docs/architecture/resource-access-contract.md
docs/architecture/resource-file-policy.md
docs/architecture/resource-upload-contract.md
docs/architecture/authentication-and-authorization.md
docs/security/role-model.md
docs/product/v1-product-contract.md
```

Este ADR documenta las decisiones arquitectónicas y sus motivos.

Los contratos especializados definen las reglas operativas exactas que la implementación de Stage 4C debe satisfacer.
