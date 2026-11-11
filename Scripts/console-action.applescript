on environmentValue(variableName)
	try
		return system attribute variableName
	on error
		return ""
	end try
end environmentValue

on run arguments
	if (count arguments) is not 1 then error "Usage: console-action.applescript start|stop|restart|update|attach" number 64
	set actionName to item 1 of arguments
	if actionName is not in {"start", "stop", "restart", "update", "attach"} then error "Unknown action: " & actionName number 64

	set launcherPath to POSIX path of (path to me)
	set managerPath to (do shell script "/usr/bin/dirname " & quoted form of launcherPath) & "/kimi-web.sh"
	set homeDirectory to environmentValue("HOME")
	if homeDirectory is "" then set homeDirectory to POSIX path of (path to home folder)
	set sessionName to environmentValue("KIMI_WEB_SCREEN_SESSION")
	if sessionName is "" then set sessionName to "kimi-web"
	set configPath to environmentValue("KIMI_WEB_CONFIG")
	if configPath is "" then set configPath to homeDirectory & "/Library/Application Support/KimiWeb/com.kimi.web.plist"
	set webURL to environmentValue("KIMI_WEB_URL")
	if webURL is "" then set webURL to "http://127.0.0.1:58627/"
	set kimiBinary to environmentValue("KIMI_WEB_KIMI_BIN")
	if kimiBinary is "" then set kimiBinary to homeDirectory & "/.kimi-code/bin/kimi"
	set stateDirectory to environmentValue("KIMI_WEB_STATE_DIR")
	if stateDirectory is "" then set stateDirectory to homeDirectory & "/Library/Logs/KimiWeb"
	set taskID to do shell script "/usr/bin/uuidgen"
	set resultPath to stateDirectory & "/.result-" & taskID

	set shellProgram to "set -u
action=$1
manager=$2
session=$3
config=$4
url=$5
kimi_bin=$6
state_dir=$7
task_id=$8
result_file=$9
lock_file=$state_dir/task.lock
state_file=$state_dir/task.state
log_file=$state_dir/console.log
lock_held=0
tracked=0
completed=0
export KIMI_WEB_SCREEN_SESSION=$session
export KIMI_WEB_CONFIG=$config
export KIMI_WEB_URL=$url
export KIMI_WEB_KIMI_BIN=$kimi_bin
export KIMI_WEB_STATE_DIR=$state_dir
umask 077

session_exists() {
	/usr/bin/screen -S \"$session\" -X select . >/dev/null 2>&1
}

http_ready() {
	/usr/bin/curl --fail --silent --show-error --output /dev/null --max-time 1 \"$url\" >/dev/null 2>&1
}

write_result() {
	local temporary=$result_file.tmp.$$
	/usr/bin/printf '%s\\n' \"$1\" > \"$temporary\" && /bin/mv -f \"$temporary\" \"$result_file\"
}

