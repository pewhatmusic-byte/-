--!strict
-- Fish Book: every species with its discovery state, filterable by location, plus a detail panel
-- that doubles as a hunting guide (locations and conditions are shown for undiscovered fish too).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local FishData = require(Shared:WaitForChild("FishData"))
local LocationData = require(Shared:WaitForChild("LocationData"))
local RarityData = require(Shared:WaitForChild("RarityData"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))

local Colors = Theme.Colors
local Sizes = Theme.TextSizes
local AtEnd = Enum.TextTruncate.AtEnd

type Ctx = {
	Gui: ScreenGui,
	State: typeof(require(script.Parent.Parent:WaitForChild("ClientState"))),
	Net: typeof(require(Shared:WaitForChild("Net"))),
	Windows: { Open: (name: string, payload: any?) -> (), Close: (name: string) -> (), CloseAll: () -> (), IsOpen: (name: string) -> boolean },
	Sounds: { Play: (name: string) -> () },
	Notify: (kind: string, text: string) -> (),
}

local Window = {}
Window.Name = "Bestiary"

local WINDOW_SIZE = UDim2.fromOffset(760, 480)
local CARD_SIZE = UDim2.fromOffset(96, 78)
local FILTER_WIDTH = 150
local GRID_X, GRID_WIDTH = 158, 330
local DETAIL_X = 496
local ALL_WATERS = "all"

local TIME_TEXT: { [string]: string } = { Any = "Any time", Day = "Day only", Night = "Night only" }
local WEATHER_TEXT: { [string]: string } = { Any = "Any weather", Clear = "Clear skies", Rain = "Rain or storm", Storm = "Storms only" }

-- The species list never changes at runtime.
local SORTED = FishData.Sorted()

local ctx: Ctx = nil :: any
local win: PixelUI.Window = nil :: any
local initialized = false
local isOpen = false
local stale = true
local flushQueued = false

local selectedFilter = ALL_WATERS
local selectedFish: string? = nil
local progressLabel: TextLabel = nil :: any
local progressBar: PixelUI.ProgressBar = nil :: any
local gridScroll: ScrollingFrame = nil :: any
local detailBody: Frame = nil :: any
local filterButtons: { [string]: TextButton } = {}
local cards: { [string]: TextButton } = {}

-- ---------------------------------------------------------------- helpers

local function clearChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

local function entryFor(id: string): Types.BestiaryEntry?
	local profile = ctx.State.Profile
	return if profile then profile.bestiary[id] else nil
end

-- "Label value" with a muted label, wrapped to the panel width.
local function infoLine(parent: GuiObject, order: number, label: string, value: string, valueColor: Color3?)
	PixelUI.Label({
		Parent = parent,
		Text = string.format(
			'<font color="#%s">%s</font> <font color="#%s">%s</font>',
			Colors.TextMuted:ToHex(),
			label,
			(valueColor or Colors.Text):ToHex(),
			value
		),
		TextSize = Sizes.Small,
		Rich = true,
		Wrap = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = order,
	})
end

-- ---------------------------------------------------------------- detail panel

