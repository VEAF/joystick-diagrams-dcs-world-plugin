-- effective_bindings.lua: effective joystick bindings of DCS World profiles, as JSON on stdout.
--
-- Reproduces DCS's own logic (Scripts/Input/Data.lua, loadProfile):
--   base = <module>/Input/<profile>/joystick/<device without GUID>.lua, else default.lua
--   diff = Saved Games/DCS/Config/Input/<profile>/joystick/<device>.diff.lua,
--          else the <device without GUID>.diff.lua shipped with the module
--   effective = base + diff (applyDiffToCommands_)
--
-- Must run with Lua 5.1, the interpreter DCS ships as bin/luae.exe: command hashes go through
-- tostring() and must produce the same text as in the game.
--
-- Input, on stdin (UTF-8, one tab-separated record per line), written by effective_bindings.py:
--   install <DCS install>        saved <Saved Games/DCS>      casefold <1 if paths ignore case>
--   profile <unit name>          (one line per profile to compute)
--   dir <directory>              followed by one "entry <name>" line per directory entry
-- Lua 5.1 can neither list a directory nor take a non-ASCII path on the command line (luae.exe
-- reads its arguments in the ANSI code page but opens files in UTF-8), hence stdin and listings.

local DCS_ROOT, SAVED_GAMES, CASEFOLD
local requested, listings = {}, {}

local function norm(path) return (path:gsub('\\', '/')) end
local function dirKey(path)
	local key = norm(path):gsub('/*$', '', 1) .. '/'
	return CASEFOLD and key:lower() or key
end

do
	local currentDir
	for line in io.lines() do
		local kind, value = line:match('^(%a+)\t(.*)$')
		if kind == 'install' then DCS_ROOT = value
		elseif kind == 'saved' then SAVED_GAMES = value
		elseif kind == 'casefold' then CASEFOLD = value == '1'
		elseif kind == 'profile' then table.insert(requested, value)
		elseif kind == 'dir' then currentDir = {} listings[value] = currentDir
		elseif kind == 'entry' and currentDir then table.insert(currentDir, value)
		end
	end
	if not (DCS_ROOT and SAVED_GAMES) then
		io.stderr:write('no "install" or "saved" record on stdin\n')
		os.exit(2)
	end
	DCS_ROOT = norm(DCS_ROOT):gsub('/*$', '', 1) .. '/'
	SAVED_GAMES = norm(SAVED_GAMES):gsub('/*$', '', 1) .. '/'
	local byKey = {}
	for dir, entries in pairs(listings) do byKey[dirKey(dir)] = entries end
	listings = byKey
end

local function warn(msg) io.stderr:write('warning: ' .. tostring(msg) .. '\n') end

local function readFile(path)
	local f = io.open(path, 'rb')
	if not f then return nil end
	local s = f:read('*a')
	f:close()
	return (s:gsub('^\239\187\191', '')) -- UTF-8 BOM, which Lua 5.1 refuses to load
end

local function isAbsolute(path) return path:match('^%a:[/\\]') or path:match('^/') end

local function loadChunk(path)
	local src = readFile(path)
	if not src then return nil, 'not found: ' .. path end
	return loadstring(src, '@' .. path)
end

-- Entries of a directory listed by effective_bindings.py; none for a directory it did not list
local function listDir(path)
	return listings[dirKey(path)] or {}
end

-- Engine commands (iCommand*) are numbers provided by the DCS executable, not by any Lua file.
-- They become symbols here, resolved later from the diffs (see learnSymbols).
local SYMBOL_PREFIX = '@'
setmetatable(_G, {__index = function(_, name)
	if type(name) == 'string' and name:match('^iCommand') then return SYMBOL_PREFIX .. name end
end})

-- dofile is relative to the DCS install, as in the game (whose working directory is the install)
function dofile(path)
	if not isAbsolute(path) then path = DCS_ROOT .. path end
	local f = assert(loadChunk(path))
	return f()
end

local defaultAssignments = assert(loadChunk(DCS_ROOT .. 'Scripts/Input/DefaultAssignments.lua'))()

local function templateName(deviceName) return (deviceName:gsub('(.*)(%s{.*})', '%1')) end

local loadProfileFile

