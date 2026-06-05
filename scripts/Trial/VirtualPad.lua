-- ============================================================================
-- Trial/VirtualPad.lua - 手机端虚拟操控（左侧轮盘摇杆 + 右侧动作按钮）
-- 职责：触摸输入检测、方向计算、布局、NanoVG 渲染
-- ============================================================================

local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")

local VirtualPad = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local _isMobile = false

---@class JoystickState
local _joystick = {
    cx = 0, cy = 0,
    baseRadius = 0,
    knobRadius = 0,
    active = false,
    touchID = -1,
    knobX = 0, knobY = 0,
    dirX = 0, dirY = 0,
}

local _activeTouches = {}   -- { [touchID] = "jump"|"attack1"|"attack2"|"down" }
local _btnPressed = { jump = false, attack1 = false, attack2 = false, down = false }
local _btnRects = {}        -- { jump={x,y,w,h}, ... }

local _screenW = 0
local _screenH = 0

-- 外部回调（由宿主设置）
local _callbacks = {
    onJump = nil,           -- function()
    onAttack1 = nil,        -- function()
    onAttack2 = nil,        -- function()
    onDown = nil,           -- function()
    onDownRelease = nil,    -- function()
    onDefaultAttack = nil,  -- function()
}

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化（进入状态时调用）
function VirtualPad.Init()
    _isMobile = PlatformUtils.NeedsVirtualJoystick()
    _activeTouches = {}
    for k in pairs(_btnPressed) do _btnPressed[k] = false end
    VirtualPad.ResetJoystick()
end

--- 是否处于手机操控模式
---@return boolean
function VirtualPad.IsActive()
    return _isMobile
end

--- 获取摇杆 X 方向 (-1 ~ 1)
---@return number
function VirtualPad.GetDirX()
    return _joystick.dirX
end

--- 获取摇杆 Y 方向 (-1 ~ 1，向下为正)
---@return number
function VirtualPad.GetDirY()
    return _joystick.dirY
end

--- 某个右侧按钮是否按下
---@param name string
---@return boolean
function VirtualPad.IsPressed(name)
    if _btnPressed[name] then return true end
    return false
end

--- 设置按钮回调
---@param cbs table
function VirtualPad.SetCallbacks(cbs)
    for k, v in pairs(cbs) do
        _callbacks[k] = v
    end
end

--- 重置摇杆状态（释放时、重新进入时）
function VirtualPad.ResetJoystick()
    _joystick.active = false
    _joystick.touchID = -1
    _joystick.knobX = 0
    _joystick.knobY = 0
    _joystick.dirX = 0
    _joystick.dirY = 0
end

-- ============================================================================
-- 布局计算
-- ============================================================================

--- 根据屏幕尺寸重算控件布局（每帧渲染前调用）
---@param sw number 逻辑宽度
---@param sh number 逻辑高度
function VirtualPad.UpdateLayout(sw, sh)
    _screenW = sw
    _screenH = sh

    local btnSize = math.floor(sh * 0.12)
    local pad = math.floor(sh * 0.03)

    -- 左侧摇杆
    local baseR = math.floor(sh * 0.14)
    local knobR = math.floor(baseR * 0.4)
    _joystick.baseRadius = baseR
    _joystick.knobRadius = knobR
    if not _joystick.active then
        _joystick.cx = pad + baseR + pad
        _joystick.cy = sh - pad - baseR - pad
    end

    -- 右侧按钮
    local bottomY = sh - pad - btnSize
    local rPad = pad
    local jumpX = sw - rPad - btnSize * 2 - pad
    local atk1X = sw - rPad - btnSize
    local atk2X = sw - rPad - btnSize * 2 - pad
    local downX = sw - rPad - btnSize
    local jumpY = bottomY - btnSize - pad * 0.5
    local atk1Y = bottomY
    local atk2Y = bottomY - btnSize - pad * 0.5
    local downY = bottomY + btnSize * 0.15 + pad * 0.5

    _btnRects.jump    = { x = jumpX, y = jumpY, w = btnSize, h = btnSize }
    _btnRects.attack1 = { x = atk1X, y = atk1Y, w = btnSize, h = btnSize }
    _btnRects.attack2 = { x = atk2X, y = atk2Y, w = btnSize, h = btnSize }
    _btnRects.down    = { x = downX, y = downY, w = btnSize, h = btnSize * 0.7 }
