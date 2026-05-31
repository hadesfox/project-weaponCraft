-- ============================================================================
-- States/MaterialState.lua - 选材阶段
-- 材质以弹幕方式从屏幕飞过，玩家点击任意方块即选中该材质并结束环节
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")

local MaterialState = {}

local gameData_ = nil
local onComplete_ = nil

-- 弹幕参数（从 Config 读取）
local DC = Config.MaterialDanmaku
local materials_ = Config.Materials

-- 运行时状态
local timer_ = 0             -- 总计时器
local spawnTimer_ = 0        -- 生成计时
local bullets_ = {}          -- 活跃弹幕列表 { x, y, speed, matIndex, lane }
local selectedMat_ = nil     -- 选中的材质（nil=未选）
local resultTimer_ = 0       -- 结果展示计时
local done_ = false          -- 是否已结束

-- 结果展示时长
local RESULT_SHOW_TIME = 1.2

--- 进入选材
function MaterialState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    timer_ = 0
    spawnTimer_ = 0
    bullets_ = {}
    selectedMat_ = nil
    resultTimer_ = 0
    done_ = false

    print("[MaterialState] Entered - 选材")
end

--- 离开
function MaterialState.Leave()
    bullets_ = {}
end

--- 构建 UI
function MaterialState.BuildUI()
    return UI.Panel {
        width = "100%", height = "100%",
        children = {
            -- 顶部提示
            UI.Panel {
                width = "100%",
                padding = 12,
                alignItems = "center",
                backgroundColor = Config.Colors.BgDark,
                children = {
                    UI.Label {
                        id = "materialTitle",
                        text = "选材",
                        fontSize = 18,
                        fontColor = Config.Colors.TextLight,
                    },
                },
            },
            -- 中间区域由 NanoVG 渲染
            UI.Panel {
                width = "100%", flexGrow = 1,
                pointerEvents = "none",
            },
            -- 底部提示
            UI.Panel {
                width = "100%",
                padding = 10,
                alignItems = "center",
                backgroundColor = Config.Colors.BgDark,
                children = {
                    UI.Label {
                        id = "materialHint",
                        text = "点击飞过的方块选择材质!",
                        fontSize = 13,
                        fontColor = { 180, 180, 200, 200 },
                    },
                },
            },
        },
    }
end

