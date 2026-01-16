--// Services
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- Data
---------------------------------------------------------------------

-- Root folder containing all shop categories (Gears, Pets, Modifiers, etc.)
local Items = ReplicatedStorage.Assets.ItemShop

-- Used to know which size tween to return to after a click
-- (prevents snapping to wrong size after mouse leave)
local isHovering = false

---------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------

-- Clears all item buttons except the template and layout objects
-- Used when switching shop sections
local function clearList(UI)
	for _, button in UI:GetChildren() do
		if button.Name ~= "Template"
			and not button:IsA("UIGridLayout")
			and not button:IsA("UIAspectRatioConstraint") then
			button:Destroy()
		end
	end
end

-- Clears old models, cameras, and tools from a ViewportFrame
-- Keeps WorldModel intact for pets
local function clearViewport(UI)
	for _, v in ipairs(UI:GetChildren()) do
		if (v:IsA("Model") or v:IsA("Camera") or v:IsA("Tool"))
			and v.Name ~= "WorldModel" then
			v:Destroy()
		end
	end
end

-- Ask the server to cache all gear models ahead of time
-- Prevents lag spikes when opening previews
local function invokeModels()
	for _, gear in ReplicatedStorage.Assets.ItemShop.Gears:GetChildren() do
		ReplicatedStorage.Source.Connectors.OneWay:FireServer(
			"MarketplaceModel",
			gear:GetAttribute("Viewport/ItemID")
		)
	end
end

-- Finds a cached viewport model by its ID
local function findModel(ID)
	return ReplicatedStorage.Assets.Cache:FindFirstChild(ID)
end

---------------------------------------------------------------------
-- Purchase Button
---------------------------------------------------------------------

-- Handles purchase button behavior on the left-side panel
local function purchaseButton(UI)
	UI.Purchase.MouseButton1Click:Connect(function()
		-- Ask server to process the purchase
		local resultText = ReplicatedStorage.Source.Connectors.TwoWay:InvokeServer(
			"PurchaseProcess",
			UI.ItemView:GetAttribute("CurrentItem"),
			UI.ItemView:GetAttribute("Price"),
			UI.Purchase,
			UI.ItemView:GetAttribute("Section")
		)

		-- Update button text based on server response
		UI.Purchase.Text = resultText

		-- Visual feedback if item is already owned
		if resultText == "Owned" then
			UI.Purchase.BackgroundColor3 = Color3.new(1, 1, 1)
		end
	end)
end

---------------------------------------------------------------------
-- Item Button Creation
---------------------------------------------------------------------

