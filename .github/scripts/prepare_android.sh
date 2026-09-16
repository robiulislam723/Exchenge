#!/usr/bin/env bash
set -euo pipefail

# Preserve our pubspec.yaml and lib/ across `flutter create`.
cp pubspec.yaml /tmp/pubspec.yaml
cp -r lib /tmp/lib_backup

if [ ! -d "android" ]; then
  flutter create --project-name exchenge_mobile --platforms=android .
fi

cp /tmp/pubspec.yaml pubspec.yaml
rm -rf lib
cp -r /tmp/lib_backup lib

manifest=android/app/src/main/AndroidManifest.xml

# Launcher / app name shown on the device.
sed -i 's#android:label="[^"]*"#android:label="Exchange"#' "$manifest"

# Permissions: internet, camera/gallery uploads, and in-app APK installs.
add_permission() {
  local perm="$1"
  if ! grep -q "android.permission.${perm}" "$manifest"; then
    sed -i "s#<application#<uses-permission android:name=\"android.permission.${perm}\"/>\n    <application#" "$manifest"
  fi
}

add_permission INTERNET
add_permission ACCESS_NETWORK_STATE
add_permission READ_MEDIA_IMAGES
add_permission REQUEST_INSTALL_PACKAGES

if ! grep -q "androidx.core.content.FileProvider" "$manifest"; then
  provider='        <provider\n            android:name="androidx.core.content.FileProvider"\n            android:authorities="${applicationId}.fileprovider"\n            android:exported="false"\n            android:grantUriPermissions="true">\n            <meta-data\n                android:name="android.support.FILE_PROVIDER_PATHS"\n                android:resource="@xml/file_paths" />\n        </provider>\n    </application>'
  sed -i "s#</application>#${provider}#" "$manifest"
fi

# pasteboard plugin needs its own FileProvider authority (${applicationId}.provider).
if ! grep -q "applicationId}.provider" "$manifest"; then
  provider2='        <provider\n            android:name="androidx.core.content.FileProvider"\n            android:authorities="${applicationId}.provider"\n            android:exported="false"\n            android:grantUriPermissions="true">\n            <meta-data\n                android:name="android.support.FILE_PROVIDER_PATHS"\n                android:resource="@xml/provider_paths" />\n        </provider>\n    </application>'
  sed -i "s#</application>#${provider2}#" "$manifest"
fi

mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/file_paths.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
    <files-path name="files" path="." />
    <external-path name="external" path="." />
</paths>
XML

cat > android/app/src/main/res/xml/provider_paths.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="cache" path="." />
    <files-path name="files" path="." />
    <external-path name="external" path="." />
</paths>
XML

# MainActivity: expose a native method channel so Dart can flush WebView
# cookies to disk on app pause (keeps the Laravel session alive), AND keep an
# extra copy of the cookies in SharedPreferences so a hard process kill can
# never drop the login session.
main_activity=$(find android/app/src/main -name MainActivity.kt | head -1)
if [ -n "$main_activity" ]; then
  pkg=$(grep -oE '^package[[:space:]]+[^[:space:]]+' "$main_activity" | awk '{print $2}')
  cat > "$main_activity" <<KT
package ${pkg}

