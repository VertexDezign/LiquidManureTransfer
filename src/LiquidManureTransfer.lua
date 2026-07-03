-- FS25 Liquid Manure Transfer
-- Moves liquid manure from animal husbandries into production points that
-- consume it (e.g. a biogas plant) within a configurable range. Runs once per
-- in-game hour on the server; clients only hold the settings for the GUI.

LiquidManureTransfer = {}
LiquidManureTransfer.MOD_NAME = g_currentModName or "FS25_LiquidManureTransfer"
LiquidManureTransfer.MOD_DIR = g_currentModDirectory or ""
LiquidManureTransfer.SETTINGS_FILE = "FS25_LiquidManureTransfer.xml"

LiquidManureTransfer.MIN_DISTANCE = 100
LiquidManureTransfer.MAX_DISTANCE = 1000
LiquidManureTransfer.DISTANCE_STEP = 100

LiquidManureTransfer.LOG_ERROR = 1
LiquidManureTransfer.LOG_WARNING = 2
LiquidManureTransfer.LOG_INFO = 3
LiquidManureTransfer.LOG_DEBUG = 4

LiquidManureTransfer.settings = {
    distance = 300,
    logLevel = LiquidManureTransfer.LOG_INFO
}

LiquidManureTransfer.initialSyncInstalled = false

function LiquidManureTransfer:log(level, message, ...)
    if level > (self.settings.logLevel or self.LOG_INFO) then
        return
    end
    local text = "[LiquidManureTransfer] " .. string.format(tostring(message), ...)
    if level == self.LOG_ERROR then
        Logging.error(text)
    elseif level == self.LOG_WARNING then
        Logging.warning(text)
    else
        Logging.info(text)
    end
end

function LiquidManureTransfer:clampDistance(value)
    value = tonumber(value) or self.settings.distance
    value = math.floor(value / self.DISTANCE_STEP + 0.5) * self.DISTANCE_STEP
    return math.max(self.MIN_DISTANCE, math.min(self.MAX_DISTANCE, value))
end

function LiquidManureTransfer:clampLogLevel(value)
    value = math.floor(tonumber(value) or self.LOG_INFO)
    return math.max(self.LOG_ERROR, math.min(self.LOG_DEBUG, value))
end

function LiquidManureTransfer:getSettingsPath()
    local basePath = getUserProfileAppPath()
    local folder = basePath .. "modSettings/"
    createFolder(folder)
    return folder .. self.SETTINGS_FILE
end

function LiquidManureTransfer:loadSettings()
    local path = self:getSettingsPath()
    if fileExists(path) then
        local xmlFile = XMLFile.load("LiquidManureTransferXML", path)
        if xmlFile ~= nil then
            self.settings.distance = self:clampDistance(xmlFile:getInt("liquidManureTransfer#distance", self.settings.distance))
            self.settings.logLevel = self:clampLogLevel(xmlFile:getInt("liquidManureTransfer#logLevel", self.settings.logLevel))
            xmlFile:delete()
            self:saveSettings()
        end
    else
        self:saveSettings()
    end
end

function LiquidManureTransfer:saveSettings()
    local path = self:getSettingsPath()
    local xmlFile = XMLFile.create("LiquidManureTransferXML", path, "liquidManureTransfer")
    if xmlFile ~= nil then
        xmlFile:setInt("liquidManureTransfer#distance", self:clampDistance(self.settings.distance))
        xmlFile:setInt("liquidManureTransfer#logLevel", self:clampLogLevel(self.settings.logLevel))
        xmlFile:save()
        xmlFile:delete()
    end
end

function LiquidManureTransfer:setSettings(distance, logLevel, noSave)
    self.settings.distance = self:clampDistance(distance)
    self.settings.logLevel = self:clampLogLevel(logLevel)
    if not noSave then
        self:saveSettings()
    end
end

-- Applies the settings locally and syncs them: a client sends them to the
-- server, the server broadcasts them to all clients.
function LiquidManureTransfer:sendSettingsToServer(distance, logLevel)
    self:setSettings(distance, logLevel, false)

    if g_client ~= nil and g_server == nil and g_client.getServerConnection ~= nil then
        g_client:getServerConnection():sendEvent(LiquidManureTransferChangeSettingsEvent.new(self.settings.distance, self.settings.logLevel))
    elseif g_server ~= nil then
        g_server:broadcastEvent(LiquidManureTransferChangeSettingsEvent.new(self.settings.distance, self.settings.logLevel), false)
    end
end

