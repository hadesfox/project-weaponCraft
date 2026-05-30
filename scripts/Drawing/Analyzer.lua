-- ============================================================================
-- Drawing/Analyzer.lua - 形状分析模块
-- 分析绘制的笔画，识别武器类型和特征
-- ============================================================================

local Config = require("Config")

local Analyzer = {}

--- 分析所有笔画，返回武器类型和属性
---@param strokes table[] 笔画数组
---@return table 分析结果 {type, features, isComposite, shapeCount}
function Analyzer.Analyze(strokes)
    if not strokes or #strokes == 0 then
        return { type = "UNKNOWN", features = {}, isComposite = false, shapeCount = 0 }
    end
    
    local result = {
        type = "UNKNOWN",
        features = {},
        isComposite = false,
        shapeCount = #strokes,
        bounds = {},       -- 每个笔画的包围盒
        totalArea = 0,
        aspectRatio = 1,
        pointCount = 0,    -- 尖端数量
        closedCount = 0,   -- 闭合形状数量
    }
    
    -- 计算各笔画的包围盒和特征
    local allMinX, allMinY = math.huge, math.huge
    local allMaxX, allMaxY = -math.huge, -math.huge
    
    for i = 1, #strokes do
        local stroke = strokes[i]
        local bounds = ComputeBounds(stroke.points)
        result.bounds[i] = bounds
        
        if stroke.closed then
            result.closedCount = result.closedCount + 1
        end
        
        allMinX = math.min(allMinX, bounds.minX)
        allMinY = math.min(allMinY, bounds.minY)
        allMaxX = math.max(allMaxX, bounds.maxX)
        allMaxY = math.max(allMaxY, bounds.maxY)
    end
    
    -- 整体尺寸
    local totalW = allMaxX - allMinX
    local totalH = allMaxY - allMinY
    if totalW < 1 then totalW = 1 end
    if totalH < 1 then totalH = 1 end
    result.aspectRatio = totalH / totalW  -- >1 表示纵向
    
    -- 尖端检测
    result.pointCount = CountSharpPoints(strokes)
    
    -- 判断是否为复合武器（隐藏机制）
    result.isComposite = DetectComposite(strokes, result)
    
    -- 武器类型识别
    result.type = ClassifyWeapon(result, strokes)
    
    local wr, ws = ComputeWidthProfile(strokes)
    print("[Analyzer] Type: " .. result.type 
        .. " | Strokes: " .. #strokes
        .. " | AR: " .. string.format("%.2f", result.aspectRatio)
        .. " | WR: " .. string.format("%.1f", wr)
        .. " | WS: " .. string.format("%.2f", ws)
        .. " | Points: " .. result.pointCount
        .. " | Closed: " .. result.closedCount
        .. " | Composite: " .. tostring(result.isComposite))
    
    return result
end

--- 计算点集的包围盒
function ComputeBounds(points)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    
    for i = 1, #points do
        local p = points[i]
        minX = math.min(minX, p.x)
        minY = math.min(minY, p.y)
        maxX = math.max(maxX, p.x)
        maxY = math.max(maxY, p.y)
    end
    
    return {
        minX = minX, minY = minY,
        maxX = maxX, maxY = maxY,
        width = maxX - minX,
        height = maxY - minY,
        centerX = (minX + maxX) / 2,
        centerY = (minY + maxY) / 2,
    }
end

--- 检测尖锐顶点数量
function CountSharpPoints(strokes)
    local sharpCount = 0
    local threshold = math.cos(math.rad(Config.Analyzer.SharpAngleDeg))
    local minEdge = Config.Analyzer.MinEdgeLength
    
    for _, stroke in ipairs(strokes) do
        local pts = stroke.points
        if #pts >= 3 then
            for i = 2, #pts - 1 do
                local ax = pts[i].x - pts[i-1].x
                local ay = pts[i].y - pts[i-1].y
                local bx = pts[i+1].x - pts[i].x
                local by = pts[i+1].y - pts[i].y
                
                local lenA = math.sqrt(ax*ax + ay*ay)
                local lenB = math.sqrt(bx*bx + by*by)
                
                if lenA > minEdge and lenB > minEdge then
                    local dot = (ax*bx + ay*by) / (lenA * lenB)
                    if dot < -threshold then  -- 角度大于 (180-SharpAngleDeg) = 尖锐转折
                        sharpCount = sharpCount + 1
                    end
                end
            end
        end
    end
    
    return sharpCount
end

--- 检测复合武器（隐藏机制）
--- 条件：2-3个独立形状 + 至少1个闭合形状 + 形状间有连接趋势
function DetectComposite(strokes, result)
    -- 至少2个笔画
    if #strokes < 2 then return false end
    
    -- 至少1个闭合
    if result.closedCount < 1 then return false end
    
    -- 检测形状间是否接近（连接点检测）
    local connectionCount = 0
    for i = 1, #strokes - 1 do
        for j = i + 1, #strokes do
            if AreStrokesConnected(strokes[i], strokes[j]) then
                connectionCount = connectionCount + 1
            end
        end
    end
    
    -- 有连接关系的独立形状 = 复合潜力
    return connectionCount >= 1 and #strokes >= 2