import android.content.Context
import android.os.Bundle
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "app/cookies"
    private val prefsName = "webview_session"
    private val cookieKey = "cookies"
    private val cookieUrl = "https://exchenge.narailexpress.net"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        restoreCookies()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        restoreCookies()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "flush" -> {
                        try {
                            saveCookies()
                            CookieManager.getInstance().flush()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("flush_failed", e.message, null)
                        }
                    }
                    "sessionStatus" -> {
                        val cookie = try {
                            CookieManager.getInstance().getCookie(cookieUrl) ?: ""
                        } catch (e: Exception) { "" }
                        val backup = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                            .getString(cookieKey, null) ?: ""
                        result.success(mapOf(
                            "hasSession" to cookie.contains("laravel_session"),
                            "hasBackup" to backup.contains("laravel_session"),
                            "cookieLength" to cookie.length
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPause() {
        saveCookies()
        CookieManager.getInstance().flush()
        super.onPause()
    }

    override fun onStop() {
        saveCookies()
        CookieManager.getInstance().flush()
        super.onStop()
    }

    /** Keep a copy of the WebView cookies outside the WebView store. */
    private fun saveCookies() {
        try {
            val cookie = CookieManager.getInstance().getCookie(cookieUrl) ?: return
            if (cookie.isBlank()) return
            getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit().putString(cookieKey, cookie).apply()
        } catch (_: Exception) {}
    }

    /** Put the saved cookies back before the first page load. */
    private fun restoreCookies() {
        try {
            val cm = CookieManager.getInstance()
            cm.setAcceptCookie(true)

            val existing = cm.getCookie(cookieUrl) ?: ""
            val saved = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getString(cookieKey, null) ?: return
            if (saved.isBlank()) return

            var restored = 0
            for (part in saved.split(";")) {
                val kv = part.trim()
                if (kv.isEmpty() || !kv.contains("=")) continue
                val name = kv.substringBefore("=").trim()
                if (name.isEmpty()) continue
                // Only fill in cookies the WebView cookie store has lost.
                if (existing.contains("\$name=")) continue
                cm.setCookie(cookieUrl, "\$kv; path=/; domain=exchenge.narailexpress.net; Secure")
                restored++
            }
            if (restored > 0) cm.flush()
        } catch (_: Exception) {}
    }
}
KT
fi

# ---------------------------------------------------------------------------
# Stable release signing.
# Without a fixed keystore every CI build is signed with a different debug key,
# so installing an update forces an uninstall — which wipes app data (cookies)
# and logs the user out. Signing every build with the same keystore lets
# updates install in place and keeps the session.
# Handles both the Groovy (build.gradle) and Kotlin (build.gradle.kts) DSL, and
# fails the build if the wiring could not be applied.
# ---------------------------------------------------------------------------
if [ ! -f signing/release.jks ]; then
  echo "ERROR: signing/release.jks missing — refusing to publish a debug-signed APK"
  exit 1
fi

cp signing/release.jks android/app/release.jks
cp signing/key.properties android/key.properties

python3 - <<'PY'
import os
import sys

def die(msg):
    sys.stderr.write('ERROR: ' + msg + '\n')
    raise SystemExit(1)

def wire_groovy(path):
    s = open(path).read()
    if 'signingConfigs {' not in s:
        loader = (
            "\ndef keystoreProperties = new Properties()\n"
            "def keystorePropertiesFile = rootProject.file('key.properties')\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
            "}\n"
        )
        s = s.replace('android {', loader + '\nandroid {', 1)
        signing = (
            "    signingConfigs {\n"
            "        release {\n"
            "            keyAlias keystoreProperties['keyAlias']\n"
            "            keyPassword keystoreProperties['keyPassword']\n"
            "            storeFile file(keystoreProperties['storeFile'])\n"
            "            storePassword keystoreProperties['storePassword']\n"
            "        }\n"
            "    }\n\n"
        )
        s = s.replace('    buildTypes {', signing + '    buildTypes {', 1)
    # Flutter templates use either the method or the assignment syntax.
    s = s.replace('signingConfig = signingConfigs.debug',
                  'signingConfig = signingConfigs.release')
    s = s.replace('signingConfig signingConfigs.debug',
                  'signingConfig signingConfigs.release')
    open(path, 'w').write(s)

def wire_kts(path):
    s = open(path).read()
    if 'import java.util.Properties' not in s:
        s = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + s
    if 'create("release")' not in s:
        loader = (
            "\nval keystoreProperties = Properties()\n"
            "val keystorePropertiesFile = rootProject.file(\"key.properties\")\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
            "}\n"
        )
        s = s.replace('android {', loader + '\nandroid {', 1)
        signing = (
            "    signingConfigs {\n"
            "        create(\"release\") {\n"
            "            keyAlias = keystoreProperties[\"keyAlias\"] as String\n"
            "            keyPassword = keystoreProperties[\"keyPassword\"] as String\n"
            "            storeFile = file(keystoreProperties[\"storeFile\"] as String)\n"
            "            storePassword = keystoreProperties[\"storePassword\"] as String\n"
            "        }\n"
            "    }\n\n"
        )
        s = s.replace('    buildTypes {', signing + '    buildTypes {', 1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")',
                  'signingConfig = signingConfigs.getByName("release")')
    open(path, 'w').write(s)

g = 'android/app/build.gradle'
k = 'android/app/build.gradle.kts'

if os.path.isfile(g):
    wire_groovy(g)
    blob = open(g).read()
    if 'signingConfigs.debug' in blob:
        die('groovy build.gradle still points the release build at signingConfigs.debug')
    if 'signingConfigs.release' not in blob:
        die('groovy build.gradle has no release signing config')
    print('release signing WIRED (groovy)')
elif os.path.isfile(k):
    wire_kts(k)
    blob = open(k).read()
    if 'getByName("debug")' in blob:
        die('kotlin build.gradle.kts still points the release build at debug')
    if 'create("release")' not in blob:
        die('kotlin build.gradle.kts has no release signing config')
    print('release signing WIRED (kotlin)')
else:
    die('no android/app/build.gradle[.kts] found')
PY

grep -n "uses-permission\|FileProvider" "$manifest" || true
flutter pub get
