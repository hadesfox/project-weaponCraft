-- ============================================================================
-- States/ResultState.lua - 锻造结果展示
-- 展示武器属性、品质、特殊效果
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")

local ResultState = {}

local gameData_ = nil
local onComplete_ = nil

-- 前向声明内部函数
local GenerateWeaponData
local CreateStatRow

--- 进入结果状态
function ResultState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    
    -- 生成武器最终数据
    GenerateWeaponData()
    
    print("[ResultState] Weapon: " .. gameData_.weaponData.name .. " Quality: " .. gameData_.quality.name)
end

--- 生成武器数据
GenerateWeaponData = function()
    local weaponType = gameData_.weaponType or "UNKNOWN"
    local typeInfo = Config.WeaponTypes[weaponType] or Config.WeaponTypes.UNKNOWN
    local quality = gameData_.quality or Config.Quality[1]
    local score = gameData_.forgeScore or 0
    
    -- 基础属性（根据类型）
    local baseStats = {
        SWORD = { atk = 40, spd = 1.2, range = 1.0 },
        AXE = { atk = 60, spd = 0.7, range = 1.3 },
        SPEAR = { atk = 35, spd = 1.0, range = 2.0 },
        SHIELD = { atk = 15, spd = 0.5, range = 0.5, def = 50 },
        HOOK = { atk = 30, spd = 1.5, range = 1.5 },
        UNKNOWN = { atk = 25, spd = 1.0, range = 1.0 },
    }
    
    local base = baseStats[weaponType] or baseStats.UNKNOWN
    
    -- 品质加成（score 0-100 映射到 1.0-2.0 倍率）
    local multiplier = 1.0 + score / 100
    
    -- 武器名称生成
    local prefixes = {
        [1] = { "破旧的", "生锈的" },
        [2] = { "普通的", "标准的" },
        [3] = { "精炼的", "锐利的" },
        [4] = { "闪耀的", "上古的" },
        [5] = { "传说中的", "神话之" },
    }
    
    local qualityIdx = 1
    for i = #Config.Quality, 1, -1 do
        if score >= Config.Quality[i].threshold then
            qualityIdx = i
            break
        end
    end
    
    local prefix = prefixes[qualityIdx][math.random(1, #prefixes[qualityIdx])]
    
    local weaponData = {
        name = prefix .. typeInfo.name,
        type = weaponType,
        typeInfo = typeInfo,
        atk = math.floor(base.atk * multiplier),
        spd = base.spd,
        range = base.range,
        def = base.def and math.floor(base.def * multiplier) or 0,
        score = score,
        isComposite = gameData_.isComposite,
    }
    
    -- 复合武器特殊属性
    if gameData_.isComposite then
        weaponData.name = "✨ " .. weaponData.name .. "（变形）"
        weaponData.modes = { "形态一", "形态二" }
        weaponData.atk = math.floor(weaponData.atk * 1.3)
    end
    
    gameData_.weaponData = weaponData
end

--- 构建结果 UI
function ResultState.BuildUI()
    local wd = gameData_.weaponData
    local quality = gameData_.quality
    
    local statsChildren = {
        CreateStatRow("⚔️ 攻击力", tostring(wd.atk)),
        CreateStatRow("⚡ 攻速", string.format("%.1f", wd.spd)),
        CreateStatRow("📏 范围", string.format("%.1f", wd.range)),
    }
    if wd.def > 0 then
        statsChildren[#statsChildren + 1] = CreateStatRow("🛡️ 防御", tostring(wd.def))
    end
    if wd.isComposite then
        statsChildren[#statsChildren + 1] = CreateStatRow("🔄 形态", tostring(#wd.modes) .. " 种变形")
    end
    
    return UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = Config.Colors.BgDark,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = "90%", maxWidth = 380,
                padding = 30, gap = 16,
                backgroundColor = Config.Colors.BgMedium,
                borderRadius = 16,
                borderWidth = 2,
                borderColor = quality.color,
                alignItems = "center",
                children = {
                    -- 品质标签
                    UI.Label {
                        text = "— " .. quality.name .. " —",
                        fontSize = 14,
                        fontColor = quality.color,
                    },
                    -- 武器名称
                    UI.Label {
                        text = wd.name,
                        fontSize = 22,
                        fontColor = Config.Colors.TextLight,
                    },
                    -- 类型
                    UI.Label {
                        text = wd.typeInfo.icon .. " " .. wd.typeInfo.name,
                        fontSize = 14,
                        fontColor = { 120, 130, 140, 255 },
                    },
                    -- 分割线
                    UI.Panel {
                        width = "80%", height = 1,
                        backgroundColor = { 50, 50, 55, 100 },
                        marginTop = 4, marginBottom = 4,
                    },
                    -- 属性列表
                    UI.Panel {
                        width = "100%",
                        gap = 6,
                        children = statsChildren,
                    },
                    -- 锻造评分（分项 + 总分）
                    UI.Panel {
                        width = "100%",
                        marginTop = 8,
                        gap = 4,
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                width = "80%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                children = {
                                    UI.Label {
                                        text = "🔨 锤击",
                                        fontSize = 12,
                                        fontColor = { 120, 130, 140, 255 },
                                    },
                                    UI.Label {
                                        text = tostring(gameData_.hammerScore or 0),
                                        fontSize = 12,
                                        fontColor = { 120, 130, 140, 255 },
                                    },
                                },
                            },
                            UI.Panel {
                                width = "80%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                children = {
                                    UI.Label {
                                        text = "💧 淬火",
                                        fontSize = 12,
                                        fontColor = { 120, 130, 140, 255 },
                                    },
                                    UI.Label {
                                        text = tostring(gameData_.quenchScore or 0),
                                        fontSize = 12,
                                        fontColor = { 120, 130, 140, 255 },
                                    },
                                },
                            },
                            UI.Panel {
                                width = "80%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                children = {
                                    UI.Label {
                                        text = "⚡ 砥砺",
                                        fontSize = 12,
                                        fontColor = { 120, 130, 140, 255 },
                                    },
                                    UI.Label {
                                        text = tostring(gameData_.grindScore or 0),
                                        fontSize = 12,
                                        fontColor = { 120, 130, 140, 255 },
                                    },
                                },
                            },
                            UI.Panel {
                                width = "80%", height = 1,
                                backgroundColor = { 50, 50, 55, 100 },
                                marginTop = 2, marginBottom = 2,
                            },
                            UI.Panel {
                                width = "80%",
                                flexDirection = "row",
                                justifyContent = "space-between",
                                children = {
                                    UI.Label {
                                        text = "总评分",
                                        fontSize = 14,
                                        fontColor = Config.Colors.Gold,
                                    },
                                    UI.Label {
                                        text = tostring(gameData_.forgeScore) .. "/100",
                                        fontSize = 14,
                                        fontColor = Config.Colors.Gold,
                                    },
                                },
                            },
                        },
                    },
                    -- 复合提示
                    wd.isComposite and UI.Panel {
                        width = "100%",
                        padding = 8,
                        backgroundColor = { 160, 140, 90, 20 },
                        borderRadius = 8,
                        children = {
                            UI.Label {
                                text = "🌟 隐藏机制触发！武器可变形切换",
                                fontSize = 12,
                                fontColor = Config.Colors.Gold,
                                textAlign = "center",
                            },
                        },
                    } or nil,
                    -- 进入试炼按钮
                    UI.Button {
                        text = "进入试炼场 →",
                        variant = "primary",
                        width = 200,
                        marginTop = 12,
                        onClick = function()
                            if onComplete_ then onComplete_() end
                        end,
                    },
                },
            },
        },
    }
end

--- 创建属性行
CreateStatRow = function(label, value)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        children = {
            UI.Label {
                text = label,
                fontSize = 14,
                fontColor = { 120, 130, 140, 255 },
            },
            UI.Label {
                text = value,
                fontSize = 14,
                fontColor = Config.Colors.TextLight,
            },
        },
    }
end

function ResultState.Update(dt)
    -- 结果页面不需要更新逻辑
end

function ResultState.Leave()
    -- 结果页面无需特殊清理
end

function ResultState.Render(vg)
    -- 结果页面纯 UI，无 NanoVG 自绘
end

function ResultState.OnKeyDown(key)
    if key == KEY_RETURN or key == KEY_SPACE then
        if onComplete_ then onComplete_() end
    end
end

function ResultState.OnMouseDown(button)
    if button == MOUSEB_LEFT then
        if onComplete_ then onComplete_() end
    end
end

function ResultState.OnMouseUp(button)
end

function ResultState.OnMouseMove()
end

function ResultState.OnTouchBegin(x, y)
    if onComplete_ then onComplete_() end
end

function ResultState.OnTouchMove(x, y)
end

function ResultState.OnTouchEnd(x, y)
end

return ResultState
