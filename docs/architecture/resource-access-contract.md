# Contrato de acceso a recursos académicos

## Estado

Decisión: **Aceptada**

Implementación: **pendiente de Stage 4C**

Este documento define el contrato normativo de autorización para recursos académicos y sus archivos.

Describe el comportamiento objetivo que PostgreSQL, RLS, RPC y los endpoints server-side deben implementar.

Mientras Stage 4C no esté implementado completamente, pueden existir diferencias entre este contrato y el comportamiento actual del repositorio.

Las diferencias deben resolverse haciendo converger implementación, migraciones, pruebas y documentación hacia este contrato.

---

## Propósito

FC Academic Hub debe separar explícitamente:

* identidad;
* estado de cuenta;
* roles;
* privilegios especiales;
* estado de revisión del recurso;
* audiencia de publicación;
* derechos de distribución;
* almacenamiento físico del archivo.

La autorización de un recurso no depende de que su objeto R2 sea público o privado.

Cloudflare R2 permanece privado.

PostgreSQL y la aplicación server-side determinan si un actor puede acceder a un recurso antes de recuperar su archivo desde R2.

---

## Principios

1. Un archivo almacenado en R2 no es público por sí mismo.
2. `visibility` representa audiencia de publicación, no visibilidad física del bucket.
3. `rights_status` y `visibility` son dimensiones diferentes.
4. Los derechos establecen el máximo de distribución permitido.
5. La audiencia seleccionada nunca puede ampliar esos derechos.
6. Ninguna audiencia permite saltarse el workflow de revisión.
7. Los roles editoriales y los privilegios especiales de lectura son conceptos distintos.
8. La autorización runtime no se deriva directamente del email.
9. Los archivos no autorizados no deben recuperarse desde R2.
10. Las claves internas de almacenamiento nunca forman parte del contrato público del cliente.

---

# 1. Terminología

## Actor

Identidad que realiza una solicitud.

Puede ser:

* anónimo;
* usuario institucional;
* usuario externo autorizado;
* Contributor;
* Reviewer;
* Moderator;
* Administrator;
* usuario con entitlement especial.

Una misma persona puede pertenecer a varias categorías simultáneamente.

Por ejemplo:

```text
institutional
+
contributor
+
privileged_material.read
```

---

## Identidad institucional

Cuenta reconocida por FC Academic Hub como perteneciente a la comunidad institucional ordinaria.

Conceptualmente:

```text
identity_kind = institutional
```

La clasificación institucional no debe recalcularse mediante comparaciones de dominio de email durante cada decisión de autorización.

---

## Identidad externa autorizada

Identidad no institucional admitida expresamente por la Facultad.

Conceptualmente:

```text
identity_kind = external_authorized
```

Una identidad externa no obtiene automáticamente permisos especiales.

Su admisión al sistema y sus privilegios runtime son decisiones diferentes.

---

## Estado de cuenta

Los estados existentes son:

```text
active
suspended
disabled
```

Los privilegios autenticados requieren normalmente:

```text
account_status = active
```

Una cuenta suspendida o deshabilitada conserva únicamente el acceso que tendría un visitante anónimo a contenido público.

---

## Rol

Los roles representan responsabilidades dentro del workflow.

```text
student
contributor
reviewer
moderator
administrator
```

Los roles no deben utilizarse como sustituto de privilegios especiales de lectura.

---

## Entitlement

Un entitlement representa una autorización explícita concedida a un usuario independientemente de sus roles editoriales.

El entitlement v1 es:

```text
privileged_material.read
```

Este entitlement permite acceder a recursos:

```text
approved + privileged
```

cuando la cuenta está activa.

No permite:

* crear recursos;
* revisar;
* aprobar;
* rechazar;
* administrar usuarios;
* saltarse estados de revisión.

---

# 2. Audiencias de publicación

El enum conceptual de `visibility` es:

```text
private
restricted
privileged
public
```

---

## `public`

Significa:

> El recurso aprobado puede ser consumido por cualquier persona.

No requiere:

* autenticación;
* identidad institucional;
* entitlement;
* rol.

Solo puede ser efectivo cuando:

```text
review_status = approved
```

y:

```text
rights_status
```

permite distribución pública.

---

## `restricted`

