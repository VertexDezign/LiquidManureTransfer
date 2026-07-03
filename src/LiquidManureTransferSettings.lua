-- Adds the Liquid Manure Transfer options to Ingame -> Game Settings.

LiquidManureTransferSettings = {}
LiquidManureTransferSettings.MOD_NAME = g_currentModName or "FS25_LiquidManureTransfer"
LiquidManureTransferSettings.installed = false
LiquidManureTransferSettings.elements = {}

function LiquidManureTransferSettings.init()
    if InGameMenuSettingsFrame ~= nil and not LiquidManureTransferSettings.installed then
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, LiquidManureTransferSettings.initSettingsGui)
        LiquidManureTransferSettings.installed = true
    end
end

function LiquidManureTransferSettings:getText(key)
    local env = g_i18n.modEnvironments ~= nil and g_i18n.modEnvironments[LiquidManureTransferSettings.MOD_NAME] or nil
    if env ~= nil and env.texts ~= nil and env.texts[key] ~= nil then
        return env.texts[key]
    end
    return g_i18n:getText(key) or key
end

function LiquidManureTransferSettings:getDistanceTexts()
    if self.distanceTexts == nil then
        self.distanceTexts = {}
        local steps = (LiquidManureTransfer.MAX_DISTANCE - LiquidManureTransfer.MIN_DISTANCE) / LiquidManureTransfer.DISTANCE_STEP + 1
        for i = 1, steps do
            self.distanceTexts[i] = string.format("%d m", LiquidManureTransfer.MIN_DISTANCE + (i - 1) * LiquidManureTransfer.DISTANCE_STEP)
        end
    end
    return self.distanceTexts
end

function LiquidManureTransferSettings:getLogLevelTexts()
    if self.logLevelTexts == nil then
        self.logLevelTexts = {
            self:getText("lmt_logLevel_error"),
            self:getText("lmt_logLevel_warning"),
            self:getText("lmt_logLevel_info"),
            self:getText("lmt_logLevel_debug")
        }
    end
    return self.logLevelTexts
end

