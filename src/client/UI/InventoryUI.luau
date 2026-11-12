--!strict
-- Inventory window: fish bag (sortable grid + detail panel), owned rods and bait.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))
local Config = require(Shared:WaitForChild("Config"))
local FishData = require(Shared:WaitForChild("FishData"))
local RodData = require(Shared:WaitForChild("RodData"))
local BaitData = require(Shared:WaitForChild("BaitData"))
local LocationData = require(Shared:WaitForChild("LocationData"))
local RarityData = require(Shared:WaitForChild("RarityData"))
local MutationData = require(Shared:WaitForChild("MutationData"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))

local Colors = Theme.Colors
local Sizes = Theme.TextSizes
local AtEnd = Enum.TextTruncate.AtEnd

type Response = { ok: boolean, message: string?, [string]: any }
-- Rows are built once and refreshed in place so a gamepad's selected button survives state changes.
type Row = { update: () -> () }

type Ctx = {
	Gui: ScreenGui,
	State: typeof(require(script.Parent.Parent:WaitForChild("ClientState"))),
	Net: typeof(require(Shared:WaitForChild("Net"))),
	Windows: { Open: (name: string, payload: any?) -> (), Close: (name: string) -> (), CloseAll: () -> (), IsOpen: (name: string) -> boolean },
	Sounds: { Play: (name: string) -> () },
	Notify: (kind: string, text: string) -> (),
}

local Window = {}
Window.Name = "Inventory"

local WINDOW_SIZE = UDim2.fromOffset(760, 480)
local CARD_SIZE = UDim2.fromOffset(98, 118)
local CONFIRM_SECONDS = 3
local SORT_NAMES = { "Newest", "Value", "Rarity" }

-- Which tabs each State.Changed key invalidates.
local KEY_TABS: { [string]: { string } } = {
	profile = { "fish", "rods", "bait" },
	fish = { "fish" },
	rods = { "rods" },
	equippedRod = { "rods" },
	bait = { "bait" },
	equippedBait = { "bait" },
}

local ctx: Ctx = nil :: any
local win: PixelUI.Window = nil :: any
local tabs: PixelUI.Tabs = nil :: any
local pages: { [string]: Frame } = {}
local stale: { [string]: boolean } = { fish = true, rods = true, bait = true }
local currentTab = "fish"
local initialized = false
local isOpen = false
local flushQueued = false
local busy = false

-- Fish tab
local sortIndex = 1
local selectedUid: string? = nil
local armedUid: string? = nil
local armedToken = 0
local sortButton: TextButton = nil :: any
local totalLabel: TextLabel = nil :: any
local emptyLabel: TextLabel = nil :: any
local fishScroll: ScrollingFrame = nil :: any
local detailBody: Frame = nil :: any
local discardButton: TextButton? = nil
local cards: { [string]: TextButton } = {}

-- Rods / bait tabs
local rodScroll: ScrollingFrame = nil :: any
local rodRows: { Row } = {}
local rodSignature = "?"
local baitScroll: ScrollingFrame = nil :: any
local baitRows: { Row } = {}
local baitSignature = "?"

-- ---------------------------------------------------------------- helpers

local function clearChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

local function mutedText(text: string): string
	return string.format('<font color="#%s">%s</font>', Colors.TextMuted:ToHex(), text)
end

local function report(resp: Response, okText: string, failText: string)
	ctx.Notify(if resp.ok then "success" else "error", resp.message or (if resp.ok then okText else failText))
end

-- Serialises server calls so a double click can't fire the same request twice.
local function request(name: string, ...: any): Response?
	if busy then
		return nil
	end
	busy = true
	local resp = ctx.Net.Invoke(name, ...)
	busy = false
	return resp
end

local function equip(kind: string, id: string?)
	local resp = request("Equip", kind, id)
	if resp then
		report(resp, "Equipped.", "Couldn't equip that.")
	end
end

