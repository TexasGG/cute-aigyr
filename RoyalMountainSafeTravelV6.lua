--------------------------------------- Configs ---------------------------------------------------

local Configs = getgenv().Configs
	or {
		["Target"] = 100000000, -- The amount of coins that will be farmed
		["CloseGameUI"] = true, -- Optimize performance
		["ShowStatusUI"] = true, -- Keep it enabled if you want to see the UI that tells you the amount of coins
		["WhiteScreen"] = false, -- Disable Roblox rendering to maximize FPS
		["FPS"] = 120, -- set it to 0 to use the default fps
	}

if not LPH_OBFUSCATED then
	getgenv().LPH_NO_VIRTUALIZE = function(...)
		return (...)
	end
end

--------------------------------------- Wait until game load ---------------------------------------------------

if not game:IsLoaded() then
	game.Loaded:Wait()
end

task.wait(5)

local ReadyEvent =
	game:GetService("ReplicatedStorage"):WaitForChild("Communication"):WaitForChild("Events"):GetChildren()[3]
ReadyEvent:FireServer("Ready")

task.wait(0.3)

local UseEvent =
	game:GetService("ReplicatedStorage"):WaitForChild("Communication"):WaitForChild("Events"):GetChildren()[6]
UseEvent:FireServer("{af4dc9fc-bdf3-489e-b29a-6c0110ced5d7}", "Gait", 2)

--------------------------------------------------- Services -------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("Events")
local TeleportService = game:GetService("TeleportService")

--------------------------------------------------- Variables -------------------------------------------------

local LP = Players.LocalPlayer
local RE = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("Events")
local RF = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("Functions")
local Data = require(LP.PlayerScripts.Priority.Data)
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local References = ReplicatedStorage.References
local Network = References.Utilities.Shared.Network
local lavaConn, charConn
local CurrentLasso = nil
local TravelFinished = false
local MAX_TAME_TIME = 60 -- seconds
local Level = Data.GetLocal("level") or 0
local WorldOrder = {}

-- ============ TRAVEL GUARD ============
local AlreadyTaming = false
local AlreadyTraveling = false
local LastTravelTime = 0
local TRAVEL_COOLDOWN = 8 -- seconds between any two Travel fires
local PendingTravelTarget = nil

-- Holds the currently running local teleport tween (non-blocking).
local CurrentTween = nil

local function GetCurrentIsland()
	if LP.Character and LP.Character.Parent then
		return LP.Character.Parent.Name
	end
	return nil
end

local function WaitForIslandChange(timeout, expected)
	timeout = timeout or 10
	local oldIsland = GetCurrentIsland()
	local elapsed = 0

	while elapsed < timeout do
		task.wait(0.5)
		local cur = GetCurrentIsland()
		if cur and cur ~= oldIsland then
			if not expected or cur == expected then
				return cur
			end
		end
		elapsed += 0.5
	end

	return nil
end

-- Single chokepoint for every cross-island Travel remote fire.
local function SafeTravel(island, waitAfter)
	if not island then
		return false
	end
	if AlreadyTraveling then
		return false
	end
	if GetCurrentIsland() == island then
		return true -- already there, no fire needed
	end
	if tick() - LastTravelTime < TRAVEL_COOLDOWN then
		return false
	end

	AlreadyTraveling = true
	PendingTravelTarget = island
	LastTravelTime = tick()

	print("[SafeTravel] Firing Travel ->", island)
	pcall(function()
		-- Remotes Beautifuler renames the Travel RemoteFunction to "Travel" at startup.
		local TravelRemote = RF:FindFirstChild("Travel")
		if TravelRemote then
			TravelRemote:InvokeServer("Travel", island, 1)
		else
			warn("[SafeTravel] Travel remote not found — Beautifuler may have failed")
		end
	end)

	local newIsland = WaitForIslandChange(12, island)
	if newIsland then
		print("[SafeTravel] Arrived at:", newIsland)
	else
		warn("[SafeTravel] Island did not change in time (target: " .. tostring(island) .. ")")
	end

	if waitAfter and waitAfter > 0 then
		task.wait(waitAfter)
	end

	PendingTravelTarget = nil
	AlreadyTraveling = false
	return newIsland ~= nil
end
-- =======================================

if game.PlaceId == 6989310863 then
	-- Mainland world
	if Level >= 0 and Level < 5 then
		WorldOrder = { "Mainland" }
	elseif Level >= 5 and Level < 20 then
		WorldOrder = { "Mainland", "Blizzard Island" }
	elseif Level >= 20 and Level < 45 then
		WorldOrder = { "Mainland", "Blizzard Island", "Forest Island" }
	elseif Level >= 45 then
		WorldOrder = { "Mainland", "Blizzard Island", "Forest Island", "Royal Island" }
	end