Significa:

> El recurso aprobado está dirigido a la comunidad institucional ordinaria.

Requiere:

```text
authenticated
AND
account_status = active
AND
identity_kind = institutional
```

No requiere un rol editorial.

Un usuario externo con:

```text
privileged_material.read
```

no obtiene acceso a `restricted` únicamente por tener dicho entitlement.

---

## `privileged`

Significa:

> El recurso aprobado está destinado a una audiencia especial expresamente autorizada.

Requiere:

```text
authenticated
AND
account_status = active
AND
privileged_material.read
```

Puede acceder una identidad:

```text
institutional
```

o:

```text
external_authorized
```

si posee el entitlement correspondiente.

Una identidad institucional sin entitlement no obtiene acceso a `privileged`.

---

## `private`

`private` no constituye una audiencia final de publicación.

Se utiliza para representar recursos internos o todavía no publicados durante el workflow.

La combinación:

```text
approved + private
```

es inválida en v1.

---

# 3. Matriz de recursos aprobados

Para usuarios finales, el acceso a recursos `approved` debe seguir esta matriz:

| Actor                                   |         `public` | `restricted` | `privileged` |
| --------------------------------------- | ---------------: | -----------: | -----------: |
| Anónimo                                 |               Sí |           No |           No |
| Institucional activo                    |               Sí |           Sí |           No |
| Institucional activo + entitlement      |               Sí |           Sí |           Sí |
| Externo autorizado activo               |               Sí |           No |           No |
| Externo autorizado activo + entitlement |               Sí |           No |           Sí |
| Cuenta suspendida                       | Sí, como anónimo |           No |           No |
| Cuenta disabled                         | Sí, como anónimo |           No |           No |

La existencia de una sesión autenticada nunca debe reducir el acceso a contenido que ya es públicamente accesible.

Por tanto:

```text
anonymous + approved/public
```

y:

```text
suspended + approved/public
```

deben producir acceso equivalente al contenido público.

---

# 4. Workflow de revisión

El flujo principal es:

```text
draft
  ↓
pending
  ↓
approved
   |
   └── rejected
```

Formalmente:

```text
draft -> pending -> approved | rejected
```

Un recurso `rejected` puede ser corregido y reenviado posteriormente.

---

# 5. Matriz de workflow

| Estado     |           Owner |                            Reviewer | Moderator | Administrator |   Usuario final |
| ---------- | --------------: | ----------------------------------: | --------: | ------------: | --------------: |
| `draft`    |              Sí |                                  No |        No |            Sí |              No |
| `pending`  |              Sí |                                  Sí |        Sí |            Sí |              No |
| `rejected` |              Sí |                                  No |        No |            Sí |              No |
| `approved` | Según audiencia | Según audiencia o función editorial |        Sí |            Sí | Según audiencia |

---

## Draft

Un `draft` todavía pertenece al espacio de trabajo del propietario.

El propietario puede acceder si conserva los permisos requeridos para gestionar su recurso.

Un Reviewer no puede acceder a drafts ajenos.

Un Moderator no puede acceder a drafts ajenos únicamente por ser Moderator.

Un Administrator puede acceder por razones administrativas.

---

## Pending

`pending` significa que el propietario ha enviado formalmente el recurso a revisión.

Pueden acceder:

* owner;
* Reviewer;
* Moderator;
* Administrator.

No pueden acceder como usuarios finales:

* anónimos;
* institucionales ordinarios;
* usuarios con entitlement privilegiado.

La audiencia propuesta no cambia esta regla.

Por ejemplo:

```text
review_status = pending
visibility = public
```

continúa sin ser público.

---

## Rejected

Un recurso rechazado vuelve al ámbito del propietario.

Pueden acceder:

* owner;
* Administrator.

Reviewer y Moderator no obtienen acceso permanente a recursos rechazados ajenos únicamente por su rol.

---

## Approved

Un recurso aprobado entra en su audiencia final:

```text
public
restricted
privileged
```

Los usuarios finales acceden según dicha audiencia.

Los Moderator y Administrator conservan acceso necesario para sus responsabilidades editoriales y administrativas.

---

# 6. Ownership

La propiedad del recurso concede acceso al workflow mientras el recurso se encuentra en estados editables o de revisión según este contrato.

