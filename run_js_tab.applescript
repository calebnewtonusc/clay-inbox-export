on run argv
	set needle to item 1 of argv
	set jsFile to item 2 of argv
	set js to (read (POSIX file jsFile) as «class utf8»)
	tell application "Google Chrome"
		repeat with w in windows
			repeat with t in tabs of w
				if (URL of t) contains needle then
					return execute t javascript js
				end if
			end repeat
		end repeat
		return "NOTABFOUND"
	end tell
end run
