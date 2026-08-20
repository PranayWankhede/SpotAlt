#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Uninstall SpotAlt for the current user.

Usage: ./scripts/uninstall.sh [--purge-data]

By default, the SQLite index, settings, and enrolled-folder permissions are kept
so a future installation can reuse them. Use --purge-data to move that data to
the Trash as well.

Environment:
  SPOTALT_INSTALL_DIR  Installation directory (default: $HOME/Applications)
EOF
}

purge_data=false

case "${1:-}" in
    "") ;;
    --purge-data) purge_data=true ;;
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

[[ "$(uname -s)" == "Darwin" ]] || fail "SpotAlt can only be uninstalled on macOS."
[[ -n "${HOME:-}" ]] || fail "HOME is not set."

requested_install_directory="${SPOTALT_INSTALL_DIR:-$HOME/Applications}"
installed_app_path="$requested_install_directory/SpotAlt.app"
trash_directory="$HOME/.Trash"
timestamp="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$trash_directory"

move_to_trash() {
    local source_path="$1"
    local trash_name="$2"
    local destination_path="$trash_directory/$trash_name"
    local suffix=1

    while [[ -e "$destination_path" ]]; do
        destination_path="$trash_directory/${trash_name}-${suffix}"
        suffix=$((suffix + 1))
    done

    mv "$source_path" "$destination_path"
    echo "Moved $source_path to $destination_path"
}

osascript -e 'tell application id "com.vez.search" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! pgrep -x SpotAlt >/dev/null 2>&1 && ! pgrep -x Vez >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
if pgrep -x SpotAlt >/dev/null 2>&1 || pgrep -x Vez >/dev/null 2>&1; then
    fail "SpotAlt did not quit. Quit it from the menu bar, then run the uninstaller again."
fi

if [[ -e "$installed_app_path" ]]; then
    move_to_trash "$installed_app_path" "SpotAlt-$timestamp.app"
else
    echo "SpotAlt is not installed at $installed_app_path"
fi

if [[ "$purge_data" == true ]]; then
    container_path="$HOME/Library/Containers/com.vez.search"
    if [[ -e "$container_path" ]]; then
        move_to_trash "$container_path" "SpotAlt-data-$timestamp"
    else
        echo "No SpotAlt data was found at $container_path"
    fi
else
    echo "SpotAlt data was preserved. Run with --purge-data to remove it."
fi