La propiedad no convierte automáticamente un recurso aprobado en visible para su propietario fuera de las reglas establecidas para recursos `approved`.

Una vez aprobado, la audiencia final es la política ordinaria de consumo del recurso.

---

# 7. Moderator

El Moderator es la autoridad editorial ordinaria sobre los recursos académicos.

Puede:

* revisar recursos `pending`;
* acceder al archivo pendiente;
* verificar metadatos;
* verificar derechos;
* evaluar duplicados;
* aprobar;
* rechazar;
* seleccionar la audiencia final;
* iniciar o ejecutar procedimientos editoriales de retiro según el contrato correspondiente.

El Moderator no puede:

* aprobar su propio recurso;
* acceder a drafts ajenos únicamente por ser Moderator;
* acceder a rejected ajenos únicamente por ser Moderator;
* conceder entitlements permanentes a usuarios;
* admitir arbitrariamente identidades externas;
* ampliar derechos legales mediante una decisión de visibilidad.

---

# 8. Múltiples moderators

El sistema admite múltiples usuarios con rol `moderator`.

No existe un límite estructural de dos moderators.

Para el piloto se recomienda mantener al menos dos Moderators activos para:

* reducir dependencia de una única persona;
* evitar bloqueo operativo durante ausencias;
* permitir que otro Moderator revise recursos propiedad de un Moderator;
* distribuir carga de revisión.

La versión 1 no exige aprobación múltiple.

Una única aprobación válida es suficiente.

La regla:

```text
Moderator cannot approve own resource
```

se mantiene independientemente del número de Moderators existentes.

---

# 9. Administrator

El Administrator es la autoridad administrativa de la plataforma.

Puede:

* gestionar roles;
* gestionar Moderators;
* suspender o deshabilitar cuentas;
* gestionar admisión de identidades externas;
* conceder y revocar entitlements;
* responder a incidentes;
* acceder administrativamente a recursos del workflow cuando sea necesario.

El Administrator no debe convertirse en el actor editorial ordinario del producto.

La publicación normal corresponde al Moderator.

Las capacidades administrativas existen para operación, seguridad, recuperación y gobierno del sistema.

---

# 10. Reviewer

Reviewer participa en el workflow de revisión.

Puede acceder a recursos:

```text
pending
```

según la política definida.

No publica recursos.

No determina la audiencia final.

No obtiene acceso general a:

```text
draft
rejected
```

ajenos únicamente por poseer el rol.

El producto v1 puede no exponer una interfaz independiente para Reviewer aunque el rol continúe existiendo internamente.

---

# 11. Contributor

Contributor puede:

* crear recursos;
* editar recursos propios permitidos;
* subir el archivo principal admitido;
* corregir recursos rechazados;
* reenviar recursos;
* proponer metadatos;
* proponer `rights_status`;
* proponer una audiencia.

La audiencia propuesta por Contributor no constituye la decisión final de publicación.

El Moderator puede:

* aceptarla;
* reducirla;
* cambiarla;

siempre dentro de los límites permitidos por `rights_status`.

---

# 12. Privilegios especiales

El privilegio:

```text
privileged_material.read
```

es independiente de los roles.

Ejemplos válidos:

```text
external_authorized
+
privileged_material.read
+
sin roles
```

Resultado:

```text
approved/public      -> acceso
approved/restricted  -> no acceso
approved/privileged  -> acceso
```

Otro ejemplo:

```text
institutional
+
privileged_material.read
```

Resultado:

```text
approved/public      -> acceso
approved/restricted  -> acceso
approved/privileged  -> acceso
```

El entitlement no concede capacidades editoriales.

---

# 13. Administración de entitlements

Los entitlements deben ser concedidos y revocados por una autoridad administrativa.

En v1:

```text
Administrator
```

es responsable de dicha gestión.

La concesión debe estar asociada al:

```text
user_id
```

de la identidad interna.

No debe implementarse autorización runtime mediante comparaciones como:

```text
email === "persona@gmail.com"
```

Conceptualmente, una asignación debe poder registrar:

```text
user_id
entitlement
granted_by
granted_at
revoked_at
reason
```

La estructura SQL exacta pertenece al diseño de implementación posterior.

---

