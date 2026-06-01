-- ============================================================================
-- Menu/Panels.lua - 设置面板 + 排行榜面板（从 MenuState.lua 抽取）
-- ============================================================================

local NVG = require("NVG")
local Config = require("Config")
local KeyBindings = require("KeyBindings")
local GameSettings = require("GameSettings")

local Panels = {}

-- ============================================================================
-- 面板状态
-- ============================================================================

local showSettings_ = false
local settingsAnim_ = 0
local settingsScroll_ = 0
local rebindingAction_ = nil
local rebindFlash_ = 0

local showLeaderboard_ = false
local leaderboardAnim_ = 0
local menuLeaderboardData_ = {}
local menuLeaderboardLoading_ = false

-- 触发区域（比例坐标）
local SETTINGS_ZONE = { rx = 0.545, ry = 0.67, rw = 0.05, rh = 0.08 }
local LEADERBOARD_ZONE = { rx = 0.05, ry = 0.02, rw = 0.14, rh = 0.35 }

-- ============================================================================
-- 查询 API
-- ============================================================================

function Panels.IsSettingsOpen()
    return showSettings_
end

function Panels.IsLeaderboardOpen()
    return showLeaderboard_
end

function Panels.GetSettingsAnim()
    return settingsAnim_
end

function Panels.GetLeaderboardAnim()
    return leaderboardAnim_
end

-- ============================================================================
-- 状态控制
-- ============================================================================

function Panels.Reset()
    showSettings_ = false
    settingsAnim_ = 0
    settingsScroll_ = 0
    rebindingAction_ = nil
    rebindFlash_ = 0
    showLeaderboard_ = false
    leaderboardAnim_ = 0
    menuLeaderboardData_ = {}
    menuLeaderboardLoading_ = false
end

function Panels.OpenSettings()
    showSettings_ = true
    settingsScroll_ = 0
    rebindingAction_ = nil
end

function Panels.CloseSettings()
    showSettings_ = false
end

function Panels.OpenLeaderboard()
    showLeaderboard_ = true
    Panels.FetchLeaderboard()
end

function Panels.CloseLeaderboard()
    showLeaderboard_ = false
end

-- ============================================================================
-- 命中测试
-- ============================================================================

function Panels.HitTestSettings(mx, my, screenW, screenH)
    local sx = screenW * SETTINGS_ZONE.rx
    local sy = screenH * SETTINGS_ZONE.ry
    local sw = screenW * SETTINGS_ZONE.rw
    local sh = screenH * SETTINGS_ZONE.rh
    return mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh
end

function Panels.HitTestLeaderboard(mx, my, screenW, screenH)
    local sx = screenW * LEADERBOARD_ZONE.rx
    local sy = screenH * LEADERBOARD_ZONE.ry
    local sw = screenW * LEADERBOARD_ZONE.rw
    local sh = screenH * LEADERBOARD_ZONE.rh
    return mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh
end

-- ============================================================================
-- 输入处理
-- ============================================================================

--- 键盘事件（重绑定模式）。返回 true 表示已消费
function Panels.HandleKeyDown(key)
    if showSettings_ then
        if rebindingAction_ then
            if key == KEY_ESCAPE then
                rebindingAction_ = nil
            else
                KeyBindings.SetKeys(rebindingAction_, { key })
                KeyBindings.Save()
                rebindingAction_ = nil
            end
            return true
        end
        if key == KEY_ESCAPE then
            showSettings_ = false
        end
        return true
    end

    if showLeaderboard_ then
        if key == KEY_ESCAPE then
            showLeaderboard_ = false
        end
        return true
    end

    return false
end