elseif game.PlaceId == 16948692582 then
	-- Mid-level world
	if Level >= 45 and Level < 90 then
		WorldOrder = { "Royal Island" }
	elseif Level >= 90 and Level < 150 then
		WorldOrder = { "Royal Island", "Glacier Island" }
	elseif Level >= 150 then
		WorldOrder = { "Royal Island", "Glacier Island", "Mountain Island" }
	end
elseif game.PlaceId == 16948702874 then
	-- High-level world
	if Level >= 250 then
		WorldOrder = { "Royal Island", "Glacier Island", "Mountain Island" }
	end
end

------------------------------------------------------------Anti-AFK------------------------------------------------------
local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
	VirtualUser:ClickButton2(Vector2.new(0, 0))
end)

-----------------------------------------------------Close Play UI----------------------------------------------------
task.spawn(function()
	local PlayButton
	repeat
		task.wait(0.1)
		if LP:FindFirstChild("PlayerGui") then
			local gui = LP.PlayerGui:FindFirstChild("Loading")
			if gui and gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Bottom") then
				PlayButton = gui.Main.Bottom:FindFirstChild("Play")
			end
		end
	until PlayButton

	local absPos = PlayButton.AbsolutePosition
	local absSize = PlayButton.AbsoluteSize
	local clickPos = Vector2.new(absPos.X + absSize.X / 2, absPos.Y + absSize.Y / 2)
	VirtualUser:CaptureController()
	VirtualUser:ClickButton1(clickPos)

	repeat
		task.wait(0.1)
	until LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")

	local ReadyEvent = ReplicatedStorage.Communication.Events:GetChildren()[3]
	ReadyEvent:FireServer("Ready")
	task.wait(0.3)

	local UseEvent = ReplicatedStorage.Communication.Events:GetChildren()[6]
	UseEvent:FireServer("{af4dc9fc-bdf3-489e-b29a-6c0110ced5d7}", "Gait", 2)
end)

--------------------------------------------- Anti-Death Protection -------------------------------------------
do
	local lavaConn

	local function EnableDeathProtection(char)
		if not char then
			return
		end
		local hum = char:WaitForChild("Humanoid")
		local hrp = char:WaitForChild("HumanoidRootPart")

		if lavaConn then
			lavaConn:Disconnect()
			lavaConn = nil
		end

		hum.BreakJointsOnDeath = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)

		local lastHealth = hum.Health

		lavaConn = hum.HealthChanged:Connect(function(hp)
			if hp < lastHealth then
				hum.Health = lastHealth
			end
			lastHealth = hum.Health
		end)
	end

	if LP.Character then
		EnableDeathProtection(LP.Character)
	end

	LP.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid")
		char:WaitForChild("HumanoidRootPart")
		task.wait(0.1)
		EnableDeathProtection(char)
	end)
end

--------------------------------------------------- Noclip (Anti-Stuck) ---------------------------------------------------

task.spawn(function()
	while true do
		task.wait(2)
		pcall(function()
			local char = LP.Character
			if not char then return end
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
				end
			end
		end)
	end
end)

--------------------------------------------------- Functions -------------------------------------------------
local function WaitForWorld(IslandName, timeout)
	timeout = timeout or 15
	local elapsed = 0
	while not workspace.Islands:FindFirstChild(IslandName) and elapsed < timeout do
		task.wait(1)
		elapsed = elapsed + 1
	end
	return workspace.Islands:FindFirstChild(IslandName) ~= nil
end

local function GetNextWorld()
	local CurrentIsland = GetCurrentIsland()

	if not CurrentIsland then
		return WorldOrder[1]
	end

	for i, world in ipairs(WorldOrder) do
		if world == CurrentIsland then
			return WorldOrder[i + 1] or WorldOrder[1]
		end
	end

	return WorldOrder[1]
end

local function GetStartingIsland()
	local Level = Data.GetLocal("level") or 0

	if Level >= 150 then
		return "Mountain Island"
	elseif Level >= 90 then
		return "Glacier Island"
	elseif Level >= 45 then
		return "Royal Island"
	else
		return "Mainland"
	end
end

-- Startup teleport (Mainland world only)
if game.PlaceId == 6989310863 then
	task.spawn(function()
		while true do
			local CurrentIsland = GetCurrentIsland()
			local StartIsland = GetStartingIsland()

			if CurrentIsland == StartIsland then
				break
			end

			if
				CurrentIsland == "Mainland"
				or CurrentIsland == "Stable Island"
				or CurrentIsland == "Tutorial Island"
				or (CurrentIsland == "Blizzard Island" and Level >= 45)
			then
				local ok = SafeTravel(StartIsland, 1)
				if ok then
					print("Successfully teleported to:", StartIsland)
					break
				else
					warn("Startup teleport failed, will retry after cooldown")
				end
			end

			task.wait(2)
		end
	end)
end