end

-- ============================================================================
-- 触摸处理
-- ============================================================================

--- 判断点是否在摇杆检测区内
local function HitTestJoystick(tx, ty)
    local dx = tx - _joystick.cx
    local dy = ty - _joystick.cy
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist <= _joystick.baseRadius * 1.5
end

--- 更新摇杆方向
local function UpdateJoystickDir(tx, ty)
    local dx = tx - _joystick.cx
    local dy = ty - _joystick.cy
    local dist = math.sqrt(dx * dx + dy * dy)
    local maxDist = _joystick.baseRadius

    if dist > maxDist then
        dx = dx / dist * maxDist
        dy = dy / dist * maxDist
    end

    _joystick.knobX = dx
    _joystick.knobY = dy
    _joystick.dirX = dx / maxDist
    _joystick.dirY = dy / maxDist
end

--- 判断点落在哪个右侧按钮上
local function HitTestBtn(tx, ty)
    for name, r in pairs(_btnRects) do
        if tx >= r.x and tx <= r.x + r.w and ty >= r.y and ty <= r.y + r.h then
            return name
        end
    end
    return nil
end

--- 同步按钮按下状态
local function SyncBtnInput()
    for k in pairs(_btnPressed) do _btnPressed[k] = false end
    for _, btnName in pairs(_activeTouches) do
        _btnPressed[btnName] = true
    end
end

--- 触发按钮对应的回调
local function FireButtonCallback(btn)
    if btn == "jump" and _callbacks.onJump then
        _callbacks.onJump()
    elseif btn == "attack1" and _callbacks.onAttack1 then
        _callbacks.onAttack1()
    elseif btn == "attack2" and _callbacks.onAttack2 then
        _callbacks.onAttack2()
    elseif btn == "down" and _callbacks.onDown then
        _callbacks.onDown()
    end
end

--- 触摸开始
---@param x number 物理像素 X
---@param y number 物理像素 Y
---@param touchID number
function VirtualPad.OnTouchBegin(x, y, touchID)
    if not _isMobile then return end
    local dpr = graphics:GetDPR()
    local tx, ty = x / dpr, y / dpr

    -- 优先：摇杆区域（左半屏）
    if not _joystick.active and tx < _screenW * 0.5 and HitTestJoystick(tx, ty) then
        _joystick.active = true
        _joystick.touchID = touchID
        UpdateJoystickDir(tx, ty)
        return
    end

    -- 右侧按钮
    local btn = HitTestBtn(tx, ty)
    if btn then
        _activeTouches[touchID] = btn
        FireButtonCallback(btn)
        SyncBtnInput()
        return
    end

    -- 左半屏随意按下：以触摸位置为临时圆心
    if not _joystick.active and tx < _screenW * 0.45 then
        _joystick.active = true
        _joystick.touchID = touchID
        _joystick.cx = tx
        _joystick.cy = ty
        _joystick.knobX = 0
        _joystick.knobY = 0
        _joystick.dirX = 0
        _joystick.dirY = 0
        return
    end

    -- 右半屏未命中按钮：默认攻击
    if tx > _screenW * 0.55 and _callbacks.onDefaultAttack then
        _callbacks.onDefaultAttack()
    end
end

--- 触摸移动
---@param x number
---@param y number
---@param touchID number
function VirtualPad.OnTouchMove(x, y, touchID)
    if not _isMobile then return end
    local dpr = graphics:GetDPR()
    local tx, ty = x / dpr, y / dpr

    if _joystick.active and _joystick.touchID == touchID then
        UpdateJoystickDir(tx, ty)
    end
