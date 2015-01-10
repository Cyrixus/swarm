--[[ swarm-drone.lua
	Core drone behavior.
]]--

-- Load the JSON encoding/decoding library
-- (Big thanks to Jeffrey Friedl for his library! See notice in lib/JSON.lua)
if not os.loadAPI(shell.resolve("") .. "/lib/JSON") then error("Failed to load JSON API, aborting.") end

-- Constants
local behaviorDir = "/behaviors"
local verbDir = "/verbs"
local resourceDir = "/resources"
local conditionalDir = "/conditionals"

-- SwarmDrone Class Definition
local function SwarmDrone()
	local self = {} -- 'this' reference

	-- Tick Info
	self.startTickSecondTime = nil
	self.ticks = 0
	self.ticksPerSecond = 0
	
	-- Behaviors
	self.behaviors = {}

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
		for i, file in fs.list(shell.resolve(behaviorDir)) do
			print(file)
			if not fs.isDir(file) then
				-- Extract and decode the behavior information
				local behaviorTable = JSON:decode(fs.open(file).readAll())
				
				-- Append all the behaviors to our master list of behaviors
				for k, behavior in behaviorTable do
					self.behaviors[#self.behaviors + 1] = behavior
				end
			end
		end -- repeat for each file in the primary directory. In the future,
			-- subdirectories can be used for alternate behavior sets.
		
		-- DEBUG: Print all the behaviors
		for k, b in self.behaviors do
			print(b)
		end
		
		-- TODO: Collect data about self and immediate surroundings (needs RESOURCE definitions)
		
		-- TODO: Announce self to swarm-net
	end

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

	local function onTick()
		--[[ FIXME: This is where the magic should start happening.
			Step 1: Regenerate constraints (fuel state, inventory fullness)
			Step 2: Poll OS events, handle anything relevent
			Step 3: Determine Active Behavior via priority, queue, fuzzy logic, etc.
			Step 4: Execute Active Behavior
		]]--
	end

	return self
end -- EOF SwarmDrone Definition

local drone = SwarmDrone()
drone.init()