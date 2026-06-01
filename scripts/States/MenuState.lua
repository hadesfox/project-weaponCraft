-- ============================================================================
-- States/MenuState.lua - 主菜单（NanoVG 背景 + 交互按钮特效）
-- 背景图上三个按钮区域：开始游戏、查看角色、离开
-- 设置面板和排行榜面板已抽取至 Menu/Panels.lua
-- 悬停放大发光，点击反馈
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local KeyBindings = require("KeyBindings")
local GameSettings = require("GameSettings")
local Panels = require("Menu.Panels")

local MenuState = {}

-- 前置声明（内部子函数）
local HitTestButtons
local HitTestSecret
local ToggleBackground
local RenderBackground
local RenderButtons
local RenderCharacterPanel
local SplitLines

-- 回调
local onStartGame_ = nil
local uiRoot_ = nil

-- 屏幕尺寸
local screenW_ = 0
local screenH_ = 0

-- 背景图（双背景切换）
local bgImage_ = nil
local bgImageAlt_ = nil        -- 备选背景（原版）
local BG_PATH_NEW = "image/menu_bg_forge.png"   -- 新版铁匠铺背景（默认）
local BG_PATH_OLD = "image/menu_bg.png"         -- 原版背景
local useNewBg_ = true          -- 当前是否使用新背景

-- 按钮定义（左上角比例坐标 + 宽高比例，基于图片实际布局）
-- "开始游戏": 左下木桩铭牌 | "查看角色": 盾牌下方铭牌 | "离开": 右下桌前木牌
local buttons_ = {
    { id = "start",     label = "开始游戏", rx = 0.22, ry = 0.77, rw = 0.115, rh = 0.05 },
    { id = "character", label = "查看角色", rx = 0.46, ry = 0.60, rw = 0.11,  rh = 0.045 },
    { id = "quit",      label = "离开",     rx = 0.72, ry = 0.765, rw = 0.105, rh = 0.05 },
}

-- 按钮交互状态
local hoverIndex_ = 0       -- 当前悬停按钮 (0=无)
local pressIndex_ = 0       -- 当前按下按钮
local glowAlpha_ = {}       -- 每个按钮的发光强度 (0~255)
local pressAnim_ = {}       -- 点击闪光动画 (0~1)

-- 隐藏触发点（左侧壁炉区域切换背景）
local SECRET_ZONE = { rx = 0.0, ry = 0.35, rw = 0.12, rh = 0.45 }

-- 角色面板状态
local showCharPanel_ = false
local charPanelAnim_ = 0    -- 面板展开动画 (0→1)

-- 已点击开始游戏（隐藏所有菜单内容，只渲染纯黑）
local gameStarted_ = false

-- 角色数据
local characters_ = {
    {
        name = "铁匠",
        image = "image/主角_锻造师_20260530003547.png",
        desc = "沉默寡言的武器大师，能将任何涂鸦锻造成神兵利器。\n据说曾为远古英雄打造过传说级武器。",
        color = { 255, 180, 80 },
    },
    {
        name = "史莱姆",
        image = "image/史莱姆_20260530090540.png",
        desc = "试炼场中的训练伙伴，身体柔软但意外顽强。\n不同颜色代表不同属性，击败它们能获得锻造灵感。",
        color = { 100, 220, 140 },
    },
}
-- 角色图片 NanoVG handle（延迟加载）
local charImages_ = {}

--- 进入菜单状态
function MenuState.Enter(onStart)
    onStartGame_ = onStart
    screenW_ = graphics:GetWidth() / graphics:GetDPR()
    screenH_ = graphics:GetHeight() / graphics:GetDPR()

    -- 加载背景（两套）
    local vg = NVG.Get()
    if vg then
        if not bgImage_ then
            bgImage_ = nvgCreateImage(vg, BG_PATH_NEW, 0)
        end
        if not bgImageAlt_ then
            bgImageAlt_ = nvgCreateImage(vg, BG_PATH_OLD, 0)
        end
    end
    useNewBg_ = true  -- 默认使用新背景

    -- 初始化按钮状态
    for i = 1, #buttons_ do
        glowAlpha_[i] = 0
        pressAnim_[i] = 0
    end

    hoverIndex_ = 0
    pressIndex_ = 0
    showCharPanel_ = false
    charPanelAnim_ = 0
    gameStarted_ = false
    Panels.Reset()
end

