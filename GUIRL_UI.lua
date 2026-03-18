GUIRL = GUIRL or CUOR or {}
CUOR = GUIRL

local ADDON_NAME = ...
local frame
local RefreshUI
local eventFrame
local activeConsumables = {}
local trackedItemIDs = {}
local POLL_INTERVAL_SECONDS = 0.5
local MIN_FRAME_WIDTH = 520
local COLUMN_GAP = 6

local COLUMN_WIDTHS = {
    name = 186,
    qty = 40,
    price = 105,
    total = 105,
}

local function GetColumnPositions()
    local xName = 0
    local xQty = xName + COLUMN_WIDTHS.name + COLUMN_GAP
    local xPrice = xQty + COLUMN_WIDTHS.qty + COLUMN_GAP
    local xTotal = xPrice + COLUMN_WIDTHS.price + COLUMN_GAP

    return xName, xQty, xPrice, xTotal
end

local function FormatMoney(copper)
    if not copper or copper <= 0 then
        return "0g 0s 0c"
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperOnly = copper % 100

    return string.format("%dg %ds %dc", gold, silver, copperOnly)
end

local function TryAuctionatorPrice(itemID, itemLink)
    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        return nil
    end

    local api = Auctionator.API.v1

    if itemLink and api.GetAuctionPriceByItemLink then
        local ok, value = pcall(api.GetAuctionPriceByItemLink, ADDON_NAME, itemLink)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end

    if itemID and api.GetAuctionPriceByItemID then
        local ok, value = pcall(api.GetAuctionPriceByItemID, ADDON_NAME, itemID)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end

    return nil
end

local function RebuildConsumableIndexes()
    activeConsumables = {}
    trackedItemIDs = {}

    for _, consumable in ipairs(GUIRL.Consumables or {}) do
        if consumable.itemID and consumable.enabled ~= false then
            activeConsumables[#activeConsumables + 1] = consumable
            trackedItemIDs[consumable.itemID] = true
        end
    end
end

local function ExtractItemIDFromLink(itemLink)
    if not itemLink or type(itemLink) ~= "string" then
        return nil
    end

    local itemID = string.match(itemLink, "item:(%d+)")
    if itemID then
        return tonumber(itemID)
    end

    return nil
end

local function GetBagSlotCount(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID) or 0
    end

    if GetContainerNumSlots then
        return GetContainerNumSlots(bagID) or 0
    end

    return 0
end

local function GetBagItemID(bagID, slotID)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bagID, slotID)
    end

    if GetContainerItemID then
        return GetContainerItemID(bagID, slotID)
    end

    if GetContainerItemLink then
        local itemLink = GetContainerItemLink(bagID, slotID)
        return ExtractItemIDFromLink(itemLink)
    end

    return nil
end

local function GetBagItemStackCount(bagID, slotID)
    if C_Container and C_Container.GetContainerItemInfo then
        local slotInfo = C_Container.GetContainerItemInfo(bagID, slotID)
        if slotInfo and slotInfo.stackCount and slotInfo.stackCount > 0 then
            return slotInfo.stackCount
        end
    end

    if GetContainerItemInfo then
        local _, itemCount = GetContainerItemInfo(bagID, slotID)
        if itemCount and itemCount > 0 then
            return itemCount
        end
    end

    return 1
end

local function GetTrackedBagCounts()
    local trackedCounts = {}

    if GetItemCount then
        for itemID in pairs(trackedItemIDs) do
            trackedCounts[itemID] = GetItemCount(itemID) or 0
        end

        return trackedCounts
    end

    if C_Item and C_Item.GetItemCount then
        for itemID in pairs(trackedItemIDs) do
            trackedCounts[itemID] = C_Item.GetItemCount(itemID, false, false, false) or 0
        end

        return trackedCounts
    end

    for bagID = 0, (NUM_BAG_SLOTS or 4) do
        local slotCount = GetBagSlotCount(bagID)

        for slotID = 1, slotCount do
            local itemID = GetBagItemID(bagID, slotID)
            if itemID and trackedItemIDs[itemID] then
                local stackCount = GetBagItemStackCount(bagID, slotID)

                trackedCounts[itemID] = (trackedCounts[itemID] or 0) + stackCount
            end
        end
    end

    return trackedCounts
end

local function ResetUsageCounts()
    GUIRL_DB.usageCounts = {}
end

local function ResetTrackedData()
    if not GUIRL_DB then
        return
    end

    ResetUsageCounts()
    RebuildConsumableIndexes()
    GUIRL_DB.lastBagSnapshot = GetTrackedBagCounts()
    RefreshUI()
end

