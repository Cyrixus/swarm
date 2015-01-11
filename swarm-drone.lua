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
local locationsDir = "/id/locs"


-- Function for loading libs
local function loadLib(libLocation)
	if not os.loadAPI(libLocation) then
		print("Failed to load library [" .. libLocation .. "], returning false.")
		return false
	end
	return true
end

-- A simple UUID method borrowed from https://gist.github.com/jrus/3197011 and simplified further
-- because we don't REALLY need a whole UUID for anything here
local random = math.random
function UUID()
    local template ='xxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
	        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
	        return string.format('%x', v)
	    end)
end


--[[ Load Libraries ]]--
-- Load the JSON encoding/decoding library
-- (Big thanks to Jeffrey Friedl for his library! See notice in lib/JSON)
local apiLocation = shell.resolve("") .. libDir .. "JSON"
if not os.loadAPI(apiLocation) then error("Failed to load JSON API @ [" .. apiLocation .. "], aborting.") end
local JSON = JSON.OBJDEF:new() -- Because, you know, CC just letting us load libs normally was too hard.

-- Load the mobility turtle API
apiLocation = shell.resolve("") .. libDir .. "mobility"
if not os.loadAPI(apiLocation) then error("Failed to load mobility API @ [" .. apiLocation .. "], aborting.") end

-- Load the IDLE behavior, because we're going to be running it frequently
local idleLoc = shell.resolve("") .. verbDir .. "IDLE"
if not os.loadAPI(idleLoc) then error("Failed to load IDLE behavior @ [" .. idleLoc .. "], aborting.") end


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

function forEachLocation(callback, locID) -- Make sure callback is a function accepting a table as a param
	local locsFolder = shell.resolve("") .. locationsDir
	local locs = fs.list(locsFolder)
	for i, locFile in ipairs(locs) do
		-- Check to see if this location is in the set we're looking for
		if locID == nil or string.find(locFile, locID, 1, true) then
			local locFileName = shell.resolve("") .. locationsDir .. locFile
		
			-- Open each non-dir file
			if not fs.isDir(locFileName) then
				local f = fs.open(locFileName, "r")
				if not f then
					error("Couldn't open file [" .. locFileName .. "]")
				end
				
				-- Decode its contents into a lua table
				local loc = JSON:decode(f.readAll())
				f.close()
				
				-- Call the callback
				callback(loc)
			end
		end
	end
end

function getClosestLocation(locID)
	-- Build a list of potential locations
    local targetList = {}
    forEachLocation(function(loc) targetList[#targetList + 1] = loc end, locID)
    
    -- If there's none, finish.
    if #targetList == 0 then return end
    
    -- If there's only one, that's what we're after!
    local targetLoc = nil
    if #targetList == 1 then
        targetLoc = targetList[1]
    end
    
    -- If there's more than one, find the closest
    if #targetList > 1 then
        for i, l in ipairs(targetList) do
            if targetLoc == nil then
                targetLoc = l
            else
                local v = vector.new(l.x, l.y, l.z)
                local vNew = mobility.getPosition() - v
                local vOld = mobility.getPosition() - targetLoc
                
                if vOld:length() > vNew:length() then
                    targetLoc = l
                end
            end
        end 
    end
    
    return targetLoc
end

function createPointLocationXZ(locID, x, z, height, facing, uuid)
	local locsFolder = shell.resolve("") .. locationsDir
	
	-- Validate all of the params, or replace the missing bits with parts of our current location
	local currentPos = mobility.getPosition()
	local currentFacing = mobility.getFacing()
	
	local loc = {}
	loc.name = locID
	loc.x = x or currentPos.x
	loc.z = z or currentPos.z
	loc.y = height or currentPos.y
	loc.facing = facing or currentFacing
	loc.uuid = uuid or UUID()
	
	-- Write the location to a file
	local f = fs.open(locsFolder .. loc.name .. "-" .. loc.uuid, "w")
	if not f then
		error("Couldn't loc file for writing!")
	end
	f.write(JSON:encode(loc))
	f.close()	
end

function deleteLocation(loc)
	if not loc.name or not loc.uuid then return end
	
	-- Remove the file containing this location from the file system
	local locsFolder = shell.resolve("") .. locationsDir
	fs.delete(locsFolder .. loc.name .. "-" .. loc.uuid)
end


--[[ SwarmDrone Class Definition ]]--
local function SwarmDrone()
	local self = {} -- 'this' reference
	
	-- UUID
	self.uuid = UUID()
	function self.uuid() return self.uuid end

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
		
		
		-- TODO: Collect data about self
		
		
		-- TODO: Load user-created id files(?)
		
		
		--[[ Check for/create important id files ]]--
		-- Fetch uuid, if it exists
		local uuidFile = shell.resolve("") .. identityDir .. "uuid"
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
		if not x then
			print("WARNING: Could not establish location via GPS. Please manually override the "
				.. "generated LASTPOS-XXXX file, providing the absolute coordinates of this machine.")
		else
			mobility.setPositionXZ(x, z, y)
		end
		
		
		--[[ TURTLE-ONLY INIT ]]--
		local isTurtle = checkConditional("IS_TURTLE")
		if not isTurtle then
			return
		end
		
		-- Check Immediate Surroundings
		print("Turtle detected! Performing turtle-only initialization...")
		executeVerb("CHECK_SURROUNDINGS")
		
		-- Save the starting position with the identifier HOME, unless one already exists
		local doesHomeExist = false
		forEachLocation(function() doesHomeExist = true end, "HOME")
		
		if not doesHomeExist then
			createPointLocationXZ("HOME")
		end
		
		-- Attempt to determine facing
		local oldPos = mobility.getPosition()
		if x and mobility.moveForward(3) then -- Check that our previous GPS attempt was good, and that we have some space
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
		end
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