-- Tiny pixel rod: grip + shaft on a diagonal, with a line and bobber.
local ROD_CELLS = {
	{ 0, 6, 1 }, { 1, 5, 1 }, { 2, 4, 2 }, { 3, 3, 2 }, { 4, 2, 2 }, { 5, 1, 2 },
	{ 6, 1, 3 }, { 6, 2, 3 }, { 6, 3, 3 }, { 6, 4, 3 }, { 6, 5, 4 },
}

local function drawRod(parent: GuiObject, rod: Types.RodDef, position: UDim2)
	local box = PixelUI.Frame({
		Name = "RodIcon",
		Parent = parent,
		Position = position,
		Size = UDim2.fromOffset(48, 48),
		Color = Colors.PanelLight,
		Border = true,
		Thickness = 2,
	})
	for _, cell in ipairs(ROD_CELLS) do
		local col, row, kind = cell[1], cell[2], cell[3]
		local thin = kind == 3
		PixelUI.Frame({
			Parent = box,
			Position = UDim2.fromOffset(3 + col * 6 + (if thin then 2 else 0), 3 + row * 6),
			Size = UDim2.fromOffset(if thin then 2 else 6, 6),
			Color = if kind == 1 then rod.color2 elseif kind == 2 then rod.color1 elseif kind == 3 then Colors.Text else Colors.Danger,
		})
	end
end

-- Two rows of rod stats in three columns.
local function buildRodStats(parent: GuiObject, rod: Types.RodDef, position: UDim2, size: UDim2)
	local holder = PixelUI.Frame({ Name = "Stats", Parent = parent, Position = position, Size = size, BackgroundTransparency = 1 })
	PixelUI.List(holder, Enum.FillDirection.Horizontal, 10)
	local columns = {
		{
			{ "Luck", "+" .. PixelUI.FormatNumber(rod.luck) .. "%" },
			{ "Lure Speed", string.format("x%.1f", rod.lureSpeed) },
		},
		{
			{ "Control", PixelUI.FormatNumber(rod.control) },
			{ "Resilience", PixelUI.FormatNumber(rod.resilience) },
		},
		{
			{ "Max Weight", PixelUI.FormatNumber(rod.maxWeight) .. " kg" },
			{ "Cast Range", PixelUI.FormatNumber(rod.castRange) .. " studs" },
		},
	}
	for index, stats in ipairs(columns) do
		local column = PixelUI.Frame({ Parent = holder, Size = UDim2.new(1 / 3, -7, 1, 0), BackgroundTransparency = 1, LayoutOrder = index })
		PixelUI.List(column, Enum.FillDirection.Vertical, 2)
		for order, stat in ipairs(stats) do
			local nameLabel, valueLabel = PixelUI.StatRow(column, stat[1], stat[2], order)
			nameLabel.TextTruncate = AtEnd
			valueLabel.TextTruncate = AtEnd
		end
	end
end

-- ---------------------------------------------------------------- fish tab

local function newest(a: Types.CaughtFish, b: Types.CaughtFish): boolean
	if a.caughtAt ~= b.caughtAt then
		return a.caughtAt > b.caughtAt
	end
	return a.uid > b.uid
end

local function rarityIndexOf(caught: Types.CaughtFish): number
	local def = FishData.Get(caught.id)
	return if def then RarityData.Index(def.rarity) else 0
end

local SORTERS: { (Types.CaughtFish, Types.CaughtFish) -> boolean } = {
	newest,
	function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return newest(a, b)
	end,
	function(a, b)
		local ra, rb = rarityIndexOf(a), rarityIndexOf(b)
		if ra ~= rb then
			return ra > rb
		end
		if a.value ~= b.value then
			return a.value > b.value
		end
		return newest(a, b)
	end,
}

local function sortedFish(): { Types.CaughtFish }
	local profile = ctx.State.Profile
	local list = table.clone(if profile then profile.fish else {})
	table.sort(list, SORTERS[sortIndex])
	return list
end