--- 离开菜单状态
function MenuState.Leave()
    -- 释放 GPU 纹理
    local vg = NVG.Get()
    if vg then
        if bgImage_ and bgImage_ ~= 0 then
            nvgDeleteImage(vg, bgImage_)
            bgImage_ = nil
        end
        if bgImageAlt_ and bgImageAlt_ ~= 0 then
            nvgDeleteImage(vg, bgImageAlt_)
            bgImageAlt_ = nil
        end
        for i = 1, #charImages_ do
            if charImages_[i] and charImages_[i] ~= 0 then
                nvgDeleteImage(vg, charImages_[i])
            end
        end
        charImages_ = {}
    end

    -- 重置 UI/面板状态
    showCharPanel_ = false
    charPanelAnim_ = 0
    Panels.Reset()
    gameStarted_ = false
    uiRoot_ = nil
    onStartGame_ = nil
end

--- 构建 UI（仅角色面板悬浮层用 UI 组件）
function MenuState.BuildUI()
    -- 菜单主体通过 NanoVG 渲染，UI 层为空壳（穿透点击）
    uiRoot_ = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "none",
    }
    return uiRoot_
end

-- ============================================================================
-- 更新
-- ============================================================================

function MenuState.Update(dt)
    -- 按钮悬停动画插值
    for i = 1, #buttons_ do
        if i == hoverIndex_ then
            glowAlpha_[i] = glowAlpha_[i] + (220 - glowAlpha_[i]) * dt * 8
        else
            glowAlpha_[i] = 0
        end

        -- 点击闪光衰减
        if pressAnim_[i] > 0 then
            pressAnim_[i] = math.max(0, pressAnim_[i] - dt * 4)
        end
    end

    -- 角色面板动画
    local targetPanel = showCharPanel_ and 1.0 or 0.0
    charPanelAnim_ = charPanelAnim_ + (targetPanel - charPanelAnim_) * dt * 8

    -- 设置/排行榜面板动画
    Panels.Update(dt)
end

-- ============================================================================
-- 输入处理
-- ============================================================================

function MenuState.OnKeyDown(key)
    -- 设置/排行榜面板优先处理
    if Panels.HandleKeyDown(key) then return end

    if key == KEY_ESCAPE then
        if showCharPanel_ then
            showCharPanel_ = false
        end
    elseif key == KEY_RETURN or key == KEY_SPACE then
        if not showCharPanel_ then
            if onStartGame_ then gameStarted_ = true; onStartGame_() end
        end
    end
end

function MenuState.OnKeyUp(key) end

function MenuState.OnMouseDown(button)
    if button ~= MOUSEB_LEFT then return end

    local mx = input.mousePosition.x / graphics:GetDPR()
    local my = input.mousePosition.y / graphics:GetDPR()

    -- 设置面板打开时
    if Panels.IsSettingsOpen() then
        Panels.HandleSettingsClick(mx, my, screenW_, screenH_)
        return
    end

    -- 排行榜面板打开时，点击关闭
    if Panels.IsLeaderboardOpen() then
        Panels.CloseLeaderboard()
        return
    end

    if showCharPanel_ then
        -- 点击关闭面板
        showCharPanel_ = false
        return
    end

    -- 隐藏触发点检测（优先于按钮）
    if HitTestSecret(mx, my) then
        ToggleBackground()
        return
    end

    -- 排行榜触发点
    if Panels.HitTestLeaderboard(mx, my, screenW_, screenH_) then
        Panels.OpenLeaderboard()
        return
    end

    -- 设置触发点
    if Panels.HitTestSettings(mx, my, screenW_, screenH_) then
        Panels.OpenSettings()
        return
    end

    local idx = HitTestButtons(mx, my)

    if idx > 0 then
        pressIndex_ = idx
        pressAnim_[idx] = 1.0
    end
end

function MenuState.OnMouseUp(button)
    if button ~= MOUSEB_LEFT then return end
    if Panels.IsSettingsOpen() then return end
    if pressIndex_ > 0 then
        local mx = input.mousePosition.x / graphics:GetDPR()
        local my = input.mousePosition.y / graphics:GetDPR()
        local idx = HitTestButtons(mx, my)

        if idx == pressIndex_ then
            -- 执行按钮动作
            local btnId = buttons_[idx].id
            if btnId == "start" then
                if onStartGame_ then gameStarted_ = true; onStartGame_() end
            elseif btnId == "character" then
                showCharPanel_ = true
            elseif btnId == "quit" then
                -- 无实际退出功能，闪光即可
            end
        end
        pressIndex_ = 0
    end
end

function MenuState.OnMouseMove()
    if showCharPanel_ or Panels.IsSettingsOpen() or Panels.IsLeaderboardOpen() then
        hoverIndex_ = 0
        return
    end
    local mx = input.mousePosition.x / graphics:GetDPR()
    local my = input.mousePosition.y / graphics:GetDPR()
    hoverIndex_ = HitTestButtons(mx, my)
end

