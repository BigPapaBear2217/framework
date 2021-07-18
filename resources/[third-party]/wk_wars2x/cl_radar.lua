local next = next 
local dot = dot 
local table = table 
local type = type
local tostring = tostring
local math = math 
local pairs = pairs 

-- Resource Rename Fix.
Citizen.SetTimeout( 1000, function()
	-- Get the name of the resource.
	local name = string.lower( GetCurrentResourceName() )

	-- Print a little message in the client's console.
	UTIL:Log( "Sending resource name (" .. name .. ") to JavaScript side." )

	-- Send a message through the NUI system to the JavaScript file to give the name of the resource.
	SendNUIMessage( { _type = "updatePathName", pathName = name } )
end )

-- UI loading trigger
local spawned = false 

-- Runs every time the player spawns, but the additional check means it only runs the first time the player spawns.
AddEventHandler( "playerSpawned", function()
	if ( not spawned ) then 
		UTIL:Log( "Attempting to load saved UI settings data." )

		-- Try and get the saved UI data.
		local uiData = GetResourceKvpString( "wk_wars2x_ui_data" )

		-- If the data exists, then we send it off.
		if ( uiData ~= nil ) then 
			SendNUIMessage( { _type = "loadUiSettings", data = json.decode( uiData ) } )
			
			UTIL:Log( "Saved UI settings data loaded!" )
		-- If the data doesn't exist, then we send the defaults.
		else 
			SendNUIMessage( { _type = "setUiDefaults", data = CONFIG.uiDefaults } )

			UTIL:Log( "Could not find any saved UI settings data." )
		end 

		spawned = true
	end 
end )

PLY = 
{
	ped = PlayerPedId(),
	veh = nil,
	inDriverSeat = false,
	vehClassValid = false
}

function PLY:VehicleStateValid()
	return DoesEntityExist( self.veh ) and self.veh > 0 and self.inDriverSeat and self.vehClassValid
end 

-- Update local player, ped id, vehicle id (if one), seat and vehicle class (valid or not).
Citizen.CreateThread( function()
	while ( true ) do 
		PLY.ped = PlayerPedId()
		PLY.veh = GetVehiclePedIsIn( PLY.ped, false )
		PLY.inDriverSeat = GetPedInVehicleSeat( PLY.veh, -1 ) == PLY.ped or GetPedInVehicleSeat( PLY.veh, 0 ) == PLY.ped 
		PLY.vehClassValid = GetVehicleClass( PLY.veh ) == 18

		Citizen.Wait( 500 )
	end 
end )

--[[ Radar Variables ]]--
RADAR = {}
RADAR.vars = 
{
	displayed = false,
	power = false, 
	poweringUp = false, 
	hidden = false,
	settings = {
		-- Should the system calculate and display faster targets.
		["fastDisplay"] = CONFIG.menuDefaults["fastDisplay"], 

		-- Sensitivity for each radar mode, this changes how far the antennas will detect vehicles.
		["same"] = CONFIG.menuDefaults["same"], 
		["opp"] = CONFIG.menuDefaults["opp"], 

		-- The volume of the audible beep.
		["beep"] = CONFIG.menuDefaults["beep"],
		
		-- The volume of the verbal lock confirmation.
		["voice"] = CONFIG.menuDefaults["voice"],
		
		-- The volume of the plate reader audio 
		["plateAudio"] = CONFIG.menuDefaults["plateAudio"], 

		-- The speed unit used in conversions
		["speedType"] = CONFIG.menuDefaults["speedType"]
	},

	menuActive = false, 
	currentOptionIndex = 1, 
	menuOptions = {
		{ displayText = { "¦¦¦", "FAS" }, optionsText = { "On¦", "Off" }, options = { true, false }, optionIndex = -1, settingText = "fastDisplay" },
		{ displayText = { "¦SL", "SEn" }, optionsText = { "¦1¦", "¦2¦", "¦3¦", "¦4¦", "¦5¦" }, options = { 0.2, 0.4, 0.6, 0.8, 1.0 }, optionIndex = -1, settingText = "same" },
		{ displayText = { "¦OP", "SEn" }, optionsText = { "¦1¦", "¦2¦", "¦3¦", "¦4¦", "¦5¦" }, options = { 0.2, 0.4, 0.6, 0.8, 1.0 }, optionIndex = -1, settingText = "opp" },
		{ displayText = { "bEE", "P¦¦" }, optionsText = { "Off", "¦1¦", "¦2¦", "¦3¦", "¦4¦", "¦5¦" }, options = { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 }, optionIndex = -1, settingText = "beep" },
		{ displayText = { "VOI", "CE¦" }, optionsText = { "Off", "¦1¦", "¦2¦", "¦3¦", "¦4¦", "¦5¦" }, options = { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 }, optionIndex = -1, settingText = "voice" },
		{ displayText = { "PLt", "AUd" }, optionsText = { "Off", "¦1¦", "¦2¦", "¦3¦", "¦4¦", "¦5¦" }, options = { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 }, optionIndex = -1, settingText = "plateAudio" },
		{ displayText = { "Uni", "tS¦" }, optionsText = { "USA", "INT" }, options = { "mph", "kmh" }, optionIndex = -1, settingText = "speedType" }
	},

	-- Player's vehicle speed, mainly used in the dynamic thread wait update.
	patrolSpeed = 0,

	-- Antennas, this table contains all of the data needed for operation of the front and rear antennas.
	antennas = {

		[ "front" ] = {
			xmit = false,			-- Whether the antenna is transmitting or in hold.
			mode = 0,				-- Current antenna mode, 0 = none, 1 = same, 2 = opp, 3 = same and opp.
			speed = 0,				-- Speed of the vehicle caught by the front antenna.
			dir = nil, 				-- Direction the caught vehicle is going, 0 = towards, 1 = away.
			fastSpeed = 0, 			-- Speed of the fastest vehicle caught by the front antenna.
			fastDir = nil, 			-- Direction the fastest vehicle is going.
			speedLocked = false, 	-- A speed has been locked for this antenna.
			lockedSpeed = nil, 		-- The locked speed.
			lockedDir = nil, 		-- The direction of the vehicle that was locked.
			lockedType = nil        -- The locked type, 1 = strongest, 2 = fastest.
		}, 

		[ "rear" ] = {
			xmit = false,			-- Whether the antenna is transmitting or in hold.
			mode = 0,				-- Current antenna mode, 0 = none, 1 = same, 2 = opp, 3 = same and opp.
			speed = 0,				-- Speed of the vehicle caught by the front antenna.
			dir = nil, 				-- Direction the caught vehicle is going, 0 = towards, 1 = away.
			fastSpeed = 0, 			-- Speed of the fastest vehicle caught by the front antenna.
			fastDir = nil, 			-- Direction the fastest vehicle is going.
			speedLocked = false,	-- A speed has been locked for this antenna.
			lockedSpeed = nil,		-- The locked speed.
			lockedDir = nil,		-- The direction of the vehicle that was locked.
			lockedType = nil        -- The locked type, 1 = strongest, 2 = fastest.
		}
	}, 
	
	maxCheckDist = 350.0,

	-- Cached dynamic vehicle sphere sizes, automatically populated when the system is running.
	sphereSizes = {}, 

	-- Table to store tables for hit entities of captured vehicles.
	capturedVehicles = {},

	-- Table for temp id storage to stop unnecessary trace checks needs to be redone.
	-- tempVehicleIDs = {},

	-- Table to store the valid vehicle models.
	validVehicles = {}, 

	-- The current vehicle data for display.
	activeVehicles = {},

	-- Vehicle pool, automatically populated when the system is running, holds all of the current vehicle IDs for the player using entity enumeration (see cl_utils.lua).
	vehiclePool = {}, 

	-- Ray trace state, this is used so the radar system doesn't initiate another set of ray traces until the current set has finished.
	rayTraceState = 0,

	-- Number of ray traces, automatically cached when the system first runs.
	numberOfRays = 0,

	-- The wait time for the ray trace system, this changes dynamically based on if the player's vehicle is stationary or not.
	threadWaitTime = 500, 
	
	-- Key lock, when true, prevents any of the radar's key events from working, like the ELS key lock.
	keyLock = false
}

