--!strict
-- Procedural pixel-art fish icons. Each icon shape is a 12x8 character grid coloured from the fish
-- definition, rendered as a handful of Frames (horizontal runs are merged to keep instance counts low).
--   .  empty      A body colour      B accent colour     D darker body
--   W  eye white  K eye pupil

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local PixelIcon = {}

local GRID_W, GRID_H = 12, 8

local SHAPES: { [string]: { string } } = {
	Round = {
		"............",
		"....AAAAA...",
		"..AAAAAAAAB.",
		".AWKAAAAAABB",
		".AAAAABAAAB.",
		"..AAAAAAAAB.",
		"....AAAAA...",
		"......B.....",
	},
	Long = {
		"............",
		".....BBB....",
		".AAAAAAAAAB.",
		".AWKAAAAAABB",
		".AAAAAAAAAB.",
		"..DAAAAAD...",
		"....BB......",
		"............",
	},
	Flat = {
		"............",
		"..BBBBBBB...",
		".BAAAAAAAB..",
		".AWKAAAAAAB.",
		".AAAAAAAAAB.",
		".BAAAAAAAB..",
		"..BBBBBBB...",
		"............",
	},
	Eel = {
		"............",
		".AAAA.......",
		".AWKAAA.....",
		".AAAAAAAA...",
		"....DAAAAA..",
		"......AAAAA.",
		"........AAAB",
		"..........B.",
	},
	Ray = {
		"....A.......",
		"...AAA......",
		"..AAAAAB....",
		".AWKAAAAB...",
		".AAAAAAAABB.",
		"..AAAAA...BB",
		"...AAA......",
		"....A.......",
	},
	Odd = {
		"...AAAAA....",
		"..AAAAAAA...",
		".AAWKAAAAA..",
		".AAAAAAAAA..",
		"..AAAAAAA...",
		".B.B.B.B.B..",
		".B.B...B.B..",
		"............",
	},
}

local SPARKLES = { { 1, 10 }, { 6, 1 }, { 0, 3 } } -- {row, col}

export type IconOptions = {
	silhouette: boolean?,
	shiny: boolean?,
	mutationColor: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	LayoutOrder: number?,
}

local function pixel(parent: Frame, row: number, col: number, run: number, color: Color3, zIndex: number)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Position = UDim2.fromScale(col / GRID_W, row / GRID_H)
	frame.Size = UDim2.fromScale(run / GRID_W, 1 / GRID_H)
	frame.ZIndex = zIndex
	frame.Parent = parent
end

-- Renders the icon into a new Frame (aspect ratio 3:2) parented to `parent`.
function PixelIcon.Render(parent: GuiObject, def: Types.FishDef, options: IconOptions?): Frame
	local opts: IconOptions = options or {}
	local container = Instance.new("Frame")
	container.Name = "Icon_" .. def.id
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = opts.Size or UDim2.fromScale(1, 1)
	container.Position = opts.Position or UDim2.new()
	container.AnchorPoint = opts.AnchorPoint or Vector2.new()
	container.ZIndex = opts.ZIndex or 1
	container.LayoutOrder = opts.LayoutOrder or 0

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = GRID_W / GRID_H
	aspect.Parent = container

	local color1, color2 = def.color1, def.color2
	if opts.mutationColor then
		color1 = color1:Lerp(opts.mutationColor, 0.55)
		color2 = color2:Lerp(opts.mutationColor, 0.35)
	end
	if opts.shiny then
		color1 = Util.Lighten(color1, 0.3)
		color2 = Util.Lighten(color2, 0.3)
	end
	local palette: { [string]: Color3 } = {
		A = color1,
		B = color2,
		D = Util.Darken(color1, 0.3),
		W = Color3.new(1, 1, 1),
		K = Color3.fromRGB(20, 20, 30),
	}
	if opts.silhouette then
		for key in pairs(palette) do
			palette[key] = Theme.Colors.Silhouette
		end
	end

	local rows = SHAPES[def.shape] or SHAPES.Round
	local z = container.ZIndex + 1
	for r, rowText in ipairs(rows) do
		local col = 0
		while col < GRID_W do
			local ch = rowText:sub(col + 1, col + 1)
			if ch == "." then
				col += 1
			else
				local run = 1
				while col + run < GRID_W and rowText:sub(col + run + 1, col + run + 1) == ch do
					run += 1
				end
				pixel(container, r - 1, col, run, palette[ch] or color1, z)
				col += run
			end
		end
	end

	if opts.shiny and not opts.silhouette then
		for _, pos in ipairs(SPARKLES) do
			pixel(container, pos[1], pos[2], 1, Color3.new(1, 1, 1), z + 1)
		end
	end

	container.Parent = parent
	return container
end

return PixelIcon