local function findFish(uid: string): Types.CaughtFish?
	local profile = ctx.State.Profile
	if profile then
		for _, caught in ipairs(profile.fish) do
			if caught.uid == uid then
				return caught
			end
		end
	end
	return nil
end

local function updateDiscardButton()
	local button = discardButton
	if not button or not button.Parent then
		return
	end
	local armed = selectedUid ~= nil and armedUid == selectedUid
	button.Text = if armed then "Really?" else "Discard"
	button:SetAttribute("BaseColor", if armed then Util.Lighten(Colors.ButtonDanger, 0.3) else Colors.ButtonDanger)
end

local function disarmDiscard()
	armedUid = nil
	armedToken += 1
	updateDiscardButton()
end

local function onDiscard()
	local uid = selectedUid
	if not uid then
		return
	end
	if armedUid ~= uid then
		-- First click: ask for confirmation, then expire it.
		armedUid = uid
		armedToken += 1
		local token = armedToken
		updateDiscardButton()
		task.delay(CONFIRM_SECONDS, function()
			if armedToken == token then
				disarmDiscard()
			end
		end)
		return
	end
	armedUid = nil
	armedToken += 1
	local resp = request("DiscardFish", uid)
	if resp then
		report(resp, "Fish released.", "Couldn't release that fish.")
	end
	updateDiscardButton()
end