-- Speed conversion values.
RADAR.speedConversions = { ["mph"] = 2.236936, ["kmh"] = 3.6 }

-- These vectors are used in the custom ray tracing system.
RADAR.rayTraces = {
	{ startVec = { x = 0.0 }, endVec = { x = 0.0, y = 0.0 }, rayType = "same" },
	{ startVec = { x = -5.0 }, endVec = { x = -5.0, y = 0.0 }, rayType = "same" },
	{ startVec = { x = 5.0 }, endVec = { x = 5.0, y = 0.0 }, rayType = "same" },
	{ startVec = { x = -10.0 }, endVec = { x = -10.0, y = 0.0 }, rayType = "opp" },
	{ startVec = { x = -17.0 }, endVec = { x = -17.0, y = 0.0 }, rayType = "opp" }
}

-- Each of these are used for sorting the captured vehicle data, the 'strongest' filter is used for the main target window of each antenna, whereas the 'fastest' filter is used for the fast target window of each antenna.
RADAR.sorting = {
	strongest = function( a, b ) return a.size > b.size end, 
	fastest = function( a, b ) return a.speed > b.speed end
}

--[[ Radar Essentials ]]--
function RADAR:IsPowerOn()
	return self.vars.power 
end 

-- Returns if the radar system is powering up, the powering up stage only takes 2 seconds.
function RADAR:IsPoweringUp()
	return self.vars.poweringUp
end 

-- Allows the powering up state variable to be set.
function RADAR:SetPoweringUpState( state )
	self.vars.poweringUp = state 
end 

-- Toggles the radar power.
function RADAR:TogglePower()
	-- Toggle the power variable.
	self.vars.power = not self.vars.power 
	
	-- Send the NUI message to toggle the power.
	SendNUIMessage( { _type = "radarPower", state = self:IsPowerOn() } )

	-- Power is now turned on.
	if ( self:IsPowerOn() ) then 
		-- Also make sure the operator menu is inactive.
		self:SetMenuState( false )
		
		-- Tell the system the radar is 'powering up'.
		self:SetPoweringUpState( true )

		-- Set a 2 second countdown .
		Citizen.SetTimeout( 2000, function()
			-- Tell the system the radar has 'powered up'.
			self:SetPoweringUpState( false )

			-- Let the UI side know the system has loaded.
			SendNUIMessage( { _type = "poweredUp" } )
		end )
	else 
		-- If the system is being turned off, then we reset the antennas.
		self:ResetAntenna( "front" )
		self:ResetAntenna( "rear" )
	end
end

-- Toggles the display state of the radar system.
function RADAR:ToggleDisplayState()
	-- Toggle the display variable.
	self.vars.displayed = not self.vars.displayed 

	-- Send the toggle message to the NUI side.
	SendNUIMessage( { _type = "setRadarDisplayState", state = self:GetDisplayState() } )
end 

-- Gets the display state.
function RADAR:GetDisplayState()
	return self.vars.displayed
end 

-- Used to set individual settings within RADAR.vars.settings, as all of the settings use string keys, using this function makes updating settings easier.
function RADAR:SetSettingValue( setting, value )
	-- Make sure that we're not trying to set a nil value for the setting.
	if ( value ~= nil ) then 
		-- Set the setting's value.
		self.vars.settings[setting] = value 

		-- If the setting that's being updated is same or opp, then we update the end coordinates for the ray tracer.
		if ( setting == "same" or setting == "opp" ) then 
			self:UpdateRayEndCoords()
		end 
	end 
end 

-- Returns the value of the given setting.
function RADAR:GetSettingValue( setting )
	return self.vars.settings[setting]
end

-- Return the state of the fastDisplay setting, short hand direct way to check if the fast system is enabled.
function RADAR:IsFastDisplayEnabled()
	return self.vars.settings["fastDisplay"]
end 

-- Returns if either of the antennas are transmitting.
function RADAR:IsEitherAntennaOn()
	return self:IsAntennaTransmitting( "front" ) or self:IsAntennaTransmitting( "rear" )
end 

-- Sends an update to the NUI side with the current state of the antennas and if the fast system is enabled.
function RADAR:SendSettingUpdate()
	-- Create a table to store the setting information for the antennas.
	local antennas = {}

	-- Iterate through each antenna and grab the relevant information.
	for ant in UTIL:Values( { "front", "rear" } ) do 
		antennas[ant] = {}
		antennas[ant].xmit = self:IsAntennaTransmitting( ant )
		antennas[ant].mode = self:GetAntennaMode( ant )
		antennas[ant].speedLocked = self:IsAntennaSpeedLocked( ant )
		antennas[ant].fast = self:ShouldFastBeDisplayed( ant )
	end 

	-- Send a message to the NUI side with the current state of the antennas.
	SendNUIMessage( { _type = "settingUpdate", antennaData = antennas } )
end 

-- Returns if a main task can be performed. A main task such as the ray trace thread should only run if the radar's power is on, the system is not in the process of powering up, and the operator menu is not open.
function RADAR:CanPerformMainTask()
	return self:IsPowerOn() and not self:IsPoweringUp() and not self:IsMenuOpen()
end 

-- Returns what the dynamic thread wait time is.
function RADAR:GetThreadWaitTime()
	return self.vars.threadWaitTime
end 

-- Sets the dynamic thread wait time to the given value.
function RADAR:SetThreadWaitTime( time )
	self.vars.threadWaitTime = time 
end 

-- Sets the display's hidden state to the given state.
function RADAR:SetDisplayHidden( state )
	self.vars.hidden = state 
end 

-- Returns if the display is hidden.
function RADAR:GetDisplayHidden()
	return self.vars.hidden 
end

-- Opens the remote only if the pause menu is not open and the player's vehicle state is valid.
function RADAR:OpenRemote()
	if ( not IsPauseMenuActive() and PLY:VehicleStateValid() ) then 
		-- Tell the NUI side to open the remote.
		SendNUIMessage( { _type = "openRemote" } )

		if ( CONFIG.allow_quick_start_video ) then 
			-- Display the new user popup if we can.
			local show = GetResourceKvpInt( "wk_wars2x_new_user" )

			if ( show == 0 ) then 
				SendNUIMessage( { _type = "showNewUser" } )
			end 
		end 

		-- Bring focus to the NUI side.
		SetNuiFocus( true, true )
	end
end 

-- Event to open the remote.
RegisterNetEvent( "wk:openRemote" )
AddEventHandler( "wk:openRemote", function()
	RADAR:OpenRemote()
end )

-- Returns if the fast limit option should be available for the radar.
function RADAR:IsFastLimitAllowed()
	return CONFIG.allow_fast_limit
end

