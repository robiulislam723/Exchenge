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

mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/file_paths.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
    <files-path name="files" path="." />
    <external-path name="external" path="." />
</paths>
XML

grep -n "uses-permission\|FileProvider" "$manifest" || true
flutter pub get
