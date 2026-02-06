local SettingsClient = {}

-------------------// SERVICES \\--------------------

local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local TS = game:GetService("TweenService")
local SS = game:GetService("SoundService")
local Players = game:GetService("Players")

-------------------// MODULES \\---------------------

local Utilities = require(RS.Shared.Utilities.GeneralUtilities)
local InstanceObserver = require(RS.Shared.InstanceObserver)
local UIButtonBinder = require(RS.Shared.UI.UIButtonBinder)
local InputSystem = require(RS.Shared.Input.InputSystem)
local UIAnimator = require(RS.Shared.UI.UIAnimator)
local TopbarPlus = require(RS.Packages.TopbarIcon)
local UIManager = require(RS.Shared.UI.UIManager)
local Bridges = require(RS.Shared.Bridges)
local Trove = require(RS.Packages.Trove)

-------------------// SIGNALS \\---------------------

local Signals = RS:WaitForChild("Signals")
local Functions = Signals:WaitForChild("Functions")

-------------------// PLAYER \\----------------------

local player = Players.LocalPlayer

---------------------// UI \\------------------------

local PlayerGui = player:WaitForChild("PlayerGui")
local FramesGui: ScreenGui = PlayerGui:WaitForChild("Frames")
local ButtonsGui: ScreenGui = PlayerGui:WaitForChild("Buttons")

local SettingsFrame: Frame = nil
local Scrolling: ScrollingFrame = nil
local PageButtonsScrolling: ScrollingFrame = nil

local settingsIcon = nil

-----------------// REFERENCES \\--------------------

--// Sound groups
local MusicGroup = SS:FindFirstChild("Music")
local SFXGroup = SS:FindFirstChild("SFX")
local AmbientGroup = SS:FindFirstChild("Ambient")
local UIGroup = SS:FindFirstChild("UI")

--// Constants
local CONTENT_CANVAS_POS = {
	Audio = Vector2.new(0, 0),
	Gameplay = Vector2.new(0, 335),
	Accessibility = Vector2.new(0, 605),
	Graphics = Vector2.new(0, 870),
	Interface = Vector2.new(0, 1284.07),
	Notifications = Vector2.new(0, 1544.07),
	Other = Vector2.new(0, 2194.07),
	Keybinds = Vector2.new(0, 1755)
}

--// Variables
local tr = Trove.new()
local playerData = nil

local pageButtons: {[string]: ImageButton} = {}
local scrollTween: Tween? = nil

----------------// PRIV. FUNCTIONS \\----------------

local function calculateSliderValue(grabber: Frame, alpha: number)
	if grabber.Parent.Parent.Name == "UIScale" then
		-- Maps 0.0 -> 1.0 to 50 -> 150
		return math.floor(50 + (alpha * 100))
	end
	return math.floor(alpha * 100)
end

local function updateAudioVolume(settingName: string, percent: number)
	local volume = percent / 100

	if settingName == "MasterVolume" then
		if MusicGroup then MusicGroup.Volume = volume end
		if SFXGroup then SFXGroup.Volume = volume end
		if AmbientGroup then AmbientGroup.Volume = volume end
		if UIGroup then UIGroup.Volume = volume end
	elseif settingName == "MusicVolume" and MusicGroup then
		MusicGroup.Volume = volume
	elseif settingName == "SFXVolume" and SFXGroup then
		SFXGroup.Volume = volume
	elseif settingName == "AmbientVolume" and AmbientGroup then
		AmbientGroup.Volume = volume
	elseif settingName == "UIVolume" and UIGroup then
		UIGroup.Volume = volume
	end
end

local function captureSlider(grabber: Frame)
	local detector: UIDragDetector = grabber:FindFirstChildOfClass("UIDragDetector")
	if not detector then return end

	local parentFrame = grabber.Parent.Parent
	local valueLabel: TextLabel = parentFrame:FindFirstChild("Value")
	local bar = grabber.Parent

	local function update()
		-- Combine Scale and Offset to get true alpha relative to the bar
		local alpha = math.clamp(grabber.Position.X.Scale + (grabber.Position.X.Offset / bar.AbsoluteSize.X), 0, 1)
		local percent = calculateSliderValue(grabber, alpha)

		if valueLabel then valueLabel.Text = tostring(percent) end
		updateAudioVolume(parentFrame.Name, percent)
		return percent
	end

	-- Real-time updates while dragging
	tr:Connect(detector.DragContinue, function()
		update()
	end)

	-- Save to server only when let go
	tr:Connect(detector.DragEnd, function()
		local percent = update()

		Bridges.SettingChanged:Fire({
			settingName = parentFrame.Name,
			state = nil,
			value = percent,
		})
	end)
end