local function renderDetail()
	clearChildren(detailBody)
	discardButton = nil

	local caught = if selectedUid then findFish(selectedUid) else nil
	local def = if caught then FishData.Get(caught.id) else nil
	if not caught or not def then
		PixelUI.Label({
			Parent = detailBody,
			Size = UDim2.fromScale(1, 1),
			Text = "Select a fish to see its details.",
			Color = Colors.TextMuted,
			XAlign = Enum.TextXAlignment.Center,
			Wrap = true,
		})
		return
	end

	local rarityColor = RarityData.Color(def.rarity)
	local mutation = MutationData.Get(caught.mutation)

	local info = PixelUI.Scroll({ Name = "Info", Parent = detailBody, Size = UDim2.new(1, 0, 1, -42), ScrollBarThickness = 4 })
	PixelUI.List(info, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)

	local iconHolder = PixelUI.Frame({ Parent = info, Size = UDim2.new(1, 0, 0, 84), BackgroundTransparency = 1, LayoutOrder = 1 })
	PixelIcon.Render(iconHolder, def, {
		shiny = caught.shiny,
		mutationColor = if mutation then mutation.color else nil,
		Size = UDim2.fromOffset(120, 80),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	PixelUI.Label({
		Parent = info,
		Text = def.name,
		TextSize = Sizes.Title,
		Color = rarityColor,
		XAlign = Enum.TextXAlignment.Center,
		Wrap = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
	})
	PixelUI.Tag({ Parent = info, Text = string.upper(def.rarity), Color = rarityColor, LayoutOrder = 3 })
	PixelUI.StatRow(info, "Weight", PixelUI.FormatWeight(caught.weight), 4)
	PixelUI.StatRow(info, "Size", caught.sizeTier, 5)
	if mutation then
		PixelUI.Label({
			Parent = info,
			Text = mutation.id .. ": " .. mutation.description,
			TextSize = Sizes.Small,
			Color = Util.Lighten(mutation.color, 0.3),
			Wrap = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 14),
			LayoutOrder = 6,
		})
	end
	if caught.shiny then
		PixelUI.Label({
			Parent = info,
			Text = "Shiny!",
			Color = Colors.Accent,
			XAlign = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 7,
		})
	end
	PixelUI.StatRow(info, "Value", PixelUI.FormatNumber(caught.value) .. " c", 8, Colors.Coins)
	PixelUI.Label({
		Parent = info,
		Text = mutedText("Caught at") .. " " .. LocationData.Name(caught.location),
		TextSize = Sizes.Small,
		Rich = true,
		Wrap = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 9,
	})

	discardButton = PixelUI.Button({
		Name = "Discard",
		Parent = detailBody,
		Text = "Discard",
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Color = Colors.ButtonDanger,
		TextColor = Colors.Text,
		OnClick = onDiscard,
	})
	updateDiscardButton()
end

local function styleCard(uid: string, selected: boolean)
	local card = cards[uid]
	if not card then
		return
	end
	card:SetAttribute("BaseColor", if selected then Colors.PanelLight else Colors.Panel)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = if selected then 4 else 2
	end
end

local function selectFish(uid: string)
	if selectedUid == uid then
		return
	end
	local previous = selectedUid
	selectedUid = uid
	armedUid = nil
	armedToken += 1
	if previous then
		styleCard(previous, false)
	end
	styleCard(uid, true)
	renderDetail()
end

local function buildCard(parent: GuiObject, def: Types.FishDef, caught: Types.CaughtFish, order: number): TextButton
	local rarityColor = RarityData.Color(def.rarity)
	local mutation = MutationData.Get(caught.mutation)
	local card = PixelUI.Button({
		Name = caught.uid,
		Parent = parent,
		Text = "",
		Size = CARD_SIZE,
		Color = Colors.Panel,
		LayoutOrder = order,
		OnClick = function()
			selectFish(caught.uid)
		end,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarityColor
		stroke.Thickness = 2
	end

	PixelIcon.Render(card, def, {
		shiny = caught.shiny,
		mutationColor = if mutation then mutation.color else nil,
		Size = UDim2.fromOffset(72, 48),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
	})
	PixelUI.Label({
		Parent = card,
		Text = def.name,
		Position = UDim2.fromOffset(4, 60),
		Size = UDim2.new(1, -8, 0, 14),
		TextSize = Sizes.Small,
		Color = rarityColor,
		XAlign = Enum.TextXAlignment.Center,
		TextTruncate = AtEnd,
		ZIndex = 3,
	})
	PixelUI.Label({
		Parent = card,
		Text = PixelUI.FormatWeight(caught.weight),
		Position = UDim2.fromOffset(4, 76),
		Size = UDim2.new(1, -8, 0, 12),
		TextSize = Sizes.Tiny,
		Color = Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	PixelUI.Label({
		Parent = card,
		Text = PixelUI.FormatNumber(caught.value) .. " c",
		Position = UDim2.fromOffset(4, 90),
		Size = UDim2.new(1, -8, 0, 14),
		TextSize = Sizes.Small,
		Color = Colors.Coins,
		XAlign = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	return card
end

local function updateTabLabel()
	local button = tabs.Buttons.fish
	if button then
		button.Text = string.format("Fish (%d/%d)", ctx.State.FishCount(), Config.FishCapacity)
	end
end

local function renderFish()
	stale.fish = false
	local sorted = sortedFish()

	clearChildren(fishScroll)
	table.clear(cards)
	local selectionExists = false
	local total = 0
	for index, caught in ipairs(sorted) do
		total += caught.value
		local def = FishData.Get(caught.id)
		if def then
			cards[caught.uid] = buildCard(fishScroll, def, caught, index)
		end
		if caught.uid == selectedUid then
			selectionExists = true
		end
	end

	if selectionExists and selectedUid then
		styleCard(selectedUid, true)
	else
		selectedUid = nil
		armedUid = nil
		armedToken += 1
	end

	local full = #sorted >= Config.FishCapacity
	emptyLabel.Visible = #sorted == 0
	totalLabel.Text = if #sorted == 0 then "" elseif full then "Bag full! Sell or release some." else string.format("Worth %s c", PixelUI.FormatNumber(total))
	totalLabel.TextColor3 = if full then Colors.Danger else Colors.TextMuted
	updateTabLabel()
	renderDetail()
end

-- Re-sorts the existing cards without rebuilding them.
local function reorderFish()
	for index, caught in ipairs(sortedFish()) do
		local card = cards[caught.uid]
		if card then
			card.LayoutOrder = index
		end
	end
	fishScroll.CanvasPosition = Vector2.zero
end

local function buildFishPage(page: Frame)
	local left = PixelUI.Frame({ Name = "Left", Parent = page, Size = UDim2.new(0.6, -4, 1, 0), BackgroundTransparency = 1 })

	local toolbar = PixelUI.Frame({ Name = "Toolbar", Parent = left, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 })
	sortButton = PixelUI.Button({
		Name = "Sort",
		Parent = toolbar,
		Text = "Sort: " .. SORT_NAMES[sortIndex],
		Size = UDim2.fromOffset(150, 28),
		TextSize = Sizes.Small,
		Color = Colors.ButtonSecondary,
		TextColor = Colors.ButtonSecondaryText,
		OnClick = function()
			sortIndex = sortIndex % #SORT_NAMES + 1
			sortButton.Text = "Sort: " .. SORT_NAMES[sortIndex]
			reorderFish()
		end,
	})
	totalLabel = PixelUI.Label({
		Name = "Total",
		Parent = toolbar,
		Position = UDim2.fromOffset(158, 0),
		Size = UDim2.new(1, -158, 1, 0),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = Sizes.Small,
		Color = Colors.TextMuted,
		TextTruncate = AtEnd,
	})

	local well = PixelUI.Frame({
		Name = "Well",
		Parent = left,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		Color = Colors.PanelDark,
		Border = true,
	})
	fishScroll = PixelUI.Scroll({ Name = "Fish", Parent = well })
	PixelUI.Padding(fishScroll, 6)
	local grid = PixelUI.Grid(fishScroll, CARD_SIZE, 6)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	emptyLabel = PixelUI.Label({
		Name = "Empty",
		Parent = well,
		Size = UDim2.fromScale(1, 1),
		Text = "No fish yet. Go cast a line!",
		Color = Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		Wrap = true,
		Visible = false,
		ZIndex = 2,
	})

	local _, body = PixelUI.Panel({
		Name = "Detail",
		Parent = page,
		Position = UDim2.new(0.6, 4, 0, 0),
		Size = UDim2.new(0.4, -9, 1, -5),
	})
	PixelUI.Padding(body, 10)
	detailBody = body
end

-- ---------------------------------------------------------------- rods tab

local function buildRodRow(parent: GuiObject, rod: Types.RodDef, order: number): Row
	local row = PixelUI.Frame({
		Name = rod.id,
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 112),
		Color = Colors.Panel,
		Border = true,
		Thickness = 2,
		LayoutOrder = order,
	})
	drawRod(row, rod, UDim2.fromOffset(10, 10))
	PixelUI.Label({
		Parent = row,
		Text = rod.name,
		Position = UDim2.fromOffset(68, 8),
		Size = UDim2.new(1, -196, 0, 22),
		TextSize = Sizes.Title,
		TextTruncate = AtEnd,
	})
	PixelUI.Label({
		Parent = row,
		Text = rod.description,
		Position = UDim2.fromOffset(68, 32),
		Size = UDim2.new(1, -196, 0, 28),
		TextSize = Sizes.Small,
		Color = Colors.TextMuted,
		Wrap = true,
		YAlign = Enum.TextYAlignment.Top,
	})
	buildRodStats(row, rod, UDim2.fromOffset(12, 66), UDim2.new(1, -24, 0, 40))

	local button = PixelUI.Button({
		Name = "Equip",
		Parent = row,
		Text = "Equip",
		Size = UDim2.fromOffset(112, 32),
		Position = UDim2.new(1, -10, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		OnClick = function()
			equip("rod", rod.id)
		end,
	})
	local stroke = row:FindFirstChildOfClass("UIStroke")

	return {
		update = function()
			local equipped = ctx.State.GetRod().id == rod.id
			button.Text = if equipped then "Equipped" else "Equip"
			button:SetAttribute("Disabled", equipped)
			if stroke then
				stroke.Color = if equipped then Colors.Accent else Colors.Border
			end
		end,
	}
end

local function renderRods()
	stale.rods = false
	local owned: { Types.RodDef } = {}
	local ids: { string } = {}
	for _, rod in ipairs(RodData.List) do
		if ctx.State.OwnsRod(rod.id) then
			table.insert(owned, rod)
			table.insert(ids, rod.id)
		end
	end

	local signature = table.concat(ids, ",")
	if signature ~= rodSignature then
		rodSignature = signature
		clearChildren(rodScroll)
		table.clear(rodRows)
		for index, rod in ipairs(owned) do
			table.insert(rodRows, buildRodRow(rodScroll, rod, index))
		end
		if #owned == 0 then
			PixelUI.Label({
				Parent = rodScroll,
				Text = "You don't own any rods yet.",
				Color = Colors.TextMuted,
				XAlign = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 40),
			})
		end
	end
	for _, row in ipairs(rodRows) do
		row.update()
	end
end

local function buildListPage(page: Frame): ScrollingFrame
	local well = PixelUI.Frame({ Parent = page, Size = UDim2.fromScale(1, 1), Color = Colors.PanelDark, Border = true })
	local scroll = PixelUI.Scroll({ Parent = well })
	PixelUI.Padding(scroll, 6)
	PixelUI.List(scroll, Enum.FillDirection.Vertical, 8)
	return scroll
end

-- ---------------------------------------------------------------- bait tab

-- `bait` = nil builds the "No Bait" row.
local function buildBaitRow(parent: GuiObject, bait: Types.BaitDef?, order: number): Row
	local row = PixelUI.Frame({
		Name = if bait then bait.id else "none",
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 76),
		Color = Colors.Panel,
		Border = true,
		Thickness = 2,
		LayoutOrder = order,
	})
	local swatchColor = if bait then bait.color else Colors.ButtonDisabled
	local swatch = PixelUI.Frame({
		Name = "Swatch",
		Parent = row,
		Position = UDim2.fromOffset(12, 18),
		Size = UDim2.fromOffset(36, 36),
		Color = swatchColor,
		Border = true,
		Thickness = 2,
	})
	PixelUI.Frame({ Parent = swatch, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(8, 8), Color = Util.Lighten(swatchColor, 0.5) })

	PixelUI.Label({
		Parent = row,
		Text = if bait then bait.name else "No Bait",
		Position = UDim2.fromOffset(60, 8),
		Size = UDim2.new(1, -284, 0, 20),
		TextTruncate = AtEnd,
	})
	PixelUI.Label({
		Parent = row,
		Text = if bait then bait.description else "Cast with a bare hook. Nothing is used up.",
		Position = UDim2.fromOffset(60, 28),
		Size = UDim2.new(1, -284, 0, 28),
		TextSize = Sizes.Small,
		Color = Colors.TextMuted,
		Wrap = true,
		YAlign = Enum.TextYAlignment.Top,
	})
	if bait then
		PixelUI.Label({
			Parent = row,
			Text = string.format("Luck +%s%%   Lure x%g", PixelUI.FormatNumber(bait.luck), bait.lureSpeed),
			Position = UDim2.fromOffset(60, 58),
			Size = UDim2.new(1, -284, 0, 12),
			TextSize = Sizes.Tiny,
			Color = Colors.Accent2,
			TextTruncate = AtEnd,
		})
	end

	local countLabel = PixelUI.Label({
		Parent = row,
		Position = UDim2.new(1, -130, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(90, 20),
		XAlign = Enum.TextXAlignment.Right,
	})
	local button = PixelUI.Button({
		Name = "Equip",
		Parent = row,
		Text = "Equip",
		Size = UDim2.fromOffset(112, 32),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		OnClick = function()
			equip("bait", if bait then bait.id else nil)
		end,
	})
	local stroke = row:FindFirstChildOfClass("UIStroke")

	return {
		update = function()
			local active = ctx.State.GetBait()
			local equipped = if bait then active ~= nil and active.id == bait.id else active == nil
			if bait then
				countLabel.Text = "x" .. PixelUI.FormatNumber(ctx.State.BaitCount(bait.id))
			end
			button.Text = if equipped then "Equipped" elseif bait then "Equip" else "Unequip"
			button:SetAttribute("Disabled", equipped)
			if stroke then
				stroke.Color = if equipped then Colors.Accent else Colors.Border
			end
		end,
	}
end

local function renderBait()
	stale.bait = false
	local owned: { Types.BaitDef } = {}
	local ids: { string } = {}
	for _, bait in ipairs(BaitData.List) do
		if ctx.State.BaitCount(bait.id) > 0 then
			table.insert(owned, bait)
			table.insert(ids, bait.id)
		end
	end

	local signature = table.concat(ids, ",")
	if signature ~= baitSignature then
		baitSignature = signature
		clearChildren(baitScroll)
		table.clear(baitRows)
		PixelUI.Label({
			Name = "Hint",
			Parent = baitScroll,
			Text = "Equipped bait is used up one per cast.",
			TextSize = Sizes.Small,
			Color = Colors.TextMuted,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = -1,
		})
		table.insert(baitRows, buildBaitRow(baitScroll, nil, 0))
		for index, bait in ipairs(owned) do
			table.insert(baitRows, buildBaitRow(baitScroll, bait, index))
		end
		if #owned == 0 then
			PixelUI.Label({
				Parent = baitScroll,
				Text = "No bait in your bag. Rod shops sell some!",
				Color = Colors.TextMuted,
				XAlign = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 40),
				LayoutOrder = 1,
			})
		end
	end
	for _, row in ipairs(baitRows) do
		row.update()
	end
end

-- ---------------------------------------------------------------- tabs & refresh

local function renderTab(id: string)
	if not stale[id] then
		return
	end
	if id == "fish" then
		renderFish()
	elseif id == "rods" then
		renderRods()
	elseif id == "bait" then
		renderBait()
	end
end

local function showTab(id: string)
	currentTab = id
	for pageId, page in pairs(pages) do
		page.Visible = pageId == id
	end
	if isOpen then
		renderTab(id)
	end
end

local function flush()
	flushQueued = false
	if not isOpen then
		return
	end
	updateTabLabel()
	renderTab(currentTab)
end

local function onStateChanged(key: string)
	local affected = KEY_TABS[key]
	if not affected then
		return
	end
	for _, id in ipairs(affected) do
		stale[id] = true
	end
	if isOpen and not flushQueued then
		flushQueued = true
		task.defer(flush)
	end
end

-- ---------------------------------------------------------------- public API

function Window.Init(context: Ctx)
	if initialized then
		return
	end
	initialized = true
	ctx = context

	win = PixelUI.Window({
		Name = "InventoryWindow",
		Parent = ctx.Gui,
		Title = "Inventory",
		Size = WINDOW_SIZE,
		OnClose = function()
			ctx.Windows.Close(Window.Name)
		end,
	})

	tabs = PixelUI.Tabs({
		Parent = win.Content,
		Tabs = {
			{ id = "fish", text = "Fish", width = 170 },
			{ id = "rods", text = "Rods", width = 120 },
			{ id = "bait", text = "Bait", width = 120 },
		},
		OnSelect = showTab,
	})

	local host = PixelUI.Frame({
		Name = "Pages",
		Parent = win.Content,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -42),
		BackgroundTransparency = 1,
	})
	for _, id in ipairs({ "fish", "rods", "bait" }) do
		pages[id] = PixelUI.Frame({ Name = id, Parent = host, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	end
	buildFishPage(pages.fish)
	rodScroll = buildListPage(pages.rods)
	baitScroll = buildListPage(pages.bait)

	ctx.State.Changed:Connect(onStateChanged)
	tabs.Select("fish")
	updateTabLabel()
end

function Window.Open(payload: any?)
	if not initialized then
		return
	end
	if type(payload) == "table" then
		local tab = payload.tab
		if type(tab) == "string" and pages[tab] then
			tabs.Select(tab)
		end
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
	disarmDiscard()
	win.SetOpen(false)
end

function Window.IsOpen(): boolean
	return isOpen
end

return Window
