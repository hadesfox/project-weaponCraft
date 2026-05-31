-- ============================================================================
-- KeyBindings.lua - 按键绑定配置系统
-- 支持玩家自定义所有操作的按键
-- ============================================================================

local KeyBindings = {}

-- 按键名→显示名映射（用于 UI 显示）
local KEY_NAMES = {
    [KEY_A] = "A", [KEY_B] = "B", [KEY_C] = "C", [KEY_D] = "D",
    [KEY_E] = "E", [KEY_F] = "F", [KEY_G] = "G", [KEY_H] = "H",
    [KEY_I] = "I", [KEY_J] = "J", [KEY_K] = "K", [KEY_L] = "L",
    [KEY_M] = "M", [KEY_N] = "N", [KEY_O] = "O", [KEY_P] = "P",
    [KEY_Q] = "Q", [KEY_R] = "R", [KEY_S] = "S", [KEY_T] = "T",
    [KEY_U] = "U", [KEY_V] = "V", [KEY_W] = "W", [KEY_X] = "X",
    [KEY_Y] = "Y", [KEY_Z] = "Z",
    [KEY_0] = "0", [KEY_1] = "1", [KEY_2] = "2", [KEY_3] = "3",
    [KEY_4] = "4", [KEY_5] = "5", [KEY_6] = "6", [KEY_7] = "7",
    [KEY_8] = "8", [KEY_9] = "9",
    [KEY_SPACE] = "空格", [KEY_RETURN] = "回车", [KEY_TAB] = "Tab",
    [KEY_SHIFT] = "Shift", [KEY_CTRL] = "Ctrl", [KEY_ALT] = "Alt",
    [KEY_LEFT] = "←", [KEY_RIGHT] = "→", [KEY_UP] = "↑", [KEY_DOWN] = "↓",
    [KEY_ESCAPE] = "ESC", [KEY_BACKSPACE] = "退格", [KEY_DELETE] = "DEL",
}

-- 操作定义（id, 显示名, 分类）
KeyBindings.Actions = {
    -- === 试炼场 ===
    { id = "move_left",   name = "左移",     category = "试炼场" },
    { id = "move_right",  name = "右移",     category = "试炼场" },
    { id = "move_down",   name = "下蹲/下跳", category = "试炼场" },
    { id = "jump",        name = "跳跃",     category = "试炼场" },
    { id = "attack1",     name = "攻击 1",   category = "试炼场" },
    { id = "attack2",     name = "攻击 2",   category = "试炼场" },
    { id = "transform",   name = "变形",     category = "试炼场" },
    -- === 锻造 ===
    { id = "forge_hit",   name = "锤击/淬火", category = "锻造" },
    { id = "grind1",      name = "砥砺 1",   category = "锻造" },
    { id = "grind2",      name = "砥砺 2",   category = "锻造" },
    { id = "grind3",      name = "砥砺 3",   category = "锻造" },
    -- === 绘图 ===
    { id = "draw_undo",   name = "撤销",     category = "绘图" },
    { id = "draw_clear",  name = "清除",     category = "绘图" },
}

-- 默认绑定（每个 action 可绑定多个键）
local DEFAULT_BINDINGS = {
    move_left  = { KEY_A, KEY_LEFT },
    move_right = { KEY_D, KEY_RIGHT },
    move_down  = { KEY_S, KEY_DOWN },
    jump       = { KEY_SPACE, KEY_W, KEY_UP },
    attack1    = { KEY_J },
    attack2    = { KEY_K },
    transform  = { KEY_Q },
    forge_hit  = { KEY_SPACE },
    grind1     = { KEY_J },
    grind2     = { KEY_K },
    grind3     = { KEY_L },
    draw_undo  = { KEY_Z },
    draw_clear = { KEY_X },
}

-- 当前绑定（运行时修改的版本）
local bindings_ = {}

