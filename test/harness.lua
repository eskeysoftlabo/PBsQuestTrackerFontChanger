-- Stub of just enough ESO client to exercise PBsQuestTrackerFontChanger.
local DIR = ADDON_DIR

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value) if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end; stringValues[_G[id]] = value end
function SafeAddVersion() end
function SafeAddString(id, value) stringValues[id] = value end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end

-- ---- chat / misc --------------------------------------------------------------------
local chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) chat[#chat + 1] = t; print("[chat] " .. t) end }
function d(t) print("[d] " .. tostring(t)) end
SLASH_COMMANDS = {}
local pendingCallLater = {}
function zo_callLater(fn, ms) pendingCallLater[#pendingCallLater + 1] = fn end
function FlushCallLater() local q = pendingCallLater; pendingCallLater = {}; for _, fn in ipairs(q) do fn() end end

local gamepadMode = true
function IsInGamepadPreferredMode() return gamepadMode end
function SetGamepadMode(v) gamepadMode = v end

function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i) return "PBsQuestTrackerFontChanger", "|cFF69B4PB\u{2019}s QuestTrackerFontChanger|r 1.2.0" end,
	}
end

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"
EVENT_GAMEPAD_PREFERRED_MODE_CHANGED = "EVENT_GAMEPAD_PREFERRED_MODE_CHANGED"
local handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, name, event, fn) handlers[event] = handlers[event] or {}; handlers[event][name] = fn end,
	UnregisterForEvent = function(_, name, event) if handlers[event] then handlers[event][name] = nil end end,
}
function Fire(event, ...) for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end end

-- ---- saved variables ----------------------------------------------------------------
SavedStore = {}
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedStore[name] = SavedStore[name] or {}
		local store = SavedStore[name]
		for k, v in pairs(defaults or {}) do if store[k] == nil then store[k] = DeepCopy(v) end end
		return store
	end,
}

-- ---- label controls -----------------------------------------------------------------
-- A font descriptor is either a named font object or "face|size|style".
local NAMED_FONTS = {
	ZoFontGamepadBold27 = { face = "$(GAMEPAD_BOLD_FONT)", size = 27, style = "soft-shadow-thick" },
	ZoFontGamepadBold22 = { face = "$(GAMEPAD_BOLD_FONT)", size = 22, style = "soft-shadow-thick" },
	ZoFontGamepad34 = { face = "$(GAMEPAD_MEDIUM_FONT)", size = 34, style = "soft-shadow-thick" },
	ZoFontGameShadow = { face = "$(BOLD_FONT)", size = 18, style = "soft-shadow-thin" },
}
-- The client scales gamepad sizes; 0.75 here so a bug that writes the raw fontdef number
-- back instead of the measured one shows up as a size change.
local GP_SCALE = 0.75

FontBuilds = {}
local function MakeLabel()
	local label = { font = nil, resolved = nil }
	function label:SetFont(descriptor)
		local named = NAMED_FONTS[descriptor]
		if named then
			local size = named.size
			if descriptor:find("Gamepad") then size = math.floor(named.size * GP_SCALE) end
			self.resolved = { face = named.face, size = size, style = named.style }
		else
			local face, size, style = descriptor:match("^([^|]+)|(%d+)|?(.*)$")
			assert(face, "unparseable descriptor: " .. tostring(descriptor))
			self.resolved = { face = face, size = tonumber(size), style = style ~= "" and style or nil }
			FontBuilds[descriptor] = (FontBuilds[descriptor] or 0) + 1
		end
		self.font = descriptor
	end
	function label:GetFont() return self.font end
	function label:GetFontFaceName() return self.resolved and self.resolved.face end
	function label:GetFontSize() return self.resolved and self.resolved.size end
	function label:GetFontStyle() return self.resolved and self.resolved.style or "" end
	function label:SetDimensions(w, h) label.height = h or 0 end
	function label:SetHeight(h) label.height = h end
	function label:GetHeight() return label.height or 0 end
	function label:SetHorizontalAlignment() end
	function label:SetVerticalAlignment() end
	return label
end