function LiquidManureTransfer:getLiquidManureFillTypeIndex()
    if self.liquidManureFillType == nil and g_fillTypeManager ~= nil then
        self.liquidManureFillType = g_fillTypeManager:getFillTypeIndexByName("LIQUIDMANURE")
    end
    return self.liquidManureFillType
end

-- ---- storage level helpers (handle both Storage objects and raw tables) ----

local function getLevel(storage, ft)
    if storage == nil then return 0 end
    if storage.fillLevels ~= nil then return storage.fillLevels[ft] or 0 end
    if storage.getFillLevel ~= nil then return storage:getFillLevel(ft) or 0 end
    return 0
end

local function getFree(storage, ft)
    if storage == nil then return 0 end
    if storage.getFreeCapacity ~= nil then return storage:getFreeCapacity(ft) or 0 end
    local cap = 0
    if storage.capacities ~= nil and storage.capacities[ft] ~= nil then
        cap = storage.capacities[ft]
    elseif storage.getCapacity ~= nil then
        cap = storage:getCapacity(ft) or 0
    end
    return math.max(0, cap - getLevel(storage, ft))
end

local function setLevel(storage, ft, level, farmId, delta)
    if storage.setFillLevel ~= nil then
        storage:setFillLevel(level, ft)
    elseif storage.addFillLevel ~= nil and delta ~= nil then
        storage:addFillLevel(farmId, ft, delta)
    elseif storage.fillLevels ~= nil then
        storage.fillLevels[ft] = level
    end
end

local function getProductionPoint(placeable)
    if placeable ~= nil and placeable.spec_productionPoint ~= nil then
        return placeable.spec_productionPoint.productionPoint
    end
    return nil
end