-- Only create the functions if the fast limit config option is enabled.
if ( RADAR:IsFastLimitAllowed() ) then
	-- Adds settings into the radar's variables for when the allow_fast_limit variable is true.
	function RADAR:CreateFastLimitConfig()
		-- Create the options for the menu.
		local fastOptions = 
		{
			{ displayText = { "FAS", "Loc" }, optionsText = { "On¦", "Off" }, options = { true, false }, optionIndex = 2, settingText = "fastLock" },
			{ displayText = { "FAS", "SPd" }, optionsText = {}, options = {}, optionIndex = 12, settingText = "fastLimit" }
		}

		-- Iterate from 5 to 200 in steps of 5 and insert into the fast limit option.
		for i = 5, 200, 5 do
			local text = UTIL:FormatSpeed( i )

			table.insert( fastOptions[2].optionsText, text )
			table.insert( fastOptions[2].options, i )
		end 

		-- Create the settings with the default options.
		self:SetSettingValue( "fastLock", false )
		self:SetSettingValue( "fastLimit", 60 )

		-- Add the fast options to the main menu options table.
		table.insert( self.vars.menuOptions, fastOptions[1] )
		table.insert( self.vars.menuOptions, fastOptions[2] )
	end 

	-- Returns the numerical fast limit.
	function RADAR:GetFastLimit()
		return self.vars.settings["fastLimit"]
	end 

	-- Returns if the fast lock menu option is on or off.
	function RADAR:IsFastLockEnabled()
		return self.vars.settings["fastLock"]
	end 
end 

-- Toggles the internal key lock state, which stops any of the radar's key binds from working.
function RADAR:ToggleKeyLock()
	-- Check the player state is valid.
	if ( PLY:VehicleStateValid() ) then 
		-- Toggle the key lock variable.
		self.vars.keyLock = not self.vars.keyLock

		-- Tell the NUI side to display the key lock message.
		SendNUIMessage( { _type = "displayKeyLock", state = self:GetKeyLockState() } )
	end
end 

-- Returns the key lock state.
function RADAR:GetKeyLockState()
	return self.vars.keyLock
end 

--[[ Radar Menu Functions ]]--
-- Sets the menu state to the given state.
function RADAR:SetMenuState( state )
	-- Make sure that the radar's power is on.
	if ( self:IsPowerOn() ) then 
		-- Set the menuActive variable to the given state.
		self.vars.menuActive = state

		-- If we are opening the menu, make sure the first item is displayed.
		if ( state ) then 
			self.vars.currentOptionIndex = 1
		end
	end
end 

-- Returns if the operator menu is open.
function RADAR:IsMenuOpen()
	return self.vars.menuActive
end 

