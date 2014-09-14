local myNAME = "merCharacterSheet"
local mySAVEDVARS = myNAME .. "_SavedVariables"
local g_savedVars = {}


local function getStringIdName(stringId)
    if type(stringId) == "number" then
        for key, value in zo_insecurePairs(_G) do
            if value == stringId and type(key) == "string" and
                key:match("^SI_[0-9A-Z_]+$") then
                return key
            end
        end
    end
    return stringId
end


local function initResearchRow(row)
    row.itemIcon = row:GetNamedChild("ItemIcon")
    row.itemName = row:GetNamedChild("ItemName")
    row.timer = ZO_TimerBar:New(row:GetNamedChild("TimerBar"))
    row.timer.direction = TIMER_BAR_COUNTS_DOWN

    -- assign time format parameters directly, only because ZOS forgot some
    -- debug output in ZO_TimerBar:SetTimeFormatParameters, which would show
    -- up since these rows are not created until character sheet is shown
    row.timer.timeFormatStyle = TIME_FORMAT_STYLE_COLONS
    row.timer.timePrecision = TIME_FORMAT_PRECISION_TWELVE_HOUR
end


local function resetResearchRow(row)
    row.timer:Stop()
end


local function updateResearchGroup(group, craftingType)
    local numResearchSlots = GetMaxSimultaneousSmithingResearch(craftingType)
    local numResearching = 0
    local anchorControl = group:GetNamedChild("Header")

    local skillName = GetSkillLineInfo(GetCraftingSkillLineIndices(craftingType))
    local skillNameLabel = group:GetNamedChild("HeaderSkillName")
    skillNameLabel:SetText(zo_strformat(SI_SKILLS_ENTRY_LINE_NAME_FORMAT, skillName))

    for lineIndex = 1, GetNumSmithingResearchLines(craftingType) do
        local name, icon, numTraits = GetSmithingResearchLineInfo(craftingType, lineIndex)
        for traitIndex = 1, numTraits do
            local duration, remaining = GetSmithingResearchLineTraitTimes(craftingType, lineIndex, traitIndex)
            if remaining then
                numResearching = numResearching + 1
                local row = group.rowPool:AcquireObject(numResearching)
                local etc = GetFrameTimeSeconds() + remaining
                local traitType = GetSmithingResearchLineTraitInfo(craftingType, lineIndex, traitIndex) 
                local traitName = GetString("SI_ITEMTRAITTYPE", traitType)
                row:ClearAnchors()
                row:SetAnchor(TOPRIGHT, anchorControl, BOTTOMRIGHT)
                row.itemName:SetText(zo_strformat("<<1>>: <<2>>", name, traitName))
                row.itemIcon:SetTexture(icon)
                row.timer:Start(etc - duration, etc)
                anchorControl = row
            end
        end
    end

    local numResearchingLabel = group:GetNamedChild("HeaderNumResearching")
    if numResearching < numResearchSlots then
        numResearchingLabel:SetColor(STAT_LOWER_COLOR:UnpackRGBA())
    else
        numResearchingLabel:SetColor(STAT_HIGHER_COLOR:UnpackRGBA())
    end
    numResearchingLabel:SetText(zo_strformat("<<1>>/<<2>>", numResearching, numResearchSlots))

    -- release unused research rows
    for rowIndex = #(group.rowPool:GetActiveObjects()), numResearching + 1, -1 do
        group.rowPool:ReleaseObject(rowIndex)
    end
end


local ZO_Stats = getmetatable(STATS)
local MovableStats = ZO_Stats:Subclass()
MovableStats.__index = MovableStats
setmetatable(STATS, MovableStats)


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
    self.merShadowHeader = createShadowControl("ShadowHeader1", "ZO_StatsHeader")
    self.merShadowDivider = createShadowControl("ShadowDivider1", "ZO_WideHorizontalDivider")
    self.merShadowDivider:SetAnchor(BOTTOM, self.merShadowHeader, TOP, 0, 5)
end


function MovableStats:merAddSection(section)
    for savedIndex, headerId in ipairs(g_savedVars.sectionOrder) do
        if section.headerId == headerId then
            section.savedIndex = savedIndex
            break
        end
    end
    if not section.savedIndex then
        local savedIndex = #(g_savedVars.sectionOrder) + 1
        g_savedVars.sectionOrder[savedIndex] = section.headerId
        section.savedIndex = savedIndex
    end
    table.insert(self.merSections, section)
end


function MovableStats:merCreateResearchSection()
    local groupsByType = {}

    local function addResearchGroup(craftingType)
        local group = self:CreateControlFromVirtual("ResearchGroup", "merCharacterSheetResearchGroup")
        group.rowPool = ZO_ControlPool:New("merCharacterSheetResearchRow", group, "Row")
        group.rowPool:SetCustomFactoryBehavior(initResearchRow)
        group.rowPool:SetCustomResetBehavior(resetResearchRow)
        updateResearchGroup(group, craftingType)
        groupsByType[craftingType] = group
    end

    local function updateResearch(eventCode, craftingType, lineIndex, traitIndex)
        local group = groupsByType[craftingType]
        if group then
            updateResearchGroup(group, craftingType)
        end
    end

    local header = self:AddHeader(SI_SMITHING_TAB_RESEARCH)
    addResearchGroup(CRAFTING_TYPE_BLACKSMITHING)
    addResearchGroup(CRAFTING_TYPE_CLOTHIER)
    addResearchGroup(CRAFTING_TYPE_WOODWORKING)
    header:RegisterForEvent(EVENT_SMITHING_TRAIT_RESEARCH_COMPLETED, updateResearch)
    header:RegisterForEvent(EVENT_SMITHING_TRAIT_RESEARCH_STARTED, updateResearch)
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

    local function onDragStart(control, button)
        if self.merDragStartY then
            self.merShadowHeader:SetText(control:GetText())
            self.merShadowHeader:SetHandler("OnUpdate", updateShadowHeader)
            self.merShadowHeader:SetHidden(false)
            self.merShadowDivider:SetHidden(false)
            -- change dragged header color
            control:SetColor(ZO_SECOND_CONTRAST_TEXT:UnpackRGBA())
        end
    end

    local function onMouseDown(control, button)
        if button == 1 then
            local _, mouseY = GetUIMousePosition()
            self.merDragStartY = mouseY - control:GetTop()
        end
    end

    local function onMouseUp(control, button, upInside)
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
    local sectionA = self.merSections[indexA]
    local sectionB = self.merSections[indexB]
    local savedIndexA = sectionA.savedIndex
    local savedIndexB = sectionB.savedIndex
    sectionA.savedIndex = savedIndexB
    sectionB.savedIndex = savedIndexA
    self.merSections[indexA] = sectionB
    self.merSections[indexB] = sectionA
    g_savedVars.sectionOrder[savedIndexA] = sectionB.headerId
    g_savedVars.sectionOrder[savedIndexB] = sectionA.headerId
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


local function onAddOnLoaded(eventCode, addOnName)
    if addOnName ~= myNAME then return end
    EVENT_MANAGER:UnregisterForEvent(myNAME, EVENT_ADD_ON_LOADED)

    if type(_G[mySAVEDVARS]) ~= "table" then
        _G[mySAVEDVARS] = g_savedVars
    else
        g_savedVars = _G[mySAVEDVARS]
    end

    if type(g_savedVars.sectionOrder) ~= "table" then
        g_savedVars.sectionOrder = {}
    end
end


EVENT_MANAGER:RegisterForEvent(myNAME, EVENT_ADD_ON_LOADED, onAddOnLoaded)

