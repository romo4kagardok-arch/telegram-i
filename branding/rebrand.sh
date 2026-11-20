#!/usr/bin/env bash
# Rebrands a teamgram-android checkout into "telegram i".
# Usage: rebrand.sh <path-to-teamgram-android>
# Reads APP_NAME, APP_PACKAGE, SERVER_IP, SERVER_PORT, ABIS from the environment (see config.env).
set -euo pipefail

SRC="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${APP_NAME:?}" "${APP_PACKAGE:?}" "${ABIS:?}"

OLD_PACKAGE="org.chatengine.messenger"
OLD_SERVER_IP="43.155.11.190"
OLD_SERVER_PORT="10443"

cd "$SRC"

echo "== App name: $APP_NAME"
find TMessagesProj/src/main/res -path '*/values*/strings.xml' -print0 | xargs -0 sed -i -E \
  -e "s#<string name=\"AppName\">[^<]*</string>#<string name=\"AppName\">${APP_NAME}</string>#" \
  -e "s#<string name=\"AppNameBeta\">[^<]*</string>#<string name=\"AppNameBeta\">${APP_NAME}</string>#"
grep -h 'name="AppName"' TMessagesProj/src/main/res/values/strings.xml

echo "== Package: $OLD_PACKAGE -> $APP_PACKAGE"
OLD_RE="${OLD_PACKAGE//./\\.}"
grep -rlE "$OLD_RE" \
  --include='*.java' --include='*.kt' --include='*.xml' --include='*.json' \
  --include='*.gradle' --include='*.properties' . \
  | xargs -r sed -i "s/${OLD_RE}/${APP_PACKAGE}/g"
grep -n '^APP_PACKAGE' gradle.properties
if grep -rqE "$OLD_RE" --include='*.java' --include='*.xml' --include='*.json' --include='*.gradle' --include='*.properties' .; then
  echo "::error::old package name is still present"; exit 1
fi

CM=TMessagesProj/jni/tgnet/ConnectionsManager.cpp
if [ -n "${SERVER_IP:-}" ]; then
  echo "== Server: ${SERVER_IP}:${SERVER_PORT:-$OLD_SERVER_PORT}"
  sed -i "s/\"${OLD_SERVER_IP//./\\.}\", ${OLD_SERVER_PORT}/\"${SERVER_IP}\", ${SERVER_PORT:-$OLD_SERVER_PORT}/g" "$CM"
  grep -q "\"${SERVER_IP}\"" "$CM" || { echo "::error::server address was not replaced"; exit 1; }
else
  echo "== Server: SERVER_IP is empty, keeping the default Teamgram test server ${OLD_SERVER_IP}"
fi
grep -n 'addAddressAndPort("' "$CM" | head -2

echo "== ABIs: $ABIS"
ABI_LIST=$(printf '"%s", ' $ABIS); ABI_LIST="${ABI_LIST%, }"
sed -i "s/abiFilters \"armeabi-v7a\", \"arm64-v8a\", \"x86\", \"x86_64\"/abiFilters ${ABI_LIST}/" TMessagesProj_App/build.gradle
# The library module builds native code for every ABI unless told otherwise.
sed -i "0,/minSdkVersion 21/s//minSdkVersion 21\n        ndk { abiFilters ${ABI_LIST} }/" TMessagesProj/build.gradle
grep -n 'abiFilters' TMessagesProj_App/build.gradle TMessagesProj/build.gradle

echo "== Icon"
python3 "$HERE/make_icons.py" "$HERE/icon.webp" TMessagesProj/src/main/res

echo "== Rebrand done"