-- ---- tree nodes ---------------------------------------------------------------------
-- ZO_TreeControlNode carries the gap above its control as m_OffsetY, and ZO_TreeControl:Update
-- anchors each control's top to the previous control's bottom by that much.
local function MakeNode(offsetY)
	local node = { m_OffsetY = offsetY }
	function node:SetOffsetY(v) self.m_OffsetY = v end
	return node
end

-- QUEST_TRACKER_TREE_LINE_SPACING, per platform, from questtracker.lua.
local QUEST_SPACING = {
	Gamepad = { headerPool = 0, stepDescriptionPool = 16, conditionPool = 16 },
	Keyboard = { headerPool = 18, stepDescriptionPool = 2, conditionPool = 2 },
}

-- ---- object pool --------------------------------------------------------------------
local Pool = {}
Pool.__index = Pool
local function NewPool()
	return setmetatable({ active = {}, nextKey = 1 }, Pool)
end
function Pool:SetCustomAcquireBehavior(fn) self.customAcquireBehavior = fn end
function Pool:AcquireObject()
	local key = self.nextKey
	self.nextKey = key + 1
	local object = MakeLabel()
	self.active[key] = object
	if self.customAcquireBehavior then self.customAcquireBehavior(object, key) end
	return object, key
end
function Pool:ReleaseAllObjects() self.active = {} end
function Pool:GetActiveObjects() return self.active end

