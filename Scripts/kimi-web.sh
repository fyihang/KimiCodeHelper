#!/bin/bash

set -u

session_name="${KIMI_WEB_SCREEN_SESSION:-kimi-web}"
config_path="${KIMI_WEB_CONFIG:-$HOME/Library/Application Support/KimiWeb/com.kimi.web.plist}"
script_path="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && pwd)/kimi-web.sh"
child_pid=""

stop_run() {
	trap - HUP TERM INT
	if [[ -n "$child_pid" ]]; then
		kill -TERM "$child_pid" 2>/dev/null
		wait "$child_pid" 2>/dev/null
	fi
	exit 0
}

session_exists() {
	local command=(/usr/bin/screen -S "$session_name" -X select .)
	"${command[@]}" >/dev/null 2>&1
}

run_web() {
	local arguments=()
	local index=0
	local argument
	local status

	while argument="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$index" "$config_path" 2>/dev/null)"; do
		arguments+=("$argument")
		index=$((index + 1))
	done

	if ((${#arguments[@]} == 0)); then
		printf 'No ProgramArguments found in %s\n' "$config_path" >&2
		return 1
	fi

	trap stop_run HUP TERM INT
	while true; do
		"${arguments[@]}" &
		child_pid=$!
		wait "$child_pid"
		status=$?
		child_pid=""
		if ((status == 0)); then
			trap - HUP TERM INT
			return 0
		fi
		printf 'Kimi Web exited with status %d; retrying in 5 seconds.\n' "$status" >&2
		/bin/sleep 5 &
		child_pid=$!
		wait "$child_pid"
		child_pid=""
	done
}

start_session() {
	if session_exists; then
		printf '%s is already running.\n' "$session_name"
		return 0
	fi

	local command=(/usr/bin/screen -dmS "$session_name" "$script_path" run)
	"${command[@]}"
	if ! session_exists; then
		printf 'Failed to start %s.\n' "$session_name" >&2
		return 1
	fi
	printf 'Started %s.\n' "$session_name"
}

stop_session() {
	if ! session_exists; then
		printf '%s is not running.\n' "$session_name"
		return 0
	fi

	local screen_pid
	local login_pid
	local process_group
	local groups=()
	local group
	local attempt
	local groups_alive
	screen_pid="$(/usr/bin/screen -ls | /usr/bin/awk -v name="$session_name" '{entry=$1; separator=index(entry, "."); if (separator > 0 && substr(entry, separator + 1) == name) {print substr(entry, 1, separator - 1); exit}}')"
	for login_pid in $(/usr/bin/pgrep -P "$screen_pid"); do
		process_group="$(/bin/ps -o pgid= -p "$login_pid" | /usr/bin/tr -d ' ')"
		if [[ -n "$process_group" ]]; then
			groups+=("$process_group")
		fi
	done
	local command=(/usr/bin/screen -S "$session_name" -X quit)
	"${command[@]}"
	for group in "${groups[@]}"; do
		kill -TERM -- "-$group" 2>/dev/null
	done
	for ((attempt = 0; attempt < 20; attempt++)); do
		groups_alive=0
		for group in "${groups[@]}"; do
			if kill -0 -- "-$group" 2>/dev/null; then
				groups_alive=1
			fi
		done
		if ((groups_alive == 0)); then
			break
		fi
		/bin/sleep 0.1
	done
	if session_exists || ((groups_alive != 0)); then
		printf 'Failed to stop %s.\n' "$session_name" >&2
		return 1
	fi
	printf 'Stopped %s.\n' "$session_name"
}

status_session() {
	if session_exists; then
		printf '%s is running.\n' "$session_name"
		return 0
	fi
	printf '%s is not running.\n' "$session_name"
	return 1
}

attach_session() {
	if ! session_exists; then
		printf '%s is not running.\n' "$session_name" >&2
		return 1
	fi
	local command=(/usr/bin/screen -r "$session_name")
	exec "${command[@]}"
}

case "${1:-}" in
	run)
		run_web
		;;
	start)
		start_session
		;;
	stop)
		stop_session
		;;
	restart)
		stop_session && start_session
		;;
	status)
		status_session
		;;
	attach)
		attach_session
		;;
	*)
		printf 'Usage: %s run|start|stop|restart|status|attach\n' "$0" >&2
		exit 64
		;;
esac