# 14. Identidades externas

Una identidad externa no puede ingresar únicamente porque utilice Gmail u otro proveedor permitido por OAuth.

La admisión externa debe requerir preautorización explícita.

La regla conceptual es:

```text
institutional domain allowed
OR
exact external identity preauthorized
```

Un Gmail arbitrario debe ser rechazado.

---

# 15. Preautorización externa

La preautorización responde únicamente:

> ¿Puede esta identidad externa ser admitida en FC Academic Hub?

No responde:

> ¿Puede acceder a recursos privileged?

Estas son decisiones diferentes.

Conceptualmente una preautorización puede conservar:

```text
normalized_email
status
authorized_by
authorized_at
revoked_by
revoked_at
reason
```

Una vez materializada la identidad, la autorización runtime debe utilizar:

```text
user_id
identity_kind
account_status
roles
entitlements
```

y no comparaciones repetidas del email.

---

# 16. Cambio de tipo de identidad

Una cuenta institucional no debe convertirse automáticamente en:

```text
external_authorized
```

porque su email haya cambiado.

Del mismo modo, una identidad externa no debe convertirse automáticamente en institucional mediante un simple cambio de email.

Los cambios que atraviesen categorías de identidad requieren un procedimiento administrativo explícito.

En v1 no se implementa linking complejo de múltiples identidades para una misma cuenta.

---

# 17. Derechos y audiencia

`rights_status` responde:

> ¿Qué distribución tenemos derecho o autorización para realizar?

`visibility` responde:

> ¿A qué audiencia decide publicar FC Academic Hub este recurso?

La segunda nunca puede superar a la primera.

---

# 18. Rights statuses

Los estados objetivo son:

```text
pending
own-work
authorized
institutional
open-license
public-domain
bibliographic-reference-only
copyright-restricted
```

---

# 19. Matriz de derechos

| `rights_status`                |              Archivo almacenado |            `public` |        `restricted` |                                                 `privileged` |
| ------------------------------ | ------------------------------: | ------------------: | ------------------: | -----------------------------------------------------------: |
| `pending`                      |  Puede existir durante workflow |          No aprobar |          No aprobar |                                                   No aprobar |
| `own-work`                     |                              Sí |                  Sí |                  Sí |                                                           Sí |
| `authorized`                   |                              Sí |  Según autorización |  Según autorización |                                           Según autorización |
| `institutional`                |                              Sí |                  No |                  Sí | Sí, cuando la autorización institucional cubra esa audiencia |
| `open-license`                 |                              Sí |                  Sí |                  Sí |                                                           Sí |
| `public-domain`                |                              Sí |                  Sí |                  Sí |                                                           Sí |
| `bibliographic-reference-only` | No archivo principal almacenado | Metadatos solamente | Metadatos solamente |                                          Metadatos solamente |
| `copyright-restricted`         |            No según política v1 |                  No |                  No |                                                           No |

Esta matriz representa el máximo potencial permitido.

No significa que un recurso deba utilizar la audiencia más amplia disponible.

Por ejemplo:

```text
rights_status = open-license
visibility = restricted
```

es válido.

---

# 20. `institutional`

`institutional` significa que la Facultad dispone de una base institucional para distribuir el recurso dentro de las audiencias autorizadas.

No implica autorización automática para publicación abierta en Internet.

Por tanto:

```text
institutional + public
```

no está permitido en v1.

Se permite:

```text
institutional + restricted
```

y:

```text
institutional + privileged
```

únicamente cuando la audiencia privilegiada esté incluida dentro de la autorización institucional aplicable.

La verificación de esta última condición forma parte de la revisión editorial.

---

# 21. `authorized`

`authorized` significa que existe autorización explícita documentada.

No implica automáticamente autorización pública.

El Moderator debe verificar que la evidencia de derechos cubra la audiencia final seleccionada.

Ejemplo:

```text
authorized
```

puede representar una autorización limitada a:

```text
restricted
```

y no permitir:

```text
public
```

En v1 no se introduce un segundo enum para modelar estructuralmente el alcance jurídico exacto de cada autorización.

Esta comprobación permanece como responsabilidad editorial humana documentada.

---

# 22. `open-license`

`open-license` indica que existe una licencia que permite distribución bajo determinadas condiciones.

