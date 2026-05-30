-- ============================================================================
-- Drawing/Canvas.lua - 绘制画布核心逻辑
-- 处理触摸/鼠标输入，记录笔画数据
-- ============================================================================

local Config = require("Config")

local Canvas = {}

-- 画布状态
local strokes_ = {}       -- 所有笔画 [{points={{x,y},...}, closed=bool}]
local currentStroke_ = nil -- 当前正在绘制的笔画
local isDrawing_ = false
local canvasX_ = 0        -- 画布在屏幕上的位置（由 UI 布局确定）
local canvasY_ = 0
local canvasW_ = Config.Canvas.Width
local canvasH_ = Config.Canvas.Height

-- NanoVG 上下文（从外部设置）
local nvg_ = nil

-- 前向声明内部函数
local RenderStroke

--- 初始化画布
---@param nvgCtx userdata NanoVG 上下文
function Canvas.Init(nvgCtx)
    nvg_ = nvgCtx
    strokes_ = {}
    currentStroke_ = nil
    isDrawing_ = false
end

--- 设置画布屏幕位置（由布局系统回调）
function Canvas.SetBounds(x, y, w, h)
    canvasX_ = x
    canvasY_ = y
    canvasW_ = w
    canvasH_ = h
end

--- 获取画布边界
function Canvas.GetBounds()
    return canvasX_, canvasY_, canvasW_, canvasH_
end

--- 清空画布
function Canvas.Clear()
    strokes_ = {}
    currentStroke_ = nil
    isDrawing_ = false
end

--- 加载模板笔画（深拷贝，不修改原模板）
function Canvas.LoadTemplate(templateStrokes)
    strokes_ = {}
    for i = 1, #templateStrokes do
        local src = templateStrokes[i]
        local copy = { closed = src.closed, points = {} }
        for j = 1, #src.points do
            copy.points[j] = { x = src.points[j].x, y = src.points[j].y }
        end
        strokes_[i] = copy
    end
    currentStroke_ = nil
    isDrawing_ = false
end

--- 获取所有笔画数据
function Canvas.GetStrokes()
    return strokes_
end

--- 屏幕坐标转画布坐标
local function ScreenToCanvas(sx, sy)
    local cx = sx - canvasX_
    local cy = sy - canvasY_
    return cx, cy
end

--- 判断点是否在画布内
local function IsInCanvas(sx, sy)
    return sx >= canvasX_ and sx <= canvasX_ + canvasW_
       and sy >= canvasY_ and sy <= canvasY_ + canvasH_
end

--- 开始绘制
function Canvas.OnPointerDown(sx, sy)
    if not IsInCanvas(sx, sy) then return false end
    
    local cx, cy = ScreenToCanvas(sx, sy)
    isDrawing_ = true
    currentStroke_ = { points = { { x = cx, y = cy } }, closed = false }
    return true
end

