# TukTuk Cliente Lite — fase 4 (integración operativa provisional)

## Alcance

TukTuk Cliente Lite se desarrolla **ahora**, sin esperar a construir el futuro módulo administrativo de carreras reales. El Cliente todavía no tiene usuarios y es el momento de hacer pruebas integradas. Esta fase no integra ni despliega código y no crea carreras automáticamente.

- **Buena conexión:** versión completa siempre optimizada; la oferta Lite no aparece.
- **Conexión débil:** la pantalla de arranque ofrece **«Modo Lite por WhatsApp»**. Si el cliente elige Lite, se comprueba la configuración pública de Admin.
- **Soporte habilitado y con número válido:** formulario ligero sin Flutter, Firebase, mapas ni GPS.
- **Soporte deshabilitado, consulta fallida o número inválido:** vuelve automáticamente a la versión completa.
- **Comprobación obligatoria:** se vuelve a consultar el número directamente a Supabase **antes de abrir WhatsApp**. Nunca se envía a un número en caché.
- **Sin Internet:** el modo completo conserva sus mecanismos de reintento; WhatsApp tampoco funciona sin red.
- No se interrumpe una carrera activa: se ofrece desde el splash de arranque, no se fuerza una redirección de la aplicación en uso.

## Reutilización dinámica de WhatsApp

El número se toma de `public.get_public_whatsapp_settings(target_project_id uuid)`, función pública ya existente en Supabase. Se utiliza la propiedad `support.number` cuando `support.enabled=true` — hoy es el mismo número que para pagos. **No se codifica ningún número real.** No se usa el número de pagos como sustituto si soporte está deshabilitado.

La configuración pública para el navegador se genera **solo durante el build web de GitHub Actions** en `lite/config.json` mediante `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` y el ID público del proyecto TukTuk. No se requiere ninguna clave `service_role` y ninguna nueva tabla/función. Las claves publicables se mantienen fuera del código fuente. Al ejecutar los tests locales, se simulan las llamadas HTTP con datos sintéticos.

## Limitación de horarios / disponibilidad real (pendiente de evolución)

La configuración actual de soporte y pagos **no contiene turnos ni presencia real de operadores**. Durante esta fase de pruebas, `support.enabled` funciona como un interruptor **manual y provisional** de disponibilidad del canal WhatsApp. Mientras esté habilitado no hay garantía automática de atención humana; la interfaz lo explica. Para pausas, almuerzo y noche se debe configurar manualmente el estado del canal. Más adelante se añadirá un control específico de turnos y estado de operadores, sin modificar el número actual.

## Carrera / flujo manual

El cliente prepara el mensaje con nombre, teléfono, servicio, origen, destino y notas, confirma consentimiento y abre WhatsApp. **Debe pulsar «Enviar»**. La solicitud queda pendiente de respuesta humana: no equivale a reserva, tarifa confirmada ni carrera creada. El Admin actual permite **carreras de prueba**; NO se debe usar ese módulo como publicador de carreras reales. Ese flujo administrativo se implementará como siguiente etapa sin impedir las pruebas del canal Lite.

## Seguridad y rendimiento

- No se almacenan datos de cliente en caché, almacenamiento local ni analítica desde Lite.
- No se utiliza Firebase, Mapbox ni Flutter en Lite.
- Consultas públicas con `cache:'no-store'` y tiempo límite de 7,5 segundos.
- No se expone credencial de servicio; únicamente se utiliza la clave publicable ya suministrada al Cliente completo.
- Los errores de red impiden abrir WhatsApp con un contacto no verificado.
- No se hace push, merge, deploy, migración SQL ni APK por este instalador.

## Fase 5: una sola experiencia y una sola entrada

- La URL pÃºblica del cliente es siempre `/cliente/tuk/`. No hay dos apps distintas.
- Antes de arrancar Flutter, el navegador identifica si la conexiÃ³n es lenta. Si lo es, accede al formulario Lite, sin descargar el paquete Flutter de la pantalla completa.
- Lite consulta el mismo nÃºmero dinÃ¡mico de soporte del Admin. Si estÃ¡ deshabilitado, no existe o la consulta falla, retorna automÃ¡ticamente a Completa con `?lite=unavailable`, evitando bucles.
- Buena conexiÃ³n o calidad desconocida: Completa optimizada. `?mode=full` permite regresar a Completa voluntariamente.
- Para probar ambos modos desde una Ãºnica URL: inicio normal y `?preview=lite` en la misma entrada. El parÃ¡metro de prueba nunca envÃ­a carreras automÃ¡ticamente.
- La navegaciÃ³n solo ocurre antes del arranque; no se cambia una carrera ya activa.
- `support.enabled` es solo un control manual provisional, NO verifica horarios ni presencia humana. La gestiÃ³n de turnos sigue pendiente.