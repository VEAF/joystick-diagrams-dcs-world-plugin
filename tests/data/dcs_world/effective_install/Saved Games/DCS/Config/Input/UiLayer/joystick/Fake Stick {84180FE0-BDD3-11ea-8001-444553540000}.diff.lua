-- The fake install has no Config/Input/UiLayer profile: no base for this device
local diff = {
	["keyDiffs"] = {
		["d5001pnilunilcdnilvdnilvpnilvunil"] = {
			["added"] = {
				[1] = {
					["key"] = "JOY_BTN30",
				},
			},
			["name"] = "UI Layer Command",
		},
	},
}
return diff
