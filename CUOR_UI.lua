CUOR = CUOR or {}

local ADDON_NAME = ...
local frame
local RefreshUI
local activeConsumables = {}
local trackedItemIDs = {}
local wasInRaidInstance = false

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

local function TryTSMPrice(itemID)
    if not CUOR.Settings.allowTSMFallback then
        return nil
    end

    if not TSM_API or not TSM_API.GetCustomPriceValue or not itemID then
        return nil
    end

    local itemString = "i:" .. tostring(itemID)
    local ok, value = pcall(TSM_API.GetCustomPriceValue, "dbmarket", itemString)
    if ok and type(value) == "number" and value > 0 then
        return value
    end

    return nil
end

local function RebuildConsumableIndexes()
    activeConsumables = {}
    trackedItemIDs = {}

    for _, consumable in ipairs(CUOR.Consumables or {}) do
        if consumable.itemID and consumable.enabled ~= false then
            activeConsumables[#activeConsumables + 1] = consumable
            trackedItemIDs[consumable.itemID] = true
        end
    end
end

local function IsInRaidInstance()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

local function IsTrackingAllowedNow()
    if CUOR.Settings.trackInRaidOnly then
        return IsInRaidInstance()
    end

    return true
end

local function GetTrackedBagCounts()
    local trackedCounts = {}

    for bagID = 0, (NUM_BAG_SLOTS or 4) do
        local slotCount = 0
        if C_Container and C_Container.GetContainerNumSlots then
            slotCount = C_Container.GetContainerNumSlots(bagID) or 0
        end

        for slotID = 1, slotCount do
            local itemID = C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bagID, slotID)
            if itemID and trackedItemIDs[itemID] then
                local stackCount = 1
                if C_Container and C_Container.GetContainerItemInfo then
                    local slotInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                    if slotInfo and slotInfo.stackCount and slotInfo.stackCount > 0 then
                        stackCount = slotInfo.stackCount
                    end
                end

                trackedCounts[itemID] = (trackedCounts[itemID] or 0) + stackCount
            end
        end
    end

    return trackedCounts
end

local function ResetUsageCounts()
    CUOR_DB.usageCounts = {}
end

local function UpdateUsageFromBagDelta()
    if not CUOR_DB or not CUOR_DB.usageCounts then
        return
    end

    local currentCounts = GetTrackedBagCounts()

    if not CUOR_DB.lastBagSnapshot then
        CUOR_DB.lastBagSnapshot = currentCounts
        return
    end

    local trackingAllowed = IsTrackingAllowedNow()
    local changed = false

    for itemID in pairs(trackedItemIDs) do
        local previousCount = CUOR_DB.lastBagSnapshot[itemID] or 0
        local currentCount = currentCounts[itemID] or 0

        if trackingAllowed and currentCount < previousCount then
            local consumedAmount = previousCount - currentCount
            CUOR_DB.usageCounts[itemID] = (CUOR_DB.usageCounts[itemID] or 0) + consumedAmount
            changed = true
        end
    end

    CUOR_DB.lastBagSnapshot = currentCounts

    if changed and frame and frame:IsShown() then
        RefreshUI()
    end
end

local function HandleRaidStateTransition()
    local inRaidInstance = IsInRaidInstance()

    if CUOR.Settings.autoResetOnRaidEnter and inRaidInstance and not wasInRaidInstance then
        ResetUsageCounts()
    end

    wasInRaidInstance = inRaidInstance
    CUOR_DB.lastBagSnapshot = GetTrackedBagCounts()

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

    local tsmPrice = TryTSMPrice(itemID)
    if tsmPrice then
        return tsmPrice, "TSM"
    end

    return 0, "no price"
end

