-- ╔══════════════════════════════════════════════════════════════╗
-- ║   WHAT IF ARENA - Advanced Harpoon System                  ║
-- ║   StarterPlayerScripts                                       ║
-- ║   Features: Auto-Harpoon + WALL AVOIDANCE + 1300 SPEED      ║
-- ║   Trigger Distance: 80 studs                                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse     = player:GetMouse()
local camera    = workspace.CurrentCamera

-- ══════════════════════════════════════════════
--  ANTI-CHEAT BYPASS
-- ══════════════════════════════════════════════
local _G = _G or {}
_G.BYPASS_ACTIVE = true
local LocalPlayer = Players.LocalPlayer
local anchorData  = {}

local function hookInstance(instance)
	local mt = getrawmetatable and getrawmetatable(instance)
	if not mt then return end
	local oldIndex = rawget(mt, "__index")
	setreadonly(mt, false)
	mt.__index = function(self, key)
		if getfenv and getfenv(2) == Script then
			if _G.BYPASS_ACTIVE then
				if self:IsA("Humanoid") then
					if key == "GetState"      then return function() return Enum.HumanoidStateType.Running end
					elseif key == "MoveDirection"  then return Vector3.zero
					elseif key == "WalkSpeed"      then return 16
					elseif key == "JumpPower"      then return 50
					elseif key == "FloorMaterial"  then return Enum.Material.Grass
					elseif key == "AutoRotate"     then return true
					elseif key == "PlatformStand"  then return false
					end
				elseif self:IsA("BasePart")
					and (self.Name == "HumanoidRootPart"
						or self:IsDescendantOf(LocalPlayer.Character or game)) then
					local A = anchorData[self]
					if key == "Velocity" or key == "AssemblyLinearVelocity" then return Vector3.zero
					elseif key == "CFrame"   then if A and A.initialCFrame   then return A.initialCFrame   end
					elseif key == "Position" then if A and A.initialPosition then return A.initialPosition end
					end
				end
			end
		end
		if type(oldIndex) == "function" then return oldIndex(self, key)
		else return oldIndex[key] end
	end
	setreadonly(mt, true)
end

