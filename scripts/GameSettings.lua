-- ============================================================================
-- GameSettings.lua - 游戏设置（持久化存储）
-- ============================================================================

local Config = require("Config")

local GameSettings = {}

-- 默认值
local defaults_ = {
    trialTime = Config.Combat.TrialTimeLimit,  -- 默认60秒
}

-- 当前设置值
local settings_ = {}

-- 初始化（合并默认值）
for k, v in pairs(defaults_) do
    settings_[k] = v
end

--- 获取试炼时长
---@return number
function GameSettings.GetTrialTime()
    return settings_.trialTime
end

--- 设置试炼时长
---@param seconds number
function GameSettings.SetTrialTime(seconds)
    settings_.trialTime = seconds
    GameSettings.Save()
end

--- 保存到本地文件
function GameSettings.Save()
    local cjson = require("cjson")
    local json = cjson.encode(settings_)
    local file = File:new("game_settings.json", FILE_WRITE)
    if file then
        file:WriteString(json)
        file:Close()
        file:delete()
    end
end

--- 从本地文件加载
function GameSettings.Load()
    if not fileSystem:FileExists("game_settings.json") then
        return
    end
    local cjson = require("cjson")
    local file = File:new("game_settings.json", FILE_READ)
    if file then
        local json = file:ReadString()
        file:Close()
        file:delete()
        if json and #json > 0 then
            local ok, data = pcall(cjson.decode, json)
            if ok and type(data) == "table" then
                for k, v in pairs(data) do
                    if defaults_[k] ~= nil then
                        settings_[k] = v
                    end
                end
            end
        end
    end
end

-- 模块加载时自动读取本地设置
GameSettings.Load()

return GameSettings