local function EnsureRows()
    frame.rows = frame.rows or {}

    local requiredRows = #activeConsumables
    while #frame.rows < requiredRows do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(frame.content:GetWidth(), CUOR.Settings.rowHeight)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWidth(170)

        row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.qtyText:SetPoint("LEFT", row.nameText, "RIGHT", 8, 0)
        row.qtyText:SetWidth(50)
        row.qtyText:SetJustifyH("RIGHT")

        row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.priceText:SetPoint("LEFT", row.qtyText, "RIGHT", 8, 0)
        row.priceText:SetWidth(100)
        row.priceText:SetJustifyH("RIGHT")

        row.totalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.totalText:SetPoint("LEFT", row.priceText, "RIGHT", 8, 0)
        row.totalText:SetWidth(100)
        row.totalText:SetJustifyH("RIGHT")

        frame.rows[#frame.rows + 1] = row
    end
end

function RefreshUI()
    if not frame then
        return
    end

    RebuildConsumableIndexes()
    EnsureRows()

    local yOffset = -2
    local grandTotal = 0

    for index, consumable in ipairs(activeConsumables) do
        local row = frame.rows[index]
        local itemName = GetItemDisplayName(consumable)
        local quantityUsed = CUOR_DB and CUOR_DB.usageCounts and CUOR_DB.usageCounts[consumable.itemID] or 0
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

        yOffset = yOffset - CUOR.Settings.rowHeight
        row:Show()
    end

    for index = #activeConsumables + 1, #frame.rows do
        frame.rows[index]:Hide()
    end

    frame.totalValue:SetText(FormatMoney(grandTotal))
end

local function BuildUI()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "CUOR_MainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(CUOR.Settings.frameWidth, 330)
    frame:SetPoint(CUOR.Settings.framePoint, UIParent, CUOR.Settings.framePoint, CUOR.Settings.frameX, CUOR.Settings.frameY)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, point, x, y = self:GetPoint(1)
        CUOR.Settings.framePoint = point or "CENTER"
        CUOR.Settings.frameX = x or 0
        CUOR.Settings.frameY = y or 0
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
    frame.title:SetText(CUOR.Settings.title)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.subtitle:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)
    frame.subtitle:SetText("Name            Qty      Unit Price      Line Total")

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -56)
    frame.content:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -56)
    frame.content:SetHeight(220)

    frame.totalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.totalLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 24)
    frame.totalLabel:SetText("Total Cost:")

    frame.totalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.totalValue:SetPoint("LEFT", frame.totalLabel, "RIGHT", 10, 0)
    frame.totalValue:SetText("0g 0s 0c")

    frame.refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refreshButton:SetSize(90, 22)
    frame.refreshButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)
    frame.refreshButton:SetText("Refresh")
    frame.refreshButton:SetScript("OnClick", RefreshUI)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(60, 22)
    frame.closeButton:SetPoint("RIGHT", frame.refreshButton, "LEFT", -8, 0)
    frame.closeButton:SetText("Close")
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:Hide()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event == "ADDON_LOADED" and loadedAddonName == ADDON_NAME then
        CUOR_DB = CUOR_DB or {}
        CUOR_DB.settings = CUOR_DB.settings or {}
        CUOR_DB.usageCounts = CUOR_DB.usageCounts or {}
        CUOR_DB.lastBagSnapshot = CUOR_DB.lastBagSnapshot or nil

        for key, value in pairs(CUOR.Settings) do
            if CUOR_DB.settings[key] == nil then
                CUOR_DB.settings[key] = value
            end
        end

        CUOR.Settings = CUOR_DB.settings
        RebuildConsumableIndexes()
        BuildUI()
        HandleRaidStateTransition()
    end

    if event == "PLAYER_ENTERING_WORLD" and frame then
        HandleRaidStateTransition()
        RefreshUI()
    end

    if event == "ZONE_CHANGED_NEW_AREA" and frame then
        HandleRaidStateTransition()
    end

    if event == "BAG_UPDATE_DELAYED" then
        UpdateUsageFromBagDelta()
    end
end)

SLASH_CUOR1 = "/cuor"
SlashCmdList.CUOR = function()
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
