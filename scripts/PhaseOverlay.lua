-- ============================================================================
-- PhaseOverlay.lua - 阶段倒数 + 黑屏过渡系统
-- 负责：
--   1. 画面左侧阶段倒数数字（5→1），碎裂感随数字递减而增大
--   2. 进入每个环节前的黑屏字幕提示
--   3. 崩裂/破碎音效播放
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
    [5] = nil,                           -- 第5阶不播放（刚开始）
    [4] = "audio/sfx/crack_1.ogg",       -- 进入4时轻微裂
    [3] = "audio/sfx/crack_2.ogg",       -- 进入3时中等裂
    [2] = "audio/sfx/crack_3.ogg",       -- 进入2时重裂
    [1] = "audio/sfx/crack_4.ogg",       -- 进入1时强裂
    [0] = "audio/sfx/shatter_final.ogg", -- 进入试炼时彻底破碎
}

-- ============================================================================
-- 状态
-- ============================================================================
local currentPhase_ = -1           -- 当前倒数阶段 (5~0)
local active_ = false              -- 倒数是否激活

-- 黑屏过渡
local transition_ = {
    active = false,
    blocking = true,              -- 是否阻塞输入（大状态切换=true，内部子阶段=false）
    timer = 0,
    duration = 1.8,               -- 黑屏总时长
    fadeInTime = 0.3,             -- 淡入时间
    fadeOutTime = 0.4,            -- 淡出时间
    phase = 0,                    -- 正在过渡到的阶段
    onDone = nil,                 -- 过渡完成回调
    soundPlayed = false,          -- 是否已播放音效
}

-- 碎片粒子系统（倒数数字破碎时飞出的碎片）
local fragments_ = {}             -- { x, y, vx, vy, rot, rotV, size, alpha, life }
local shatterTriggered_ = false   -- 最终破碎是否已触发

-- 音频
local audioScene_ = nil
local audioNode_ = nil

-- ============================================================================
-- 初始化
-- ============================================================================

function PhaseOverlay.Init()
    audioScene_ = Scene()
    audioNode_ = audioScene_:CreateChild("PhaseOverlaySFX")
    currentPhase_ = -1
    active_ = false
    fragments_ = {}
    shatterTriggered_ = false
end

function PhaseOverlay.Shutdown()
    if audioScene_ then
        audioScene_:Remove()
        audioScene_ = nil
        audioNode_ = nil
    end
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

--- 生成碎片（数字碎裂效果）
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

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 开始倒数（进入第一个环节时调用）
function PhaseOverlay.Start()
    active_ = true
    currentPhase_ = 5
    fragments_ = {}
    shatterTriggered_ = false
    print("[PhaseOverlay] Started at phase 5")
end

--- 获取当前阶段数
function PhaseOverlay.GetPhase()
    return currentPhase_
end

--- 是否正在阻塞式黑屏过渡中（只有大状态切换才阻塞）
function PhaseOverlay.IsTransitioning()
    return transition_.active and transition_.blocking
end

--- 触发阶段过渡（黑屏字幕 → 倒数减一 → 回调）
--- @param targetPhase number 目标阶段数（4,3,2,1,0）
--- @param onDone function|nil 过渡完毕后的回调
--- @param blocking boolean|nil 是否阻塞输入（默认 true）
function PhaseOverlay.TransitionTo(targetPhase, onDone, blocking)
    if blocking == nil then blocking = (onDone ~= nil) end
    transition_.active = true
    transition_.blocking = blocking
    transition_.timer = 0
    transition_.phase = targetPhase
    transition_.onDone = onDone
    transition_.soundPlayed = false
    -- 非阻塞过渡更短（只需触发音效和碎片）
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
    -- 更新碎片
    local i = 1
    while i <= #fragments_ do
        local f = fragments_[i]
        f.life = f.life - dt
        if f.life <= 0 then
            table.remove(fragments_, i)
        else
            f.x = f.x + f.vx * dt
            f.y = f.y + f.vy * dt
            f.vy = f.vy + 200 * dt  -- 重力
            f.rot = f.rot + f.rotV * dt
            f.alpha = math.max(0, f.alpha - 180 * dt)
            i = i + 1
        end
    end
    
    -- 更新黑屏过渡
    if transition_.active then
        transition_.timer = transition_.timer + dt
        
        -- 在黑屏中间点播放音效并切换阶段
        local midPoint = transition_.fadeInTime + 0.2
        if transition_.timer >= midPoint and not transition_.soundPlayed then
            transition_.soundPlayed = true
            currentPhase_ = transition_.phase
            
            -- 播放崩裂音效
            PlayCrackSound(transition_.phase)
            
            -- 生成碎片（越后期越多）
            local dpr = graphics:GetDPR()
            local lw = graphics:GetWidth() / dpr
            local lh = graphics:GetHeight() / dpr
            local cx = 50  -- 倒数数字在左侧
            local cy = lh * 0.5
            local intensity = (5 - transition_.phase) / 4  -- 0→1
            local count = math.floor(8 + intensity * 25)
            
            if transition_.phase == 0 then
                -- 最终破碎：大量碎片
                SpawnFragments(cx, cy, 50, 2.0)
                shatterTriggered_ = true
            else
                SpawnFragments(cx, cy, count, intensity)
            end
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

