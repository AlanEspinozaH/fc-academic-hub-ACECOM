# Modelo de roles, permisos y entitlements

## Estado

Baseline implementado: **Stage 3A / 4A**

Evolución de autorización: **aceptada para Stage 4C**

Implementación de entitlements, identidades externas y nueva semántica de acceso: **pendiente**

Este documento define las responsabilidades asociadas a los roles de FC Academic Hub y su separación respecto de:

* identidad;
* estado de cuenta;
* audiencia de recursos;
* entitlements;
* ownership;
* workflow de revisión.

El modelo de roles no sustituye las políticas RLS.

PostgreSQL continúa siendo la autoridad de autorización.

---

# 1. Principio fundamental

FC Academic Hub distingue tres conceptos:

```text
identity
roles
entitlements
```

Cada uno responde una pregunta distinta.

## Identidad

Responde:

> ¿Qué clase de cuenta es?

Ejemplos:

```text
institutional
external_authorized
```

La identidad puede determinar pertenencia a una audiencia ordinaria como:

```text
restricted
```

---

## Rol

Responde:

> ¿Qué responsabilidades tiene esta persona dentro del workflow?

Ejemplos:

```text
contributor
reviewer
moderator
administrator
```

---

## Entitlement

Responde:

> ¿Qué privilegio especial se ha concedido explícitamente a esta cuenta?

En v1:

```text
privileged_material.read
```

---

# 2. Roles

Los roles existentes son:

```text
student
contributor
reviewer
moderator
administrator
```

Los roles y `identity_kind` son conceptos distintos, pero su combinación está restringida en v1.

Todos los roles internos requieren:

```text
identity_kind = institutional
account_status = active
```

Una identidad:

```text
external_authorized
```

no puede recibir:

```text
student
contributor
reviewer
moderator
administrator
```

Una identidad institucional puede existir sin roles.

También es válido:

```text
identity_kind = external_authorized
+
privileged_material.read
+
roles = none
```
---

# 3. Estados de cuenta

Los estados son:

```text
active
suspended
disabled
```

Las capacidades autenticadas internas requieren normalmente:

```text
account_status = active
```

Las cuentas `suspended` y `disabled` pierden:

* capacidades editoriales;
* acceso `restricted`;
* acceso `privileged`;
* gestión administrativa.

Conservan únicamente aquello que también pueda consumir un actor anónimo, como un recurso:

```text
approved + public
```

---

# 4. Capacidades editoriales

Las capacidades conceptuales principales son:

```text
submission.create
submission.review
submission.publish

role.manage
entitlement.manage
external_identity.manage
account.suspend
audit.read
```

La implementación puede utilizar nombres diferentes internamente siempre que conserve esta separación semántica.

---

# 5. Acceso de audiencia no es un rol

Las siguientes capacidades de lectura no deben derivarse de la jerarquía editorial:

```text
restricted
privileged
```

## `restricted`

Depende de:

```text
account_status = active
AND
identity_kind = institutional
```

No depende de:

```text
student
contributor
reviewer
moderator
```

como condición de audiencia.

---

## `privileged`

Depende de:

```text
account_status = active
AND
privileged_material.read
```

No se obtiene automáticamente por poseer ningún rol.

---

# 6. `restricted_material.read` legacy

El baseline anterior asociaba:

```text
student
→ restricted_material.read
```

y propagaba esa capacidad a roles superiores.

Stage 4C reemplaza esa interpretación.

`restricted_material.read` debe considerarse un concepto legacy de autorización y no la fuente normativa para decidir acceso `restricted`.

La regla normativa nueva es:

```text
restricted
→ active institutional identity
```

Si el símbolo `restricted_material.read` debe permanecer temporalmente en TypeScript o PostgreSQL por compatibilidad durante la migración, no debe utilizarse para introducir una segunda política de acceso contradictoria.

Su eliminación o redefinición debe realizarse de forma controlada durante Stage 4C.

---

# 7. `student`

El rol:

```text
student
```

se conserva en v1 por compatibilidad y posible semántica futura.

No es necesario poseer `student` para acceder a recursos:

```text
approved + restricted
```

Una identidad institucional activa obtiene dicha audiencia por su clasificación de identidad.

Por tanto, en Stage 4C el rol `student` no debe considerarse la fuente de acceso institucional.

No se elimina todavía para evitar un refactor no relacionado.