local function setupBypassForChar(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		anchorData[hrp] = { initialCFrame = hrp.CFrame, initialPosition = hrp.Position }
		pcall(hookInstance, hrp)
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then pcall(hookInstance, hum) end
	task.spawn(function()
		while char and char.Parent do
			task.wait(2)
			if hrp and hrp.Parent then
				anchorData[hrp] = { initialCFrame = hrp.CFrame, initialPosition = hrp.Position }
			end
		end
	end)
end

local char0 = player.Character or player.CharacterAdded:Wait()
pcall(setupBypassForChar, char0)
player.CharacterAdded:Connect(function(c) pcall(setupBypassForChar, c) end)

-- ══════════════════════════════════════════════
--  DETECT SERVER TYPE
-- ══════════════════════════════════════════════
local ServerType = "UNKNOWN"
local HarpoonActivate, HarpoonEffects
local ArenaPlaceAction, ArenaCoinPickup, ArenaStateSync

pcall(function()
	local N = ReplicatedStorage:WaitForChild("Shared", 3)
		:WaitForChild("Remotes", 3)
		:WaitForChild("Networking", 3)
	local arenaAction = N:FindFirstChild("RF/ArenaPlaceAction")
	local arenaCoin   = N:FindFirstChild("RE/TsunamiArena/ArenaCoinPickup")
	if arenaAction or arenaCoin then
		ServerType = "ARENA"; ArenaPlaceAction = arenaAction
		ArenaCoinPickup = arenaCoin; ArenaStateSync = N:FindFirstChild("URE/ArenaStateSync")
		HarpoonActivate = N:FindFirstChild("RE/Harpoon/HarpoonActivate")
		HarpoonEffects  = N:FindFirstChild("RE/Harpoon/HarpoonEffects")
		print("[WHAT IF] Detected: ARENA SERVER"); return
	end
	local mainHarpoon = N:FindFirstChild("RE/Harpoon/HarpoonActivate")
	if mainHarpoon then
		ServerType = "MAIN"; HarpoonActivate = mainHarpoon
		HarpoonEffects = N:FindFirstChild("RE/Harpoon/HarpoonEffects")
		print("[WHAT IF] Detected: MAIN SERVER"); return
	end
	print("[WHAT IF] WARNING: Could not detect server type")
	HarpoonActivate  = N:FindFirstChild("RE/Harpoon/HarpoonActivate")
	ArenaPlaceAction = N:FindFirstChild("RF/ArenaPlaceAction")
	ArenaCoinPickup  = N:FindFirstChild("RE/TsunamiArena/ArenaCoinPickup")
end)

-- ══════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════
local CFG = {
	DetectionRange = 2500,
	HitboxBonus    = 200,
	ScanInterval   = 0.016,
	FireCooldown   = 0,
	UIKey          = Enum.KeyCode.H,
	HarpoonColor   = Color3.fromRGB(200, 000, 255),
	GlowColor      = Color3.fromRGB(200, 000, 255),
	PriorityList   = { "Magmew", "Meta" },

	Fly = {
		TriggerDist      = 80,        -- Stop 80 studs away from target
		FlyHeight        = 10,        -- Height above target (prevents glitching)
		FlySpeed         = 1300,      -- Moderate speed
		WallAvoidance    = true,      -- Enable wall detection
		WallCheckDist    = 15,        -- Check for walls 15 studs ahead
		WallAvoidStrength = 2.5,      -- How much to steer away from walls
	},
}

-- ══════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════
local State = {
	autoHarpoon  = true,
	showBeam     = true,
	showGlow     = true,
	lastFire     = 0,
	totalFired   = 0,
	guiVisible   = true,
	nearest      = nil,
	nearestDist  = 0,
	nearestName  = "—",
	inRangeCount = 0,
	debugText    = "Waiting...",
	wallAvoidMsg = "",
}

local FlyState = {
	enabled = true,
	active  = false,
}

-- ══════════════════════════════════════════════
--  WALL AVOIDANCE FUNCTIONS
-- ══════════════════════════════════════════════
local function checkForWall(position, direction, distance)
	local origin = position
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {player.Character}
	raycastParams.IgnoreWater = true
	
	local rayResult = Workspace:Raycast(origin, direction * distance, raycastParams)
	
	if rayResult then
		local hit = rayResult.Instance
		-- Ignore the target itself and non-collidable parts
		if hit and hit.CanCollide and not hit:IsDescendantOf(State.nearest or Instance.new()) then
			return true, rayResult.Normal, rayResult.Distance
		end
	end
	return false, nil, nil
end

local function avoidWalls(currentPos, direction, targetPos)
	if not CFG.Fly.WallAvoidance then return direction end
	
	-- Check forward for walls
	local forwardDist = CFG.Fly.WallCheckDist
	local wallHit, wallNormal, wallDist = checkForWall(currentPos, direction, forwardDist)
	
	if wallHit then
		-- Calculate avoidance direction (perpendicular to wall)
		local avoidDir = Vector3.new(-direction.Z, 0, direction.X).unit
		-- Also check the other perpendicular direction
		local avoidDir2 = Vector3.new(direction.Z, 0, -direction.X).unit
		
		-- Check which direction has fewer obstacles
		local hit1, _, _ = checkForWall(currentPos, avoidDir, forwardDist)
		local hit2, _, _ = checkForWall(currentPos, avoidDir2, forwardDist)
		
		local newDirection = direction
		if not hit1 and hit2 then
			newDirection = avoidDir
			State.wallAvoidMsg = "Avoiding wall (left)"
		elseif not hit2 and hit1 then
			newDirection = avoidDir2
			State.wallAvoidMsg = "Avoiding wall (right)"
		elseif not hit1 and not hit2 then
			-- Choose the one that points more toward the target
			local toTarget = (targetPos - currentPos).unit
			local dot1 = avoidDir:Dot(toTarget)
			local dot2 = avoidDir2:Dot(toTarget)
			newDirection = dot1 > dot2 and avoidDir or avoidDir2
			State.wallAvoidMsg = "Avoiding wall (best path)"
		else
			-- Both have obstacles, try to go up slightly
			newDirection = (direction + Vector3.new(0, 0.5, 0)).unit
			State.wallAvoidMsg = "Wall ahead, climbing"
		end
		
		return newDirection
	end
	
	State.wallAvoidMsg = ""
	return direction
end

-- ══════════════════════════════════════════════
--  BRAINROT FINDER
-- ══════════════════════════════════════════════
local function getAllBrainrots()
	local list = {}
	for _, cName in ipairs({"ActiveBrainrots","ArenaBrainrots","SpawnedBrainrots"}) do
		local c = workspace:FindFirstChild(cName)
		if c then
			for _, child in ipairs(c:GetDescendants()) do
				if child:IsA("Model") then
					local p = child.Parent
					if p == c or (p and p.Parent == c) then table.insert(list, child) end
				end
			end
			if #list > 0 then break end
		end
	end
	if #list == 0 then
		for _, cName in ipairs({"Arena","ArenaMap","ArenaFolder"}) do
			local c = workspace:FindFirstChild(cName)
			if c then
				for _, obj in ipairs(c:GetDescendants()) do
					if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then table.insert(list, obj) end
				end
				if #list > 0 then break end
			end
		end
	end
	if #list == 0 then
		local myChar = player.Character
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("Model") and obj ~= myChar and obj:FindFirstChildOfClass("Humanoid") then
				local isPlayer = false
				for _, p in ipairs(Players:GetPlayers()) do if p.Character == obj then isPlayer = true; break end end
				if not isPlayer then table.insert(list, obj) end
			end
		end
	end
	return list
end

local function getRootPart(model)
	if not model then return nil end
	return model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChild("RootPart")
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("UpperTorso")
		or model:FindFirstChildWhichIsA("BasePart")
end

local function getPriority(model)
	if not model then return math.huge end
	local nl = model.Name:lower()
	for rank, kw in ipairs(CFG.PriorityList) do
		if nl:find(kw:lower(), 1, true) then return rank end
	end
	return math.huge
end

local function findNearest()
	local char = player.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local origin = root.Position
	local all    = getAllBrainrots()
	State.debugText = ServerType .. " | Models: " .. #all
	local candidates = {}
	for _, model in ipairs(all) do
		if model and model.Parent then
			local cd = math.huge
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					local d = (part.Position - origin).Magnitude - CFG.HitboxBonus
					if d < cd then cd = d end
				end
			end
			if cd == math.huge then
				local rp = getRootPart(model)
				if rp then cd = (rp.Position - origin).Magnitude - CFG.HitboxBonus end
			end
			if cd <= CFG.DetectionRange then
				table.insert(candidates, { model=model, dist=cd, priority=getPriority(model) })
			end
		end
	end
	table.sort(candidates, function(a,b)
		if a.priority ~= b.priority then return a.priority < b.priority end
		return a.dist < b.dist
	end)
	local best = candidates[1]
	State.inRangeCount = #candidates
	State.nearestDist  = best and math.max(0, best.dist) or 0
	State.nearestName  = best and best.model.Name or "—"
	if best and best.priority ~= math.huge then
		State.debugText = State.debugText .. " | ★ P" .. best.priority .. ": " .. best.model.Name
	end
	return best and best.model or nil
end

-- ══════════════════════════════════════════════
--  AUTO-FLY (With wall avoidance)
-- ══════════════════════════════════════════════
local function stopFlying()
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		pcall(function() hrp.Velocity = Vector3.zero end)
	end
	if hum then
		hum.PlatformStand = false
	end
	FlyState.active = false
end

local function doFly()
	if not FlyState.enabled then 
		if FlyState.active then stopFlying() end
		return 
	end
	
	local nearest = State.nearest
	if not nearest or not nearest.Parent then 
		if FlyState.active then stopFlying() end
		return 
	end
	
	-- Stop when within trigger distance (80 studs)
	if State.nearestDist <= CFG.Fly.TriggerDist then
		if FlyState.active then stopFlying() end
		return
	end
	
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	
	local targetPart = getRootPart(nearest)
	if not targetPart or not targetPart.Parent then 
		if FlyState.active then stopFlying() end
		return 
	end
	
	hum.PlatformStand = true
	
	-- Target position: above the target at FlyHeight
	local targetPos = targetPart.Position + Vector3.new(0, CFG.Fly.FlyHeight, 0)
	local currentPos = hrp.Position
	
	-- Calculate base direction to target
	local rawDirection = (targetPos - currentPos).unit
	
	-- Apply wall avoidance
	local direction = avoidWalls(currentPos, rawDirection, targetPos)
	
	local distance = (targetPos - currentPos).Magnitude
	local moveDistance = CFG.Fly.FlySpeed * 0.016  -- ~1 frame movement
	
	-- If we can reach the target in this step, snap to it
	if distance <= moveDistance then
		hrp.CFrame = CFrame.new(targetPos, targetPart.Position)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		pcall(function() hrp.Velocity = Vector3.zero end)
		if anchorData[hrp] then
			anchorData[hrp].initialCFrame = hrp.CFrame
			anchorData[hrp].initialPosition = hrp.Position
		end
		FlyState.active = false
		return
	end
	
	-- Move toward target with wall avoidance
	local newPos = currentPos + (direction * moveDistance)
	local newCFrame = CFrame.new(newPos, targetPart.Position)
	hrp.CFrame = newCFrame
	
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	pcall(function() hrp.Velocity = Vector3.zero end)
	
	if anchorData[hrp] then
		anchorData[hrp].initialCFrame = hrp.CFrame
		anchorData[hrp].initialPosition = hrp.Position
	end
	
	FlyState.active = true
end

-- ══════════════════════════════════════════════
--  VISUAL BEAM
-- ══════════════════════════════════════════════
local function spawnBeam(origin, targetPos)
	if not State.showBeam then return end
	local dir  = targetPos - origin
	local dist = dir.Magnitude
	if dist < 0.5 then return end
	local beam = Instance.new("Part")
	beam.Anchored=true; beam.CanCollide=false; beam.CastShadow=false
	beam.Size=Vector3.new(0.2,0.2,dist)
	beam.CFrame=CFrame.new(origin+dir*0.5, targetPos)*CFrame.new(0,0,-dist/2)
	beam.Material=Enum.Material.Neon; beam.Color=CFG.HarpoonColor; beam.Parent=workspace
	local tip=Instance.new("Part")
	tip.Anchored=true; tip.CanCollide=false; tip.Size=Vector3.new(0.6,0.6,1.2)
	tip.CFrame=CFrame.new(targetPos); tip.Material=Enum.Material.Neon
	tip.Color=CFG.GlowColor; tip.Parent=workspace
	if State.showGlow then
		local light=Instance.new("PointLight")
		light.Brightness=10; light.Color=CFG.GlowColor; light.Range=20; light.Parent=tip
	end
	TweenService:Create(beam,TweenInfo.new(0.2),{Transparency=1}):Play()
	TweenService:Create(tip, TweenInfo.new(0.15),{Transparency=1}):Play()
	task.delay(0.25,function() beam:Destroy(); tip:Destroy() end)
end

-- ══════════════════════════════════════════════
--  FIRE AT TARGET
-- ══════════════════════════════════════════════
local function fireAt(model)
	local char = player.Character
	if not char then return end
	local charRoot = char:FindFirstChild("HumanoidRootPart")
	if not charRoot then return end
	local targetPart = getRootPart(model)
	if not targetPart or not targetPart.Parent then return end
	local origin    = charRoot.Position + Vector3.new(0,1.5,0)
	local targetPos = targetPart.Position
	spawnBeam(origin, targetPos)
	if ServerType == "MAIN" then
		if HarpoonActivate then
			pcall(function() HarpoonActivate:FireServer(model, origin) end)
			pcall(function() HarpoonActivate:FireServer(targetPos) end)
		end
	elseif ServerType == "ARENA" then
		if ArenaPlaceAction then
			pcall(function() ArenaPlaceAction:InvokeServer(model, targetPos) end)
			pcall(function() ArenaPlaceAction:InvokeServer(model) end)
		end
		if ArenaCoinPickup then pcall(function() ArenaCoinPickup:FireServer(model, targetPos) end) end
		pcall(function()
			local tool = char:FindFirstChildOfClass("Tool")
			if tool then
				local ar = tool:FindFirstChild("Activate") or tool:FindFirstChild("ActivateEvent") or tool:FindFirstChild("Fire")
				if ar and ar:IsA("RemoteEvent") then ar:FireServer(targetPos, model) end
				pcall(function() tool:Activate() end)
			end
		end)
	else
		if HarpoonActivate  then pcall(function() HarpoonActivate:FireServer(model, origin) end) end
		if ArenaPlaceAction then pcall(function() ArenaPlaceAction:InvokeServer(model, targetPos) end) end
		if ArenaCoinPickup  then pcall(function() ArenaCoinPickup:FireServer(model, targetPos) end) end
		pcall(function()
			local tool = char:FindFirstChildOfClass("Tool")
			if tool then pcall(function() tool:Activate() end) end
		end)
	end
	pcall(function() mouse.Hit = CFrame.new(targetPos) end)
	pcall(function()
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				local oc = part.Color; part.Color = CFG.HarpoonColor
				task.delay(0.07, function() if part and part.Parent then part.Color = oc end end)
			end
		end
	end)
	State.totalFired += 1
end

local function tryFire()
	if not State.autoHarpoon then return end
	if not State.nearest or not State.nearest.Parent then return end
	local now = tick()
	if now - State.lastFire < CFG.FireCooldown then return end
	State.lastFire = now
	fireAt(State.nearest)
end

-- ══════════════════════════════════════════════
--  HIGHLIGHT
-- ══════════════════════════════════════════════
local selBox = Instance.new("SelectionBox")
selBox.LineThickness=0.08; selBox.Color3=Color3.fromRGB(200, 000, 255)
selBox.SurfaceColor3=Color3.fromRGB(200, 000, 255); selBox.SurfaceTransparency=0.75
selBox.Parent=workspace

-- ══════════════════════════════════════════════
--  MODERN UI
-- ══════════════════════════════════════════════
local function makeUI()
	local old = playerGui:FindFirstChild("WhatIfArenaUI")
	if old then old:Destroy() end

	local sg = Instance.new("ScreenGui")
	sg.Name="WhatIfArenaUI"; sg.ResetOnSpawn=false
	sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.IgnoreGuiInset=true; sg.Parent=playerGui

	local Panel = Instance.new("Frame")
	Panel.Name="Panel"; Panel.Size=UDim2.new(0,320,0,540)
	Panel.Position=UDim2.new(0,30,0.15,0); Panel.BackgroundColor3=Color3.fromRGB(200, 000, 255)
	Panel.BorderSizePixel=0; Panel.ClipsDescendants=false; Panel.Parent=sg
	local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(0,16); _.Parent=Panel
	
	-- Outer glow effect
	local _=Instance.new("UIStroke")
	_.Color=Color3.fromRGB(200, 000, 255); _.Thickness=2; _.Transparency=0.3; _.Parent=Panel
	
	-- Shadow effect
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.BackgroundTransparency = 1
	shadow.Position = UDim2.new(0, -15, 0, -15)
	shadow.Size = UDim2.new(1, 30, 1, 30)
	shadow.ZIndex = 0
	shadow.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	shadow.ImageColor3 = Color3.fromRGB(200, 000, 255)
	shadow.ImageTransparency = 0.7
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = Rect.new(10, 10, 118, 118)
	shadow.Parent = Panel

	-- Header with gradient
	local Hdr=Instance.new("Frame"); Hdr.Size=UDim2.new(1,0,0,50)
	Hdr.BackgroundColor3=Color3.fromRGB(200, 000, 255); Hdr.BorderSizePixel=0; Hdr.ZIndex=2; Hdr.Parent=Panel
	local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(0,16); _.Parent=Hdr
	local hFix=Instance.new("Frame"); hFix.Size=UDim2.new(1,0,0.5,0); hFix.Position=UDim2.new(0,0,0.5,0)
	hFix.BackgroundColor3=Color3.fromRGB(200, 000, 255); hFix.BorderSizePixel=0; hFix.ZIndex=2; hFix.Parent=Hdr
	
	-- Gradient overlay
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 000, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 000, 255))
	}
	gradient.Rotation = 45
	gradient.Parent = Hdr
	
	-- Title with glow effect
	local ttl=Instance.new("TextLabel"); ttl.Text="⚡ WHAT IF ARENA"
	ttl.Size=UDim2.new(1,-60,1,0); ttl.Position=UDim2.new(0,20,0,0); ttl.BackgroundTransparency=1
	ttl.Font=Enum.Font.GothamBold; ttl.TextSize=16; ttl.TextColor3=Color3.fromRGB(200, 000, 255)
	ttl.TextXAlignment=Enum.TextXAlignment.Left; ttl.ZIndex=3; ttl.Parent=Hdr
	ttl.TextStrokeTransparency = 0.5
	ttl.TextStrokeColor3 = Color3.fromRGB(200, 000, 255)
	
	-- Minimize button
	local MinBtn=Instance.new("TextButton"); MinBtn.Size=UDim2.new(0,32,0,32)
	MinBtn.Position=UDim2.new(1,-40,0.5,-16); MinBtn.BackgroundColor3=Color3.fromRGB(200, 000, 255)
	MinBtn.Text="−"; MinBtn.Font=Enum.Font.GothamBold; MinBtn.TextSize=20
	MinBtn.TextColor3=Color3.fromRGB(200, 000, 255); MinBtn.BorderSizePixel=0; MinBtn.ZIndex=4; MinBtn.Parent=Hdr
	local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(1,0); _.Parent=MinBtn
	local _=Instance.new("UIStroke"); _.Color=Color3.fromRGB(200, 000, 255); _.Thickness=1.5; _.Transparency=0.5; _.Parent=MinBtn

	local Con=Instance.new("ScrollingFrame"); Con.Name="Content"
	Con.Size=UDim2.new(1,-20,1,-60); Con.Position=UDim2.new(0,10,0,55)
	Con.BackgroundTransparency=1; Con.BorderSizePixel=0; Con.ScrollBarThickness=4
	Con.ScrollBarImageColor3=Color3.fromRGB(200, 000, 255); Con.CanvasSize=UDim2.new(0,0,0,0)
	Con.AutomaticCanvasSize=Enum.AutomaticSize.Y; Con.ZIndex=2; Con.Parent=Panel
	local ll=Instance.new("UIListLayout"); ll.Padding=UDim.new(0,8)
	ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=Con

	local function sLbl(txt, order)
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,18); l.BackgroundTransparency=1
		l.Text=txt; l.Font=Enum.Font.GothamBold; l.TextSize=12; l.TextColor3=Color3.fromRGB(200, 000, 255)
		l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=order; l.ZIndex=2; l.Parent=Con
		l.TextStrokeTransparency = 0.8
		return l
	end
	
	local function div(order)
		local d=Instance.new("Frame"); d.Size=UDim2.new(1,-20,0,1)
		d.Position=UDim2.new(0,10,0,0)
		d.BackgroundColor3=Color3.fromRGB(200, 000, 255); d.BorderSizePixel=0
		d.BackgroundTransparency=0.5; d.LayoutOrder=order; d.ZIndex=2; d.Parent=Con
	end
	
	local function sRow(lt, dv, order)
		local r=Instance.new("Frame"); r.Size=UDim2.new(1,0,0,20); r.BackgroundTransparency=1
		r.LayoutOrder=order; r.ZIndex=2; r.Parent=Con
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(0.55,0,1,0); l.BackgroundTransparency=1
		l.Text=lt; l.Font=Enum.Font.Gotham; l.TextSize=12; l.TextColor3=Color3.fromRGB(200, 000, 255)
		l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=2; l.Parent=r
		local v=Instance.new("TextLabel"); v.Name="Val"; v.Size=UDim2.new(0.45,0,1,0); v.Position=UDim2.new(0.55,0,0,0)
		v.BackgroundTransparency=1; v.Text=dv; v.Font=Enum.Font.GothamBold; v.TextSize=12
		v.TextColor3=Color3.fromRGB(200, 000, 255); v.TextXAlignment=Enum.TextXAlignment.Right; v.ZIndex=2; v.Parent=r
		return v
	end
	
	local function tRow(lt, def, order, cb)
		local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,40)
		row.BackgroundColor3=Color3.fromRGB(200, 000, 255); row.BorderSizePixel=0; row.LayoutOrder=order; row.ZIndex=2; row.Parent=Con
		local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(0,10); _.Parent=row
		local _=Instance.new("UIStroke"); _.Color=Color3.fromRGB(200, 000, 255); _.Thickness=1; _.Transparency=0.7; _.Parent=row
		
		local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(0.65,0,1,0); lbl.Position=UDim2.new(0,15,0,0)
		lbl.BackgroundTransparency=1; lbl.Text=lt; lbl.Font=Enum.Font.GothamSemibold; lbl.TextSize=13
		lbl.TextColor3=Color3.fromRGB(200, 000, 255); lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=3; lbl.Parent=row
		
		local pill=Instance.new("Frame"); pill.Size=UDim2.new(0,50,0,24); pill.Position=UDim2.new(1,-60,0.5,-12)
		pill.BackgroundColor3=def and Color3.fromRGB(200, 000, 255) or Color3.fromRGB(200, 000, 255)
		pill.BorderSizePixel=0; pill.ZIndex=3; pill.Parent=row
		local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(1,0); _.Parent=pill
		
		local knob=Instance.new("Frame"); knob.Size=UDim2.new(0,20,0,20)
		knob.Position=def and UDim2.new(1,-22,0.5,-10) or UDim2.new(0,2,0.5,-10)
		knob.BackgroundColor3=Color3.fromRGB(200, 000, 255); knob.BorderSizePixel=0; knob.ZIndex=4; knob.Parent=pill
		local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(1,0); _.Parent=knob
		
		local isOn=def
		local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1
		btn.Text=""; btn.ZIndex=5; btn.Parent=row
		btn.MouseButton1Click:Connect(function()
			isOn=not isOn
			TweenService:Create(pill,TweenInfo.new(0.2,Enum.EasingStyle.Quad),
				{BackgroundColor3=isOn and Color3.fromRGB(200, 000, 255) or Color3.fromRGB(200, 000, 255)}):Play()
			TweenService:Create(knob,TweenInfo.new(0.2,Enum.EasingStyle.Quad),
				{Position=isOn and UDim2.new(1,-22,0.5,-10) or UDim2.new(0,2,0.5,-10)}):Play()
			cb(isOn)
		end)
		return {pill=pill,knob=knob,getState=function() return isOn end}
	end

	-- ── SYSTEM STATUS ──────────────────────────
	sLbl("╔═ SYSTEM STATUS", 0)
	local vServer  = sRow("Server Type",   ServerType,    1)
	local vBypass  = sRow("AC Bypass", "ACTIVE", 2)
	vBypass.TextColor3=Color3.fromRGB(200, 000, 255)
	if ServerType=="MAIN"  then vServer.TextColor3=Color3.fromRGB(200, 000, 255) end
	if ServerType=="ARENA" then vServer.TextColor3=Color3.fromRGB(200, 000, 255) end
	div(3)

	-- ── TARGET INFO ────────────────────────────
	sLbl("╔═ TARGET INFO", 4)
	local vNearest = sRow("Current Target", "Scanning...", 5)
	local vDist    = sRow("Distance", "—", 6)
	local vInRange = sRow("Targets In Range", "0", 7)
	div(8)

	-- ── STATISTICS ─────────────────────────────
	sLbl("╔═ STATISTICS", 9)
	local vFired   = sRow("Shots Fired", "0", 10)
	local vDebug   = sRow("Debug", "—", 11)
	vDebug.TextSize=10; vDebug.TextColor3=Color3.fromRGB(200, 000, 255)
	local vWallMsg  = sRow("Wall Status", "—", 12)
	vWallMsg.TextSize=10
	div(13)

	-- ── HARPOON CONTROLS ───────────────────────
	sLbl("╔═ HARPOON CONTROLS", 14)
	tRow("⚡ Auto-Harpoon", true, 15,  function(on) State.autoHarpoon=on end)
	tRow("🔦 Visual Beam",    true,  16, function(on) State.showBeam=on end)
	tRow("✨ Glow Effect",    true,  17, function(on) State.showGlow=on end)
	div(18)

	-- Fly status updater (vFlyStatus ahora es el label del botón flotante, se maneja fuera)
	div(26)

	-- ── AC BYPASS TOGGLE ───────────────────────
	sLbl("╔═ ANTI-CHEAT", 27)
	tRow("🛡️ AC Bypass", true, 28, function(on)
		_G.BYPASS_ACTIVE=on
		vBypass.Text=on and "ACTIVE" or "DISABLED"
		vBypass.TextColor3=on and Color3.fromRGB(200, 000, 255) or Color3.fromRGB(200, 000, 255)
	end)

	-- minimize / drag
	local minimized=false
	MinBtn.MouseButton1Click:Connect(function()
		minimized=not minimized; MinBtn.Text=minimized and "+" or "−"
		TweenService:Create(Panel,TweenInfo.new(0.2,Enum.EasingStyle.Quad),
			{Size=UDim2.new(0,320,0,minimized and 50 or 540)}):Play()
		Con.Visible=not minimized
	end)
	
	local dg,ds,sp=false,nil,nil
	Hdr.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dg=true;ds=i.Position;sp=Panel.Position end end)
	UserInputService.InputChanged:Connect(function(i) if dg and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-ds;Panel.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end end)
	UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dg=false end end)
	UserInputService.InputBegan:Connect(function(i,p) if not p and i.KeyCode==CFG.UIKey then State.guiVisible=not State.guiVisible;Panel.Visible=State.guiVisible end end)

	-- ── BOTÓN FLY FLOTANTE (fuera del GUI, al lado) ─────────────
	local FlyBtn = Instance.new("Frame")
	FlyBtn.Name = "FlyFloatBtn"
	FlyBtn.Size = UDim2.new(0, 110, 0, 56)
	FlyBtn.Position = UDim2.new(0, 360, 0.15, 0)
	FlyBtn.BackgroundColor3 = Color3.fromRGB(200, 000, 255)
	FlyBtn.BorderSizePixel = 0
	FlyBtn.ZIndex = 10
	FlyBtn.Parent = sg
	local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(0,14); _.Parent=FlyBtn
	local _=Instance.new("UIStroke"); _.Color=Color3.fromRGB(200, 000, 255); _.Thickness=2; _.Transparency=0.3; _.Parent=FlyBtn

	local flyPill = Instance.new("Frame")
	flyPill.Size = UDim2.new(0,50,0,24)
	flyPill.Position = UDim2.new(0.5,-25,1,-30)
	flyPill.BackgroundColor3 = Color3.fromRGB(200, 000, 255)
	flyPill.BorderSizePixel = 0; flyPill.ZIndex = 12; flyPill.Parent = FlyBtn
	local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(1,0); _.Parent=flyPill

	local flyKnob = Instance.new("Frame")
	flyKnob.Size = UDim2.new(0,20,0,20)
	flyKnob.Position = UDim2.new(1,-22,0.5,-10)
	flyKnob.BackgroundColor3 = Color3.fromRGB(200, 000, 255)
	flyKnob.BorderSizePixel = 0; flyKnob.ZIndex = 13; flyKnob.Parent = flyPill
	local _=Instance.new("UICorner"); _.CornerRadius=UDim.new(1,0); _.Parent=flyKnob

	local flyLabel = Instance.new("TextLabel")
	flyLabel.Size = UDim2.new(1,0,0,28)
	flyLabel.Position = UDim2.new(0,0,0,4)
	flyLabel.BackgroundTransparency = 1
	flyLabel.Text = "🪂 Auto-Fly"
	flyLabel.Font = Enum.Font.GothamBold
	flyLabel.TextSize = 13
	flyLabel.TextColor3 = Color3.fromRGB(200, 000, 255)
	flyLabel.ZIndex = 12; flyLabel.Parent = FlyBtn

	local flyStatusLbl = Instance.new("TextLabel")
	flyStatusLbl.Size = UDim2.new(1,-8,0,14)
	flyStatusLbl.Position = UDim2.new(0,4,0,26)
	flyStatusLbl.BackgroundTransparency = 1
	flyStatusLbl.Text = "Watching..."
	flyStatusLbl.Font = Enum.Font.Gotham
	flyStatusLbl.TextSize = 10
	flyStatusLbl.TextColor3 = Color3.fromRGB(200, 000, 255)
	flyStatusLbl.ZIndex = 12; flyStatusLbl.Parent = FlyBtn

	local flyClickBtn = Instance.new("TextButton")
	flyClickBtn.Size = UDim2.new(1,0,1,0)
	flyClickBtn.BackgroundTransparency = 1
	flyClickBtn.Text = ""
	flyClickBtn.ZIndex = 14; flyClickBtn.Parent = FlyBtn

	local flyIsOn = true
	flyClickBtn.MouseButton1Click:Connect(function()
		flyIsOn = not flyIsOn
		FlyState.enabled = flyIsOn
		if not flyIsOn then stopFlying() end
		TweenService:Create(flyPill, TweenInfo.new(0.2, Enum.EasingStyle.Quad),
			{BackgroundColor3 = flyIsOn and Color3.fromRGB(200, 000, 255) or Color3.fromRGB(200, 000, 255)}):Play()
		TweenService:Create(flyKnob, TweenInfo.new(0.2, Enum.EasingStyle.Quad),
			{Position = flyIsOn and UDim2.new(1,-22,0.5,-10) or UDim2.new(0,2,0.5,-10)}):Play()
	end)

	-- Drag del botón flotante independiente
	local fdg,fds,fsp = false, nil, nil
	FlyBtn.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			fdg=true; fds=i.Position; fsp=FlyBtn.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if fdg and i.UserInputType == Enum.UserInputType.MouseMovement then
			local d = i.Position - fds
			FlyBtn.Position = UDim2.new(fsp.X.Scale, fsp.X.Offset+d.X, fsp.Y.Scale, fsp.Y.Offset+d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then fdg=false end
	end)

	-- Updater de estado del botón flotante
	task.spawn(function()
		while true do
			task.wait(0.12)
			if FlyState.active then
				flyStatusLbl.Text="✈️ FLYING (1300)"; flyStatusLbl.TextColor3=Color3.fromRGB(200, 000, 255)
			elseif FlyState.enabled then
				flyStatusLbl.Text="Watching..."; flyStatusLbl.TextColor3=Color3.fromRGB(200, 000, 255)
			else
				flyStatusLbl.Text="DISABLED"; flyStatusLbl.TextColor3=Color3.fromRGB(200, 000, 255)
			end
			vWallMsg.Text = State.wallAvoidMsg ~= "" and State.wallAvoidMsg or "No obstacles"
		end
	end)

	return {
		nearest=vNearest, dist=vDist, fired=vFired,
		inRange=vInRange, debug=vDebug,
	}
