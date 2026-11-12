--!strict
-- Pixel-art UI theme: one palette, one pixel font, square corners everywhere.

local rgb = Color3.fromRGB

local Theme = {
	Font = Enum.Font.Arcade,
	TextSizes = { Tiny = 10, Small = 12, Body = 14, Title = 18, Big = 24, Huge = 32 },
	Border = 3,
	Shadow = 5,

	Colors = {
		Panel = rgb(38, 46, 72),
		PanelDark = rgb(24, 30, 48),
		PanelLight = rgb(56, 66, 98),
		Border = rgb(14, 18, 30),
		Shadow = rgb(10, 12, 22),

		Text = rgb(247, 241, 227),
		TextMuted = rgb(154, 165, 196),
		TextDark = rgb(28, 32, 48),

		Accent = rgb(242, 193, 78),
		Accent2 = rgb(79, 209, 197),
		Success = rgb(108, 203, 95),
		Danger = rgb(229, 83, 61),
		Info = rgb(90, 160, 240),

		Button = rgb(79, 209, 197),
		ButtonText = rgb(20, 30, 40),
		ButtonSecondary = rgb(96, 108, 150),
		ButtonSecondaryText = rgb(247, 241, 227),
		ButtonDanger = rgb(229, 83, 61),
		ButtonDisabled = rgb(70, 76, 96),

		XP = rgb(126, 220, 110),
		Coins = rgb(242, 193, 78),
		Silhouette = rgb(44, 50, 76),
		Water = rgb(63, 167, 214),
	},
}

return Theme
