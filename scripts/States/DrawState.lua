-- ============================================================================
-- States/DrawState.lua - 绘制阶段状态
-- 使用全局共享 NanoVG 上下文，不再自行创建
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local Canvas = require("Drawing.Canvas")
local Templates = require("Drawing.Templates")
local Analyzer = require("Drawing.Analyzer")

local DrawState = {}

local gameData_ = nil
local onComplete_ = nil

-- 画布位置（由 UI 布局动态决定）
local canvasScreenX_ = 0
local canvasScreenY_ = 0
local canvasSize_ = 200

-- 中间占位面板引用（用于获取实际布局）
local canvasAreaPanel_ = nil
local canvasBoundsReady_ = false

-- 输入追踪
local pointerDown_ = false

--- 进入绘制状态
function DrawState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    gameData_.strokes = {}
    pointerDown_ = false
    
    Canvas.Init(NVG.Get())
    canvasBoundsReady_ = false
    
    print("[DrawState] Entered. Waiting for UI layout to determine canvas bounds.")
end

--- 离开状态时清理
function DrawState.Leave()
    pointerDown_ = false
end

--- 构建绘制阶段的 UI
function DrawState.BuildUI()
    canvasAreaPanel_ = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        pointerEvents = "none",
    }
    return UI.Panel {
        width = "100%", height = "100%",
        children = {
            -- 顶部工具栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexShrink = 0,
                justifyContent = "space-between",
                alignItems = "center",
                padding = 12,
                backgroundColor = Config.Colors.BgDark,
                children = {
                    UI.Label {
                        text = "✏️ 绘制你的武器",
                        fontSize = 16,
                        fontColor = Config.Colors.TextLight,
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 8,
                        children = {
                            UI.Button {
                                text = "撤销",
                                variant = "outline",
                                size = "small",
                                onClick = function()
                                    Canvas.Undo()
                                end,
                            },
                            UI.Button {
                                text = "清空",
                                variant = "outline",
                                size = "small",
                                onClick = function()
                                    Canvas.Clear()
                                end,
                            },
                        },
                    },
                },
            },
            
            -- 画布区域（由 NanoVG 直接渲染，UI 只占位，必须透明）
            canvasAreaPanel_,
            
            -- 底部：模板选择 + 完成按钮
            UI.Panel {
                width = "100%",
                padding = 12,
                gap = 10,
                flexShrink = 0,
                alignItems = "center",
                backgroundColor = Config.Colors.BgDark,
                children = {
                    -- 模板按钮行
                    UI.Panel {
                        flexDirection = "row", gap = 8,
                        children = {
                            UI.Label {
                                text = "模板:",
                                fontSize = 12,
                                fontColor = { 160, 160, 180, 255 },
                            },
                            UI.Button {
                                text = "⚔️ 剑",
                                size = "small",
                                variant = "outline",
                                onClick = function()
                                    local t = Templates.Get("sword")
                                    if t then Canvas.LoadTemplate(t.strokes) end
                                end,
                            },
                            UI.Button {
                                text = "🪓 斧",
                                size = "small",
                                variant = "outline",
                                onClick = function()
                                    local t = Templates.Get("axe")
                                    if t then Canvas.LoadTemplate(t.strokes) end
                                end,
                            },
                            UI.Button {
                                text = "🛡️ 盾",
                                size = "small",
                                variant = "outline",
                                onClick = function()
                                    local t = Templates.Get("shield")
                                    if t then Canvas.LoadTemplate(t.strokes) end
                                end,
                            },
                        },
                    },
                    -- 完成按钮
                    UI.Button {
                        text = "完成绘制 →",
                        variant = "primary",
                        width = 200,
                        onClick = function()
                            DrawState.FinishDrawing()
                        end,
                    },
                    UI.Label {
                        text = "💡 画出多个相连形状可能触发隐藏效果",
                        fontSize = 11,
                        fontColor = { 120, 120, 140, 160 },
                    },
                },
            },
        },
    }
end

--- 完成绘制，分析形状
function DrawState.FinishDrawing()
    local strokes = Canvas.GetStrokes()
    if #strokes == 0 then
        print("[DrawState] No strokes, cannot proceed")
        return
    end
    
    -- 保存笔画数据
    gameData_.strokes = strokes
    
    -- 分析形状
    local analysis = Analyzer.Analyze(strokes)
    gameData_.weaponType = analysis.type
    gameData_.isComposite = analysis.isComposite
    gameData_.analysis = analysis
    
    print("[DrawState] Done. Type: " .. analysis.type .. " Composite: " .. tostring(analysis.isComposite))
    
    if onComplete_ then onComplete_() end
end