--- 设置面板内的点击处理
function Panels.HandleSettingsClick(mx, my, screenW, screenH)
    if rebindingAction_ then
        rebindingAction_ = nil
    end

    local margin = 12
    local panelW = screenW - margin * 2
    local panelH = screenH - margin * 2
    local px = margin
    local py = margin

    -- "恢复默认"按钮区域（面板底部）
    local resetBtnW = 120
    local resetBtnH = 32
    local resetBtnX = px + panelW / 2 - resetBtnW / 2
    local resetBtnY = py + panelH - 50
    if mx >= resetBtnX and mx <= resetBtnX + resetBtnW and
       my >= resetBtnY and my <= resetBtnY + resetBtnH then
        KeyBindings.ResetToDefault()
        GameSettings.ResetDurations()
        return
    end

    -- ====== 环节时长按钮点击检测 ======
    local contentTop = py + 52
    local curY = contentTop + 6 - settingsScroll_
    curY = curY + 26  -- 跳过【环节时长】标题

    local btnW = 46
    local btnH = 28
    local btnGap = 8

    local durationClickRows = {
        { options = Config.MaterialTimeOptions, setter = GameSettings.SetMaterialTime },
        { options = Config.HammerTimeOptions, setter = GameSettings.SetHammerTime },
        { options = Config.QuenchTimeOptions, setter = GameSettings.SetQuenchTime },
        { options = Config.GrindTimeOptions, setter = GameSettings.SetGrindTime },
        { options = Config.TrialTimeOptions, setter = GameSettings.SetTrialTime },
    }

    for _, row in ipairs(durationClickRows) do
        local opts = row.options
        local totalW = #opts * btnW + (#opts - 1) * btnGap
        local startX = px + panelW - 24 - totalW
        local btnRowY = curY + 4

        for oi = 1, #opts do
            local bx = startX + (oi - 1) * (btnW + btnGap)
            if mx >= bx and mx <= bx + btnW and
               my >= btnRowY and my <= btnRowY + btnH then
                row.setter(opts[oi])
                return
            end
        end

        curY = curY + 42
    end

    curY = curY + 12  -- 分隔线间距

    -- ====== 按键绑定行点击 → 进入重绑定 ======
    local actions = KeyBindings.Actions
    local rowH = 36
    local lastCategory = ""

    for i = 1, #actions do
        local action = actions[i]

        if action.category ~= lastCategory then
            lastCategory = action.category
            if i > 1 then curY = curY + 12 end
            curY = curY + 26
        end

        local rowY = curY

        local keyBoxX = px + panelW * 0.50
        local keyBoxW = panelW * 0.42
        if mx >= keyBoxX and mx <= keyBoxX + keyBoxW and
           my >= rowY and my <= rowY + rowH then
            rebindingAction_ = action.id
            rebindFlash_ = 0
            return
        end

        curY = curY + rowH
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

function Panels.Update(dt)
    local targetSettings = showSettings_ and 1.0 or 0.0
    settingsAnim_ = settingsAnim_ + (targetSettings - settingsAnim_) * dt * 8

    local targetLb = showLeaderboard_ and 1.0 or 0.0
    leaderboardAnim_ = leaderboardAnim_ + (targetLb - leaderboardAnim_) * dt * 8

    if rebindingAction_ then
        rebindFlash_ = rebindFlash_ + dt * 6
    end
end

-- ============================================================================
-- 数据获取
-- ============================================================================

