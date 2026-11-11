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
session_name="kimi-web"
temporary_plist=""
old_service_loaded=false

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

wait_until_loaded() {
	local target="$1"
	local attempt
	for ((attempt = 0; attempt < 25; attempt++)); do
		if /bin/launchctl print "$target" >/dev/null 2>&1; then
			return 0
		fi
		/bin/sleep 0.2
	done
	return 1
}

wait_for_session() {
	local attempt
	for ((attempt = 0; attempt < 60; attempt++)); do
		if /usr/bin/screen -S "$session_name" -X select . >/dev/null 2>&1; then
			return 0
		fi
		/bin/sleep 0.5
	done
	return 1
}

rollback_installation() {
	/bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
	if ! wait_until_unloaded "$domain/$label"; then
		printf 'Rollback could not unload %s.\n' "$label" >&2
	fi
	/bin/rm -f "$new_plist"

	if [[ "$old_service_loaded" == true ]]; then
		if [[ ! -f "$old_plist" ]]; then
			printf 'Rollback could not restore %s because %s is missing.\n' "$old_label" "$old_plist" >&2
		elif ! /bin/launchctl bootstrap "$domain" "$old_plist"; then
			printf 'Rollback could not bootstrap %s from %s.\n' "$old_label" "$old_plist" >&2
		elif ! wait_until_loaded "$domain/$old_label"; then
			printf 'Rollback could not confirm that %s was restored.\n' "$old_label" >&2
		else
			printf 'Restored %s from %s.\n' "$old_label" "$old_plist"
		fi
	fi
}

main() {
	preflight
	/bin/mkdir -p "$launch_agents_dir"
	temporary_plist="$(/usr/bin/mktemp "$launch_agents_dir/.com.kimi.web.terminal.XXXXXX")"
	write_launch_agent "$temporary_plist"
	/usr/bin/plutil -lint "$temporary_plist" >/dev/null
	/bin/chmod 644 "$temporary_plist"

	if /bin/launchctl print "$domain/$old_label" >/dev/null 2>&1; then
		old_service_loaded=true
	fi
	/bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
	if ! wait_until_unloaded "$domain/$label"; then
		printf 'Failed to unload the existing %s service; the old service was not changed.\n' "$label" >&2
		return 1
	fi

	/bin/launchctl bootout "$domain/$old_label" >/dev/null 2>&1 || true
	if ! wait_until_unloaded "$domain/$old_label"; then
		printf 'Failed to unload %s; the old LaunchAgent was left in place.\n' "$old_label" >&2
		return 1
	fi
	if ! /bin/mv "$temporary_plist" "$new_plist"; then
		printf 'Failed to install %s.\n' "$new_plist" >&2
		rollback_installation
		return 1
	fi
	temporary_plist=""
	if ! /bin/launchctl bootstrap "$domain" "$new_plist"; then
		printf 'Failed to bootstrap %s.\n' "$label" >&2
		rollback_installation
		return 1
	fi
	if ! wait_for_session; then
		printf 'Timed out waiting for the %s screen session; rolling back the installation.\n' "$session_name" >&2
		rollback_installation
		return 1
	fi

	/bin/rm -f "$old_plist"
	printf 'Installed %s and confirmed that screen session %s is running.\n' "$label" "$session_name"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
