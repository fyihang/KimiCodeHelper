#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
dist_dir="$root_dir/dist"
app_path="$dist_dir/Kimi Web.app"
temporary_app="$dist_dir/.Kimi Web.app.tmp.$$"

for tool in /usr/bin/swiftc /usr/bin/plutil /usr/bin/osacompile /usr/bin/codesign; do
    if [[ ! -x "$tool" ]]; then
        printf 'Required build tool is missing: %s\n' "$tool" >&2
        exit 1
    fi
done
for source in "$root_dir"/Sources/*.swift "$root_dir/Scripts/kimi-web.sh" "$root_dir/Scripts/console-action.applescript" "$root_dir/app-template/Info.plist"; do
    if [[ ! -f "$source" ]]; then
        printf 'Required build input is missing: %s\n' "$source" >&2
        exit 1
    fi
done

/bin/rm -rf "$temporary_app"
trap '/bin/rm -rf "$temporary_app"' EXIT
/bin/mkdir -p "$temporary_app/Contents/MacOS" "$temporary_app/Contents/Resources"
/bin/cp "$root_dir/app-template/Info.plist" "$temporary_app/Contents/Info.plist"
/bin/cp "$root_dir/Scripts/kimi-web.sh" "$root_dir/Scripts/console-action.applescript" "$temporary_app/Contents/Resources/"
/usr/bin/plutil -lint "$temporary_app/Contents/Info.plist"
/usr/bin/osacompile -o "$temporary_app/Contents/Resources/.console-action-check.scpt" "$root_dir/Scripts/console-action.applescript"
/bin/rm -f "$temporary_app/Contents/Resources/.console-action-check.scpt"
/usr/bin/swiftc -parse-as-library -target "$(/usr/bin/uname -m)-apple-macos13.0" -framework SwiftUI "$root_dir"/Sources/*.swift -o "$temporary_app/Contents/MacOS/KimiWebConsole"
/usr/bin/codesign --force --sign - --timestamp=none "$temporary_app"
/usr/bin/codesign --verify --strict "$temporary_app"

/bin/rm -rf "$app_path"
/bin/mv "$temporary_app" "$app_path"
trap - EXIT
printf 'Built %s\n' "$app_path"