--------------------------------------------------- Local Teleport (non-blocking) -------------------------------------------
local function SafeTeleport(A)
	local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Cancel any tween still running from a previous call
	if CurrentTween then
		pcall(function() CurrentTween:Cancel() end)
		CurrentTween = nil
	end

	local Distance = (hrp.Position - A.Position).Magnitude
	local SafeVelocity = 100
	local Time = Distance / SafeVelocity
	if Time < 0.05 then Time = 0.05 end

	local TI = TweenInfo.new(Time, Enum.EasingStyle.Linear)
	local TP = { CFrame = A }

	-- Anchor HRP so gravity/physics can't fight the tween while noclipped
	hrp.Anchored = true

	CurrentTween = game:GetService("TweenService"):Create(hrp, TI, TP)
	CurrentTween:Play()

	-- Unanchor after the tween finishes (non-blocking)
	local thisTween = CurrentTween
	task.spawn(function()
		thisTween.Completed:Wait()
		-- Only unanchor if this is still the active tween (wasn't superseded)
		if CurrentTween == thisTween then
			local currentHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
			if currentHrp then
				currentHrp.Anchored = false
				currentHrp.Velocity = Vector3.zero
				currentHrp.RotVelocity = Vector3.zero
			end
			CurrentTween = nil
		end
	end)
end

local function CancelTeleport()
	if CurrentTween then
		pcall(function() CurrentTween:Cancel() end)
		CurrentTween = nil
	end
	local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = false
		hrp.Velocity = Vector3.zero
	end
end

local function IsNear(point, threshold)
	local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	return (hrp.Position - point).Magnitude <= (threshold or 25)
end

local function UnequipActiveHorse()
    for uuid, data in pairs(Data.GetLocal({ "inventory" })) do
        if data and data.loc == "following" then
            print("[AutoFarm] Unequipping horse:", uuid)

            RE:WaitForChild("Inventory"):FireServer("Use", uuid, "Pickup")
            return true
        end
    end

    warn("[AutoFarm] No active horse found")
    return false
end

-- Horse spawn coordinates per island
local IslandHorseCoords = {
    ["Mainland"]        = { Vector3.new(187.54, 15.06, -20.37) },
    ["Royal Island"]    = { Vector3.new(193.90, 57.10, -5768.05) },
    ["Blizzard Island"] = { Vector3.new(218.74, 30.17, -3775.73) },
    ["Forest Island"]   = { Vector3.new(-7963.85, 24.28, 3683.25) },
    ["Desert Island"]   = { Vector3.new(49.67, 15.50, 4042.71) },
    ["Glacier Island"]  = { Vector3.new(3216.72, -6.92, -964.91) },
    ["Mountain Island"] = { Vector3.new(-6781.65, 277.10, -170.18) },
    ["Jungle Island"]   = { Vector3.new(3830.86, 15.50, 2650.00) },
    ["Lunar Islands"] = {
        Vector3.new(-2291.25, 127.67, -994.32),
        Vector3.new(-3595.88, 15.98, -4006.31),
    },
    ["Volcano Island"] = {
        Vector3.new(3413.79, 34.57, -8863.07),
        Vector3.new(4662.25, 25.81, -7028.31),
    },
}

-- Scan for the nearest unowned horse near a point on a given island
local function ScanHorsesNear(Island, point, radius)
	radius = radius or math.huge
	if not workspace.Islands:FindFirstChild(Island) then
		return nil
	end
	local Target, MaxDistance = nil, math.huge
	for _, v in ipairs(workspace.Islands[Island]:GetChildren()) do
		if v:IsA("Model") and not v:GetAttribute("owner") and v:GetAttribute("data") and v.PrimaryPart then
			local Distance = (v.PrimaryPart.Position - point).Magnitude
			if Distance < MaxDistance and Distance <= radius then
				MaxDistance = Distance
				Target = v
			end
		end
	end
	return Target
end

local function GetNearestHorse()
	local CurrentIsland = GetCurrentIsland()
	local Level = Data.GetLocal("level") or 0
	local Character = LP.Character
	local HRP = Character and Character:FindFirstChild("HumanoidRootPart")
	if not HRP then
		return nil
	end

	for _, Island in ipairs(WorldOrder) do
		if Island == "Mainland" and Level > 45 then
			continue
		end

		if workspace.Islands:FindFirstChild(Island) then
			local SearchPoints = IslandHorseCoords[Island] or { HRP.Position }

			-- If we're NOT on this island, just check if any horses exist remotely,
			-- and if so travel there. Don't local-teleport first.
			if CurrentIsland ~= Island then
				local anyHorse = nil
				for _, point in ipairs(SearchPoints) do
					anyHorse = ScanHorsesNear(Island, point)
					if anyHorse then break end
				end
				if anyHorse then
					SafeTravel(Island, 2)
					CurrentIsland = GetCurrentIsland()
					if CurrentIsland ~= Island then
						continue
					end
				else
					continue
				end
			end

			-- Now we ARE on the island. Visit each checkpoint, scanning DURING flight.
			for i, point in ipairs(SearchPoints) do
				local hrpCheck = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
				if hrpCheck then
					print(("Teleporting to checkpoint %d of %s"):format(i, Island))
					SafeTeleport(CFrame.new(point)) -- starts tween, returns immediately

					-- Scan continuously while the tween is flying us there
					local maxFlightTime = 20
					local flightStart = tick()

					while tick() - flightStart < maxFlightTime do
						local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
						if not hrp then break end

						-- Scan from our CURRENT position to spot horses we fly past
						local Target = ScanHorsesNear(Island, hrp.Position)
						if Target then
							print(("Horse spotted mid-flight near checkpoint %d of %s"):format(i, Island))
							CancelTeleport()
							return Target
						end

						-- Reached the checkpoint? Move on.
						if IsNear(point, 30) then
							break
						end

						task.wait(0.15)
					end

					-- One more scan at the checkpoint position itself
					local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local Target = ScanHorsesNear(Island, hrp.Position) or ScanHorsesNear(Island, point)
						if Target then
							print(("Horse found at checkpoint %d of %s"):format(i, Island))
							return Target
						end
					end
				end
			end
		end
	end

	return nil
end

local RARE_SPAWN_CHANCE = 0.003

local function IsRareHorse(Value)
	return typeof(Value.spwnChnc) == "number" and Value.spwnChnc <= RARE_SPAWN_CHANCE
end

local function SellAllHorses()
	local SellList = {}

	for Item, Value in pairs(Data.GetLocal({ "inventory" })) do
		if Value and Value.origin then
			if not IsRareHorse(Value) then
				SellList[Item] = 1
			end
		end
	end

	if next(SellList) then
		RE.Shopping:FireServer("SellItems", SellList)
	end
end

local function GetLasso()
	local Level = Data.GetLocal("level") or 0
	local Lasso, LassoName = nil
	local LassoAmount = 0
	local TinOre = 0
	local Rope = 0

	for Name, v in pairs(Data.GetLocal({ "inventory" })) do
		for Property, Value in pairs(v) do
			if Property == "id" then
				for _, ItemData in pairs(require(References).Items.GetInfo(Value)) do
					if ItemData == "Tin Lasso" and Level > 5 then
						Lasso = Name
						LassoName = "Tin Lasso"
						LassoAmount = v.amt or 0
					elseif ItemData == "Lasso" and not Lasso then
						LassoName = "Lasso"
						Lasso = Name
					elseif ItemData == "Tin Ore" then
						TinOre = v.amt or 0
					elseif ItemData == "Rope" then
						Rope = v.amt or 0
					end
				end
			end
		end
	end

	if LassoAmount < 2 and Level > 5 then
		if Rope < 10 then
			RE.Shopping:FireServer("BuyShopItem", "Mainland Shop", 1, 10 - Rope)
		end

		if TinOre < 30 then
			RE.Shopping:FireServer("BuyShopItem", "Mainland Shop", 10, 30 - TinOre)
		end

		RE.Crafting:FireServer("Craft", { ["id"] = 18, ["variants"] = {}, ["amt"] = 10 })
		for Name, v in pairs(Data.GetLocal({ "inventory" })) do
			for Property, Value in pairs(v) do
				if Property == "id" then
					for _, ItemData in pairs(require(References).Items.GetInfo(Value)) do
						if ItemData == "Tin Lasso" then
							Lasso = Name
							LassoName = "Tin Lasso"
							LassoAmount = v.amt or 0
						end
					end
				end
			end
		end
	end

	return Lasso, LassoName
end

local function Tame()
	if AlreadyTaming or AlreadyTraveling then
		return
	end

	local Animal = GetNearestHorse()

	if Animal then
		AlreadyTaming = true

		local Platform = Instance.new("Part")
		Platform.Size = Vector3.new(10, 1, 10)
		Platform.Transparency = 1
		Platform.Anchored = true
		Platform.CanCollide = false
		Platform.Parent = workspace

		local tameStart = tick()

		while Animal and Animal.Parent and task.wait() do
			if tick() - tameStart > MAX_TAME_TIME then
				warn("Anti-Stuck: Tame exceeded time limit, resetting")
				break
			end

			pcall(function()
				local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
				if not hrp then
					return
				end

				local yOffset = (GetCurrentIsland() == "Volcano Island") and 12 or 6
				SafeTeleport(CFrame.new(Animal.PrimaryPart.Position + Vector3.new(0, yOffset, 0)))
				Platform.Position = Animal.PrimaryPart.Position + Vector3.new(0, yOffset - 3, 0)

				RE:WaitForChild("Equipment"):FireServer(CurrentLasso, "Activate", Animal)
			end)
		end

		AlreadyTaming = false

		-- Reset lasso
		RE:WaitForChild("QuickEquipment"):FireServer("Set", "Lasso", CurrentLasso, true)

		-- Safe detach
		if Platform then
			Platform:Destroy()
			if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
				LP.Character.HumanoidRootPart.Velocity = Vector3.zero
			end
		end
	else
		-- No horse anywhere on the current island. Wait briefly in place, then rotate.
		local found = false
		for i = 1, 6 do
			task.wait(2)
			-- Lightweight check: just scan current island without teleporting
			local cur = GetCurrentIsland()
			if cur and workspace.Islands:FindFirstChild(cur) then
				local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local a = ScanHorsesNear(cur, hrp.Position)
					if a then
						found = true
						break
					end
				end
			end
		end

		if found then
			return
		end

		-- Rotate to next world
		local NextWorld = GetNextWorld()
		if not NextWorld then
			warn("No valid next world found!")
			return
		end

		print("No horse found, traveling to:", NextWorld)
		SafeTravel(NextWorld, 6)
	end
end

--------------------------------------------------- Anti-UI Duplication -------------------------------------------------

for _, v in ipairs(game.CoreGui:GetChildren()) do
	if v.Name == "MadeByMangnex" then
		v:Destroy()
	end
end

--------------------------------------------------- UI -------------------------------------------------

local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
ScreenGui.Name = "MadeByMangnex"
ScreenGui.ScreenInsets = Enum.ScreenInsets.None

local Background = Instance.new("Frame", ScreenGui)
Background.Size = UDim2.new(1, 0, 1, 0)
Background.BackgroundTransparency = 0.3
Background.BackgroundColor3 = Color3.new(0, 0, 0)

local GameName = Instance.new("TextLabel", ScreenGui)
GameName.BackgroundTransparency = 1
GameName.TextStrokeTransparency = 0.5
GameName.Position = UDim2.new(0.25, 0, 0.23, 0)
GameName.Size = UDim2.new(0.2, 0, 0.04, 0)
GameName.TextColor3 = Color3.fromRGB(255, 255, 255)
GameName.Text = "Wild Horse Island"
GameName.TextScaled = true
GameName.Font = Enum.Font.FredokaOne

local ElapsedTimeLabel = Instance.new("TextLabel", ScreenGui)
ElapsedTimeLabel.BackgroundTransparency = 1
ElapsedTimeLabel.TextStrokeTransparency = 0.5
ElapsedTimeLabel.Position = UDim2.new(0.23, 0, 0, 7)
ElapsedTimeLabel.Size = UDim2.new(0.5, 0, 0.2, 0)
ElapsedTimeLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
ElapsedTimeLabel.Text = "00:00:00:00"
ElapsedTimeLabel.TextScaled = true
ElapsedTimeLabel.Font = Enum.Font.FredokaOne

local ScriptName = Instance.new("TextLabel", ScreenGui)
ScriptName.BackgroundTransparency = 1
ScriptName.TextStrokeTransparency = 0.5
ScriptName.Position = UDim2.new(0.38, 0, 0.23, 0)
ScriptName.Size = UDim2.new(0.35, 0, 0.04, 0)
ScriptName.TextColor3 = Color3.fromRGB(116, 116, 116)
ScriptName.Text = "Auto Farm made by Mangnex"
ScriptName.TextScaled = true
ScriptName.Font = Enum.Font.FredokaOne

local n = Instance.new("ImageLabel", ScreenGui)
n.Position = UDim2.new(0.36, 0, 0.4, 0)
n.Size = UDim2.new(0.3, 0, 0.15, 0)
n.Image = "rbxassetid://6936545322"
n.BackgroundTransparency = 1

local CurrencyIcon = Instance.new("ImageLabel", n)
CurrencyIcon.Position = UDim2.new(-0.2, 0, -0.4, 0)
CurrencyIcon.Rotation = 27
CurrencyIcon.Size = UDim2.new(0.4, 0, 1.5, 0)
CurrencyIcon.Image = "rbxassetid://13116451197"
CurrencyIcon.BackgroundTransparency = 1

local CurrencyTextBackground = Instance.new("TextLabel", n)
CurrencyTextBackground.Font = Enum.Font.FredokaOne
CurrencyTextBackground.BackgroundTransparency = 1
CurrencyTextBackground.TextScaled = true
CurrencyTextBackground.Text = 0
CurrencyTextBackground.TextColor3 = Color3.fromRGB(0, 0, 0)
CurrencyTextBackground.Position = UDim2.new(0.3, -16, 0.1, 2)
CurrencyTextBackground.Size = UDim2.new(0.7, 0, 0.8, 0)
CurrencyTextBackground.TextXAlignment = Enum.TextXAlignment.Left

local CurrencyText = Instance.new("TextLabel")
CurrencyText.Font = Enum.Font.FredokaOne
CurrencyText.BackgroundTransparency = 1
CurrencyText.TextScaled = true
CurrencyText.Text = 0
CurrencyText.TextColor3 = Color3.fromRGB(193, 192, 196)
CurrencyText.Position = UDim2.new(0.3, -17, 0.1, 0)
CurrencyText.Size = UDim2.new(0.7, 0, 0.8, 0)
CurrencyText.Parent = n
CurrencyText.TextXAlignment = Enum.TextXAlignment.Left

local D = 0
local H = 0
local M = 0
local S = 0

local function Update()
	local daysText = string.format("%02d", D)
	local hoursText = string.format("%02d", H)
	local minutesText = string.format("%02d", M)
	local secondsText = string.format("%02d", S)

	ElapsedTimeLabel.Text = daysText .. ":" .. hoursText .. ":" .. minutesText .. ":" .. secondsText
end

local function Start()
	S = S + 1

	if S >= 60 then
		S = 0
		M = M + 1
	end

	if M >= 60 then
		M = 0
		H = H + 1
	end

	if H >= 24 then
		H = 0
		D = D + 1
	end

	Update()
end

task.spawn(LPH_NO_VIRTUALIZE(function()
	pcall(function()
		while task.wait(1) do
			local Money = Data.GetLocal({ "Tokens" }) or 0
			CurrencyText.Text = Money
			CurrencyTextBackground.Text = Money
			Start()
		end
	end)
end))

--------------------------------------------------- Remotes Beautifuler (AntiCheat) -------------------------------------------------

local handlerMap = getupvalue(getsenv(Network).GetHandler, 1)

for name, data in pairs(handlerMap.Event) do
	if data and type(data) == "table" then
		if data.Remote then data.Remote.Name = name end
		if data.Unreliable then data.Unreliable.Name = name end
	end
end

for name, data in pairs(handlerMap.Function) do
	if data and type(data) == "table" then
		if data.Remote then data.Remote.Name = name end
	end
end

--------------------------------------------------- Block Game Analytics Remote -------------------------------------------------

local namecall
namecall = hookmetamethod(game, "__namecall", function(self, ...)
	if getnamecallmethod() == "FireServer" and tostring(self) == "GameAnalyticsError" then
		return
	end
	return namecall(self, ...)
end)

--------------------------------------------------- Private Server Check -------------------------------------------------
local PRIVATE_SERVER_PLACES = {
	[6989310863] = true,
	[16948692582] = true,
	[16948702874] = true,
}

if PRIVATE_SERVER_PLACES[game.PlaceId] and #Players:GetPlayers() >= 3 then
	task.spawn(function()
		LP:Kick("Too many players in this server! Please join a private server.")
	end)
end

task.wait(1) -- small delay to ensure data is ready
UnequipActiveHorse()
-------------------------------------------------------- Webhook Config (Breed + Coat + Mane) ----------------------------------------------------------

local WEBHOOK_URL =
	"https://discordapp.com/api/webhooks/1464050232198172793/1miQ4_u4bMLmDnfAjORZNUZp80jMcUmJF4zZBpFh0DmUFxHOrqmeXyi79zj-Rbyj445_"

local SCAN_INTERVAL = 10 -- seconds between inventory scans

-- BREEDS you WANT to be pinged for, by display name. Leave EMPTY ( {} ) to watch EVERY breed.
local TARGET_BREEDS = {
	"Friesian",
	"Arab",
	"Tennessee Walking Horse",
	"Percheron",
	"Clydesdale",
}

-- COAT colors you do NOT want to be pinged for (exact `variants.colour` string).
local BLOCKED_COAT_COLORS = {
	["chestnutArab"] = true,
	["greyArab"] = true,
	["blackArab"] = true,
	["bayArab"] = true,
	["buckskinClydes2"] = true,
	["brownClydes2"] = true,
	["bayClydes2"] = true,
	["blackClydes2"] = true,
	["baySabinoClydes2"] = true,
	["chestnutClydes2"] = true,
	["glacierChimera"] = true,
	["mountainSunrise"] = true,
	["crackedLava"] = true,
	["jaguar"] = true,
	["deepSpace"] = true,
	["blackTWH"] = true,
	["chestnutTWH"] = true,
	["bayTWH"] = true,
	["greyPercheron"] = true,
	["chestnutPercheron"] = true,
	["greyPercheron"] = true,
	["blueRoanPercheron"] = true,
	["bayPercheron"] = true,
}

-- MANE filter: ONLY island-unique manes ping. This is an ALLOW list, so you no longer
-- have to block every new event / natural-diet mane by hand.
--   * Natural-diet horses (isNatDyed = true) never ping, whatever their mane.
--   * Regular breed manes (black, white, palomino, ...) and event manes aren't listed,
--     so they never ping either.
-- When a NEW island adds new manes, the console prints "[BreedWebhook] Unknown mane ..."
-- for manes it hasn't seen — add the island ones here.
local ISLAND_UNIQUE_MANES = {
	-- Jungle
	emerald = true, topaz = true, jaguarSpots = true, tigerStripes = true, mossy = true, amethyst = true,
	-- Volcano
	volcanicOrange = true, volcanicBlack = true, crackedLavaFade = true, prismatic = true, pearlyBlack = true,
	-- Lunar
	moonstone = true, deepSpace = true, obsidian = true, pearlyBlue = true, neonPurple = true, neonBlue = true,
	-- Glacier
	glacierBlue = true, glacierGreen = true, snowyGlacierFade = true,
	-- Mountain
	sapphire = true, pinkCowPrint = true, sunriseStreaks = true,
	-- Royal
	leathery = true, cowPrint = true, pearlyPink = true,
	-- Desert
	zebraStripes = true, pearlyRed = true, dustyFade = true,
}

-- Regular (non-island) manes — never ping, and don't trigger the "Unknown mane" console hint.
local BASE_MANES = {
	black = true, white = true, palomino = true, grey = true, darkGrey = true,
	chestnut = true, darkChestnut = true, liverChestnut = true, flaxen = true,
	champagne = true, pearl = true, goldenCremello = true, red = true, orange = true,
	brunblakk = true, rodblakk = true, gra = true, ulsblakk = true,
}

-- OPTIONAL rarity cap. Set to a number (e.g. 0.0005) to ONLY ping horses at or below
-- that spawn chance. Leave as nil to ignore spawn chance entirely.
local MAX_SPAWN_CHANCE = 0.0005

local HttpService = game:GetService("HttpService")

-- HTTP request function (name varies between executors).
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request

-- References.Items.GetInfo -> breed names (References already loaded above at boot).
local ItemsGetInfo = require(References).Items.GetInfo

local alreadyNotified = {}

-- Normalize the target list into a case-insensitive lookup, and remember if it's empty.
local TARGET_LOOKUP = {}
local HAS_TARGETS = false
for _, name in ipairs(TARGET_BREEDS) do
	TARGET_LOOKUP[string.lower(name)] = true
	HAS_TARGETS = true
end

-- Cache id -> resolved breed name so we don't re-require every scan.
local breedNameCache = {}

-- Returns (canonicalName, isTargeted).
local function ResolveBreed(id)
	local cached = breedNameCache[id]
	if cached then
		return cached[1], cached[2]
	end

	local names = {}
	pcall(function()
		local info = ItemsGetInfo(id)
		if type(info) == "table" then
			for _, v in pairs(info) do
				if type(v) == "string" then
					names[#names + 1] = v
				end
			end
		elseif type(info) == "string" then
			names[1] = info
		end
	end)

	for _, n in ipairs(names) do
		if TARGET_LOOKUP[string.lower(n)] then
			breedNameCache[id] = { n, true }
			return n, true
		end
	end

	local canonical = names[1] or ("Breed#" .. tostring(id))
	local result = { canonical, false }
	breedNameCache[id] = result
	return canonical, false
end

local function SendWebhook(title, description, fields)
	local data = {
		["username"] = "🐎 Horse Sniper",
		["embeds"] = {
			{
				["title"] = title,
				["description"] = description,
				["color"] = 16766720,
				["fields"] = fields,
				["footer"] = { ["text"] = "Wild Horse Island | Breed Watcher" },
				["timestamp"] = DateTime.now():ToIsoDate(),
			},
		},
	}

	local body = HttpService:JSONEncode(data)

	pcall(function()
		httpRequest({
			Url = WEBHOOK_URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
	end)
end

local reportedUnknownManes = {}

local function NotifyHorse(uuid, HorseData)
	if not HorseData then
		return
	end

	-- Console hint for manes we've never classified (e.g. a new island's manes).
	-- Skips natural-diet and throwback horses, whose manes are diet/event colours.
	local maneSeen = HorseData.variants and HorseData.variants.maneColour
	if maneSeen and not HorseData.isNatDyed and not HorseData.throwbackEvent
		and not ISLAND_UNIQUE_MANES[maneSeen] and not BASE_MANES[maneSeen]
		and not reportedUnknownManes[maneSeen] then
		reportedUnknownManes[maneSeen] = true
		print("[BreedWebhook] Unknown mane '" .. tostring(maneSeen) .. "' on "
			.. tostring(HorseData.islandFnd) .. " — add to ISLAND_UNIQUE_MANES if it's island-unique.")
	end

	-- Natural-diet horses never ping.
	if HorseData.isNatDyed then
		return
	end

	-- Optional rarity gate.
	if MAX_SPAWN_CHANCE then
		if typeof(HorseData.spwnChnc) ~= "number" or HorseData.spwnChnc > MAX_SPAWN_CHANCE then
			return
		end
	end

	-- 1. Breed filter (by name). If TARGET_BREEDS is empty, all breeds pass.
	local breedName, isTargeted = ResolveBreed(HorseData.id)
	if HAS_TARGETS and not isTargeted then
		return
	end

	local variants = HorseData.variants or {}
	local coat = tostring(variants.colour or "")
	local maneColor = tostring(variants.maneColour or "unknown")

	-- 2. Coat block.
	if BLOCKED_COAT_COLORS[coat] then
		return
	end

	-- 3. Mane must be island-unique.
	if not ISLAND_UNIQUE_MANES[maneColor] then
		return
	end

	-- Dedupe by the horse's unique UUID (the inventory key).
	if alreadyNotified[uuid] then
		return
	end
	alreadyNotified[uuid] = true

	local island = tostring(HorseData.islandFnd or "Unknown")

	local fields = {
		{ name = "🐎 Breed", value = breedName, inline = true },
		{ name = "🎨 Coat", value = coat, inline = true },
		{ name = "🎯 Spawn", value = tostring(HorseData.spwnChnc), inline = true },
		{ name = "🎨 Mane Style", value = tostring(variants.maneStyle or "Default"), inline = true },
		{ name = "🎨 Tail Style", value = tostring(variants.tailStyle or "Default"), inline = true },
		{ name = "💇 Mane Color", value = maneColor, inline = true },
		{ name = "💇 Tail Color", value = tostring(variants.tailColour or "Natural"), inline = true },
		{ name = "🌍 Island", value = island, inline = true },
	}

	if variants.hornStyle or variants.hornColour then
		table.insert(fields, {
			name = "🦄 Horn",
			value = tostring(variants.hornStyle or "?") .. " / " .. tostring(variants.hornColour or "?"),
			inline = true,
		})
	end

	table.insert(fields, { name = "🆔 Horse ID", value = tostring(uuid), inline = false })

	SendWebhook(
		"🔥 " .. breedName .. " CAUGHT! | " .. LP.DisplayName,
		"**Found on " .. island .. "** — coat: `" .. coat .. "` | mane: `" .. maneColor .. "`",
		fields
	)
end

if httpRequest then
	if HAS_TARGETS then
		print("[BreedWebhook] Watching breeds:", table.concat(TARGET_BREEDS, ", "))
	else
		print("[BreedWebhook] Watching ALL breeds (block lists only).")
	end

	task.spawn(function()
		while true do
			pcall(function()
				for uuid, Value in pairs(Data.GetLocal({ "inventory" })) do
					-- Value.origin is present only on real caught horses.
					if Value and Value.origin then
						NotifyHorse(uuid, Value)
					end
				end
			end)
			task.wait(SCAN_INTERVAL)
		end
	end)
else
	warn("[BreedWebhook] No HTTP request function available in this executor.")
end

---------------------------------------------------------------------- Render ----------------------------------------------------------------------

if Configs.WhiteScreen then
	pcall(function()
		game:GetService("RunService"):Set3dRenderingEnabled(false)
	end)
end

--------------------------------------------------- Auto Load -------------------------------------------------

if LP.PlayerGui:FindFirstChild("Loading") then
	firesignal(LP.PlayerGui.Loading.Main.Bottom.Play.Activated)
end

--------------------------------------------------- Auto Equip Lasso -------------------------------------------------

task.spawn(function()
	while task.wait(1) do
		pcall(function()
			if LP.Character then
				local Lasso, LassoName = GetLasso()
				CurrentLasso = Lasso

				if
					LP.Character.RightHand:FindFirstChild("WearableWeld")
					and LP.Character.RightHand:FindFirstChild("WearableWeld").Part1
				then
					local ToolName = LP.Character.RightHand:FindFirstChild("WearableWeld").Part1.Parent.Name
					if ToolName ~= LassoName then
						RE:WaitForChild("QuickEquipment"):FireServer("Set", "Lasso", CurrentLasso, true)
					end
				else
					RE:WaitForChild("QuickEquipment"):FireServer("Set", "Lasso", CurrentLasso, true)
				end
			end
		end)
	end
end)

--------------------------------------------------- RAM Reset via Blizzard Travel ---------------------------------------------------

task.spawn(function()
	task.wait(80 * 60) -- wait 90 minutes
	-- Let any active tame finish cleanly first (up to 70 s)
	local waitStart = tick()
	while AlreadyTaming and tick() - waitStart < 70 do
		task.wait(1)
	end
	print("[RAMReset] 90 min reached — traveling to Blizzard Island to flush world memory...")
	AlreadyTraveling = true
	pcall(function()
		local TravelRemote = RF:FindFirstChild("Travel")
		if TravelRemote then
			TravelRemote:InvokeServer("Travel", "Blizzard Island", 1)
		end
	end)
	AlreadyTraveling = false
end)

--------------------------------------------------- Auto Tame -------------------------------------------------

local EquipmentEvent = RE:WaitForChild("QuickEquipment")
while task.wait(1) do
	if not AlreadyTaming and not AlreadyTraveling then
		pcall(Tame)
	end

	task.spawn(function()
		pcall(SellAllHorses)
	end)

	if LP.Character and not AlreadyTraveling then
		local Lasso, LassoName = GetLasso()
		CurrentLasso = Lasso

		local RightHand = LP.Character:FindFirstChild("RightHand")
		if RightHand then
			local WearableWeld = RightHand:FindFirstChild("WearableWeld")
			local NeedsEquip = false

			if WearableWeld and WearableWeld.Part1 then
				local ToolName = WearableWeld.Part1.Parent.Name
				if ToolName ~= LassoName then
					NeedsEquip = true
				end
			else
				NeedsEquip = true
			end

			if NeedsEquip then
				EquipmentEvent:FireServer("Set", "Lasso", CurrentLasso, true)
			end
		end
	end
end