function Panels.FetchLeaderboard()
    if menuLeaderboardLoading_ then return end
    menuLeaderboardLoading_ = true
    menuLeaderboardData_ = {}
    local cjson = require("cjson")

    clientCloud:Get("leaderboard_history", {
        ok = function(values)
            local history = {}
            if values and values.leaderboard_history then
                local ok2, decoded = pcall(cjson.decode, values.leaderboard_history)
                if ok2 and type(decoded) == "table" then
                    history = decoded
                end
            end
            table.sort(history, function(a, b)
                if a.time ~= b.time then return a.time < b.time end
                return a.damage < b.damage
            end)
            print("[MenuState] Leaderboard fetched from history, count=" .. #history)
            menuLeaderboardData_ = history
            menuLeaderboardLoading_ = false
        end,
        error = function(code, reason)
            print("[MenuState] Leaderboard error: " .. tostring(reason))
            menuLeaderboardData_ = {}
            menuLeaderboardLoading_ = false
        end,
    })
end

-- ============================================================================
-- 渲染
-- ============================================================================

function Panels.RenderSettings(vg, screenW, screenH)
    local alpha = math.floor(settingsAnim_ * 255)
    local panelScale = 0.9 + settingsAnim_ * 0.1

    -- 全屏遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(settingsAnim_ * 220)))
    nvgFill(vg)

    -- 全屏面板尺寸
    local margin = 12
    local panelW = screenW - margin * 2
    local panelH = screenH - margin * 2
    local px = margin
    local py = margin

    nvgSave(vg)
    nvgTranslate(vg, screenW / 2, screenH / 2)
    nvgScale(vg, panelScale, panelScale)
    nvgTranslate(vg, -screenW / 2, -screenH / 2)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 10)
    nvgFillColor(vg, nvgRGBA(20, 22, 30, alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 90, math.floor(alpha * 0.6)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local fontId = NVG.GetFont()
    if fontId == -1 then
        nvgRestore(vg)
        return
    end
    nvgFontFaceId(vg, fontId)

    -- 标题
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg, 22)
    nvgFillColor(vg, nvgRGBA(160, 140, 90, alpha))
    nvgText(vg, screenW / 2, py + 16, "系统设置", nil)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 20, py + 46)
    nvgLineTo(vg, px + panelW - 20, py + 46)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 90, math.floor(alpha * 0.5)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 裁剪区域（内容区）
    local contentTop = py + 52
    local contentBottom = py + panelH - 60
    nvgScissor(vg, px, contentTop, panelW, contentBottom - contentTop)

    local curY = contentTop + 6 - settingsScroll_

    -- ====== 环节时长设置 ======
    nvgFontSize(vg, 15)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(100, 180, 255, math.floor(alpha * 0.8)))
    nvgText(vg, px + 24, curY, "【环节时长】", nil)
    curY = curY + 26

    local btnW = 46
    local btnH = 28
    local btnGap = 8

    local durationRows = {
        { label = "选材时长", options = Config.MaterialTimeOptions, current = GameSettings.GetMaterialTime() },
        { label = "锤击时长", options = Config.HammerTimeOptions, current = GameSettings.GetHammerTime() },
        { label = "淬火时长", options = Config.QuenchTimeOptions, current = GameSettings.GetQuenchTime() },
        { label = "砥砺时长", options = Config.GrindTimeOptions, current = GameSettings.GetGrindTime() },
        { label = "试炼时长", options = Config.TrialTimeOptions, current = GameSettings.GetTrialTime() },
    }

    for _, row in ipairs(durationRows) do
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 205, 210, alpha))
        nvgText(vg, px + 30, curY + 18, row.label, nil)

        local opts = row.options
        local totalW = #opts * btnW + (#opts - 1) * btnGap
        local startX = px + panelW - 24 - totalW

        for oi = 1, #opts do
            local optVal = opts[oi]
            local bx = startX + (oi - 1) * (btnW + btnGap)
            local by = curY + 4
            local isSelected = (optVal == row.current)

            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, btnW, btnH, 5)
            if isSelected then
                nvgFillColor(vg, nvgRGBA(60, 100, 60, alpha))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(80, 200, 120, alpha))
            else
                nvgFillColor(vg, nvgRGBA(40, 42, 52, alpha))
                nvgFill(vg)
                nvgStrokeColor(vg, nvgRGBA(80, 80, 95, math.floor(alpha * 0.6)))
            end
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFontSize(vg, 13)
            if isSelected then
                nvgFillColor(vg, nvgRGBA(80, 220, 130, alpha))
            else
                nvgFillColor(vg, nvgRGBA(180, 185, 195, alpha))
            end
            nvgText(vg, bx + btnW / 2, by + btnH / 2, tostring(optVal) .. "s", nil)
        end

        curY = curY + 42
    end

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 24, curY)
    nvgLineTo(vg, px + panelW - 24, curY)
    nvgStrokeColor(vg, nvgRGBA(60, 60, 70, math.floor(alpha * 0.4)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    curY = curY + 12

    -- ====== 按键设置 ======
    local actions = KeyBindings.Actions
    local rowH = 36
    local lastCategory = ""

    for i = 1, #actions do
        local action = actions[i]

        if action.category ~= lastCategory then
            lastCategory = action.category
            if i > 1 then curY = curY + 12 end
            nvgFontSize(vg, 15)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(100, 180, 255, math.floor(alpha * 0.8)))
            nvgText(vg, px + 24, curY, "【" .. action.category .. "】", nil)
            curY = curY + 26
        end

        local rowY = curY

        -- 操作名
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 205, 210, alpha))
        nvgText(vg, px + 30, rowY + rowH / 2, action.name, nil)

        -- 按键框
        local keyBoxX = px + panelW * 0.50
        local keyBoxW = panelW * 0.42
        local keyBoxH = rowH - 6
        local keyBoxY = rowY + 3

        local isRebinding = (rebindingAction_ == action.id)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, keyBoxX, keyBoxY, keyBoxW, keyBoxH, 5)
        if isRebinding then
            local flash = math.abs(math.sin(rebindFlash_))
            nvgFillColor(vg, nvgRGBA(60, 50, 20, alpha))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 60, math.floor(alpha * (0.5 + flash * 0.5))))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        else
            nvgFillColor(vg, nvgRGBA(40, 42, 52, alpha))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(80, 80, 95, math.floor(alpha * 0.6)))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end

        -- 按键文字
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isRebinding then
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(255, 200, 60, alpha))
            nvgText(vg, keyBoxX + keyBoxW / 2, keyBoxY + keyBoxH / 2, "请按下新按键...", nil)
        else
            nvgFontSize(vg, 15)
            nvgFillColor(vg, nvgRGBA(180, 185, 195, alpha))
            local displayText = KeyBindings.GetDisplayText(action.id)
            nvgText(vg, keyBoxX + keyBoxW / 2, keyBoxY + keyBoxH / 2, displayText, nil)
        end

        curY = curY + rowH
    end

    nvgResetScissor(vg)

    -- "恢复默认"按钮
    local resetBtnW = 120
    local resetBtnH = 32
    local resetBtnX = px + panelW / 2 - resetBtnW / 2
    local resetBtnY = py + panelH - 50

    nvgBeginPath(vg)
    nvgRoundedRect(vg, resetBtnX, resetBtnY, resetBtnW, resetBtnH, 6)
    nvgFillColor(vg, nvgRGBA(60, 40, 40, alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(200, 80, 80, math.floor(alpha * 0.7)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(220, 100, 100, alpha))
    nvgText(vg, resetBtnX + resetBtnW / 2, resetBtnY + resetBtnH / 2, "恢复默认", nil)

    -- 底部提示
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(120, 130, 140, math.floor(alpha * 0.7)))
    nvgText(vg, screenW / 2, py + panelH - 12, "点击选项修改 · ESC 关闭", nil)

    nvgRestore(vg)
end

function Panels.RenderLeaderboard(vg, screenW, screenH)
    local alpha = math.floor(leaderboardAnim_ * 255)
    local panelScale = 0.85 + leaderboardAnim_ * 0.15

    -- 半透明遮罩
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(leaderboardAnim_ * 180)))
    nvgFill(vg)

    -- 面板尺寸
    local panelW = math.min(screenW * 0.75, 400)
    local panelH = math.min(screenH * 0.8, 420)
    local px = (screenW - panelW) / 2
    local py = (screenH - panelH) / 2

    nvgSave(vg)
    nvgTranslate(vg, screenW / 2, screenH / 2)
    nvgScale(vg, panelScale, panelScale)
    nvgTranslate(vg, -screenW / 2, -screenH / 2)

    -- 面板背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, px, py, panelW, panelH, 14)
    nvgFillColor(vg, nvgRGBA(20, 22, 28, alpha))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 90, math.floor(alpha * 0.6)))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    local fontId = NVG.GetFont()
    if fontId == -1 then
        nvgRestore(vg)
        return
    end
    nvgFontFaceId(vg, fontId)

    -- 标题
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(160, 140, 90, alpha))
    nvgText(vg, screenW / 2, py + 16, "排行榜", nil)

    -- 分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, px + 20, py + 44)
    nvgLineTo(vg, px + panelW - 20, py + 44)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 90, math.floor(alpha * 0.5)))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 列标题
    local contentX = px + 20
    local contentW = panelW - 40
    local headerY = py + 52

    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(120, 130, 140, math.floor(alpha * 0.8)))
    nvgText(vg, contentX, headerY, "排名", nil)
    nvgText(vg, contentX + 40, headerY, "玩家", nil)
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    nvgText(vg, contentX + contentW, headerY, "用时 / 伤害", nil)

    -- 内容区
    local rowY = headerY + 22
    local rowH = 28

    if menuLeaderboardLoading_ then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(150, 160, 170, alpha))
        nvgText(vg, screenW / 2, rowY + 20, "加载中...", nil)
    elseif #menuLeaderboardData_ == 0 then
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(150, 160, 170, alpha))
        nvgText(vg, screenW / 2, rowY + 20, "暂无数据", nil)
    else
        for i, item in ipairs(menuLeaderboardData_) do
            local y = rowY + (i - 1) * rowH
            if y + rowH > py + panelH - 40 then break end

            local t = item.time or 0
            local d = item.damage or 0
            local name = item.name or "未知"

            -- 排名颜色
            local rankColor
            if i == 1 then
                rankColor = { 255, 215, 0, alpha }
            elseif i == 2 then
                rankColor = { 200, 200, 210, alpha }
            elseif i == 3 then
                rankColor = { 205, 127, 50, alpha }
            else
                rankColor = { 180, 185, 195, alpha }
            end

            -- 行背景（交替）
            if i % 2 == 0 then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, contentX - 4, y - 2, contentW + 8, rowH, 4)
                nvgFillColor(vg, nvgRGBA(40, 42, 50, math.floor(alpha * 0.4)))
                nvgFill(vg)
            end

            -- 排名
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(rankColor[1], rankColor[2], rankColor[3], rankColor[4]))
            nvgText(vg, contentX, y + 4, "#" .. i, nil)

            -- 玩家名
            nvgFillColor(vg, nvgRGBA(200, 205, 210, alpha))
            nvgText(vg, contentX + 40, y + 4, name, nil)

            -- 用时和伤害
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgFillColor(vg, nvgRGBA(160, 170, 180, math.floor(alpha * 0.9)))
            nvgText(vg, contentX + contentW, y + 4, t .. "秒 " .. d .. "伤害", nil)
        end
    end

    -- 底部提示
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 130, 140, math.floor(alpha * 0.7)))
    nvgText(vg, screenW / 2, py + panelH - 10, "点击任意位置关闭", nil)

    nvgRestore(vg)
end

return Panels
