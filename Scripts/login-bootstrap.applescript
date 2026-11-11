on environmentValue(variableName)
	try
		return system attribute variableName
	on error
		return ""
	end try
end environmentValue

set launcherPath to POSIX path of (path to me)
set managerPath to (do shell script "/usr/bin/dirname " & quoted form of launcherPath) & "/kimi-web.sh"
set sessionName to environmentValue("KIMI_WEB_SCREEN_SESSION")
if sessionName is "" then set sessionName to "kimi-web"

set startCommand to ""
if environmentValue("KIMI_WEB_SCREEN_SESSION") is not "" then
	set startCommand to startCommand & "export KIMI_WEB_SCREEN_SESSION=" & quoted form of sessionName & "; "
end if
if environmentValue("KIMI_WEB_CONFIG") is not "" then
	set startCommand to startCommand & "export KIMI_WEB_CONFIG=" & quoted form of environmentValue("KIMI_WEB_CONFIG") & "; "
end if
set startCommand to startCommand & quoted form of managerPath & " start; exit_code=$?; if [ \"$exit_code\" -ne 0 ]; then echo \"Kimi Web startup failed; leaving this window open for diagnostics.\"; exec /bin/bash; fi"

tell application "Terminal"
	do script startCommand
	set newWindowID to id of front window
	set sessionStarted to false
	repeat 60 times
		try
			do shell script "/usr/bin/screen -S " & quoted form of sessionName & " -X select . >/dev/null 2>&1"
			set sessionStarted to true
			exit repeat
		end try
		delay 0.5
	end repeat
	if sessionStarted then close window id newWindowID
end tell