-- Creates a shop item button and handles preview + selection logic
local function newButton(Section, Template, Text, Font, Color, Viewport, Price, Decal, Data)
	local leftSide = Template.Parent.parent.LeftSide
	local button = Template:Clone()
	local Gear

	-----------------------------------------------------------------
	-- Preview setup (button viewport)
	-----------------------------------------------------------------
	if Viewport ~= false then
		-- Gear preview (numeric Viewport ID, non-pets)
		if typeof(Viewport) == "number" and tostring(Section) ~= "Pets" then
			button.Name = Viewport

			-- Clone cached gear model
			Gear = findModel(Viewport):Clone()
			Gear.Parent = button.ItemView
			Gear:PivotTo(CFrame.new())

			-- Setup viewport camera
			local handle = Gear:FindFirstChildOfClass("Tool").Handle
			local camera = Instance.new("Camera", button.ItemView)
			camera.FieldOfView += 5
			button.ItemView.CurrentCamera = camera

			-- Rotate model to face camera
			local cf, size = handle.Parent:GetBoundingBox()
			handle.Parent:PivotTo(cf * CFrame.Angles(0, math.pi, 0))

			-- Camera distance adjustment based on model size
			if size.Y >= 1.5 then
				local dist = math.max(size.X, size.Y, size.Z) * 0.75
				camera.CFrame = CFrame.new(cf.Position - cf.LookVector * dist, cf.Position)
			else
				camera.CFrame = CFrame.new(
					handle.Position + Vector3.new(0.5, 0.5, 0.5),
					handle.Position
				)
			end
		else
			-- Non-gear or fallback case
			button.Name = tostring(Viewport)
		end

		-- Pet preview (requires WorldModel)
		if tostring(Section) == "Pets" then
			button.Name = Text

			-- Clone pet model
			local pet = ReplicatedStorage.Assets.ItemShop.Pets:FindFirstChild(Text):Clone()
			local worldModel = button.ItemView:FindFirstChild("WorldModel")
				or Instance.new("WorldModel", button.ItemView)

			worldModel.Name = "WorldModel"
			worldModel:ClearAllChildren()
			pet.Parent = worldModel

			-- Ensure PrimaryPart is set
			pet.PrimaryPart = pet.PrimaryPart or pet:FindFirstChildWhichIsA("BasePart")
			pet:PivotTo(CFrame.new())

			-- Setup viewport camera
			local camera = Instance.new("Camera", button.ItemView)
			camera.FieldOfView += 5
			button.ItemView.CurrentCamera = camera

			-- Camera positioning based on pet size
			local cf, size = pet:GetBoundingBox()
			local dist = math.max(size.X, size.Y, size.Z)

			local camPos =
				cf.Position
				+ cf.LookVector * (dist * 0.8)
				+ cf.RightVector * (dist * 0.6)
				+ cf.UpVector * (dist * 0.3)

			camera.CFrame = CFrame.new(camPos, cf.Position)
		end
	else
		-- Items without viewport
		button.Name = Text
	end

	-----------------------------------------------------------------
	-- Visuals
	-----------------------------------------------------------------
	-- Optional decal icon
	if Decal then
		button.Decal.Image = "rbxassetid://" .. Decal
		button.Decal.Visible = true
	else
		button.Decal.Visible = false
	end

	-- Title styling
	if Font then button.Title.FontFace = Font end
	button.Title.Text = tostring(Text)
	if Color then button.Title.TextColor3 = Color end

	button.Parent = Template.Parent
	button.Visible = true

	-----------------------------------------------------------------
	-- Item selection logic
	-----------------------------------------------------------------
	button.MouseButton1Click:Connect(function()
		Price = tostring(Price)

		-- Update left-side info panel
		leftSide.ItemName.Text = button.Title.Text
		leftSide.ItemView:SetAttribute("CurrentItem", button.Name)
		leftSide.ItemView:SetAttribute("Price", tonumber((Price:gsub("%$", ""))))
		leftSide.ItemView:SetAttribute("Section", tostring(Section))

		leftSide.ItemName.TextColor3 = Color or Color3.new(1, 1, 1)

		-- Check ownership from server
		local owned = ReplicatedStorage.Source.Connectors.TwoWay:InvokeServer(
			"CheckOwned",
			button.Name,
			Section
		)

		-- Price and purchase button handling
		if Price == "Unavailable" or Price == "$Unavailable" then
			leftSide.Purchase.Visible = false
			leftSide.Price.Text = "Unavailable"
		else
			leftSide.Purchase.Visible = true
			leftSide.Price.Text = "$" .. Price:gsub("%$", "")
		end

		-- Modifier-specific behavior
		if tostring(Section) == "Modifiers" then
			task.wait()
			if owned ~= nil then
				leftSide.Purchase.Text = "Activated"
				leftSide.Purchase.BackgroundColor3 = Color3.new(1, 1, 1)
			else
				leftSide.Purchase.Text = "Purchase"
				leftSide.Purchase.BackgroundColor3 = Color3.new(0.588, 1, 0.556)
			end
		else
			-- Standard items
			if owned then
				leftSide.Purchase.Text = "Owned"
				leftSide.Purchase.BackgroundColor3 = Color3.new(1, 1, 1)
			else
				leftSide.Purchase.Text = "Purchase"
				leftSide.Purchase.BackgroundColor3 = Color3.new(0.588, 1, 0.556)
			end
		end

		-----------------------------------------------------------------
		-- Left-side preview
		-----------------------------------------------------------------
		clearViewport(leftSide.ItemView)

		if Viewport ~= false then
			local lookAt

			-- Pet preview
			if tostring(Section) == "Pets" then
				local pet = ReplicatedStorage.Assets.ItemShop.Pets:FindFirstChild(button.Name):Clone()
				pet.Parent = leftSide.ItemView
				lookAt = pet.PrimaryPart or pet.Head

			-- Gear preview
			elseif typeof(Viewport) == "number" then
				Gear = findModel(Viewport):Clone()
				Gear.Parent = leftSide.ItemView
				Gear:PivotTo(CFrame.new())
				lookAt = Gear:FindFirstChildOfClass("Tool").Handle
			end

			-- Setup camera if a target exists
			if lookAt then
				local camera = Instance.new("Camera", leftSide.ItemView)
				camera.FieldOfView += 5
				leftSide.ItemView.CurrentCamera = camera

				local cf, size = lookAt.Parent:GetBoundingBox()
				lookAt.Parent:PivotTo(cf * CFrame.Angles(0, math.pi, 0))

				if size.Y >= 1.5 then
					local dist = math.max(size.X, size.Y, size.Z)
					camera.CFrame = CFrame.new(cf.Position - cf.LookVector * dist, cf.Position)
				else
					camera.CFrame = CFrame.new(
						lookAt.Position + Vector3.new(1, 0.5, 1),
						lookAt.Position
					)
				end
			end
		end
	end)

	return button