local function UpdateUsageFromBagDelta()
    if not GUIRL_DB or not GUIRL_DB.usageCounts then
        return
    end

    RebuildConsumableIndexes()

    local currentCounts = GetTrackedBagCounts()

    if not GUIRL_DB.lastBagSnapshot then
        GUIRL_DB.lastBagSnapshot = currentCounts
        return
    end

    local changed = false

    for itemID in pairs(trackedItemIDs) do
        local previousCount = GUIRL_DB.lastBagSnapshot[itemID] or 0
        local currentCount = currentCounts[itemID] or 0

        if currentCount < previousCount then
            local consumedAmount = previousCount - currentCount
            GUIRL_DB.usageCounts[itemID] = (GUIRL_DB.usageCounts[itemID] or 0) + consumedAmount
            changed = true
        end
    end

    GUIRL_DB.lastBagSnapshot = currentCounts

    if changed and frame and frame:IsShown() then
        RefreshUI()
    end
end

local function HandleRaidStateTransition()
    GUIRL_DB.lastBagSnapshot = GetTrackedBagCounts()

    if frame and frame:IsShown() then
        RefreshUI()
    end
end

local function GetItemDisplayName(consumable)
    if consumable.label and consumable.label ~= "" then
        return consumable.label
    end

    if consumable.itemID then
        local itemName = nil
        if C_Item and C_Item.GetItemInfo then
            itemName = C_Item.GetItemInfo(consumable.itemID)
        elseif GetItemInfo then
            itemName = GetItemInfo(consumable.itemID)
        end

        if itemName and itemName ~= "" then
            return itemName
        end
    end

    if consumable.itemID then
        return "Item " .. tostring(consumable.itemID)
    end

    return "Unknown"
end

local function GetItemPrice(itemID)
    if not itemID then
        return 0, "missing itemID"
    end

    local itemLink = nil
    if C_Item and C_Item.GetItemInfo then
        local _, link = C_Item.GetItemInfo(itemID)
        itemLink = link
    elseif GetItemInfo then
        local _, link = GetItemInfo(itemID)
        itemLink = link
    end

    local price = TryAuctionatorPrice(itemID, itemLink)
    if price then
        return price, "Auctionator"
    end

    return 0, "no price"
end

local function EnsureRows(requiredRows)
    frame.rows = frame.rows or {}

    local xName, xQty, xPrice, xTotal = GetColumnPositions()

    while #frame.rows < requiredRows do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(frame.content:GetWidth(), GUIRL.Settings.rowHeight)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", row, "LEFT", xName, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWidth(COLUMN_WIDTHS.name)
        row.nameText:SetWordWrap(false)

        row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.qtyText:SetPoint("LEFT", row, "LEFT", xQty, 0)
        row.qtyText:SetWidth(COLUMN_WIDTHS.qty)
        row.qtyText:SetJustifyH("RIGHT")
        row.qtyText:SetWordWrap(false)

        row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.priceText:SetPoint("LEFT", row, "LEFT", xPrice, 0)
        row.priceText:SetWidth(COLUMN_WIDTHS.price)
        row.priceText:SetJustifyH("RIGHT")
        row.priceText:SetWordWrap(false)

        row.totalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.totalText:SetPoint("LEFT", row, "LEFT", xTotal, 0)
        row.totalText:SetWidth(COLUMN_WIDTHS.total)
        row.totalText:SetJustifyH("RIGHT")
        row.totalText:SetWordWrap(false)

        frame.rows[#frame.rows + 1] = row
    end
end

function RefreshUI()
    if not frame then
        return
    end

    RebuildConsumableIndexes()

    local displayConsumables = {}
    for _, consumable in ipairs(activeConsumables) do
        local quantityUsed = GUIRL_DB and GUIRL_DB.usageCounts and GUIRL_DB.usageCounts[consumable.itemID] or 0
        if quantityUsed > 0 then
            displayConsumables[#displayConsumables + 1] = consumable
        end
    end

    EnsureRows(#displayConsumables)

    local yOffset = -2
    local grandTotal = 0

    for index, consumable in ipairs(displayConsumables) do
        local row = frame.rows[index]
        local itemName = GetItemDisplayName(consumable)
        local quantityUsed = GUIRL_DB and GUIRL_DB.usageCounts and GUIRL_DB.usageCounts[consumable.itemID] or 0
        local price = 0

        if quantityUsed > 0 then
            price = select(1, GetItemPrice(consumable.itemID)) or 0
        end

        local lineTotal = price * quantityUsed
        grandTotal = grandTotal + lineTotal

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, yOffset)

        row.nameText:SetText(itemName)
        row.qtyText:SetText(tostring(quantityUsed))
        row.priceText:SetText(FormatMoney(price))
        row.totalText:SetText(FormatMoney(lineTotal))

        yOffset = yOffset - GUIRL.Settings.rowHeight
        row:Show()
    end

    for index = #displayConsumables + 1, #frame.rows do
        frame.rows[index]:Hide()
    end

    frame.totalValue:SetText(FormatMoney(grandTotal))
end

local function BuildUI()
    if frame then
        return
    end

    if not GUIRL.Settings.frameWidth or GUIRL.Settings.frameWidth < MIN_FRAME_WIDTH then
        GUIRL.Settings.frameWidth = MIN_FRAME_WIDTH
    end

    frame = CreateFrame("Frame", "GUIRL_MainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(GUIRL.Settings.frameWidth, 330)
    frame:SetPoint(GUIRL.Settings.framePoint, UIParent, GUIRL.Settings.framePoint, GUIRL.Settings.frameX, GUIRL.Settings.frameY)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, point, x, y = self:GetPoint(1)
        GUIRL.Settings.framePoint = point or "CENTER"
        GUIRL.Settings.frameX = x or 0
        GUIRL.Settings.frameY = y or 0
    end)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -14)
    frame.title:SetText(GUIRL.Settings.title)

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -56)
    frame.content:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -56)
    frame.content:SetHeight(220)

    local xName, xQty, xPrice, xTotal = GetColumnPositions()

    frame.headerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerName:SetPoint("TOPLEFT", frame.content, "TOPLEFT", xName, 14)
    frame.headerName:SetWidth(COLUMN_WIDTHS.name)
    frame.headerName:SetJustifyH("LEFT")
    frame.headerName:SetText("Name")

    frame.headerQty = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerQty:SetPoint("TOPLEFT", frame.content, "TOPLEFT", xQty, 14)
    frame.headerQty:SetWidth(COLUMN_WIDTHS.qty)
    frame.headerQty:SetJustifyH("RIGHT")
    frame.headerQty:SetText("Qty")

    frame.headerPrice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerPrice:SetPoint("TOPLEFT", frame.content, "TOPLEFT", xPrice, 14)
    frame.headerPrice:SetWidth(COLUMN_WIDTHS.price)
    frame.headerPrice:SetJustifyH("RIGHT")
    frame.headerPrice:SetText("Unit Price")

    frame.headerTotal = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerTotal:SetPoint("TOPLEFT", frame.content, "TOPLEFT", xTotal, 14)
    frame.headerTotal:SetWidth(COLUMN_WIDTHS.total)
    frame.headerTotal:SetJustifyH("RIGHT")
    frame.headerTotal:SetText("Line Total")

    frame.headerSeparator = frame:CreateTexture(nil, "ARTWORK")
    frame.headerSeparator:SetColorTexture(1, 1, 1, 0.2)
    frame.headerSeparator:SetHeight(1)
    frame.headerSeparator:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, 0)
    frame.headerSeparator:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, 0)

    frame.totalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.totalLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 24)
    frame.totalLabel:SetText("Total Cost:")

    frame.totalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.totalValue:SetPoint("LEFT", frame.totalLabel, "RIGHT", 10, 0)
    frame.totalValue:SetText("0g 0s 0c")

    frame.resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.resetButton:SetSize(90, 22)
    frame.resetButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)
    frame.resetButton:SetText("Reset")
    frame.resetButton:SetScript("OnClick", ResetTrackedData)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(60, 22)
    frame.closeButton:SetPoint("RIGHT", frame.resetButton, "LEFT", -8, 0)
    frame.closeButton:SetText("Close")
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:Hide()
end

