--[[ swarm-drone.lua
	Core drone behavior.
	
	Matthew DiBernardo [01.10.2015]
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
		return false
	end
	return true
end

--[[ Engine Calls ]]--
function checkConditional(conditional, params)
	local conLoc = shell.resolve("") .. conditionalDir .. conditional
	if loadLib(conLoc) then
		-- Call the conditional, with the provided params
		local result = _G[conditional].compare(params)
		
		-- Clean up the API when we're done
		os.unloadAPI(conLoc)
		
		if result >= 1 then return true end
	end
	return false
end

function executeVerb(verb, params)
	local verbLoc = shell.resolve("") .. verbDir .. verb
	if loadLib(verbLoc) then
		-- Execute the verb, with the provided params
		_G[verb].execute(verb)
		
		-- Clean up the API when we're done
		os.unloadAPI(verbLoc)
	end
end

function matchResourceByName(resource, name)
	local resLoc = shell.resolve("") .. resourceDir .. resource
	if loadLib(resLoc) then
		-- Perform the match
		local result = _G[resource].matchName(name)
		
		-- Clean up the API when we're done
		os.unloadAPI(resLoc)
		if result >= 1 then return true end
	end
	return false
end

-- Load the JSON encoding/decoding library
-- (Big thanks to Jeffrey Friedl for his library! See notice in lib/JSON)
local apiLocation = shell.resolve("") .. libDir .. "JSON"
if not os.loadAPI(apiLocation) then error("Failed to load JSON API @ [" .. apiLocation .. "], aborting.") end
local JSON = JSON.OBJDEF:new() -- Because, you know, CC just letting us load libs normally was too hard.

-- Load the mobility turtle API
apiLocation = shell.resolve("") .. libDir .. "mobility"
if not os.loadAPI(apiLocation) then error("Failed to load mobility API @ [" .. apiLocation .. "], aborting." end)

-- Load the IDLE behavior, because we're going to be running it frequently
local idleLoc = shell.resolve("") .. verbDir .. "IDLE"
if not os.loadAPI(idleLoc) then error("Failed to load IDLE behavior @ [" .. idleLoc .. "], aborting.") end


--[[ SwarmDrone Class Definition ]]--
local function SwarmDrone()
	local self = {} -- 'this' reference

	-- Tick Info
	self.startTickSecondTime = nil
	self.ticks = 0
	self.ticksPerSecond = 0
	
	-- Idle Tick Info
	self.lastIdleTime = 0
	
	-- Behaviors
	self.behaviors = {}

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
			
		print("Successfully loaded [" .. #self.behaviors .. "] behaviors from disk...")
		
		-- TODO: Collect data about self and immediate surroundings (needs RESOURCE definitions)
		--[[ TURTLE-ONLY INIT ]]--
		local isTurtle = checkConditional("IS_TURTLE")
		if isTurtle then
			print("Turtle detected! Performing turtle-only initialization...")
			executeVerb("CHECK_SURROUNDINGS")
		end
		
		-- TODO: Announce self to swarm-net
	end

	--[[ doIDLE ]]--
	local function doIDLE()
		IDLE.execute()
		self.lastIdleTime = os.clock()
	end

	--[[ Engine Tick Event ]]--
	local function onTick()
		--[[ FIXME: This is where the magic should start happening.
			Step 1: Regenerate constraints (fuel state, inventory fullness)
			Step 2: Poll OS events, handle anything relevent
			Step 3: Determine Active Behavior via priority, queue, fuzzy logic, etc.
			Step 4: Execute Active Behavior
		]]--
		
		-- Force an IDLE tick if we're approaching the 10 second limit between os.pullEvent() calls
		local currentTime = os.clock()
		if currentTime - self.lastIdleTime > 5.0 then -- Every 5.0 seconds
			doIDLE()
			return true
		end
		
		-- FIXME: Determine which behavior we're actually going to run
		local activeVerb = nil
		local verbParams = nil
		
		-- Iterate through all the behaviors and find a valid one
		for i, behavior in ipairs(self.behaviors) do
			local conditionals = behavior['c'] -- 'c' for 'conditions'
			local isValid = true
			for conditional, params in pairs(conditionals) do
				if not checkConditional(conditional, params) then
					isValid = false
					break
				end
			end
			
			if isValid then
				activeVerb = behavior['v'] -- 'v' for 'verb'
				verbParams = behavior['t'] -- 't' for 'target'
				break
			end
		end
		
		-- Execute the active verb
		if activeVerb then
			-- Unless it's really IDLE, in which case just doIDLE()
			if activeVerb == "IDLE" then 
				doIDLE()
				return true
			end
			
			executeVerb(activeVerb, verbParams)
		else
			-- If we don't have an active verb, just chill
			doIDLE()
		end
		return true
	end
	
	
	--[[ tick metacall ]]--
	function self.tick()
		-- Recalculate ticksPerSecond
		local currentTime = os.clock() -- Gets the elapsed computer time
		if self.startTickSecondTime ~= nil then
			-- If at least a second has elapsed, calculate average t/sec
			local elapsed = currentTime - self.startTickSecondTime
			if elapsed > 1.0 then
				self.ticksPerSecond = self.ticks / elapsed
				self.ticks = 0
				self.startTickSecondTime = currentTime
			end
		else
			-- Otherwise, start the clock
			self.startTickSecondTime = currentTime
		end

		-- DO TICK BEHAVIOR
		local continueTicking = onTick() -- This may not be called EVERY tick(), in the future

		-- Increment Tick Counter
		self.ticks = self.ticks + 1
		return continueTicking
	end -- EOF tick()

	return self
end --[[ EOF SwarmDrone Definition ]]--


--[[ Main Execution Loop ]]--
local drone = SwarmDrone()
drone.init()
while drone.tick() do
	-- Do nothing. Repeat.
end


--[[ Lib Cleanup ]]
-- Unload global libs
os.unloadAPI(shell.resolve("") .. verbDir .. "IDLE")
os.unloadAPI(shell.resolve("") .. libDir .. "mobility")
os.unloadAPI(shell.resolve("") .. libDir .. "JSON")