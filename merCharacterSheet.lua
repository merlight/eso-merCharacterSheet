local myNAME = "merCharacterSheet"
local mySAVEDVARS = myNAME .. "_SavedVariables"
local DT = merCharacterSheet.DeepTable
local EM = EVENT_MANAGER
local LOG2 = 0.6931471805599453

local g_characterName = nil
local g_characterVars = nil
local g_savedVars = nil

local g_researchGroupPool = nil
local g_researchGroupsByCraftingType = {
    -- initialization with non-nil values allows looping
    -- over the keys before actually creating the groups
    [CRAFTING_TYPE_BLACKSMITHING] = false,
    [CRAFTING_TYPE_CLOTHIER] = false,
    [CRAFTING_TYPE_WOODWORKING] = false,
    [CRAFTING_TYPE_JEWELRYCRAFTING] = false,
}

local craftingTypeToName = {
    [CRAFTING_TYPE_BLACKSMITHING] = "CRAFTING_TYPE_BLACKSMITHING",
    [CRAFTING_TYPE_CLOTHIER] = "CRAFTING_TYPE_CLOTHIER",
    [CRAFTING_TYPE_WOODWORKING] = "CRAFTING_TYPE_WOODWORKING",
    [CRAFTING_TYPE_JEWELRYCRAFTING] = "CRAFTING_TYPE_JEWELRYCRAFTING",
}

local CHAMPION_ATTRIBUTE_HUD_ICONS =
{
    [ATTRIBUTE_HEALTH] = "EsoUI/Art/Champion/champion_points_health_icon-HUD-32.dds",
    [ATTRIBUTE_MAGICKA] = "EsoUI/Art/Champion/champion_points_magicka_icon-HUD-32.dds",
    [ATTRIBUTE_STAMINA] = "EsoUI/Art/Champion/champion_points_stamina_icon-HUD-32.dds",
}


local function foreachAltCraft(func)
    local func = func[1]
    for altName, altVars in pairs(DT.sub(g_savedVars, "characters")) do
        if altName ~= g_characterName and type(altVars) == "table" then
            for craftingType, craftingTypeName in pairs(craftingTypeToName) do
                local craftingTypeVars = altVars[craftingTypeName]
                if type(craftingTypeVars) == "table" then
                    func(altName, craftingType, craftingTypeName, craftingTypeVars)
                end
            end
        end
    end
end


local function formatSkillName(skillType, skillIndex)
    local rawSkillName = GetSkillLineInfo(skillType, skillIndex)
    return zo_strformat(SI_SKILLS_ENTRY_LINE_NAME_FORMAT, rawSkillName)
end


local function getStringIdName(stringId)
    if type(stringId) == "number" then
        for key, value in zo_insecurePairs(_G) do
            if value == stringId and type(key) == "string" and
                key:find("^SI_[0-9A-Z_]+$") then
                return key
            end
        end
    end
    return stringId
end


local function initResearchRow(row)
    row.itemIcon = row:GetNamedChild("ItemIcon")
    row.itemName = row:GetNamedChild("ItemName")
    row.timer = merCharacterSheet.LogTimerBar:New(row:GetNamedChild("TimerBar"))
    row.timer.direction = TIMER_BAR_COUNTS_DOWN

    -- assign time format parameters directly, only because ZOS forgot some
    -- debug output in ZO_TimerBar:SetTimeFormatParameters, which would show
    -- up since these rows are not created until character sheet is shown
    row.timer.timeFormatStyle = TIME_FORMAT_STYLE_COLONS
    row.timer.timePrecision = TIME_FORMAT_PRECISION_TWELVE_HOUR
end


local function resetResearchRow(row)
    row.timer.onStop = nil
    row.timer:Stop()
end


local function setupResearchRow(row, anchorControl, craftingType, lineIndex, traitIndex)
    local name, icon = GetSmithingResearchLineInfo(craftingType, lineIndex)
    local traitType = GetSmithingResearchLineTraitInfo(craftingType, lineIndex, traitIndex)
    local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
    row:ClearAnchors()
    row:SetAnchor(TOPRIGHT, anchorControl, BOTTOMRIGHT)
    row.itemName:SetText(zo_strformat("<<1>>: <<2>>", name, traitName))
    row.itemIcon:SetTexture(icon)
end


