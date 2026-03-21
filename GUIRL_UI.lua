GUIRL = GUIRL or CUOR or {}
CUOR = GUIRL

local ADDON_NAME = ...
local frame
local RefreshUI
local RenderGraph
local BuildUI
local minimapButton
local eventFrame
local activeConsumables = {}
local trackedItemIDs = {}
local POLL_INTERVAL_SECONDS = 0.5
local MIN_FRAME_WIDTH = 520
local COLUMN_GAP = 6
local ADDON_ICON_FILENAME = "Haste_AI.png"
local LEGACY_TITLE = "Gold used In Riad Loser"

local function GetAddonIconPath()
    local addonFolder = ADDON_NAME or "GUIRL"
    return "Interface\\AddOns\\" .. addonFolder .. "\\Media\\" .. ADDON_ICON_FILENAME
end

local function ToggleMainFrame()
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

local function PositionMinimapButton()
    if not minimapButton or not GUIRL or not GUIRL.Settings then
        return
    end

    local angle = tonumber(GUIRL.Settings.minimapAngle) or 225
    local radians = math.rad(angle)
    local x = math.cos(radians) * 80
    local y = math.sin(radians) * 80

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    if minimapButton then
        return
    end

    minimapButton = CreateFrame("Button", "GUIRL_MinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")

    minimapButton.icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    minimapButton.icon:SetSize(20, 20)
    minimapButton.icon:SetPoint("CENTER")
    minimapButton.icon:SetTexture(GetAddonIconPath())

    minimapButton.border = minimapButton:CreateTexture(nil, "OVERLAY")
    minimapButton.border:SetSize(54, 54)
    minimapButton.border:SetPoint("TOPLEFT")
    minimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    minimapButton:SetScript("OnClick", function()
        ToggleMainFrame()
    end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("/guirl for UI")
        GameTooltip:AddLine("Made by Hypri", 1, 1, 1)
        GameTooltip:Show()
    end)

    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(button)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx = cx / scale
            cy = cy / scale

            local angle = math.deg(math.atan2(cy - my, cx - mx))
            GUIRL.Settings.minimapAngle = angle
            PositionMinimapButton()
        end)
    end)

    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    PositionMinimapButton()
end

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

local function GetPricePer1000Gold()
    if not GUIRL or not GUIRL.Settings then
        return 0
    end

    return tonumber(GUIRL.Settings.pricePer1000Gold) or 0
end

local function FormatRealCurrency(copper)
    local pricePer1000 = GetPricePer1000Gold()
    if pricePer1000 <= 0 then
        return "n/a"
    end

    local numericCopper = tonumber(copper) or 0
    local value = (numericCopper / 10000000) * pricePer1000

    return string.format("%.2f", value)
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

local function BuildDisplayRowsAndTotal()
    RebuildConsumableIndexes()

    local displayRows = {}
    local grandTotal = 0

    for _, consumable in ipairs(activeConsumables) do
        local quantityUsed = GUIRL_DB and GUIRL_DB.usageCounts and GUIRL_DB.usageCounts[consumable.itemID] or 0

        if quantityUsed > 0 then
            local price = select(1, GetItemPrice(consumable.itemID)) or 0
            local lineTotal = price * quantityUsed

            displayRows[#displayRows + 1] = {
                itemID = consumable.itemID,
                itemName = GetItemDisplayName(consumable),
                quantityUsed = quantityUsed,
                price = price,
                lineTotal = lineTotal,
            }

            grandTotal = grandTotal + lineTotal
        end
    end

    return displayRows, grandTotal
end

local function RenderDisplayRows(displayRows, grandTotal)
    EnsureRows(#displayRows)

    local yOffset = -2

    for index, rowData in ipairs(displayRows) do
        local row = frame.rows[index]

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, yOffset)

        row.nameText:SetText(rowData.itemName)
        row.qtyText:SetText(tostring(rowData.quantityUsed))
        row.priceText:SetText(FormatMoney(rowData.price))
        row.totalText:SetText(FormatMoney(rowData.lineTotal))

        yOffset = yOffset - GUIRL.Settings.rowHeight
        row:Show()
    end

    for index = #displayRows + 1, #frame.rows do
        frame.rows[index]:Hide()
    end

    frame.totalValue:SetText(FormatMoney(grandTotal))

    if frame.totalRealValue then
        frame.totalRealValue:SetText("EURO " .. FormatRealCurrency(grandTotal))
    end
