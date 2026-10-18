declare_plugin("FakePlane by Test", {
	installed = true,
	displayName = _("Fake Plane"),
	InputProfiles = {
		["FakePlane"] = current_mod_path .. '/Input/FakePlane',
	},
})

make_flyable('FakePlane', current_mod_path .. '/Cockpit/Scripts/', nil, current_mod_path .. '/comm.lua')
plugin_done()