-- Storages of a husbandry that currently hold liquid manure.
local function getHusbandrySourceStorages(p, ft)
    local result = {}
    if p.spec_husbandry ~= nil then
        local h = p.spec_husbandry
        if h.storage ~= nil and getLevel(h.storage, ft) > 0 then
            result[#result + 1] = h.storage
        end
        if h.storages ~= nil then
            for _, s in ipairs(h.storages) do
                if getLevel(s, ft) > 0 then
                    result[#result + 1] = s
                end
            end
        end
    end
    return result
end

local function getOwnerFarmId(p)
    if p.getOwnerFarmId ~= nil then
        return p:getOwnerFarmId()
    end
    return nil
end

-- ---- transfer pass ----------------------------------------------------------

-- Production points that consume liquid manure as a production input, with
-- their world position and owner, so sources can filter by range and farm.
function LiquidManureTransfer:collectTargets(ft)
    local targets = {}
    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if placeableSystem == nil then
        return targets
    end
    for _, p in ipairs(placeableSystem.placeables) do
        local pp = getProductionPoint(p)
        if pp ~= nil and pp.storage ~= nil and p.rootNode ~= nil
                and pp.inputFillTypeIds ~= nil and pp.inputFillTypeIds[ft] then
            local x, _, z = getWorldTranslation(p.rootNode)
            targets[#targets + 1] = { placeable = p, pp = pp, x = x, z = z, farmId = getOwnerFarmId(p) }
        end
    end
    return targets
end

function LiquidManureTransfer:transferAll()
    local ft = self:getLiquidManureFillTypeIndex()
    if ft == nil then
        self:log(self.LOG_ERROR, "Fill type LIQUIDMANURE not found, cannot transfer")
        return
    end

    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if placeableSystem == nil then
        return
    end

    local targets = self:collectTargets(ft)
    if #targets == 0 then
        self:log(self.LOG_DEBUG, "No production point with a liquid manure input found")
        return
    end

    local maxDistance = self.settings.distance
    local maxDistance2 = maxDistance * maxDistance
    local spectatorFarmId = FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID or 0
    local totalMoved = 0

    for _, p in ipairs(placeableSystem.placeables) do
        if p.spec_husbandryLiquidManure ~= nil and p.rootNode ~= nil then
            local sourceFt = p.spec_husbandryLiquidManure.fillType or ft
            local farmId = getOwnerFarmId(p)
            if sourceFt == ft and farmId ~= nil and farmId ~= spectatorFarmId then
                local sx, _, sz = getWorldTranslation(p.rootNode)

                -- targets of the same farm within range, nearest first
                local inRange = {}
                for _, t in ipairs(targets) do
                    if t.placeable ~= p and t.farmId == farmId then
                        local dx, dz = t.x - sx, t.z - sz
                        local d2 = dx * dx + dz * dz
                        if d2 <= maxDistance2 then
                            inRange[#inRange + 1] = { target = t, d2 = d2 }
                        end
                    end
                end
                table.sort(inRange, function(a, b) return a.d2 < b.d2 end)

                for _, entry in ipairs(inRange) do
                    local target = entry.target
                    for _, storage in ipairs(getHusbandrySourceStorages(p, ft)) do
                        local available = getLevel(storage, ft)
                        local free = getFree(target.pp.storage, ft)
                        local moved = math.min(available, free)
                        if moved > 0 then
                            setLevel(storage, ft, available - moved, farmId, -moved)
                            setLevel(target.pp.storage, ft, getLevel(target.pp.storage, ft) + moved, farmId, moved)
                            totalMoved = totalMoved + moved
                            local name = p.getName ~= nil and p:getName() or "husbandry"
                            local targetName = target.placeable.getName ~= nil and target.placeable:getName() or "production"
                            self:log(self.LOG_DEBUG, "Moved %d l liquid manure from '%s' to '%s' (%.0f m)",
                                moved, tostring(name), tostring(targetName), math.sqrt(entry.d2))
                        end
                    end
                end
            end
        end
    end

    if totalMoved > 0 then
        self:log(self.LOG_INFO, "Transferred %d l liquid manure to production points", totalMoved)
    else
        self:log(self.LOG_DEBUG, "Hourly pass finished, nothing to transfer")
    end
end

function LiquidManureTransfer:onHourChanged()
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end
    self:transferAll()
end

-- ---- initial multiplayer sync ------------------------------------------------
-- The server pushes its current settings to every client that finishes joining,
-- so the settings GUI on clients always shows the server state.
function LiquidManureTransfer.installInitialSync()
    if LiquidManureTransfer.initialSyncInstalled then
        return
    end
    if FSBaseMission ~= nil and FSBaseMission.sendInitialClientState ~= nil then
        FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState,
            function(mission, connection, user, farm)
                if connection ~= nil then
                    connection:sendEvent(LiquidManureTransferChangeSettingsEvent.new(
                        LiquidManureTransfer.settings.distance, LiquidManureTransfer.settings.logLevel))
                end
            end)
        LiquidManureTransfer.initialSyncInstalled = true
    end
end

-- ---- console commands ---------------------------------------------------------

function LiquidManureTransfer:consolePrintSettings()
    print("LiquidManureTransfer settings:")
    print(string.format("  Distance:  %d m", self.settings.distance))
    print(string.format("  Log level: %d (1=Error, 2=Warning, 3=Info, 4=Debug)", self.settings.logLevel))
end

function LiquidManureTransfer:consoleSetDistance(value)
    if value == nil then
        return "Usage: lmtSetDistance <100-1000>"
    end
    self:sendSettingsToServer(value, self.settings.logLevel)
    return string.format("LiquidManureTransfer: distance set to %d m", self.settings.distance)
end

function LiquidManureTransfer:consoleSetLogLevel(value)
    if value == nil then
        return "Usage: lmtSetLogLevel <1=Error|2=Warning|3=Info|4=Debug>"
    end
    self:sendSettingsToServer(self.settings.distance, value)
    return string.format("LiquidManureTransfer: log level set to %d", self.settings.logLevel)
end

function LiquidManureTransfer:consoleTransferNow()
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return "lmtTransferNow only works on the server"
    end
    self:transferAll()
    return "LiquidManureTransfer: transfer pass executed"
end

-- ---- lifecycle -----------------------------------------------------------------

function LiquidManureTransfer:loadMap(name)
    self:loadSettings()
    if g_messageCenter ~= nil and MessageType.HOUR_CHANGED ~= nil then
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
    end
    addConsoleCommand("lmtPrintSettings", "Print Liquid Manure Transfer settings", "consolePrintSettings", self)
    addConsoleCommand("lmtSetDistance", "Set Liquid Manure Transfer distance: <100-1000>", "consoleSetDistance", self)
    addConsoleCommand("lmtSetLogLevel", "Set Liquid Manure Transfer log level: <1-4>", "consoleSetLogLevel", self)
    addConsoleCommand("lmtTransferNow", "Run a Liquid Manure Transfer pass now (server only)", "consoleTransferNow", self)
    self:log(self.LOG_INFO, "Loaded (distance: %d m, log level: %d)", self.settings.distance, self.settings.logLevel)
end

function LiquidManureTransfer:deleteMap()
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(self)
    end
    removeConsoleCommand("lmtPrintSettings")
    removeConsoleCommand("lmtSetDistance")
    removeConsoleCommand("lmtSetLogLevel")
    removeConsoleCommand("lmtTransferNow")
end

LiquidManureTransfer:loadSettings()
LiquidManureTransfer.installInitialSync()
addModEventListener(LiquidManureTransfer)
