--!strict
-- Sell window: every fish in the bag sorted by value, a Sell button per fish and a two-step "Sell All".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))
local FishData = require(Shared:WaitForChild("FishData"))
local RarityData = require(Shared:WaitForChild("RarityData"))
local MutationData = require(Shared:WaitForChild("MutationData"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local PixelUI = require(script.Parent:WaitForChild("PixelUI"))
local PixelIcon = require(script.Parent:WaitForChild("PixelIcon"))

local Colors = Theme.Colors
local Sizes = Theme.TextSizes
local AtEnd = Enum.TextTruncate.AtEnd

type Response = { ok: boolean, message: string?, [string]: any }

type Ctx = {
	Gui: ScreenGui,
	State: typeof(require(script.Parent.Parent:WaitForChild("ClientState"))),
	Net: typeof(require(Shared:WaitForChild("Net"))),
	Windows: { Open: (name: string, payload: any?) -> (), Close: (name: string) -> (), CloseAll: () -> (), IsOpen: (name: string) -> boolean },
	Sounds: { Play: (name: string) -> () },
	Notify: (kind: string, text: string) -> (),
}

local Window = {}
Window.Name = "Sell"

local WINDOW_SIZE = UDim2.fromOffset(760, 480)
local ROW_HEIGHT = 54
local CONFIRM_SECONDS = 3
local DEFAULT_NPC = "Marlo"

local ctx: Ctx = nil :: any
local win: PixelUI.Window = nil :: any
local initialized = false
local isOpen = false
local stale = true
local flushQueued = false
local busy = false
local npcName = DEFAULT_NPC

local listScroll: ScrollingFrame = nil :: any
local emptyLabel: TextLabel = nil :: any
local summaryLabel: TextLabel = nil :: any
local sellAllButton: TextButton = nil :: any
local sellAllArmed = false
local sellAllToken = 0

-- ---------------------------------------------------------------- helpers

local function clearChildren(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

local function coloredText(text: string, color: Color3): string
	return string.format('<font color="#%s">%s</font>', color:ToHex(), text)
end

local function report(resp: Response, okText: string, failText: string)
	ctx.Notify(if resp.ok then "success" else "error", resp.message or (if resp.ok then okText else failText))
end

-- Serialises server calls so a double click can't sell the same fish twice.
local function request(name: string, ...: any): Response?
	if busy then
		return nil
	end
	busy = true
	local resp = ctx.Net.Invoke(name, ...)
	busy = false
	return resp
end

local function soldMessage(resp: Response): string
	local count, total = tonumber(resp.soldCount), tonumber(resp.total)
	if count and total then
		return string.format("Sold %s fish for %s coins.", PixelUI.FormatNumber(count), PixelUI.FormatNumber(total))
	end
	return "Sold!"
end

local function sell(selection: any)
	local resp = request("SellFish", selection)
	if not resp then
		return
	end
	if resp.ok then
		ctx.Sounds.Play("Coin")
	end
	report(resp, soldMessage(resp), "Couldn't sell that.")
end

-- ---------------------------------------------------------------- Sell All confirmation

local function updateSellAll()
	local armed = sellAllArmed and ctx.State.FishCount() > 0
	sellAllButton.Text = if armed then "Sell everything?" else "Sell All"
	sellAllButton:SetAttribute("BaseColor", if armed then Colors.ButtonDanger else Colors.Accent)
	sellAllButton:SetAttribute("TextBase", if armed then Colors.Text else Colors.TextDark)
	sellAllButton:SetAttribute("Disabled", ctx.State.FishCount() == 0)
end

local function disarmSellAll()
	sellAllArmed = false
	sellAllToken += 1
	updateSellAll()
end

local function onSellAll()
	if not sellAllArmed then
		-- First click: ask for confirmation, then let it expire.
		sellAllArmed = true
		sellAllToken += 1
		local token = sellAllToken
		updateSellAll()
		task.delay(CONFIRM_SECONDS, function()
			if sellAllToken == token then
				disarmSellAll()
			end
		end)
		return
	end
	disarmSellAll()
	sell("all")
end

-- ---------------------------------------------------------------- list

local function byValue(a: Types.CaughtFish, b: Types.CaughtFish): boolean
	if a.value ~= b.value then
		return a.value > b.value
	end
	if a.caughtAt ~= b.caughtAt then
		return a.caughtAt > b.caughtAt
	end
	return a.uid > b.uid
end

local function buildRow(parent: GuiObject, def: Types.FishDef, caught: Types.CaughtFish, order: number)
	local rarityColor = RarityData.Color(def.rarity)
	local mutation = MutationData.Get(caught.mutation)

	local row = PixelUI.Frame({
		Name = caught.uid,
		Parent = parent,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Color = Colors.Panel,
		Border = true,
		Thickness = 2,
		LayoutOrder = order,
	})
	PixelUI.Frame({ Name = "RarityBar", Parent = row, Size = UDim2.new(0, 5, 1, 0), Color = rarityColor })
	PixelIcon.Render(row, def, {
		shiny = caught.shiny,
		mutationColor = if mutation then mutation.color else nil,
		Size = UDim2.fromOffset(60, 40),
		Position = UDim2.fromOffset(16, 7),
	})

	PixelUI.Label({
		Parent = row,
		Text = def.name,
		Position = UDim2.fromOffset(86, 6),
		Size = UDim2.new(1, -86 - 236, 0, 20),
		Color = rarityColor,
		TextTruncate = AtEnd,
	})
	local details = { coloredText(PixelUI.FormatWeight(caught.weight), Colors.TextMuted) }
	if mutation then
		table.insert(details, coloredText(mutation.id, Util.Lighten(mutation.color, 0.3)))
	end
	if caught.shiny then
		table.insert(details, coloredText("Shiny!", Colors.Accent))
	end
	PixelUI.Label({
		Parent = row,
		Text = table.concat(details, ", "),
		Position = UDim2.fromOffset(86, 28),
		Size = UDim2.new(1, -86 - 236, 0, 16),
		TextSize = Sizes.Small,
		Rich = true,
		TextTruncate = AtEnd,
	})

	PixelUI.Label({
		Parent = row,
		Text = PixelUI.FormatNumber(caught.value) .. " c",
		Position = UDim2.new(1, -96, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(130, 20),
		XAlign = Enum.TextXAlignment.Right,
		Color = Colors.Coins,
	})
	PixelUI.Button({
		Name = "Sell",
		Parent = row,
		Text = "Sell",
		Size = UDim2.fromOffset(76, 32),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = Colors.Accent,
		TextColor = Colors.TextDark,
		OnClick = function()
			sell({ caught.uid })
		end,
	})
end

local function render()
	stale = false
	local profile = ctx.State.Profile
	local sorted = table.clone(if profile then profile.fish else {})
	table.sort(sorted, byValue)

	clearChildren(listScroll)
	local total = 0
	for index, caught in ipairs(sorted) do
		total += caught.value
		local def = FishData.Get(caught.id)
		if def then
			buildRow(listScroll, def, caught, index)
		end
	end

	emptyLabel.Visible = #sorted == 0
	summaryLabel.Text = string.format(
		"%s fish - Total: %s",
		PixelUI.FormatNumber(#sorted),
		coloredText(PixelUI.FormatNumber(total) .. " coins", Colors.Coins)
	)
	if #sorted == 0 then
		sellAllArmed = false
		sellAllToken += 1
	end
	updateSellAll()
end

local function flush()
	flushQueued = false
	if isOpen and stale then
		render()
	end
end

local function onStateChanged(key: string)
	if key ~= "profile" and key ~= "fish" then
		return
	end
	stale = true
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
		Name = "SellWindow",
		Parent = ctx.Gui,
		Title = "Sell Fish - " .. npcName,
		Size = WINDOW_SIZE,
		OnClose = function()
			ctx.Windows.Close(Window.Name)
		end,
	})

	local well = PixelUI.Frame({
		Name = "Well",
		Parent = win.Content,
		Size = UDim2.new(1, 0, 1, -62),
		Color = Colors.PanelDark,
		Border = true,
	})
	listScroll = PixelUI.Scroll({ Name = "Fish", Parent = well })
	PixelUI.Padding(listScroll, 6)
	PixelUI.List(listScroll, Enum.FillDirection.Vertical, 6)
	emptyLabel = PixelUI.Label({
		Name = "Empty",
		Parent = well,
		Size = UDim2.fromScale(1, 1),
		Text = "Nothing to sell. The sea awaits!",
		Color = Colors.TextMuted,
		XAlign = Enum.TextXAlignment.Center,
		Wrap = true,
		Visible = false,
		ZIndex = 2,
	})

	local footer = PixelUI.Frame({
		Name = "Footer",
		Parent = win.Content,
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
	})
	summaryLabel = PixelUI.Label({
		Name = "Summary",
		Parent = footer,
		Size = UDim2.new(1, -240, 1, 0),
		Rich = true,
		TextTruncate = AtEnd,
	})
	sellAllButton = PixelUI.Button({
		Name = "SellAll",
		Parent = footer,
		Text = "Sell All",
		Size = UDim2.fromOffset(224, 44),
		Position = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = Colors.Accent,
		TextColor = Colors.TextDark,
		OnClick = onSellAll,
	})

	ctx.State.Changed:Connect(onStateChanged)
end

function Window.Open(payload: any?)
	if not initialized then
		return
	end
	if type(payload) == "table" and type(payload.npcName) == "string" then
		npcName = payload.npcName
	else
		npcName = DEFAULT_NPC
	end
	win.Title.Text = "Sell Fish - " .. npcName
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
	disarmSellAll()
	win.SetOpen(false)
end

function Window.IsOpen(): boolean
	return isOpen
end

return Window
