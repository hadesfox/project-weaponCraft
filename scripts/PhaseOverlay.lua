-- ============================================================================
-- PhaseOverlay.lua - 竞技场铁门 + 黑屏过渡系统
-- 负责：
--   1. 画面左侧竞技场铁门（随阶段 5→1 逐步碎裂）
--   2. 进入每个环节前的黑屏字幕提示
--   3. 最终破碎：铁门放大崩碎消散进入竞技场
-- ============================================================================

local Config = require("Config")
local NVG = require("NVG")

local PhaseOverlay = {}

-- ============================================================================
-- 阶段定义
-- ============================================================================
-- 阶段编号: 5=绘制, 4=材质, 3=锤击, 2=淬火, 1=砥砺, 0=试炼场(破碎)
local PHASE_INFO = {
    [5] = { title = "阶段五", subtitle = "绘制武器轮廓" },
    [4] = { title = "阶段四", subtitle = "选材" },
    [3] = { title = "阶段三", subtitle = "锤击定型" },
    [2] = { title = "阶段二", subtitle = "淬火淬炼" },
    [1] = { title = "阶段一", subtitle = "砥砺磨光" },
    [0] = { title = "试炼", subtitle = "以剑证道" },
}

-- 音效路径
local CRACK_SOUNDS = {
    [5] = nil,
    [4] = "audio/sfx/crack_1.ogg",
    [3] = "audio/sfx/crack_2.ogg",
    [2] = "audio/sfx/crack_3.ogg",
    [1] = "audio/sfx/crack_4.ogg",
    [0] = "audio/sfx/shatter_final.ogg",
}

-- ============================================================================
-- 状态
-- ============================================================================
local currentPhase_ = -1
local active_ = false

-- 黑屏过渡
local transition_ = {
    active = false,
    blocking = true,
    timer = 0,
    duration = 1.8,
    fadeInTime = 0.3,
    fadeOutTime = 0.4,
    phase = 0,
    onDone = nil,
    soundPlayed = false,
}

-- 碎片粒子系统
local fragments_ = {}
local shatterTriggered_ = false

-- 最终破碎动画
local finalShatter_ = {
    active = false,
    timer = 0,
    duration = 1.2,      -- 铁门放大崩碎持续时间
}

-- 铁门碎片（最终崩碎时的大块铁片）
local gateShards_ = {}

-- 音频
local audioScene_ = nil
local audioNode_ = nil

-- 铁门裂缝数据（每阶段固定种子，避免闪烁）
local gateCracks_ = {}

-- 心跳节奏系统
local heartbeat_ = {
    enabled = false,
    timer = 0,           -- 累计计时
    interval = 1.2,      -- 当前心跳间隔（秒）
    lastBeat = 0,        -- 上次心跳时间
    pulse = 0,           -- 脉冲动画值 0→1→0
    sound = nil,         -- Sound 资源
    source = nil,        -- SoundSource 组件
}

-- 每个阶段的心跳间隔（阶段5最慢，阶段1最快）
local HEARTBEAT_INTERVALS = {
    [5] = 1.4,   -- 平静
    [4] = 1.1,   -- 稍快
    [3] = 0.85,  -- 紧张
    [2] = 0.65,  -- 急促
    [1] = 0.45,  -- 疯狂
}

-- ============================================================================
-- 初始化
-- ============================================================================

function PhaseOverlay.Init()
    audioScene_ = Scene()
    audioNode_ = audioScene_:CreateChild("PhaseOverlaySFX")
    currentPhase_ = -1
    active_ = false
    fragments_ = {}
    gateShards_ = {}
    shatterTriggered_ = false
    finalShatter_.active = false
    finalShatter_.timer = 0
    -- 预生成裂缝数据
    PhaseOverlay.GenerateCracks()
    -- 加载心跳音效
    heartbeat_.sound = cache:GetResource("Sound", "audio/sfx/heartbeat.ogg")
    if heartbeat_.sound then
        heartbeat_.sound.looped = false
    end
    heartbeat_.enabled = false
    heartbeat_.timer = 0
    heartbeat_.lastBeat = -10
    heartbeat_.pulse = 0