local function setupResearchTimer(timer, duration, completion)
    -- base 2 logarithm of "research duration divided by 3 hours"
    -- for the first trait (6 hours without passives), it will be 1
    -- for the ninth trait (64 days without passives), it will be 9
    local logdur = math.log(math.max(duration / 10800, 1)) / LOG2
    timer.control:SetWidth(135 + 15 * logdur)
    timer:Start(completion - duration, completion)
end


local function initResearchGroup(group)
    group.rowPool = ZO_ControlPool:New("merCharacterSheetResearchRow", group, "Row")
    group.rowPool:SetCustomFactoryBehavior(initResearchRow)
    group.rowPool:SetCustomResetBehavior(resetResearchRow)
end


local function resetResearchGroup(group)
    group.rowPool:ReleaseAllObjects()
end


local function updateResearchGroupFromSavedVars(group)
    local craftingType = group.craftingType
    local numResearching = 0

    local skillName = formatSkillName(GetCraftingSkillLineIndices(craftingType))
    local skillNameLabel = group:GetNamedChild("HeaderSkillName")
    skillNameLabel:SetText(skillName)

    group.rowPool:ReleaseAllObjects()

    local researchSlots = group.savedVars["researchSlots"]
    if type(researchSlots) == "table" then

        -- ZO_TimerBar uses relative time since login. Shifting the assumed game
        -- start time one second backwards ensures the timer bar doesn't run out
        -- before reaching actual completion time, which could otherwise happen
        -- due to GetTimeStamp() and GetFrameTimeSeconds() sampling at different
        -- phases.
        local currentTime = GetTimeStamp()
        local frameTimeShift = currentTime - GetFrameTimeSeconds() - 1

        local anchorControl = group:GetNamedChild("Header")

        for _, info in ipairs(researchSlots) do
            if info.completion > currentTime then
                local row = group.rowPool:AcquireObject()
                setupResearchRow(row, anchorControl, craftingType, info.lineIndex, info.traitIndex)
                setupResearchTimer(row.timer, info.duration, info.completion - frameTimeShift)
                if group.characterName ~= g_characterName then
                    function row.timer:onStop()
                        updateResearchGroupFromSavedVars(group)
                    end
                end
                anchorControl = row
                numResearching = numResearching + 1
            end
        end
    end

    local numResearchingLabel = group:GetNamedChild("HeaderNumResearching")
    local numResearchSlots = tonumber(group.savedVars["maxResearchSlots"]) or 1
    if numResearching < numResearchSlots then
        numResearchingLabel:SetColor(STAT_LOWER_COLOR:UnpackRGBA())
    else
        numResearchingLabel:SetColor(STAT_HIGHER_COLOR:UnpackRGBA())
    end
    numResearchingLabel:SetText(zo_strformat("<<1>>/<<2>>", numResearching, numResearchSlots))
end


local function updateResearchSavedVars(craftingType)
    local craftingTypeName = craftingTypeToName[craftingType]
    local craftingVars = DT.sub(g_characterVars, craftingTypeName)
    local maxResearchSlots = GetMaxSimultaneousSmithingResearch(craftingType)

    craftingVars["researchSlots"] = nil
    craftingVars["maxResearchSlots"] = maxResearchSlots

    for lineIndex = 1, GetNumSmithingResearchLines(craftingType) do
        local _, _, numTraits = GetSmithingResearchLineInfo(craftingType, lineIndex)
        for traitIndex = 1, numTraits do
            local duration, remaining = GetSmithingResearchLineTraitTimes(craftingType, lineIndex, traitIndex)
            if remaining then
                local info = {
                    lineIndex = lineIndex,
                    traitIndex = traitIndex,
                    duration = duration,
                    completion = GetTimeStamp() + remaining,
                }
                DT.append(craftingVars, "researchSlots", info)
            end
        end
    end
end


local function createResearchGroup(characterName, craftingType, craftingTypeName)
    local group = g_researchGroupPool:AcquireObject()
    group.characterName = characterName
    group.craftingType = craftingType
    group.craftingTypeName = craftingTypeName
    group.savedVars = DT.sub(g_savedVars, "characters", characterName, craftingTypeName)
    group.characterNameLabel = group:GetNamedChild("HeaderCharacterName")
    group.characterNameLabel:SetText(group.characterName)
    updateResearchGroupFromSavedVars(group)
    return group
end


local ZO_Stats = getmetatable(STATS)
local MovableStats = ZO_Stats:Subclass()
MovableStats.__index = MovableStats
setmetatable(STATS, MovableStats)


