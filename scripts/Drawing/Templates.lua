-- ============================================================================
-- Drawing/Templates.lua - 预设武器模板
-- 提供几个标准形状供玩家参考或直接使用
-- ============================================================================

local Templates = {}

-- 生成圆弧上的点
local function ArcPoints(cx, cy, radius, startAngle, endAngle, steps)
    local pts = {}
    for i = 0, steps do
        local angle = startAngle + (endAngle - startAngle) * i / steps
        pts[#pts + 1] = {
            x = cx + math.cos(angle) * radius,
            y = cy + math.sin(angle) * radius,
        }
    end
    return pts
end

-- 模板: 直剑
Templates.Sword = {
    name = "直剑",
    icon = "⚔️",
    description = "经典直剑，攻速快",
    strokes = {
        {
            points = (function()
                local pts = {}
                -- 剑身（从下到上的细长形状）
                local cx, cy = 200, 200
                -- 左边缘
                pts[#pts + 1] = { x = cx - 12, y = cy + 120 }
                pts[#pts + 1] = { x = cx - 15, y = cy + 100 }
                pts[#pts + 1] = { x = cx - 10, y = cy + 40 }
                pts[#pts + 1] = { x = cx - 8, y = cy - 20 }
                pts[#pts + 1] = { x = cx - 6, y = cy - 80 }
                -- 剑尖
                pts[#pts + 1] = { x = cx, y = cy - 130 }
                -- 右边缘
                pts[#pts + 1] = { x = cx + 6, y = cy - 80 }
                pts[#pts + 1] = { x = cx + 8, y = cy - 20 }
                pts[#pts + 1] = { x = cx + 10, y = cy + 40 }
                pts[#pts + 1] = { x = cx + 15, y = cy + 100 }
                pts[#pts + 1] = { x = cx + 12, y = cy + 120 }
                -- 闭合
                pts[#pts + 1] = { x = cx - 12, y = cy + 120 }
                return pts
            end)(),
            closed = true,
        },
        {
            -- 护手（横线）
            points = (function()
                local cx, cy = 200, 320
                local pts = {}
                pts[#pts + 1] = { x = cx - 35, y = cy }
                pts[#pts + 1] = { x = cx - 30, y = cy - 5 }
                pts[#pts + 1] = { x = cx + 30, y = cy - 5 }
                pts[#pts + 1] = { x = cx + 35, y = cy }
                pts[#pts + 1] = { x = cx + 30, y = cy + 5 }
                pts[#pts + 1] = { x = cx - 30, y = cy + 5 }
                pts[#pts + 1] = { x = cx - 35, y = cy }
                return pts
            end)(),
            closed = true,
        },
    },
}

-- 模板: 战斧
Templates.Axe = {
    name = "战斧",
    icon = "🪓",
    description = "范围大，伤害高",
    strokes = {
        {
            -- 斧头部分（宽弧形）
            points = (function()
                local pts = {}
                local cx, cy = 200, 160
                -- 斧刃弧形
                for i = 0, 12 do
                    local angle = -math.pi * 0.6 + math.pi * 1.2 * i / 12
                    pts[#pts + 1] = {
                        x = cx + math.cos(angle) * 60,
                        y = cy + math.sin(angle) * 50,
                    }
                end
                -- 内弧（较小）
                for i = 12, 0, -1 do
                    local angle = -math.pi * 0.6 + math.pi * 1.2 * i / 12
                    pts[#pts + 1] = {
                        x = cx + math.cos(angle) * 20,
                        y = cy + math.sin(angle) * 15,
                    }
                end
                pts[#pts + 1] = pts[1]
                return pts
            end)(),
            closed = true,
        },
        {
            -- 斧柄
            points = (function()
                local pts = {}
                local cx = 200
                pts[#pts + 1] = { x = cx - 5, y = 200 }
                pts[#pts + 1] = { x = cx - 5, y = 350 }
                pts[#pts + 1] = { x = cx + 5, y = 350 }
                pts[#pts + 1] = { x = cx + 5, y = 200 }
                return pts
            end)(),
            closed = false,
        },
    },
}

-- 模板: 圆盾
Templates.Shield = {
    name = "圆盾",
    icon = "🛡️",
    description = "防御利器，可弹反",
    strokes = {
        {
            points = (function()
                local pts = {}
                local cx, cy = 200, 200
                local radius = 80
                for i = 0, 24 do
                    local angle = math.pi * 2 * i / 24
                    pts[#pts + 1] = {
                        x = cx + math.cos(angle) * radius,
                        y = cy + math.sin(angle) * radius,
                    }
                end
                return pts
            end)(),
            closed = true,
        },
        {
            -- 盾心装饰
            points = (function()
                local pts = {}
                local cx, cy = 200, 200
                local radius = 25
                for i = 0, 16 do
                    local angle = math.pi * 2 * i / 16
                    pts[#pts + 1] = {
                        x = cx + math.cos(angle) * radius,
                        y = cy + math.sin(angle) * radius,
                    }
                end
                return pts
            end)(),
            closed = true,
        },
    },
}

--- 获取所有模板列表
function Templates.GetList()
    return {
        { key = "sword", data = Templates.Sword },
        { key = "axe", data = Templates.Axe },
        { key = "shield", data = Templates.Shield },
    }
end

--- 根据 key 获取模板
function Templates.Get(key)
    if key == "sword" then return Templates.Sword
    elseif key == "axe" then return Templates.Axe
    elseif key == "shield" then return Templates.Shield
    end
    return nil
end

return Templates