end

--- 触摸结束
---@param x number
---@param y number
---@param touchID number
function VirtualPad.OnTouchEnd(x, y, touchID)
    if not _isMobile then return end

    -- 摇杆释放
    if _joystick.active and _joystick.touchID == touchID then
        VirtualPad.ResetJoystick()
        return
    end

    -- 按钮释放
    local btn = _activeTouches[touchID]
    _activeTouches[touchID] = nil
    if btn == "down" and _callbacks.onDownRelease then
        _callbacks.onDownRelease()
    end
    SyncBtnInput()
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

--- 渲染摇杆底盘和把手
local function RenderJoystick(vg)
    local jsCx = _joystick.cx
    local jsCy = _joystick.cy
    local baseR = _joystick.baseRadius
    local knobR = _joystick.knobRadius
    local active = _joystick.active

    -- 底盘外圈
    nvgBeginPath(vg)
    nvgCircle(vg, jsCx, jsCy, baseR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, active and 100 or 60))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, active and 180 or 100))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)

    -- 内圈方向指示
    nvgBeginPath(vg)
    nvgCircle(vg, jsCx, jsCy, baseR * 0.45)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 40))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 十字线
    local lineLen = baseR * 0.3
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 50))
    nvgStrokeWidth(vg, 1.5)
    nvgBeginPath(vg)
    nvgMoveTo(vg, jsCx - lineLen, jsCy)
    nvgLineTo(vg, jsCx + lineLen, jsCy)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, jsCx, jsCy - lineLen)
    nvgLineTo(vg, jsCx, jsCy + lineLen)
    nvgStroke(vg)

    -- 把手
    local knobCx = jsCx + _joystick.knobX
    local knobCy = jsCy + _joystick.knobY
    -- 阴影
    nvgBeginPath(vg)
    nvgCircle(vg, knobCx + 2, knobCy + 2, knobR)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgFill(vg)
    -- 本体
    nvgBeginPath(vg)
    nvgCircle(vg, knobCx, knobCy, knobR)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, active and 200 or 160))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, active and 240 or 140))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

--- 渲染右侧动作按钮
local function RenderButtons(vg)
    local alpha = 140
    local pressedAlpha = 220

    for name, r in pairs(_btnRects) do
        local pressed = _btnPressed[name]
        local a = pressed and pressedAlpha or alpha
        local radius = math.min(r.w, r.h) * 0.2

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, r.x, r.y, r.w, r.h, radius)
        if pressed then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
        else
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 80))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, a))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 图标
        local cx = r.x + r.w * 0.5
        local cy = r.y + r.h * 0.5
        local iconSize = math.min(r.w, r.h) * 0.4
        nvgFillColor(vg, nvgRGBA(255, 255, 255, a))

        if name == "jump" then
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx - iconSize * 0.6, cy + iconSize * 0.3)
            nvgLineTo(vg, cx, cy - iconSize * 0.4)
            nvgLineTo(vg, cx + iconSize * 0.6, cy + iconSize * 0.3)
            nvgClosePath(vg)
            nvgFill(vg)
        elseif name == "attack1" then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, iconSize * 1.5)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, cx, cy, "斩")
        elseif name == "attack2" then
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, iconSize * 1.5)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, cx, cy, "劈")
        elseif name == "down" then
            nvgBeginPath(vg)
            nvgMoveTo(vg, cx - iconSize * 0.6, cy - iconSize * 0.3)
            nvgLineTo(vg, cx, cy + iconSize * 0.4)
            nvgLineTo(vg, cx + iconSize * 0.6, cy - iconSize * 0.3)
            nvgClosePath(vg)
            nvgFill(vg)
        end
    end
end

--- 渲染全部虚拟操控（在 nvgBeginFrame/nvgScale 之后调用）
---@param vg userdata NanoVG 上下文
function VirtualPad.Render(vg)
    RenderJoystick(vg)
    RenderButtons(vg)
end

return VirtualPad