function MovableStats:AddBountyRow(rowName)
    self:merAddChampionRow()
    return ZO_Stats.AddBountyRow(self, rowName)
end


function MovableStats:AddDivider()
    self.merLastSection = nil
    return ZO_Stats.AddDivider(self)
end


function MovableStats:AddHeader(text, optionalTemplate)
    local divider = self.lastControl
    local header = ZO_Stats.AddHeader(self, text, optionalTemplate)
    if not self.merLastSection then
        self.merLastSection =
        {
            dividerControl = divider,
            headerId = getStringIdName(text),
            headerControl = header,
            lastControl = header,
        }
        self:merAddSection(self.merLastSection)
        self:merMakeHeaderDraggable(header)
    end
    return header
end


function MovableStats:AddRawControl(control)
    local control = ZO_Stats.AddRawControl(self, control)
    if self.merLastSection then
        self.merLastSection.lastControl = control
    end
    return control
end


function MovableStats:CreateControlFromVirtual(controlType, template)
    local lastControl = self.lastControl
    local control = ZO_Stats.CreateControlFromVirtual(self, controlType, template)

    -- in ESO Update 6, the SI_STATS_ATTRIBUTES header is created by
    -- calling this function directly, instead of through AddHeader()
    if not self.merLastSection and template == "ZO_AttributesHeader" then
        self.merLastSection =
        {
            dividerControl = lastControl,
            headerId = "SI_STATS_ATTRIBUTES",
            headerControl = control,
            lastControl = control,
        }
        self:merAddSection(self.merLastSection)
        -- making this header draggable is not that simple,
        -- since it's now comprised of three labels
        --FIXME self:merMakeHeaderDraggable(control)
    end

    return control
end


function MovableStats:InitializeKeybindButtons()
    self:AddDivider()
    self:merCreateResearchSection()
    ZO_Stats.InitializeKeybindButtons(self)
    self:merSortSections()
    self:merUpdateAnchors()
end


function MovableStats:SetUpTitleSection()
    ZO_Stats.SetUpTitleSection(self)

    local function createShadowControl(name, template)
        local control = CreateControlFromVirtual("$(parent)", self.scrollChild, template, name)
        control:SetHidden(true)
        control:SetAlpha(0.6)
        control:SetExcludeFromResizeToFitExtents(true)
        return control
    end

    self.merSections = {}
    self.merShadowHeader = createShadowControl("ShadowHeader", "ZO_StatsHeader")
    self.merShadowDivider = createShadowControl("ShadowDivider", "ZO_WideHorizontalDivider")
    self.merShadowDivider:SetAnchor(BOTTOM, self.merShadowHeader, TOP, 0, 5)
end


function MovableStats:merAddChampionRow()
    local championRow = self:AddIconRow(GetString(SI_STAT_GAMEPAD_CHAMPION_POINTS_LABEL))

    local function updateChampionPoints()
        local pointsEarned = GetPlayerChampionPointsEarned()
        local pointsSpent = 0
        local nextPointAttribute

        for attribute, _ in next, CHAMPION_ATTRIBUTE_HUD_ICONS do
            pointsSpent = pointsSpent + GetNumSpentChampionPoints(attribute)
        end

        if GetNumChampionXPInChampionPoint(pointsEarned) then
            nextPointAttribute = GetChampionPointAttributeForRank(pointsEarned + 1)
        else
            nextPointAttribute = GetChampionPointAttributeForRank(pointsEarned)
        end

        if pointsSpent == pointsEarned then
            championRow.value:SetText(zo_strformat("<<1>>", pointsSpent))
        else
            championRow.value:SetText(zo_strformat("<<1>>/<<2>>", pointsSpent, pointsEarned))
        end

        championRow.icon:SetHidden(false)
        championRow.icon:SetTexture(CHAMPION_ATTRIBUTE_HUD_ICONS[nextPointAttribute])
    end

    championRow:RegisterForEvent(EVENT_UNSPENT_CHAMPION_POINTS_CHANGED, updateChampionPoints)
    updateChampionPoints()
end


function MovableStats:merAddSection(section)
    local sectionOrder = DT.sub(g_savedVars, "sectionOrder")
    for savedIndex, headerId in ipairs(sectionOrder) do
        if section.headerId == headerId then
            section.savedIndex = savedIndex
            break
        end
    end
    if not section.savedIndex then
        local savedIndex = #(sectionOrder) + 1
        sectionOrder[savedIndex] = section.headerId
        section.savedIndex = savedIndex
    end
    table.insert(self.merSections, section)
