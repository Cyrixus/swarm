--[[ swarm-drone.lua
	Core drone behavior.
	
	Matthew DiBernardo [01.10.2015]
]]--

--[[ Constants ]]--
local libDir = "/lib/"

--[[ Load Libraries ]]--
-- Load the JSON encoding/decoding library
-- (Big thanks to Jeffrey Friedl for his library! See notice in lib/JSON)
local apiLocation = shell.resolve("") .. libDir .. "JSON"
if not os.loadAPI(apiLocation) then error("Failed to load JSON API @ [" .. apiLocation .. "], aborting.") end
local JSON = JSON.OBJDEF:new() -- Because, you know, CC just letting us load libs normally was too hard.

-- Load the mobility turtle API
apiLocation = shell.resolve("") .. libDir .. "mobility"
if not os.loadAPI(apiLocation) then error("Failed to load mobility API @ [" .. apiLocation .. "], aborting.") end

-- Load the swarmlib API
apiLocation = shell.resolve("") .. libDir .. "swarmlib"
if not os.loadAPI(apiLocation) then error("Failed to load swarmlib API @ [" .. apiLocation .. "], aborting.") end
swarmlib.setRelativeDir(shell.resolve(""))

-- Load the IDLE behavior, because we're going to be running it frequently
local idleLoc = shell.resolve("") .. swarmlib.verbDir .. "IDLE"
if not os.loadAPI(idleLoc) then error("Failed to load IDLE behavior @ [" .. idleLoc .. "], aborting.") end





