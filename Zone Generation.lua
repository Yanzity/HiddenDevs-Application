local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Game settings module (difficulty, timings, modifiers, etc.)
local SETTINGS = require(ServerScriptService.Source.Generation.Settings)

-- Folder containing obstacle models grouped by difficulty rating
local ObstaclesFolder = ServerStorage.Assets.Obstacles.Ratings

local module = {}

--------------------------------------------------
-- Difficulty Selection
--------------------------------------------------

-- Picks a difficulty based on lobby settings and a scaling boost
local function RandomDifficulty()
	local lobby = SETTINGS.ServerLobby
	
	-- Allowed difficulty range for this lobby
	local minDifficulty, maxDifficulty = table.unpack(SETTINGS.LobbyDifficulties[lobby])
	
	-- Boost increases chance of higher difficulties over time
	local boost = workspace:GetAttribute("DifficultyBoost") or 0

	local totalWeight = 0
	local weights = {}

	-- Assign a weight to each difficulty
	for difficulty = minDifficulty, maxDifficulty do
		-- If no boost, all difficulties are equal
		-- Otherwise higher difficulties get exponentially favored
		local weight = (boost == 0) and 1 or (difficulty ^ boost)
		weights[difficulty] = weight
		totalWeight += weight
	end

	-- Random weighted roll
	local roll = math.random() * totalWeight
	local runningSum = 0

	-- Select difficulty based on weight distribution
	for difficulty = minDifficulty, maxDifficulty do
		runningSum += weights[difficulty]
		if roll <= runningSum then
			return difficulty
		end
	end
end

--------------------------------------------------
-- Obstacle Selection
--------------------------------------------------

