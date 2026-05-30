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

-- 画布位置（居中计算）
local canvasScreenX_ = 0
local canvasScreenY_ = 0

-- 输入追踪
local pointerDown_ = false

--- 进入绘制状态
function DrawState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    gameData_.strokes = {}
    pointerDown_ = false
    
    Canvas.Init(NVG.Get())
    
    -- 计算画布居中位置
    local screenW = graphics:GetWidth() / graphics:GetDPR()
    local screenH = graphics:GetHeight() / graphics:GetDPR()
    canvasScreenX_ = (screenW - Config.Canvas.Width) / 2
    canvasScreenY_ = (screenH - Config.Canvas.Height) / 2 - 20
    Canvas.SetBounds(canvasScreenX_, canvasScreenY_, Config.Canvas.Width, Config.Canvas.Height)
    
    print("[DrawState] Entered. Canvas at: " .. canvasScreenX_ .. ", " .. canvasScreenY_)
end

--- 离开状态时清理
function DrawState.Leave()
    pointerDown_ = false
end

--- 构建绘制阶段的 UI
function DrawState.BuildUI()
    return UI.Panel {
        width = "100%", height = "100%",
        children = {
            -- 顶部工具栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
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
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                pointerEvents = "none",
            },
            
            -- 底部：模板选择 + 完成按钮
            UI.Panel {
                width = "100%",
                padding = 12,
                gap = 10,
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

--- 更新（画布不需要逻辑更新）
function DrawState.Update(dt)
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
    
    Canvas.Render(vg, canvasScreenX_, canvasScreenY_)
    
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

return DrawState
