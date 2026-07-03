-- Syncs the Liquid Manure Transfer settings between clients and the server.
-- Carries the full settings state: a client sends its change to the server,
-- the server applies it and broadcasts it to all other clients. The server
-- also sends this event to every newly joining client (initial sync).

LiquidManureTransferChangeSettingsEvent = {}
LiquidManureTransferChangeSettingsEvent_mt = Class(LiquidManureTransferChangeSettingsEvent, Event)
InitEventClass(LiquidManureTransferChangeSettingsEvent, "LiquidManureTransferChangeSettingsEvent")

function LiquidManureTransferChangeSettingsEvent.emptyNew()
    return Event.new(LiquidManureTransferChangeSettingsEvent_mt)
end

function LiquidManureTransferChangeSettingsEvent.new(distance, logLevel)
    local self = LiquidManureTransferChangeSettingsEvent.emptyNew()
    self.distance = tonumber(distance) or LiquidManureTransfer.settings.distance
    self.logLevel = tonumber(logLevel) or LiquidManureTransfer.settings.logLevel
    return self
end

function LiquidManureTransferChangeSettingsEvent:readStream(streamId, connection)
    self.distance = streamReadUInt16(streamId)
    self.logLevel = streamReadUInt8(streamId)
    self:run(connection)
end

function LiquidManureTransferChangeSettingsEvent:writeStream(streamId, connection)
    streamWriteUInt16(streamId, self.distance)
    streamWriteUInt8(streamId, self.logLevel)
end

function LiquidManureTransferChangeSettingsEvent:run(connection)
    if LiquidManureTransfer ~= nil then
        LiquidManureTransfer:setSettings(self.distance, self.logLevel, false)
        if LiquidManureTransferSettings ~= nil then
            LiquidManureTransferSettings:refreshGui()
        end
    end

    if g_server ~= nil then
        g_server:broadcastEvent(self, false, connection)
    end
end
