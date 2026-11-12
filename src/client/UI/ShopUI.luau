--!strict
-- Rod shop window: buy and equip rods, buy bait. Rows are built once per shop and refreshed in place,
-- so a gamepad's selected button survives every purchase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))
local RodData = require(Shared:WaitForChild("RodData"))
local BaitData = require(Shared:WaitForChild("BaitData"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))

local Colors = Theme.Colors
local Sizes = Theme.TextSizes
local AtEnd = Enum.TextTruncate.AtEnd

type Response = { ok: boolean, message: string?, [string]: any }
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
Window.Name = "Shop"

local WINDOW_SIZE = UDim2.fromOffset(760, 480)
local DEFAULT_SHOP = "mossbell"
local DEFAULT_NPC = "Wren"

-- State.Changed keys that affect what the shop shows.
local REFRESH_KEYS: { [string]: boolean } = {
	profile = true,
	coins = true,
	level = true,
	rods = true,
	bait = true,
	equippedRod = true,
}

local ctx: Ctx = nil :: any
local win: PixelUI.Window = nil :: any
local tabs: PixelUI.Tabs = nil :: any
local pages: { [string]: Frame } = {}
local initialized = false
local isOpen = false
local dirty = true
local flushQueued = false
local busy = false

local shopId = DEFAULT_SHOP
local builtShop = ""
local npcName = DEFAULT_NPC

local coinsLabel: TextLabel = nil :: any
local levelLabel: TextLabel = nil :: any
local rodScroll: ScrollingFrame = nil :: any
local baitScroll: ScrollingFrame = nil :: any
local rodRows: { Row } = {}
local baitRows: { Row } = {}

-- ---------------------------------------------------------------- helpers

local function clearChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

local function report(resp: Response, okText: string, failText: string)
	ctx.Notify(if resp.ok then "success" else "error", resp.message or (if resp.ok then okText else failText))
end

-- Serialises server calls so a double click can't buy twice.
local function request(name: string, ...: any): Response?
	if busy then
		return nil
	end
	busy = true
	local resp = ctx.Net.Invoke(name, ...)
	busy = false
	return resp
end

local function equipRod(id: string)
	local resp = request("Equip", "rod", id)
	if resp then
		report(resp, "Equipped.", "Couldn't equip that.")
	end
end

local function buy(kind: string, id: string, amount: number?)
	local resp = request("Purchase", kind, id, amount)
	if not resp then
		return
	end
	if resp.ok then
		ctx.Sounds.Play("Coin")
	end
	report(resp, "Purchased!", "Couldn't buy that.")
end

local function playerNumbers(): (number, number)
	local profile = ctx.State.Profile
	if profile then
		return profile.coins, profile.level
	end
	return 0, 1
end

local function setButtonStyle(button: TextButton, base: Color3, text: Color3)
	button:SetAttribute("BaseColor", base)
	button:SetAttribute("TextBase", text)
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

-- ---------------------------------------------------------------- rods

local function buildRodRow(parent: GuiObject, rod: Types.RodDef, order: number): Row
	local row = PixelUI.Frame({
		Name = rod.id,
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 136),
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
		Size = UDim2.new(1, -260, 0, 22),
		TextSize = Sizes.Title,
		TextTruncate = AtEnd,
	})
	PixelUI.Label({
		Parent = row,
		Text = rod.description,
		Position = UDim2.fromOffset(68, 32),
		Size = UDim2.new(1, -260, 0, 28),
		TextSize = Sizes.Small,
		Color = Colors.TextMuted,
		Wrap = true,
		YAlign = Enum.TextYAlignment.Top,
	})
	buildRodStats(row, rod, UDim2.fromOffset(12, 92), UDim2.new(1, -24, 0, 38))

	local priceLabel = PixelUI.Label({
		Name = "Price",
		Parent = row,
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(180, 20),
		XAlign = Enum.TextXAlignment.Right,
		Color = Colors.Coins,
	})
	local levelLabel = PixelUI.Label({
		Name = "Level",
		Parent = row,
		Position = UDim2.new(1, -12, 0, 30),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(180, 14),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = Sizes.Small,
	})
	local reasonLabel = PixelUI.Label({
		Name = "Reason",
		Parent = row,
		Position = UDim2.new(1, -152, 0, 67),
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(200, 14),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = Sizes.Tiny,
		Color = Colors.TextMuted,
		TextTruncate = AtEnd,
	})
	local button = PixelUI.Button({
		Name = "Action",
		Parent = row,
		Text = "Buy",
		Size = UDim2.fromOffset(136, 32),
		Position = UDim2.new(1, -12, 0, 51),
		AnchorPoint = Vector2.new(1, 0),
		OnClick = function()
			if ctx.State.OwnsRod(rod.id) then
				equipRod(rod.id)
			else
				buy("rod", rod.id, nil)
			end
		end,
	})
	local stroke = row:FindFirstChildOfClass("UIStroke")

	return {
		update = function()
			local coins, level = playerNumbers()
			local owned = ctx.State.OwnsRod(rod.id)
			local equipped = owned and ctx.State.GetRod().id == rod.id

			priceLabel.Text = if owned then "Owned" elseif rod.price > 0 then PixelUI.FormatNumber(rod.price) .. " coins" else "Free"
			priceLabel.TextColor3 = if owned then Colors.Success else Colors.Coins
			levelLabel.Text = "Lv. " .. PixelUI.FormatNumber(rod.levelReq)
			levelLabel.TextColor3 = if level >= rod.levelReq then Colors.TextMuted else Colors.Danger

			local reason = ""
			if owned then
				button.Text = if equipped then "Equipped" else "Equip"
				button:SetAttribute("Disabled", equipped)
				setButtonStyle(button, Colors.Button, Colors.ButtonText)
			else
				button.Text = "Buy"
				if level < rod.levelReq then
					reason = "Need level " .. PixelUI.FormatNumber(rod.levelReq)
				elseif coins < rod.price then
					reason = "Not enough coins"
				end
				button:SetAttribute("Disabled", reason ~= "")
				setButtonStyle(button, Colors.Accent, Colors.TextDark)
			end
			reasonLabel.Text = reason
			if stroke then
				stroke.Color = if equipped then Colors.Accent else Colors.Border
			end
		end,
	}
