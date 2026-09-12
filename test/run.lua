-- Behavioural tests for PB's QuestTrackerFontChanger.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload,
-- boot the PS5, log in. harness.lua stubs the part of the client the add-on actually touches
-- -- the quest tracker's three ZO_ControlPools, the two ZO_HUDTracker_Base panels and their
-- fixed labels, a LabelControl that parses "face|size|style", saved variables and
-- LibHarvensAddonSettings -- so the logic can be exercised here instead.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)
--
-- The stub deliberately scales gamepad font sizes by 0.75, the way the client scales $(GP_27)
-- and friends. A build that wrote the raw fontdef number back instead of the measured size
-- would look right against a 1:1 stub and change the text on a real client.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-54s got=%s want=%s", ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

local function FirstOf(poolName)
	for _, c in pairs(FOCUSED_QUEST_TRACKER[poolName]:GetActiveObjects()) do return c end
end
local function House(field) return HOUSE_INFORMATION_TRACKER[field] end
local function Pursuit(field) return PROMOTIONAL_EVENT_TRACKER[field] end
local function NodeOffset(poolName)
	local c = FirstOf(poolName)
	return c and c.m_TreeNode and c.m_TreeNode.m_OffsetY
end
local function CountBuilds()
	local n = 0
	for _ in pairs(FontBuilds) do n = n + 1 end
	return n