end

function PhaseOverlay.Shutdown()
    if audioScene_ then
        audioScene_:Remove()
        audioScene_ = nil
        audioNode_ = nil
    end
end

--- 预生成每个碎裂等级的裂缝路径（固定种子避免每帧闪烁）
function PhaseOverlay.GenerateCracks()
    math.randomseed(42)
    gateCracks_ = {}
    for level = 1, 4 do
        gateCracks_[level] = {}
        local count = level * 3 + 2
        for i = 1, count do
            local crack = {
                -- 起始点偏移（相对于门中心）
                sx = (math.random() - 0.5) * 0.6,
                sy = (math.random() - 0.5) * 0.8,
                -- 方向和长度
                angle = math.random() * math.pi * 2,
                length = 0.1 + math.random() * 0.2 * level,
                -- 中间折点偏移
                bend = (math.random() - 0.5) * 0.15,
                -- 宽度
                width = 1.0 + math.random() * 1.5,
            }
            gateCracks_[level][i] = crack
        end
    end
    math.randomseed(os.time())
end

--- 播放崩裂音效
local function PlayCrackSound(phase)
    local path = CRACK_SOUNDS[phase]
    if not path then return end
    if not audioNode_ then return end

    local sound = cache:GetResource("Sound", path)
    if not sound then return end
    sound.looped = false

    local src = audioNode_:CreateComponent("SoundSource")
    src.soundType = SOUND_EFFECT
    src.gain = 0.8
    src:Play(sound)
end

