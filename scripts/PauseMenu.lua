-- ============================================================================
-- PauseMenu.lua - ESC 暂停菜单模块
-- 所有游戏环节（除主菜单外）按 ESC 暂停并弹出菜单
-- 试炼场额外展示左侧武器信息卡片
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")

local PauseMenu = {}

local visible_ = false
local overlayRoot_ = nil        -- 暂停菜单 UI 根节点
local prevUiRoot_ = nil         -- 暂停前的 UI 根节点（用于恢复）
local onReturnMenu_ = nil       -- "返回主界面"回调
local onResume_ = nil           -- "继续游戏"回调

--- 判断暂停菜单是否正在显示
function PauseMenu.IsVisible()
    return visible_
end

--- 显示暂停菜单
--- @param opts table { onReturnMenu: function, weaponData?: table, material?: table, quality?: table }
function PauseMenu.Show(opts)
    if visible_ then return end
    visible_ = true
    onReturnMenu_ = opts and opts.onReturnMenu or nil
    onResume_ = opts and opts.onResume or nil

    local weaponData = opts and opts.weaponData or nil
    local material = opts and opts.material or nil
    local quality = opts and opts.quality or nil

    -- 构建菜单内容
    local menuChildren = {}

    -- 如果有武器数据（试炼场），左侧显示武器卡片
    local leftCard = nil
    if weaponData then
        leftCard = PauseMenu._BuildWeaponCard(weaponData, material, quality)
    end

    -- 右侧/中间菜单面板
    local menuPanel = UI.Panel {
        width = 240,
        padding = 24, gap = 16,
        backgroundColor = { 30, 32, 42, 245 },
        borderRadius = 14,
        borderWidth = 2,
        borderColor = { 80, 80, 100, 180 },
        alignItems = "center",
        children = {
            UI.Label {
                text = "游戏暂停",
                fontSize = 20,
                fontColor = Config.Colors.TextLight,
            },
            -- 分割线
            UI.Panel {
                width = "80%", height = 1,
                backgroundColor = { 60, 60, 70, 150 },
            },
            -- 继续游戏
            UI.Button {
                text = "继续游戏",
                variant = "primary",
                width = "100%",
                onClick = function()
                    local cb = onResume_
                    PauseMenu.Hide()
                    if cb then cb() end
                end,
            },
            -- 返回主界面
            UI.Button {
                text = "返回主界面",
                variant = "outline",
                width = "100%",
                onClick = function()
                    local cb = onReturnMenu_
                    PauseMenu.Hide()
                    if cb then cb() end
                end,
            },
        },
    }

    -- 布局：如果有武器卡片则双列，否则居中单列
    local contentChildren
    if leftCard then
        contentChildren = {
            UI.Panel {
                flexDirection = "row",
                gap = 20,
                alignItems = "center",
                children = {
                    leftCard,
                    menuPanel,
                },
            },
        }
    else
        contentChildren = { menuPanel }
    end

    overlayRoot_ = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        children = contentChildren,
    }

    -- 保存当前 UI 并替换为暂停菜单
    prevUiRoot_ = nil  -- 由外部 main.lua 管理恢复
    UI.SetRoot(overlayRoot_)
end

--- 隐藏暂停菜单
function PauseMenu.Hide()
    if not visible_ then return end
    visible_ = false
    overlayRoot_ = nil
    onReturnMenu_ = nil
end

--- 获取暂停覆盖层根节点（用于外部 SetRoot 恢复判断）
function PauseMenu.GetOverlayRoot()
    return overlayRoot_
end

--- 构建武器信息卡片（试炼场专用）
function PauseMenu._BuildWeaponCard(wd, mat, quality)
    local borderColor = quality and quality.color or { 80, 80, 100, 180 }

    -- 属性行
    local function StatRow(label, value)
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            children = {
                UI.Label { text = label, fontSize = 13, fontColor = { 120, 130, 140, 255 } },
                UI.Label { text = value, fontSize = 13, fontColor = Config.Colors.TextLight },
            },
        }
    end

    -- 计算显示属性（含材质加成）
    local displayAtk = wd.atk or 0
    local displaySpd = wd.spd or 1.0
    if mat then
        displayAtk = math.floor(wd.atk * (1 + (mat.atkMod or 0)))
        displaySpd = wd.spd * (1 + (mat.spdMod or 0))
    end

    local statsChildren = {
        StatRow("⚔️ 攻击力", tostring(displayAtk)),
        StatRow("⚡ 攻速", string.format("%.2f", displaySpd)),
        StatRow("📏 范围", string.format("%.1f", wd.range or 0)),
    }
    if wd.def and wd.def > 0 then
        statsChildren[#statsChildren + 1] = StatRow("🛡️ 防御", tostring(wd.def))
    end
    if wd.isComposite then
        statsChildren[#statsChildren + 1] = StatRow("🔄 形态", "2 种变形")
    end

    local cardChildren = {}

    -- 品质标签
    if quality then
        cardChildren[#cardChildren + 1] = UI.Label {
            text = "— " .. quality.name .. " —",
            fontSize = 12,
            fontColor = quality.color,
        }
    end

    -- 武器名称
    cardChildren[#cardChildren + 1] = UI.Label {
        text = wd.name or "未知武器",
        fontSize = 18,
        fontColor = Config.Colors.TextLight,
    }

    -- 类型
    if wd.typeInfo then
        cardChildren[#cardChildren + 1] = UI.Label {
            text = wd.typeInfo.icon .. " " .. wd.typeInfo.name,
            fontSize = 12,
            fontColor = { 120, 130, 140, 255 },
        }
    end

    -- 分割线
    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "80%", height = 1,
        backgroundColor = { 50, 50, 55, 100 },
        marginTop = 4, marginBottom = 4,
    }

    -- 属性列表
    cardChildren[#cardChildren + 1] = UI.Panel {
        width = "100%", gap = 5,
        children = statsChildren,
    }

    -- 材质信息
    if mat then
        cardChildren[#cardChildren + 1] = UI.Panel {
            width = "100%",
            padding = 8, marginTop = 4,
            backgroundColor = { mat.color[1], mat.color[2], mat.color[3], 30 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = { mat.color[1], mat.color[2], mat.color[3], 120 },
            gap = 3,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "材质: " .. mat.name,
                    fontSize = 12,
                    fontColor = { mat.color[1], mat.color[2], mat.color[3], 255 },
                },
                UI.Label {
                    text = mat.desc,
                    fontSize = 11,
                    fontColor = { 200, 205, 210, 200 },
                },
            },
        }
    end

    return UI.Panel {
        width = 220,
        padding = 18, gap = 10,
        backgroundColor = { 30, 32, 42, 245 },
        borderRadius = 14,
        borderWidth = 2,
        borderColor = borderColor,
        alignItems = "center",
        children = cardChildren,
    }
end

return PauseMenu
