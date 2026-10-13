local Grimoire = Grimoire

-- Classic-era Blizzard art is the default look (see docs/adr/0001-prefer-classic-style-ui.md).
-- Keep every asset path here so a future skin can swap them in one place.
Grimoire.media = {
	statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
	flat = "Interface\\Buttons\\WHITE8X8",
	classicInset = 4,
	classicBackdrop = {
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	},
	dialogBackdrop = {
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	},
	dialogHeader = "Interface\\DialogFrame\\UI-DialogBox-Header",
	emptySlot = "Interface\\PaperDoll\\UI-Backpack-EmptySlot",
	rowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
	-- Round classic button (the minimap-button look, free-floating)
	roundButtonBorder = "Interface\\Minimap\\MiniMap-TrackingBorder",
	roundButtonBackground = "Interface\\Minimap\\UI-Minimap-Background",
	roundButtonHighlight = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
	-- Player frame status icons
	stateIcon = "Interface\\CharacterFrame\\UI-StateIcon",
	stateIconResting = { 0, 0.5, 0, 0.421875 },
	stateIconCombat = { 0.5, 1, 0, 0.484375 },
	leaderIcon = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
	pvpIcon = "Interface\\TargetingFrame\\UI-PVP-", -- .. "Horde" / "Alliance" / "FFA"
	-- Classic unit frame art: party member (ring portrait + bar slots), target frame
	-- and its elite/rare dragon variants, raid target markers.
	partyFrame = "Interface\\TargetingFrame\\UI-PartyFrame",
	targetFrame = "Interface\\TargetingFrame\\UI-TargetingFrame",
	targetFrameElite = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
	targetFrameRare = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
	targetFrameRareElite = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
	targetOfTargetFrame = "Interface\\TargetingFrame\\UI-TargetofTargetFrame",
	raidTargetIcons = "Interface\\TargetingFrame\\UI-RaidTargetingIcons",
	auraBorder = "Interface\\Buttons\\UI-Debuff-Overlays",
	nameBackground = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground",
}

function Grimoire.FormatAgo(timestamp)
	if not timestamp then return "never" end
	local seconds = time() - timestamp
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h ago"
	end
	return math.floor(seconds / 86400) .. "d ago"
end

function Grimoire.FormatMoney(copper)
	if GetMoneyString then
		return GetMoneyString(copper, true)
	end
	return GetCoinTextureString(copper)
end

-- The first of these Blizzard font objects that exists on this client. Forever lacks
-- some (no TextStatusBarTextSmall), and inheriting a missing one is a hard error.
function Grimoire.Font(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if _G[name] then
			return name
		end
	end
	return "GameFontHighlightSmall"
end

-- frame must inherit "BackdropTemplate".
function Grimoire.ApplyClassicBackdrop(frame)
	frame:SetBackdrop(Grimoire.media.classicBackdrop)
	frame:SetBackdropColor(0, 0, 0, 0.8)
	frame:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
end

-- Secret values ----------------------------------------------------------------
-- In combat, many unit/aura/cooldown values come back as opaque "secrets". They
-- can be passed straight into Blizzard widgets (StatusBar:SetValue,
-- FontString:SetText, …) but cannot be compared, used in arithmetic or branched
-- on. Always check before doing any of those.

local issecretvalue = issecretvalue

function Grimoire.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

function Grimoire.AnySecret(...)
	for i = 1, select("#", ...) do
		if Grimoire.IsSecret((select(i, ...))) then
			return true
		end
	end
	return false
end

function Grimoire.CreateBackground(frame, r, g, b, a)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(r or 0, g or 0, b or 0, a or 0.6)
	return bg
end

-- Replacing Blizzard UI --------------------------------------------------------------
-- Components that replace a default frame hide it here. It isn't destroyed: disabling
-- the component and /reload brings it back.
--
-- Forever runs Blizzard's retail UI, where Edit Mode manages many of these frames and
-- reads their parents and anchors. Reparenting them under an add-on frame taints Edit
-- Mode (seen: ADDON_ACTION_FORBIDDEN on TargetUnit) and makes Blizzard code fail on
-- secret values. So the frame stays where it is: its events and those of every frame
-- inside it are switched off (its bars update themselves), Blizzard's unit watch is
-- stopped, and a secure state driver keeps it hidden, in combat too.

local function UnregisterDeep(frame)
	frame:UnregisterAllEvents()
	for _, child in ipairs({ frame:GetChildren() }) do
		UnregisterDeep(child)
	end
end

function Grimoire:HideBlizzardFrame(frame)
	if not frame then return end
	self:RunOutOfCombat(function()
		UnregisterDeep(frame)
		pcall(UnregisterUnitWatch, frame)
		RegisterStateDriver(frame, "visibility", "hide")
		frame:Hide()
	end)
end
