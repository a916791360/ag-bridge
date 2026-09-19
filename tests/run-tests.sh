#!/bin/bash

# The launcher is sourced in library mode below. ShellCheck cannot infer that
# the guard returns instead of exiting, or that stub functions are called by
# functions loaded from the sourced file.
# shellcheck disable=SC2317,SC2329

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ag-bridge-tests.XXXXXX")"
trap '/bin/rm -rf "$TEST_TMP"' EXIT

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_file_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if ! /usr/bin/cmp -s "$expected" "$actual"; then
    printf 'FAIL: %s\n' "$message" >&2
    exit 1
  fi
}

/bin/bash -n "$ROOT_DIR/src/ag-bridge"
/usr/bin/plutil -lint "$ROOT_DIR/packaging/Info.plist" >/dev/null

export AG_BRIDGE_LIBRARY_ONLY=1
export AG_BRIDGE_CONFIG_DIR="$TEST_TMP/config"
# shellcheck disable=SC1091
source "$ROOT_DIR/src/ag-bridge"
unset AG_BRIDGE_LIBRARY_ONLY

# 版本号必须与 Info.plist 一致，否则 --version 会撒谎
assert_equal \
  "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/packaging/Info.plist")" \
  "$BRIDGE_VERSION" 'BRIDGE_VERSION matches Info.plist'

for port in 1 80 65535; do
  is_valid_port "$port" || { printf 'FAIL: valid port rejected: %s\n' "$port" >&2; exit 1; }
done
for port in 0 65536 abc ''; do
  if is_valid_port "$port"; then
    printf 'FAIL: invalid port accepted: %s\n' "$port" >&2
    exit 1
  fi
done

assert_equal 160 "$(score_candidate 'macOS 系统代理' http 127.0.0.1 1)" 'system HTTP score'
assert_equal 25 "$(score_candidate Surge socks5 localhost 0)" 'Surge SOCKS score'

add_candidate() {
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"
}

clash_result="$(parse_clash_config Fixture "$ROOT_DIR/tests/fixtures/clash-config.yaml")"
assert_equal $'Fixture|http|127.0.0.1|17890\nFixture|http|127.0.0.1|17891\nFixture|socks5|127.0.0.1|17892' \
  "$clash_result" 'Clash fixture parsing'

surge_result="$(parse_surge_profile "$ROOT_DIR/tests/fixtures/surge-profile.conf")"
assert_equal $'Surge|http|127.0.0.1|16152\nSurge|socks5|0.0.0.0|16153' \
  "$surge_result" 'Surge fixture parsing'

build_proxy_urls http 127.0.0.1 7890
assert_equal 'http://127.0.0.1:7890' "$ENV_PROXY_URL" 'HTTP environment proxy URL'
assert_equal 'http://127.0.0.1:7890' "$CHROMIUM_PROXY_URL" 'HTTP Chromium proxy URL'
build_proxy_urls socks5 localhost 7891
assert_equal 'socks5h://localhost:7891' "$ENV_PROXY_URL" 'SOCKS environment proxy URL'
assert_equal 'socks5://localhost:7891' "$CHROMIUM_PROXY_URL" 'SOCKS Chromium proxy URL'

make_fake_app() {
  local path="$1"
  local bundle_id="$2"
  /bin/mkdir -p "$path/Contents"
  /usr/bin/plutil -create xml1 "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$bundle_id" "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleExecutable -string FakeExec "$path/Contents/Info.plist"
}

# Google 把 Antigravity 拆成了两个 App，两者都必须被接受
FAKE_IDE_APP="$TEST_TMP/Antigravity IDE.app"
make_fake_app "$FAKE_IDE_APP" com.google.antigravity-ide
verify_antigravity_bundle "$FAKE_IDE_APP" \
  || { printf 'FAIL: Antigravity IDE bundle rejected\n' >&2; exit 1; }

FAKE_MANAGER_APP="$TEST_TMP/Antigravity.app"
make_fake_app "$FAKE_MANAGER_APP" com.google.antigravity
verify_antigravity_bundle "$FAKE_MANAGER_APP" \
  || { printf 'FAIL: Antigravity agent manager bundle rejected\n' >&2; exit 1; }

FAKE_OTHER_APP="$TEST_TMP/Unrelated.app"
make_fake_app "$FAKE_OTHER_APP" com.example.unrelated
if verify_antigravity_bundle "$FAKE_OTHER_APP"; then
  printf 'FAIL: unrelated bundle accepted\n' >&2
  exit 1
fi

# 只有 Extras 目录、没有 Contents/Info.plist 的路径也必须被拒绝
if verify_antigravity_bundle "$TEST_TMP"; then
  printf 'FAIL: path without Info.plist accepted\n' >&2
  exit 1
fi

SELECTED_TYPE=http
SELECTED_HOST=127.0.0.1
SELECTED_PORT=7890
SELECTED_SOURCE=Test
ANTIGRAVITY_PATH="$FAKE_MANAGER_APP"
save_config
assert_equal 600 "$(/usr/bin/stat -f '%Lp' "$CONFIG_FILE")" 'config file permissions'