end

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsQuestTrackerFontChanger")
local addon = PBS_QUEST_TRACKER_FONT_CHANGER
check("version read from manifest", addon.version, "1.2.0")
check("quest pools hooked at load", addon.hooked.quest, true)
check("pursuit tracker hooked at load", addon.hooked.pursuit, true)
check("house tracker hooked at load", addon.hooked.house, true)
check("slash command registered", type(SLASH_COMMANDS["/pbquest"]), "function")
-- 1 explanation
-- + 11 quest (heading, note, checkbox, 3 size sliders, 3 layout sliders, 2 dropdowns)
-- + 7 pursuit + 7 house (heading, note, checkbox, 2 sliders, 2 dropdowns each)
-- + 3 shared (heading, reset, hint)
check("panel rows built", #PanelRows, 29)

print("\n== 2. defaults: nothing is written, in either tracker ==")
Fire(EVENT_PLAYER_ACTIVATED)
check("first apply is deferred past the loading screen", FirstOf("headerPool"), nil)
FlushCallLater()
FOCUSED_QUEST_TRACKER:TrackAQuest()
check("no font built", CountBuilds(), 0)
check("quest name still the game's named font", FirstOf("headerPool"):GetFont(), "ZoFontGamepadBold27")
check("quest goal still the game's named font", FirstOf("conditionPool"):GetFont(), "ZoFontGamepad34")
check("house name still the game's named font", House("headerLabel"):GetFont(), "ZoFontGamepadBold27")
check("house tags still the game's named font", House("tagsLabel"):GetFont(), "ZoFontGamepad34")
check("pursuit heading still the game's named font", Pursuit("headerLabel"):GetFont(), "ZoFontGamepadBold27")
check("pursuit progress still the game's named font", Pursuit("progressLabel"):GetFont(), "ZoFontGamepad34")

print("\n== 3. the measured size is the client's scaled size, not the fontdef number ==")
-- The harness scales gamepad fonts by 0.75, so ZoFontGamepadBold27 draws at 20.
check("quest name default measured", addon:DefaultSize("questName"), 20)
check("quest step default measured", addon:DefaultSize("questStep"), 16)
check("quest goal default measured", addon:DefaultSize("questGoal"), 25)
check("house name default measured", addon:DefaultSize("houseName"), 20)
check("house detail default measured", addon:DefaultSize("houseDetail"), 25)
check("pursuit name default measured", addon:DefaultSize("pursuitName"), 20)
check("pursuit detail default measured", addon:DefaultSize("pursuitDetail"), 25)

print("\n== 4. the three sections are independent ==")
SLASH_COMMANDS["/pbquest"]("quest name 40")
check("quest name written", FirstOf("headerPool"):GetFont(), "$(GAMEPAD_BOLD_FONT)|40|soft-shadow-thick")
check("quest step untouched", FirstOf("stepDescriptionPool"):GetFont(), "ZoFontGamepadBold22")
check("house name untouched by a quest command", House("headerLabel"):GetFont(), "ZoFontGamepadBold27")
check("pursuit heading untouched by a quest command", Pursuit("headerLabel"):GetFont(), "ZoFontGamepadBold27")

SLASH_COMMANDS["/pbquest"]("house name 44")
check("house name written", House("headerLabel"):GetFont(), "$(GAMEPAD_BOLD_FONT)|44|soft-shadow-thick")
check("house detail untouched", House("subLabel"):GetFont(), "ZoFontGamepad34")
check("quest name kept its own size", FirstOf("headerPool"):GetFontSize(), 40)
check("pursuit still untouched", Pursuit("headerLabel"):GetFont(), "ZoFontGamepadBold27")

SLASH_COMMANDS["/pbquest"]("pursuit detail 36")
check("pursuit activity name written", Pursuit("subLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|36|soft-shadow-thick")
check("pursuit progress written", Pursuit("progressLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|36|soft-shadow-thick")
check("pursuit heading untouched", Pursuit("headerLabel"):GetFont(), "ZoFontGamepadBold27")
check("house detail untouched by the pursuit command", House("subLabel"):GetFont(), "ZoFontGamepad34")
check("three fonts built, one per changed part", CountBuilds(), 3)

print("\n== 4b. the quest-name box grows with the quest name ==")
-- 28 * 40 / 20 = 56. Without this the 40pt name sits in a 28-tall box and the step
-- description below it is anchored over the top of it. The house labels have no fixed box.
check("quest name box grown", FirstOf("headerPool"):GetHeight(), 56)
check("quest step box untouched", FirstOf("stepDescriptionPool"):GetHeight(), 0)
check("house name box untouched", House("headerLabel"):GetHeight(), 0)
check("pursuit heading box untouched", Pursuit("headerLabel"):GetHeight(), 0)

print("\n== 4c. the gaps close up with the text ==")
-- The gaps are not part of the font: they are tree node offsets in the quest tracker and
-- anchor offsets in the HUD panels, and the game leaves them where they are when the font
-- changes. Each is scaled by the ratio of the text below it.
check("untouched roles keep the game's gap", NodeOffset("conditionPool"), 16)
SLASH_COMMANDS["/pbquest"]("quest goal 50")
-- 50 / 25 = 2.0, so the 16-point gap above each objective line doubles.
check("objective gap doubled", NodeOffset("conditionPool"), 32)
check("step gap untouched", NodeOffset("stepDescriptionPool"), 16)
SLASH_COMMANDS["/pbquest"]("quest goal 13")
-- ...and tightens when the text shrinks: 13 / 25 = 0.52, 16 * 0.52 = 8.32 -> 8.
check("objective gap tightened", NodeOffset("conditionPool"), 8)

-- The header's node is written once when the quest is created and never reset, so a naive
-- rescale on every update would compound. Three more updates must change nothing.
FOCUSED_QUEST_TRACKER:UpdateTreeView()
FOCUSED_QUEST_TRACKER:UpdateTreeView()
FOCUSED_QUEST_TRACKER:UpdateTreeView()
check("gap does not compound across updates", NodeOffset("conditionPool"), 8)

SLASH_COMMANDS["/pbquest"]("quest goal 25")
check("back to the default size restores the game's gap", NodeOffset("conditionPool"), 16)

print("\n== 4d. the HUD panels' gaps too, on the style anchors ==")
-- The "pursuit detail 36" in step 4 already moved this on its own: 10 * 36/25 = 14.4 -> 14.
check("pursuit gap followed the earlier size change", PURSUIT_STYLE_GAMEPAD.PROGRESS_LABEL_PRIMARY_ANCHOR:GetOffsetY(), 14)
SLASH_COMMANDS["/pbquest"]("pursuit detail 50")
check("pursuit progress gap doubled", PURSUIT_STYLE_GAMEPAD.PROGRESS_LABEL_PRIMARY_ANCHOR:GetOffsetY(), 20)
check("pursuit sub label gap doubled", PURSUIT_STYLE_GAMEPAD.SUBLABEL_PRIMARY_ANCHOR:GetOffsetY(), 20)
check("the panel's own placement is not touched", PURSUIT_STYLE_GAMEPAD.TOP_LEVEL_SECONDARY_ANCHOR:GetOffsetY(), 0)
check("the x offset survives", PURSUIT_STYLE_GAMEPAD.PROGRESS_LABEL_PRIMARY_ANCHOR:GetOffsetX(), 0)
-- Re-applying the platform style is what a mode change does; it must not compound either.
PROMOTIONAL_EVENT_TRACKER:ApplyPlatformStyle(PROMOTIONAL_EVENT_TRACKER.currentStyle)
PROMOTIONAL_EVENT_TRACKER:ApplyPlatformStyle(PROMOTIONAL_EVENT_TRACKER.currentStyle)
check("pursuit gap does not compound", PURSUIT_STYLE_GAMEPAD.PROGRESS_LABEL_PRIMARY_ANCHOR:GetOffsetY(), 20)
SLASH_COMMANDS["/pbquest"]("pursuit off")
check("off restores the game's gap", PURSUIT_STYLE_GAMEPAD.PROGRESS_LABEL_PRIMARY_ANCHOR:GetOffsetY(), 10)
SLASH_COMMANDS["/pbquest"]("pursuit on")
SLASH_COMMANDS["/pbquest"]("pursuit detail 36")

print("\n== 5. one house slider drives all three detail labels ==")
SLASH_COMMANDS["/pbquest"]("house detail 30")
check("sub label", House("subLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|30|soft-shadow-thick")
check("population label", House("populationLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|30|soft-shadow-thick")
check("tags label", House("tagsLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|30|soft-shadow-thick")
check("anchors settled after the change", AnchorRefreshes.house > 0, true)
check("the pursuit panel settled its own anchors too", AnchorRefreshes.pursuit > 0, true)

print("\n== 6. a rebuild of the quest tracker keeps the setting ==")
FOCUSED_QUEST_TRACKER:TrackAQuest()
check("quest name still ours after rebuild", FirstOf("headerPool"):GetFont(), "$(GAMEPAD_BOLD_FONT)|40|soft-shadow-thick")

print("\n== 7. the game restyling a HUD panel keeps the setting ==")
-- What a platform change or the game's own refresh does: our wrapper is on that method.
HOUSE_INFORMATION_TRACKER:ApplyPlatformStyle(HOUSE_INFORMATION_TRACKER.currentStyle)
PROMOTIONAL_EVENT_TRACKER:ApplyPlatformStyle(PROMOTIONAL_EVENT_TRACKER.currentStyle)
check("house name still ours", House("headerLabel"):GetFont(), "$(GAMEPAD_BOLD_FONT)|44|soft-shadow-thick")
check("pursuit detail still ours", Pursuit("progressLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|36|soft-shadow-thick")

print("\n== 8. shrinking below the default still applies ==")
SLASH_COMMANDS["/pbquest"]("quest name 12")
check("quest name shrunk", FirstOf("headerPool"):GetFontSize(), 12)
check("quest name box left alone when shrinking", FirstOf("headerPool"):GetHeight(), 28)

print("\n== 9. face and outline are per section ==")
addon:Settings("quest").face = "$(GAMEPAD_LIGHT_FONT)"
addon:Settings("quest").style = "thick-outline"
addon:Refresh("quest")
check("quest name face+style", FirstOf("headerPool"):GetFont(), "$(GAMEPAD_LIGHT_FONT)|12|thick-outline")
check("quest goal face+style", FirstOf("conditionPool"):GetFont(), "$(GAMEPAD_LIGHT_FONT)|25|thick-outline")
check("house face untouched", House("headerLabel"):GetFont(), "$(GAMEPAD_BOLD_FONT)|44|soft-shadow-thick")
check("pursuit face untouched", Pursuit("subLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|36|soft-shadow-thick")

addon:Settings("house").style = addon.STYLE_NONE
addon:Refresh("house")
check("house drops the style component", House("headerLabel"):GetFont(), "$(GAMEPAD_BOLD_FONT)|44")
check("quest outline kept", FirstOf("headerPool"):GetFontStyle(), "thick-outline")

print("\n== 10. off restores the game's own named fonts, per section ==")
SLASH_COMMANDS["/pbquest"]("pursuit off")
check("pursuit restored", Pursuit("subLabel"):GetFont(), "ZoFontGamepad34")
SLASH_COMMANDS["/pbquest"]("quest off")
check("quest name restored", FirstOf("headerPool"):GetFont(), "ZoFontGamepadBold27")
check("quest name box restored", FirstOf("headerPool"):GetHeight(), 28)
check("house still custom", House("headerLabel"):GetFont(), "$(GAMEPAD_BOLD_FONT)|44")
SLASH_COMMANDS["/pbquest"]("house off")
check("house name restored", House("headerLabel"):GetFont(), "ZoFontGamepadBold27")
check("house detail restored", House("populationLabel"):GetFont(), "ZoFontGamepad34")
check("house gaps restored", HOUSE_STYLE_GAMEPAD.POPULATION_SUBLABEL_PRIMARY_ANCHOR:GetOffsetY(), 0)
check("house sub label gap restored", HOUSE_STYLE_GAMEPAD.SUBLABEL_PRIMARY_ANCHOR:GetOffsetY(), 10)
SLASH_COMMANDS["/pbquest"]("on")
check("on puts them all back", FirstOf("headerPool"):GetFont(), "$(GAMEPAD_LIGHT_FONT)|12|thick-outline")
check("on puts the house back too", House("headerLabel"):GetFont(), "$(GAMEPAD_BOLD_FONT)|44")
check("on puts the pursuit back too", Pursuit("subLabel"):GetFont(), "$(GAMEPAD_MEDIUM_FONT)|36|soft-shadow-thick")

print("\n== 11. size sets everything in every tracker ==")
SLASH_COMMANDS["/pbquest"]("size 26")
check("quest name", FirstOf("headerPool"):GetFontSize(), 26)
check("quest goal", FirstOf("conditionPool"):GetFontSize(), 26)
check("house name", House("headerLabel"):GetFontSize(), 26)
check("house tags", House("tagsLabel"):GetFontSize(), 26)
check("pursuit heading", Pursuit("headerLabel"):GetFontSize(), 26)
check("pursuit progress", Pursuit("progressLabel"):GetFontSize(), 26)

print("\n== 12. reset ==")
SLASH_COMMANDS["/pbquest"]("reset")
check("quest back to the game's font", FirstOf("headerPool"):GetFont(), "ZoFontGamepadBold27")
check("quest gaps back to the game's", NodeOffset("conditionPool"), 16)
check("house gaps back to the game's", HOUSE_STYLE_GAMEPAD.SUBLABEL_PRIMARY_ANCHOR:GetOffsetY(), 10)
check("pursuit gaps back to the game's", PURSUIT_STYLE_GAMEPAD.SUBLABEL_PRIMARY_ANCHOR:GetOffsetY(), 10)
check("house back to the game's font", House("headerLabel"):GetFont(), "ZoFontGamepadBold27")
check("pursuit back to the game's font", Pursuit("progressLabel"):GetFont(), "ZoFontGamepad34")
check("quest face cleared", addon:Settings("quest").face, "")
check("house style cleared", addon:Settings("house").style, "")
check("measurement kept", addon:DefaultSize("questName"), 20)

print("\n== 13. keyboard mode has its own sizes ==")
addon:SetSizeFor("questName", 44)
addon:SetSizeFor("houseName", 44)
addon:SetSizeFor("pursuitName", 44)
addon:Refresh()
check("gamepad quest name 44", FirstOf("headerPool"):GetFontSize(), 44)
check("gamepad house name 44", House("headerLabel"):GetFontSize(), 44)
check("gamepad pursuit name 44", Pursuit("headerLabel"):GetFontSize(), 44)
SetGamepadMode(false)
Fire(EVENT_GAMEPAD_PREFERRED_MODE_CHANGED)
HudApplyStock()
FlushCallLater()
check("keyboard quest name untouched", FirstOf("headerPool"):GetFont(), "ZoFontGameShadow")
check("keyboard house name untouched", House("headerLabel"):GetFont(), "ZoFontGameShadow")
check("keyboard pursuit name untouched", Pursuit("headerLabel"):GetFont(), "ZoFontGameShadow")
check("keyboard default measured", addon:DefaultSize("questName"), 18)
SetGamepadMode(true)
Fire(EVENT_GAMEPAD_PREFERRED_MODE_CHANGED)
HudApplyStock()
FlushCallLater()
check("gamepad quest size comes back", FirstOf("headerPool"):GetFontSize(), 44)
check("gamepad house size comes back", House("headerLabel"):GetFontSize(), 44)
check("gamepad pursuit size comes back", Pursuit("headerLabel"):GetFontSize(), 44)

print("\n== 14. settings panel rows behave ==")
local sliders, dropdowns, checkboxes = {}, {}, {}
for _, row in ipairs(PanelRows) do
	if row.type == "slider" then sliders[#sliders + 1] = row end
	if row.type == "dropdown" then dropdowns[#dropdowns + 1] = row end
	if row.type == "checkbox" then checkboxes[#checkboxes + 1] = row end
end
-- Found by label rather than by position, so inserting a row somewhere does not silently
-- re-point these at the wrong setting.
local function RowFor(stringId)
	local wanted = GetString(_G[stringId])
	for _, row in ipairs(sliders) do
		if row.label == wanted then return row end
	end
end
check("ten sliders", #sliders, 10)
check("six dropdowns", #dropdowns, 6)
check("one checkbox per section", #checkboxes, 3)
check("quest name slider reads its size", RowFor("SI_PBSQTFC_SIZE_QUEST_NAME").getFunction(), 44)
check("pursuit name slider reads its size", RowFor("SI_PBSQTFC_SIZE_PURSUIT_NAME").getFunction(), 44)
check("house name slider reads its size", RowFor("SI_PBSQTFC_SIZE_HOUSE_NAME").getFunction(), 44)
RowFor("SI_PBSQTFC_SIZE_HOUSE_DETAIL").setFunction(31)
check("house detail slider set its size", House("tagsLabel"):GetFontSize(), 31)
check("quest untouched by the house slider", FirstOf("headerPool"):GetFontSize(), 44)
checkboxes[3].setFunction(false)
check("house checkbox turned the house off", House("headerLabel"):GetFont(), "ZoFontGamepadBold27")
check("quest checkbox untouched", FirstOf("headerPool"):GetFontSize(), 44)
check("pursuit checkbox untouched", Pursuit("headerLabel"):GetFontSize(), 44)
checkboxes[3].setFunction(true)

print("\n== 14b. the layout sliders move and scale the panel ==")
local panel = FOCUSED_QUEST_TRACKER.trackerPanel
local function PanelOffsets()
	local _, _, _, _, x, y = panel:GetAnchor(0)
	return x, y
end
check("panel starts where the game put it", select(1, PanelOffsets()), 0)
check("panel scale starts at 1", panel:GetScale(), 1)

RowFor("SI_PBSQTFC_POS_X").setFunction(-150)
RowFor("SI_PBSQTFC_POS_Y").setFunction(40)
RowFor("SI_PBSQTFC_SCALE").setFunction(80)
FlushCallLater()
local px, py = PanelOffsets()
check("moved left", px, -150)
check("moved down", py, 40)
check("scaled", panel:GetScale(), 0.8)
check("only one anchor is left on it", #panel.anchors, 1)
check("the game's own anchor point is kept", select(2, panel:GetAnchor(0)), "TOPRIGHT")
check("and its target", select(3, panel:GetAnchor(0)), DYNAMIC_EVENTS_TRACKER)

-- The offsets are a nudge from the game's own, not an absolute position, so re-applying must
-- not accumulate.
addon:RequestLayout()
addon:RequestLayout()
FlushCallLater()
check("the nudge does not accumulate", select(1, PanelOffsets()), -150)

checkboxes[1].setFunction(false)
FlushCallLater()
check("off puts the panel back", select(1, PanelOffsets()), 0)
check("off puts the scale back", panel:GetScale(), 1)
checkboxes[1].setFunction(true)
FlushCallLater()
check("on restores the move", select(1, PanelOffsets()), -150)

SLASH_COMMANDS["/pbquest"]("pos reset")
FlushCallLater()
check("pos reset puts it back", select(1, PanelOffsets()), 0)
check("but keeps the scale", panel:GetScale(), 0.8)
SLASH_COMMANDS["/pbquest"]("scale 100")
FlushCallLater()
check("scale 100 is the game's own", panel:GetScale(), 1)
SLASH_COMMANDS["/pbquest"]("pos -40 10")
SLASH_COMMANDS["/pbquest"]("scale 120")
FlushCallLater()
check("pos command moved it", select(2, PanelOffsets()), 10)
check("scale command scaled it", panel:GetScale(), 1.2)

print("\n== 14c. reset returns the panel as well as the fonts ==")
SLASH_COMMANDS["/pbquest"]("reset")
FlushCallLater()
check("panel back where the game put it", select(1, PanelOffsets()), 0)
check("and down too", select(2, PanelOffsets()), 0)
check("panel scale back to 1", panel:GetScale(), 1)
check("quest fonts back to the game's", FirstOf("headerPool"):GetFont(), "ZoFontGamepadBold27")
-- ...and the settings the later checks rely on are put back by hand.
SLASH_COMMANDS["/pbquest"]("pos -40 10")
SLASH_COMMANDS["/pbquest"]("scale 120")
addon:SetSizeFor("questName", 44)
addon:SetSizeFor("pursuitName", 44)
addon:SetSizeFor("houseDetail", 31)
addon:Refresh()
FlushCallLater()

print("\n== 15. saved variables survive a reload ==")
local store = SavedStore.PBsQuestTrackerFontChanger_Data
check("quest sizes persisted", store.quest.sizes.Gamepad.questName, 44)
check("house sizes persisted", store.house.sizes.Gamepad.houseDetail, 31)
check("pursuit sizes persisted", store.pursuit.sizes.Gamepad.pursuitName, 44)
check("layout persisted", store.quest.layout.Gamepad.offsetX, -40)
check("scale persisted", store.quest.layout.Gamepad.scale, 120)
check("measurements persisted outside the sections", store.measured.Gamepad.pursuitName, 20)

print("\n== 16. loading again over labels that already carry our font ==")
-- A real /reloadui rebuilds every control from XML, so the labels would be pristine. This
-- loads on top of the *modified* ones on purpose: it is the one way the measured default
-- could be replaced by one of our own sizes and the client's real number lost for good, which
-- is exactly what went wrong once in PB's NamePlateChanger.
store.quest.face = "$(STONE_TABLET_FONT)"
store.pursuit.face = "$(ANTIQUE_FONT)"
store.house.face = "$(CHAT_FONT)"
PBS_QUEST_TRACKER_FONT_CHANGER = nil
dofile(ADDON_DIR .. "/Main.lua")
Fire(EVENT_ADD_ON_LOADED, "PBsQuestTrackerFontChanger")
local reloaded = PBS_QUEST_TRACKER_FONT_CHANGER
check("quest retired face dropped", reloaded:Settings("quest").face, "")
check("pursuit retired face dropped", reloaded:Settings("pursuit").face, "")
check("house retired face dropped", reloaded:Settings("house").face, "")
check("our own font was not measured as the default", reloaded:DefaultSize("houseName"), 20)
check("nor for the detail labels", reloaded:DefaultSize("houseDetail"), 25)
check("nor in the pursuit panel", reloaded:DefaultSize("pursuitName"), 20)
-- ...and a genuinely pristine label is still measured after one was refused.
HudApplyStock()
check("a pristine label still measures", reloaded:DefaultSize("houseName"), 20)

print("\n== 17. status prints ==")
SLASH_COMMANDS["/pbquest"]("status")

print("\n== 18. usage prints for a typo rather than doing something ==")
SLASH_COMMANDS["/pbquest"]("quest wobble 30")

print(string.format("\n%s  (%d failures)", failures == 0 and "ALL PASS" or "FAILURES", failures))
os.exit(failures == 0 and 0 or 1)