function MenuState.OnTouchBegin(x, y)
    local dpr = graphics:GetDPR()
    local tx, ty = x / dpr, y / dpr

    if Panels.IsSettingsOpen() then
        Panels.HandleSettingsClick(tx, ty, screenW_, screenH_)
        return
    end

    -- 排行榜面板打开时，点击关闭
    if Panels.IsLeaderboardOpen() then
        Panels.CloseLeaderboard()
        return
    end

    if showCharPanel_ then
        showCharPanel_ = false
        return
    end

    -- 隐藏触发点检测（优先于按钮）
    if HitTestSecret(tx, ty) then
        ToggleBackground()
        return
    end

    -- 排行榜触发点
    if Panels.HitTestLeaderboard(tx, ty, screenW_, screenH_) then
        Panels.OpenLeaderboard()
        return
    end

    -- 设置触发点
    if Panels.HitTestSettings(tx, ty, screenW_, screenH_) then
        Panels.OpenSettings()
        return
    end

    local idx = HitTestButtons(tx, ty)
    if idx > 0 then
        pressAnim_[idx] = 1.0
        local btnId = buttons_[idx].id
        if btnId == "start" then
            if onStartGame_ then gameStarted_ = true; onStartGame_() end
        elseif btnId == "character" then
            showCharPanel_ = true
        end
    end
end

function MenuState.OnTouchMove(x, y) end
function MenuState.OnTouchEnd(x, y) end

--- 命中测试：隐藏触发区域（左侧壁炉）
HitTestSecret = function(mx, my)
    local sx = screenW_ * SECRET_ZONE.rx
    local sy = screenH_ * SECRET_ZONE.ry
    local sw = screenW_ * SECRET_ZONE.rw
    local sh = screenH_ * SECRET_ZONE.rh
    return mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh
end

--- 切换背景
ToggleBackground = function()
    useNewBg_ = not useNewBg_
end

--- 命中测试：返回鼠标下的按钮索引，0=无
--- 按钮坐标为左上角 (rx,ry) + 宽高 (rw,rh)
function HitTestButtons(mx, my)
    for i = 1, #buttons_ do
        local b = buttons_[i]
        local bx = screenW_ * b.rx
        local by = screenH_ * b.ry
        local bw = screenW_ * b.rw
        local bh = screenH_ * b.rh
        if mx >= bx and mx <= bx + bw and
           my >= by and my <= by + bh then
            return i
        end
    end
    return 0
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

function MenuState.Render(vg)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    screenW_ = w / dpr
    screenH_ = h / dpr

    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)

    -- 点击开始后立即切为纯黑，避免过渡期间闪现菜单背景
    if gameStarted_ then
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenW_, screenH_)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        nvgFill(vg)
        nvgResetTransform(vg)
        nvgEndFrame(vg)
        return
    end

    -- 背景图
    RenderBackground(vg)

    -- 按钮特效
    RenderButtons(vg)

    -- 角色面板
    if charPanelAnim_ > 0.01 then
        RenderCharacterPanel(vg)
    end

    -- 设置面板
    if Panels.GetSettingsAnim() > 0.01 then
        Panels.RenderSettings(vg, screenW_, screenH_)
    end

    -- 排行榜面板
    if Panels.GetLeaderboardAnim() > 0.01 then
        Panels.RenderLeaderboard(vg, screenW_, screenH_)
    end

    -- 右下角版本号
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(80, 80, 80, 200))
    nvgText(vg, screenW_ - 12, screenH_ - 10, Config.Version)

    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

--- 渲染背景图（铺满屏幕）
function RenderBackground(vg)
    local currentBg = useNewBg_ and bgImage_ or bgImageAlt_
    if not currentBg or currentBg == 0 then
        -- 无图片时纯色备用 - 深蓝灰
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenW_, screenH_)
        nvgFillColor(vg, nvgRGBA(20, 22, 28, 255))
        nvgFill(vg)
        return
    end

    local imgPaint = nvgImagePattern(vg, 0, 0, screenW_, screenH_, 0, currentBg, 1.0)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW_, screenH_)
    nvgFillPaint(vg, imgPaint)
    nvgFill(vg)
end

