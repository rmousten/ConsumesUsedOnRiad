GUIRL = GUIRL or {}

GUIRL.Log = GUIRL.Log or {}

local function EnsureLogTable(db)
    if not db.log then
        db.log = {
            entries = {},
            nextId = 1,
        }
    end

    if not db.log.entries then
        db.log.entries = {}
    end

    if not db.log.nextId then
        db.log.nextId = #db.log.entries + 1
    end

    return db.log
end

function GUIRL.Log.Initialize(db)
    if not db then
        return
    end

    EnsureLogTable(db)
end

function GUIRL.Log.SaveSnapshot(displayRows, totalCopper)
    if not GUIRL_DB then
        return false
    end

    local logTable = EnsureLogTable(GUIRL_DB)

    local snapshotTotal = tonumber(totalCopper) or 0

    local entry = {
        id = logTable.nextId,
        timestamp = time and time() or 0,
        totalCopper = snapshotTotal,
        snapshotTotalCopper = snapshotTotal,
        isSnapshot = true,
        rows = {},
    }

    for _, row in ipairs(displayRows or {}) do
        local quantityUsed = tonumber(row.quantityUsed) or 0
        local unitPrice = tonumber(row.price) or 0
        local lineTotal = tonumber(row.lineTotal) or (unitPrice * quantityUsed)

        entry.rows[#entry.rows + 1] = {
            itemID = row.itemID,
            itemName = row.itemName,
            quantityUsed = quantityUsed,
            unitPrice = unitPrice,
            lineTotal = lineTotal,
            snapshotUnitPriceCopper = unitPrice,
            snapshotLineTotalCopper = lineTotal,
        }
    end

    logTable.entries[#logTable.entries + 1] = entry
    logTable.nextId = logTable.nextId + 1

    return true
end