local function StartPolling()
    if eventFrame and eventFrame.pollingActive then
        return
    end

    eventFrame.pollingActive = true
    eventFrame.pollElapsed = 0

    eventFrame:SetScript("OnUpdate", function(_, elapsed)
        eventFrame.pollElapsed = eventFrame.pollElapsed + elapsed
        if eventFrame.pollElapsed < POLL_INTERVAL_SECONDS then
            return
        end

        eventFrame.pollElapsed = 0
        UpdateUsageFromBagDelta()
    end)
end

eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

eventFrame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event == "ADDON_LOADED" and loadedAddonName == ADDON_NAME then
        GUIRL_DB = GUIRL_DB or CUOR_DB or {}
        CUOR_DB = GUIRL_DB
        GUIRL_DB.settings = GUIRL_DB.settings or {}
        GUIRL_DB.usageCounts = GUIRL_DB.usageCounts or {}
        GUIRL_DB.lastBagSnapshot = GUIRL_DB.lastBagSnapshot or nil

        for key, value in pairs(GUIRL.Settings) do
            if GUIRL_DB.settings[key] == nil then
                GUIRL_DB.settings[key] = value
            end
        end

        GUIRL.Settings = GUIRL_DB.settings
        if not GUIRL.Settings.frameWidth or GUIRL.Settings.frameWidth < MIN_FRAME_WIDTH then
            GUIRL.Settings.frameWidth = MIN_FRAME_WIDTH
        end
        RebuildConsumableIndexes()
        BuildUI()
        HandleRaidStateTransition()
        StartPolling()
    end

    if event == "PLAYER_ENTERING_WORLD" and frame then
        HandleRaidStateTransition()
        RefreshUI()
    end

    if event == "ZONE_CHANGED_NEW_AREA" and frame then
        HandleRaidStateTransition()
    end

    if event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        UpdateUsageFromBagDelta()
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitToken = loadedAddonName
        if unitToken == "player" then
            UpdateUsageFromBagDelta()
        end
    end
end)

SLASH_GUIRL1 = "/guirl"
SlashCmdList.GUIRL = function()
    if not frame then
        BuildUI()
    end

    if frame:IsShown() then
        frame:Hide()
    else
        RefreshUI()
        frame:Show()
    end
end