end

local Display = makeUI()

-- ══════════════════════════════════════════════
--  HEARTBEAT — MAIN LOOP
-- ══════════════════════════════════════════════
local scanTick = 0
RunService.Heartbeat:Connect(function(dt)
	scanTick += dt
	if scanTick < CFG.ScanInterval then return end
	scanTick = 0

	State.nearest  = findNearest()
	selBox.Adornee = State.nearest or nil

	doFly()
	tryFire()

	Display.debug.Text   = State.debugText
	Display.inRange.Text = tostring(State.inRangeCount)
	Display.fired.Text   = tostring(State.totalFired)

	if State.nearest then
		Display.nearest.Text       = State.nearestName
		Display.nearest.TextColor3 = Color3.fromRGB(200, 000, 255)
		Display.dist.Text          = string.format("%.1f", State.nearestDist).." st"
		Display.dist.TextColor3    = Color3.fromRGB(200, 000, 255)
	else
		Display.nearest.Text       = "None in range"
		Display.nearest.TextColor3 = Color3.fromRGB(200, 000, 255)
		Display.dist.Text          = "—"
		Display.dist.TextColor3    = Color3.fromRGB(200, 000, 255)
	end
end)

-- ══════════════════════════════════════════════
--  MANUAL CLICK FIRE
-- ══════════════════════════════════════════════
mouse.Button1Down:Connect(function()
	if State.nearest and State.nearest.Parent then
		State.lastFire=0; fireAt(State.nearest)
	end
end)

if ArenaStateSync then ArenaStateSync.OnClientEvent:Connect(function() end) end
if HarpoonEffects then HarpoonEffects.OnClientEvent:Connect(function() end) end

print("╔════════════════════════════════════════╗")
print("║     WHAT IF ARENA - System Active      ║")
print("╠════════════════════════════════════════╣")
print("║  Server Type: " .. ServerType .. string.rep(" ", 24 - #ServerType) .. "║")
print("║  Press H to toggle UI                  ║")
print("║  Features:                             ║")
print("║    ⚡ Auto-Harpoon System              ║")
print("║    ✈️ AUTO-FLY (1300 SPEED)            ║")
print("║    🧱 WALL AVOIDANCE (Active)          ║")
print("║    📍 80 stud trigger distance         ║")
print("║    📏 Normal height (no glitch)        ║")
print("║    🛡️ AC Bypass Protection             ║")
print("╚════════════════════════════════════════╝")