Puede permitir:

```text
public
restricted
privileged
```

pero no obliga a seleccionar `public`.

Las condiciones concretas de la licencia deben respetarse.

Una futura versión puede registrar estructuralmente el identificador concreto de licencia.

---

# 23. `public-domain`

`public-domain` permite utilizar una audiencia pública cuando la condición de dominio público haya sido correctamente determinada.

También puede utilizarse una audiencia más restrictiva.

---

# 24. Decisión final de audiencia

El Contributor puede proponer:

```text
visibility
```

durante la preparación del recurso.

La propuesta no tiene autoridad final.

Durante aprobación, el Moderator determina:

```text
final_visibility
```

entre:

```text
public
restricted
privileged
```

PostgreSQL debe impedir que la audiencia final exceda lo permitido por:

```text
rights_status
```

Conceptualmente:

```text
Contributor proposes audience
        ↓
resource becomes pending
        ↓
Moderator reviews rights
        ↓
Moderator selects final audience
        ↓
PostgreSQL validates combination
        ↓
approved
```

---

# 25. `approved + private`

La combinación:

```text
review_status = approved
visibility = private
```

es inválida.

Una aprobación debe establecer una audiencia final válida:

```text
public
restricted
privileged
```

---

# 26. Acceso público y cuentas suspendidas

Una suspensión elimina privilegios autenticados.

No elimina capacidades disponibles universalmente.

Por tanto:

```text
suspended
+
approved/public
```

debe continuar siendo accesible.

En cambio:

```text
suspended
+
approved/restricted
```

debe ser denegado.

Y:

```text
suspended
+
approved/privileged
```

también debe ser denegado aunque exista un entitlement no revocado.

---

# 27. Recursos pendientes y entitlements

Un entitlement nunca permite saltarse el estado de revisión.

Ejemplo:

```text
identity = external_authorized
entitlement = privileged_material.read

resource:
review_status = pending
visibility = privileged
```

Resultado:

```text
DENY
```

Solo los actores del workflow correspondiente pueden acceder al recurso pendiente.

---

# 28. Autorización de archivos

La autorización de metadatos y la autorización del archivo deben utilizar el mismo contrato de acceso.

Un usuario que no puede acceder al recurso tampoco puede:

* previsualizar su archivo;
* descargarlo;
* obtener una URL directa;
* conocer su `storage_key`.

La vista previa y la descarga tienen la misma autorización.

---

# 29. Endpoint binario

Las solicitudes directas al contenido de un archivo deben evitar revelar innecesariamente su existencia.

Para el endpoint binario:

```text
file does not exist
```

y:

```text
file exists but actor is unauthorized
```

deben producir el mismo comportamiento observable:

```text
404 Not Found
```

La interfaz normal puede mostrar mensajes más informativos cuando ya conoce legítimamente los metadatos del recurso.

---

# 30. Orden obligatorio de autorización

La recuperación de un archivo debe seguir conceptualmente:

```text
request
   ↓
identify actor
   ↓
PostgreSQL authorization / RLS
   ↓
accessible file metadata?
   │
   ├── no
   │     ↓
   │    404
   │
   └── yes
         ↓
     resolve private storage object
         ↓
       R2 read
         ↓
      response
```

Nunca:

```text
R2.get
   ↓
authorization afterwards
```

Un rechazo de autorización debe evitar la lectura del objeto.

---

# 31. Storage

Cloudflare R2 permanece privado.

No se utiliza R2 como autoridad de autorización.

No crear reglas equivalentes a:

```text
visibility = public
-> make R2 object public
```

La publicación es una propiedad lógica del recurso, no del bucket.

---

# 32. `storage_key`

`storage_key` es metadata interna.

No debe:

* exponerse en respuestas públicas;
* devolverse al navegador;
* aceptarse libremente desde el cliente;
* utilizarse como identificador público del recurso.

Los clientes trabajan con identificadores de dominio como:

```text
resource_id
file_id
```

El servidor resuelve internamente el objeto correspondiente.

---

# 33. Roles enviados por cliente

La aplicación no debe confiar en valores como:

```text
role = moderator
```

enviados por:

* formularios;
* JSON;
* headers controlados por cliente;
* localStorage;
* query parameters.

