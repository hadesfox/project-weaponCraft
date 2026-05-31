-- ============================================================================
-- GameSettings.lua - 游戏设置（持久化存储）
-- ============================================================================

local Config = require("Config")

local GameSettings = {}

-- 默认值
local defaults_ = {
    trialTime = Config.Combat.TrialTimeLimit,         -- 试炼时长（默认60秒）
    materialTime = Config.MaterialDanmaku.Duration,   -- 选材时长（默认5秒）
    hammerTime = Config.Forge.HammerDuration,         -- 锤击时长（默认5秒）
    quenchTime = Config.Forge.QuenchDuration,         -- 淬火时长（默认5秒）
    grindTime = Config.Forge.GrindDuration,           -- 砥砺时长（默认3秒）
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

--- 获取选材时长
---@return number
function GameSettings.GetMaterialTime()
    return settings_.materialTime
end

--- 设置选材时长
---@param seconds number
function GameSettings.SetMaterialTime(seconds)
    settings_.materialTime = seconds
    GameSettings.Save()
end

--- 获取锤击时长
---@return number
function GameSettings.GetHammerTime()
    return settings_.hammerTime
end

--- 设置锤击时长
---@param seconds number
function GameSettings.SetHammerTime(seconds)
    settings_.hammerTime = seconds
    GameSettings.Save()
end

--- 获取淬火时长
---@return number
function GameSettings.GetQuenchTime()
    return settings_.quenchTime
end

--- 设置淬火时长
---@param seconds number
function GameSettings.SetQuenchTime(seconds)
    settings_.quenchTime = seconds
    GameSettings.Save()
end

--- 获取砥砺时长
---@return number
function GameSettings.GetGrindTime()
    return settings_.grindTime
end

--- 设置砥砺时长
---@param seconds number
function GameSettings.SetGrindTime(seconds)
    settings_.grindTime = seconds
    GameSettings.Save()
end

--- 恢复所有时长为默认值
function GameSettings.ResetDurations()
    for k, v in pairs(defaults_) do
        settings_[k] = v
    end
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