--- 根据屏幕尺寸直接计算画布位置（不依赖 UI 布局）
local function CalcCanvasBounds()
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr
    local logH = graphics:GetHeight() / dpr
    
    -- 预估工具栏和底栏高度
    local topBarH = 50
    local bottomBarH = 110
    
    -- 可用绘制区域
    local areaX = 0
    local areaY = topBarH
    local areaW = logW
    local areaH = logH - topBarH - bottomBarH
    
    -- 正方形画布，取可用宽高较小值的 88%
    local size = math.min(areaW * 0.88, areaH * 0.88)
    size = math.max(size, 150)
    
    -- 居中放置
    local cx = areaX + (areaW - size) / 2
    local cy = areaY + (areaH - size) / 2
    
    return cx, cy, size
end

--- 更新：每帧计算画布位置
function DrawState.Update(dt)
    -- 优先使用 UI 布局面板的准确坐标
    local areaX, areaY, areaW, areaH
    local layoutOK = false
    
    if canvasAreaPanel_ then
        local layout = canvasAreaPanel_:GetAbsoluteLayout()
        if layout and layout.w > 0 and layout.h > 0 then
            areaX = layout.x
            areaY = layout.y
            areaW = layout.w
            areaH = layout.h
            layoutOK = true
        end
    end
    
    local newX, newY, size
    if layoutOK then
        size = math.min(areaW * 0.92, areaH * 0.92)
        size = math.max(size, 150)
        newX = areaX + (areaW - size) / 2
        newY = areaY + (areaH - size) / 2
    else
        -- Fallback: 直接根据屏幕尺寸计算
        newX, newY, size = CalcCanvasBounds()
    end
    
    -- 更新画布位置
    if math.abs(canvasSize_ - size) > 0.5 or math.abs(canvasScreenX_ - newX) > 0.5 or math.abs(canvasScreenY_ - newY) > 0.5 or not canvasBoundsReady_ then
        canvasSize_ = size
        canvasScreenX_ = newX
        canvasScreenY_ = newY
        Canvas.SetBounds(canvasScreenX_, canvasScreenY_, size, size)
        if not canvasBoundsReady_ then
            print(string.format("[DrawState] Canvas init: x=%.0f y=%.0f size=%.0f layout=%s",
                newX, newY, size, tostring(layoutOK)))
        end
        canvasBoundsReady_ = true
    end
end

--- 按键处理
function DrawState.OnKeyDown(key)
    if key == KEY_Z then
        Canvas.Undo()
    elseif key == KEY_X then
        Canvas.Clear()
    end
end

-- ============================================================================
-- 输入处理（由 main.lua 分发调用）
-- ============================================================================

function DrawState.OnMouseDown(button)
    if button ~= MOUSEB_LEFT then return end
    
    local dpr = graphics:GetDPR()
    local mx = input:GetMousePosition().x / dpr
    local my = input:GetMousePosition().y / dpr
    
    if Canvas.OnPointerDown(mx, my) then
        pointerDown_ = true
    end
end

function DrawState.OnMouseUp(button)
    if not pointerDown_ then return end
    pointerDown_ = false
    
    local dpr = graphics:GetDPR()
    local mx = input:GetMousePosition().x / dpr
    local my = input:GetMousePosition().y / dpr
    Canvas.OnPointerUp(mx, my)
end

function DrawState.OnMouseMove()
    if not pointerDown_ then return end
    
    local dpr = graphics:GetDPR()
    local mx = input:GetMousePosition().x / dpr
    local my = input:GetMousePosition().y / dpr
    Canvas.OnPointerMove(mx, my)
end

function DrawState.OnTouchBegin(x, y)
    local dpr = graphics:GetDPR()
    local tx = x / dpr
    local ty = y / dpr
    
    if Canvas.OnPointerDown(tx, ty) then
        pointerDown_ = true
    end
end

function DrawState.OnTouchMove(x, y)
    if not pointerDown_ then return end
    local dpr = graphics:GetDPR()
    Canvas.OnPointerMove(x / dpr, y / dpr)
end

function DrawState.OnTouchEnd(x, y)
    if not pointerDown_ then return end
    pointerDown_ = false
    local dpr = graphics:GetDPR()
    Canvas.OnPointerUp(x / dpr, y / dpr)
end

-- ============================================================================
-- NanoVG 渲染（由 main.lua 的 HandleNanoVGRender 调用）
-- ============================================================================

function DrawState.Render(vg)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    
    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)
    
    -- 绘制画布区域的深色背景（仅画布周围，避免覆盖 UI 工具栏）
    local logW = w / dpr
    local logH = h / dpr
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logW, logH)
    nvgFillColor(vg, nvgRGBA(
        Config.Colors.BgDark[1],
        Config.Colors.BgDark[2],
        Config.Colors.BgDark[3],
        Config.Colors.BgDark[4]
    ))
    nvgFill(vg)
    
    -- 仅在布局就绪后渲染画布
    if canvasBoundsReady_ then
        Canvas.Render(vg, canvasScreenX_, canvasScreenY_)
    end
    
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

return DrawState
