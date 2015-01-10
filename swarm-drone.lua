--[[ swarm-drone.lua
	Core drone behavior.
]]--

-- Constants
local libDir = "/lib/"
-- Directories for all the key components of the Behavior Engine
local behaviorDir = "/behaviors/"
local verbDir = "/verbs/"
local resourceDir = "/resources/"
local conditionalDir = "/conditionals/"
-- Directories for information specific to this drone.
local identityDir = "/id/" -- As in the psychological id. This dir contains the knowledge of "self".


-- Function for loading libs
local function loadLib(libLocation)
	if not os.loadAPI(libLocation) then
		print("Failed to load library [" .. libLocation .. "], returning false.")
	end
end

-- Load the JSON encoding/decoding library
-- (Big thanks to Jeffrey Friedl for his library! See notice in lib/JSON.lua)
local apiLocation = shell.resolve("") .. libDir.. "JSON"
if not os.loadAPI(apiLocation) then error("Failed to load JSON API @ [" .. apiLocation .. "], aborting.") end
local JSON = JSON.OBJDEF:new() -- Because, you know, CC just letting us load libs normally was too hard.

-- Load the IDLE behavior, because we're going to be running it frequently
local idleLoc = shell.resolve("") .. verbDir .. "IDLE"
if not os.loadAPI(idleLoc) then error("Failed to load IDLE behavior @ [" .. idleLoc .. "], aborting.") end

-- SwarmDrone Class Definition
local function SwarmDrone()
	local self = {} -- 'this' reference

	-- Tick Info
	self.startTickSecondTime = nil
	self.ticks = 0
	self.ticksPerSecond = 0
	
	-- Behaviors
	self.behaviors = {}
	
	
	--[[ Engine Calls ]]--
	local function checkConditional(conditional, params)
		local conLoc = shell.resolve("") .. conditionalDir .. conditional
		if loadLib(conLoc) then
			-- Call the conditional, with the provided params
			local result = _G[conditional].compare(params)
			
			-- Clean up the file when we're done
			os.unloadAPI(conLoc)
			
			if result > 1 then return true end
		end
		return false
	end

	--[[ Initialization ]]--
	function self.init()
		--[[ TODO
			Step 1: Load potential behaviors (and thier constraints)
				from disk, hold in local memory.
			Step 2: Collect data about self and immediate surroundings
			Step 3: Announce self to swarm-net, if possible
		]]--
		
		-- Reset the behavior array, just in case
		self.behaviors = {}
		
		-- Load the Behavior lists
		local files = fs.list(shell.resolve("") .. behaviorDir)
		for i, file in ipairs(files) do
			local fileName = shell.resolve("") .. behaviorDir .. file
			print(fileName, " : ", file)
			if not fs.isDir(fileName) then
				-- Extract and decode the behavior information
				local f = fs.open(fileName, "r")
				if not f then
					error("Couldn't open file [" .. fileName .. "]")
				end
				local behaviorTable = JSON:decode(f.readAll())
				f.close()
				
				-- Append all the behaviors to our master list of behaviors
				for k, behavior in pairs(behaviorTable) do
					self.behaviors[#self.behaviors + 1] = behavior
				end
			end
		end -- repeat for each file in the primary directory. In the future,
			-- subdirectories can be used for alternate behavior sets.
			
		-- DEBUG
		for k, v in pairs(self.behaviors) do print (k) for key, value in pairs(v) do print(key..": ", value) end end
		
		-- TODO: Collect data about self and immediate surroundings (needs RESOURCE definitions)
		local isTurtle = checkConditional("IS_TURTLE")
		print("Is turtle: ", true)
		
		
		
		-- TODO: Announce self to swarm-net
	end


	--[[ Engine Tick Event ]]--
	local function onTick()
		--[[ FIXME: This is where the magic should start happening.
			Step 1: Regenerate constraints (fuel state, inventory fullness)
			Step 2: Poll OS events, handle anything relevent
			Step 3: Determine Active Behavior via priority, queue, fuzzy logic, etc.
			Step 4: Execute Active Behavior
		]]--
		
		if false then
			-- FIXME: Determine which behavior we're actually going to run
		else
			IDLE.execute() -- Execute the idle behavior
		end
	end
	
	
	--[[ tick metacall ]]--
	function self.tick()
		-- Recalculate ticksPerSecond
		local currentTime = os.time() -- Gets the minecraft time
		if self.startTickSecondTime ~= nil then
			-- If at least a second has elapsed, calculate average t/sec
			local elapsed = currentTime - self.startTickSecondTime
			if elapsed > 1.0 then
				self.ticksPerSecond = self.ticks / elapsed
				self.ticks = 0
				self.startTickSecondTime = currentTime
			
			-- Avoid some possible issues with time rolling over at
			-- midnight by reseting the clock
			elseif elapsed < 0.0 then
				self.startTickSecondTime = currentTime
			end
		else
			-- Otherwise, start the clock
			self.startTickSecondTime = currentTime
		end

		-- DO TICK BEHAVIOR
		onTick() -- This may not be called EVERY tick(), in the future

		-- Increment Tick Counter
		self.ticks = self.ticks + 1
	end -- EOF tick()

	return self
end -- EOF SwarmDrone Definition

local drone = SwarmDrone()
drone.init()
drone.tick()

-- Unload global libs
os.unloadAPI(shell.resolve(verbDir) .. "IDLE")
os.unloadAPI(shell.resolve("") .. "/lib/JSON")