end

-- ---------------------------------------------------------------- bait

local function buildBaitRow(parent: GuiObject, bait: Types.BaitDef, order: number): Row
	local row = PixelUI.Frame({
		Name = bait.id,
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 76),
		Color = Colors.Panel,
		Border = true,
		Thickness = 2,
		LayoutOrder = order,
	})
	local swatch = PixelUI.Frame({
		Name = "Swatch",
		Parent = row,
		Position = UDim2.fromOffset(12, 18),
		Size = UDim2.fromOffset(36, 36),
		Color = bait.color,
		Border = true,
		Thickness = 2,
	})
	PixelUI.Frame({ Parent = swatch, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(8, 8), Color = Util.Lighten(bait.color, 0.5) })

	PixelUI.Label({
		Parent = row,
		Text = bait.name,
		Position = UDim2.fromOffset(60, 8),
		Size = UDim2.new(1, -430, 0, 20),
		TextTruncate = AtEnd,
	})
	PixelUI.Label({
		Parent = row,
		Text = bait.description,
		Position = UDim2.fromOffset(60, 28),
		Size = UDim2.new(1, -430, 0, 28),
		TextSize = Sizes.Small,
		Color = Colors.TextMuted,
		Wrap = true,
		YAlign = Enum.TextYAlignment.Top,
	})
	PixelUI.Label({
		Parent = row,
		Text = string.format("Luck +%s%%   Lure x%g", PixelUI.FormatNumber(bait.luck), bait.lureSpeed),
		Position = UDim2.fromOffset(60, 58),
		Size = UDim2.new(1, -430, 0, 12),
		TextSize = Sizes.Tiny,
		Color = Colors.Accent2,
		TextTruncate = AtEnd,
	})

	PixelUI.Label({
		Name = "Price",
		Parent = row,
		Text = PixelUI.FormatNumber(bait.price) .. " coins each",
		Position = UDim2.new(1, -212, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(150, 18),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = Sizes.Small,
		Color = Colors.Coins,
		TextTruncate = AtEnd,
	})
	local ownedLabel = PixelUI.Label({
		Name = "Owned",
		Parent = row,
		Position = UDim2.new(1, -212, 0, 36),
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(150, 16),
		XAlign = Enum.TextXAlignment.Right,
		TextSize = Sizes.Small,
		Color = Colors.TextMuted,
		TextTruncate = AtEnd,
	})

	local function buyButton(label: string, amount: number, rightOffset: number): TextButton
		return PixelUI.Button({
			Name = "Buy" .. tostring(amount),
			Parent = row,
			Text = label,
			Size = UDim2.fromOffset(92, 32),
			Position = UDim2.new(1, rightOffset, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = Colors.Accent,
			TextColor = Colors.TextDark,
			OnClick = function()
				buy("bait", bait.id, amount)
			end,
		})
	end
	local buyOne = buyButton("Buy 1", 1, -112)
	local buyTen = buyButton("Buy 10", 10, -12)

	return {
		update = function()
			local coins = playerNumbers()
			ownedLabel.Text = "Owned: " .. PixelUI.FormatNumber(ctx.State.BaitCount(bait.id))
			buyOne:SetAttribute("Disabled", coins < bait.price)
			buyTen:SetAttribute("Disabled", coins < bait.price * 10)
		end,
	}
end

-- ---------------------------------------------------------------- build / refresh

local function addNote(parent: GuiObject, text: string)
	PixelUI.Label({
		Parent = parent,
		Text = text,
		Color = Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 40),
	})
end

local function rebuildRows()
	builtShop = shopId
	clearChildren(rodScroll)
	clearChildren(baitScroll)
	table.clear(rodRows)
	table.clear(baitRows)

	for _, rod in ipairs(RodData.List) do
		if rod.shop == shopId then
			table.insert(rodRows, buildRodRow(rodScroll, rod, #rodRows + 1))
		end
	end
	if #rodRows == 0 then
		addNote(rodScroll, "No rods for sale here.")
	end

	for _, bait in ipairs(BaitData.List) do
		if bait.shop == shopId then
			table.insert(baitRows, buildBaitRow(baitScroll, bait, #baitRows + 1))
		end
	end
	if #baitRows == 0 then
		addNote(baitScroll, "No bait for sale here.")
	end
end

local function refresh()
	dirty = false
	local coins, level = playerNumbers()
	coinsLabel.Text = "Coins: " .. PixelUI.FormatNumber(coins)
	levelLabel.Text = "Level " .. PixelUI.FormatNumber(level)
	for _, row in ipairs(rodRows) do
		row.update()
	end
	for _, row in ipairs(baitRows) do
		row.update()
	end
end

local function flush()
	flushQueued = false
	if isOpen and dirty then
		refresh()
	end
end

local function onStateChanged(key: string)
	if not REFRESH_KEYS[key] then
		return
	end
	dirty = true
	if isOpen and not flushQueued then
		flushQueued = true
		task.defer(flush)
	end
end

local function showTab(id: string)
	for pageId, page in pairs(pages) do
		page.Visible = pageId == id
	end
end

local function buildListPage(host: Frame, id: string): ScrollingFrame
	local page = PixelUI.Frame({ Name = id, Parent = host, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
	pages[id] = page
	local well = PixelUI.Frame({ Name = "Well", Parent = page, Size = UDim2.fromScale(1, 1), Color = Colors.PanelDark, Border = true })
	local scroll = PixelUI.Scroll({ Name = "List", Parent = well })
	PixelUI.Padding(scroll, 6)
	PixelUI.List(scroll, Enum.FillDirection.Vertical, 8)
	return scroll
end

-- ---------------------------------------------------------------- public API

function Window.Init(context: Ctx)
	if initialized then
		return
	end
	initialized = true
	ctx = context

	win = PixelUI.Window({
		Name = "ShopWindow",
		Parent = ctx.Gui,
		Title = string.format("%s's Rod Shop", npcName),
		Size = WINDOW_SIZE,
		OnClose = function()
			ctx.Windows.Close(Window.Name)
		end,
	})

	local header = PixelUI.Frame({ Name = "Header", Parent = win.Content, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 })
	tabs = PixelUI.Tabs({
		Parent = header,
		Size = UDim2.fromOffset(240, 34),
		Tabs = {
			{ id = "rods", text = "Rods", width = 110 },
			{ id = "bait", text = "Bait", width = 110 },
		},
		OnSelect = showTab,
	})
	coinsLabel = PixelUI.Label({
		Name = "Coins",
		Parent = header,
		Position = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(230, 24),
		XAlign = Enum.TextXAlignment.Right,
		Color = Colors.Coins,
	})
	levelLabel = PixelUI.Label({
		Name = "Level",
		Parent = header,
		Position = UDim2.new(1, -240, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(130, 24),
		XAlign = Enum.TextXAlignment.Right,
	})

	local host = PixelUI.Frame({
		Name = "Pages",
		Parent = win.Content,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -42),
		BackgroundTransparency = 1,
	})
	rodScroll = buildListPage(host, "rods")
	baitScroll = buildListPage(host, "bait")

	ctx.State.Changed:Connect(onStateChanged)
	tabs.Select("rods")
end

function Window.Open(payload: any?)
	if not initialized then
		return
	end
	if type(payload) == "table" then
		if type(payload.shop) == "string" then
			shopId = payload.shop
		end
		if type(payload.npcName) == "string" then
			npcName = payload.npcName
		end
	end
	win.Title.Text = string.format("%s's Rod Shop", npcName)
	if shopId ~= builtShop then
		rebuildRows()
		dirty = true
	end
	if not isOpen then
		isOpen = true
		win.SetOpen(true)
	end
	if dirty then
		refresh()
	end
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