end

local function GetGraphEntryTotal(entry)
    if not entry then
        return 0
    end

    return tonumber(entry.snapshotTotalCopper) or tonumber(entry.totalCopper) or 0
end

local function GetAngleRadians(deltaY, deltaX)
    if math.atan2 then
        return math.atan2(deltaY, deltaX)
    end

    return math.atan(deltaY, deltaX)
end

local function GetLogTotals()
    local entries = GUIRL_DB and GUIRL_DB.log and GUIRL_DB.log.entries or {}
    local lifetimeTotal = 0

    for _, entry in ipairs(entries) do
        lifetimeTotal = lifetimeTotal + GetGraphEntryTotal(entry)
    end

    local lastRaidTotal = 0
    if #entries > 0 then
        lastRaidTotal = GetGraphEntryTotal(entries[#entries])
    end

    return lastRaidTotal, lifetimeTotal
end

local function UpdateRaidSummaryCounters()
    if not frame or not frame.lastRaidValue or not frame.lifetimeValue then
        return
    end

    local lastRaidTotal, lifetimeTotal = GetLogTotals()
    frame.lastRaidValue:SetText(FormatMoney(lastRaidTotal))
    frame.lifetimeValue:SetText(FormatMoney(lifetimeTotal))

    if frame.lastRaidRealValue then
        frame.lastRaidRealValue:SetText("EURO " .. FormatRealCurrency(lastRaidTotal))
    end

    if frame.lifetimeRealValue then
        frame.lifetimeRealValue:SetText("EURO " .. FormatRealCurrency(lifetimeTotal))
    end
end

local function CreateChartArea(parent, topAnchor, titleText)
    local area = CreateFrame("Frame", nil, parent)
    area:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, topAnchor)
    area:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, topAnchor)
    area:SetHeight(84)

    area.titleText = area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    area.titleText:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    area.titleText:SetText(titleText)

    area.yAxis = area:CreateTexture(nil, "BORDER")
    area.yAxis:SetColorTexture(1, 1, 1, 0.2)
    area.yAxis:SetWidth(1)
    area.yAxis:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 20, 14)
    area.yAxis:SetPoint("TOPLEFT", area, "TOPLEFT", 20, -14)

    area.xAxis = area:CreateTexture(nil, "BORDER")
    area.xAxis:SetColorTexture(1, 1, 1, 0.2)
    area.xAxis:SetHeight(1)
    area.xAxis:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 20, 14)
    area.xAxis:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 14)

    area.lines = {}
    area.points = {}

    return area
end

local function EnsureGraphWidgets()
    if frame.graphPanel then
        return
    end

    frame.graphPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.graphPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -70)
    frame.graphPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -70)
    frame.graphPanel:SetHeight(220)
    frame.graphPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
    })
    frame.graphPanel:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
    frame.graphPanel:SetBackdropBorderColor(1, 1, 1, 0.12)

    frame.graphPanel.emptyText = frame.graphPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.graphPanel.emptyText:SetPoint("CENTER", frame.graphPanel, "CENTER", 0, 0)
    frame.graphPanel.emptyText:SetText("No log entries yet.\nUse Reset with logging to add points.")

    frame.graphPanel.perRaidArea = CreateChartArea(frame.graphPanel, -10, "Total Gold Spend Per Raid")
    frame.graphPanel.cumulativeArea = CreateChartArea(frame.graphPanel, -112, "Gold Spend Built Up Over Time")
    frame.graphPanel:Hide()

    frame.graphPanel:SetScript("OnSizeChanged", function()
        if frame and frame.showingGraph then
            RenderGraph()
        end
    end)
end

