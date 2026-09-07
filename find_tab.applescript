on run argv
	set needle to item 1 of argv
	tell application "Google Chrome"
		set wi to 0
		repeat with w in windows
			set wi to wi + 1
			set ti to 0
			repeat with t in tabs of w
				set ti to ti + 1
				if (URL of t) contains needle then
					set active tab index of w to ti
					set index of w to 1
					return "FOUND " & wi & " " & ti & " " & (URL of t)
				end if
			end repeat
		end repeat
		return "NOTFOUND"
	end tell
end run