--- 初始化（加载保存的配置或使用默认）
function KeyBindings.Init()
    -- 深拷贝默认绑定
    for actionId, keys in pairs(DEFAULT_BINDINGS) do
        bindings_[actionId] = {}
        for i = 1, #keys do
            bindings_[actionId][i] = keys[i]
        end
    end

    -- 尝试从本地存储加载自定义配置
    KeyBindings.Load()
end

--- 获取某个操作绑定的所有键
---@param actionId string
---@return table
function KeyBindings.GetKeys(actionId)
    return bindings_[actionId] or {}
end

--- 检查某个键是否对应某个操作
---@param actionId string
---@param key number
---@return boolean
function KeyBindings.IsKey(actionId, key)
    local keys = bindings_[actionId]
    if not keys then return false end
    for i = 1, #keys do
        if keys[i] == key then return true end
    end
    return false
end

--- 检查某个操作是否正在按下（GetKeyDown）
---@param actionId string
---@return boolean
function KeyBindings.IsDown(actionId)
    local keys = bindings_[actionId]
    if not keys then return false end
    for i = 1, #keys do
        if input:GetKeyDown(keys[i]) then return true end
    end
    return false
end

--- 设置某个操作的按键绑定
---@param actionId string
---@param keys table  按键数组
function KeyBindings.SetKeys(actionId, keys)
    bindings_[actionId] = keys
end

--- 获取按键的显示名称
---@param key number
---@return string
function KeyBindings.GetKeyName(key)
    return KEY_NAMES[key] or ("?=" .. tostring(key))
end

--- 获取某操作当前绑定的显示文字
---@param actionId string
---@return string
function KeyBindings.GetDisplayText(actionId)
    local keys = bindings_[actionId]
    if not keys or #keys == 0 then return "未绑定" end
    local parts = {}
    for i = 1, #keys do
        parts[i] = KeyBindings.GetKeyName(keys[i])
    end
    return table.concat(parts, " / ")
end

--- 恢复默认绑定
function KeyBindings.ResetToDefault()
    for actionId, keys in pairs(DEFAULT_BINDINGS) do
        bindings_[actionId] = {}
        for i = 1, #keys do
            bindings_[actionId][i] = keys[i]
        end
    end
    KeyBindings.Save()
end

--- 保存到本地
function KeyBindings.Save()
    local cjson = require("cjson")
    local data = {}
    for actionId, keys in pairs(bindings_) do
        data[actionId] = keys
    end
    local json = cjson.encode(data)
    local file = File:new("keybindings.json", FILE_WRITE)
    if file then
        file:WriteString(json)
        file:Close()
        file:delete()
    end
end

--- 从本地加载
function KeyBindings.Load()
    if not fileSystem:FileExists("keybindings.json") then
        return
    end
    local cjson = require("cjson")
    local file = File:new("keybindings.json", FILE_READ)
    if file then
        local json = file:ReadString()
        file:Close()
        file:delete()
        if json and #json > 0 then
            local ok, data = pcall(cjson.decode, json)
            if ok and type(data) == "table" then
                for actionId, keys in pairs(data) do
                    if DEFAULT_BINDINGS[actionId] then
                        bindings_[actionId] = keys
                    end
                end
                print("[KeyBindings] Loaded custom bindings")
            end
        end
    end
end

--- 获取砥砺按键序列名（供 ForgeState 使用）
---@return table  如 {"J", "K", "L"}
function KeyBindings.GetGrindKeyNames()
    local names = {}
    local grindActions = { "grind1", "grind2", "grind3" }
    for i = 1, #grindActions do
        local keys = bindings_[grindActions[i]]
        if keys and #keys > 0 then
            names[i] = KeyBindings.GetKeyName(keys[1])
        else
            names[i] = "?"
        end
    end
    return names
end

--- 检查按键的砥砺序列匹配（返回匹配的砥砺编号 1/2/3，或 nil）
---@param key number
---@return number|nil
function KeyBindings.GetGrindIndex(key)
    if KeyBindings.IsKey("grind1", key) then return 1 end
    if KeyBindings.IsKey("grind2", key) then return 2 end
    if KeyBindings.IsKey("grind3", key) then return 3 end
    return nil
end

return KeyBindings