local function HideUsageList()
    frame.content:Hide()
    frame.headerName:Hide()
    frame.headerQty:Hide()
    frame.headerPrice:Hide()
    frame.headerTotal:Hide()
    frame.headerSeparator:Hide()
    frame.totalLabel:Hide()
    frame.totalValue:Hide()
    if frame.totalRealLabel then
        frame.totalRealLabel:Hide()
    end
    if frame.totalRealValue then
        frame.totalRealValue:Hide()
    end

    if frame.rows then
        for _, row in ipairs(frame.rows) do
            row:Hide()
        end
    end
end

local function ShowUsageList()
    frame.content:Show()
    frame.headerName:Show()
    frame.headerQty:Show()
    frame.headerPrice:Show()
    frame.headerTotal:Show()
    frame.headerSeparator:Show()
    frame.totalLabel:Show()
    frame.totalValue:Show()
    if frame.totalRealLabel then
        frame.totalRealLabel:Show()
    end
    if frame.totalRealValue then
        frame.totalRealValue:Show()
    end
end

local function ShowGraphPointTooltip(pointFrame)
    if not pointFrame then
        return
    end

    local isShiftDown = IsShiftKeyDown and IsShiftKeyDown()
    local rows = pointFrame.rows or {}

    GameTooltip:SetOwner(pointFrame, "ANCHOR_RIGHT")
    local seriesTitle = pointFrame.seriesTitle or "Log Point"
    local valueLabel = pointFrame.valueLabel or "Total Spent"

    GameTooltip:SetText(seriesTitle .. " " .. tostring(pointFrame.logIndex or ""))
    GameTooltip:AddLine(valueLabel .. ": " .. FormatMoney(pointFrame.totalCopper or 0), 1, 1, 1)
    GameTooltip:AddLine("Value (EURO): " .. FormatRealCurrency(pointFrame.totalCopper or 0), 0.9, 0.9, 0.9)

    if pointFrame.timestamp and pointFrame.timestamp > 0 then
        GameTooltip:AddLine(date("%Y-%m-%d %H:%M", pointFrame.timestamp), 0.8, 0.8, 0.8)
    end

    if pointFrame.rows and #rows > 0 and not isShiftDown then
        GameTooltip:AddLine("Hold Shift for more info", 0.75, 0.75, 0.75)
    elseif pointFrame.rows and #rows > 0 then
        GameTooltip:AddLine("Items Logged:", 1, 0.9, 0.4)

        for _, row in ipairs(rows) do
            local quantity = tonumber(row.quantityUsed) or 0
            local itemName = row.itemName or (row.itemID and ("Item " .. tostring(row.itemID))) or "Unknown"
            GameTooltip:AddLine(string.format("%dx %s", quantity, itemName), 0.95, 0.95, 0.95)
        end
    end

    GameTooltip:Show()
    pointFrame.lastShiftState = isShiftDown
end