write_state() {
	local temporary
	temporary=$(/usr/bin/mktemp \"$state_dir/.task-state.XXXXXX\") || return 1
	local message=${2//$'\\n'/ }
	/usr/bin/printf 'id=%s\\naction=%s\\nstatus=%s\\npid=%s\\nupdated_at=%s\\nmessage=%s\\nlog=%s\\n' \"$task_id\" \"$action\" \"$1\" \"$$\" \"$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')\" \"$message\" \"$log_file\" > \"$temporary\" && /bin/mv -f \"$temporary\" \"$state_file\"
}

cleanup() {
	local exit_status=$?
	if ((lock_held == 1)); then /bin/rm -f \"$lock_file\"; fi
	if ((tracked == 1 && completed == 0)); then
		write_state failed \"Action interrupted; inspect the Terminal output and log.\"
		write_result failed
	fi
	exit \"$exit_status\"
}

finish() {
	local task_status=$1
	local exit_status=$2
	local message=$3
	if ((tracked == 1)); then write_state \"$task_status\" \"$message\"; fi
	write_result \"$task_status\"
	completed=1
	/usr/bin/printf '%s\\n' \"$message\"
	exit \"$exit_status\"
}

wait_ready() {
	local deadline=$((SECONDS + 30))
	while ((SECONDS < deadline)); do
		if session_exists && http_ready; then return 0; fi
		/bin/sleep 0.25
	done
	return 1
}

start_service() {
	\"$manager\" start || return 1
	if ! wait_ready; then
		/usr/bin/printf 'Timed out after 30 seconds waiting for screen session %s and HTTP %s.\\n' \"$session\" \"$url\" >&2
		return 1
	fi
	return 0
}

stop_service() {
	local groups=()
	local screen_pid
	local login_pid
	local process_group
	local group
	local attempt
	local alive
	if session_exists; then
		screen_pid=$(/usr/bin/screen -ls | /usr/bin/awk -v name=\"$session\" '{entry=$1; separator=index(entry, \".\"); if (separator > 0 && substr(entry, separator + 1) == name) {print substr(entry, 1, separator - 1); exit}}')
		for login_pid in $(/usr/bin/pgrep -P \"${screen_pid:-0}\" 2>/dev/null); do
			process_group=$(/bin/ps -o pgid= -p \"$login_pid\" | /usr/bin/tr -d ' ')
			if [[ -n \"$process_group\" ]]; then groups+=(\"$process_group\"); fi
		done
	fi
	\"$manager\" stop || return 1
	for ((attempt = 0; attempt < 30; attempt++)); do
		alive=0
		if session_exists; then alive=1; fi
		for group in \"${groups[@]}\"; do
			if kill -0 -- \"-$group\" 2>/dev/null; then alive=1; fi
		done
		if ((alive == 0)); then return 0; fi
		/bin/sleep 0.1
	done
	/usr/bin/printf 'Screen session or service process group did not disappear.\\n' >&2
	return 1
}

restart_service() {
	\"$manager\" restart || return 1
	if ! wait_ready; then
		/usr/bin/printf 'Timed out after 30 seconds waiting for screen session %s and HTTP %s after restart.\\n' \"$session\" \"$url\" >&2
		return 1
	fi
	return 0
}

if ! /bin/mkdir -p \"$state_dir\"; then
	/usr/bin/printf 'Cannot create state directory: %s\\n' \"$state_dir\" >&2
	exit 1
fi

if [[ \"$action\" == attach ]]; then
	/usr/bin/printf 'Attaching to %s. Press Control-A, then D to detach.\\n' \"$session\"
	\"$manager\" attach
	attach_status=$?
	if ((attach_status == 0)); then
		finish succeeded 0 'Detached from the service session.'
	else
		finish failed \"$attach_status\" 'Could not attach to the service session; this window is retained for diagnostics.'
	fi
fi

trap cleanup EXIT HUP TERM INT
if ! /usr/bin/shlock -f \"$lock_file\" -p \"$$\"; then
	/usr/bin/printf 'Another console action is already running; this request was rejected.\\n' >&2
	finish failed 75 'Another console action is already running; no duplicate task was started.'
fi
lock_held=1
tracked=1
exec > >(/usr/bin/tee -a \"$log_file\") 2>&1
/usr/bin/printf '\\n[%s] action=%s id=%s\\n' \"$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')\" \"$action\" \"$task_id\"
write_state running \"Action is running.\"

case \"$action\" in
	start)
		if start_service; then
			finish succeeded 0 'Service is running and HTTP is ready.'
		else
			finish failed 1 'Service start failed or did not become ready; this window is retained for diagnostics.'
		fi
		;;
	stop)
		if stop_service; then
			finish succeeded 0 'Service session and service processes stopped.'
		else
			finish failed 1 'Service stop failed; this window is retained for diagnostics.'
		fi
		;;
	restart)
		if restart_service; then
			finish succeeded 0 'Service restarted and HTTP is ready.'
		else
			finish failed 1 'Service restart failed or did not become ready; this window is retained for diagnostics.'
		fi
		;;
	update)
		original_running=0
		if session_exists; then original_running=1; fi
		old_version=$(\"$kimi_bin\" --version 2>&1) || old_version=unknown
		/usr/bin/printf 'Original service running: %s; version: %s\\n' \"$original_running\" \"$old_version\"
		if ((original_running == 1)); then
			if ! stop_service; then
				finish failed 1 'Update was not run because the running service could not be stopped.'
			fi
		fi
		/usr/bin/printf 'Running update command: %s update -y\\n' \"$kimi_bin\"
		\"$kimi_bin\" update -y
		update_status=$?
		new_version=$(\"$kimi_bin\" --version 2>&1) || new_version=unknown
		/usr/bin/printf 'Update exit status: %s; version after update: %s\\n' \"$update_status\" \"$new_version\"
		if ((update_status == 0)); then
			if start_service; then
				finish succeeded 0 \"Update succeeded; service is ready. Version: $old_version -> $new_version\"
			else
				finish failed 1 'Update succeeded, but service start or readiness failed; this window is retained for diagnostics.'
			fi
		elif ((original_running == 1)); then
			if start_service; then
				finish failed \"$update_status\" \"Update failed (exit $update_status); the residual binary was restarted successfully, but no rollback is guaranteed.\"
			else
				finish failed 1 \"Update failed (exit $update_status) and service recovery failed; this window is retained for diagnostics.\"
			fi
		else
			finish failed \"$update_status\" \"Update failed (exit $update_status); the service was originally stopped and was not restarted.\"
		fi
		;;
esac
"
	set terminalCommand to "/bin/bash -c " & quoted form of shellProgram & " console-action " & quoted form of actionName & " " & quoted form of managerPath & " " & quoted form of sessionName & " " & quoted form of configPath & " " & quoted form of webURL & " " & quoted form of kimiBinary & " " & quoted form of stateDirectory & " " & quoted form of taskID & " " & quoted form of resultPath

	tell application "Terminal"
		set newTab to do script terminalCommand
		set newTTY to tty of newTab
		set newWindowID to missing value
		repeat with windowIndex from 1 to count windows
			set candidateWindow to window windowIndex
			try
				if tty of selected tab of candidateWindow is newTTY then set newWindowID to id of candidateWindow
			end try
		end repeat
		if newWindowID is missing value then error "Could not identify the Terminal window created for this console action."
	end tell

	set resultStatus to ""
	repeat
		try
			set resultStatus to do shell script "/bin/cat " & quoted form of resultPath & " 2>/dev/null"
		end try
		if resultStatus is not "" then exit repeat
		delay 0.2
		set tabIsBusy to true
		tell application "Terminal"
			try
				set tabIsBusy to busy of newTab
			end try
		end tell
		if not tabIsBusy then
			try
				set resultStatus to do shell script "/bin/cat " & quoted form of resultPath & " 2>/dev/null"
			end try
			if resultStatus is "" then error "The Terminal action ended without writing a result; its window is retained for diagnostics."
			exit repeat
		end if
	end repeat
	do shell script "/bin/rm -f " & quoted form of resultPath

	if resultStatus is "succeeded" then
		tell application "Terminal"
			try
				if tty of selected tab of window id newWindowID is newTTY then close window id newWindowID
			end try
		end tell
		return resultStatus
	else
		error "Console action failed; inspect " & stateDirectory & "/task.state and console.log. The Terminal window is retained for diagnostics." number 1
	end if
end run