-- ---- the tracker --------------------------------------------------------------------
local PLATFORM_FONTS = {
	Gamepad = { headerPool = "ZoFontGamepadBold27", stepDescriptionPool = "ZoFontGamepadBold22", conditionPool = "ZoFontGamepad34" },
	Keyboard = { headerPool = "ZoFontGameShadow", stepDescriptionPool = "ZoFontGameShadow", conditionPool = "ZoFontGameShadow" },
}
-- ZO_FocusedQuestTrackerPanel: the top-level control the whole tracker hangs off. Anchored
-- once from XML and never re-anchored by the game, and its scale is never set.
DYNAMIC_EVENTS_TRACKER = { name = "ZO_DynamicEventsTracker_TL" }
local function MakePanel()
	local panel = { anchors = { { valid = true, point = "TOPRIGHT", relativeTo = DYNAMIC_EVENTS_TRACKER, relativePoint = "BOTTOMRIGHT", x = 0, y = 0, constrains = "XY" } }, scale = 1 }
	function panel:GetAnchor(i)
		local a = self.anchors[i + 1]
		if not a then return false end
		return true, a.point, a.relativeTo, a.relativePoint, a.x, a.y, a.constrains
	end
	function panel:ClearAnchors() self.anchors = {} end
	function panel:SetAnchor(point, relativeTo, relativePoint, x, y, constrains)
		self.anchors[#self.anchors + 1] = { valid = true, point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y, constrains = constrains }
	end
	function panel:GetScale() return self.scale end
	function panel:SetScale(v) self.scale = v end
	function panel:GetNamedChild() return nil end
	return panel
end

TreeViewUpdates = 0
local tracker = { headerPool = NewPool(), stepDescriptionPool = NewPool(), conditionPool = NewPool(), numTracked = 0, trackerPanel = MakePanel() }
local function PlatformFont(poolName) return PLATFORM_FONTS[IsInGamepadPreferredMode() and "Gamepad" or "Keyboard"][poolName] end
-- The game's own SetCustomAcquireBehavior, installed before any add-on loads.
for _, poolName in ipairs({ "headerPool", "stepDescriptionPool", "conditionPool" }) do
	tracker[poolName]:SetCustomAcquireBehavior(function(control)
		control:SetFont(PlatformFont(poolName))
		-- QUEST_HEADER_BASE_HEIGHT: gamepad gives the header a fixed box, nothing else.
		if poolName == "headerPool" then control:SetDimensions(nil, IsInGamepadPreferredMode() and 28 or 0) end
	end)
end
function tracker:ApplyPlatformStyle()
	for _, poolName in ipairs({ "headerPool", "stepDescriptionPool", "conditionPool" }) do
		for _, control in pairs(self[poolName]:GetActiveObjects()) do
			control:SetFont(PlatformFont(poolName))
			if poolName == "headerPool" then control:SetDimensions(nil, IsInGamepadPreferredMode() and 28 or 0) end
		end
	end
	self:UpdateTreeView()
end
function tracker:UpdateTreeView() TreeViewUpdates = TreeViewUpdates + 1 end
function tracker:GetNumTracked() return self.numTracked end
function tracker:TrackAQuest()
	self.headerPool:ReleaseAllObjects()
	self.stepDescriptionPool:ReleaseAllObjects()
	self.conditionPool:ReleaseAllObjects()
	self.numTracked = 1

	-- The game creates the tree node right after acquiring the label and sets its offset from
	-- its own constants, every time. Ours does the same, so a rebuild re-bases the spacing.
	local platform = IsInGamepadPreferredMode() and "Gamepad" or "Keyboard"
	for _, poolName in ipairs({ "headerPool", "stepDescriptionPool", "conditionPool", "conditionPool" }) do
		local control = self[poolName]:AcquireObject()
		control.m_TreeNode = MakeNode(QUEST_SPACING[platform][poolName])
	end

	self:UpdateTreeView()
end
FOCUSED_QUEST_TRACKER = tracker

-- ---- the ZO_HUDTracker_Base panels ---------------------------------------------------
-- ZO_PromotionalEventTracker (Golden Pursuits) and ZO_HouseInformationTracker: singletons
-- with a handful of fixed labels, styled only through ApplyPlatformStyle. No pools, no fixed
-- heights.
AnchorRefreshes = {}
-- ZO_Anchor, cut down to the offsets this add-on touches.
local function MakeAnchor(offsetX, offsetY)
	local anchor = { x = offsetX, y = offsetY }
	function anchor:GetOffsetX() return self.x end
	function anchor:GetOffsetY() return self.y end
	function anchor:GetOffsets() return self.x, self.y end
	function anchor:SetOffsets(x, y) self.x, self.y = x, y end
	return anchor
end

local function MakeHudTracker(name, labelFields, styles)
	local tracker = { name = name }
	for _, field in ipairs(labelFields) do
		tracker[field] = MakeLabel()
	end
	AnchorRefreshes[name] = 0
	function tracker:ApplyPlatformStyle(style)
		style = style or styles[IsInGamepadPreferredMode() and "Gamepad" or "Keyboard"]
		self.currentStyle = style
		for field, fontKey in pairs(labelFields.fonts) do
			self[field]:SetFont(style[fontKey])
		end
		self:RefreshAnchors()
	end
	function tracker:RefreshAnchors() AnchorRefreshes[name] = AnchorRefreshes[name] + 1 end
	-- What the client does while building the UI, before any add-on loads.
	function tracker:ApplyStock() self:ApplyPlatformStyle(styles[IsInGamepadPreferredMode() and "Gamepad" or "Keyboard"]) end
	return tracker
end

local HOUSE_FIELDS = { "headerLabel", "subLabel", "populationLabel", "tagsLabel" }
HOUSE_FIELDS.fonts = { headerLabel = "FONT_HEADER", subLabel = "FONT_SUBLABEL", populationLabel = "FONT_POPULATION", tagsLabel = "FONT_TAGS" }
-- The gamepad offsets from ZO_HouseInformationTracker:InitializeStyles and the gamepad
-- defaults ZO_HUDTracker_Base fills in. TOP_LEVEL / CONTAINER / HEADER anchors are in here
-- too, at offsets the add-on must not touch -- they place the panel, not its lines.
HOUSE_STYLE_GAMEPAD = {
	FONT_HEADER = "ZoFontGamepadBold27", FONT_SUBLABEL = "ZoFontGamepad34", FONT_POPULATION = "ZoFontGamepad34", FONT_TAGS = "ZoFontGamepad34",
	SUBLABEL_PRIMARY_ANCHOR = MakeAnchor(0, 10),
	POPULATION_HEADERLABEL_PRIMARY_ANCHOR = MakeAnchor(0, 10),
	POPULATION_SUBLABEL_PRIMARY_ANCHOR = MakeAnchor(0, 0),
	TAGS_LABEL_PRIMARY_ANCHOR = MakeAnchor(0, 0),
	TOP_LEVEL_SECONDARY_ANCHOR = MakeAnchor(-15, 0),
	CONTAINER_PRIMARY_ANCHOR = MakeAnchor(0, 0),
}
HOUSE_INFORMATION_TRACKER = MakeHudTracker("house", HOUSE_FIELDS, {
	Gamepad = HOUSE_STYLE_GAMEPAD,
	Keyboard = {
		FONT_HEADER = "ZoFontGameShadow", FONT_SUBLABEL = "ZoFontGameShadow", FONT_POPULATION = "ZoFontGameShadow", FONT_TAGS = "ZoFontGameShadow",
		SUBLABEL_PRIMARY_ANCHOR = MakeAnchor(0, 2),
		POPULATION_HEADERLABEL_PRIMARY_ANCHOR = MakeAnchor(10, 2),
		POPULATION_SUBLABEL_PRIMARY_ANCHOR = MakeAnchor(0, 0),
		TAGS_LABEL_PRIMARY_ANCHOR = MakeAnchor(0, 0),
		TOP_LEVEL_SECONDARY_ANCHOR = MakeAnchor(-15, 0),
	},
})

local PURSUIT_FIELDS = { "headerLabel", "subLabel", "progressLabel" }
PURSUIT_FIELDS.fonts = { headerLabel = "FONT_HEADER", subLabel = "FONT_SUBLABEL", progressLabel = "FONT_PROGRESS_LABEL" }
PURSUIT_STYLE_GAMEPAD = {
	FONT_HEADER = "ZoFontGamepadBold27", FONT_SUBLABEL = "ZoFontGamepad34", FONT_PROGRESS_LABEL = "ZoFontGamepad34",
	SUBLABEL_PRIMARY_ANCHOR = MakeAnchor(0, 10),
	PROGRESS_LABEL_PRIMARY_ANCHOR = MakeAnchor(0, 10),
	TOP_LEVEL_SECONDARY_ANCHOR = MakeAnchor(-15, 0),
}
PROMOTIONAL_EVENT_TRACKER = MakeHudTracker("pursuit", PURSUIT_FIELDS, {
	Gamepad = PURSUIT_STYLE_GAMEPAD,
	Keyboard = {
		FONT_HEADER = "ZoFontGameShadow", FONT_SUBLABEL = "ZoFontGameShadow", FONT_PROGRESS_LABEL = "ZoFontGameShadow",
		SUBLABEL_PRIMARY_ANCHOR = MakeAnchor(0, 2),
		PROGRESS_LABEL_PRIMARY_ANCHOR = MakeAnchor(0, 2),
		TOP_LEVEL_SECONDARY_ANCHOR = MakeAnchor(-15, 0),
	},
})

function HudApplyStock()
	HOUSE_INFORMATION_TRACKER:ApplyStock()
	PROMOTIONAL_EVENT_TRACKER:ApplyStock()
end

local inHouse = true
HOUSING_EDITOR_STATE = { IsHouseInstance = function() return inHouse end }
function SetInHouse(v) inHouse = v end

-- ---- LibHarvensAddonSettings --------------------------------------------------------
PanelRows = {}
LibHarvensAddonSettings = {
	ST_LABEL = "label", ST_CHECKBOX = "checkbox", ST_SLIDER = "slider", ST_DROPDOWN = "dropdown", ST_BUTTON = "button",
	AddAddon = function(_, title)
		local panel = { title = title }
		function panel:AddSetting(row) PanelRows[#PanelRows + 1] = row end
		function panel:UpdateControls() end
		return panel
	end,
}

-- ---- load the add-on ----------------------------------------------------------------
-- The client styles these panels while building the UI (ZO_PlatformStyle applies as soon as
-- ZO_HUDTracker_Base:InitializeStyles runs, at ZO_Ingame's EVENT_ADD_ON_LOADED), so it has
-- already happened by the time an add-on is loaded.
HudApplyStock()

dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/lang/jp.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/Settings.lua")