--- 生成一颗弹幕
local function SpawnBullet()
    local matIdx = math.random(1, #materials_)
    local lane = math.random(1, DC.Lanes)
    local speed = DC.Speed[1] + math.random() * (DC.Speed[2] - DC.Speed[1])

    -- 从右侧屏幕外生成
    local dpr = graphics:GetDPR()
    local logW = graphics:GetWidth() / dpr

    local bullet = {
        x = logW + DC.BoxWidth,
        y = 0,
        speed = speed,
        matIndex = matIdx,
        lane = lane,
    }
    bullets_[#bullets_ + 1] = bullet
end

--- 超时自动随机选取
local function AutoSelect()
    if selectedMat_ then return end
    local idx = math.random(1, #materials_)
    selectedMat_ = materials_[idx]
    gameData_.material = selectedMat_
    resultTimer_ = 0
    print("[MaterialState] Auto-selected: " .. selectedMat_.name)
end

--- 玩家手动选取
local function SelectMaterial(matIndex)
    if selectedMat_ then return end
    if matIndex < 1 or matIndex > #materials_ then return end
    selectedMat_ = materials_[matIndex]
    gameData_.material = selectedMat_
    resultTimer_ = 0
    print("[MaterialState] Player selected: " .. selectedMat_.name)
end

--- 碰撞检测：点击坐标是否在弹幕框内
local function HitTest(px, py)
    local dpr = graphics:GetDPR()
    local logH = graphics:GetHeight() / dpr

    -- 计算弹幕区域
    local topBarH = 44
    local bottomBarH = 44
    local areaT = topBarH
    local areaH = logH - topBarH - bottomBarH
    local laneH = areaH / DC.Lanes

    for i = #bullets_, 1, -1 do
        local b = bullets_[i]
        local by = areaT + (b.lane - 0.5) * laneH - DC.BoxHeight / 2
        local bx = b.x

        if px >= bx and px <= bx + DC.BoxWidth and
           py >= by and py <= by + DC.BoxHeight then
            return b.matIndex
        end
    end
    return nil
end

--- 处理输入（点击/触摸）
local function HandleInput(px, py)
    if done_ then return end
    if selectedMat_ then return end

    -- 将物理坐标转为逻辑坐标
    local dpr = graphics:GetDPR()
    local lx = px / dpr
    local ly = py / dpr

    local hitIdx = HitTest(lx, ly)
    if hitIdx then
        SelectMaterial(hitIdx)
    end
end

--- 更新
function MaterialState.Update(dt)
    if done_ then return end

    -- 已选中：展示结果后结束
    if selectedMat_ then
        resultTimer_ = resultTimer_ + dt
        if resultTimer_ >= RESULT_SHOW_TIME then
            done_ = true
            if onComplete_ then onComplete_() end
        end
        return
    end

    -- 计时
    timer_ = timer_ + dt

    -- 超时判定
    if timer_ >= DC.Duration then
        AutoSelect()
        return
    end

    -- 生成弹幕
    spawnTimer_ = spawnTimer_ + dt
    if spawnTimer_ >= DC.SpawnInterval then
        spawnTimer_ = spawnTimer_ - DC.SpawnInterval
        SpawnBullet()
    end

    -- 更新弹幕位置
    local i = 1
    while i <= #bullets_ do
        local b = bullets_[i]
        b.x = b.x - b.speed * dt
        -- 移出屏幕左侧则移除
        if b.x + DC.BoxWidth < -20 then
            table.remove(bullets_, i)
        else
            i = i + 1
        end
    end
end

--- 渲染
function MaterialState.Render(vg)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local lw = w / dpr
    local lh = h / dpr

    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, lw, lh)
    nvgFillColor(vg, nvgRGBA(
        Config.Colors.BgDark[1],
        Config.Colors.BgDark[2],
        Config.Colors.BgDark[3],
        Config.Colors.BgDark[4]
    ))
    nvgFill(vg)

    local fontId = NVG.GetFont()
    if fontId == -1 then
        nvgResetTransform(vg)
        nvgEndFrame(vg)
        return
    end
    nvgFontFaceId(vg, fontId)

    -- 弹幕区域
    local topBarH = 44
    local bottomBarH = 44
    local areaT = topBarH
    local areaH = lh - topBarH - bottomBarH
    local laneH = areaH / DC.Lanes

    -- 绘制车道线（微弱分隔线）
    for i = 1, DC.Lanes - 1 do
        local ly = areaT + i * laneH
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, ly)
        nvgLineTo(vg, lw, ly)
        nvgStrokeColor(vg, nvgRGBA(50, 50, 60, 80))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    -- 绘制弹幕方块
    for _, b in ipairs(bullets_) do
        local mat = materials_[b.matIndex]
        local by = areaT + (b.lane - 0.5) * laneH - DC.BoxHeight / 2
        local bx = b.x

        -- 方块背景（使用材质颜色）
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, by, DC.BoxWidth, DC.BoxHeight, 6)
        nvgFillColor(vg, nvgRGBA(mat.color[1], mat.color[2], mat.color[3], 180))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(
            math.min(255, mat.color[1] + 60),
            math.min(255, mat.color[2] + 60),
            math.min(255, mat.color[3] + 60),
            150
        ))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 材质名称文字
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(240, 240, 250, 240))
        nvgText(vg, bx + DC.BoxWidth / 2, by + DC.BoxHeight / 2, mat.name, nil)
    end

    -- 倒计时显示
    if not selectedMat_ then
        local remaining = math.max(0, DC.Duration - timer_)
        local timeText = string.format("%.1f", remaining)
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if remaining <= 1.5 then
            local pulse = math.abs(math.sin(timer_ * 8))
            nvgFillColor(vg, nvgRGBA(240, 80, 80, math.floor(180 + pulse * 75)))
        else
            nvgFillColor(vg, nvgRGBA(200, 205, 210, 200))
        end
        nvgText(vg, lw / 2, areaT + 8, timeText, nil)
    end

    -- 选中结果展示
    if selectedMat_ then
        -- 半透明遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, lw, lh)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)

        -- 结果面板
        local panelW = math.min(260, lw * 0.7)
        local panelH = 130
        local px = (lw - panelW) / 2
        local py = (lh - panelH) / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py, panelW, panelH, 12)
        nvgFillColor(vg, nvgRGBA(30, 32, 40, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(
            selectedMat_.color[1],
            selectedMat_.color[2],
            selectedMat_.color[3],
            200
        ))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)

        -- 材质名称（大字）
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 24)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(
            selectedMat_.color[1],
            selectedMat_.color[2],
            selectedMat_.color[3],
            255
        ))
        nvgText(vg, lw / 2, py + 35, selectedMat_.name, nil)

        -- 效果描述
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(200, 205, 210, 230))
        nvgText(vg, lw / 2, py + 68, selectedMat_.desc, nil)

        -- 属性修正
        local atkText = ""
        if selectedMat_.atkMod > 0 then
            atkText = "攻击+" .. math.floor(selectedMat_.atkMod * 100) .. "%"
        elseif selectedMat_.atkMod < 0 then
            atkText = "攻击" .. math.floor(selectedMat_.atkMod * 100) .. "%"
        end

        local spdText = ""
        if selectedMat_.spdMod > 0 then
            spdText = "攻速+" .. math.floor(selectedMat_.spdMod * 100) .. "%"
        elseif selectedMat_.spdMod < 0 then
            spdText = "攻速" .. math.floor(selectedMat_.spdMod * 100) .. "%"
        end

        local statLine = ""
        if atkText ~= "" then statLine = atkText end
        if spdText ~= "" then
            if statLine ~= "" then statLine = statLine .. "  " end
            statLine = statLine .. spdText
        end

        if statLine ~= "" then
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(Config.Colors.Gold[1], Config.Colors.Gold[2], Config.Colors.Gold[3], 200))
            nvgText(vg, lw / 2, py + 95, statLine, nil)
        end

        -- 代价
        if selectedMat_.penalty then
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(240, 80, 80, 180))
            local penaltyText = "代价: " .. selectedMat_.penalty
            nvgText(vg, lw / 2, py + 115, penaltyText, nil)
        end
    end

    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

-- ============================================================================
-- 输入处理
-- ============================================================================

function MaterialState.OnKeyDown(key)
end

function MaterialState.OnKeyUp(key)
end

function MaterialState.OnMouseDown(button)
    if button == MOUSEB_LEFT then
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        HandleInput(mx, my)
    end
end

function MaterialState.OnMouseUp(button)
end

function MaterialState.OnMouseMove()
end

function MaterialState.OnTouchBegin(x, y)
    HandleInput(x, y)
end

function MaterialState.OnTouchMove(x, y)
end

function MaterialState.OnTouchEnd(x, y)
end

return MaterialState
