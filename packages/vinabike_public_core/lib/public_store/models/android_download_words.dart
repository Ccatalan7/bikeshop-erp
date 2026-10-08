// The team's private Android download (`/cuenta/descargas/android`): what
// the page says. The Flutter page and the HTML store's use these, so a word
// changes in one place (2026-10-08).

const androidDownloadTitle = 'Vinabike ERP para Android';
const androidDownloadLead = 'Descarga privada para el equipo de Viñabike.';

// ================================================================ the way in

const androidDownloadSignInTitle = 'Acceso del equipo';
const androidDownloadEmailLabel = 'Correo';
const androidDownloadPasswordLabel = 'Contraseña';
const androidDownloadSignIn = 'Ingresar';
const androidDownloadSigningIn = 'Ingresando…';
const androidDownloadSignInFailed = 'Correo o contraseña incorrectos.';

String? androidDownloadEmailError(String? value) =>
    (value?.trim() ?? '').contains('@') ? null : 'Ingresa un correo válido.';

String? androidDownloadPasswordError(String? value) =>
    (value?.isNotEmpty ?? false) ? null : 'Ingresa tu contraseña.';

// =============================================================== the release

const androidDownloadUnpublished =
    'La versión Android todavía no está publicada.';
const androidDownloadForbidden =
    'Esta cuenta no tiene acceso a la aplicación interna.';
const androidDownloadLoadFailed = 'No pudimos cargar la versión Android.';
const androidDownloadNone = 'No hay una descarga disponible para esta cuenta.';
const androidDownloadOtherAccount = 'Usar otra cuenta';
const androidDownloadSignOut = 'Salir';
const androidDownloadDefaultSummary = 'Piloto privado para Android.';
const androidDownloadSizeLabel = 'Tamaño';
const androidDownloadCheckLabel = 'Verificación';
const androidDownloadButton = 'Descargar APK';
const androidDownloadFailed = 'No pudimos iniciar la descarga.';
const androidDownloadNote =
    'La primera vez, Android pedirá autorizar instalaciones desde el '
    'navegador. Las siguientes versiones aparecerán dentro de la aplicación.';

String androidDownloadVersion(String name) => 'Versión $name';

/// The download's progress; `Object` so the HTML page can pass `{n}`.
String androidDownloadProgress(Object percent) => 'Descargando $percent%';

/// The APK's size as the page shows it.
String androidDownloadSize(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// The first characters of the APK's SHA-256 the page shows.
String androidDownloadCheck(String sha256) => '${sha256.substring(0, 12)}…';
