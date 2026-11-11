#!/bin/bash

set -euo pipefail

label="com.kimi.web.terminal"
old_label="com.kimi.web"
script_dir="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
manager_path="$script_dir/kimi-web.sh"
launcher_path="$script_dir/login-bootstrap.applescript"
config_path="$HOME/Library/Application Support/KimiWeb/com.kimi.web.plist"
launch_agents_dir="$HOME/Library/LaunchAgents"
new_plist="$launch_agents_dir/$label.plist"
old_plist="$launch_agents_dir/$old_label.plist"
domain="gui/$(/usr/bin/id -u)"
temporary_plist=""

cleanup() {
	if [[ -n "$temporary_plist" ]]; then
		/bin/rm -f "$temporary_plist"
	fi
}
trap cleanup EXIT

xml_escape() {
	local value="$1"
	value="${value//&/&amp;}"
	value="${value//</&lt;}"
	value="${value//>/&gt;}"
	printf '%s' "$value"
}

write_launch_agent() {
	local destination="$1"
	local escaped_launcher_path
	escaped_launcher_path="$(xml_escape "$launcher_path")"
	/bin/cat >"$destination" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/osascript</string>
		<string>$escaped_launcher_path</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
}

preflight() {
	local required_path
	for required_path in "$manager_path" "$launcher_path" "$config_path"; do
		if [[ ! -f "$required_path" ]]; then
			printf 'Required file is missing: %s\n' "$required_path" >&2
			return 1
		fi
	done
	for required_path in "$manager_path" /usr/bin/osascript /usr/bin/screen /bin/launchctl; do
		if [[ ! -x "$required_path" ]]; then
			printf 'Required executable is unavailable: %s\n' "$required_path" >&2
			return 1
		fi
	done
	if [[ ! -d /System/Applications/Utilities/Terminal.app ]]; then
		printf 'Terminal.app was not found.\n' >&2
		return 1
	fi
	if [[ ! -t 0 ]]; then
		printf 'Run this installer interactively from Terminal after granting Full Disk Access.\n' >&2
		return 1
	fi
	printf 'Enable Terminal in System Settings > Privacy & Security > Full Disk Access before continuing.\n'
	printf 'After installation, leave Terminal running in the background; do not quit it completely.\n'
	local response
	read -r -p 'Has Terminal been granted Full Disk Access? [y/N] ' response
	case "$response" in
		[yY]|[yY][eE][sS]) ;;
		*)
			printf 'Installation cancelled; no services were changed.\n' >&2
			return 1
			;;
	esac
}

wait_until_unloaded() {
	local target="$1"
	local attempt
	for ((attempt = 0; attempt < 25; attempt++)); do
		if ! /bin/launchctl print "$target" >/dev/null 2>&1; then
			return 0
		fi
		/bin/sleep 0.2
	done
	return 1
}

main() {
	preflight
	/bin/mkdir -p "$launch_agents_dir"
	temporary_plist="$(/usr/bin/mktemp "$launch_agents_dir/.com.kimi.web.terminal.XXXXXX")"
	write_launch_agent "$temporary_plist"
	/usr/bin/plutil -lint "$temporary_plist" >/dev/null
	/bin/chmod 644 "$temporary_plist"

	/bin/launchctl bootout "$domain/$old_label" >/dev/null 2>&1 || true
	if ! wait_until_unloaded "$domain/$old_label"; then
		printf 'Failed to unload %s; the old LaunchAgent was left in place.\n' "$old_label" >&2
		return 1
	fi
	/bin/rm -f "$old_plist"

	/bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
	if ! wait_until_unloaded "$domain/$label"; then
		printf 'Failed to unload the existing %s service.\n' "$label" >&2
		return 1
	fi
	/bin/mv "$temporary_plist" "$new_plist"
	temporary_plist=""
	/bin/launchctl bootstrap "$domain" "$new_plist"
	printf 'Installed and started %s. RunAtLoad invoked the Terminal launcher.\n' "$label"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