---

# 8. `contributor`

Contributor representa capacidad de aportar recursos académicos.

Puede:

* crear recursos;
* editar recursos propios cuando el workflow lo permita;
* subir el archivo principal admitido;
* corregir recursos rechazados propios;
* reenviar recursos;
* proponer metadata;
* proponer `rights_status`;
* proponer audiencia.

Conceptualmente posee:

```text
submission.create
```

Contributor no puede:

* aprobar recursos;
* publicar;
* administrar cuentas;
* administrar roles;
* conceder entitlements.

La audiencia propuesta por Contributor no es vinculante.

---

# 9. `reviewer`

Reviewer participa en la revisión formal.

Puede:

* acceder a recursos `pending`;
* revisar metadata y archivo;
* identificar problemas;
* rechazar cuando la política lo permita;
* registrar observaciones de revisión.

Conceptualmente posee:

```text
submission.create
submission.review
```

Mantener la capacidad de Contributor en Reviewer preserva la jerarquía funcional existente.

Reviewer no puede realizar la publicación final.

No obtiene acceso general a:

```text
draft
rejected
```

ajenos únicamente por poseer el rol.

---

# 10. `moderator`

Moderator es la autoridad editorial ordinaria de FC Academic Hub.

Conceptualmente posee:

```text
submission.create
submission.review
submission.publish
```

Puede:

* revisar recursos `pending`;
* abrir archivos pendientes;
* revisar metadata;
* verificar derechos;
* detectar duplicados;
* aprobar;
* rechazar;
* determinar la audiencia final;
* intervenir en procedimientos editoriales de retiro.

---

# 11. Autoridad del Moderator

El Moderator decide la publicación de recursos, pero no es la máxima autoridad administrativa del software.

Su autoridad principal es:

```text
editorial
```

El Moderator decide:

```text
¿se publica este recurso?
```

y:

```text
¿su audiencia final es
public,
restricted
o privileged?
```

dentro de los derechos aplicables al recurso, incluidas las restricciones estructurales y el alcance de la evidencia documental cuando corresponda.

---

# 12. Límites del Moderator

Moderator no puede:

* aprobar su propio recurso;
* leer drafts ajenos únicamente por su rol;
* leer rejected ajenos únicamente por su rol;
* conceder `privileged_material.read`;
* revocar `privileged_material.read`;
* preautorizar arbitrariamente identidades externas;
* gestionar roles;
* suspender cuentas por autoridad editorial;
* modificar derechos para hacer legal una audiencia que no lo sea.

El Moderator selecciona la audiencia del **recurso**.

No selecciona quién pertenece a la audiencia `privileged`.

---

# 13. Múltiples Moderators

El sistema admite múltiples usuarios con rol:

```text
moderator
```

No existe un límite estructural de dos.

Para el piloto se recomienda mantener:

```text
al menos 2 Moderators activos
```

Esto permite:

* continuidad durante ausencias;
* reparto de carga;
* revisión de recursos pertenecientes a otro Moderator;
* menor dependencia de una única persona.

---

# 14. Aprobación

V1 requiere:

```text
una aprobación válida
```

para aprobar un recurso.

No exige:

```text
2 Moderators
+
2 aprobaciones
```

ni consenso unánime.

Esta decisión evita que la ausencia de uno de dos Moderators bloquee el workflow.

Una futura política de doble aprobación para determinadas clases de material requeriría una modificación explícita del contrato.

---

# 15. Self-approval

Un Moderator puede también poseer capacidades de Contributor.

Eso no significa que pueda aprobar sus propios recursos.

La regla es:

```text
moderator
+
resource.owner = moderator
→ cannot approve own resource
```

Otro Moderator deberá realizar la revisión correspondiente.

Esta es una de las razones operativas para mantener más de un Moderator activo.

---

# 16. `administrator`

Administrator es la autoridad administrativa de la plataforma.

Conceptualmente dispone de:

```text
role.manage
entitlement.manage
external_identity.manage
account.suspend
audit.read
```

y de las capacidades necesarias para intervención administrativa y recuperación.

El modelo actual puede conservar capacidades funcionales acumulativas adicionales, pero Administrator no debe convertirse en el actor editorial ordinario del producto.

El rol `administrator` representa administración dentro de FC Academic Hub.

No equivale conceptualmente a la custodia de infraestructura externa como:

```text
GitHub
Cloudflare
Supabase
deployment
secrets
```

La misma persona puede ejercer ambas responsabilidades, especialmente durante la etapa inicial, pero `App Administrator` e `Infrastructure Custodian` son responsabilidades distintas y pueden separarse posteriormente sin modificar el modelo de roles.

---

# 17. Responsabilidades del Administrator

Administrator puede:

* asignar roles;
* revocar roles;
* gestionar Moderators;
* conceder entitlements;
* revocar entitlements;
* gestionar la admisión de identidades externas;
* suspender cuentas;
* deshabilitar cuentas;
* responder a incidentes;
* consultar información de auditoría;
* realizar intervenciones administrativas excepcionales.

---

# 18. Administrator y publicación

El workflow ordinario es:

```text
Contributor
    ↓
Reviewer / Moderator
    ↓
Moderator publishes
```

Administrator conserva las capacidades excepcionales necesarias para:

* recuperación;
* incidentes;
* administración;
* mantenimiento.

Pero la interfaz y los procesos normales no deben convertir Administrator en el sustituto diario de Moderator.

---

# 19. Gobierno de los roles superiores

El modelo de software distingue las responsabilidades:

```text
Moderator
-> autoridad editorial operativa

Administrator
-> autoridad administrativa de la aplicación

Infrastructure Custodian
-> custodia de infraestructura externa
```

La asignación organizacional concreta de estas responsabilidades no forma parte del modelo de autorización.

El rol `administrator` y la función `Infrastructure Custodian` son conceptos diferentes aunque una misma persona pueda ejercer ambos.

Toda persona que reciba un rol interno debe cumplir:

```text
identity_kind = institutional
account_status = active
```

La designación, transferencia y continuidad institucional de estas responsabilidades se documentan separadamente en:

```text
docs/operations/governance.md
```

---

# 20. Acceso administrativo excepcional

Administrator puede acceder a:

```text
draft
pending
rejected
approved
```

cuando sea necesario para funciones administrativas legítimas.

Esta capacidad es una excepción de gobierno y seguridad.

No representa una audiencia ordinaria del recurso.

Las acciones administrativas sensibles deben ser auditables.

---

# 21. Jerarquía funcional

V1 puede conservar la jerarquía funcional:

```text
student
   ↓
contributor
   ↓
reviewer
   ↓
moderator
```

en aquellas capacidades editoriales donde tenga sentido.

Por ejemplo:

```text
contributor
→ submission.create

reviewer
→ submission.create
→ submission.review

moderator
→ submission.create
→ submission.review
→ submission.publish
```

Esta jerarquía no se utiliza para determinar:

```text
restricted access
privileged access
```

---

# 22. No usar jerarquía numérica para autorización

Aunque algunos roles acumulen capacidades, la implementación no debe asumir comparaciones numéricas como:

```text
role >= moderator
```

La autorización debe utilizar conjuntos explícitos de capacidades o funciones controladas.

Esto evita convertir accidentalmente una jerarquía organizativa en una regla universal de autorización.

---

# 23. Entitlements

Los entitlements son independientes de roles.

V1 define:

```text
privileged_material.read
```

Un entitlement debe:

* asignarse explícitamente;
* asociarse a `user_id`;
* ser revocable;
* ser auditable.

---

# 24. `privileged_material.read`

Este entitlement permite consumir:

```text
approved + privileged
```

cuando la cuenta está activa.

No concede:

```text
submission.create
submission.review
submission.publish
role.manage
account.suspend
```

---

# 25. Usuario externo privilegiado

Es válido:

```text
identity_kind = external_authorized
account_status = active
privileged_material.read = active
roles = none
```

Ese usuario puede:

```text
approved/public
→ read

approved/privileged
→ read
```

pero:

```text
approved/restricted
→ deny
```

y tampoco puede:

* contribuir;
* revisar;
* publicar;
* administrar.

---

# 26. Usuario institucional privilegiado

También es válido:

```text
identity_kind = institutional
account_status = active
privileged_material.read = active
```

Resultado:

```text
approved/public
→ allow

approved/restricted
→ allow

approved/privileged
→ allow
```

independientemente de que posea un rol editorial.

---

# 27. Moderator sin entitlement

Un Moderator no necesita necesariamente:

```text
privileged_material.read
```

