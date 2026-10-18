-- Device template: the module defaults plus throttle-specific commands
local res = external_profile('Mods/aircraft/FakePlane/Input/FakePlane/joystick/default.lua')
join(res.keyCommands, {
	{combos = {{key = 'JOY_BTN10'}}, down = 3010, cockpit_device_id = 15, value_down = 1.0, name = _('Speed Brake'), category = _('Throttle')},
})
return res