--- 绘制中
function Canvas.OnPointerMove(sx, sy)
    if not isDrawing_ or not currentStroke_ then return end
    if not IsInCanvas(sx, sy) then return end
    
    local cx, cy = ScreenToCanvas(sx, sy)
    local points = currentStroke_.points
    local lastPt = points[#points]
    
    -- 最小距离过滤（避免过多采样点）
    local dx = cx - lastPt.x
    local dy = cy - lastPt.y
    if dx * dx + dy * dy >= Config.Canvas.MinPointDistanceSq then
        if #points < Config.Canvas.MaxPoints then
            points[#points + 1] = { x = cx, y = cy }
        end
    end
end

--- 结束绘制
function Canvas.OnPointerUp(sx, sy)
    if not isDrawing_ then return end
    isDrawing_ = false
    
    if currentStroke_ and #currentStroke_.points >= 3 then
        -- 检测是否闭合（首尾距离在阈值内）
        local pts = currentStroke_.points
        local first = pts[1]
        local last = pts[#pts]
        local dx = last.x - first.x
        local dy = last.y - first.y
        if dx * dx + dy * dy < Config.Canvas.CloseThresholdSq then
            currentStroke_.closed = true
        end
        
        strokes_[#strokes_ + 1] = currentStroke_
    end
    
    currentStroke_ = nil
end

--- 撤销最后一笔
function Canvas.Undo()
    if #strokes_ > 0 then
        strokes_[#strokes_] = nil
    end
end

--- 渲染画布（在 NanoVG 帧内调用）
function Canvas.Render(vg, offsetX, offsetY)
    if not vg then return end
    
    local ox = offsetX or canvasX_
    local oy = offsetY or canvasY_
    
    -- 画布背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, ox, oy, canvasW_, canvasH_, 12)
    nvgFillColor(vg, nvgRGBA(
        Config.Canvas.BackgroundColor[1],
        Config.Canvas.BackgroundColor[2],
        Config.Canvas.BackgroundColor[3],
        Config.Canvas.BackgroundColor[4]
    ))
    nvgFill(vg)
    
    -- 网格线
    nvgBeginPath(vg)
    local gridStep = 40
    for gx = gridStep, canvasW_ - 1, gridStep do
        nvgMoveTo(vg, ox + gx, oy)
        nvgLineTo(vg, ox + gx, oy + canvasH_)
    end
    for gy = gridStep, canvasH_ - 1, gridStep do
        nvgMoveTo(vg, ox, oy + gy)
        nvgLineTo(vg, ox + canvasW_, oy + gy)
    end
    nvgStrokeColor(vg, nvgRGBA(
        Config.Canvas.GridColor[1],
        Config.Canvas.GridColor[2],
        Config.Canvas.GridColor[3],
        Config.Canvas.GridColor[4]
    ))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    
    -- 中心十字
    nvgBeginPath(vg)
    local cx = ox + canvasW_ / 2
    local cy = oy + canvasH_ / 2
    nvgMoveTo(vg, cx - 10, cy)
    nvgLineTo(vg, cx + 10, cy)
    nvgMoveTo(vg, cx, cy - 10)
    nvgLineTo(vg, cx, cy + 10)
    nvgStrokeColor(vg, nvgRGBA(120, 130, 140, 120))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    
    -- 渲染已完成的笔画
    for i = 1, #strokes_ do
        RenderStroke(vg, strokes_[i], ox, oy)
    end
    
    -- 渲染当前正在绘制的笔画
    if currentStroke_ and #currentStroke_.points >= 2 then
        RenderStroke(vg, currentStroke_, ox, oy)
    end
    
    -- 画布边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, ox, oy, canvasW_, canvasH_, 12)
    nvgStrokeColor(vg, nvgRGBA(150, 200, 255, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

--- 渲染单个笔画
RenderStroke = function(vg, stroke, ox, oy)
    local pts = stroke.points
    if #pts < 2 then return end
    
    nvgBeginPath(vg)
    nvgMoveTo(vg, ox + pts[1].x, oy + pts[1].y)
    
    -- 使用贝塞尔曲线平滑
    for i = 2, #pts do
        if i < #pts then
            local mx = (pts[i].x + pts[i + 1].x) * 0.5
            local my = (pts[i].y + pts[i + 1].y) * 0.5
            nvgQuadTo(vg, ox + pts[i].x, oy + pts[i].y, ox + mx, oy + my)
        else
            nvgLineTo(vg, ox + pts[i].x, oy + pts[i].y)
        end
    end
    
    if stroke.closed then
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(50, 50, 55, 40))
        nvgFill(vg)
    end
    
    nvgStrokeColor(vg, nvgRGBA(
        Config.Canvas.StrokeColor[1],
        Config.Canvas.StrokeColor[2],
        Config.Canvas.StrokeColor[3],
        Config.Canvas.StrokeColor[4]
    ))
    nvgStrokeWidth(vg, Config.Canvas.BrushSize)
    nvgLineCap(vg, NVG_ROUND)
    nvgLineJoin(vg, NVG_ROUND)
    nvgStroke(vg)
end

return Canvas