--- 生成碎片粒子
local function SpawnFragments(cx, cy, count, intensity)
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = (40 + math.random() * 80) * intensity
        local frag = {
            x = cx + (math.random() - 0.5) * 20,
            y = cy + (math.random() - 0.5) * 20,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 30,
            rot = math.random() * math.pi * 2,
            rotV = (math.random() - 0.5) * 12,
            size = 3 + math.random() * 5 * intensity,
            alpha = 255,
            life = 1.0 + math.random() * 0.5,
        }
        fragments_[#fragments_ + 1] = frag
    end
end

--- 生成铁门崩碎碎片（大块铁片飞散）
local function SpawnGateShards(cx, cy, gateW, gateH)
    gateShards_ = {}
    local cols = 4
    local rows = 5
    local shardW = gateW / cols
    local shardH = gateH / rows
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local sx = cx - gateW / 2 + c * shardW + shardW / 2
            local sy = cy - gateH / 2 + r * shardH + shardH / 2
            local angle = math.atan(sy - cy, sx - cx)
            local speed = 150 + math.random() * 200
            local shard = {
                x = sx, y = sy,
                w = shardW * (0.8 + math.random() * 0.4),
                h = shardH * (0.8 + math.random() * 0.4),
                vx = math.cos(angle) * speed + (math.random() - 0.5) * 60,
                vy = math.sin(angle) * speed - 80 - math.random() * 60,
                rot = 0,
                rotV = (math.random() - 0.5) * 15,
                alpha = 255,
                life = 0.8 + math.random() * 0.4,
            }
            gateShards_[#gateShards_ + 1] = shard
        end
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function PhaseOverlay.Start()
    active_ = true
    currentPhase_ = 5
    fragments_ = {}
    gateShards_ = {}
    shatterTriggered_ = false
    finalShatter_.active = false
    finalShatter_.timer = 0
    -- 启动心跳
    heartbeat_.enabled = true
    heartbeat_.timer = 0
    heartbeat_.lastBeat = -10
    heartbeat_.pulse = 0
    heartbeat_.interval = HEARTBEAT_INTERVALS[5] or 1.4
    print("[PhaseOverlay] Started at phase 5")
end

function PhaseOverlay.GetPhase()
    return currentPhase_
end

function PhaseOverlay.IsTransitioning()
    return (transition_.active and transition_.blocking) or finalShatter_.active
end

--- 触发阶段过渡
function PhaseOverlay.TransitionTo(targetPhase, onDone, blocking)
    if blocking == nil then blocking = (onDone ~= nil) end
    transition_.active = true
    transition_.blocking = blocking
    transition_.timer = 0
    transition_.phase = targetPhase
    transition_.onDone = onDone
    transition_.soundPlayed = false
    if blocking then
        transition_.duration = 1.8
        transition_.fadeInTime = 0.3
        transition_.fadeOutTime = 0.4
    else
        transition_.duration = 0.6
        transition_.fadeInTime = 0.1
        transition_.fadeOutTime = 0.1
    end
    print("[PhaseOverlay] Transition to phase " .. targetPhase .. (blocking and " [blocking]" or " [non-blocking]"))
end

--- 更新（每帧调用）
function PhaseOverlay.Update(dt)
    -- 更新心跳节奏
    if heartbeat_.enabled and not finalShatter_.active then
        heartbeat_.timer = heartbeat_.timer + dt
        -- 脉冲衰减（快速回落）
        if heartbeat_.pulse > 0 then
            heartbeat_.pulse = heartbeat_.pulse - dt * 4.0
            if heartbeat_.pulse < 0 then heartbeat_.pulse = 0 end
        end
        -- 到达心跳间隔时触发
        if heartbeat_.timer - heartbeat_.lastBeat >= heartbeat_.interval then
            heartbeat_.lastBeat = heartbeat_.timer
            heartbeat_.pulse = 1.0  -- 触发脉冲
            -- 播放心跳音效
            if heartbeat_.sound and audioNode_ then
                local src = audioNode_:CreateComponent("SoundSource")
                src.soundType = SOUND_EFFECT
                -- 越快越响（阶段1最大）
                local gain = 0.25 + (1.4 - heartbeat_.interval) / 1.0 * 0.35
                src.gain = math.min(0.6, gain)
                src:Play(heartbeat_.sound)
            end
        end
    end

    -- 更新小碎片
    local i = 1
    while i <= #fragments_ do
        local f = fragments_[i]
        f.life = f.life - dt
        if f.life <= 0 then
            table.remove(fragments_, i)
        else
            f.x = f.x + f.vx * dt
            f.y = f.y + f.vy * dt
            f.vy = f.vy + 200 * dt
            f.rot = f.rot + f.rotV * dt
            f.alpha = math.max(0, f.alpha - 180 * dt)
            i = i + 1
        end
    end

    -- 更新铁门碎片
    i = 1
    while i <= #gateShards_ do
        local s = gateShards_[i]
        s.life = s.life - dt
        if s.life <= 0 then
            table.remove(gateShards_, i)
        else
            s.x = s.x + s.vx * dt
            s.y = s.y + s.vy * dt
            s.vy = s.vy + 400 * dt  -- 重力
            s.rot = s.rot + s.rotV * dt
            s.alpha = math.max(0, 255 * (s.life / 1.2))
            i = i + 1
        end
    end

    -- 最终崩碎动画
    if finalShatter_.active then
        finalShatter_.timer = finalShatter_.timer + dt
        if finalShatter_.timer >= finalShatter_.duration then
            finalShatter_.active = false
            -- 过渡完成回调
            if transition_.onDone then
                local cb = transition_.onDone
                transition_.onDone = nil
                transition_.active = false
                cb()
            end
        end
        return  -- 崩碎动画期间不处理其他过渡
    end

    -- 更新黑屏过渡
    if transition_.active then
        transition_.timer = transition_.timer + dt

        local midPoint = transition_.fadeInTime + 0.2
        if transition_.timer >= midPoint and not transition_.soundPlayed then
            transition_.soundPlayed = true
            currentPhase_ = transition_.phase

            -- 更新心跳节奏（越后面的阶段越快）
            if HEARTBEAT_INTERVALS[currentPhase_] then
                heartbeat_.interval = HEARTBEAT_INTERVALS[currentPhase_]
            elseif currentPhase_ <= 0 then
                heartbeat_.enabled = false  -- 进入试炼场后停止心跳
            end

            PlayCrackSound(transition_.phase)

            local dpr = graphics:GetDPR()
            local lw = graphics:GetWidth() / dpr
            local lh = graphics:GetHeight() / dpr
            local gateW = lw * 0.12
            local gateH = lh * 0.55
            local cx = gateW * 0.55
            local cy = lh * 0.48
            local intensity = (5 - transition_.phase) / 4

            if transition_.phase == 0 then
                -- 最终破碎：启动铁门崩碎动画
                shatterTriggered_ = true
                finalShatter_.active = true
                finalShatter_.timer = 0
                -- 生成铁门碎片
                SpawnGateShards(cx, cy, gateW, gateH)
                SpawnFragments(cx, cy, 40, 2.0)
            else
                local count = math.floor(8 + intensity * 25)
                SpawnFragments(cx, cy, count, intensity)
            end
        end

        -- 过渡结束（非最终破碎）
        if transition_.timer >= transition_.duration and transition_.phase ~= 0 then
            transition_.active = false
            if transition_.onDone then
                transition_.onDone()
            end
        end
        -- phase==0 的过渡由 finalShatter_ 控制结束
        if transition_.phase == 0 and transition_.timer >= transition_.duration and not finalShatter_.active then
            transition_.active = false
        end
    end
end

-- ============================================================================
-- 铁门渲染
-- ============================================================================

--- 绘制竞技场铁门（带碎裂程度）
--- crackLevel: 0=完好(阶段5), 1=轻微(4), 2=中度(3), 3=重度(2), 4=极碎(1)
local function RenderIronGate(vg, cx, cy, gateW, gateH, crackLevel, scale)
    scale = scale or 1.0
    local hw = gateW / 2 * scale
    local hh = gateH / 2 * scale

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)

    -- ====== 铁门主体 ======
    -- 门框底色（深灰铁色）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -hw, -hh, hw * 2, hh * 2, 4 * scale)
    local baseR = math.max(30, 55 - crackLevel * 5)
    local baseG = math.max(28, 52 - crackLevel * 5)
    local baseB = math.max(32, 58 - crackLevel * 5)
    nvgFillColor(vg, nvgRGBA(baseR, baseG, baseB, 240))
    nvgFill(vg)

    -- 门框边框
    nvgStrokeColor(vg, nvgRGBA(90, 85, 80, 220))
    nvgStrokeWidth(vg, 3 * scale)
    nvgStroke(vg)

    -- ====== 竖条铁栅栏 ======
    local barCount = 5
    local barSpacing = (hw * 2) / (barCount + 1)
    nvgStrokeWidth(vg, 4 * scale)
    for i = 1, barCount do
        local bx = -hw + i * barSpacing
        -- 碎裂时铁条弯曲/断裂
        local bendY = 0
        local broken = false
        if crackLevel >= 2 and (i == 2 or i == 4) then
            bendY = crackLevel * 3 * scale
        end
        if crackLevel >= 3 and i == 3 then
            broken = true
        end
        if crackLevel >= 4 and (i == 1 or i == 5) then
            bendY = crackLevel * 5 * scale
        end

        if not broken then
            nvgBeginPath(vg)
            nvgMoveTo(vg, bx, -hh + 6 * scale)
            if bendY ~= 0 then
                -- 弯曲的铁条
                nvgBezierTo(vg, bx, -hh * 0.3, bx + bendY, hh * 0.3, bx, hh - 6 * scale)
            else
                nvgLineTo(vg, bx, hh - 6 * scale)
            end
            nvgStrokeColor(vg, nvgRGBA(75, 72, 68, 255))
            nvgStroke(vg)
        else
            -- 断裂铁条：上半截和下半截分离
            nvgBeginPath(vg)
            nvgMoveTo(vg, bx, -hh + 6 * scale)
            nvgLineTo(vg, bx - 2 * scale, -4 * scale)
            nvgStrokeColor(vg, nvgRGBA(75, 72, 68, 255))
            nvgStroke(vg)
            nvgBeginPath(vg)
            nvgMoveTo(vg, bx + 3 * scale, 8 * scale)
            nvgLineTo(vg, bx, hh - 6 * scale)
            nvgStroke(vg)
        end
    end

    -- ====== 横条加固条 ======
    local hBarCount = 3
    local hBarSpacing = (hh * 2) / (hBarCount + 1)
    nvgStrokeWidth(vg, 3 * scale)
    for i = 1, hBarCount do
        local by = -hh + i * hBarSpacing
        local offsetX = 0
        if crackLevel >= 3 and i == 2 then
            offsetX = crackLevel * 2 * scale  -- 横条位移
        end
        nvgBeginPath(vg)
        nvgMoveTo(vg, -hw + 4 * scale + offsetX, by)
        nvgLineTo(vg, hw - 4 * scale + offsetX, by)
        nvgStrokeColor(vg, nvgRGBA(65, 62, 58, 255))
        nvgStroke(vg)
    end

    -- ====== 铆钉 ======
    local rivetPositions = {
        {-hw + 8, -hh + 8}, {hw - 8, -hh + 8},
        {-hw + 8, hh - 8},  {hw - 8, hh - 8},
        {-hw + 8, 0},       {hw - 8, 0},
    }
    for idx, pos in ipairs(rivetPositions) do
        local rx, ry = pos[1] * scale, pos[2] * scale
        -- 碎裂时部分铆钉脱落
        local fallen = false
        if crackLevel >= 1 and idx == 4 then fallen = true end
        if crackLevel >= 2 and idx == 6 then fallen = true end
        if crackLevel >= 3 and idx == 1 then fallen = true end
        if crackLevel >= 4 and idx == 3 then fallen = true end

        if not fallen then
            nvgBeginPath(vg)
            nvgCircle(vg, rx, ry, 3.5 * scale)
            nvgFillColor(vg, nvgRGBA(100, 95, 88, 255))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, rx - 1 * scale, ry - 1 * scale, 1.5 * scale)
            nvgFillColor(vg, nvgRGBA(130, 125, 115, 200))
            nvgFill(vg)
        else
            -- 脱落铆钉孔
            nvgBeginPath(vg)
            nvgCircle(vg, rx, ry, 3 * scale)
            nvgFillColor(vg, nvgRGBA(20, 18, 22, 200))
            nvgFill(vg)
        end
    end

    -- ====== 裂缝 ======
    if crackLevel > 0 and gateCracks_[crackLevel] then
        nvgStrokeWidth(vg, 1.5 * scale)
        for _, crack in ipairs(gateCracks_[crackLevel]) do
            local sx = crack.sx * hw * 2
            local sy = crack.sy * hh * 2
            local length = crack.length * hh * 2
            local ex = sx + math.cos(crack.angle) * length
            local ey = sy + math.sin(crack.angle) * length
            local mx = (sx + ex) / 2 + crack.bend * hw
            local my = (sy + ey) / 2 + crack.bend * hh

            nvgBeginPath(vg)
            nvgMoveTo(vg, sx, sy)
            nvgLineTo(vg, mx, my)
            nvgLineTo(vg, ex, ey)

            -- 裂缝颜色：越碎越亮（发红光）
            local cr = math.min(255, 80 + crackLevel * 40)
            local cg = math.max(15, 40 - crackLevel * 8)
            local cb = math.max(10, 30 - crackLevel * 5)
            local ca = math.min(255, 120 + crackLevel * 30)
            nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, ca))
            nvgStroke(vg)
        end

        -- 裂缝发光效果（高碎裂等级）
        if crackLevel >= 3 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, -hw, -hh, hw * 2, hh * 2, 4 * scale)
            local glowAlpha = (crackLevel - 2) * 15
            nvgFillColor(vg, nvgRGBA(180, 60, 20, glowAlpha))
            nvgFill(vg)
        end
    end

    -- ====== 铁门表面大字（五四三二一） ======
    local PHASE_CHARS = { [5] = "五", [4] = "四", [3] = "三", [2] = "二", [1] = "一" }
    local phaseChar = PHASE_CHARS[currentPhase_]
    if phaseChar then
        local fontId = NVG.GetFont()
        if fontId ~= -1 then
            nvgFontFaceId(vg, fontId)
            local fontSize = math.floor(math.min(hw * 1.4, hh * 0.7) * 2)
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            -- 底层阴影（凿刻深度感）
            nvgFillColor(vg, nvgRGBA(10, 8, 12, 160))
            nvgText(vg, 2 * scale, 2 * scale, phaseChar, nil)
            -- 主体文字（金属浮雕色，随碎裂程度变红）
            local tr = math.min(255, 140 + crackLevel * 25)
            local tg = math.max(60, 120 - crackLevel * 15)
            local tb = math.max(40, 100 - crackLevel * 15)
            nvgFillColor(vg, nvgRGBA(tr, tg, tb, 220))
            nvgText(vg, 0, 0, phaseChar, nil)
            -- 高光（顶部偏移，金属反光）
            nvgFillColor(vg, nvgRGBA(220, 210, 190, 50 - crackLevel * 8))
            nvgText(vg, -1 * scale, -2 * scale, phaseChar, nil)
        end
    end

    -- ====== 阶段标注 ======
    local fontId = NVG.GetFont()
    if fontId ~= -1 then
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, math.floor(11 * scale))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(140, 130, 120, 180))
        nvgText(vg, 0, hh + 14 * scale, "阶段" .. (currentPhase_ > 0 and tostring(currentPhase_) or ""), nil)
    end

    nvgRestore(vg)
