-- ============================================================================
-- PhaseOverlay.lua - 黑屏过渡 + 心跳节奏系统
-- 负责：
--   1. 进入每个环节前的黑屏字幕提示
--   2. 心跳节奏音效（随阶段加速）
--   3. 阶段过渡管理
-- ============================================================================

local PhaseOverlay = {}

-- 阶段编号: 5=绘制, 4=材质, 3=锤击, 2=淬火, 1=砥砺, 0=试炼场

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

-- 音频
local audioScene_ = nil
local audioNode_ = nil
local heartbeatSrc_ = nil  -- 预创建心跳音源（复用）
local crackSrc_ = nil       -- 预创建崩裂音源（复用）

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
    -- 预创建音源组件（复用，避免每次播放都 CreateComponent）
    heartbeatSrc_ = audioNode_:CreateComponent("SoundSource")
    heartbeatSrc_.soundType = SOUND_EFFECT
    crackSrc_ = audioNode_:CreateComponent("SoundSource")
    crackSrc_.soundType = SOUND_EFFECT
    currentPhase_ = -1
    active_ = false
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
    heartbeatSrc_ = nil
    crackSrc_ = nil
    if audioScene_ then
        audioScene_:Dispose()
        audioScene_ = nil
        audioNode_ = nil
    end
end

--- 播放崩裂音效（复用预创建的 crackSrc_）
local function PlayCrackSound(phase)
    local path = CRACK_SOUNDS[phase]
    if not path then return end
    if not crackSrc_ then return end

    local sound = cache:GetResource("Sound", path)
    if not sound then return end
    sound.looped = false

    crackSrc_.gain = 0.8
    crackSrc_:Play(sound)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function PhaseOverlay.Start()
    active_ = true
    currentPhase_ = 5
    -- 启动心跳
    heartbeat_.enabled = true
    heartbeat_.timer = 0
    heartbeat_.lastBeat = -10
    heartbeat_.pulse = 0
    heartbeat_.interval = HEARTBEAT_INTERVALS[5] or 1.4
    print("[PhaseOverlay] Started at phase 5")
end

--- 停止并释放所有状态（返回主菜单时调用）
function PhaseOverlay.Stop()
    active_ = false
    currentPhase_ = -1
    transition_.active = false
    transition_.blocking = false
    transition_.timer = 0
    transition_.onDone = nil
    heartbeat_.enabled = false
    heartbeat_.timer = 0
    heartbeat_.pulse = 0
    print("[PhaseOverlay] Stopped and released")
end

function PhaseOverlay.GetPhase()
    return currentPhase_
end

function PhaseOverlay.IsTransitioning()
    return transition_.active and transition_.blocking
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
        transition_.duration = 0.8
        transition_.fadeInTime = 0.2
        transition_.fadeOutTime = 0.2
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
    if heartbeat_.enabled then
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
            -- 播放心跳音效（复用预创建的 heartbeatSrc_）
            if heartbeat_.sound and heartbeatSrc_ then
                -- 越快越响（阶段1最大）
                local gain = 0.25 + (1.4 - heartbeat_.interval) / 1.0 * 0.35
                heartbeatSrc_.gain = math.min(0.6, gain)
                heartbeatSrc_:Play(heartbeat_.sound)
            end
        end
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
        end

        -- 过渡结束
        if transition_.timer >= transition_.duration then
            transition_.active = false
            if transition_.onDone then
                transition_.onDone()
            end
        end
    end
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

    -- ========================================
    -- 黑屏过渡渲染（阻塞式）
    -- ========================================
    if transition_.active and transition_.blocking then
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

        -- 全屏黑色遮罩（纯过渡，文字已合并到 PhaseIntro 中显示）
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, lw, lh)
        nvgFillColor(vg, nvgRGBA(5, 5, 10, math.floor(alpha * 240)))
        nvgFill(vg)
    end
end

return PhaseOverlay
