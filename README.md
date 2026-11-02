# HTPoWiFi

Gestor de Hotspot MikroTik para Android. Administra usuarios, sesiones activas y tarjetas prepago del Hotspot de tu RouterOS v7 desde el celular.

## Funciones

- **Dashboard** — Stats del hotspot en tiempo real (usuarios, conectados, expirados)
- **Usuarios** — Crear, editar, eliminar individualmente o por selección, habilitar/deshabilitar, reiniciar tiempo. Expirados separados por perfil.
- **Sesiones activas** — Ver quién está conectado con tráfico, IP, MAC — desconectar individual o masivo
- **Generador de tarjetas** — Crear usuarios en lote con tiempo limitado, copiar al portapapeles
- **Contabilidad** — Registra el primer uso de cada tarjeta, calcula ingresos a 150 pesos/hora para `default` y 250 pesos/hora para `Premium` (ambos editables), horas y usuarios por día contable desde las 7:00 a. m. Consulta 24, 48 y 72 horas, 7 y 30 días; permite corregir una tarjeta o los totales del día.

## Contabilidad y primer uso

Desde **Contabilidad → Activar**, la aplicación instala el scheduler independiente `htpowifi-first-use` en el router. Cada minuto marca `[ACC:fecha hora]` en el comentario de un usuario cuando este empieza a consumir tiempo. Así se conserva la fecha si el teléfono está apagado. No modifica los perfiles Hotspot ni el lector REST de la aplicación. Antes de activarlo, los usuarios que ya consumieron tiempo reciben `[ACC:?]` y no se cuentan como ingresos nuevos.

Los registros contables se guardan **solo en este teléfono**. Se sincronizan al abrir la aplicación, al volver a ella y cada minuto mientras está abierta. Si un usuario se borra, renueva o reinicia directamente en el router antes de que el teléfono vuelva a sincronizar, su primer uso anterior puede faltar en el historial local. La fecha del router debe estar correcta (NTP). Los cambios de tarifa se aplican a registros nuevos; los anteriores conservan el precio registrado.

## Requisitos

- MikroTik con RouterOS v7 (REST API habilitada por defecto)
- El celular debe tener acceso a la IP del router
- Puerto 80 (HTTP) o 443 (HTTPS) abierto en el router

## Habilitar REST API en RouterOS

La REST API viene habilitada por defecto en RouterOS v7. Verifica que el servicio `www` esté activo:

```
/ip/service print
```

Si `www` está deshabilitado:

```
/ip/service enable www
```

## Compilar

```bash
flutter pub get
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`

## Autor

JSUS — [@paragpt04-boop](https://github.com/paragpt04-boop)
