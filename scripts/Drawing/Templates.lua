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

-- 模板: 直剑（单笔画，避免触发复合武器判定）
-- 设计要点：ar 约 2.5-3.0（剑类），宽护手拉低纵横比，左右对称
Templates.Sword = {
    name = "直剑",
    icon = "⚔️",
    description = "经典直剑，攻速快",
    strokes = {
        {
            -- 完整剑轮廓（剑身+护手一体）
            -- 整体高约 250，宽约 90（护手），ar ≈ 250/90 ≈ 2.8
            points = (function()
                local pts = {}
                local cx = 200
                -- 剑尖
                pts[#pts + 1] = { x = cx, y = 80 }
                -- 右刃（较宽的剑身）
                pts[#pts + 1] = { x = cx + 10, y = 110 }
                pts[#pts + 1] = { x = cx + 14, y = 160 }
                pts[#pts + 1] = { x = cx + 16, y = 210 }
                pts[#pts + 1] = { x = cx + 14, y = 250 }
                -- 右护手（宽）
                pts[#pts + 1] = { x = cx + 14, y = 255 }
                pts[#pts + 1] = { x = cx + 45, y = 255 }
                pts[#pts + 1] = { x = cx + 45, y = 268 }
                pts[#pts + 1] = { x = cx + 14, y = 268 }
                -- 剑柄右侧
                pts[#pts + 1] = { x = cx + 8, y = 272 }
                pts[#pts + 1] = { x = cx + 8, y = 320 }
                -- 柄底圆头
                pts[#pts + 1] = { x = cx + 12, y = 328 }
                pts[#pts + 1] = { x = cx, y = 333 }
                pts[#pts + 1] = { x = cx - 12, y = 328 }
                -- 剑柄左侧
                pts[#pts + 1] = { x = cx - 8, y = 320 }
                pts[#pts + 1] = { x = cx - 8, y = 272 }
                -- 左护手（宽）
                pts[#pts + 1] = { x = cx - 14, y = 268 }
                pts[#pts + 1] = { x = cx - 45, y = 268 }
                pts[#pts + 1] = { x = cx - 45, y = 255 }
                pts[#pts + 1] = { x = cx - 14, y = 255 }
                -- 左刃
                pts[#pts + 1] = { x = cx - 14, y = 250 }
                pts[#pts + 1] = { x = cx - 16, y = 210 }
                pts[#pts + 1] = { x = cx - 14, y = 160 }
                pts[#pts + 1] = { x = cx - 10, y = 110 }
                -- 回到剑尖闭合
                pts[#pts + 1] = { x = cx, y = 80 }
                return pts
            end)(),
            closed = true,
        },
    },
}

-- 模板: 战斧（单笔画，避免触发复合武器判定）
-- 设计要点：ar 约 1.5-2.5（斧类），斧刃偏右侧，左右不对称 asym > 1.8
Templates.Axe = {
    name = "战斧",
    icon = "🪓",
    description = "范围大，伤害高",
    strokes = {
        {
            -- 完整斧轮廓（斧刃在右侧，柄居左）
            -- 宽约 120（右侧刃宽），高约 280，ar ≈ 2.3，asym ≈ 3+
            points = (function()
                local pts = {}
                local cx = 180  -- 偏左，让斧刃向右展开
                -- 从柄顶左侧开始，顺时针
                -- 柄顶（窄）
                pts[#pts + 1] = { x = cx - 6, y = 90 }
                pts[#pts + 1] = { x = cx + 6, y = 90 }
                -- 柄右侧向下到斧头连接处
                pts[#pts + 1] = { x = cx + 6, y = 130 }
                -- 斧刃顶部（向右展开）
                pts[#pts + 1] = { x = cx + 30, y = 120 }
                pts[#pts + 1] = { x = cx + 60, y = 125 }
                pts[#pts + 1] = { x = cx + 80, y = 140 }
                -- 斧刃弧线（右侧大弧）
                pts[#pts + 1] = { x = cx + 90, y = 160 }
                pts[#pts + 1] = { x = cx + 92, y = 180 }
                pts[#pts + 1] = { x = cx + 88, y = 200 }
                pts[#pts + 1] = { x = cx + 78, y = 218 }
                -- 斧刃底部（收回）
                pts[#pts + 1] = { x = cx + 60, y = 230 }
                pts[#pts + 1] = { x = cx + 35, y = 238 }
                pts[#pts + 1] = { x = cx + 6, y = 235 }
                -- 柄右侧继续向下
                pts[#pts + 1] = { x = cx + 6, y = 360 }
                -- 柄底
                pts[#pts + 1] = { x = cx + 10, y = 368 }
                pts[#pts + 1] = { x = cx - 10, y = 368 }
                -- 柄左侧向上
                pts[#pts + 1] = { x = cx - 6, y = 360 }
                pts[#pts + 1] = { x = cx - 6, y = 130 }
                -- 闭合回柄顶
                pts[#pts + 1] = { x = cx - 6, y = 90 }
                return pts
            end)(),
            closed = true,
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