-- Environment of a profile file: the helpers Scripts/Input/Data.lua gives it
local function makeEnv(filename, folder, deviceName)
	local env = {}
	local generic = deviceName and templateName(deviceName)
	env.folder, env.filename, env.deviceName = folder, filename, deviceName
	env._ = function(s) return s end
	env.external_profile = function(f, folderNew)
		if not isAbsolute(f) then f = DCS_ROOT .. f end
		return loadProfileFile(f, deviceName, folderNew or folder)
	end
	env.join = function(to, from)
		for _, v in ipairs(from) do table.insert(to, v) end
		return to
	end
	env.ignore_features = function(commands, features)
		local set = {}
		for _, f in ipairs(features) do set[f] = true end
		for i = #commands, 1, -1 do
			for _, f in ipairs(commands[i].features or {}) do
				if set[f] then table.remove(commands, i) break end
			end
		end
	end
	env.defaultFFB = function() return {} end
	env.defaultDeviceAssignmentFor = function(name)
		local assignments = (generic and defaultAssignments[generic]) or defaultAssignments.default
		local assigned = assignments[name]
		if type(assigned) == 'table' then
			if assigned.key ~= nil then return {assigned} end
		elseif assigned ~= nil then
			return {{key = assigned}}
		end
	end
	env.MultiEngineDefaultDeviceAssignmentForThrust = function()
		local common = env.defaultDeviceAssignmentFor('thrust')
		local left = env.defaultDeviceAssignmentFor('thrust_left')
		local right = env.defaultDeviceAssignmentFor('thrust_right')
		if not common then return nil, left, right end
		if left and left[1].key and right and right[1].key then return nil, left, right end
		return common, nil, nil
	end
	env.bindKeyboardCommandsToMouse = function(unitInputFolder)
		local keyboard = env.external_profile(unitInputFolder .. 'keyboard/default.lua')
		local mouse = env.external_profile('Config/Input/Aircrafts/Default/mouse/default.lua')
		for _, c in ipairs(keyboard.keyCommands) do c.combos = nil end
		env.join(mouse.keyCommands, keyboard.keyCommands)
		return mouse
	end
	return setmetatable(env, {__index = _G})
end

-- Quaggles Input Command Injector (hook Scripts/Hooks/QuagglesInputCommandInjector.lua): for each
-- profile file loaded from Mods/aircraft/ or Config/Input/, the file at the same relative path
-- under Saved Games/DCS/InputCommands/ runs in the same environment and its commands are appended.
local injectorActive = readFile(DCS_ROOT .. 'Scripts/Hooks/QuagglesInputCommandInjector.lua') ~= nil
	or readFile(SAVED_GAMES .. 'Scripts/Hooks/QuagglesInputCommandInjector.lua') ~= nil

