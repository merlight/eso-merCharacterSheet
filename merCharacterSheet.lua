local myNAME = "merCharacterSheet"
local mySAVEDVARS = myNAME .. "_SavedVariables"

local g_savedVars = nil
local g_characterVars = nil
local g_researchGroups = {}


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
    self.merShadowHeader = createShadowControl("ShadowHeader", "ZO_StatsHeader")
    self.merShadowDivider = createShadowControl("ShadowDivider", "ZO_WideHorizontalDivider")
    self.merShadowDivider:SetAnchor(BOTTOM, self.merShadowHeader, TOP, 0, 5)
end


function MovableStats:merAddSection(section)
    local sectionOrder = g_savedVars:sub("sectionOrder")
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
    local hideResearch = g_characterVars:sub("hideResearch")
    local header = self:AddHeader(SI_SMITHING_TAB_RESEARCH)
    local container = self.scrollChild:CreateControl("$(parent)Research", CT_CONTROL)

    self:SetNextControlPadding(0)
    self:AddRawControl(container)
    container:SetResizeToFitDescendents(true)

    local function updateToggleButtonIcon(button)
        if hideResearch[button.craftingTypeName] then
            button.icon:SetColor(ZO_DEFAULT_DISABLED_COLOR:UnpackRGBA())
        else
            button.icon:SetColor(ZO_DEFAULT_ENABLED_COLOR:UnpackRGBA())
        end
    end

    local function onToggleButtonClicked(button, mouseButton)
        if mouseButton == 1 then
            local craftingTypeName = button.craftingTypeName
            hideResearch[craftingTypeName] = not hideResearch[craftingTypeName]
            updateToggleButtonIcon(button)
            self:merUpdateResearchGroupAnchors()
        end
    end

    local function addToggleButton(craftingTypeName, offsetX)
        local craftingType = _G[craftingTypeName]
        local skillType, skillIndex = GetCraftingSkillLineIndices(craftingType)
        local skillName = GetSkillLineInfo(skillType, skillIndex)
        local _, skillIcon = GetSkillAbilityInfo(skillType, skillIndex, 1)
        local button = CreateControlFromVirtual("$(parent)Button", header,
                                                "merCharacterSheetResearchToggleButton",
                                                craftingType)
        button.craftingTypeName = craftingTypeName
        button.tooltipText = zo_strformat(SI_SKILLS_ENTRY_LINE_NAME_FORMAT, skillName)
        button.icon = button:GetNamedChild("Icon")
        button.icon:SetTexture(skillIcon)
        button:SetAnchor(LEFT, nil, LEFT, offsetX, 2)
        button:SetHandler("OnClicked", onToggleButtonClicked)
        updateToggleButtonIcon(button)
    end

    local function addResearchGroup(craftingTypeName)
        local craftingType = _G[craftingTypeName]
        local group = CreateControlFromVirtual("$(parent)Group", container,
                                               "merCharacterSheetResearchGroup",
                                               craftingType)
        group.craftingType = craftingType
        group.craftingTypeName = craftingTypeName
        group.rowPool = ZO_ControlPool:New("merCharacterSheetResearchRow", group, "Row")
        group.rowPool:SetCustomFactoryBehavior(initResearchRow)
        group.rowPool:SetCustomResetBehavior(resetResearchRow)
        updateResearchGroup(group, craftingType)
        table.insert(g_researchGroups, group)
    end

    local headerTextWidth = header:GetTextWidth()
    addToggleButton("CRAFTING_TYPE_BLACKSMITHING", headerTextWidth + 15)
    addToggleButton("CRAFTING_TYPE_CLOTHIER", headerTextWidth + 55)
    addToggleButton("CRAFTING_TYPE_WOODWORKING", headerTextWidth + 95)

    addResearchGroup("CRAFTING_TYPE_BLACKSMITHING")
    addResearchGroup("CRAFTING_TYPE_CLOTHIER")
    addResearchGroup("CRAFTING_TYPE_WOODWORKING")

    self:merUpdateResearchGroupAnchors()

    local function updateResearch(eventCode, craftingType, lineIndex, traitIndex)
        for _, group in ipairs(g_researchGroups) do
            if eventCode == EVENT_SKILLS_FULL_UPDATE or
               craftingType == group.craftingType then
                updateResearchGroup(group, group.craftingType)
            end
        end
    end

    header:RegisterForEvent(EVENT_SKILLS_FULL_UPDATE, updateResearch)
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

    local function onDragStart(control, mouseButton)
        if self.merDragStartY then
            self.merShadowHeader:SetText(control:GetText())
            self.merShadowHeader:SetHandler("OnUpdate", updateShadowHeader)
            self.merShadowHeader:SetHidden(false)
            self.merShadowDivider:SetHidden(false)
            -- change dragged header color
            control:SetColor(ZO_SECOND_CONTRAST_TEXT:UnpackRGBA())
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
    local sectionOrder = g_savedVars:sub("sectionOrder")
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
    for _, group in ipairs(g_researchGroups) do
        group:ClearAnchors()
        if g_characterVars:get("hideResearch", group.craftingTypeName) then
            group:SetHidden(true)
        else
            group:SetAnchor(TOP, anchorControl, anchorPoint, 0, 5)
            group:SetHidden(false)
            anchorControl, anchorPoint = group, BOTTOM
        end
    end
end


local SavedTable = {}
SavedTable.__index = SavedTable


function SavedTable.get(tab, ...)
    for i = 1, select("#", ...) do
        if type(tab) ~= "table" then
            return nil
        end
        tab = tab[select(i, ...)]
    end
    return tab
end


function SavedTable.sub(tab, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local sub = tab[key]
        if type(sub) ~= "table" then
            sub = {}
            tab[key] = sub
        end
        tab = sub
    end
    return tab
end


local function onAddOnLoaded(eventCode, addOnName)
    if addOnName ~= myNAME then return end
    EVENT_MANAGER:UnregisterForEvent(myNAME, EVENT_ADD_ON_LOADED)

    g_savedVars = SavedTable.sub(_G, mySAVEDVARS)
    setmetatable(g_savedVars, SavedTable)

    g_characterVars = g_savedVars:sub("character:" .. GetUnitName("player"))
    setmetatable(g_characterVars, SavedTable)
end


EVENT_MANAGER:RegisterForEvent(myNAME, EVENT_ADD_ON_LOADED, onAddOnLoaded)