-- This function changes the menu index variable so the user can iterate through the options in the operator menu.
function RADAR:ChangeMenuIndex()
	-- Create a temporary variable of the current menu index plus 1.
	local temp = self.vars.currentOptionIndex + 1

	-- If the temporary value is larger than how many options there are, set it to 1, this way the menu loops back round to the start of the menu.
	if ( temp > #self.vars.menuOptions ) then 
		temp = 1 
	end 

	-- Set the menu index variable to the temporary value we created.
	self.vars.currentOptionIndex = temp

	-- Call the function to send an update to the NUI side.
	self:SendMenuUpdate()
end 

-- Returns the option table of the current menu index.
function RADAR:GetMenuOptionTable()
	return self.vars.menuOptions[self.vars.currentOptionIndex]
end 

-- Changes the index for an individual option E.g. { "On" "Off" }, index = 2 would be "Off".
function RADAR:SetMenuOptionIndex( index )
	self.vars.menuOptions[self.vars.currentOptionIndex].optionIndex = index
end 

-- Returns the option value for the current option.
function RADAR:GetMenuOptionValue()
	local opt = self:GetMenuOptionTable()
	local index = opt.optionIndex

	return opt.options[index]
end 

-- This function is similar to RADAR:ChangeMenuIndex() but allows for iterating forward and backward through options.
function RADAR:ChangeMenuOption( dir )
	-- Get the option table of the currently selected option.
	local opt = self:GetMenuOptionTable()

	-- Get the current option index of the selected option.
	local index = opt.optionIndex

	-- Cache the size of this setting's options table.
	local size = #opt.options

	-- As the XMIT/HOLD buttons are used for changing the option values, we have to check which button is being pressed.
	if ( dir == "front" ) then 
		index = index + 1
		if ( index > size ) then index = 1 end 
	elseif ( dir == "rear" ) then 
		index = index - 1
		if ( index < 1 ) then index = size end 
	end

	-- Update the option's index.
	self:SetMenuOptionIndex( index )

	-- Change the value of the setting in the main RADAR.vars.settings table.
	self:SetSettingValue( opt.settingText, self:GetMenuOptionValue() )

	-- Call the function to send an update to the NUI side.
	self:SendMenuUpdate()
end 

-- Returns what text should be displayed in the boxes for the current option E.g. "¦SL" "SEN".
function RADAR:GetMenuOptionDisplayText()
	return self:GetMenuOptionTable().displayText
end 

-- Returns the option text of the currently selected setting.
function RADAR:GetMenuOptionText()
	local opt = self:GetMenuOptionTable()

	return opt.optionsText[opt.optionIndex]
end 

-- Sends a message to the NUI side with updated information on what should be displayed for the menu.
function RADAR:SendMenuUpdate()
	SendNUIMessage( { _type = "menu", text = self:GetMenuOptionDisplayText(), option = self:GetMenuOptionText() } )
end 

-- Attempts to load the saved operator menu data.
function RADAR:LoadOMData()
	UTIL:Log( "Attempting to load saved operator menu data." )

	-- Try and get the data
	local rawData = GetResourceKvpString( "wk_wars2x_om_data" )

	-- If the data exists, decode it and replace the operator menu table.
	if ( rawData ~= nil ) then 
		local omData = json.decode( rawData )
		self.vars.settings = omData

		UTIL:Log( "Saved operator menu data loaded!" )
	else 
		UTIL:Log( "Could not find any saved operator menu data." )
	end 
end 

-- Updates the operator menu option indexes, as the default menu values can be changed in the config, we need to update the indexes otherwise the menu will display the wrong values.
function RADAR:UpdateOptionIndexes()
	self:LoadOMData()

	-- Iterate through each of the internal settings.
	for k, v in pairs( self.vars.settings ) do     
		-- Iterate through all of the menu options.
		for i, t in pairs( self.vars.menuOptions ) do 
			-- If the current menu option is the same as the current setting.
			if ( t.settingText == k ) then 
				-- Iterate through the option values of the current menu option.
				for oi, ov in pairs( t.options ) do 
					-- If the value of the current option set in the config matches the current value of the option value, then we update the option index variable.
					if ( v == ov ) then 
						t.optionIndex = oi
					end 
				end 
			end 
		end 
	end 
end 

--[[ Radar Basic Functions ]]-- 
-- Returns the patrol speed value stored.
function RADAR:GetPatrolSpeed()	
	return self.vars.patrolSpeed
end 

-- Returns the current vehicle pool.
function RADAR:GetVehiclePool()
	return self.vars.vehiclePool
end 

-- Returns the maximum distance a ray trace can go.
function RADAR:GetMaxCheckDist()
	return self.vars.maxCheckDist
end 

-- Returns the table sorting function 'strongest'.
function RADAR:GetStrongestSortFunc()
	return self.sorting.strongest 
end 

-- Returns the table sorting function 'fastest'.
function RADAR:GetFastestSortFunc()
	return self.sorting.fastest
end 

-- Sets the patrol speed to a formatted version of the given number.
function RADAR:SetPatrolSpeed( speed )
	if ( type( speed ) == "number" ) then 
		self.vars.patrolSpeed = self:GetVehSpeedConverted( speed )
	end
end

-- Sets the vehicle pool to the given value if it's a table.
function RADAR:SetVehiclePool( pool )
	if ( type( pool ) == "table" ) then 
		self.vars.vehiclePool = pool 
	end
end 

--[[ Radar ray trace functions ]]--
-- Returns what the current ray trace state is.
function RADAR:GetRayTraceState()
	return self.vars.rayTraceState
end

-- Caches the number of ray traces in RADAR.rayTraces.
function RADAR:CacheNumRays()
	self.vars.numberOfRays = #self.rayTraces
end 

-- Returns the number of ray traces the system has.
function RADAR:GetNumOfRays()
	return self.vars.numberOfRays
end

-- Increases the system's ray trace state ny 1.
function RADAR:IncreaseRayTraceState()
	self.vars.rayTraceState = self.vars.rayTraceState + 1
end 

-- Resets the ray trace state to 0.
function RADAR:ResetRayTraceState()
	self.vars.rayTraceState = 0
end 

-- This function is used to determine if a sphere intersect is in front or behind the player's vehicle, the sphere intersect calculation has a 'tProj' value that is a line from the centre of the sphere that goes onto the line being traced. This value will either be positive or negative and can be used to work out the relative position of a point.
function RADAR:GetIntersectedVehIsFrontOrRear( t )
	if ( t > 8.0 ) then 
		return 1 -- Vehicle is in front.
	elseif ( t < -8.0 ) then 
		return -1 -- Vehicle is behind.
	end 

	return 0 -- Vehicle is next to self.
end 

-- It does Raycasts.
function RADAR:GetLineHitsSphereAndDir( c, radius, rs, re )
	-- Take the vector3's and turn them into vector2's, this way all of the calculations below are for an infinite cylinder rather than a sphere.
	local rayStart = vector2( rs.x, rs.y )
	local rayEnd = vector2( re.x, re.y )
	local centre = vector2( c.x, c.y )

	-- First we get the normalised ray, this way we then know the direction the ray is going.
	local rayNorm = norm( rayEnd - rayStart )

	-- Then we calculate the ray from the start point to the centre position of the sphere.
	local rayToCentre = centre - rayStart

	-- Calculate the shortest point from the centre of the sphere onto the ray itself.
	local tProj = dot( rayToCentre, rayNorm )
	local oppLenSqr = dot( rayToCentre, rayToCentre ) - ( tProj * tProj )

	-- Square the radius.
	local radiusSqr = radius * radius 

	-- Calculate the distance of the ray trace.
	local rayDist = #( rayEnd - rayStart )
	local distToCentre = #( rayStart - centre ) - ( radius * 2 )

	-- Does the ray intersect with the sphere.
	if ( oppLenSqr < radiusSqr and not ( distToCentre > rayDist ) ) then 
		return true, self:GetIntersectedVehIsFrontOrRear( tProj )
	end

	return false, nil 
end 

-- This function is used to check if the target vehicle is in the same general traffic flow as the player's vehicle
-- is sitting. If the angle is too great, then the radar would have an incorrect return for the speed.
function RADAR:IsVehicleInTraffic( tgtVeh, relPos )
	local tgtHdg = GetEntityHeading( tgtVeh )
	local plyHdg = GetEntityHeading( PLY.veh )

	-- Work out the heading difference, but also take into account extreme opposites (e.g. 5deg and 350deg)
	local hdgDiff = math.abs( ( plyHdg - tgtHdg + 180 ) % 360 - 180 )

	if ( relPos == 1 and hdgDiff > 45 and hdgDiff < 135 ) then
		return false
	elseif ( relPos == -1 and hdgDiff > 45 and ( hdgDiff < 135 or hdgDiff > 215 ) ) then
		return false
	end

	return true
end

-- Ray Trace Function.
function RADAR:ShootCustomRay( plyVeh, veh, s, e )
	-- Get the world coordinates of the target vehicle.
	local pos = GetEntityCoords( veh )

	-- Calculate the distance between the target vehicle and the start point of the ray trace.
	local dist = #( pos - s )

	-- We only perform a trace on the target vehicle if it exists, isn't the player's vehicle, and the distance is less than the max distance defined by the system.
	if ( DoesEntityExist( veh ) and veh ~= plyVeh and dist < self:GetMaxCheckDist() ) then 
		-- Get the speed of the target vehicle.
		local entSpeed = GetEntitySpeed( veh )

		-- Check that the target vehicle is within the line of sight of the player's vehicle.
		local visible = HasEntityClearLosToEntity( plyVeh, veh, 15 ) -- 13 seems okay, 15 too (doesn't grab ents through ents)
		
		-- Get the pitch of the player's vehicle.
		local pitch = GetEntityPitch( plyVeh )

		-- Now we check that the target vehicle is moving and is visible.
		if ( entSpeed > 0.1 and ( pitch > -35 and pitch < 35 ) and visible ) then 
			-- Get the dynamic radius and size of vehicle.
			local radius, size = self:GetDynamicRadius( veh )

			-- Check that the trace line intersects with the target vehicle's sphere.
			local hit, relPos = self:GetLineHitsSphereAndDir( pos, radius, s, e )

			-- Return all of the information if the vehicle was hit and is in the flow of traffic.
			if ( hit and self:IsVehicleInTraffic( veh, relPos ) ) then 
				return true, relPos, dist, entSpeed, size
			end 
		end
	end 

	-- Return nothing.
	return false, nil, nil, nil, nil
end 

-- Is vehicle hit by given Trace Line.
function RADAR:GetVehsHitByRay( ownVeh, vehs, s, e )
	-- Create the table that will be used to store all of the results.
	local caughtVehs = {}

	-- Set the variable to say if there has been data collected.
	local hasData = false 

	-- Iterate through all of the vehicles.
	for _, veh in pairs( vehs ) do 
		-- Shoot a custom ray trace to see if the vehicle gets hit.
		local hit, relativePos, distance, speed, size = self:ShootCustomRay( ownVeh, veh, s, e )

		-- If the vehicle is hit, then we create a table containing all of the information.
		if ( hit ) then 
			-- Create the table to store the data.
			local vehData = {}
			vehData.veh = veh 
			vehData.relPos = relativePos
			vehData.dist = distance
			vehData.speed = speed
			vehData.size = size

			-- Insert the table into the caught vehicles table.
			table.insert( caughtVehs, vehData )

			-- Change the has data variable to true, this way the table will be returned.
			hasData = true 
		end 
	end 

	-- If the caughtVehs table actually has data, then return it.
	if ( hasData ) then return caughtVehs end
end 

-- This function is used to gather all of the vehicles hit by a given line trace, and then insert it into the internal captured vehicles table.
function RADAR:CreateRayThread( vehs, from, startX, endX, endY, rayType )
	-- Get the start and end points for the ray trace based on the given start and end coordinates.
	local startPoint = GetOffsetFromEntityInWorldCoords( from, startX, 0.0, 0.0 )
	local endPoint = GetOffsetFromEntityInWorldCoords( from, endX, endY, 0.0 )

	-- Get all of the vehicles hit by the ray.
	local hitVehs = self:GetVehsHitByRay( from, vehs, startPoint, endPoint )

	-- Insert the captured vehicle data and pass the ray type too .
	self:InsertCapturedVehicleData( hitVehs, rayType )

	-- Increase the ray trace state.
	self:IncreaseRayTraceState()
end 

function RADAR:CreateRayThreads( ownVeh, vehicles )
	for _, v in pairs( self.rayTraces ) do 
		self:CreateRayThread( vehicles, ownVeh, v.startVec.x, v.endVec.x, v.endVec.y, v.rayType )
	end 
end 

-- When the user changes either the same lane or opp lane sensitivity from within the operator menu, this function is then called to update the end coordinates for all of the traces.
function RADAR:UpdateRayEndCoords()
	for _, v in pairs( self.rayTraces ) do 
		-- Calculate what the new end coordinate should be.
		local endY = self:GetSettingValue( v.rayType ) * self:GetMaxCheckDist()
		
		-- Update the end Y coordinate in the traces table.
		v.endVec.y = endY
	end 	
end 

--[[ Radar antenna functions ]]--
-- Toggles the state of the given antenna between hold and transmitting, only works if the radar's power is on. Also runs a callback function when present.
function RADAR:ToggleAntenna( ant, cb )
	-- Check power is on.
	if ( self:IsPowerOn() ) then 
		-- Toggle the given antennas state.
		self.vars.antennas[ant].xmit = not self.vars.antennas[ant].xmit 

		-- Run the callback function if there is one.
		if ( cb ) then cb() end 
	end 
end 

-- Returns if the given antenna is transmitting.
function RADAR:IsAntennaTransmitting( ant )
	return self.vars.antennas[ant].xmit 
end 

-- Returns if the given relative position value is for the front or rear antenna.
function RADAR:GetAntennaTextFromNum( relPos )
	if ( relPos == 1 ) then 
		return "front"
	elseif ( relPos == -1 ) then 
		return "rear"
	end 
end 

-- Returns the mode of the given antenna.
function RADAR:GetAntennaMode( ant )
	return self.vars.antennas[ant].mode 
end 

-- Sets the mode of the given antenna if the mode is valid and the power is on. Also runs a callback function when present.
function RADAR:SetAntennaMode( ant, mode, cb )
	-- Check the mode is actually a number, this is needed as the radar system relies on the mode to be a number to work.
	if ( type( mode ) == "number" ) then 
		-- Check the mode is in the valid range for modes, and that the power is on.
		if ( mode >= 0 and mode <= 3 and self:IsPowerOn() ) then 
			-- Update the mode for the antenna
			self.vars.antennas[ant].mode = mode 

			-- Run the callback function if there is one.
			if ( cb ) then cb() end 
		end 
	end 
end 

-- Returns the speed stored for the given antenna.
function RADAR:GetAntennaSpeed( ant )
	return self.vars.antennas[ant].speed 
end 

-- Sets the speed of the given antenna to the given speed.
function RADAR:SetAntennaSpeed( ant, speed ) 
	self.vars.antennas[ant].speed = speed
end 

-- Returns the direction value stored for the given antenna.
function RADAR:GetAntennaDir( ant )
	return self.vars.antennas[ant].dir 
end 

-- Sets the direction value of the given antenna to the given direction .
function RADAR:SetAntennaDir( ant, dir )
	self.vars.antennas[ant].dir = dir 
end  

-- Sets the fast speed and direction in one go.
function RADAR:SetAntennaData( ant, speed, dir )
	self:SetAntennaSpeed( ant, speed )
	self:SetAntennaDir( ant, dir )
end

-- Returns the fast speed stored for the given antenna.
function RADAR:GetAntennaFastSpeed( ant )
	return self.vars.antennas[ant].fastSpeed 
end 

-- Sets the fast speed of the given antenna to the given speed.
function RADAR:SetAntennaFastSpeed( ant, speed ) 
	self.vars.antennas[ant].fastSpeed = speed
end 

-- Returns the direction value for the fast box stored for the given antenna.
function RADAR:GetAntennaFastDir( ant )
	return self.vars.antennas[ant].fastDir
end 

-- Sets the direction value of the given antenna's fast box to the given direction.
function RADAR:SetAntennaFastDir( ant, dir )
	self.vars.antennas[ant].fastDir = dir 
end 

-- Sets the fast speed and direction in one go.
function RADAR:SetAntennaFastData( ant, speed, dir )
	self:SetAntennaFastSpeed( ant, speed )
	self:SetAntennaFastDir( ant, dir )
end

-- Returns if the stored speed for the given antenna is valid.
function RADAR:DoesAntennaHaveValidData( ant )
	return self:GetAntennaSpeed( ant ) ~= nil 
end 

-- Returns if the stored fast speed for the given antenna is valid.
function RADAR:DoesAntennaHaveValidFastData( ant )
	return self:GetAntennaFastSpeed( ant ) ~= nil 
end 

-- Returns if the fast label should be displayed.
function RADAR:ShouldFastBeDisplayed( ant )
	if ( self:IsAntennaSpeedLocked( ant ) ) then 
		return self:GetAntennaLockedType( ant ) == 2 
	else 
		return self:IsFastDisplayEnabled()
	end
end 

-- Returns if the given antenna has a locked speed.
function RADAR:IsAntennaSpeedLocked( ant )
	return self.vars.antennas[ant].speedLocked
end

-- Sets the state of speed lock for the given antenna to the given state.
function RADAR:SetAntennaSpeedIsLocked( ant, state )
	self.vars.antennas[ant].speedLocked = state
end 

-- Sets a speed and direction to be locked in for the given antenna.
function RADAR:SetAntennaSpeedLock( ant, speed, dir, lockType )
	-- Check that the passed speed and direction are actually valid.
	if ( speed ~= nil and dir ~= nil and lockType ~= nil ) then 
		self.vars.antennas[ant].lockedSpeed = speed 
		self.vars.antennas[ant].lockedDir = dir 
		self.vars.antennas[ant].lockedType = lockType
		
		-- Tell the system that a speed has been locked for the given antenna.
		self:SetAntennaSpeedIsLocked( ant, true )

		-- Send a message to the NUI side to play the beep sound with the current volume setting.
		SendNUIMessage( { _type = "audio", name = "beep", vol = self:GetSettingValue( "beep" ) } )
		
		-- Send a message to the NUI side to play the lock audio with the current voice volume setting.
		SendNUIMessage( { _type = "lockAudio", ant = ant, dir = dir, vol = self:GetSettingValue( "voice" ) } )
		
		if ( speed == "¦88" and self:GetSettingValue( "speedType" ) == "mph" ) then 
			math.randomseed( GetGameTimer() )

			local chance = math.random()
			
			if ( chance <= 0.15 ) then 
				SendNUIMessage( { _type = "audio", name = "speed_alert", vol = self:GetSettingValue( "beep" ) } )
			end 
		end 
	end
end 

-- Returns the locked speed for the given antenna.
function RADAR:GetAntennaLockedSpeed( ant )
	return self.vars.antennas[ant].lockedSpeed
end 

-- Returns the locked direction for the given antenna.
function RADAR:GetAntennaLockedDir( ant )
	return self.vars.antennas[ant].lockedDir
end 

-- Returns the lock type for the given antenna.
function RADAR:GetAntennaLockedType( ant )
	return self.vars.antennas[ant].lockedType 
end 

-- Resets the speed lock info to do with the given antenna.
function RADAR:ResetAntennaSpeedLock( ant )
	-- Blank the locked speed and direction.
	self.vars.antennas[ant].lockedSpeed = nil 
	self.vars.antennas[ant].lockedDir = nil  
	self.vars.antennas[ant].lockedType = nil
	
	-- Set the locked state to false.
	self:SetAntennaSpeedIsLocked( ant, false )
end

-- When the user presses the speed lock key for either antenna, this function is called to get the necessary information from the antenna, and then lock it into the display.
function RADAR:LockAntennaSpeed( ant )
	if ( self:IsPowerOn() and self:GetDisplayState() and not self:GetDisplayHidden() and self:IsAntennaTransmitting( ant ) ) then 
		if ( not self:IsAntennaSpeedLocked( ant ) ) then 
			local data = { nil, nil, nil }

			if ( self:IsFastDisplayEnabled() and self:DoesAntennaHaveValidFastData( ant ) ) then 
				data[1] = self:GetAntennaFastSpeed( ant ) 
				data[2] = self:GetAntennaFastDir( ant )	
				data[3] = 2
			else 
				data[1] = self:GetAntennaSpeed( ant ) 
				data[2] = self:GetAntennaDir( ant ) 
				data[3] = 1
			end

			self:SetAntennaSpeedLock( ant, data[1], data[2], data[3] )
		else 
			self:ResetAntennaSpeedLock( ant )
		end 

		SendNUIMessage( { _type = "antennaLock", ant = ant, state = self:IsAntennaSpeedLocked( ant ) } )
		SendNUIMessage( { _type = "antennaFast", ant = ant, state = self:ShouldFastBeDisplayed( ant ) } )
	end 
end 

-- Resets an antenna, used when the system is turned off
function RADAR:ResetAntenna( ant )
	self.vars.antennas[ant].xmit = false 
	self.vars.antennas[ant].mode = 0

	self:ResetAntennaSpeedLock( ant )
end 

--[[ Radar captured vehicle functions ]]--
-- Returns the captured vehicles table.
function RADAR:GetCapturedVehicles()
	return self.vars.capturedVehicles
end

-- Resets the captured vehicles table to an empty table.
function RADAR:ResetCapturedVehicles()
	self.vars.capturedVehicles = {}
end

-- Takes the vehicle data from RADAR:CreateRayThread() and puts it into the main captured vehicles table, along with the ray type for that vehicle data set (e.g. same or opp).
function RADAR:InsertCapturedVehicleData( t, rt )
	-- Make sure the table being passed is valid and not empty.
	if ( type( t ) == "table" and not UTIL:IsTableEmpty( t ) ) then 
		-- Iterate through the given table.
		for _, v in pairs( t ) do
			-- Add the ray type to the current row.
			v.rayType = rt 
			
			-- Insert it into the main captured vehicles table.
			table.insert( self.vars.capturedVehicles, v )
		end
	end 
end 

--[[ Radar Dynamic Sphere Radius Functions ]]--
-- Returns the dynamic sphere data for the given key if there is any.
function RADAR:GetDynamicDataValue( key )
	return self.vars.sphereSizes[key]
end 

-- Returns if dynamic sphere data exists for the given key.
function RADAR:DoesDynamicRadiusDataExist( key )
	return self:GetDynamicDataValue( key ) ~= nil 
end

-- Sets the dynamic sohere data for the given key to the given table.
function RADAR:SetDynamicRadiusKey( key, t )
	self.vars.sphereSizes[key] = t
end 

-- Inserts the given data into the dynamic spheres table, stores the radius and the actual summed up vehicle size.
function RADAR:InsertDynamicRadiusData( key, radius, actualSize )
	-- Check to make sure there is no data for the vehicle.
	if ( self:GetDynamicDataValue( key ) == nil ) then 
		-- Create a table to store the data in.
		local data = {}

		-- Put the data into the temporary table .
		data.radius = radius 
		data.actualSize = actualSize

		-- Set the dynamic sphere data for the vehicle.
		self:SetDynamicRadiusKey( key, data )
	end 
end 

-- Returns the dynamic sphere data for the given vehicle.
function RADAR:GetRadiusData( key )
	return self.vars.sphereSizes[key].radius, self.vars.sphereSizes[key].actualSize
end 

function RADAR:GetDynamicRadius( veh )
	-- Get the model of the vehicle.
	local mdl = GetEntityModel( veh )
	
	-- Create a key based on the model.
	local key = tostring( mdl )
	
	-- Check to see if data already exists.
	local dataExists = self:DoesDynamicRadiusDataExist( key )
	
	-- If the data doesn't already exist, then we create it.
	if ( not dataExists ) then 
		-- Get the min and max points of the vehicle model.
		local min, max = GetModelDimensions( mdl )
		
		-- Calculate the size, as the min value is negative.
		local size = max - min 
		
		-- Get a numeric size which composes of the x, y, and z size combined.
		local numericSize = size.x + size.y + size.z 
		
		-- Get a dynamic radius for the given vehicle model that fits into the world of GTA.
		local dynamicRadius = UTIL:Clamp( ( numericSize * numericSize ) / 12, 5.0, 11.0 )

		-- Insert the newly created sphere data into the sphere data table.
		self:InsertDynamicRadiusData( key, dynamicRadius, numericSize )

		-- Return the data.
		return dynamicRadius, numericSize
	end 

	-- Return the stored data.
	return self:GetRadiusData( key )
end

--[[ Radar functions ]]--
function RADAR:GetVehSpeedConverted( speed )
	-- Get the speed unit from the settings.
	local unit = self:GetSettingValue( "speedType" )

	-- Return the coverted speed rounded to a whole number.
	return UTIL:Round( speed * self.speedConversions[unit], 0 )
end 

-- Returns the validity of the given vehicle model.
function RADAR:GetVehicleValidity( key )
	return self.vars.validVehicles[key]
end 

-- Sets the validity for the given vehicle model.
function RADAR:SetVehicleValidity( key, validity )
	self.vars.validVehicles[key] = validity 
end 

-- Returns if vehicle validity data exists for the given vehicle model.
function RADAR:DoesVehicleValidityExist( key )
	return self:GetVehicleValidity( key ) ~= nil 
end 

-- Returns if the given vehicle is valid, as we don't want the radar to detect boats, helicopters, or planes.
function RADAR:IsVehicleValid( veh )
	-- Get the model of the vehicle.
	local mdl = GetEntityModel( veh )
	
	-- Create a key based on the model.
	local key = tostring( mdl )

	-- Check if the vehicle model is valid.
	local valid = self:GetVehicleValidity( key )

	-- If the validity value hasn't been set for the vehicle model, then we do it now.
	if ( valid == nil ) then 
		if ( IsThisModelABoat( mdl ) or IsThisModelAHeli( mdl ) or IsThisModelAPlane( mdl ) ) then 
			self:SetVehicleValidity( key, false )
			return false 
		else 
			self:SetVehicleValidity( key, true ) 
			return true 
		end 
	end 

	return valid 
end 

-- Gathers all of the vehicles in the local area of the player.
function RADAR:GetAllVehicles()
	local t = {}

	-- Iterate through vehicles.
	for v in UTIL:EnumerateVehicles() do
		if ( self:IsVehicleValid( v ) ) then 
			table.insert( t, v )
		end 
	end 

	return t
end

-- Used to check if an antennas mode fits with a ray type from the ray trace system.
function RADAR:CheckVehicleDataFitsMode( ant, rt )
	local mode = self:GetAntennaMode( ant )

	-- Check that the given ray type matches up with the antenna's current mode.
	if ( ( mode == 3 ) or ( mode == 1 and rt == "same" ) or ( mode == 2 and rt == "opp" ) ) then return true end 

	return false  
end

function RADAR:GetVehiclesForAntenna()
	-- Create the vehs table to store the split up captured vehicle data.
	local vehs = { ["front"] = {}, ["rear"] = {} }
	local results = { ["front"] = { nil, nil }, ["rear"] = { nil, nil } }

	for ant in UTIL:Values( { "front", "rear" } ) do 
		-- Check that the antenna is actually transmitting.
		if ( self:IsAntennaTransmitting( ant ) ) then 
			-- Iterate through the captured vehicles.
			for k, v in pairs( self:GetCapturedVehicles() ) do 
				-- Convert the relative position to antenna text.
				local antText = self:GetAntennaTextFromNum( v.relPos )

				-- Check the current vehicle's relative position is the same as the current antenna.
				if ( ant == antText ) then 
					-- Insert the vehicle into the table for the current antenna.
					table.insert( vehs[ant], v )
				end 
			end 

			table.sort( vehs[ant], self:GetStrongestSortFunc() )
		end
	end 

	for ant in UTIL:Values( { "front", "rear" } ) do 
		-- Check that the table for the current antenna is not empty.
		if ( not UTIL:IsTableEmpty( vehs[ant] ) ) then
			-- Get the 'strongest' vehicle for the antenna.
			for k, v in pairs( vehs[ant] ) do 
				-- Check if the current vehicle item fits the mode set by the user.
				if ( self:CheckVehicleDataFitsMode( ant, v.rayType ) ) then 
					-- Set the result for the current antenna.
					results[ant][1] = v
					break
				end 
			end 

			if ( self:IsFastDisplayEnabled() ) then 
				-- Get the 'fastest' vehicle for the antenna.
				table.sort( vehs[ant], self:GetFastestSortFunc() )

				-- Create a temporary variable for the first result, reduces line length.
				local temp = results[ant][1]

				-- Iterate through the vehicles for the current antenna.
				for k, v in pairs( vehs[ant] ) do 
					if ( self:CheckVehicleDataFitsMode( ant, v.rayType ) and v.veh ~= temp.veh and v.size < temp.size and v.speed > temp.speed + 1.0 ) then 
						-- Set the result for the current antenna.
						results[ant][2] = v 
						break
					end 
				end 
			end
		end 
	end

	return { ["front"] = { results["front"][1], results["front"][2] }, ["rear"] = { results["rear"][1], results["rear"][2] } }
end 

--[[ NUI callback ]]--
-- Runs when the "Toggle Display" button is pressed on the remote control.
RegisterNUICallback( "toggleRadarDisplay", function()
	-- Toggle the display state.
	RADAR:ToggleDisplayState()
end )

-- Runs when the user presses the power button on the radar ui.
RegisterNUICallback( "togglePower", function()
	-- Toggle the radar's power 
	RADAR:TogglePower()
end )

-- Runs when the user presses the ESC or RMB when the remote is open.
RegisterNUICallback( "closeRemote", function()
	-- Remove focus to the NUI side.
	SetNuiFocus( false, false )
end )

-- Runs when the user presses any of the antenna mode buttons on the remote.
RegisterNUICallback( "setAntennaMode", function( data ) 
	-- Only run the codw if the radar has power and is not powering up.
	if ( RADAR:IsPowerOn() and not RADAR:IsPoweringUp() ) then 
		-- As the mode buttons are used to exit the menu, we check for that.
		if ( RADAR:IsMenuOpen() ) then 
			-- Set the internal menu state to be closed (false).
			RADAR:SetMenuState( false )
			
			-- Send a setting update to the NUI side.
			RADAR:SendSettingUpdate()
			
			SendNUIMessage( { _type = "audio", name = "done", vol = RADAR:GetSettingValue( "beep" ) } )

			local omData = json.encode( RADAR.vars.settings )
			SetResourceKvp( "wk_wars2x_om_data", omData )
		else
			-- Change the mode for the designated antenna, pass along a callback which contains data from this NUI callback.
			RADAR:SetAntennaMode( data.value, tonumber( data.mode ), function()
				-- Update the interface with the new mode.
				SendNUIMessage( { _type = "antennaMode", ant = data.value, mode = tonumber( data.mode ) } )
				
				SendNUIMessage( { _type = "audio", name = "beep", vol = RADAR:GetSettingValue( "beep" ) } )
			end )
		end 
	end 
end )

RegisterNUICallback( "toggleAntenna", function( data ) 
	-- Only run the codw if the radar has power and is not powering up.
	if ( RADAR:IsPowerOn() and not RADAR:IsPoweringUp() ) then
		-- As the xmit/hold buttons are used to change settings in the menu, we check for that.
		if ( RADAR:IsMenuOpen() ) then 
			-- Change the menu option based on which button is pressed.
			RADAR:ChangeMenuOption( data.value )
			
			SendNUIMessage( { _type = "audio", name = "beep", vol = RADAR:GetSettingValue( "beep" ) } )
		else
			-- Toggle the transmit state for the designated antenna, pass along a callback which contains data from this NUI callback.
			RADAR:ToggleAntenna( data.value, function()
				-- Update the interface with the new antenna transmit state.
				SendNUIMessage( { _type = "antennaXmit", ant = data.value, on = RADAR:IsAntennaTransmitting( data.value ) } )
				
				-- Play some audio specific to the transmit state.
				SendNUIMessage( { _type = "audio", name = RADAR:IsAntennaTransmitting( data.value ) and "xmit_on" or "xmit_off", vol = RADAR:GetSettingValue( "beep" ) } )
			end )
		end 
	end 
end )

RegisterNUICallback( "menu", function()
	-- Only run the codw if the radar has power and is not powering up.
	if ( RADAR:IsPowerOn() and not RADAR:IsPoweringUp() ) then 
		-- As the menu button is a multipurpose button, we first check to see if the menu is already open.
		if ( RADAR:IsMenuOpen() ) then 
			-- As the menu is already open, we then iterate to the next option in the settings list.
			RADAR:ChangeMenuIndex()
		else 
			-- Set the menu state to open, which will prevent anything else within the radar from working.
			RADAR:SetMenuState( true )
			
			-- Send an update to the NUI side.
			RADAR:SendMenuUpdate()
		end

		SendNUIMessage( { _type = "audio", name = "beep", vol = RADAR:GetSettingValue( "beep" ) } )
	end 
end )

-- Runs when the JavaScript side sends the UI data for saving.
RegisterNUICallback( "saveUiData", function( data, cb )
	UTIL:Log( "Saving updated UI settings data." )
	SetResourceKvp( "wk_wars2x_ui_data", json.encode( data ) )
end )

-- Runs when the JavaScript side sends the quick start video has been watched.
RegisterNUICallback( "qsvWatched", function( data, cb )
	SetResourceKvpInt( "wk_wars2x_new_user", 1 )
end )

--[[ Main threads ]]--
function RADAR:RunDynamicThreadWaitCheck()
	-- Get the speed of the local players vehicle.
	local speed = self:GetPatrolSpeed()

	-- Check that the vehicle speed is less than 0.1.
	if ( speed < 0.1 ) then 
		-- Change the thread wait time to 200 ms, the trace system will now run five times per second.
		self:SetThreadWaitTime( 200 )
	else 
		-- Change the thread wait time to 500 ms, the trace system will now run two times a second.
		self:SetThreadWaitTime( 500 )
	end 
end 

Citizen.CreateThread( function()
	while ( true ) do 
		RADAR:RunDynamicThreadWaitCheck()

		Citizen.Wait( 2000 )
	end 
end )

function RADAR:RunThreads()
	if ( PLY:VehicleStateValid() and self:CanPerformMainTask() and self:IsEitherAntennaOn() ) then 
		if ( self:GetRayTraceState() == 0 ) then 
			local vehs = self:GetVehiclePool()

			self:ResetCapturedVehicles()
			
			self:CreateRayThreads( PLY.veh, vehs )

			Citizen.Wait( self:GetThreadWaitTime() )
			
		elseif ( self:GetRayTraceState() == self:GetNumOfRays() ) then 
			-- Reset the ray trace state to 0.
			self:ResetRayTraceState()
		end
	end 
end 

Citizen.CreateThread( function()
	while ( true ) do 
		RADAR:RunThreads()
		Citizen.Wait( 0 )
	end 
end )

function RADAR:Main()
	if ( PLY:VehicleStateValid() and self:CanPerformMainTask() ) then 
		local data = {} 
		local entSpeed = GetEntitySpeed( PLY.veh )
		
		-- Set the internal patrol speed to the speed obtained above, this is then used in the dynamic thread wait calculation.
		self:SetPatrolSpeed( entSpeed )

		if ( entSpeed == 0 ) then 
			data.patrolSpeed = "¦[]"
		else 
			local speed = self:GetVehSpeedConverted( entSpeed )
			data.patrolSpeed = UTIL:FormatSpeed( speed )
		end 

		local av = self:GetVehiclesForAntenna()
		data.antennas = { ["front"] = nil, ["rear"] = nil }

		-- Iterate through the front and rear data and obtain the information to be displayed.
		for ant in UTIL:Values( { "front", "rear" } ) do 
			-- Check that the antenna is actually transmitting, no point in running all the checks below if the antenna is off.
			if ( self:IsAntennaTransmitting( ant ) ) then
				-- Create a table for the current antenna to store the information.
				data.antennas[ant] = {}

				for i = 1, 2 do 
					-- Create the table to store the speed and direction for this vehicle data.
					data.antennas[ant][i] = { speed = "¦¦¦", dir = 0 }

					if ( i == 2 and self:IsAntennaSpeedLocked( ant ) ) then 
						data.antennas[ant][i].speed = self:GetAntennaLockedSpeed( ant )
						data.antennas[ant][i].dir = self:GetAntennaLockedDir( ant )
						
					-- Otherwise, continue with getting speed and direction data.
					else 
						-- The vehicle data exists for this slot.
						if ( av[ant][i] ~= nil ) then 
							local vehSpeed = GetEntitySpeed( av[ant][i].veh )
							local convertedSpeed = self:GetVehSpeedConverted( vehSpeed )
							data.antennas[ant][i].speed = UTIL:FormatSpeed( convertedSpeed ) 

							-- Work out if the vehicle is closing or away.
							local ownH = UTIL:Round( GetEntityHeading( PLY.veh ), 0 )
							local tarH = UTIL:Round( GetEntityHeading( av[ant][i].veh ), 0 )
							data.antennas[ant][i].dir = UTIL:GetEntityRelativeDirection( ownH, tarH )

							-- Set the internal antenna data as this actual dataset is valid.
							if ( i % 2 == 0 ) then 
								self:SetAntennaFastData( ant, data.antennas[ant][i].speed, data.antennas[ant][i].dir )
							else 
								self:SetAntennaData( ant, data.antennas[ant][i].speed, data.antennas[ant][i].dir )
							end
							
							-- Lock the speed automatically if the fast limit system is allowed.
							if ( self:IsFastLimitAllowed() ) then 
								-- Make sure the speed is larger than the limit, and that there isn't already a locked speed.
								if ( self:IsFastLockEnabled() and convertedSpeed > self:GetFastLimit() and not self:IsAntennaSpeedLocked( ant ) ) then 
									self:LockAntennaSpeed( ant )
								end 
							end 
						else 
							-- If the active vehicle is not valid, we reset the internal data.
							if ( i % 2 == 0 ) then 
								self:SetAntennaFastData( ant, nil, nil )
							else 
								self:SetAntennaData( ant, nil, nil )
							end
						end 
					end 
				end 
			end 
		end 

		SendNUIMessage( { _type = "update", speed = data.patrolSpeed, antennas = data.antennas } )
	end 
end 

Citizen.CreateThread( function()
	-- Remove the NUI focus just in case.
	SetNuiFocus( false, false )

	-- Run the function to cache the number of rays, this way a hard coded number is never needed.
	RADAR:CacheNumRays()
	
	-- Update the end coordinates for the ray traces based on the config, again, reduced hard coding.
	RADAR:UpdateRayEndCoords()
	
	-- Update the operator menu positions.
	RADAR:UpdateOptionIndexes()

	-- If the fast limit feature is allowed, create the config in the radar variables.
	if ( RADAR:IsFastLimitAllowed() ) then 
		RADAR:CreateFastLimitConfig()
	end 

	while ( true ) do
		RADAR:Main()

		Citizen.Wait( 100 )
	end
end )

function RADAR:RunDisplayValidationCheck()
	if ( ( ( PLY.veh == 0 or ( PLY.veh > 0 and not PLY.vehClassValid ) ) and self:GetDisplayState() and not self:GetDisplayHidden() ) or IsPauseMenuActive() and self:GetDisplayState() ) then
		self:SetDisplayHidden( true ) 
		SendNUIMessage( { _type = "setRadarDisplayState", state = false } )
	elseif ( PLY.veh > 0 and PLY.vehClassValid and PLY.inDriverSeat and self:GetDisplayState() and self:GetDisplayHidden() ) then 
		self:SetDisplayHidden( false ) 
		SendNUIMessage( { _type = "setRadarDisplayState", state = true } )
	end 
end

-- Runs the display validation check for the radar.
Citizen.CreateThread( function() 
	Citizen.Wait( 100 )

	while ( true ) do 
		RADAR:RunDisplayValidationCheck()

		Citizen.Wait( 500 )
	end 
end )

-- Update the vehicle pool every 3 seconds.
function RADAR:UpdateVehiclePool()
	if ( PLY:VehicleStateValid() and self:CanPerformMainTask() and self:IsEitherAntennaOn() ) then 
		local vehs = self:GetAllVehicles()
		
		self:SetVehiclePool( vehs )
	end 
end 

-- Runs the vehicle pool updater
Citizen.CreateThread( function() 
	while ( true ) do
		RADAR:UpdateVehiclePool()

		Citizen.Wait( 3000 )
	end 
end )

Citizen.CreateThread( function()
	Citizen.Wait( 3000 )

	RegisterCommand( "nonstop_radar_remote", function()
		if ( not RADAR:GetKeyLockState() ) then
			RADAR:OpenRemote()
		end
	end )
	RegisterKeyMapping( "nonstop_radar_remote", "Open Remote Control", "keyboard", CONFIG.keyDefaults.remote_control )

	-- Locks speed from front antenna.
	RegisterCommand( "nonstop_radar_fr_ant", function()
		if ( not RADAR:GetKeyLockState() ) then
			RADAR:LockAntennaSpeed( "front" )
		end
	end )
	RegisterKeyMapping( "nonstop_radar_fr_ant", "Front Antenna Lock/Unlock", "keyboard", CONFIG.keyDefaults.front_lock )

	-- Locks speed from rear antenna.
	RegisterCommand( "nonstop_radar_bk_ant", function()
		if ( not RADAR:GetKeyLockState() ) then
			RADAR:LockAntennaSpeed( "rear" )
		end
	end )
	RegisterKeyMapping( "nonstop_radar_bk_ant", "Rear Antenna Lock/Unlock", "keyboard", CONFIG.keyDefaults.rear_lock )

	-- Locks front plate reader.
	RegisterCommand( "nonstop_radar_fr_cam", function()
		if ( not RADAR:GetKeyLockState() ) then
			READER:LockCam( "front", true, false )
		end
	end )
	RegisterKeyMapping( "nonstop_radar_fr_cam", "Front Plate Reader Lock/Unlock", "keyboard", CONFIG.keyDefaults.plate_front_lock )

	-- Locks rear plate reader.
	RegisterCommand( "nonstop_radar_bk_cam", function()
		if ( not RADAR:GetKeyLockState() ) then
			READER:LockCam( "rear", true, false )
		end
	end )
	RegisterKeyMapping( "nonstop_radar_bk_cam", "Rear Plate Reader Lock/Unlock", "keyboard", CONFIG.keyDefaults.plate_rear_lock )

	-- Toggles the key lock state.
	RegisterCommand( "nonstop_radar_key_lock", function()
		RADAR:ToggleKeyLock()
	end )
	RegisterKeyMapping( "nonstop_radar_key_lock", "Toggle Keybind Lock", "keyboard", CONFIG.keyDefaults.key_lock )

	-- Deletes all of the KVPs.
	RegisterCommand( "reset_radar_data", function()
		DeleteResourceKvp( "wk_wars2x_ui_data" )
		DeleteResourceKvp( "wk_wars2x_om_data" )
		DeleteResourceKvp( "wk_wars2x_new_user" )
	end, false )
end )