on run argv
	set jsFile to item 1 of argv
	set js to (read (POSIX file jsFile) as «class utf8»)
	tell application "Google Chrome"
		return execute front window's active tab javascript js
	end tell
end run
