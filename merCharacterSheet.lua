local myNAME = "merCharacterSheet"


local function initResearchRow(row)
    row.itemIcon = row:GetNamedChild("ItemIcon")
    row.itemName = row:GetNamedChild("ItemName")
    row.timer = ZO_TimerBar:New(row:GetNamedChild("TimerBar"))
    row.timer.direction = TIMER_BAR_COUNTS_DOWN
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


local function zoStats_CreateResearchSection(self)
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


local function onAddOnLoaded(eventCode, addOnName)
    if addOnName ~= myNAME then return end
    EVENT_MANAGER:UnregisterForEvent(myNAME, EVENT_ADD_ON_LOADED)

    local zoStats_CreateMountSection = STATS.CreateMountSection
    local zoStats_CreateActiveEffectsSection = STATS.CreateActiveEffectsSection

    STATS.CreateMountSection = zoStats_CreateActiveEffectsSection
    STATS.CreateActiveEffectsSection = function(self)
        zoStats_CreateMountSection(self)
        self:AddDivider()
        zoStats_CreateResearchSection(self)
    end
end


EVENT_MANAGER:RegisterForEvent(myNAME, EVENT_ADD_ON_LOADED, onAddOnLoaded)