local function BuildCumulativeRowsByPoint(entries)
    local cumulativeRowsByPoint = {}
    local quantityByKey = {}
    local nameByKey = {}
    local keyOrder = {}

    for index, entry in ipairs(entries) do
        for _, row in ipairs(entry.rows or {}) do
            local itemName = row.itemName or "Unknown"
            local itemID = tonumber(row.itemID)
            local key = itemID or ("name:" .. itemName)

            if not quantityByKey[key] then
                quantityByKey[key] = 0
                nameByKey[key] = itemName
                keyOrder[#keyOrder + 1] = key
            end

            quantityByKey[key] = quantityByKey[key] + (tonumber(row.quantityUsed) or 0)
        end

        local pointRows = {}
        for _, key in ipairs(keyOrder) do
            local quantity = quantityByKey[key] or 0
            if quantity > 0 then
                pointRows[#pointRows + 1] = {
                    itemID = type(key) == "number" and key or nil,
                    itemName = nameByKey[key] or "Unknown",
                    quantityUsed = quantity,
                }
            end
        end

        cumulativeRowsByPoint[index] = pointRows
    end

    return cumulativeRowsByPoint
end

local function RenderChartSeries(area, entries, values, colorR, colorG, colorB, seriesTitle, valueLabel, includeRows, rowsByPoint)
    for _, lineTexture in ipairs(area.lines) do
        lineTexture:Hide()
    end

    for _, pointFrame in ipairs(area.points) do
        pointFrame:Hide()
    end

    if #values == 0 then
        return
    end

    local leftPadding = 20
    local rightPadding = 8
    local topPadding = 18
    local bottomPadding = 14
    local graphWidth = math.max(area:GetWidth() - leftPadding - rightPadding, 1)
    local graphHeight = math.max(area:GetHeight() - topPadding - bottomPadding, 1)
    local minValue = nil
    local maxValue = nil

    for _, value in ipairs(values) do
        if not minValue or value < minValue then
            minValue = value
        end

        if not maxValue or value > maxValue then
            maxValue = value
        end
    end

    local valueSpan = (maxValue or 0) - (minValue or 0)
    local xStep = #values > 1 and (graphWidth / (#values - 1)) or 0
    local previousX = nil
    local previousY = nil

    for index, value in ipairs(values) do
        local normalizedY = valueSpan > 0 and ((value - minValue) / valueSpan) or 0.5
        local x = leftPadding + (#values > 1 and ((index - 1) * xStep) or (graphWidth * 0.5))
        local y = bottomPadding + (normalizedY * graphHeight)

        if previousX and previousY then
            local lineTexture = area.lines[index - 1]

            if not lineTexture then
                lineTexture = area:CreateTexture(nil, "ARTWORK")
                area.lines[index - 1] = lineTexture
            end

            local deltaX = x - previousX
            local deltaY = y - previousY
            local length = math.sqrt((deltaX * deltaX) + (deltaY * deltaY))

            lineTexture:SetColorTexture(colorR, colorG, colorB, 0.9)
            lineTexture:ClearAllPoints()
            lineTexture:SetPoint("CENTER", area, "BOTTOMLEFT", (previousX + x) * 0.5, (previousY + y) * 0.5)
            lineTexture:SetSize(length, 2)
            lineTexture:SetRotation(GetAngleRadians(deltaY, deltaX))
            lineTexture:Show()
        end

        local pointFrame = area.points[index]

        if not pointFrame then
            pointFrame = CreateFrame("Frame", nil, area)
            pointFrame:SetSize(10, 10)

            pointFrame.dot = pointFrame:CreateTexture(nil, "ARTWORK")
            pointFrame.dot:SetAllPoints()
            pointFrame.dot:SetTexture("Interface\\Buttons\\WHITE8X8")

            pointFrame:SetScript("OnEnter", function(self)
                ShowGraphPointTooltip(self)

                self:SetScript("OnUpdate", function(point)
                    local shiftState = IsShiftKeyDown and IsShiftKeyDown() or false
                    if shiftState ~= point.lastShiftState then
                        ShowGraphPointTooltip(point)
                    end
                end)
            end)

            pointFrame:SetScript("OnLeave", function(self)
                self:SetScript("OnUpdate", nil)
                self.lastShiftState = nil
                GameTooltip:Hide()
            end)

            area.points[index] = pointFrame
        end

        pointFrame.dot:SetVertexColor(colorR, colorG, colorB, 1)
        pointFrame.totalCopper = value
        pointFrame.timestamp = entries[index] and entries[index].timestamp or 0
        if rowsByPoint and rowsByPoint[index] then
            pointFrame.rows = rowsByPoint[index]
        else
            pointFrame.rows = includeRows and entries[index] and entries[index].rows or nil
        end
        pointFrame.logIndex = index
        pointFrame.seriesTitle = seriesTitle
        pointFrame.valueLabel = valueLabel
        pointFrame:ClearAllPoints()
        pointFrame:SetPoint("CENTER", area, "BOTTOMLEFT", x, y)
        pointFrame:Show()

        previousX = x
        previousY = y
    end
end

RenderGraph = function()
    if not frame then
        return
    end

    EnsureGraphWidgets()

    local panel = frame.graphPanel
    local entries = GUIRL_DB and GUIRL_DB.log and GUIRL_DB.log.entries or {}

    local perRaidValues = {}
    local cumulativeValues = {}
    local cumulativeRowsByPoint = BuildCumulativeRowsByPoint(entries)
    local runningTotal = 0

    for _, entry in ipairs(entries) do
        local raidTotal = GetGraphEntryTotal(entry)
        runningTotal = runningTotal + raidTotal

        perRaidValues[#perRaidValues + 1] = raidTotal
        cumulativeValues[#cumulativeValues + 1] = runningTotal
    end

    if #entries == 0 then
        panel.perRaidArea:Hide()
        panel.cumulativeArea:Hide()
        panel.emptyText:Show()
        return
    end

    panel.perRaidArea:Show()
    panel.cumulativeArea:Show()
    panel.emptyText:Hide()

    RenderChartSeries(panel.perRaidArea, entries, perRaidValues, 1, 0.85, 0.2, "Raid", "Total Gold Spent", true)
    RenderChartSeries(panel.cumulativeArea, entries, cumulativeValues, 0.3, 0.9, 1, "Lifetime", "Cumulative Gold Spent", false, cumulativeRowsByPoint)
end

local function ToggleGraphView()
    if not frame then
        return
    end

    EnsureGraphWidgets()

    if frame.showingGraph then
        frame.showingGraph = false
        frame.graphPanel:Hide()
        ShowUsageList()
        frame.graphButton:SetText("Graph")
        RefreshUI()
    else
        frame.showingGraph = true
        HideUsageList()
        frame.graphPanel:Show()
        frame.graphButton:SetText("List")
        RenderGraph()
    end
end

function RefreshUI(shouldLog)
    if not frame then
        return
    end

    local displayRows, grandTotal = BuildDisplayRowsAndTotal()

    if shouldLog and GUIRL.Log and GUIRL.Log.SaveSnapshot then
        GUIRL.Log.SaveSnapshot(displayRows, grandTotal)
    end

    RenderDisplayRows(displayRows, grandTotal)
    UpdateRaidSummaryCounters()

    if frame.showingGraph then
        RenderGraph()
    end
end

local function ShowResetPopup()
    if not StaticPopupDialogs["GUIRL_RESET_LOG_PROMPT"] then
        StaticPopupDialogs["GUIRL_RESET_LOG_PROMPT"] = {
            text = "Do you want to log before reset?",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                RefreshUI(true)
                ResetTrackedData()
            end,
            OnCancel = function()
                ResetTrackedData()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    StaticPopup_Show("GUIRL_RESET_LOG_PROMPT")
end

BuildUI = function()
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

    frame.topRightArt = frame:CreateTexture(nil, "ARTWORK")
    frame.topRightArt:SetSize(46, 46)
    frame.topRightArt:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -8)

    frame.topRightArt:SetTexture(GetAddonIconPath())

    frame.topRightArt:SetBlendMode("BLEND")
    frame.topRightArt:SetAlpha(0.95)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOP", frame, "TOP", -40, -28)
    frame.title:SetText(GUIRL.Settings.title)

    frame.priceInputLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.priceInputLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -10)
    frame.priceInputLabel:SetText("Price of 1000 Gold")
    frame.priceInputLabel:SetTextColor(1, 0.82, 0, 1)

    frame.setPriceButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.setPriceButton:SetSize(72, 20)
    frame.setPriceButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -30)
    frame.setPriceButton:SetText("Set Price")

    frame.priceInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.priceInput:SetSize(90, 20)
    frame.priceInput:SetPoint("RIGHT", frame.setPriceButton, "LEFT", -8, 0)
    frame.priceInput:SetAutoFocus(false)
    frame.priceInput:SetTextInsets(4, 4, 0, 0)

    frame.priceInputLabel:ClearAllPoints()
    frame.priceInputLabel:SetPoint("BOTTOMLEFT", frame.priceInput, "TOPLEFT", 0, 4)

    local existingPrice = GetPricePer1000Gold()
    if existingPrice > 0 then
        frame.priceInput:SetText(string.format("%.2f", existingPrice))
    else
        frame.priceInput:SetText("")
    end

    frame.priceInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        frame.setPriceButton:Click()
    end)

    frame.priceInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    frame.setPriceButton:SetScript("OnClick", function()
        local rawText = frame.priceInput:GetText() or ""
        rawText = string.gsub(rawText, ",", ".")
        local parsedValue = tonumber(rawText)

        if parsedValue and parsedValue > 0 then
            GUIRL.Settings.pricePer1000Gold = parsedValue
            frame.priceInput:SetText(string.format("%.2f", parsedValue))
        else
            GUIRL.Settings.pricePer1000Gold = 0
            frame.priceInput:SetText("")
        end

        RefreshUI()
    end)

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -70)
    frame.content:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -70)
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

    frame.totalRealLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.totalRealLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 8)
    frame.totalRealLabel:SetText("Value (EURO):")

    frame.totalRealValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.totalRealValue:SetPoint("LEFT", frame.totalRealLabel, "RIGHT", 8, 0)
    frame.totalRealValue:SetText("n/a")

    frame.summaryBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.summaryBox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 10, -6)
    frame.summaryBox:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -10, -6)
    frame.summaryBox:SetHeight(58)
    frame.summaryBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
    })
    frame.summaryBox:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
    frame.summaryBox:SetBackdropBorderColor(1, 1, 1, 0.12)

    frame.lastRaidLabel = frame.summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.lastRaidLabel:SetPoint("TOPLEFT", frame.summaryBox, "TOPLEFT", 10, -8)
    frame.lastRaidLabel:SetText("Gold Used Last Raid:")

    frame.lastRaidValue = frame.summaryBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.lastRaidValue:SetPoint("LEFT", frame.lastRaidLabel, "RIGHT", 6, 0)
    frame.lastRaidValue:SetTextColor(1, 1, 1, 1)
    frame.lastRaidValue:SetText("0g 0s 0c")

    frame.lastRaidRealValue = frame.summaryBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.lastRaidRealValue:SetPoint("TOPLEFT", frame.lastRaidValue, "BOTTOMLEFT", 0, -2)
    frame.lastRaidRealValue:SetText("EURO n/a")

    frame.lifetimeLabel = frame.summaryBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.lifetimeLabel:SetPoint("LEFT", frame.lastRaidValue, "RIGHT", 20, 0)
    frame.lifetimeLabel:SetText("Gold Used Lifetime:")

    frame.lifetimeValue = frame.summaryBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.lifetimeValue:SetPoint("LEFT", frame.lifetimeLabel, "RIGHT", 6, 0)
    frame.lifetimeValue:SetTextColor(1, 1, 1, 1)
    frame.lifetimeValue:SetText("0g 0s 0c")

    frame.lifetimeRealValue = frame.summaryBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.lifetimeRealValue:SetPoint("TOPLEFT", frame.lifetimeValue, "BOTTOMLEFT", 0, -2)
    frame.lifetimeRealValue:SetText("EURO n/a")

    frame.resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.resetButton:SetSize(110, 22)
    frame.resetButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)
    frame.resetButton:SetText("Reset/Log")
    frame.resetButton:SetScript("OnClick", ShowResetPopup)

    frame.graphButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.graphButton:SetSize(70, 22)
    frame.graphButton:SetPoint("RIGHT", frame.resetButton, "LEFT", -8, 0)
    frame.graphButton:SetText("Graph")
    frame.graphButton:SetScript("OnClick", ToggleGraphView)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(60, 22)
    frame.closeButton:SetPoint("RIGHT", frame.graphButton, "LEFT", -8, 0)
    frame.closeButton:SetText("Close")
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    UpdateRaidSummaryCounters()

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
        if GUIRL.Log and GUIRL.Log.Initialize then
            GUIRL.Log.Initialize(GUIRL_DB)
        end

        for key, value in pairs(GUIRL.Settings) do
            if GUIRL_DB.settings[key] == nil then
                GUIRL_DB.settings[key] = value
            end
        end

        -- Migrate legacy typo from older saved settings.
        if GUIRL_DB.settings.title == LEGACY_TITLE then
            GUIRL_DB.settings.title = GUIRL.Settings.title
        end

        GUIRL.Settings = GUIRL_DB.settings
        if not GUIRL.Settings.frameWidth or GUIRL.Settings.frameWidth < MIN_FRAME_WIDTH then
            GUIRL.Settings.frameWidth = MIN_FRAME_WIDTH
        end
        if GUIRL.Settings.minimapAngle == nil then
            GUIRL.Settings.minimapAngle = 225
        end
        RebuildConsumableIndexes()
        BuildUI()
        CreateMinimapButton()
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
    ToggleMainFrame()
end
