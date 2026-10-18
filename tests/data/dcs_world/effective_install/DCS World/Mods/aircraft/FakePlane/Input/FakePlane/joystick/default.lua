local res = {
	keyCommands = {
		{combos = {{key = 'JOY_BTN1'}}, down = 3001, up = 3001, cockpit_device_id = 12, value_down = 1.0, value_up = 0.0, name = _('Weapon Release'), category = _('Weapons')},
		{combos = {{key = 'JOY_BTN2'}}, down = 3002, cockpit_device_id = 12, value_down = 1.0, name = _('Gun Trigger'), category = _('Weapons')},
		{combos = {{key = 'JOY_BTN3'}}, pressed = iCommandPlaneTrimUp, name = _('Trim: Nose Up'), category = _('Trim')},
		{down = 3003, cockpit_device_id = 12, value_down = 1.0, name = _('Master Arm'), category = _('Weapons')},
		{combos = {{key = 'JOY_BTN_POV1_U'}}, down = 3004, cockpit_device_id = 13, value_down = 1.0, name = _('Sensor Up'), category = {_('Sensors'), _('HOTAS')}},
		{combos = {{key = 'JOY_BTN6'}}, down = 3005, cockpit_device_id = 13, value_down = 1.0, name = _('Sensor Select'), category = _('Sensors')},
	},
	axisCommands = {
		{combos = defaultDeviceAssignmentFor('roll'), action = iCommandPlaneRoll, name = _('Roll')},
		{combos = {{key = 'JOY_Y'}}, action = 2001, cockpit_device_id = 14, name = _('Zoom')},
		{combos = {{key = 'JOY_Z'}}, action = 2002, cockpit_device_id = 14, name = _('Brightness')},
	},
}
return res
