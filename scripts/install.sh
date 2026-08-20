#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Build and install SpotAlt for the current user.

Usage: ./scripts/install.sh [--no-launch]

Environment:
  SPOTALT_INSTALL_DIR  Installation directory (default: $HOME/Applications)
EOF
}

launch_after_install=true

case "${1:-}" in
    "") ;;
    --no-launch) launch_after_install=false ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 2
fi

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "SpotAlt can only be installed on macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "SpotAlt currently requires an Apple silicon Mac."
[[ -n "${HOME:-}" ]] || fail "HOME is not set."

for command_name in xcodebuild codesign ditto open; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "$command_name is required. Install the full version of Xcode first."
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
project_path="$repository_root/SpotAlt.xcodeproj"
derived_data_path="$repository_root/.build/Installer"
built_app_path="$derived_data_path/Build/Products/Release/SpotAlt.app"
requested_install_directory="${SPOTALT_INSTALL_DIR:-$HOME/Applications}"

[[ -d "$project_path" ]] || fail "SpotAlt.xcodeproj was not found at $project_path."
[[ -n "$requested_install_directory" ]] || fail "SPOTALT_INSTALL_DIR cannot be empty."

mkdir -p "$requested_install_directory"
install_directory="$(cd "$requested_install_directory" && pwd)"
[[ "$install_directory" != "/" ]] || fail "Refusing to install directly into the filesystem root."

installed_app_path="$install_directory/SpotAlt.app"
staging_directory=""
backup_directory=""
restore_backup=false

cleanup() {
    if [[ "$restore_backup" == true \
        && -n "$backup_directory" \
        && -d "$backup_directory/SpotAlt.app" \
        && ! -e "$installed_app_path" ]]; then
        mv "$backup_directory/SpotAlt.app" "$installed_app_path"
    fi

    if [[ -n "$staging_directory" && -d "$staging_directory" ]]; then
        rm -rf "$staging_directory"
    fi
    if [[ -n "$backup_directory" && -d "$backup_directory" ]]; then
        rm -rf "$backup_directory"
    fi
}
trap cleanup EXIT

echo "Building SpotAlt (Release)..."
xcodebuild \
    -project "$project_path" \
    -scheme SpotAlt \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data_path" \
    -quiet \
    build

[[ -d "$built_app_path" ]] || fail "The Release build did not produce SpotAlt.app."
codesign --verify --deep --strict "$built_app_path"

staging_directory="$(mktemp -d "$install_directory/.spotalt-install.XXXXXX")"
staged_app_path="$staging_directory/SpotAlt.app"
ditto "$built_app_path" "$staged_app_path"
codesign --verify --deep --strict "$staged_app_path"

# The stable bundle identifier lets this quit both current and pre-rename builds.
osascript -e 'tell application id "com.vez.search" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! pgrep -x SpotAlt >/dev/null 2>&1 && ! pgrep -x Vez >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
if pgrep -x SpotAlt >/dev/null 2>&1 || pgrep -x Vez >/dev/null 2>&1; then
    fail "SpotAlt did not quit. Quit it from the menu bar, then run the installer again."
fi

if [[ -e "$installed_app_path" ]]; then
    backup_directory="$(mktemp -d "$install_directory/.spotalt-backup.XXXXXX")"
    mv "$installed_app_path" "$backup_directory/SpotAlt.app"
    restore_backup=true
fi

mv "$staged_app_path" "$installed_app_path"
restore_backup=false

if [[ "$launch_after_install" == true ]]; then
    open "$installed_app_path"
fi

echo "Installed SpotAlt at $installed_app_path"
echo "Press Option-Space to open it."