para ejercer sus responsabilidades editoriales sobre recursos que debe moderar.

El acceso editorial del Moderator se deriva del workflow y su rol, no de pertenecer a la audiencia privileged ordinaria.

Esto evita mezclar:

```text
audiencia de consumo
```

con:

```text
autoridad editorial
```

---

# 28. Administrator sin entitlement

Administrator tampoco necesita necesariamente un entitlement para ejecutar una intervención administrativa legítima.

Su acceso excepcional se deriva de su autoridad administrativa.

No debe asignarse artificialmente:

```text
privileged_material.read
```

solo para poder administrar el sistema.

---

# 29. Gestión de roles

Los clientes no tienen `INSERT`, `UPDATE` ni `DELETE` directo sobre las asignaciones de roles.

El baseline implementado utiliza operaciones equivalentes a:

```text
grant_user_role(target_user_id, role, reason)
revoke_user_role(target_user_id, role, reason)
```

La operación identifica al actor mediante:

```text
auth.uid()
```

El cliente no proporciona libremente:

```text
granted_by
revoked_by
```

---

# 30. Autoridad para gestionar roles

En v1:

```text
Administrator
```

es el único rol que puede conceder y revocar roles de aplicación.

No pueden hacerlo:

```text
Moderator
Reviewer
Contributor
Student
```

Ningún usuario puede autoasignarse un rol.

---

# 31. Gestión de Moderators

Moderator no puede crear otro Moderator.

La asignación o revocación del rol:

```text
moderator
```

corresponde a Administrator.

Esto mantiene una separación entre:

```text
autoridad editorial
```

y:

```text
gobierno administrativo
```

---

# 32. Gestión de entitlements

La gestión de:

```text
privileged_material.read
```

corresponde en v1 a Administrator.

Conceptualmente deben existir operaciones controladas equivalentes a:

```text
grant entitlement
revoke entitlement
```

que obtengan al actor mediante:

```text
auth.uid()
```

y no permitan al cliente falsificar el administrador responsable.

---

# 33. Historial de entitlements

La asignación debe conservar conceptualmente:

```text
user_id
entitlement
granted_by
granted_at
revoked_by
revoked_at
reason
```

No es obligatorio que la estructura SQL use exactamente esos nombres, pero debe permitir auditoría y revocación confiables.

---

# 34. No autoentitlements

La creación de una cuenta no concede automáticamente:

```text
privileged_material.read
```

Esto aplica tanto a:

```text
institutional
```

como:

```text
external_authorized
```

---

# 35. Admisión externa y roles

La admisión de una identidad externa no constituye un rol.

```text
preauthorized external identity
        ↓
external_authorized account
```

En v1, esa cuenta no puede recibir ningún rol interno, ni automáticamente ni mediante concesión administrativa.

Puede recibir únicamente entitlements explícitos admitidos por el producto, actualmente:

```text
privileged_material.read
```

---

# 36. Ownership

Los roles no eliminan el concepto de ownership.

Contributor puede gestionar:

```text
sus propios recursos
```

en estados permitidos.

El hecho de que Reviewer o Moderator hereden conceptualmente `submission.create` no les permite editar recursos ajenos arbitrariamente.

La autorización combina:

```text
role
+
ownership
+
review_status
```

---

# 37. Workflow y acceso a recursos

Los roles intervienen en el workflow según sus responsabilidades, pero este documento no redefine las matrices de acceso.

La fuente normativa para:

```text
draft
pending
rejected
approved
public
restricted
privileged
ownership
```

es:

```text
docs/architecture/resource-access-contract.md
```

Los roles definidos aquí no crean excepciones adicionales a ese contrato.

---

# 38. Rights y roles

Un rol editorial no puede ampliar los derechos legales o institucionales del recurso.

Por ejemplo:

```text
Moderator
```

puede seleccionar la audiencia final, pero no puede transformar:

```text
rights_status = institutional
```

en autorización para:

```text
public
```

cuando la política de derechos lo prohíbe.

---

# 39. Auditoría de roles

El baseline existente utiliza:

```text
public.role_audit_log
```

para registrar:

```text
grant
revoke
```

de roles.

Los clientes no deben poder modificar directamente entradas históricas de auditoría.

El patrón append-only debe conservarse.

---

# 40. Auditoría de entitlements

Stage 4C debe proporcionar una capacidad equivalente de auditoría para:

```text
grant privileged_material.read
revoke privileged_material.read
```

Como mínimo debe poder conocerse:

* destinatario;
* acción;
* actor;
* fecha;
* razón.

---

# 41. Auditoría administrativa

También deben poder auditarse según corresponda:

* admisión de identidad externa;
* revocación de dicha admisión;
* cambio administrativo de tipo de identidad;
* suspensión;
* deshabilitación;
* reactivación;
* cambios de Moderator.

---

# 42. Roles enviados por navegador

Nunca se confía en datos como:

```text
role = moderator
```

proporcionados por:

* formulario;
* JSON;
* query string;
* localStorage;
* metadata OAuth manipulable.

Los roles efectivos se resuelven desde PostgreSQL.

---

# 43. Entitlements enviados por navegador

La misma regla aplica a:

```text
privileged_material.read = true
```

enviado por el cliente.

No tiene valor autoritativo.

El entitlement debe existir como grant activo en la fuente de datos controlada.

---

# 44. No roles automáticos

La creación automática de:

```text
public.profiles
```

desde:

```text
auth.users
```

no asigna automáticamente ningún rol.

No existe:

```text
automatic student
automatic contributor
automatic moderator
automatic administrator
```

salvo que una futura política aceptada modifique expresamente esta decisión.

Para `external_authorized`, la restricción es más fuerte: los roles internos no solo dejan de asignarse automáticamente, sino que son combinaciones inválidas en v1.

---

# 45. No Administrator automático

En particular, no debe crearse un Administrator automáticamente:

* por ser el primer usuario;
* por dominio de correo;
* por metadata OAuth;
* por variable enviada por navegador.

El bootstrap administrativo debe utilizar un procedimiento explícito y controlado.

---

# 46. Matriz conceptual objetivo

La matriz de responsabilidades objetivo es:

| Rol             |                     Crear recursos | Revisar `pending` |    Publicar | Gestionar roles | Gestionar entitlements | Gestionar cuentas |
| --------------- | ---------------------------------: | ----------------: | ----------: | --------------: | ---------------------: | ----------------: |
| `student`       |                                 No |                No |          No |              No |                     No |                No |
| `contributor`   |                                 Sí |                No |          No |              No |                     No |                No |
| `reviewer`      |                                 Sí |                Sí |          No |              No |                     No |                No |
| `moderator`     |                                 Sí |                Sí |          Sí |              No |                     No |                No |
| `administrator` | Excepcional / según implementación |       Excepcional | Excepcional |              Sí |                     Sí |                Sí |

La palabra `Excepcional` para Administrator indica capacidad de gobierno y recuperación, no el flujo editorial ordinario.

---

# 47. Invariantes normativas

## RM-01 — Roles represent responsibilities

Los roles describen responsabilidades dentro del workflow y gobierno del sistema.

---

## RM-02 — Identity is not role

Ser institucional o externo autorizado no constituye un rol.

---

## RM-03 — Audience is not role

`restricted` y `privileged` no son roles.

---

## RM-04 — Restricted by identity

El acceso ordinario `restricted` depende de identidad institucional activa, no de `student`.

---

## RM-05 — Privileged by entitlement

El acceso ordinario `privileged` depende de `privileged_material.read`.

---

## RM-06 — Entitlement is not editorial role

`privileged_material.read` no concede capacidades de contribución, revisión o publicación.

---

## RM-07 — Administrator manages roles

Solo Administrator gestiona roles en v1.

---

## RM-08 — Administrator manages entitlements

Solo Administrator concede o revoca `privileged_material.read` en v1.

---

## RM-09 — Moderator is editorial authority

Moderator decide aprobación y audiencia final dentro de los derechos permitidos.

---

## RM-10 — Moderator cannot self-approve

Moderator no puede aprobar su propio recurso.

---

## RM-11 — Moderator cannot manage audience membership

Moderator puede clasificar un recurso como `privileged`, pero no decide qué cuentas reciben el entitlement.

---

## RM-12 — Draft isolation

Reviewer y Moderator no pueden leer drafts ajenos solamente por su rol.

---

## RM-13 — Rejected isolation

Reviewer y Moderator no conservan acceso general a rejected ajenos.

---

## RM-14 — Pending review

Reviewer y Moderator pueden acceder a recursos `pending` para realizar revisión.

---

## RM-15 — Administrator exceptional access