end

---------------------------------------------------------------------
-- Section Buttons (All, Gears, Pets, etc.)
---------------------------------------------------------------------

-- Handles section switching and item population
local function SectionButtons(UI, Data)
	for _, Button in UI:GetChildren() do
		if not (Button:IsA("ImageButton") or Button:IsA("TextButton")) then
			continue
		end

		-- Button animations
		local tweenClick = TweenService:Create(Button, TweenInfo.new(0.1), {
			Size = UDim2.new(1.271, 0, 0.146, 0)
		})
		local tweenHover = TweenService:Create(Button, TweenInfo.new(0.25), {
			Size = UDim2.new(1.142, 0, 0.134, 0)
		})
		local tweenLeave = TweenService:Create(Button, TweenInfo.new(0.25), {
			Size = UDim2.new(1, 0, 0.116, 0)
		})

		Button.MouseEnter:Connect(function()
			isHovering = true
			tweenHover:Play()
		end)

		Button.MouseLeave:Connect(function()
			isHovering = false
			tweenLeave:Play()
		end)

		Button.MouseButton1Down:Connect(function()
			-- Clear current item list
			clearList(UI.Parent.ScrollingFrame)

			-- "All" section shows everything
			if Button.Name == "All" then
				for _, section in Items:GetChildren() do
					for _, item in section:GetChildren() do
						newButton(
							section,
							UI.Parent.ScrollingFrame.Template,
							item.Name,
							item:GetAttribute("Font"),
							item:GetAttribute("Color"),
							item:GetAttribute("Viewport/ItemID") or false,
							item:GetAttribute("Price") or "Unavailable",
							item:GetAttribute("DecalID"),
							Data
						)
					end
				end
			else
				-- Single category
				local section = Items:FindFirstChild(Button.Name)
				if section then
					for _, item in section:GetChildren() do
						newButton(
							section,
							UI.Parent.ScrollingFrame.Template,
							item.Name,
							item:GetAttribute("Font"),
							item:GetAttribute("Color"),
							item:GetAttribute("Viewport/ItemID") or false,
							item:GetAttribute("Price") or "Unavailable",
							item:GetAttribute("DecalID"),
							Data
						)
					end
				end
			end

			-- Click animation logic
			tweenClick:Play()
			tweenClick.Completed:Once(function()
				if isHovering then
					tweenHover:Play()
				else
					tweenLeave:Play()
				end
			end)
		end)
	end
end

---------------------------------------------------------------------
-- Entry Point
---------------------------------------------------------------------

-- Initializes the shop UI
return function(Data, UI)
	UI = UI.Shop
	invokeModels()                    -- Preload gear models
	SectionButtons(UI.Sections, Data) -- Setup section buttons
	purchaseButton(UI.LeftSide)       -- Setup purchase button
end