function LiquidManureTransferSettings:getStateFromDistance(distance)
    local state = math.floor((LiquidManureTransfer:clampDistance(distance) - LiquidManureTransfer.MIN_DISTANCE) / LiquidManureTransfer.DISTANCE_STEP) + 1
    return math.max(1, math.min(#self:getDistanceTexts(), state))
end

function LiquidManureTransferSettings:getDistanceFromState(state)
    return LiquidManureTransfer:clampDistance(LiquidManureTransfer.MIN_DISTANCE + ((tonumber(state) or 1) - 1) * LiquidManureTransfer.DISTANCE_STEP)
end

function LiquidManureTransferSettings:findOptionTemplate(frame)
    if frame.economicDifficulty ~= nil and frame.economicDifficulty.clone ~= nil then
        return frame.economicDifficulty
    end
    return nil
end

function LiquidManureTransferSettings:getSettingsRowTemplate(frame)
    if frame.gameSettingsLayout ~= nil then
        -- In the reference mod, element 5 is the row container and element 7 is the section header.
        return frame.gameSettingsLayout.elements[5], frame.gameSettingsLayout.elements[7]
    end
    return nil, nil
end

-- Pushes the current settings into the GUI elements (used on frame open and
-- when a settings event arrives from the network while the menu is visible).
function LiquidManureTransferSettings:refreshGui()
    local elements = LiquidManureTransferSettings.elements
    if elements.distance ~= nil then
        elements.distance:setState(LiquidManureTransferSettings:getStateFromDistance(LiquidManureTransfer.settings.distance))
    end
    if elements.logLevel ~= nil then
        elements.logLevel:setState(LiquidManureTransfer:clampLogLevel(LiquidManureTransfer.settings.logLevel))
    end
end

function LiquidManureTransferSettings.initSettingsGui(frame)
    if LiquidManureTransfer == nil or frame == nil or frame.gameSettingsLayout == nil then
        return
    end

    if frame.lmtDistance ~= nil then
        LiquidManureTransferSettings:refreshGui()
        return
    end

    local rowTemplate, headerTemplate = LiquidManureTransferSettings:getSettingsRowTemplate(frame)
    local optionTemplate = LiquidManureTransferSettings:findOptionTemplate(frame)

    if rowTemplate == nil or headerTemplate == nil or optionTemplate == nil then
        Logging.warning("[LiquidManureTransfer] Could not add settings menu entries because required FS25 GUI templates were not found")
        return
    end

    local title = headerTemplate:clone()
    title:applyProfile("fs25_settingsSectionHeader", true)
    title:setText(LiquidManureTransferSettings:getText("lmt_title"))
    title.focusChangeData = {}
    title.focusId = FocusManager.serveAutoFocusId()
    frame.gameSettingsLayout:addElement(title)

    local options = {
        { id = "lmtDistance", key = "distance", title = "lmt_distance", tooltip = "lmt_distance_tooltip", texts = LiquidManureTransferSettings:getDistanceTexts() },
        { id = "lmtLogLevel", key = "logLevel", title = "lmt_logLevel", tooltip = "lmt_logLevel_tooltip", texts = LiquidManureTransferSettings:getLogLevelTexts() }
    }

    for _, option in ipairs(options) do
        local cloneElement = optionTemplate:clone()
        cloneElement.id = option.id
        cloneElement.target = cloneElement

        cloneElement.texts = option.texts
        cloneElement.onClickCallback = LiquidManureTransferSettings.onSettingChanged
        cloneElement.buttonLRChange = true

        LiquidManureTransferSettings:addOptionToLayout(frame.gameSettingsLayout, cloneElement, option.id, option.title, option.tooltip, rowTemplate)

        LiquidManureTransferSettings.elements[option.key] = cloneElement
        frame[option.id] = cloneElement
    end

    LiquidManureTransferSettings:refreshGui()
    frame.gameSettingsLayout:invalidateLayout()
end

function LiquidManureTransferSettings:addOptionToLayout(gameSettingsLayout, cloneElement, id, textId, tooltipId, rowTemplate)
    cloneElement.id = id

    local tooltip = cloneElement.elements ~= nil and cloneElement.elements[1] or nil
    if tooltip ~= nil then
        tooltip.text = LiquidManureTransferSettings:getText(tooltipId)
        tooltip.sourceText = LiquidManureTransferSettings:getText(tooltipId)
    end

    local optionTitle = rowTemplate.elements[2]:clone()
    optionTitle.id = id .. "Title"
    optionTitle:applyProfile("fs25_settingsMultiTextOptionTitle", true)
    optionTitle:setText(LiquidManureTransferSettings:getText(textId))

    local optionContainer = rowTemplate:clone()
    optionContainer.id = id .. "Container"
    optionContainer:applyProfile("fs25_multiTextOptionContainer", true)

    for key, _ in pairs(optionContainer.elements) do
        optionContainer.elements[key] = nil
    end

    optionContainer:addElement(optionTitle)
    optionContainer:addElement(cloneElement)
    gameSettingsLayout:addElement(optionContainer)
end

function LiquidManureTransferSettings.onSettingChanged(element, state)
    local elements = LiquidManureTransferSettings.elements
    if LiquidManureTransfer == nil or elements.distance == nil or elements.logLevel == nil then
        return
    end

    local distanceState = element == elements.distance and (state or element.state) or elements.distance.state
    local logLevelState = element == elements.logLevel and (state or element.state) or elements.logLevel.state
    local distance = LiquidManureTransferSettings:getDistanceFromState(distanceState)
    local logLevel = LiquidManureTransfer:clampLogLevel(logLevelState)
    LiquidManureTransfer:sendSettingsToServer(distance, logLevel)
end

LiquidManureTransferSettings.init()