end

-- ============================================================================
-- 渲染
-- ============================================================================

function PhaseOverlay.Render(vg)
    if not active_ then return end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local lw = w / dpr
    local lh = h / dpr

    local fontId = NVG.GetFont()
    if fontId == -1 then return end

    -- ========================================
    -- 1. 渲染左侧竞技场铁门
    -- ========================================
    if currentPhase_ >= 1 and not shatterTriggered_ then
        local gateW = lw * 0.12            -- 宽度占屏幕12%（自适应）
        local gateH = lh * 0.55            -- 高度占屏幕55%（更大更有压迫感）
        local gateX = gateW * 0.55         -- 左侧居中偏移
        local gateY = lh * 0.48            -- 垂直略偏上
        -- crackLevel: 0(阶段5完好) → 4(阶段1极碎)
        local crackLevel = 5 - currentPhase_

        -- 心跳脉冲：铁门轻微放大（easeOut 衰减曲线）
        local pulseScale = 1.0
        if heartbeat_.enabled and heartbeat_.pulse > 0 then
            local eased = heartbeat_.pulse * heartbeat_.pulse  -- 快速衰减
            -- 脉冲幅度随阶段递增（阶段5微弱，阶段1明显）
            local maxPulse = 0.02 + crackLevel * 0.02  -- 0.02 ~ 0.10
            pulseScale = 1.0 + eased * maxPulse
        end

        RenderIronGate(vg, gateX, gateY, gateW, gateH, crackLevel, pulseScale)
    end

    -- ========================================
    -- 2. 最终崩碎动画（铁门放大 → 碎裂消散）
    -- ========================================
    if finalShatter_.active then
        local t = finalShatter_.timer / finalShatter_.duration  -- 0→1
        local gateW = lw * 0.12
        local gateH = lh * 0.55
        local gateX = gateW * 0.55
        local gateY = lh * 0.48

        -- 前30%: 门向中心放大+震动
        if t < 0.3 then
            local st = t / 0.3  -- 0→1
            local scale = 1.0 + st * 2.5  -- 放大到3.5倍
            local shakeX = math.sin(st * 30) * 4 * (1 - st)
            local shakeY = math.cos(st * 25) * 3 * (1 - st)
            local moveX = (lw * 0.5 - gateX) * st * 0.6
            RenderIronGate(vg, gateX + moveX + shakeX, gateY + shakeY, gateW, gateH, 4, scale)
        end
        -- 30%之后: 渲染飞散的铁门碎片
        -- (碎片在 Update 中更新位置)

        -- 全屏闪白（崩碎瞬间）
        if t > 0.25 and t < 0.45 then
            local flashT = (t - 0.25) / 0.2
            local flashAlpha = math.sin(flashT * math.pi) * 120
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, lw, lh)
            nvgFillColor(vg, nvgRGBA(255, 240, 200, math.floor(flashAlpha)))
            nvgFill(vg)
        end

        -- 尾部淡黑（过渡到竞技场）
        if t > 0.7 then
            local fadeT = (t - 0.7) / 0.3
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, lw, lh)
            nvgFillColor(vg, nvgRGBA(5, 5, 10, math.floor(fadeT * 255)))
            nvgFill(vg)
        end
    end

    -- ========================================
    -- 3. 渲染铁门碎片（崩碎飞散）
    -- ========================================
    for _, s in ipairs(gateShards_) do
        if s.alpha > 0 then
            nvgSave(vg)
            nvgTranslate(vg, s.x, s.y)
            nvgRotate(vg, s.rot)
            nvgBeginPath(vg)
            -- 不规则铁片碎片
            local hw2 = s.w / 2
            local hh2 = s.h / 2
            nvgMoveTo(vg, -hw2 * 0.8, -hh2)
            nvgLineTo(vg, hw2, -hh2 * 0.7)
            nvgLineTo(vg, hw2 * 0.9, hh2)
            nvgLineTo(vg, -hw2, hh2 * 0.8)
            nvgClosePath(vg)
            nvgFillColor(vg, nvgRGBA(60, 58, 55, math.floor(s.alpha)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(90, 85, 78, math.floor(s.alpha * 0.8)))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
            nvgRestore(vg)
        end
    end

    -- ========================================
    -- 4. 渲染小碎片粒子
    -- ========================================
    for _, f in ipairs(fragments_) do
        nvgSave(vg)
        nvgTranslate(vg, f.x, f.y)
        nvgRotate(vg, f.rot)
        nvgBeginPath(vg)
        local hs = f.size / 2
        nvgMoveTo(vg, -hs, -hs * 0.6)
        nvgLineTo(vg, hs * 0.7, -hs)
        nvgLineTo(vg, hs, hs * 0.5)
        nvgLineTo(vg, -hs * 0.5, hs)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(160, 80, 40, math.floor(f.alpha)))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- ========================================
    -- 5. 黑屏过渡渲染（阻塞式）
    -- ========================================
    if transition_.active and transition_.blocking and not finalShatter_.active then
        local t = transition_.timer
        local dur = transition_.duration
        local fadeIn = transition_.fadeInTime
        local fadeOut = transition_.fadeOutTime

        local alpha = 0
        if t < fadeIn then
            alpha = t / fadeIn
        elseif t > dur - fadeOut then
            alpha = (dur - t) / fadeOut
        else
            alpha = 1.0
        end
        alpha = math.max(0, math.min(1, alpha))

        -- 全屏黑色遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, lw, lh)
        nvgFillColor(vg, nvgRGBA(5, 5, 10, math.floor(alpha * 240)))
        nvgFill(vg)

        -- 中间文字
        if alpha > 0.7 then
            local info = PHASE_INFO[transition_.phase]
            if info then
                local textAlpha = math.floor(math.min(1, (alpha - 0.7) / 0.3) * 255)

                nvgFontFaceId(vg, fontId)
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(220, 200, 160, textAlpha))
                nvgText(vg, lw / 2, lh / 2 - 20, info.title, nil)

                nvgFontSize(vg, 16)
                nvgFillColor(vg, nvgRGBA(180, 180, 190, math.floor(textAlpha * 0.8)))
                nvgText(vg, lw / 2, lh / 2 + 18, info.subtitle, nil)
            end
        end
    end
end

return PhaseOverlay