local function animateStatusSlide(button: TextButton)
	if not button or not button:IsA("TextButton") then return end

	local parentFrame: Frame = button.Parent
	local statusLabel: TextLabel = parentFrame.Status

	local middlePos: UDim2 = UDim2.new(0.842, 0, 0.5, 0)
	local leftEndPos: UDim2 = UDim2.new(0.784, 0, 0.5, 0)
	local rightEndPos: UDim2 = UDim2.new(0.903, 0, 0.5, 0)

	local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	if button.Name == "LeftArrow" then
		local slideOut = TS:Create(statusLabel, tweenInfo, {Position = leftEndPos})
		tr:Add(slideOut)
		slideOut:Play()
		slideOut.Completed:Wait()

		statusLabel.Visible = false
		statusLabel.Position = rightEndPos
		statusLabel.Visible = true

		local slideIn = TS:Create(statusLabel, tweenInfo, {Position = middlePos})
		tr:Add(slideIn)
		slideIn:Play()

	elseif button.Name == "RightArrow" then
		local slideOut = TS:Create(statusLabel, tweenInfo, {Position = rightEndPos})
		tr:Add(slideOut)
		slideOut:Play()
		slideOut.Completed:Wait()

		statusLabel.Visible = false
		statusLabel.Position = leftEndPos
		statusLabel.Visible = true

		local slideIn = TS:Create(statusLabel, tweenInfo, {Position = middlePos})
		tr:Add(slideIn)
		slideIn:Play()
	end

	statusLabel.Text = if statusLabel.Text == "On" then "Off" else "On"

	local newState = (statusLabel.Text == "On")
	player:SetAttribute(parentFrame.Name, newState)

	Bridges.SettingChanged:Fire({
		settingName = parentFrame.Name,
		state = if statusLabel.Text == "On" then true else false,
		value = nil,
	})
end

local function captureToggleButtons(button: TextButton)
	tr:Connect(button.Activated, function()
		animateStatusSlide(button)
	end)
end

local function setStrokeSelected(selectedName: string)
	for i, btn in pairs(pageButtons) do		
		local onStroke: UIStroke = btn:FindFirstChild("StrokeOn")
		local offStroke: UIStroke = btn:FindFirstChild("StrokeOff")
		if not onStroke or not offStroke then continue end

		onStroke.Enabled = btn.Name == selectedName
		offStroke.Enabled = not (btn.Name == selectedName)
	end
end

local function goToPage(pageName: string)
	local contentPos = CONTENT_CANVAS_POS[pageName]

	if contentPos and Scrolling then
		if scrollTween then
			scrollTween:Cancel()
			scrollTween:Destroy()
			scrollTween = nil
		end

		scrollTween = TS:Create(
			Scrolling,
			TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{CanvasPosition = contentPos}
		)
		tr:Add(scrollTween)
		scrollTween:Play()
	end

	setStrokeSelected(pageName)
end

local function hookPageButtons()
	for _, btn: ImageButton in PageButtonsScrolling:GetChildren() do
		if not btn:IsA("ImageButton") then continue end

		pageButtons[btn.Name] = btn
		tr:Connect(btn.Activated, function()
			goToPage(btn.Name)
		end)
	end
end

local function updateSettingsStatus()
	if not playerData then
		repeat
			playerData = Functions.RequestData:InvokeServer()
			task.wait(0.1)
		until playerData or not player.Parent	
	end

	task.spawn(function()
		for settingName, state in pairs(playerData.PlayerSettings) do
			task.spawn(function()
				if typeof(state) == "table" then return end
				player:SetAttribute(settingName, state)

				local frame: Frame = Scrolling:FindFirstChild(settingName)
				if not frame then return end

				if typeof(state) == "boolean" then
					frame:SetAttribute("State", state)
					frame.Status.Text = if state then "On" else "Off"
				elseif typeof(state) == "number" then
					frame:SetAttribute("SettingValue", state)

					local grabber = frame:FindFirstChild("Grabber", true)
					if grabber then
						local alpha = 0
						if frame.Name == "UIScale" then
							-- Reverse mapping: (value - min) / range
							alpha = math.clamp((state - 50) / 100, 0, 1)
						else
							alpha = state / 100
						end
						grabber.Position = UDim2.fromScale(alpha, 0.5)
						if frame:FindFirstChild("Value") then frame.Value.Text = tostring(state) end
						updateAudioVolume(frame.Name, state)
					end
				end
			end)
		end
	end)
end

------------------// LIFECYCLE \\--------------------

function SettingsClient.init()

	------------------// UI \\--------------------

	SettingsFrame = UIManager.Get("Frames.Settings")
	Scrolling = UIManager.Get("Scrolling", SettingsFrame)
	PageButtonsScrolling = UIManager.Get("PageButtonsScrolling", SettingsFrame)

	--------------// TOPBAR BUTTON \\-------------

	settingsIcon = TopbarPlus.new()
		:setImage("rbxassetid://102290219889575")
		:setCaption("Settings")
		:align("Right")

	UIButtonBinder.RegisterIcon(settingsIcon, SettingsFrame)

	--------------// CONNECTIONS \\---------------

	-- Left toggle buttons
	for _, button: TextButton in CS:GetTagged("LeftToggleArrow") do captureToggleButtons(button) end
	tr:Connect(CS:GetInstanceAddedSignal("LeftToggleArrow"), captureToggleButtons)

	-- Right toggle buttons
	for _, button: TextButton in CS:GetTagged("RightToggleArrow") do captureToggleButtons(button) end
	tr:Connect(CS:GetInstanceAddedSignal("RightToggleArrow"), captureToggleButtons)

	-- Slider grabbers
	for _, grabber: Frame in CS:GetTagged("SettingUISlider") do captureSlider(grabber) end
	tr:Connect(CS:GetInstanceAddedSignal("SettingUISlider"), captureSlider)

	---------------// SIGNALS \\------------------

	-- Data loaded for the local player
	InstanceObserver.ObserveAttribute(player, "DataLoaded", function()
		playerData = Functions.RequestData:InvokeServer()
	end)
end

function SettingsClient.SetupPlayer()
	hookPageButtons()
	updateSettingsStatus()
	goToPage("Audio")
end

function SettingsClient.CleanupPlayer()
	tr:Destroy()	
end

------------------// FUNCTIONS \\--------------------

return SettingsClient
