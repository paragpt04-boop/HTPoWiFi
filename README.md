# HTPoWiFi

Gestor de Hotspot MikroTik para Android. Administra usuarios, sesiones activas y tarjetas prepago del Hotspot de tu RouterOS v7 desde el celular.

## Funciones

- **Dashboard** — Stats del hotspot en tiempo real (usuarios, conectados, expirados)
- **Usuarios** — Crear, editar, eliminar, habilitar/deshabilitar, reiniciar tiempo
- **Sesiones activas** — Ver quién está conectado con tráfico, IP, MAC — desconectar individual o masivo
- **Generador de tarjetas** — Crear usuarios en lote con tiempo limitado, copiar al portapapeles

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