-- Chooses a random obstacle matching the chosen difficulty
local function RandomObstacle()
	local chosenDifficulty = RandomDifficulty()

	-- Look for the folder with the matching difficulty attribute
	for _, folder in ipairs(ObstaclesFolder:GetChildren()) do
		if folder:GetAttribute("Difficulty") == chosenDifficulty then
			local obstacles = folder:GetChildren()
			
			-- Pick a random obstacle from that difficulty tier
			return obstacles[math.random(1, #obstacles)]
		end
	end
end

--------------------------------------------------
-- Obstacle Insertion
--------------------------------------------------

-- Clones and places an obstacle inside a zone
local function InsertObstacle(obstacleTemplate, zone)
	local difficulty = obstacleTemplate.Parent:GetAttribute("Difficulty")
	local obstacle = obstacleTemplate:Clone()

	-- Correctly position models vs. single parts
	if obstacle:IsA("Model") then
		obstacle:PivotTo(zone.PrimaryPart.CFrame)
	else
		obstacle.CFrame = zone.PrimaryPart.CFrame
	end

	-- Store the difficulty on the zone itself
	zone:SetAttribute("Difficulty", difficulty)
	obstacle.Name = "Obstacle"

	-- Update in-world debug UI if present
	if obstacle:FindFirstChild("Main") then
		local debug = obstacle.Main:FindFirstChild("DifficultyDebug")
		if debug then
			debug.TextLabel.Text = "Difficulty: " .. difficulty
		end
	end

	-- Parent obstacle to the zone so it gets cleaned up easily
	obstacle.Parent = zone
end

--------------------------------------------------
-- Player Reset
--------------------------------------------------

-- Resets players between rounds/intermissions
local function resetPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		-- Clear pass status
		player:SetAttribute("Passed", nil)

		-- Remove all active modifiers
		if player:FindFirstChild("Data") and player.Data:FindFirstChild("Modifiers") then
			for _, modifier in ipairs(player.Data.Modifiers:GetChildren()) do
				modifier:Destroy()
			end
		end

		local character = player.Character
		if character and character.PrimaryPart then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				-- Teleport player back to spawn
				character:PivotTo(SETTINGS.SpawnLocation.CFrame + Vector3.new(0, 2, 0))
				
				-- Reset default movement values
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				humanoid.AutoRotate = true
			end
		end
	end
end

--------------------------------------------------
-- Obstacle Spawning
--------------------------------------------------

-- Clears old obstacles and spawns new ones in each zone
local function SpawnObstacles()
	for _, zone in ipairs(workspace.Layout.Zones:GetChildren()) do
		-- Remove previous obstacle if it exists
		local oldObstacle = zone:FindFirstChild("Obstacle")
		if oldObstacle then
			oldObstacle:Destroy()
		end

		-- Insert a new randomly selected obstacle
		local obstacle = RandomObstacle()
		if obstacle then
			InsertObstacle(obstacle, zone)
		end
	end
end

--------------------------------------------------
-- Module Init
--------------------------------------------------

-- Main game loop controller
function module.Init()
	local lobby = SETTINGS.ServerLobby
	
	-- Round time in seconds
	local roundTime = SETTINGS.TimeLobby[lobby] * 60

	-- Tracks when to apply modifiers
	workspace:SetAttribute("ModifierLoop", 4)

	-- Initial obstacle spawn
	SpawnObstacles()

	-- Calculate total difficulty for debugging/balancing
	local totalDifficulty = 0
	for _, zone in ipairs(workspace.Layout.Zones:GetChildren()) do
		totalDifficulty += zone:GetAttribute("Difficulty") or 0
	end
	workspace:SetAttribute("OverallDifficulty", totalDifficulty)

	-- Core game loop
	while true do
		-- When timer reaches zero, switch states
		if workspace:GetAttribute("Timer") <= 0 then
			task.wait(2)

			if not workspace:GetAttribute("Intermission") then
				--------------------------------------------------
				-- Start Intermission
				--------------------------------------------------
				workspace:SetAttribute("Intermission", true)
				workspace:SetAttribute("Timer", SETTINGS.Intermission)

				local winners = workspace:GetAttribute("Winners") or 0
				local boost = workspace:GetAttribute("DifficultyBoost") or 0

				-- Increase difficulty faster if players win
				if winners > 0 then
					boost += SETTINGS.DifficultyBoost[lobby].Won * winners
				else
					-- Punish failure with a smaller boost
					boost += SETTINGS.DifficultyBoost[lobby].Lost
				end

				workspace:SetAttribute("DifficultyBoost", boost)
				workspace:SetAttribute("Winners", 0)

				-- Prepare next round
				SpawnObstacles()
				resetPlayers()

				--------------------------------------------------
				-- Modifier Logic
				--------------------------------------------------
				local modifierLoop = (workspace:GetAttribute("ModifierLoop") or 0) + 1
				workspace:SetAttribute("ModifierLoop", modifierLoop)

				-- Apply a modifier every X rounds
				if modifierLoop >= SETTINGS.Modifier_Frequency then
					local modifiers = {}
					for name in pairs(SETTINGS.Modifiers[lobby]) do
						table.insert(modifiers, name)
					end

					-- Pick a random modifier
					local chosenModifier = modifiers[math.random(1, #modifiers)]
					workspace:SetAttribute("CurrentModifier", chosenModifier)

					-- Apply modifier to all players
					for _, player in ipairs(Players:GetPlayers()) do
						if player:FindFirstChild("Data") and player.Data:FindFirstChild("Modifiers") then
							local modifier = Instance.new("BoolValue")
							modifier.Name = chosenModifier
							modifier:SetAttribute(
								"Multiplicator",
								SETTINGS.Modifiers[lobby][chosenModifier]
							)
							modifier.Parent = player.Data.Modifiers
						end
					end

					-- Reset modifier loop counter
					workspace:SetAttribute("ModifierLoop", 0)
				end
			else
				--------------------------------------------------
				-- Start Round
				--------------------------------------------------
				workspace:SetAttribute("Timer", roundTime)
				workspace:SetAttribute("Intermission", false)
			end
		end

		-- Winners speed up the game loop slightly
		local winners = workspace:GetAttribute("Winners") or 0
		task.wait(1 / (2 ^ winners))

		-- Decrease the timer every tick
		workspace:SetAttribute("Timer", workspace:GetAttribute("Timer") - 1)
	end
end

return module