SELECTED_TYPE=''
SELECTED_HOST=''
SELECTED_PORT=''
SELECTED_SOURCE=''
ANTIGRAVITY_PATH=''
proxy_is_usable() { return 0; }
load_saved_config
assert_equal http "$SELECTED_TYPE" 'saved proxy type'
assert_equal 127.0.0.1 "$SELECTED_HOST" 'saved proxy host'
assert_equal 7890 "$SELECTED_PORT" 'saved proxy port'
assert_equal Test "$SELECTED_SOURCE" 'saved proxy source'
assert_equal "$FAKE_MANAGER_APP" "$ANTIGRAVITY_PATH" 'saved Antigravity path'

# 旧版配置目录（上游 Antigravity Bridge / 更早的 Antigravity Proxy）应能自动迁移。
# 注意：这里调用的是 src/ag-bridge 里的真函数，只是通过覆盖它读取的全局变量
# 把它指到临时目录 —— 绝不在这里重写一遍逻辑，否则等于在测副本。
MIGRATION_TMP="$TEST_TMP/migration"
/bin/mkdir -p "$MIGRATION_TMP/Antigravity Bridge"
/bin/cp "$CONFIG_FILE" "$MIGRATION_TMP/Antigravity Bridge/config.plist"

DEFAULT_CONFIG_ROOT="$TEST_TMP/migrated"
CONFIG_ROOT="$TEST_TMP/migrated"
CONFIG_FILE="$CONFIG_ROOT/config.plist"
LEGACY_CONFIG_ROOTS=(
  "$MIGRATION_TMP/Antigravity Bridge"
  "$MIGRATION_TMP/Antigravity Proxy"
)
migrate_legacy_config
[[ -r "$CONFIG_FILE" ]] \
  || { printf 'FAIL: legacy Antigravity Bridge config was not migrated\n' >&2; exit 1; }
assert_equal 600 "$(/usr/bin/stat -f '%Lp' "$CONFIG_FILE")" 'migrated config permissions'

# 只有更早的 Antigravity Proxy 目录存在时，也应该迁移成功
/bin/rm -rf "$MIGRATION_TMP" "$TEST_TMP/migrated"
/bin/mkdir -p "$MIGRATION_TMP/Antigravity Proxy"
/bin/cp "$TEST_TMP/config/config.plist" "$MIGRATION_TMP/Antigravity Proxy/config.plist"
CONFIG_ROOT="$TEST_TMP/migrated"
CONFIG_FILE="$CONFIG_ROOT/config.plist"
migrate_legacy_config
[[ -r "$CONFIG_FILE" ]] \
  || { printf 'FAIL: legacy Antigravity Proxy config was not migrated\n' >&2; exit 1; }

# 已经存在配置时不应被旧配置覆盖
printf 'sentinel\n' > "$CONFIG_FILE"
migrate_legacy_config
assert_equal 'sentinel' "$(/bin/cat "$CONFIG_FILE")" 'existing config is not overwritten'

BUILD_DIST="$TEST_TMP/build"
DIST_DIR="$BUILD_DIST" "$ROOT_DIR/scripts/build.sh" >/dev/null
APP_DIR="$BUILD_DIST/AG Bridge.app"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
assert_file_equal "$ROOT_DIR/src/ag-bridge" \
  "$APP_DIR/Contents/MacOS/ag-bridge" 'bundled executable matches source'
assert_file_equal "$ROOT_DIR/packaging/Info.plist" \
  "$APP_DIR/Contents/Info.plist" 'bundled plist matches source'
assert_file_equal "$ROOT_DIR/resources/AGBridge.icns" \
  "$APP_DIR/Contents/Resources/AGBridge.icns" 'bundled icon matches source'
assert_equal 'AG Bridge' \
  "$(/usr/bin/plutil -extract CFBundleDisplayName raw "$APP_DIR/Contents/Info.plist")" \
  'display name'

PACKAGE_DIST="$TEST_TMP/package"
DIST_DIR="$PACKAGE_DIST" "$ROOT_DIR/scripts/package.sh" v1.0.0 >/dev/null
ZIP_FILE="$PACKAGE_DIST/AG-Bridge-v1.0.0-unsigned.zip"
DMG_FILE="$PACKAGE_DIST/AG-Bridge-v1.0.0-unsigned.dmg"
/usr/bin/unzip -t "$ZIP_FILE" >/dev/null
if /usr/bin/unzip -Z1 "$ZIP_FILE" | /usr/bin/grep -E '(^|/)(__MACOSX|\.DS_Store|\._)' >/dev/null; then
  printf 'FAIL: release ZIP contains macOS metadata\n' >&2
  exit 1
fi
/usr/bin/hdiutil verify "$DMG_FILE" >/dev/null
/usr/bin/hdiutil imageinfo "$DMG_FILE" >/dev/null
(
  cd "$PACKAGE_DIST"
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
)

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT_DIR/src/ag-bridge" "$ROOT_DIR/scripts/"*.sh "$ROOT_DIR/tests/run-tests.sh"
else
  printf 'NOTE: shellcheck is not installed; static lint was skipped.\n'
fi

printf 'All tests passed.\n'