--- 渲染按钮特效（透明触发框 + 高亮边框 + 放大镜效果）
function RenderButtons(vg)
    local ZOOM = 1.3  -- 放大镜倍率

    for i = 1, #buttons_ do
        local b = buttons_[i]
        local bx = screenW_ * b.rx
        local by = screenH_ * b.ry
        local bw = screenW_ * b.rw
        local bh = screenH_ * b.rh
        local glow = glowAlpha_[i] or 0
        local press = pressAnim_[i] or 0

        -- 按钮中心
        local cx = bx + bw / 2
        local cy = by + bh / 2

        -- 放大镜效果：悬停时裁剪该区域并放大显示背景图
        local currentBg = useNewBg_ and bgImage_ or bgImageAlt_
        if glow > 5 and currentBg and currentBg ~= 0 then
            nvgSave(vg)

            -- 用 nvgScissor 裁剪到按钮区域（带少量外扩）
            local expand = 3
            nvgScissor(vg, bx - expand, by - expand, bw + expand * 2, bh + expand * 2)

            -- 在裁剪区域内绘制放大后的背景
            -- 计算放大后的图片偏移，使按钮中心位置对齐
            local imgW = screenW_ * ZOOM
            local imgH = screenH_ * ZOOM
            local imgX = cx - (cx / screenW_) * imgW
            local imgY = cy - (cy / screenH_) * imgH

            local zoomPaint = nvgImagePattern(vg, imgX, imgY, imgW, imgH, 0, currentBg, 1.0)
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx - expand, by - expand, bw + expand * 2, bh + expand * 2, 5)
            nvgFillPaint(vg, zoomPaint)
            nvgFill(vg)

            nvgRestore(vg)
        end


    end
end

--- 渲染角色信息面板
function RenderCharacterPanel(vg)
    local alpha = math.floor(charPanelAnim_ * 255)
    local panelScale = 0.85 + charPanelAnim_ * 0.15

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW_, screenH_)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(charPanelAnim_ * 180)))
    nvgFill(vg)

    -- 面板
    local panelW = math.min(screenW_ * 0.85, 520)
    local panelH = math.min(screenH_ * 0.7, 360)
    local px = (screenW_ - panelW) / 2
    local py = (screenH_ - panelH) / 2

    nvgSave(vg)
    nvgTranslate(vg, screenW_ / 2, screenH_ / 2)
    nvgScale(vg, panelScale, panelScale)
    nvgTranslate(vg, -screenW_ / 2, -screenH_ / 2)

    -- 面板背景 - 深蓝灰底色 + 宝蓝边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 16)
    nvgFillColor(vg, nvgRGBA(20, 22, 28, alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(150, 200, 255, math.floor(alpha * 0.6)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 标题
    local fontId = NVG.GetFont()
    if fontId ~= -1 then
        nvgFontFaceId(vg, fontId)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(160, 140, 90, alpha))
        nvgText(vg, screenW_ / 2, py + 18, "角色图鉴", nil)

        -- 角色卡片
        local cardW = (panelW - 60) / 2
        local cardH = panelH - 80
        local cardY = py + 55

        for i = 1, #characters_ do
            local ch = characters_[i]
            local cardX = px + 20 + (i - 1) * (cardW + 20)

            -- 卡片背景 - 灰蓝中底色
            nvgBeginPath(vg)
            nvgRoundedRect(vg, cardX, cardY, cardW, cardH, 10)
            nvgFillColor(vg, nvgRGBA(50, 50, 55, alpha))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(ch.color[1], ch.color[2], ch.color[3], math.floor(alpha * 0.5)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 角色图片
            if ch.image then
                if not charImages_[i] then
                    charImages_[i] = nvgCreateImage(vg, ch.image, 0)
                end
                local imgHandle = charImages_[i]
                if imgHandle > 0 then
                    local imgSize = math.min(cardW - 20, 80)
                    local imgX = cardX + (cardW - imgSize) / 2
                    local imgY = cardY + 8
                    local imgPat = nvgImagePattern(vg, imgX, imgY, imgSize, imgSize, 0, imgHandle, alpha / 255.0)
                    nvgBeginPath(vg)
                    nvgRoundedRect(vg, imgX, imgY, imgSize, imgSize, 6)
                    nvgFillPaint(vg, imgPat)
                    nvgFill(vg)
                end
            end

            -- 名称
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(ch.color[1], ch.color[2], ch.color[3], alpha))
            nvgText(vg, cardX + cardW / 2, cardY + 95, ch.name, nil)

            -- 描述（多行文本）- 银灰色
            nvgFontSize(vg, 11)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(120, 130, 140, alpha))
            local descLines = SplitLines(ch.desc)
            local lineY = cardY + 118
            for j = 1, #descLines do
                nvgText(vg, cardX + 12, lineY, descLines[j], nil)
                lineY = lineY + 15
            end
        end

        -- 底部提示 - 银灰色
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, math.floor(alpha * 0.7)))
        nvgText(vg, screenW_ / 2, py + panelH - 10, "点击任意位置关闭", nil)
    end

    nvgRestore(vg)
end
--- 工具：按换行符拆分字符串
function SplitLines(str)
    local lines = {}
    for line in str:gmatch("([^\n]+)") do
        lines[#lines + 1] = line
    end
    return lines
end

return MenuState
