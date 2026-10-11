# TUKTUK Cliente — elTOQUE, fase 2 (preparación SIN DESPLIEGUE)

## Decisión funcional

- Avisar por cambio real detectado por la sincronización automática de Supabase, no a una hora fija.
- No requiere suscripción de pago ni registro con nombre/correo/contraseña.
- Consentimiento explícito por dispositivo; poder desactivar las notificaciones.
- Barra visible de fase 1 siempre presente, manteniendo los seis pasos y mapas.
- En Cliente Web/PWA se usa Firebase Web Push y service worker en `/cliente/tuk/`; Android APK no forma parte de esta fase.

## Implementación preparada

- Cliente: dependencias Firebase, inicialización web tolerante a errores, indicador en la barra expandida, opt-in/opt-out, token de dispositivo, recuperación y pruebas.
- Backend: proyecto independiente de Edge Function `marketplace-customer-rate-push`, sin modificar el trabajador de Conductor.
- SQL: tablas segregadas y protegidas con RLS sin acceso anónimo, cola única por `subscription_id + rate_history_id`, trigger solo para cambios automáticos auténticos de elTOQUE, batch con bloqueo para evitar reclamaciones simultáneas.
- Credenciales: cuenta de servicio Firebase y clave de despacho solo mediante secretos en Edge; el cliente contiene únicamente configuración pública Firebase/VAPID.
- Cron: propuesta independiente cada 5 minutos, NO activada. La consulta del proveedor hoy es cada hora.

## Requisitos previos obligatorios antes de integrar/publicar

1. Revisar que el token del mismo proyecto Firebase admite el origen `www.vrixora.com` y que el service worker está limitado a `/cliente/tuk/`.
2. Auditar el rate limiting y abuso de registro anónimo; el origen del navegador por sí solo no es una prueba de identidad. Habilitar límites perimetrales o por sesión/IP antes de producción.
3. Revisar todas las grants y RLS de las nuevas tablas, especialmente `service_role` y ausencia de permisos `anon`.
4. Migrar SQL al repositorio propietario `vrixora-admin-canvas` y probar primero su esquema; NO copiar SQL de docs directamente a producción.
5. Desplegar la Edge Function con secretos correctos; comprobar suscripciones válidas e inválidas, revocación, caída temporal de FCM y cola.
6. Configurar el cron de despacho solamente después de validar la función; verificar ausencia de avisos duplicados.
7. Pruebas reales navegador Android: primer permiso, denegación, WebApp en segundo plano/cerrada, cambio real y desactivación.
8. Solo entonces solicitar aprobación expresa para merge a main y publicación del Worker Cliente.

## Advertencias

- Un servicio push de tipo `at least once` no garantiza entrega exacta ni recepción instantánea; puede haber reintentos o condiciones del SO/navegador.
- El token de navegador debe tratarse como sensible. El cliente almacena una clave secreta aleatoria únicamente en su almacenamiento local y el servidor almacena solo su hash.
- La tasa es referencial y NO se utiliza para recalcular el precio de las carreras.
- El registro sin identidad obligatoria necesita limitación de abusos antes de la fase de producción.
