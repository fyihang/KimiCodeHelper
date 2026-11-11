#!/bin/bash

set -euo pipefail

label="com.kimi.web.terminal"
script_dir="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd -P)"
manager_path="$script_dir/kimi-web.sh"
launch_agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(/usr/bin/id -u)"

if [[ ! -x "$manager_path" ]]; then
	printf 'Required executable is unavailable: %s\n' "$manager_path" >&2
	exit 1
fi

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

/bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
if ! wait_until_unloaded "$domain/$label"; then
	printf 'Failed to unload %s; its LaunchAgent was left in place.\n' "$label" >&2
	exit 1
fi
/bin/rm -f "$launch_agent"
"$manager_path" stop
printf 'Uninstalled %s. User configuration was retained.\n' "$label"