--- 渲染（在 NanoVG 帧内调用，叠加在场景之上）
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
    -- 1. 渲染左侧倒数数字（带碎裂效果）
    -- ========================================
    if currentPhase_ >= 1 and not shatterTriggered_ then
        local numX = 40
        local numY = lh * 0.5
        local crackLevel = (5 - currentPhase_) / 4  -- 0(阶段5)→1(阶段1)
        
        -- 数字大小：越碎裂越大（紧张感）
        local fontSize = 52 + crackLevel * 16
        
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, fontSize)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        
        -- 绘制裂纹效果（通过多层偏移模拟碎裂）
        if crackLevel > 0 then
            local offsetMax = crackLevel * 4
            -- 裂缝阴影层
            for j = 1, math.floor(crackLevel * 5) do
                local ox = (math.random() - 0.5) * offsetMax * 2
                local oy = (math.random() - 0.5) * offsetMax * 2
                nvgFillColor(vg, nvgRGBA(80, 30, 20, math.floor(30 + crackLevel * 40)))
                nvgText(vg, numX + ox, numY + oy, tostring(currentPhase_), nil)
            end
        end
        
        -- 主数字（逐渐从银白变为炽红）
        local r = math.floor(180 + crackLevel * 75)
        local g = math.floor(190 - crackLevel * 130)
        local b = math.floor(200 - crackLevel * 150)
        nvgFillColor(vg, nvgRGBA(r, g, b, 230))
        nvgText(vg, numX, numY, tostring(currentPhase_), nil)
        
        -- 裂纹线条（NanoVG 路径模拟裂缝）
        if crackLevel > 0.2 then
            local crackCount = math.floor(crackLevel * 6)
            nvgStrokeWidth(vg, 1.5)
            for j = 1, crackCount do
                local startAngle = (j / crackCount) * math.pi * 2
                local length = 8 + crackLevel * 20
                local sx = numX + math.cos(startAngle) * 8
                local sy = numY + math.sin(startAngle) * 8
                local ex = sx + math.cos(startAngle + (math.random() - 0.5) * 0.8) * length
                local ey = sy + math.sin(startAngle + (math.random() - 0.5) * 0.8) * length
                
                nvgBeginPath(vg)
                nvgMoveTo(vg, sx, sy)
                -- 锯齿形裂缝
                local mx = (sx + ex) / 2 + (math.random() - 0.5) * 6
                local my = (sy + ey) / 2 + (math.random() - 0.5) * 6
                nvgLineTo(vg, mx, my)
                nvgLineTo(vg, ex, ey)
                nvgStrokeColor(vg, nvgRGBA(120, 40, 20, math.floor(80 + crackLevel * 120)))
                nvgStroke(vg)
            end
        end
        
        -- "阶段X" 小字标注
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(150, 150, 160, 150))
        nvgText(vg, numX, numY + fontSize / 2 + 6, "阶段", nil)
    end
    
    -- ========================================
    -- 2. 渲染碎片粒子
    -- ========================================
    for _, f in ipairs(fragments_) do
        nvgSave(vg)
        nvgTranslate(vg, f.x, f.y)
        nvgRotate(vg, f.rot)
        nvgBeginPath(vg)
        local hs = f.size / 2
        -- 不规则四边形碎片
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
    -- 3. 黑屏过渡渲染（仅阻塞式过渡显示黑幕）
    -- ========================================
    if transition_.active and transition_.blocking then
        local t = transition_.timer
        local dur = transition_.duration
        local fadeIn = transition_.fadeInTime
        local fadeOut = transition_.fadeOutTime
        
        -- 计算透明度
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
        
        -- 中间文字（只在完全显示阶段绘制）
        if alpha > 0.7 then
            local info = PHASE_INFO[transition_.phase]
            if info then
                local textAlpha = math.floor(math.min(1, (alpha - 0.7) / 0.3) * 255)
                
                -- 阶段标题
                nvgFontFaceId(vg, fontId)
                nvgFontSize(vg, 36)
                nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(vg, nvgRGBA(220, 200, 160, textAlpha))
                nvgText(vg, lw / 2, lh / 2 - 20, info.title, nil)
                
                -- 副标题（说明做什么）
                nvgFontSize(vg, 16)
                nvgFillColor(vg, nvgRGBA(180, 180, 190, math.floor(textAlpha * 0.8)))
                nvgText(vg, lw / 2, lh / 2 + 18, info.subtitle, nil)
            end
        end
    end
end

return PhaseOverlay