Administrator puede ejercer acceso excepcional para gobierno, incidentes y recuperación.

---

## RM-16 — No automatic grants

Crear una identidad no asigna automáticamente roles ni entitlements.

---

## RM-17 — Server authority

Roles y entitlements se resuelven desde fuentes server-side confiables.

---

## RM-18 — Auditability

Grants y revocaciones sensibles deben ser auditables.

## RM-19 — Internal roles require institutional identity

En v1, todos los roles internos requieren una identidad institucional activa.

Una identidad `external_authorized` no puede poseer roles.

---

## RM-20 — Organizational governance is separate

El modelo de roles define responsabilidades técnicas y editoriales, pero no determina qué organización o cargo institucional designa permanentemente a sus titulares.

La política de designación, transferencia y recuperación se define en:

```text
docs/operations/governance.md
```

---

# 48. Pruebas normativas de roles

Stage 4C debe demostrar como mínimo:

```text
contributor
-> create own resource
-> cannot review other pending
-> cannot publish
```

```text
reviewer
-> review pending
-> cannot publish
```

```text
moderator
-> review pending
-> publish valid pending
-> cannot approve own resource
```

```text
moderator
+ other owner's draft
-> deny
```

```text
moderator
+ other owner's rejected
-> deny
```

---

# 49. Pruebas de Administrator

Debe comprobarse:

```text
administrator
-> grant role
-> revoke role
```

```text
non-administrator
-> grant role
-> deny
```

```text
administrator
-> grant privileged_material.read
-> revoke privileged_material.read
```

```text
moderator
-> grant privileged_material.read
-> deny
```

---

# 50. Pruebas de independencia entre rol y audience

```text
external_authorized + student
-> invalid

external_authorized + contributor
-> invalid

external_authorized + reviewer
-> invalid

external_authorized + moderator
-> invalid

external_authorized + administrator
-> invalid

external_authorized + privileged_material.read
-> valid
```

Ejemplo:

```text
external_authorized
+
privileged_material.read
+
roles = none
```

debe:

```text
read approved/privileged -> allow
read approved/restricted -> deny
create -> deny
review -> deny
publish -> deny
```

---

Otro ejemplo:

```text
institutional
+
roles = none
```

debe:

```text
read approved/restricted -> allow
read approved/privileged -> deny
```

---

# 51. Pruebas de Moderator y entitlement

```text
moderator
+
no privileged_material.read
+
approved/privileged
```

puede requerir acceso por su función editorial o administrativa definida en el contrato de recursos.

La implementación no debe resolver ese caso concediendo artificialmente un entitlement permanente al Moderator.

---

# 52. Non-goals v1

Este modelo no introduce:

* roles personalizados por usuario;
* creación arbitraria de nuevos roles;
* ACL por recurso;
* grupos privileged múltiples;
* permisos resource-specific;
* doble aprobación obligatoria;
* Moderator gestionando cuentas;
* Moderator gestionando entitlements;
* roles derivados automáticamente del email;
* entitlements derivados automáticamente del email;
* jerarquía numérica universal de roles;
* autorización basada exclusivamente en frontend.

---

# 53. Relación con otros documentos

La identidad y admisión se definen en:

```text
docs/architecture/authentication-and-authorization.md
```

La política exacta de acceso a recursos se define en:

```text
docs/architecture/resource-access-contract.md
```

La política de archivos se define en:

```text
docs/architecture/resource-file-policy.md
```

El workflow transaccional de subida se define en:

```text
docs/architecture/resource-upload-contract.md
```

El alcance de producto se define en:

```text
docs/product/v1-product-contract.md
```

Este documento no debe duplicar esas políticas más allá de lo necesario para definir responsabilidades de roles y entitlements.

---

# 54. Regla de implementación

Codex debe preservar la separación:

```text
identity
≠
role
≠
entitlement
≠
resource audience
```

No debe resolver problemas de autorización concediendo un rol más alto cuando únicamente se necesita un entitlement.

No debe resolver acceso institucional mediante el rol `student`.

No debe conceder `privileged_material.read` a Moderator o Administrator únicamente para que puedan ejercer responsabilidades editoriales o administrativas.

Cualquier cambio que introduzca:

* nuevos roles;
* nuevos entitlements;
* nuevas capacidades;
* nueva jerarquía;

requiere primero modificar y aceptar este contrato.