end


function MovableStats:merCreateResearchSection()
    local header = self:AddHeader(SI_SMITHING_TAB_RESEARCH)
    local container = self.scrollChild:CreateControl("$(parent)Research", CT_CONTROL)

    self:SetNextControlPadding(0)
    self:AddRawControl(container)
    container:SetResizeToFitDescendents(true)

    local function updateResearchToggleIcon(button, state)
        if state then
            button.icon:SetColor(ZO_DEFAULT_ENABLED_COLOR:UnpackRGBA())
        else
            button.icon:SetColor(ZO_DEFAULT_DISABLED_COLOR:UnpackRGBA())
        end
    end

    local function onResearchToggleClicked(button, mouseButton)
        if mouseButton == 1 then
            local craftingTypeName = button.craftingTypeName
            local state = DT.neg(g_characterVars, craftingTypeName, "showResearchProgress")
            updateResearchToggleIcon(button, state)
            self:merUpdateResearchGroupAnchors()
        end
    end

    local function addResearchToggle(craftingTypeName, offsetX)
        local craftingType = _G[craftingTypeName]
        local skillType, skillIndex = GetCraftingSkillLineIndices(craftingType)
        local skillName = formatSkillName(skillType, skillIndex)
        local _, skillIcon = GetSkillAbilityInfo(skillType, skillIndex, 1)
        local button = CreateControlFromVirtual("$(parent)Button", header,
                                                "merCharacterSheetResearchToggleButton",
                                                craftingType)
        button.craftingTypeName = craftingTypeName
        button.tooltipText = skillName
        button.icon = button:GetNamedChild("Icon")
        button.icon:SetTexture(skillIcon)
        button:SetAnchor(LEFT, nil, LEFT, offsetX, 2)
        button:SetHandler("OnClicked", onResearchToggleClicked)
        local state = DT.get(g_characterVars, craftingTypeName, "showResearchProgress")
        updateResearchToggleIcon(button, state)
    end

    local function createAltResearchGroup(altName, craftingType, craftingTypeName, craftingTypeVars)
        if craftingTypeVars["showResearchProgress"] then
            createResearchGroup(altName, craftingType, craftingTypeName)
        end
    end

    local altsResearchGroupsCreated = false

    local function updateAltsToggleState(button, state)
        if state then
            if not altsResearchGroupsCreated then
                altsResearchGroupsCreated = true
                foreachAltCraft { createAltResearchGroup }
                g_researchGroupPool:SortActiveObjects()
            end
            button:SetState(BSTATE_DISABLED)
        else
            button:SetState(BSTATE_NORMAL)
        end
    end

    local function onAltsToggleMouseUp(button, mouseButton, upInside)
        if mouseButton == 1 and upInside then
            local state = DT.neg(g_savedVars, "showAllCharactersResearch")
            updateAltsToggleState(button, state)
            self:merUpdateResearchGroupAnchors()
        end
    end

    local function addAltsToggle(offsetX)
        local button = CreateControlFromVirtual("$(parent)Alts", header,
                                                "merCharacterSheetAltsToggleButton")
        button.tooltipText = zo_strformat(SI_ADDON_MANAGER_CHARACTER_SELECT_ALL)
        button:SetAnchor(RIGHT, nil, RIGHT, offsetX, 2)
        button:SetHandler("OnMouseUp", onAltsToggleMouseUp)
        local state = DT.get(g_savedVars, "showAllCharactersResearch")
        updateAltsToggleState(button, state)
    end

    g_researchGroupPool = ZO_ControlPool:New("merCharacterSheetResearchGroup", container, "Group")
    g_researchGroupPool:SetCustomFactoryBehavior(initResearchGroup)
    g_researchGroupPool:SetCustomResetBehavior(resetResearchGroup)

    do
        local function compareResearchGroups(a, b)
            if a.characterName == b.characterName then
                return a.craftingType < b.craftingType
            elseif a.characterName == g_characterName then
                return true
            elseif b.characterName == g_characterName then
                return false
            else
                return a.characterName < b.characterName
            end
        end

        function g_researchGroupPool:SortActiveObjects()
            table.sort(self:GetActiveObjects(), compareResearchGroups)
        end
    end

    for craftingType, craftingTypeName in pairs(craftingTypeToName) do
        local group = createResearchGroup(g_characterName, craftingType, craftingTypeName)
        g_researchGroupsByCraftingType[group.craftingType] = group
    end

    g_researchGroupPool:SortActiveObjects()

    local offsetX = header:GetTextWidth() + 15

    for i, group in ipairs(g_researchGroupPool:GetActiveObjects()) do
        addResearchToggle(group.craftingTypeName, offsetX)
        offsetX = offsetX + 40
    end

    addAltsToggle(-20)

    self:merUpdateResearchGroupAnchors()