local function injectedFileFor(filename)
	for _, prefix in ipairs({'Mods/aircraft/', 'Config/Input/'}) do
		if filename:sub(1, #DCS_ROOT + #prefix) == DCS_ROOT .. prefix then
			return SAVED_GAMES .. 'InputCommands/' .. filename:sub(#DCS_ROOT + #prefix + 1)
		end
	end
end

local function injectCommands(filename, env, result)
	local injected = injectedFileFor(filename)
	local f = injected and loadChunk(injected)
	if not f then return end
	setfenv(f, env)
	local ok, res = pcall(f)
	if not ok then warn(res) return end
	for _, field in ipairs({'keyCommands', 'axisCommands'}) do
		if result[field] and res[field] then
			env.join(result[field], res[field])
		elseif res[field] then
			result[field] = res[field]
		end
	end
end

loadProfileFile = function(filename, deviceName, folder)
	local f = loadChunk(filename)
	if not f then return nil end
	local env = makeEnv(filename, folder, deviceName)
	setfenv(f, env)
	local ok, res = pcall(f)
	if not ok then warn(res) return nil end
	if injectorActive and type(res) == 'table' then injectCommands(filename, env, res) end
	return res
end

local function loadDiffFile(filename)
	local f = loadChunk(filename)
	if not f then return nil end
	setfenv(f, {})
	local ok, res = pcall(f)
	if not ok then warn(res) return nil end
	return res
end

-- Base profile of a device, as DCS picks it (Data.lua, loadProfileDefaultDeviceProfile_): its
-- template, else default.lua; for a unit profile, then the same two in the Default unit.
local DEFAULT_UNIT_FOLDER = 'Config/Input/Aircrafts/Default/'
local function loadBase(baseFolder, deviceName, deviceType, unitProfile)
	local folders = {baseFolder}
	if unitProfile then table.insert(folders, DCS_ROOT .. DEFAULT_UNIT_FOLDER .. deviceType .. '/') end
	for _, folder in ipairs(folders) do
		for _, file in ipairs({folder .. templateName(deviceName) .. '.lua', folder .. 'default.lua'}) do
			local base = loadProfileFile(file, deviceName, folder)
			if base then return base, file end
		end
	end
end

-- Command hash (Scripts/Input/Utils.lua, getCommandHash)
local KEY_HASH = {{'down', 'd'}, {'pressed', 'p'}, {'up', 'u'}, {'cockpit_device_id', 'cd'},
	{'value_down', 'vd'}, {'value_pressed', 'vp'}, {'value_up', 'vu'}}
local AXIS_HASH = {{'action', 'a'}, {'cockpit_device_id', 'cd'}}

local symbolVotes = {} -- iCommandXxx -> {number -> votes}, learned from the diffs
local symbolValues = {} -- iCommandXxx -> number, the value with the most votes

local function hashOf(command, infos)
	local parts = {}
	for _, info in ipairs(infos) do
		local v = command[info[1]]
		if type(v) == 'string' and v:sub(1, 1) == SYMBOL_PREFIX then
			v = symbolValues[v:sub(2)] or v
		end
		table.insert(parts, info[2] .. tostring(v))
	end
	return table.concat(parts)
end

-- A diff entry carries the numeric hash and the name of its command: for a base command of the
-- same name whose hash contains symbols, this gives a vote for the value of each symbol.
local function learnSymbols(commands, diffs, infos)
	if not (commands and diffs) then return end
	local byName = {}
	for _, c in ipairs(commands) do
		if c.name then
			byName[c.name] = byName[c.name] or {}
			table.insert(byName[c.name], c)
		end
	end
	for diffHash, d in pairs(diffs) do
		for _, c in ipairs(byName[d.name] or {}) do
			local symbols, pattern = {}, {}
			for _, info in ipairs(infos) do
				local v = c[info[1]]
				if type(v) == 'string' and v:sub(1, 1) == SYMBOL_PREFIX then
					table.insert(symbols, v:sub(2))
					table.insert(pattern, info[2] .. '(%-?%d+)')
				else
					table.insert(pattern, ((info[2] .. tostring(v)):gsub('%p', '%%%0')))
				end
			end
			if #symbols > 0 then
				local captures = {diffHash:match('^' .. table.concat(pattern) .. '$')}
				for i, s in ipairs(symbols) do
					local value = tonumber(captures[i])
					if value then
						symbolVotes[s] = symbolVotes[s] or {}
						symbolVotes[s][value] = (symbolVotes[s][value] or 0) + 1
					end
				end
			end
		end
	end
end

-- A diff is written with the hashes of the defaults of its time: when a module later binds a
-- command name to another engine command, its old diffs vote for a wrong value (e.g. a C-130J
-- diff written when "Aircraft Pitch Down" was iCommandPlaneUpStart there, as in every other
-- module). The value with the most votes wins; disagreements are reported.
local function resolveSymbols()
	local conflicts = {} -- symbol -> {value as text -> votes}
	for s, votes in pairs(symbolVotes) do
		local best, bestVotes, count = nil, 0, 0
		local byText = {}
		for value, n in pairs(votes) do
			count = count + 1
			byText[tostring(value)] = n
			if n > bestVotes or (n == bestVotes and value < best) then best, bestVotes = value, n end
		end
		symbolValues[s] = best
		if count > 1 then conflicts[s] = byText end
	end
	return conflicts
end

-- Diff application (Scripts/Input/Data.lua, applyDiffToCommands_)
local function comboHash(combo)
	local h = combo.key or ''
	if combo.reformers then
		local r = {}
		for i, v in ipairs(combo.reformers) do r[i] = v end
		table.sort(r)
		h = h .. table.concat(r)
	end
	return h
end

local function removeCombos(combos, removed)
	for _, combo in ipairs(removed or {}) do
		for i = #combos, 1, -1 do
			if comboHash(combos[i]) == comboHash(combo) then table.remove(combos, i) break end
		end
	end
end

local function addCombos(combos, added)
	for _, combo in ipairs(added or {}) do
		local found = false
		for _, c in ipairs(combos) do
			if comboHash(c) == comboHash(combo) then found = true break end
		end
		if not found then table.insert(combos, combo) end
	end
end

-- Returns the diff entries matching no base command: DCS ignores them too, but here it can also
-- mean an unresolved iCommand symbol.
local function applyDiff(commands, diff, infos)
	if not (diff and next(diff) and commands) then return {} end
	local matched, diffInfos = {}, {}
	for diffHash, d in pairs(diff) do
		for _, combo in ipairs(d.added or {}) do
			local h = comboHash(combo)
			diffInfos[h] = diffInfos[h] or {}
			diffInfos[h].addedHash = diffHash
		end
		for _, combo in ipairs(d.removed or {}) do
			local h = comboHash(combo)
			diffInfos[h] = diffInfos[h] or {}
			diffInfos[h].removedHash = diffHash
		end
	end
	for _, command in ipairs(commands) do
		local hash = hashOf(command, infos)
		local combos = command.combos
		if combos then
			local updated = false
			for _, combo in ipairs(combos) do
				local info = diffInfos[comboHash(combo)]
				if info and hash ~= info.addedHash and hash ~= info.removedHash then updated = true break end
			end
			if not updated then
				-- DCS removes from the defaults every combo the diff mentions, so that an update
				-- of the defaults cannot conflict with the user's settings
				for _, d in pairs(diff) do
					removeCombos(combos, d.added)
					removeCombos(combos, d.removed)
					removeCombos(combos, d.changed)
				end
			end
		end
		local d = diff[hash]
		if d then
			matched[hash] = true
			if not combos then combos = {} command.combos = combos end
			removeCombos(combos, d.removed)
			addCombos(combos, d.added)
			addCombos(combos, d.changed)
		end
	end
	local unmatched = {}
	for diffHash, d in pairs(diff) do
		if not matched[diffHash] then table.insert(unmatched, {hash = diffHash, name = d.name}) end
	end
	return unmatched
end

-- Profiles DCS creates itself (Scripts/Input/ProfileDatabase.lua): unit name -> folder under
-- Config/Input/
local BUILTIN_PROFILES = {
	['Default'] = 'Aircrafts/Default', ['UiLayer'] = 'UiLayer', ['CameraFree'] = 'CameraFree',
	['GeoTerrain'] = 'GeoTerrain', ['CameraObject'] = 'CameraObject', ['CameraRoom'] = 'CameraRoom',
	['VoiceChat'] = 'VoiceChat', ['JFT binocular'] = 'JFT/binocular', ['JFT camera'] = 'JFT/camera',
	['JFT global'] = 'JFT/global', ['Explorations'] = 'Explorations', ['CommandMenu'] = 'CommandMenu',
	['TrainingWaitForUser'] = 'TrainingWaitForUser',
}

-- Stands for anything an entry.lua may use besides declare_plugin: callable, indexable,
-- concatenable, so that the script runs far enough to declare its input profiles.
local stub
stub = setmetatable({}, {
	__index = function() return stub end,
	__newindex = function() end,
	__call = function() return stub end,
	__concat = function() return stub end,
	__add = function() return stub end, __sub = function() return stub end,
	__mul = function() return stub end, __div = function() return stub end,
	__unm = function() return stub end,
})

-- InputProfiles of a module: the table its entry.lua passes to declare_plugin, unit name -> folder
local function moduleInputProfiles(modDir)
	local f = loadChunk(modDir .. 'entry.lua')
	if not f then return {} end
	local declared = {}
	local env = setmetatable({
		current_mod_path = modDir:gsub('/$', ''),
		declare_plugin = function(_, plugin)
			if type(plugin) == 'table' and type(plugin.InputProfiles) == 'table' then
				for unitName, folder in pairs(plugin.InputProfiles) do
					if type(unitName) == 'string' and type(folder) == 'string' then
						declared[unitName] = norm(folder):gsub('/+$', '') .. '/'
					end
				end
			end
		end,
		_ = function(s) return s end,
		dofile = function() return stub end,
		loadfile = function() return function() return stub end end,
		require = function() return stub end,
	}, {__index = function(_, k) return rawget(_G, k) or stub end})
	setfenv(f, env)
	pcall(f) -- an error after declare_plugin does not matter
	return declared
end

-- Profiles of the install: unit name -> {folder = profile folder, unit = is a unit profile}.
-- The unit name, stripped of the characters a file name cannot hold, is the profile's folder in
-- Saved Games/DCS/Config/Input/.
local function listProfiles()
	local result, seenFolders = {}, {}
	local function add(unitName, folder, unit)
		local userName = unitName:gsub('[%*/%?<>|\\:"]', '')
		if not result[userName] then
			result[userName] = {folder = folder, unit = unit}
			seenFolders[folder] = true
		end
	end
	for unitName, folder in pairs(BUILTIN_PROFILES) do
		-- of these, only Default is a unit profile (ProfileDatabase.lua, LoadDefaultUnitProfile)
		add(unitName, DCS_ROOT .. 'Config/Input/' .. folder .. '/', unitName == 'Default')
	end
	-- community modules (e.g. the A-4E-C) are installed in Saved Games
	local moduleRoots = {DCS_ROOT .. 'Mods/aircraft/', DCS_ROOT .. 'CoreMods/aircraft/', DCS_ROOT .. 'Mods/tech/',
		SAVED_GAMES .. 'Mods/aircraft/'}
	for _, root in ipairs(moduleRoots) do
		for _, mod in ipairs(listDir(root)) do
			local modDir = root .. mod .. '/'
			for unitName, folder in pairs(moduleInputProfiles(modDir)) do add(unitName, folder, true) end
			-- fallback for an Input folder no InputProfiles entry points to: its name.lua
			local inputDir = modDir .. 'Input/'
			for _, profile in ipairs(listDir(inputDir)) do
				local folder = inputDir .. profile .. '/'
				local f = not seenFolders[folder] and loadChunk(folder .. 'name.lua')
				if f then
					setfenv(f, {_ = function(s) return s end})
					local ok, name = pcall(f, profile)
					if ok and type(name) == 'string' then add(name, folder, true) end
				end
			end
		end
	end
	return result
end

-- Learns the iCommand numbers from every profile: each diff (the user's or shipped with the
-- module) matched by name to the base DCS would apply it to. A command renamed in one module is
-- thus caught by another module where its name did not change.
local function learnAllSymbols(profiles)
	local seenFolders = {} -- a folder shared by several units counts its own diffs once
	for userName, profile in pairs(profiles) do
		for _, deviceType in ipairs({'joystick', 'keyboard'}) do
			local baseFolder = profile.folder .. deviceType .. '/'
			local userFolder = SAVED_GAMES .. 'Config/Input/' .. userName .. '/' .. deviceType .. '/'
			local folders = {userFolder}
			if not seenFolders[baseFolder] then
				seenFolders[baseFolder] = true
				table.insert(folders, baseFolder)
			end
			local diffFiles = {}
			for _, folder in ipairs(folders) do
				for _, file in ipairs(listDir(folder)) do
					local deviceName = file:match('^(.*)%.diff%.lua$')
					if deviceName then table.insert(diffFiles, {folder .. file, deviceName}) end
				end
			end
			local bases = {}
			for _, item in ipairs(diffFiles) do
				local path, deviceName = item[1], item[2]
				local template = templateName(deviceName)
				if bases[template] == nil then
					bases[template] = loadBase(baseFolder, deviceName, deviceType, profile.unit) or false
				end
				local base, diff = bases[template], loadDiffFile(path)
				if base and diff then
					learnSymbols(base.keyCommands, diff.keyDiffs, KEY_HASH)
					learnSymbols(base.axisCommands, diff.axisDiffs, AXIS_HASH)
				end
			end
		end
	end
end

-- JSON. A table is an array when it has a first element, or when it is empty unless marked with
-- asObject.
local OBJECT = {}
local function asObject(t) return setmetatable(t, OBJECT) end

local function jsonEncode(v)
	local t = type(v)
	if t == 'nil' then return 'null'
	elseif t == 'boolean' or t == 'number' then return tostring(v)
	elseif t == 'string' then
		return '"' .. v:gsub('[%c"\\]', function(c)
			local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
			return map[c] or string.format('\\u%04x', c:byte())
		end) .. '"'
	end
	if getmetatable(v) ~= OBJECT and (#v > 0 or next(v) == nil) then
		local out = {}
		for _, x in ipairs(v) do table.insert(out, jsonEncode(x)) end
		return '[' .. table.concat(out, ',') .. ']'
	end
	local keys, out = {}, {}
	for k in pairs(v) do table.insert(keys, k) end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do table.insert(out, jsonEncode(tostring(k)) .. ':' .. jsonEncode(v[k])) end
	return '{' .. table.concat(out, ',') .. '}'
end

local function categoryOf(c)
	if type(c.category) == 'table' then return c.category end
	if c.category then return {c.category} end
	return {}
end

-- natural order: JOY_BTN2 before JOY_BTN10
local function sortKey(key)
	return (key:gsub('%d+', function(n) return string.format('%06d', tonumber(n)) end))
end

-- Effective bindings of one joystick, one entry per (command hash, combo): commands sharing a
-- hash (e.g. a community keybind and an ED command) are one command for DCS, the first name wins.
local function deviceBindings(baseFolder, userFolder, deviceName, unitProfile)
	local base, baseFile = loadBase(baseFolder, deviceName, 'joystick', unitProfile)
	if not base then
		warn('no base profile for ' .. deviceName)
		return {name = deviceName, error = 'no base profile'}
	end
	local diffFile = userFolder .. deviceName .. '.diff.lua'
	local diff = loadDiffFile(diffFile)
	if not diff then
		diffFile = baseFolder .. templateName(deviceName) .. '.diff.lua'
		diff = loadDiffFile(diffFile)
	end
	local unmatched = applyDiff(base.keyCommands, diff and diff.keyDiffs, KEY_HASH)
	for _, u in ipairs(applyDiff(base.axisCommands, diff and diff.axisDiffs, AXIS_HASH)) do
		table.insert(unmatched, u)
	end

	local bindings, seen = {}, {}
	for _, kind in ipairs({'key', 'axis'}) do
		local commands = (kind == 'key' and base.keyCommands or base.axisCommands) or {}
		for _, c in ipairs(commands) do
			local hash = hashOf(c, kind == 'key' and KEY_HASH or AXIS_HASH)
			for _, combo in ipairs(c.combos or {}) do
				local id = hash .. '|' .. comboHash(combo)
				if combo.key and not seen[id] then
					seen[id] = true
					table.insert(bindings, {
						kind = kind,
						hash = hash,
						key = combo.key,
						reformers = combo.reformers or {},
						command = c.name,
						category = categoryOf(c),
					})
				end
			end
		end
	end
	table.sort(bindings, function(a, b)
		if a.key ~= b.key then return sortKey(a.key) < sortKey(b.key) end
		return (a.command or '') < (b.command or '')
	end)
	return {
		name = deviceName,
		base_file = baseFile,
		diff_file = diff and diffFile or nil,
		bindings = bindings,
		unmatched_diffs = unmatched,
	}
end

-- Main program
if #requested == 0 then requested = listDir(SAVED_GAMES .. 'Config/Input/') end

local profiles = listProfiles()
learnAllSymbols(profiles)
local conflicts = resolveSymbols()

local learned = 0
for _ in pairs(symbolValues) do learned = learned + 1 end
for s, votes in pairs(conflicts) do
	local parts = {}
	for value, n in pairs(votes) do table.insert(parts, value .. ' (' .. n .. ' votes)') end
	warn(s .. ' learned with different values: ' .. table.concat(parts, ', ') .. '; kept ' .. symbolValues[s])
end

local result = {}
for _, name in ipairs(requested) do
	local profile = profiles[name]
	local entry = {found = profile ~= nil, profile_folder = profile and profile.folder, devices = {}}
	if profile then
		local baseFolder = profile.folder .. 'joystick/'
		local userFolder = SAVED_GAMES .. 'Config/Input/' .. name .. '/joystick/'
		for _, file in ipairs(listDir(userFolder)) do
			local deviceName = file:match('^(.*)%.diff%.lua$')
			local device = deviceName and deviceBindings(baseFolder, userFolder, deviceName, profile.unit)
			if device then table.insert(entry.devices, device) end
		end
	end
	result[name] = entry
end

io.write(jsonEncode({
	injector = injectorActive,
	learned_symbols = learned,
	symbol_conflicts = asObject(conflicts),
	profiles = result,
}), '\n')