--[[ SwarmDrone Class Definition ]]--
local function SwarmDrone()
	local self = {} -- 'this' reference
	
	-- UUID
	self.uuid = swarmlib.UUID()
	function self.getUUID() return self.uuid end

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
		
		-- Create the id and id/locs folders if they don't already exist
		local idDir = shell.resolve("") .. swarmlib.identityDir
		if not fs.exists(idDir) then fs.makeDir(idDir) end
		idDir = shell.resolve("") .. swarmlib.locationsDir
		if not fs.exists(idDir) then fs.makeDir(idDir) end
		
		
		-- Reset the behavior array, just in case
		self.behaviors = {}
		
		-- Load the Behavior lists
		local files = fs.list(shell.resolve("") .. swarmlib.behaviorDir)
		for i, file in ipairs(files) do
			local fileName = shell.resolve("") .. swarmlib.behaviorDir .. file
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
		
		
		-- TODO: Collect data about self
		
		
		-- TODO: Load user-created id files(?)
		
		
		--[[ Check for/create important id files ]]--
		-- Fetch uuid, if it exists
		local uuidFile = shell.resolve("") .. swarmlib.identityDir .. "uuid"
		if fs.exists(uuidFile) and not fs.isDir(uuidFile) then
			local f = fs.open(uuidFile, "r")
			if not f then
				error("uuid file exists, but couldn't be opened!")
			end
			local uuid = f.readLine()
			f.close()
			if string.len(uuid) == 8 then
				self.uuid = uuid
			else
				print("WARNING: Loaded uuid was invalid, replacing.")
			end
		end
		
		-- Set this machine's label to the current uuid
		-- This allows files to be saved even when the computer is broken.
		os.setComputerLabel("swarm-drone-"..self.uuid)
		
		-- Write the uuid to disk for later
		local f = fs.open(uuidFile, "w")
		if not f then
			error("Couldn't uuid file for writing!")
		end
		f.write(self.uuid)
		f.close()
		
		
		-- TODO: Announce self to swarm-net
		
		
		-- Attempt to determine absolute position
		local x, y, z = gps.locate(5)
		local gpsSuccess = false
		local lastPos = swarmlib.getExactLocation("LAST_POS", self.uuid)
		if not x then
			print("WARNING: Could not establish location via GPS. Please manually override the "
				.. "generated LAST_POS-XXXX file, providing the absolute coordinates of this machine.")
			if lastPos then
				print("NOTICE: GPS unavailable, assuming last recorded position [" 
					.. lastPos.x .. ", " .. lastPos.y .. ", " .. lastPos.z .. ", " .. lastPos.facing .. "].")
				mobility.setPositionXZ(lastPos.x, lastPos.z, lastPos.y)
				mobility.setFacing(lastPos.facing)
			else
				print("NOTICE: GPS unavailable and no previous position detected, assuming [0, 0, 0, north].")
				mobility.setPositionXZ(0, 0, 0, "north")
			end
		else
			gpsSuccess = true
			mobility.setPositionXZ(x, z, y)
			
			if lastPos then
				print("NOTICE: GPS available and previous position detected, setting position to [" 
					.. x .. ", " .. y .. ", " .. z .. ", " .. lastPos.facing .."].")
				mobility.setFacing(lastPos.facing)
			else
				print("NOTICE: GPS available but previous position undetected, setting position to [" 
					.. x .. ", " .. y .. ", " .. z .. ", " .. "north" .."].")
				mobility.setFacing("north")
			end
		end
		
		
		--[[ TURTLE-ONLY INIT ]]--
		local isTurtle = swarmlib.checkConditional("IS_TURTLE")
		if not isTurtle then
			return
		end
		
		-- Check Immediate Surroundings
		print("Turtle detected! Performing turtle-only initialization...")
		swarmlib.executeVerb("CHECK_SURROUNDINGS")
		
		-- Save the starting position with the identifier HOME, unless one already exists
		
		local home = swarmlib.getExactLocation("HOME", self.uuid)
		if home then
			print("Home location found at [" .. home.x .. ", " .. home.y .. ", " .. home.z .."]")
		else
			print("Creating home location...")
			swarmlib.createPointLocation("HOME", nil, nil, nil, self.uuid)
		end
		
		-- Attempt to determine facing
		local oldPos = mobility.getPosition()
		local couldMove = mobility.moveForward(3)
		if gpsSuccess and couldMove then -- Check that our previous GPS attempt was good, and that we have some space
			print("NOTICE: Attempting to determine absolute facing via GPS...")
			
			-- Get a new reading and figure out our facing
			x, y, z = gps.locate(5)
			if x then
				local facingVec = vector.new(x,y,z) - oldPos
				
				-- North
				if facingVec.z < 0 then
					mobility.setFacing("north")
				end
				
				-- South
				if facingVec.z > 0 then
					mobility.setFacing("south")
				end
				
				-- East
				if facingVec.x > 0 then
					mobility.setFacing("east")
				end
				
				-- West
				if facingVec.x < 0 then
					mobility.setFacing("west")
				end
			end
			print("Facing registered as [" .. mobility.getFacing() .. "].")
		else
			local reason = ""
			if not gpsSuccess then reason = reason .. "No GPS available. " end
			if not couldMove then reason = reason .. "Movement blocked. " end
			print("WARNING: Unable to calculate facing. It is recommended to start this drone with an inital "
				.. "facing of [" .. mobility.getFacing() .. "]; reason: " .. reason)
		end
		print("SwarmDrone Initialization Complete!")
	end

	--[[ doIDLE ]]--
	local function doIDLE()
		IDLE.execute(self)
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
		
		-- Save our current position
   		swarmlib.createPointLocationXZ("LAST_POS", nil, nil, nil, nil, self.uuid)
		
		-- Force an IDLE tick if we're approaching the 10 second limit between os.pullEvent() calls
		local currentTime = os.clock()
		if currentTime - self.lastIdleTime > 3.0 then -- Every 5.0 seconds
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
				if not swarmlib.checkConditional(conditional, params) then
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
			
			swarmlib.executeVerb(activeVerb, verbParams)
			
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
os.unloadAPI(shell.resolve("") .. swarmlib.verbDir .. "IDLE")
os.unloadAPI(shell.resolve("") .. libDir .. "swarmlib")
os.unloadAPI(shell.resolve("") .. libDir .. "mobility")
os.unloadAPI(shell.resolve("") .. libDir .. "JSON")