end

--- 判断两个笔画是否有连接关系
function AreStrokesConnected(strokeA, strokeB)
    local threshold = Config.Analyzer.ConnectionDistanceSq
    local ptsA = strokeA.points
    local ptsB = strokeB.points
    
    if #ptsA == 0 or #ptsB == 0 then return false end
    
    -- 检查 A 的端点和 B 的端点/边缘距离
    local checkPoints = {
        ptsA[1], ptsA[#ptsA],
        ptsB[1], ptsB[#ptsB],
    }
    
    -- A的首尾 vs B的首尾
    for ai = 1, 2 do
        for bi = 3, 4 do
            local dx = checkPoints[ai].x - checkPoints[bi].x
            local dy = checkPoints[ai].y - checkPoints[bi].y
            if dx*dx + dy*dy < threshold then
                return true
            end
        end
    end
    
    return false
end

--- 分析形状的宽度分布特征（用于区分斧和剑）
--- 将形状按高度切成若干水平带，统计每带的宽度
--- 返回: widthRatio（最大宽/最小宽）, wideSpan（宽区域占比）
function ComputeWidthProfile(strokes)
    if not strokes or #strokes == 0 then return 1.0, 0 end
    -- 收集所有点
    local allPts = {}
    local minY, maxY = math.huge, -math.huge
    for _, stroke in ipairs(strokes) do
        for _, p in ipairs(stroke.points) do
            allPts[#allPts + 1] = p
            minY = math.min(minY, p.y)
            maxY = math.max(maxY, p.y)
        end
    end
    if #allPts < 3 then return 1.0, 0 end
    local totalH = maxY - minY
    if totalH < 1 then return 1.0, 0 end

    -- 将形状分成 8 个水平带，计算每带的 X 跨度
    local numBands = 8
    local bandH = totalH / numBands
    local bandWidths = {}
    for b = 1, numBands do
        local bMinY = minY + (b - 1) * bandH
        local bMaxY = minY + b * bandH
        local bMinX, bMaxX = math.huge, -math.huge
        local hasPoints = false
        for _, p in ipairs(allPts) do
            if p.y >= bMinY and p.y <= bMaxY then
                bMinX = math.min(bMinX, p.x)
                bMaxX = math.max(bMaxX, p.x)
                hasPoints = true
            end
        end
        if hasPoints and bMaxX > bMinX then
            bandWidths[#bandWidths + 1] = bMaxX - bMinX
        else
            bandWidths[#bandWidths + 1] = 0
        end
    end

    -- 找最大宽度和最小非零宽度
    local maxW = 0
    local minW = math.huge
    for _, w in ipairs(bandWidths) do
        if w > maxW then maxW = w end
        if w > 0 and w < minW then minW = w end
    end
    if minW == math.huge or minW < 1 then minW = 1 end
    local widthRatio = maxW / minW

    -- 计算"宽区域占比"：宽度超过最大宽度 40% 的带数 / 总带数
    local wideCount = 0
    local threshold = maxW * 0.4
    for _, w in ipairs(bandWidths) do
        if w >= threshold then
            wideCount = wideCount + 1
        end
    end
    local wideSpan = wideCount / numBands

    return widthRatio, wideSpan
end

--- 根据特征分类武器类型
function ClassifyWeapon(result, strokes)
    local ar = result.aspectRatio
    local sharp = result.pointCount
    local closed = result.closedCount
    local strokeCount = result.shapeCount
    local widthRatio, wideSpan = ComputeWidthProfile(strokes)
    
    result.widthRatio = widthRatio
    result.wideSpan = wideSpan
    
    -- 圆盾：高闭合率 + 接近正方形比例
    if closed >= 1 and ar > 0.7 and ar < 1.4 and strokeCount <= 2 then
        return "SHIELD"
    end
    
    -- 斧：宽度变化大 + 宽区域占较大比例（斧刃覆盖相当高度）
    -- widthRatio > 3: 最宽处比最窄处宽 3 倍以上
    -- wideSpan > 0.3: 超过 30% 的高度是"宽"的（区别于剑的护手只占一小段）
    if widthRatio > 3.0 and wideSpan > 0.3 and ar > 0.8 and ar < 3.5 then
        return "AXE"
    end
    
    -- 矛/枪：极高纵横比 + 很窄（宽度变化小）
    if ar > 4.0 and sharp <= 2 then
        return "SPEAR"
    end
    
    -- 剑：高纵横比 + 尖端
    if ar > 1.8 and sharp >= 1 then
        return "SWORD"
    end
    
    -- 钩：有明显弯曲
    if sharp >= 3 then
        return "HOOK"
    end
    
    -- 默认归为剑（最通用）
    if ar > 1.2 then
        return "SWORD"
    end
    
    return "UNKNOWN"
end

return Analyzer