local function renderDetail()
	clearChildren(detailBody)

	local def = if selectedFish then FishData.Get(selectedFish) else nil
	if not def then
		PixelUI.Label({
			Parent = detailBody,
			Size = UDim2.fromScale(1, 1),
			Text = "Pick a fish to read its entry.",
			Color = Colors.TextMuted,
			XAlign = Enum.TextXAlignment.Center,
			Wrap = true,
		})
		return
	end

	local entry = entryFor(def.id)
	local discovered = entry ~= nil
	local rarityColor = RarityData.Color(def.rarity)

	local info = PixelUI.Scroll({ Name = "Info", Parent = detailBody, ScrollBarThickness = 4 })
	PixelUI.List(info, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)

	local iconHolder = PixelUI.Frame({ Parent = info, Size = UDim2.new(1, 0, 0, 84), BackgroundTransparency = 1, LayoutOrder = 1 })
	PixelIcon.Render(iconHolder, def, {
		silhouette = not discovered,
		Size = UDim2.fromOffset(120, 80),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	PixelUI.Label({
		Parent = info,
		Text = if discovered then def.name else "???",
		TextSize = Sizes.Title,
		Color = if discovered then rarityColor else Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		Wrap = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
	})
	PixelUI.Tag({ Parent = info, Text = string.upper(def.rarity), Color = rarityColor, LayoutOrder = 3 })
	PixelUI.Label({
		Parent = info,
		Text = if discovered then def.description else "Catch one to learn its story.",
		TextSize = Sizes.Small,
		Color = if discovered then Colors.Text else Colors.TextMuted,
		Wrap = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 4,
	})
	PixelUI.Divider(info, 5)

	infoLine(info, 6, "Weight:", PixelUI.FormatWeight(def.minWeight) .. " - " .. PixelUI.FormatWeight(def.maxWeight))
	infoLine(info, 7, "Base value:", PixelUI.FormatNumber(def.baseValue) .. " c", Colors.Coins)
	local places: { string } = {}
	for _, locationId in ipairs(def.locations) do
		table.insert(places, LocationData.Name(locationId))
	end
	infoLine(info, 8, "Found in:", table.concat(places, ", "), Colors.Accent2)
	infoLine(info, 9, "Time:", TIME_TEXT[def.time] or "Any time")
	infoLine(info, 10, "Weather:", WEATHER_TEXT[def.weather] or "Any weather")

	if entry then
		PixelUI.Divider(info, 11)
		infoLine(info, 12, "Caught:", PixelUI.FormatNumber(entry.count))
		infoLine(info, 13, "Best:", PixelUI.FormatWeight(entry.bestWeight))
		infoLine(info, 14, "Shiny caught:", if entry.shiny then "Yes" else "No", if entry.shiny then Colors.Accent else nil)
	end
end

-- ---------------------------------------------------------------- grid

local function styleCard(id: string, selected: boolean)
	local card = cards[id]
	if not card then
		return
	end
	local base = if selected then Colors.PanelLight elseif entryFor(id) then Colors.Panel else Colors.PanelDark
	card:SetAttribute("BaseColor", base)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = if selected then 4 else 2
	end
end

local function selectFish(id: string)
	if selectedFish == id then
		return
	end
	local previous = selectedFish
	selectedFish = id
	if previous then
		styleCard(previous, false)
	end
	styleCard(id, true)
	renderDetail()
end

local function buildCard(parent: GuiObject, def: Types.FishDef, entry: Types.BestiaryEntry?, order: number): TextButton
	local discovered = entry ~= nil
	local rarityColor = RarityData.Color(def.rarity)
	local card = PixelUI.Button({
		Name = def.id,
		Parent = parent,
		Text = "",
		Size = CARD_SIZE,
		Color = if discovered then Colors.Panel else Colors.PanelDark,
		LayoutOrder = order,
		OnClick = function()
			selectFish(def.id)
		end,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarityColor
		stroke.Thickness = 2
	end

	PixelIcon.Render(card, def, {
		silhouette = not discovered,
		Size = UDim2.fromOffset(66, 44),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
	})
	PixelUI.Label({
		Parent = card,
		Text = if discovered then def.name else "???",
		Position = UDim2.fromOffset(4, 54),
		Size = UDim2.new(1, -8, 0, 14),
		TextSize = Sizes.Small,
		Color = if discovered then rarityColor else Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		TextTruncate = AtEnd,
		ZIndex = 3,
	})
	if entry and entry.shiny then
		PixelUI.Label({
			Parent = card,
			Text = "*",
			Position = UDim2.new(1, -16, 0, 2),
			Size = UDim2.fromOffset(12, 14),
			XAlign = Enum.TextXAlignment.Center,
			Color = Colors.Accent,
			Outline = true,
			ZIndex = 4,
		})
	end
	return card
end

local function renderGrid()
	clearChildren(gridScroll)
	table.clear(cards)

	local filtered = selectedFilter ~= ALL_WATERS
	local pool: { [string]: boolean } = {}
	if filtered then
		for _, def in ipairs(FishData.PoolFor(selectedFilter)) do
			pool[def.id] = true
		end
	end

	local selectionVisible = false
	local order = 0
	for _, def in ipairs(SORTED) do
		if not filtered or pool[def.id] then
			order += 1
			cards[def.id] = buildCard(gridScroll, def, entryFor(def.id), order)
			if def.id == selectedFish then
				selectionVisible = true
			end
		end
	end

	if selectedFish and selectionVisible then
		styleCard(selectedFish, true)
	else
		selectedFish = nil
	end
	renderDetail()
end

local function updateHeader()
	local profile = ctx.State.Profile
	local total = #FishData.List
	local discovered = 0
	if profile then
		for _, def in ipairs(FishData.List) do
			if profile.bestiary[def.id] then
				discovered += 1
			end
		end
	end
	local fraction = if total > 0 then discovered / total else 0
	progressLabel.Text = string.format("Discovered %d / %d", discovered, total)
	progressBar.Set(fraction, false)
	progressBar.Label.Text = string.format("%d%%", math.floor(fraction * 100))
end

local function render()
	stale = false
	updateHeader()
	renderGrid()
end

local function flush()
	flushQueued = false
	if isOpen and stale then
		render()
	end
end

local function onStateChanged(key: string)
	if key ~= "profile" and key ~= "bestiary" then
		return
	end
	stale = true
	if isOpen and not flushQueued then
		flushQueued = true
		task.defer(flush)
	end
end

-- ---------------------------------------------------------------- filters

local function styleFilters()
	for id, button in pairs(filterButtons) do
		local active = id == selectedFilter
		button:SetAttribute("BaseColor", if active then Colors.Accent else Colors.ButtonSecondary)
		button:SetAttribute("TextBase", if active then Colors.TextDark else Colors.ButtonSecondaryText)
	end
end

local function setFilter(id: string)
	selectedFilter = id
	styleFilters()
	if isOpen then
		renderGrid()
		gridScroll.CanvasPosition = Vector2.zero
	else
		stale = true
	end
end

local function buildFilters(parent: GuiObject)
	local entries = { { id = ALL_WATERS, name = "All Waters" } }
	for _, location in ipairs(LocationData.List) do
		if #FishData.PoolFor(location.id) > 0 then
			table.insert(entries, { id = location.id, name = location.name })
		end
	end
	for index, entry in ipairs(entries) do
		filterButtons[entry.id] = PixelUI.Button({
			Name = entry.id,
			Parent = parent,
			Text = entry.name,
			Size = UDim2.new(1, -4, 0, 36),
			TextSize = Sizes.Small,
			TextWrapped = true,
			LayoutOrder = index,
			OnClick = function()
				setFilter(entry.id)
			end,
		})
	end
	styleFilters()
end

-- ---------------------------------------------------------------- public API

function Window.Init(context: Ctx)
	if initialized then
		return
	end
	initialized = true
	ctx = context

	win = PixelUI.Window({
		Name = "BestiaryWindow",
		Parent = ctx.Gui,
		Title = "Fish Book",
		Size = WINDOW_SIZE,
		OnClose = function()
			ctx.Windows.Close(Window.Name)
		end,
	})

	local header = PixelUI.Frame({ Name = "Header", Parent = win.Content, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 })
	progressLabel = PixelUI.Label({
		Name = "Discovered",
		Parent = header,
		Size = UDim2.fromOffset(280, 28),
		Text = string.format("Discovered 0 / %d", #FishData.List),
	})
	progressBar = PixelUI.ProgressBar({
		Parent = header,
		Position = UDim2.new(0, 290, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, -290, 0, 20),
		Color = Colors.Accent2,
		Value = 0,
		Text = "0%",
	})

	local body = PixelUI.Frame({
		Name = "Body",
		Parent = win.Content,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		BackgroundTransparency = 1,
	})

	local filters = PixelUI.Scroll({ Name = "Filters", Parent = body, Size = UDim2.new(0, FILTER_WIDTH, 1, 0), ScrollBarThickness = 6 })
	PixelUI.List(filters, Enum.FillDirection.Vertical, 4)
	buildFilters(filters)

	local well = PixelUI.Frame({
		Name = "Well",
		Parent = body,
		Position = UDim2.fromOffset(GRID_X, 0),
		Size = UDim2.new(0, GRID_WIDTH, 1, 0),
		Color = Colors.PanelDark,
		Border = true,
	})
	gridScroll = PixelUI.Scroll({ Name = "Fish", Parent = well })
	PixelUI.Padding(gridScroll, 6)
	local grid = PixelUI.Grid(gridScroll, CARD_SIZE, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local _, detail = PixelUI.Panel({
		Name = "Detail",
		Parent = body,
		Position = UDim2.fromOffset(DETAIL_X, 0),
		Size = UDim2.new(1, -DETAIL_X - 5, 1, -5),
	})
	PixelUI.Padding(detail, 10)
	detailBody = detail

	ctx.State.Changed:Connect(onStateChanged)
end

function Window.Open(_payload: any?)
	if not initialized then
		return
	end
	if not isOpen then
		isOpen = true
		win.SetOpen(true)
	end
	flush()
end

function Window.Close()
	if not initialized or not isOpen then
		return
	end
	isOpen = false
	win.SetOpen(false)
end

function Window.IsOpen(): boolean
	return isOpen
end

return Window
