-- Community keybinds, injected by the Quaggles Input Command Injector
return {
	keyCommands = {
		{combos = {{key = 'JOY_BTN20'}}, down = 3020, cockpit_device_id = 12, value_down = 1.0, name = _('Laser Arm (community)'), category = _('Community')},
		-- same hash as the module's 'Weapon Release': one command for DCS
		{combos = {{key = 'JOY_BTN1'}}, down = 3001, up = 3001, cockpit_device_id = 12, value_down = 1.0, value_up = 0.0, name = _('Weapon Release (community)'), category = _('Community')},
	},
}