end


function MovableStats:merMakeHeaderDraggable(header)

    local function updateShadowHeader()
        local _, mouseY = GetUIMousePosition()
        local shadowTop = mouseY - self.merDragStartY
        for index, section in ipairs(self.merSections) do
            if header == section.headerControl then
                local sectionAbove = self.merSections[index - 1]
                local sectionBelow = self.merSections[index + 1]
                if sectionBelow and sectionBelow.headerControl:GetTop() + 5 < shadowTop then
                    self:merSwapSections(index, index + 1)
                    self:merUpdateAnchors()
                elseif sectionAbove and sectionAbove.headerControl:GetTop() - 2 > shadowTop then
                    self:merSwapSections(index, index - 1)
                    self:merUpdateAnchors()
                end
                break
            end
        end
        self.merShadowHeader:ClearAnchors()
        self.merShadowHeader:SetAnchor(TOP, nil, TOP, 0, shadowTop - self.scrollChild:GetTop())
    end

    local function onDragStart(control, mouseButton)
        if self.merDragStartY then
            self.merShadowHeader:SetText(control:GetText())
            self.merShadowHeader:SetHandler("OnUpdate", updateShadowHeader)
            self.merShadowHeader:SetHidden(false)
            self.merShadowDivider:SetHidden(false)
            -- change dragged header color
            control:SetColor(ZO_DISABLED_TEXT:UnpackRGBA())
        end
    end

    local function onMouseDown(control, mouseButton)
        if mouseButton == 1 then
            local _, mouseY = GetUIMousePosition()
            self.merDragStartY = mouseY - control:GetTop()
        end
    end

    local function onMouseUp(control, mouseButton, upInside)
        if self.merDragStartY then
            self.merShadowHeader:SetHandler("OnUpdate", nil)
            self.merShadowHeader:SetHidden(true)
            self.merShadowDivider:SetHidden(true)
            self.merDragStartY = nil
            -- restore default header color
            control:SetColor(ZO_SELECTED_TEXT:UnpackRGBA())
        end
    end

    header:SetMouseEnabled(true)
    header:SetHandler("OnDragStart", onDragStart)
    header:SetHandler("OnMouseDown", onMouseDown)
    header:SetHandler("OnMouseUp", onMouseUp)
end


function MovableStats:merSortSections()
    local function sectionComp(a, b)
        return a.savedIndex < b.savedIndex
    end
    table.sort(self.merSections, sectionComp)
end


function MovableStats:merSwapSections(indexA, indexB)
    local sectionOrder = DT.sub(g_savedVars, "sectionOrder")
    local sectionA = self.merSections[indexA]
    local sectionB = self.merSections[indexB]
    local savedIndexA = sectionA.savedIndex
    local savedIndexB = sectionB.savedIndex
    sectionA.savedIndex = savedIndexB
    sectionB.savedIndex = savedIndexA
    self.merSections[indexA] = sectionB
    self.merSections[indexB] = sectionA
    sectionOrder[savedIndexA] = sectionB.headerId
    sectionOrder[savedIndexB] = sectionA.headerId
end


function MovableStats:merUpdateAnchors()
    local anchorControl = nil
    for index, section in ipairs(self.merSections) do
        section.dividerControl:ClearAnchors()
        if anchorControl == nil then
            section.dividerControl:SetAnchor(TOP, anchorControl, TOP, 0, 2)
        else
            section.dividerControl:SetAnchor(TOP, anchorControl, BOTTOM, 0, 15)
        end
        anchorControl = section.lastControl
    end
end