Los roles y entitlements efectivos se resuelven mediante PostgreSQL y las estructuras autorizadas del sistema.

---

# 34. Email y autorización runtime

No debe existir autorización de recursos basada en reglas como:

```text
email.endsWith("@universidad.edu")
```

durante cada request.

El email participa en admisión e identidad.

La autorización utiliza atributos persistidos y controlados por el sistema.

---

# 35. Invariantes normativas

## RA-01 — Public access

El acceso `approved + public` es independiente del estado de autenticación.

---

## RA-02 — Suspended/disabled baseline

Las cuentas `suspended` y `disabled` conservan únicamente el acceso disponible para un actor anónimo.

---

## RA-03 — Restricted identity

`approved + restricted` requiere:

```text
active
+
institutional
```

---

## RA-04 — Privileged entitlement

`approved + privileged` requiere:

```text
active
+
privileged_material.read
```

---

## RA-05 — Privileged does not imply institutional

Una identidad externa con `privileged_material.read` no obtiene acceso a `restricted`.

---

## RA-06 — Workflow cannot be bypassed

Roles de audiencia y entitlements nunca omiten `review_status`.

---

## RA-07 — Moderator draft isolation

Un Moderator no puede leer drafts o rejected ajenos únicamente por su rol.

---

## RA-08 — Administrator exceptional access

Administrator puede acceder a recursos internos cuando sea necesario para administración, seguridad y recuperación.

---

## RA-09 — Approved private invalid

```text
approved + private
```

es inválido.

---

## RA-10 — Rights ceiling

La audiencia final nunca puede superar la distribución permitida por `rights_status`.

---

## RA-11 — Non-disclosure

Una solicitud directa de archivo no debe distinguir externamente entre:

```text
missing
```

y:

```text
unauthorized
```

---

## RA-12 — Trusted authorization sources

La autorización no depende de:

* roles enviados por navegador;
* comparación runtime directa del email;
* `storage_key` proporcionado por cliente.

---

## RA-13 — Moderator final audience

El Moderator selecciona la audiencia final durante aprobación.

La audiencia propuesta por Contributor no es vinculante.

---

## RA-14 — Administrative grants

Solo la autoridad administrativa definida por el producto puede:

* admitir identidades externas;
* conceder;
* revocar;

`privileged_material.read`.

En v1 esa autoridad es Administrator.

---

## RA-15 — R2 after authorization

R2 no debe consultarse para recuperar un objeto antes de que la autorización haya sido confirmada.

---

## RA-16 — Preview equals download authorization

Preview y descarga requieren exactamente la misma autorización sobre el recurso.

---

# 36. Pruebas normativas requeridas

La implementación debe demostrar como mínimo las siguientes reglas.

## Public

```text
anonymous + approved/public -> allow
institutional active + approved/public -> allow
external active + approved/public -> allow
suspended + approved/public -> allow
disabled + approved/public -> allow
```

---

## Restricted

```text
anonymous + approved/restricted -> deny
institutional active + approved/restricted -> allow
institutional suspended + approved/restricted -> deny
external active + approved/restricted -> deny
external privileged + approved/restricted -> deny
institutional privileged + approved/restricted -> allow
```

---

## Privileged

```text
anonymous + approved/privileged -> deny

institutional active without entitlement
+ approved/privileged
-> deny

institutional active with entitlement
+ approved/privileged
-> allow

external active without entitlement
+ approved/privileged
-> deny

external active with entitlement
+ approved/privileged
-> allow

suspended user with entitlement
+ approved/privileged
-> deny

revoked entitlement
+ approved/privileged
-> deny
```

---

# 37. Pruebas de workflow

## Draft

```text
owner contributor -> allow
reviewer other -> deny
moderator other -> deny
administrator -> allow
privileged user -> deny
anonymous -> deny
```

## Pending

```text
owner -> allow
reviewer -> allow
moderator -> allow
administrator -> allow
institutional ordinary user -> deny
privileged ordinary user -> deny
anonymous -> deny
```

## Rejected

```text
owner -> allow
reviewer other -> deny
moderator other -> deny
administrator -> allow
ordinary user -> deny
```

---

# 38. Pruebas de roles y entitlements

