--!strict
-- Pixel-style UI widget toolkit. Every builder takes a props table; unknown props are applied
-- directly to the created instance (so you can pass Name, Position, LayoutOrder, ZIndex, ...).

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local RarityData = require(Shared:WaitForChild("RarityData"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local PixelUI = {}

export type Props = { [string]: any }

-- Hook for a click sound; set by the Sounds module.
PixelUI.OnClickSound = nil :: (() -> ())?

local function applyProps(inst: Instance, props: Props?, skip: { [string]: boolean })
	if not props then
		return
	end
	for key, value in pairs(props) do
		if not skip[key] then
			(inst :: any)[key] = value
		end
	end
end

function PixelUI.FormatNumber(n: number): string
	return Util.FormatNumber(n)
end

function PixelUI.FormatWeight(kg: number): string
	return Util.FormatWeight(kg)
end

function PixelUI.RarityColor(rarity: string): Color3
	return RarityData.Color(rarity)
end

function PixelUI.Tween(inst: Instance, goal: { [string]: any }, time: number?, style: Enum.EasingStyle?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time or 0.15, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- ---------------------------------------------------------------- layout helpers

function PixelUI.Stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Color = color or Theme.Colors.Border
	stroke.Thickness = thickness or Theme.Border
	stroke.Parent = parent
	return stroke
end

function PixelUI.Padding(parent: GuiObject, px: number, py: number?): UIPadding
	local pad = Instance.new("UIPadding")
	local y = py or px
	pad.PaddingLeft = UDim.new(0, px)
	pad.PaddingRight = UDim.new(0, px)
	pad.PaddingTop = UDim.new(0, y)
	pad.PaddingBottom = UDim.new(0, y)
	pad.Parent = parent
	return pad
end

function PixelUI.List(parent: GuiObject, direction: Enum.FillDirection?, gap: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, gap or 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = vAlign or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

function PixelUI.Grid(parent: GuiObject, cellSize: UDim2, gap: number?): UIGridLayout
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = cellSize
	grid.CellPadding = UDim2.fromOffset(gap or 6, gap or 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = parent
	return grid
end

-- Keeps the whole UI readable on phones and 4K monitors alike.
function PixelUI.Scale(gui: ScreenGui): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function update()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		local s = math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.62, 1.3)
		scale.Scale = s
	end
	update()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

-- ---------------------------------------------------------------- widgets

local FRAME_SKIP = { Border = true, BorderColor = true, Thickness = true, Color = true, Parent = true }
-- props: Color, Border (boolean), BorderColor, Thickness, + any Frame property
function PixelUI.Frame(props: Props): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = props.Color or Theme.Colors.Panel
	frame.Size = props.Size or UDim2.fromScale(1, 1)
	applyProps(frame, props, FRAME_SKIP)
	if props.Border then
		PixelUI.Stroke(frame, props.BorderColor, props.Thickness)
	end
	frame.Parent = props.Parent
	return frame
end

-- A bordered panel with a hard pixel drop shadow. Returns (holder, body): position the holder, parent children to the body.
function PixelUI.Panel(props: Props): (Frame, Frame)
	local holder = Instance.new("Frame")
	holder.Name = props.Name or "Panel"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = props.Size or UDim2.fromOffset(200, 100)
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.new()
	holder.ZIndex = props.ZIndex or 1
	holder.LayoutOrder = props.LayoutOrder or 0
	holder.Visible = props.Visible ~= false

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Theme.Colors.Shadow
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.fromOffset(Theme.Shadow, Theme.Shadow)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.ZIndex = 1
	shadow.Parent = holder

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = props.Color or Theme.Colors.Panel
	body.BorderSizePixel = 0
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 2
	body.Parent = holder
	PixelUI.Stroke(body, props.BorderColor, props.Thickness)

	holder.Parent = props.Parent
	return holder, body
end

local LABEL_SKIP = { Color = true, Wrap = true, XAlign = true, YAlign = true, Rich = true, Outline = true, Parent = true }
-- props: Text, TextSize, Color, XAlign, YAlign, Wrap, Rich, Outline, + any TextLabel property
function PixelUI.Label(props: Props): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Theme.Font
	label.TextColor3 = props.Color or Theme.Colors.Text
	label.TextSize = props.TextSize or Theme.TextSizes.Body
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	label.TextYAlignment = props.YAlign or Enum.TextYAlignment.Center
	label.TextWrapped = props.Wrap == true
	label.RichText = props.Rich == true
	label.TextStrokeTransparency = if props.Outline then 0 else 1
	label.TextStrokeColor3 = Theme.Colors.Border
	label.Size = props.Size or UDim2.new(1, 0, 0, 20)
	label.Text = props.Text or ""
	applyProps(label, props, LABEL_SKIP)
	label.Parent = props.Parent
	return label
end

local BUTTON_SKIP = { Color = true, TextColor = true, OnClick = true, Disabled = true, Parent = true }
-- props: Text, Color, TextColor, TextSize, OnClick(button), Disabled, + any TextButton property.
-- Toggle later with button:SetAttribute("Disabled", bool) or button:SetAttribute("BaseColor", Color3).
function PixelUI.Button(props: Props): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = Theme.Font
	button.TextSize = props.TextSize or Theme.TextSizes.Body
	button.Text = props.Text or "Button"
	button.Size = props.Size or UDim2.fromOffset(120, 36)
	button.Selectable = true
	applyProps(button, props, BUTTON_SKIP)
	PixelUI.Stroke(button)

	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.BorderSizePixel = 0
	edge.AnchorPoint = Vector2.new(0, 1)
	edge.Position = UDim2.fromScale(0, 1)
	edge.Size = UDim2.new(1, 0, 0, 4)
	edge.ZIndex = button.ZIndex + 1
	edge.Parent = button

	button:SetAttribute("BaseColor", props.Color or Theme.Colors.Button)
	button:SetAttribute("TextBase", props.TextColor or Theme.Colors.ButtonText)
	button:SetAttribute("Disabled", props.Disabled == true)

	local hovering, pressing = false, false
	local function refresh()
		local base = button:GetAttribute("BaseColor") :: Color3
		local textBase = button:GetAttribute("TextBase") :: Color3
		local disabled = button:GetAttribute("Disabled") == true
		edge.BackgroundColor3 = Util.Darken(base, 0.4)
		if disabled then
			button.BackgroundColor3 = Theme.Colors.ButtonDisabled
			button.TextColor3 = Theme.Colors.TextMuted
			edge.Visible = false
		elseif pressing then
			button.BackgroundColor3 = Util.Darken(base, 0.2)
			button.TextColor3 = textBase
			edge.Visible = false
		elseif hovering then
			button.BackgroundColor3 = Util.Lighten(base, 0.18)
			button.TextColor3 = textBase
			edge.Visible = true
		else
			button.BackgroundColor3 = base
			button.TextColor3 = textBase
			edge.Visible = true
		end
	end
	refresh()

	button.MouseEnter:Connect(function() hovering = true; refresh() end)
	button.MouseLeave:Connect(function() hovering = false; pressing = false; refresh() end)
	button.MouseButton1Down:Connect(function() pressing = true; refresh() end)
	button.MouseButton1Up:Connect(function() pressing = false; refresh() end)
	button.SelectionGained:Connect(function() hovering = true; refresh() end)
	button.SelectionLost:Connect(function() hovering = false; pressing = false; refresh() end)
	button:GetAttributeChangedSignal("Disabled"):Connect(refresh)
	button:GetAttributeChangedSignal("BaseColor"):Connect(refresh)
	button:GetAttributeChangedSignal("TextBase"):Connect(refresh)
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") == true then
			return
		end
		if PixelUI.OnClickSound then
			PixelUI.OnClickSound()
		end
		if props.OnClick then
			props.OnClick(button)
		end
	end)
	button.Parent = props.Parent
	return button
end

export type ProgressBar = { Frame: Frame, Fill: Frame, Label: TextLabel, Set: (value: number, animate: boolean?) -> () }
-- props: Size, Position, AnchorPoint, Color (fill), BgColor, Value (0..1), Text, TextSize, + Frame props
function PixelUI.ProgressBar(props: Props): ProgressBar
	local frame = PixelUI.Frame({
		Name = props.Name or "ProgressBar",
		Parent = props.Parent,
		Size = props.Size or UDim2.new(1, 0, 0, 16),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Color = props.BgColor or Theme.Colors.PanelDark,
		Border = true,
	})
	local fill = PixelUI.Frame({
		Name = "Fill",
		Parent = frame,
		Size = UDim2.fromScale(math.clamp(props.Value or 0, 0, 1), 1),
		Color = props.Color or Theme.Colors.Accent2,
		ZIndex = frame.ZIndex + 1,
	})
	local label = PixelUI.Label({
		Name = "Label",
		Parent = frame,
		Size = UDim2.fromScale(1, 1),
		Text = props.Text or "",
		TextSize = props.TextSize or Theme.TextSizes.Small,
		XAlign = Enum.TextXAlignment.Center,
		Outline = true,
		ZIndex = frame.ZIndex + 2,
	})
	local bar: ProgressBar = {
		Frame = frame,
		Fill = fill,
		Label = label,
		Set = function(value: number, animate: boolean?)
			local goal = UDim2.fromScale(math.clamp(value, 0, 1), 1)
			if animate then
				PixelUI.Tween(fill, { Size = goal }, 0.25)
			else
				fill.Size = goal
			end
		end,
	}
	return bar
end

export type Window = {
	Root: Frame,
	Body: Frame,
	Content: Frame,
	Title: TextLabel,
	CloseButton: TextButton,
	SetOpen: (open: boolean) -> (),
}
-- props: Parent, Title, Size (UDim2), OnClose()
function PixelUI.Window(props: Props): Window
	local holder, body = PixelUI.Panel({
		Name = props.Name or "Window",
		Parent = props.Parent,
		Size = props.Size or UDim2.fromOffset(640, 420),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 20,
	})

	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local titleBar = PixelUI.Frame({
		Name = "TitleBar",
		Parent = body,
		Size = UDim2.new(1, 0, 0, 40),
		Color = Theme.Colors.PanelDark,
		ZIndex = 3,
	})
	local title = PixelUI.Label({
		Name = "Title",
		Parent = titleBar,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Text = props.Title or "",
		TextSize = Theme.TextSizes.Title,
		Color = Theme.Colors.Accent,
		ZIndex = 4,
	})
	local closeButton = PixelUI.Button({
		Name = "Close",
		Parent = titleBar,
		Text = "X",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -6, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = Theme.Colors.ButtonDanger,
		TextColor = Theme.Colors.Text,
		ZIndex = 4,
		OnClick = function()
			if props.OnClose then
				props.OnClose()
			end
		end,
	})
	local content = PixelUI.Frame({
		Name = "Content",
		Parent = body,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	PixelUI.Padding(content, 10)

	local window: Window = {
		Root = holder,
		Body = body,
		Content = content,
		Title = title,
		CloseButton = closeButton,
		SetOpen = function(open: boolean)
			if open then
				holder.Visible = true
				scale.Scale = 0.92
				PixelUI.Tween(scale, { Scale = 1 }, 0.12, Enum.EasingStyle.Back)
			else
				holder.Visible = false
			end
		end,
	}
	return window
end

-- A vertical scrolling container with AutomaticCanvasSize.
function PixelUI.Scroll(props: Props): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Theme.Colors.Accent2
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Size = props.Size or UDim2.fromScale(1, 1)
	scroll.Selectable = false
	applyProps(scroll, props, { Parent = true })
	scroll.Parent = props.Parent
	return scroll
end

export type Tabs = { Frame: Frame, Buttons: { [string]: TextButton }, Select: (id: string) -> (), Selected: () -> string? }
-- props: Parent, Tabs = { {id=, text=}, ... }, OnSelect(id), Size, Position
function PixelUI.Tabs(props: Props): Tabs
	local frame = PixelUI.Frame({
		Name = "Tabs",
		Parent = props.Parent,
		Size = props.Size or UDim2.new(1, 0, 0, 34),
		Position = props.Position,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
	})
	PixelUI.List(frame, Enum.FillDirection.Horizontal, 6)

	local buttons: { [string]: TextButton } = {}
	local selected: string? = nil
	local tabs: Tabs
	local function selectTab(id: string)
		selected = id
		for tabId, button in pairs(buttons) do
			button:SetAttribute("BaseColor", if tabId == id then Theme.Colors.Accent else Theme.Colors.ButtonSecondary)
			button:SetAttribute("TextBase", if tabId == id then Theme.Colors.TextDark else Theme.Colors.ButtonSecondaryText)
		end
		if props.OnSelect then
			props.OnSelect(id)
		end
	end
	for index, tab in ipairs(props.Tabs) do
		buttons[tab.id] = PixelUI.Button({
			Parent = frame,
			Text = tab.text,
			Size = UDim2.fromOffset(tab.width or 120, 30),
			LayoutOrder = index,
			Color = Theme.Colors.ButtonSecondary,
			TextColor = Theme.Colors.ButtonSecondaryText,
			OnClick = function()
				selectTab(tab.id)
			end,
		})
	end
	tabs = {
		Frame = frame,
		Buttons = buttons,
		Select = selectTab,
		Selected = function()
			return selected
		end,
	}
	return tabs
end

-- Small coloured tag, e.g. a rarity badge.
function PixelUI.Tag(props: Props): TextLabel
	local label = PixelUI.Label({
		Parent = props.Parent,
		Text = props.Text or "",
		TextSize = props.TextSize or Theme.TextSizes.Tiny,
		Color = props.TextColor or Theme.Colors.TextDark,
		XAlign = Enum.TextXAlignment.Center,
		Size = props.Size or UDim2.fromOffset(90, 18),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
	})
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = props.Color or Theme.Colors.Accent
	PixelUI.Stroke(label, nil, 2)
	return label
end

-- "Label ............ value" row used in stat panels.
function PixelUI.StatRow(parent: GuiObject, name: string, value: string, layoutOrder: number?, valueColor: Color3?): (TextLabel, TextLabel)
	local row = PixelUI.Frame({
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder or 0,
	})
	local nameLabel = PixelUI.Label({ Parent = row, Text = name, Size = UDim2.fromScale(0.55, 1), Color = Theme.Colors.TextMuted, TextSize = Theme.TextSizes.Small })
	local valueLabel = PixelUI.Label({
		Parent = row,
		Text = value,
		Size = UDim2.fromScale(0.45, 1),
		Position = UDim2.fromScale(0.55, 0),
		XAlign = Enum.TextXAlignment.Right,
		Color = valueColor or Theme.Colors.Text,
		TextSize = Theme.TextSizes.Small,
	})
	return nameLabel, valueLabel
end

function PixelUI.Divider(parent: GuiObject, layoutOrder: number?): Frame
	return PixelUI.Frame({
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 3),
		Color = Theme.Colors.Border,
		LayoutOrder = layoutOrder or 0,
	})
end

return PixelUI
