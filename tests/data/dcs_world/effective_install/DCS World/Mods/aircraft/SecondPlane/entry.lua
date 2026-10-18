-- The unit name is an expression and the script calls functions the loader does not know
local flyable_ID = 'SecondPlane'
mount_vfs_texture_path(current_mod_path .. '/Textures')

declare_plugin(flyable_ID, {
	InputProfiles = {
		[flyable_ID .. '_pilot'] = current_mod_path .. '/Input/Second/',
	},
})

dofile(current_mod_path .. '/SecondPlane.lua')
make_flyable(flyable_ID, current_mod_path .. '/Cockpit/', SecondPlane.FM, nil)
plugin_done()