Debe demostrarse que roles y entitlements son independientes.

Ejemplo:

```text
external_authorized
+
privileged_material.read
+
no editorial roles
```

debe:

```text
read approved/privileged -> allow
create resource -> deny
review pending -> deny
approve -> deny
manage roles -> deny
```

---

# 39. Pruebas de derechos y audiencia

Como mínimo:

```text
institutional + public
-> approval rejected

institutional + restricted
-> approval allowed

institutional + privileged
-> allowed only under documented institutional authorization

open-license + public
-> allowed

public-domain + public
-> allowed

pending rights + approval
-> rejected

copyright-restricted + approval with stored file
-> rejected

bibliographic-reference-only + stored file
-> rejected
```

---

# 40. Pruebas de autoridad editorial

Ejemplo:

```text
Contributor proposes:
visibility = public
rights_status = institutional
```

Moderator intenta:

```text
approve(public)
```

Resultado:

```text
REJECT
```

Moderator selecciona:

```text
approve(restricted)
```

Resultado:

```text
ALLOW
```

Otro ejemplo:

```text
Contributor proposes:
visibility = restricted
rights_status = open-license
```

Moderator puede seleccionar:

```text
public
```

si el resto de las condiciones de publicación están satisfechas.

---

# 41. Pruebas del endpoint binario

Debe comprobarse:

```text
missing file
-> 404
```

y:

```text
unauthorized file
-> 404
```

Además:

```text
authorization denied
-> R2 read must not execute
```

---

# 42. Auditoría

Las acciones sensibles deben poder auditarse.

Como mínimo:

* aprobación;
* rechazo;
* cambio final de audiencia;
* concesión de roles;
* revocación de roles;
* concesión de entitlement;
* revocación de entitlement;
* admisión administrativa de identidad externa;
* suspensión/desactivación de cuentas;
* retiro de contenido.

La estructura exacta de las tablas de auditoría pertenece al diseño de implementación.

---

# 43. No objetivos v1

Este contrato no introduce:

* ACL individual `usuario × recurso`;
* múltiples cohortes privileged;
* grupos arbitrarios;
* permisos personalizados por archivo;
* account linking entre Gmail e identidad institucional;
* múltiples identidades activas para una misma cuenta;
* publicación directa de objetos R2;
* URLs públicas permanentes de R2;
* URLs firmadas como mecanismo principal de autorización;
* autorización basada en email durante cada request;
* doble aprobación obligatoria por dos Moderators;
* bypass administrativo silencioso sin auditoría.

---

# 44. Modelo privileged v1

En v1 existe una única audiencia privilegiada global.

Conceptualmente:

```text
privileged_material.read
```

significa:

> El usuario puede consultar todos los recursos `approved + privileged`.

No existe todavía:

```text
privileged_group_A
privileged_group_B
```

ni:

```text
user X can read resource Y
```

Si en el futuro existen necesidades reales de múltiples cohortes, grupos o permisos específicos por recurso, deberán diseñarse mediante un cambio explícito de contrato y, cuando corresponda, un nuevo ADR.

---

# 45. Relación con otros documentos

Este documento define la política normativa de acceso.

Debe leerse junto con:

```text
docs/product/v1-product-contract.md
```

para alcance de producto;

```text
docs/adr/0011-resource-files-access-and-external-identities.md
```

para decisiones arquitectónicas y su justificación;

```text
docs/architecture/resource-file-policy.md
```

para formatos, validación y presentación de archivos;

```text
docs/architecture/resource-upload-contract.md
```

para atomicidad, compensación y garantías del upload;

y:

```text
docs/security/role-model.md
```

para responsabilidades editoriales y administrativas.

Cuando una implementación de Stage 4C modifique comportamiento cubierto por este contrato, las pruebas correspondientes deben actualizarse en el mismo cambio.

---

# 46. Regla de implementación

Codex y cualquier implementación futura deben tratar este documento como contrato cerrado para Stage 4C.

No deben añadirse implícitamente:

* nuevas audiencias;
* nuevos entitlements;
* nuevos roles;
* excepciones de autorización;
* bypasses administrativos;
* ACL por recurso;

sin modificar primero el contrato normativo y aprobar explícitamente la nueva decisión de producto o arquitectura.