function MovableStats:merUpdateResearchGroupAnchors()
    local anchorControl, anchorPoint = nil, TOP
    local showAll = DT.get(g_savedVars, "showAllCharactersResearch")
    local lastName = (showAll and "" or g_characterName)
    for _, group in ipairs(g_researchGroupPool:GetActiveObjects()) do
        local canShow = (showAll or group.characterName == g_characterName)
        group:ClearAnchors()
        if canShow and group.savedVars["showResearchProgress"] then
            group:SetAnchor(TOP, anchorControl, anchorPoint, 0, 5)
            group:SetHidden(false)
            group.characterNameLabel:SetHidden(lastName == group.characterName)
            lastName = group.characterName
            anchorControl, anchorPoint = group, BOTTOM
        else
            group:SetHidden(true)
        end
    end
end


local announceAltResearchCompleted
do
    local eventTag = myNAME .. "_AltResearchCompleted"
    local maxCheckInterval = 168 * 3600 -- one week is more than enough
    local lastCheckTime = GetTimeStamp()
    local nextCheckTime = -1
    local currentTime = nil

    local function checkResearch(altName, craftingType, researchIndex, researchInfo)
        local completion = researchInfo.completion
        if completion > currentTime then
            if nextCheckTime > completion then
                nextCheckTime = completion
            end
        elseif completion > lastCheckTime then
            ZO_AlertEvent(EVENT_SMITHING_TRAIT_RESEARCH_COMPLETED, craftingType,
                          researchInfo.lineIndex,  researchInfo.traitIndex)
        end
    end

    local function checkCraft(altName, craftingType, craftingTypeName, craftingTypeVars)
        local showResearchProgress = craftingTypeVars["showResearchProgress"]
        local researchSlots = craftingTypeVars["researchSlots"]
        if showResearchProgress and type(researchSlots) == "table" then
            for index, info in ipairs(researchSlots) do
                checkResearch(altName, craftingType, index, info)
            end
        end
    end

    function announceAltResearchCompleted()
        EM:UnregisterForUpdate(eventTag)

        currentTime = GetTimeStamp()
        nextCheckTime = currentTime + maxCheckInterval

        foreachAltCraft { checkCraft }
        lastCheckTime = currentTime

        if nextCheckTime < currentTime + maxCheckInterval then
            local ms = (nextCheckTime - currentTime) * 1000
            EM:RegisterForUpdate(eventTag, ms, announceAltResearchCompleted)
        end
    end
end


local function onRefreshAllResearch(eventCode)
    if eventCode == EVENT_PLAYER_ACTIVATED then
        EM:UnregisterForEvent(myNAME, eventCode)
        announceAltResearchCompleted()
    end
    for craftingType, group in pairs(g_researchGroupsByCraftingType) do
        updateResearchSavedVars(craftingType)
        if group then -- false until character sheet is shown
            updateResearchGroupFromSavedVars(group)
        end
    end
end


local function onRefreshOneResearch(eventCode, craftingType, lineIndex, traitIndex)
    updateResearchSavedVars(craftingType)
    local group = g_researchGroupsByCraftingType[craftingType]
    if group then -- false until character sheet is shown
        updateResearchGroupFromSavedVars(group)
    end
end


local function onAddOnLoaded(eventCode, addOnName)
    if addOnName ~= myNAME then return end
    EM:UnregisterForEvent(myNAME, eventCode)

    g_savedVars = DT.sub(_G, mySAVEDVARS)
    g_characterName = GetUnitName("player")
    g_characterVars = DT.sub(g_savedVars, "characters", g_characterName)

    -- delete settings from version <= 1.4
    DT.del(g_savedVars, "character:" .. g_characterName)

    EM:RegisterForEvent(myNAME, EVENT_PLAYER_ACTIVATED, onRefreshAllResearch)
    EM:RegisterForEvent(myNAME, EVENT_SKILLS_FULL_UPDATE, onRefreshAllResearch)
    EM:RegisterForEvent(myNAME, EVENT_SMITHING_TRAIT_RESEARCH_CANCELED, onRefreshOneResearch)
    EM:RegisterForEvent(myNAME, EVENT_SMITHING_TRAIT_RESEARCH_COMPLETED, onRefreshOneResearch)
    EM:RegisterForEvent(myNAME, EVENT_SMITHING_TRAIT_RESEARCH_STARTED, onRefreshOneResearch)
    EM:RegisterForEvent(myNAME, EVENT_SMITHING_TRAIT_RESEARCH_TIMES_UPDATED, onRefreshAllResearch)
end


EM:RegisterForEvent(myNAME, EVENT_ADD_ON_LOADED, onAddOnLoaded)
