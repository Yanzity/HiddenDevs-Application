local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local SETTINGS = require(ServerScriptService.Source.Generation.Settings)
local ObstaclesFolder = ServerStorage.Assets.Obstacles.Ratings

local module = {}

--------------------------------------------------
-- Difficulty Selection
--------------------------------------------------

local function RandomDifficulty()
	local lobby = SETTINGS.ServerLobby
	local minDifficulty, maxDifficulty = table.unpack(SETTINGS.LobbyDifficulties[lobby])
	local boost = workspace:GetAttribute("DifficultyBoost") or 0

	local totalWeight = 0
	local weights = {}

	for difficulty = minDifficulty, maxDifficulty do
		local weight = (boost == 0) and 1 or (difficulty ^ boost)
		weights[difficulty] = weight
		totalWeight += weight
	end

	local roll = math.random() * totalWeight
	local runningSum = 0

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

local function RandomObstacle()
	local chosenDifficulty = RandomDifficulty()

	for _, folder in ipairs(ObstaclesFolder:GetChildren()) do
		if folder:GetAttribute("Difficulty") == chosenDifficulty then
			local obstacles = folder:GetChildren()
			return obstacles[math.random(1, #obstacles)]
		end
	end
end

--------------------------------------------------
-- Obstacle Insertion
--------------------------------------------------

local function InsertObstacle(obstacleTemplate, zone)
	local difficulty = obstacleTemplate.Parent:GetAttribute("Difficulty")
	local obstacle = obstacleTemplate:Clone()

	if obstacle:IsA("Model") then
		obstacle:PivotTo(zone.PrimaryPart.CFrame)
	else
		obstacle.CFrame = zone.PrimaryPart.CFrame
	end

	zone:SetAttribute("Difficulty", difficulty)
	obstacle.Name = "Obstacle"

	if obstacle:FindFirstChild("Main") then
		local debug = obstacle.Main:FindFirstChild("DifficultyDebug")
		if debug then
			debug.TextLabel.Text = "Difficulty: " .. difficulty
		end
	end

	obstacle.Parent = zone
end

--------------------------------------------------
-- Player Reset
--------------------------------------------------

local function resetPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Passed", nil)

		if player:FindFirstChild("Data") and player.Data:FindFirstChild("Modifiers") then
			for _, modifier in ipairs(player.Data.Modifiers:GetChildren()) do
				modifier:Destroy()
			end
		end

		local character = player.Character
		if character and character.PrimaryPart then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				character:PivotTo(SETTINGS.SpawnLocation.CFrame + Vector3.new(0, 2, 0))
				
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

local function SpawnObstacles()
	for _, zone in ipairs(workspace.Layout.Zones:GetChildren()) do
		local oldObstacle = zone:FindFirstChild("Obstacle")
		if oldObstacle then
			oldObstacle:Destroy()
		end

		local obstacle = RandomObstacle()
		if obstacle then
			InsertObstacle(obstacle, zone)
		end
	end
end

--------------------------------------------------
-- Module Init
--------------------------------------------------

function module.Init()
	local lobby = SETTINGS.ServerLobby
	local roundTime = SETTINGS.TimeLobby[lobby] * 60

	workspace:SetAttribute("ModifierLoop", 4)

	SpawnObstacles()

	local totalDifficulty = 0
	for _, zone in ipairs(workspace.Layout.Zones:GetChildren()) do
		totalDifficulty += zone:GetAttribute("Difficulty") or 0
	end
	workspace:SetAttribute("OverallDifficulty", totalDifficulty)

	while true do
		if workspace:GetAttribute("Timer") <= 0 then
			task.wait(2)

			if not workspace:GetAttribute("Intermission") then
				-- Start Intermission
				workspace:SetAttribute("Intermission", true)
				workspace:SetAttribute("Timer", SETTINGS.Intermission)

				local winners = workspace:GetAttribute("Winners") or 0
				local boost = workspace:GetAttribute("DifficultyBoost") or 0

				if winners > 0 then
					boost += SETTINGS.DifficultyBoost[lobby].Won * winners
				else
					boost += SETTINGS.DifficultyBoost[lobby].Lost
				end

				workspace:SetAttribute("DifficultyBoost", boost)
				workspace:SetAttribute("Winners", 0)

				SpawnObstacles()
				resetPlayers()

				-- Modifier Logic
				local modifierLoop = (workspace:GetAttribute("ModifierLoop") or 0) + 1
				workspace:SetAttribute("ModifierLoop", modifierLoop)

				if modifierLoop >= SETTINGS.Modifier_Frequency then
					local modifiers = {}
					for name in pairs(SETTINGS.Modifiers[lobby]) do
						table.insert(modifiers, name)
					end

					local chosenModifier = modifiers[math.random(1, #modifiers)]
					workspace:SetAttribute("CurrentModifier", chosenModifier)

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

					workspace:SetAttribute("ModifierLoop", 0)
				end
			else
				-- Start Round
				workspace:SetAttribute("Timer", roundTime)
				workspace:SetAttribute("Intermission", false)
			end
		end

		local winners = workspace:GetAttribute("Winners") or 0
		task.wait(1 / (2 ^ winners))
		workspace:SetAttribute("Timer", workspace:GetAttribute("Timer") - 1)
	end
end

return module
