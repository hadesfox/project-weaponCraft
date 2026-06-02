-- ============================================================================
-- States/TrialState.lua - 试炼场（横版）
-- 战斗系统已抽取至 Trial/Combat.lua，末屏已抽取至 Trial/EndScreen.lua
-- 横版动作：左右移动 + 跳跃 + 武器攻击
-- PC: AD/方向键移动, 空格跳跃, 鼠标/J键攻击, Q键变形
-- 移动端: 左侧方向按钮, 右侧跳跃+攻击按钮, 左下变形按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local Video = require("urhox-libs/Video")
local Config = require("Config")
local NVG = require("NVG")
local KeyBindings = require("KeyBindings")
local GameSettings = require("GameSettings")
local Slime = require("Trial.Slime")
local Renderer = require("Trial.Renderer")
local VirtualPad = require("Trial.VirtualPad")
local Combat = require("Trial.Combat")
local EndScreen = require("Trial.EndScreen")

local TrialState = {}

local gameData_ = nil
local onComplete_ = nil

-- 屏幕尺寸（逻辑像素）
local screenW_ = 0
local screenH_ = 0

-- ============================================================================
-- 玩家状态（横版）
-- ============================================================================
local player_ = {
    x = 0, y = 0,
    vx = 0, vy = 0,
    facingRight = true,
    onGround = false,
    width = 32, height = 48,
}

-- 输入状态
local inputLeft_ = false
local inputRight_ = false
local inputDown_ = false
local dropThrough_ = 0  -- 下落穿透计时器（秒），>0 时忽略平台碰撞

-- 虚拟操控（手机端）由 Trial.VirtualPad 模块提供

-- 攻击系统 → Trial/Combat.lua
local attacks_ = {}

-- ============================================================================
-- 变形系统（复合武器）
-- ============================================================================
local isComposite_ = false
local currentForm_ = 1            -- 当前形态 (1 或 2)
local formAttacks_ = { {}, {} }   -- 两种形态的攻击组
local formNames_ = { "", "" }     -- 形态名称
local formStrokes_ = { {}, {} }   -- 两种形态的武器笔画（仅闭合结构）
local transformAnim_ = 0          -- 变形动画计时

-- ============================================================================
-- 武器绘图数据（玩家手绘 → 武器贴图）
-- ============================================================================
local weaponStrokes_ = {}    -- 归一化后的笔画（中心在0,0，缩放到武器尺寸）
local weaponBounds_ = { minX = 0, minY = 0, maxX = 1, maxY = 1 }
local weaponScale_ = 1.0     -- 笔画缩放系数

-- ============================================================================
-- 场景
-- ============================================================================
local groundY_ = 0
local platforms_ = {}
local targets_ = {}
local score_ = 0
local combo_ = 0
local comboTimer_ = 0
local hitEffects_ = {}

-- 木桩（永久靶子）
local dummy_ = nil
local dummyDef_ = nil

-- 木桩攻击/武器碰撞/格挡弹开 → Trial/Combat.lua
local dummyAttacks_ = {}             -- 锻造师专用攻击组（剑）

-- 材质效果系统
local materialEffect_ = nil     -- 当前材质效果ID（字符串）
local materialAtkMod_ = 0       -- 攻击力修正
local materialSpdMod_ = 0       -- 攻速修正
local burnTimer_ = 0            -- 灼烧DOT累计计时
local burnTickInterval_ = 1.0   -- 灼烧每秒一次
local growthBonus_ = 0          -- 成长累计伤害加成

-- 平台/靶子比例定义
local platformDefs_ = {}
local targetDefs_ = {}

-- 物理缩放因子（基于设计高度600px）
local DESIGN_HEIGHT = 600
local physScale_ = 1.0

-- 主角贴图
local playerImage_ = nil       -- 待机帧
local playerRunFrames_ = {}    -- 跑步动画帧数组
local playerFrameIndex_ = 1    -- 当前帧索引
local playerFrameTimer_ = 0    -- 帧切换计时器
local FRAME_DURATION = 0.10    -- 每帧持续时间(秒)

-- UI 引用
local uiRoot_ = nil

-- 敌人贴图
local enemyImage_ = nil
-- 锻造师武器贴图
local dummySwordImage_ = nil

-- ============================================================================
-- 试炼场计时与结算系统
-- ============================================================================
local trialTimer_ = 0              -- 已消耗时间（秒）
local trialTimeLimit_ = 60         -- 时间限制
local trialTotalDamage_ = 0        -- 累计对锻造师造成的伤害
local trialEnded_ = false          -- 试炼是否已结束
local trialEndReason_ = ""         -- 结束原因: "kill" / "timeout"
-- attackHitDummy_ → Combat 模块内部管理

-- 结算 UI → EndScreen 模块管理

-- 内部函数前向声明
local PrepareWeaponStrokes
local SetupTransformSystem
local GetComplementaryType
local DoTransform
local GeneratePlatforms
local RecalcPlatforms
local SpawnTargets
local RecalcTargets
local UpdateInput
local UpdatePlayerPhysics
local DoJump
-- 攻击/碰撞/木桩AI/武器格挡 → Combat.StartAttack / Combat.Update* 等
local UpdateTargets
local UpdateCombo
local UpdateHitEffects
local UpdateTransformAnim
local CheckWaveClear
local UpdateHUD

-- PlayEndVideo / ShowEndScreen / SubmitScore / FetchLeaderboard → EndScreen 模块

--- 进入试炼状态
function TrialState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    
    -- 虚拟操控初始化
    VirtualPad.Init()
    VirtualPad.SetCallbacks({
        onJump = function() DoJump() end,
        onAttack1 = function() Combat.StartAttack(1) end,
        onAttack2 = function() Combat.StartAttack(2) end,
        onDown = function()
            inputDown_ = true
            if player_.onGround then dropThrough_ = 0.2 end
        end,
        onDownRelease = function() inputDown_ = false end,
        onDefaultAttack = function() Combat.StartAttack(1) end,
    })
    
    screenW_ = graphics:GetWidth() / graphics:GetDPR()
    screenH_ = graphics:GetHeight() / graphics:GetDPR()
    
    -- 物理缩放因子：屏幕越大，速度/重力等比增大，保持相对运动感一致
    physScale_ = screenH_ / DESIGN_HEIGHT
    
    -- 地面位置
    groundY_ = screenH_ * Config.Trial.GroundY
    
    -- 初始化玩家（尺寸按比例缩放）
    player_.width = Config.Trial.PlayerWidth * physScale_
    player_.height = Config.Trial.PlayerHeight * physScale_
    player_.x = screenW_ * 0.2
    player_.y = groundY_ - player_.height
    player_.vx = 0
    player_.vy = 0
    player_.onGround = true
    player_.facingRight = true
    -- 程序化动画状态
    player_.animTime = 0         -- 动画累计时间
    player_.state = "idle"       -- idle / run / jump / fall
    player_.landSquash = 0       -- 着地压缩动画计时器
    player_.prevOnGround = true  -- 上一帧是否着地（用于检测落地瞬间）
    player_.hp = Config.Combat.DummyHP       -- 玩家血量（与木桩相同，近乎无限）
    player_.maxHp = Config.Combat.DummyHP
    player_.hitAnim = 0          -- 受击闪烁动画
    
    -- 处理武器绘图数据（归一化笔画）
    PrepareWeaponStrokes()
    
    -- 初始化变形系统
    SetupTransformSystem()
    
    -- 初始化材质效果
    local mat = gameData_ and gameData_.material or nil
    materialEffect_ = mat and mat.effect or nil
    materialAtkMod_ = mat and mat.atkMod or 0
    materialSpdMod_ = mat and mat.spdMod or 0
    burnTimer_ = 0
    growthBonus_ = 0
    
    -- 初始化分数
    score_ = 0
    combo_ = 0
    comboTimer_ = 0
    hitEffects_ = {}
    
    -- 初始化试炼计时系统
    trialTimer_ = 0
    trialTimeLimit_ = GameSettings.GetTrialTime()
    trialTotalDamage_ = 0
    trialEnded_ = false
    trialEndReason_ = ""
    EndScreen.Init({
        getTrialTimer = function() return trialTimer_ end,
        getTotalDamage = function() return trialTotalDamage_ end,
        getEndReason = function() return trialEndReason_ end,
        getCombo = function() return combo_ end,
        getUIRoot = function() return uiRoot_ end,
        setUIRoot = function(root) uiRoot_ = root end,
        onComplete = function() if onComplete_ then onComplete_() end end,
    })
    
    -- 输入重置
    inputLeft_ = false
    inputRight_ = false
    inputDown_ = false
    dropThrough_ = 0
    
    -- 预加载渲染器 NanoVG 图片句柄
    Renderer.Preload(NVG.Get())
    
    -- 加载主角贴图（待机帧）
    playerImage_ = nvgCreateImage(NVG.Get(), Config.Trial.PlayerImage, 0)
    -- 加载跑步动画帧（4帧完整循环：右腿前→过渡→左腿前→过渡）
    local runFramePaths = Config.Trial.RunFrames
    playerRunFrames_ = {}
    for i = 1, #runFramePaths do
        playerRunFrames_[i] = nvgCreateImage(NVG.Get(), runFramePaths[i], 0)
    end
    -- 加载敌人贴图
    enemyImage_ = nvgCreateImage(NVG.Get(), Config.Trial.EnemyImage, 0)
    -- 加载锻造师武器贴图
    dummySwordImage_ = nvgCreateImage(NVG.Get(), Config.Trial.DummySwordImage, 0)
    playerFrameIndex_ = 1
    playerFrameTimer_ = 0
    
    -- 生成平台和靶子
    GeneratePlatforms()
    SpawnTargets()
    
    -- 初始化史莱姆
    Slime.Init(screenW_, screenH_, groundY_, physScale_)
    
    -- 初始化战斗系统（攻击、木桩AI、武器碰撞）
    dummyAttacks_ = Config.Attacks.SWORD
    Combat.Init({
        player = player_,
        dummy = dummy_,
        targets = targets_,
        hitEffects = hitEffects_,
        getCombo = function() return combo_ end,
        setCombo = function(v) combo_ = v; comboTimer_ = 0 end,
        getScore = function() return score_ end,
        setScore = function(v) score_ = v end,
        getPhysScale = function() return physScale_ end,
        getScreenW = function() return screenW_ end,
        getGameData = function() return gameData_ end,
        getMaterialEffect = function() return materialEffect_ end,
        getMaterialAtkMod = function() return materialAtkMod_ end,
        getMaterialSpdMod = function() return materialSpdMod_ end,
        getGrowthBonus = function() return growthBonus_ end,
        setGrowthBonus = function(v) growthBonus_ = v end,
        getTotalDamage = function() return trialTotalDamage_ end,
        setTotalDamage = function(v) trialTotalDamage_ = v end,
        getAttacks = function() return attacks_ end,
        getDummyAttacks = function() return dummyAttacks_ end,
        isTrialEnded = function() return trialEnded_ end,
    })
    
    local weaponType = gameData_.weaponData and gameData_.weaponData.type or "UNKNOWN"
    print("[TrialState] Entered. Weapon: " .. weaponType .. " Composite: " .. tostring(isComposite_))
end

--- 归一化一组笔画（以它们自身的包围盒为中心，缩放到 targetSize）
--- @param strokes table[] 原始笔画
--- @param targetSize number 目标尺寸
--- @return table[] 归一化后的笔画, number 缩放系数
local function NormalizeStrokesToCenter(strokes, targetSize)
    if not strokes or #strokes == 0 then return {}, 1.0 end
    
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    for i = 1, #strokes do
        local pts = strokes[i].points
        for j = 1, #pts do
            minX = math.min(minX, pts[j].x)
            minY = math.min(minY, pts[j].y)
            maxX = math.max(maxX, pts[j].x)
            maxY = math.max(maxY, pts[j].y)
        end
    end
    local bw = math.max(1, maxX - minX)
    local bh = math.max(1, maxY - minY)
    local cx = (minX + maxX) / 2
    local cy = (minY + maxY) / 2
    local scale = targetSize / math.max(bw, bh)
    
    local result = {}
    for i = 1, #strokes do
        local src = strokes[i]
        local normalizedPts = {}
        for j = 1, #src.points do
            normalizedPts[j] = {
                x = (src.points[j].x - cx) * scale,
                y = (src.points[j].y - cy) * scale,
            }
        end
        result[i] = { points = normalizedPts, closed = src.closed }
    end
    return result, scale
end

--- 准备武器笔画（归一化到以原点为中心的坐标）
--- 复合武器时，将闭合结构分离到两个形态
PrepareWeaponStrokes = function()
    weaponStrokes_ = {}
    formStrokes_ = { {}, {} }
    
    local strokes = gameData_.strokes
    if not strokes or #strokes == 0 then return end
    
    local isComp = gameData_.weaponData and gameData_.weaponData.isComposite or false
    
    if isComp then
        -- 复合武器：将闭合结构分配到两个形态
        local closedStrokes = {}
        for i = 1, #strokes do
            if strokes[i].closed then
                closedStrokes[#closedStrokes + 1] = strokes[i]
            end
        end
        
        if #closedStrokes >= 2 then
            -- 分配：第一个闭合结构 → 形态1，第二个 → 形态2
            -- 如果超过2个，交替分配
            local group1 = {}
            local group2 = {}
            for i = 1, #closedStrokes do
                if i % 2 == 1 then
                    group1[#group1 + 1] = closedStrokes[i]
                else
                    group2[#group2 + 1] = closedStrokes[i]
                end
            end
            
            local targetSize = 60
            formStrokes_[1] = NormalizeStrokesToCenter(group1, targetSize)
            formStrokes_[2] = NormalizeStrokesToCenter(group2, targetSize)
            
            -- 默认显示形态1
            weaponStrokes_ = formStrokes_[1]
            weaponScale_ = targetSize / 60  -- 归一化后的比例
        else
            -- 只有1个闭合结构：整体作为统一笔画（退化为普通武器渲染）
            local allNorm, scale = NormalizeStrokesToCenter(strokes, 60)
            weaponStrokes_ = allNorm
            weaponScale_ = scale
            formStrokes_[1] = allNorm
            formStrokes_[2] = allNorm
        end
    else
        -- 非复合武器：所有笔画统一归一化
        local allNorm, scale = NormalizeStrokesToCenter(strokes, 60)
        weaponStrokes_ = allNorm
        weaponScale_ = scale
        formStrokes_[1] = allNorm
        formStrokes_[2] = allNorm
    end
    
    -- 计算整体包围盒（用于其他用途）
    local allMinX, allMinY = math.huge, math.huge
    local allMaxX, allMaxY = -math.huge, -math.huge
    for i = 1, #strokes do
        local pts = strokes[i].points
        for j = 1, #pts do
            allMinX = math.min(allMinX, pts[j].x)
            allMinY = math.min(allMinY, pts[j].y)
            allMaxX = math.max(allMaxX, pts[j].x)
            allMaxY = math.max(allMaxY, pts[j].y)
        end
    end
    weaponBounds_ = { minX = allMinX, minY = allMinY, maxX = allMaxX, maxY = allMaxY }
    
    print("[TrialState] Weapon strokes: " .. #weaponStrokes_ .. " | Composite forms: " .. #formStrokes_[1] .. " / " .. #formStrokes_[2])
end

--- 设置变形系统
SetupTransformSystem = function()
    local weaponType = gameData_.weaponData and gameData_.weaponData.type or "UNKNOWN"
    isComposite_ = gameData_.weaponData and gameData_.weaponData.isComposite or false
    currentForm_ = 1
    transformAnim_ = 0
    
    if isComposite_ then
        -- 变形武器：使用独立分类的两种子武器类型
        local type1 = gameData_.weaponData.form1Type or weaponType
        local type2 = gameData_.weaponData.form2Type or GetComplementaryType(weaponType)
        
        -- 形态一
        formAttacks_[1] = Config.Attacks[type1] or Config.Attacks.UNKNOWN
        formNames_[1] = (Config.WeaponTypes[type1] or Config.WeaponTypes.UNKNOWN).name
        
        -- 形态二
        formAttacks_[2] = Config.Attacks[type2] or Config.Attacks.UNKNOWN
        formNames_[2] = (Config.WeaponTypes[type2] or Config.WeaponTypes.UNKNOWN).name
        
        -- 默认使用形态一
        attacks_ = formAttacks_[1]
        
        print("[TrialState] Composite! Form1: " .. type1 .. " (" .. formNames_[1] .. ") Form2: " .. type2 .. " (" .. formNames_[2] .. ")")
    else
        -- 非复合：只有一种攻击组
        attacks_ = Config.Attacks[weaponType] or Config.Attacks.UNKNOWN
        formAttacks_[1] = attacks_
        formNames_[1] = (Config.WeaponTypes[weaponType] or Config.WeaponTypes.UNKNOWN).name
    end
    
    Combat.StopAttack()
end

--- 根据主武器类型获取互补类型
GetComplementaryType = function(primary)
    local mapping = {
        SWORD = "SHIELD",
        AXE = "HOOK",
        SPEAR = "SWORD",
        SHIELD = "SPEAR",
        HOOK = "AXE",
        UNKNOWN = "SWORD",
    }
    return mapping[primary] or "SWORD"
end

--- 执行变形
DoTransform = function()
    if not isComposite_ then return end
    if Combat.IsAttacking() then return end  -- 攻击中不可变形
    
    -- 切换形态
    currentForm_ = currentForm_ == 1 and 2 or 1
    attacks_ = formAttacks_[currentForm_]
    Combat.SyncAttacks()
    transformAnim_ = 1.0  -- 触发变形动画
    
    -- 切换武器图案（核心：使用对应形态的闭合结构笔画）
    weaponStrokes_ = formStrokes_[currentForm_]
    
    -- 更新 HUD
    local formLabel = uiRoot_ and uiRoot_:FindById("trialFormLabel")
    if formLabel then
        formLabel:SetText("形态: " .. formNames_[currentForm_])
    end
    
    print("[TrialState] Transform! Now form " .. currentForm_ .. ": " .. formNames_[currentForm_] .. " | Strokes: " .. #weaponStrokes_)
end

--- 离开试炼状态
function TrialState.Leave()
    -- ① 释放 GPU 纹理
    if playerImage_ and playerImage_ ~= 0 then
        nvgDeleteImage(NVG.Get(), playerImage_)
        playerImage_ = nil
    end
    if enemyImage_ and enemyImage_ ~= 0 then
        nvgDeleteImage(NVG.Get(), enemyImage_)
        enemyImage_ = nil
    end
    if dummySwordImage_ and dummySwordImage_ ~= 0 then
        nvgDeleteImage(NVG.Get(), dummySwordImage_)
        dummySwordImage_ = nil
    end
    for i = 1, #playerRunFrames_ do
        if playerRunFrames_[i] and playerRunFrames_[i] ~= 0 then
            nvgDeleteImage(NVG.Get(), playerRunFrames_[i])
        end
    end
    playerRunFrames_ = {}

    -- ② 释放子模块资源
    Slime.Shutdown()
    Renderer.ReleaseImages(NVG.Get())

    -- ③ 清空大型游戏数据表
    targets_ = {}
    platforms_ = {}
    platformDefs_ = {}
    targetDefs_ = {}
    attacks_ = {}
    hitEffects_ = {}
    weaponStrokes_ = {}
    formAttacks_ = { {}, {} }
    formStrokes_ = { {}, {} }
    dummyAttacks_ = {}

    -- ④ 释放视频播放器 + 结算画面
    EndScreen.Reset()

    -- ⑤ 重置状态标志
    trialEnded_ = false
    dummy_ = nil
    dummyDef_ = nil
    materialEffect_ = nil
    uiRoot_ = nil
    gameData_ = nil
    onComplete_ = nil
end

--- 生成平台（多层复杂布局）
GeneratePlatforms = function()
    -- 平台使用比例坐标存储，渲染/物理时实时计算实际位置
    -- rx: X占屏幕宽比例, ry: Y相对地面的比例(0=地面, 1=屏幕顶部), rw: 宽度占屏幕宽比例
    platformDefs_ = {}
    
    -- 第一层：地面上方低矮平台（左中右）
    platformDefs_[#platformDefs_ + 1] = { rx = 0.05, ry = 0.12, rw = 0.10 }
    platformDefs_[#platformDefs_ + 1] = { rx = 0.42, ry = 0.14, rw = 0.08 }
    platformDefs_[#platformDefs_ + 1] = { rx = 0.75, ry = 0.11, rw = 0.10 }
    
    -- 第二层：中间高度平台（错开分布）
    platformDefs_[#platformDefs_ + 1] = { rx = 0.15, ry = 0.25, rw = 0.11 }
    platformDefs_[#platformDefs_ + 1] = { rx = 0.55, ry = 0.28, rw = 0.09 }
    platformDefs_[#platformDefs_ + 1] = { rx = 0.82, ry = 0.23, rw = 0.07 }
    
    -- 第三层：高处小平台（跳跃挑战）
    platformDefs_[#platformDefs_ + 1] = { rx = 0.30, ry = 0.38, rw = 0.07 }
    platformDefs_[#platformDefs_ + 1] = { rx = 0.65, ry = 0.40, rw = 0.07 }
    
    -- 初始化木桩比例（基础宽高在 RecalcPlatforms 中按 physScale_ 缩放）
    dummyDef_ = { rx = 0.50, baseW = 20, baseH = 60 }
    
    -- 立即计算一次实际坐标
    RecalcPlatforms()
end

--- 根据当前屏幕尺寸重算平台、木桩实际坐标
RecalcPlatforms = function()
    platforms_ = {}
    local ph = Config.Trial.PlatformHeight
    local arenaH = groundY_  -- 地面以上的可用高度
    
    for i = 1, #platformDefs_ do
        local def = platformDefs_[i]
        platforms_[i] = {
            x = screenW_ * def.rx,
            y = groundY_ - arenaH * def.ry,
            w = screenW_ * def.rw,
            h = ph,
        }
    end
    
    -- 木桩（尺寸按 physScale_ 缩放，保留移动后的位置）
    dummy_ = {
        x = dummy_ and dummy_.x or screenW_ * dummyDef_.rx,
        y = groundY_,
        width = dummyDef_.baseW * physScale_,
        height = dummyDef_.baseH * physScale_,
        hitAnim = dummy_ and dummy_.hitAnim or 0,
        hitDir = dummy_ and dummy_.hitDir or 0,
        hp = dummy_ and dummy_.hp or Config.Combat.DummyHP,
        maxHp = Config.Combat.DummyHP,
        alive = dummy_ and dummy_.alive ~= false,
    }
end

--- 生成靶子（使用比例坐标）
SpawnTargets = function()
    targets_ = {}
    targetDefs_ = {}
    local arenaH = groundY_

    -- 随机选择不重复的平台索引，让敌人只刷新在平台上
    local platIndices = {}
    for i = 1, #platformDefs_ do
        platIndices[#platIndices + 1] = i
    end
    -- Fisher-Yates 洗牌
    for i = #platIndices, 2, -1 do
        local j = math.random(1, i)
        platIndices[i], platIndices[j] = platIndices[j], platIndices[i]
    end

    for i = 1, Config.Trial.TargetCount do
        local baseSize = Config.Trial.TargetMinSize + math.random() * (Config.Trial.TargetMaxSize - Config.Trial.TargetMinSize)
        local size = baseSize * physScale_

        -- 所有敌人都放在平台上
        local platIdx = platIndices[((i - 1) % #platIndices) + 1]
        local pdef = platformDefs_[platIdx]
        local rx = pdef.rx + pdef.rw / 2 + (math.random() - 0.5) * 0.04
        local ry = pdef.ry + size / arenaH + 0.01
        local platformRy = pdef.ry

        targetDefs_[i] = { rx = rx, ry = ry, baseSize = baseSize, isGround = false, platformRy = platformRy }
        local ty = groundY_ - arenaH * ry
        targets_[i] = {
            x = screenW_ * rx,
            y = ty,
            size = size,
            hitRadius = size / 2,
            alive = true,
            hp = Config.Combat.BaseHP,
            maxHp = Config.Combat.BaseHP,
            hitAnim = 0,
            spawnAnim = 1.0,
            knockX = 0, knockY = 0,
        }
    end
end

--- 根据屏幕尺寸重算靶子位置和大小
RecalcTargets = function()
    if not targetDefs_ then return end
    local arenaH = groundY_
    for i = 1, #targetDefs_ do
        if targets_[i] then
            local def = targetDefs_[i]
            local size = def.baseSize * physScale_
            local ty = groundY_ - arenaH * def.ry
            targets_[i].x = screenW_ * def.rx
            targets_[i].y = ty
            targets_[i].size = size
            targets_[i].hitRadius = size / 2
        end
    end
end

--- 构建试炼 UI
function TrialState.BuildUI()
    local wd = gameData_.weaponData
    
    -- 变形按钮（仅复合武器显示）
    local transformChildren = {}
    if wd and wd.isComposite then
        transformChildren = {
            UI.Panel {
                flexDirection = "row", gap = 6, alignItems = "center",
                children = {
                    UI.Label {
                        id = "trialFormLabel",
                        text = "形态: " .. formNames_[1],
                        fontSize = 11,
                        fontColor = Config.Colors.Gold,
                    },
                },
            },
            UI.Button {
                id = "transformBtn",
                text = "🔄 变形 (Q)",
                size = "small",
                variant = "outline",
                onClick = function()
                    DoTransform()
                end,
            },
        }
    end
    
    uiRoot_ = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 顶部 HUD
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                padding = 10,
                backgroundColor = { 20, 22, 30, 200 },
                children = {
                    UI.Panel {
                        gap = 2,
                        children = {
                            UI.Label {
                                id = "trialWeaponLabel",
                                text = wd and (wd.typeInfo.icon .. " " .. wd.name) or "未知武器",
                                fontSize = 13,
                                fontColor = Config.Colors.TextLight,
                            },
                            UI.Label {
                                id = "trialAttackLabel",
                                text = "招式: " .. (attacks_[1] and attacks_[1].name or "-"),
                                fontSize = 10,
                                fontColor = { 160, 200, 255, 200 },
                            },
                        },
                    },
                    -- 中间：倒计时 + 伤害
                    UI.Panel {
                        flexDirection = "row", gap = 10,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "trialTimerLabel",
                                text = string.format("%02d", trialTimeLimit_),
                                fontSize = 20,
                                fontColor = Config.Colors.TextLight,
                            },
                            UI.Label {
                                id = "trialDmgLabel",
                                text = "伤害:0",
                                fontSize = 12,
                                fontColor = { 255, 180, 100, 220 },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                id = "trialComboLabel",
                                text = "",
                                fontSize = 13,
                                fontColor = Config.Colors.Secondary,
                            },
                            UI.Label {
                                id = "trialScoreLabel",
                                text = "0",
                                fontSize = 18,
                                fontColor = Config.Colors.Gold,
                            },
                        },
                    },
                },
            },
            -- 游戏区域（NanoVG渲染，穿透点击）
            UI.Panel {
                width = "100%", flexGrow = 1,
                pointerEvents = "none",
            },
            -- 底部控制栏
            UI.Panel {
                width = "100%",
                padding = 8,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                backgroundColor = { 20, 22, 30, 200 },
                children = {
                    -- 左下：变形按钮区域
                    UI.Panel {
                        gap = 4,
                        children = transformChildren,
                    },
                    -- 中间：操作提示
                    UI.Label {
                        text = isComposite_ and "AD移动|空格跳|左键攻击1|右键攻击2|Q变形" or "AD移动|空格跳|左键攻击1|右键攻击2",
                        fontSize = 9,
                        fontColor = { 140, 140, 160, 160 },
                    },
                    -- 右下：返回按钮
                    UI.Button {
                        text = "返回",
                        size = "small",
                        variant = "outline",
                        onClick = function()
                            if onComplete_ then onComplete_() end
                        end,
                    },
                },
            },
        },
    }
    return uiRoot_
end

-- ============================================================================
-- 更新
-- ============================================================================

function TrialState.Update(dt)
    -- 试炼已结束，只更新特效动画
    if trialEnded_ then
        UpdateHitEffects(dt)
        UpdateHUD()
        return
    end
    
    -- 更新倒计时
    trialTimer_ = trialTimer_ + dt
    if trialTimer_ >= trialTimeLimit_ then
        trialTimer_ = trialTimeLimit_
        trialEnded_ = true
        trialEndReason_ = "timeout"
        Combat.StopAttack()
        EndScreen.PlayEndVideo()
        return
    end
    
    -- 检测玩家血量归零（被锻造师击败）
    if player_.hp <= 0 and not trialEnded_ then
        trialEnded_ = true
        trialEndReason_ = "defeated"
        Combat.StopAttack()
        EndScreen.PlayEndVideo()
        return
    end
    
    UpdateInput()
    UpdatePlayerPhysics(dt)
    Combat.UpdateAttack(dt)
    UpdateTargets(dt)
    Combat.UpdateDummyAttack(dt)
    Combat.UpdateDummyWeapon(dt)
    Combat.UpdateWeaponClash(dt)
    Slime.Update(dt, player_)
    UpdateCombo(dt)
    UpdateHitEffects(dt)
    UpdateTransformAnim(dt)
    CheckWaveClear()
    
    -- 材质效果：burn（灼烧）- 对木桩造成每秒2%最大HP真伤
    if materialEffect_ == "burn" and dummy_ and dummy_.alive then
        burnTimer_ = burnTimer_ + dt
        if burnTimer_ >= burnTickInterval_ then
            burnTimer_ = burnTimer_ - burnTickInterval_
            local burnDmg = math.floor(Config.Combat.DummyHP * 0.02)
            dummy_.hp = math.max(0, dummy_.hp - burnDmg)
            dummy_.hitAnim = 0.3
            trialTotalDamage_ = trialTotalDamage_ + burnDmg
            hitEffects_[#hitEffects_ + 1] = {
                x = dummy_.x + math.random(-10, 10),
                y = dummy_.y - (dummy_.height or 60) * 0.5,
                text = "灼烧-" .. burnDmg,
                timer = 0.9,
                color = { 100, 255, 80 },
            }
            if dummy_.hp <= 0 then
                dummy_.alive = false
                dummy_.hp = 0
            end
        end
    end
    
    -- 检测锻造师血量归零
    if dummy_ and dummy_.hp <= 0 and not trialEnded_ then
        trialEnded_ = true
        trialEndReason_ = "kill"
        Combat.StopAttack()
        EndScreen.PlayEndVideo()
        return
    end
    
    UpdateHUD()
end

--- 读取输入状态
UpdateInput = function()
    if VirtualPad.IsActive() then
        local deadZone = 0.2
        inputLeft_ = VirtualPad.GetDirX() < -deadZone
        inputRight_ = VirtualPad.GetDirX() > deadZone
        -- inputDown_ 由 VirtualPad 回调驱动
        return
    end
    inputLeft_ = KeyBindings.IsDown("move_left")
    inputRight_ = KeyBindings.IsDown("move_right")
    inputDown_ = KeyBindings.IsDown("move_down")
end

--- 玩家物理（横版重力）
UpdatePlayerPhysics = function(dt)
    local speed = Config.Trial.MoveSpeed * physScale_
    -- agile 效果：攻击时移速不减；否则攻击时清零
    if Combat.IsAttacking() and materialEffect_ ~= "agile" then
        speed = 0
    end
    
    if inputLeft_ then
        player_.vx = -speed
        if not Combat.IsAttacking() then player_.facingRight = false end
    elseif inputRight_ then
        player_.vx = speed
        if not Combat.IsAttacking() then player_.facingRight = true end
    else
        player_.vx = 0
    end
    
    if not player_.onGround then
        player_.vy = player_.vy + Config.Trial.Gravity * physScale_ * dt
        if player_.vy > Config.Trial.MaxFallSpeed * physScale_ then
            player_.vy = Config.Trial.MaxFallSpeed * physScale_
        end
    end
    
    player_.x = player_.x + player_.vx * dt
    player_.y = player_.y + player_.vy * dt
    
    -- 地面碰撞
    player_.onGround = false
    if player_.y + player_.height >= groundY_ then
        player_.y = groundY_ - player_.height
        player_.vy = 0
        player_.onGround = true
    end
    
    -- 下落穿透计时器递减
    if dropThrough_ > 0 then
        dropThrough_ = dropThrough_ - dt
    end
    
    -- 平台碰撞（仅下落时或静止站立时，穿透期间跳过）
    if player_.vy >= 0 and dropThrough_ <= 0 then
        for i = 1, #platforms_ do
            local p = platforms_[i]
            local playerBottom = player_.y + player_.height
            local prevBottom = playerBottom - player_.vy * dt
            if player_.x + player_.width > p.x and player_.x < p.x + p.w then
                -- 使用容差 -1 避免浮点精度导致的振动
                -- (snap 后 p.y - height + height 可能不精确等于 p.y)
                if prevBottom <= p.y + 2 and playerBottom >= p.y - 1 then
                    player_.y = p.y - player_.height
                    player_.vy = 0
                    player_.onGround = true
                    break
                end
            end
        end
    end
    
    player_.x = math.max(0, math.min(screenW_ - player_.width, player_.x))
    
    -- 更新动画状态
    local wasOnGround = player_.prevOnGround
    player_.prevOnGround = player_.onGround
    
    -- 检测刚落地 → 触发着地压缩回弹
    if player_.onGround and not wasOnGround then
        player_.landSquash = 0.15  -- 压缩回弹总时长(秒)
    end
    
    -- 更新着地压缩计时
    if player_.landSquash > 0 then
        player_.landSquash = player_.landSquash - dt
        if player_.landSquash < 0 then player_.landSquash = 0 end
    end
    
    -- 更新受击闪烁
    if player_.hitAnim > 0 then
        player_.hitAnim = player_.hitAnim - dt * 2
        if player_.hitAnim < 0 then player_.hitAnim = 0 end
    end
    
    -- 确定动画状态
    if not player_.onGround then
        if player_.vy < 0 then
            player_.state = "jump"
        else
            player_.state = "fall"
        end
    elseif math.abs(player_.vx) > 0.1 then
        player_.state = "run"
    else
        player_.state = "idle"
    end
    
    -- 动画时间累计（跑步时按速度推进）
    if player_.state == "run" then
        player_.animTime = player_.animTime + dt * 12  -- 跑步频率
        -- 帧动画切换
        playerFrameTimer_ = playerFrameTimer_ + dt
        if playerFrameTimer_ >= FRAME_DURATION then
            playerFrameTimer_ = playerFrameTimer_ - FRAME_DURATION
            playerFrameIndex_ = playerFrameIndex_ + 1
            if playerFrameIndex_ > #playerRunFrames_ then
                playerFrameIndex_ = 1
            end
        end
    elseif player_.state == "idle" then
        player_.animTime = player_.animTime + dt * 2   -- 待机呼吸频率
        -- 回到待机帧
        playerFrameIndex_ = 1
        playerFrameTimer_ = 0
    else
        -- 跳跃/下落时保持当前帧不切换
        playerFrameTimer_ = 0
    end
end

--- 跳跃（按住下键时从平台下落穿透）
DoJump = function()
    if player_.onGround then
        if inputDown_ and (player_.y + player_.height < groundY_ - 1) then
            -- 站在平台上且按住下键 → 下落穿透
            player_.y = player_.y + 2  -- 轻微下移脱离平台表面
            player_.vy = 50 * physScale_  -- 给一个小的向下初速度
            player_.onGround = false
            dropThrough_ = 0.15  -- 150ms 内忽略平台碰撞
        else
            -- 正常跳跃
            player_.vy = Config.Trial.JumpVelocity * physScale_
            player_.onGround = false
            player_.landSquash = 0  -- 跳跃时立刻取消着地动画
        end
    end
end

--- 靶子动画更新
UpdateTargets = function(dt)
    for i = 1, #targets_ do
        local t = targets_[i]
        if t.spawnAnim > 0 then
            t.spawnAnim = math.max(0, t.spawnAnim - dt * 3)
        end
        if t.hitAnim > 0 then
            t.hitAnim = t.hitAnim - dt * 2.5
            t.knockX = t.knockX * 0.92
            t.knockY = t.knockY + dt * 200
        end
    end
    -- 木桩受击动画衰减
    if dummy_ and dummy_.hitAnim > 0 then
        dummy_.hitAnim = dummy_.hitAnim - dt * 3
    end
end

--- 连击衰减
UpdateCombo = function(dt)
    if combo_ > 0 then
        comboTimer_ = comboTimer_ + dt
        if comboTimer_ >= Config.Trial.ComboDecayTime then
            combo_ = 0
            comboTimer_ = 0
        end
    end
end

--- 命中特效更新
UpdateHitEffects = function(dt)
    local i = 1
    while i <= #hitEffects_ do
        hitEffects_[i].timer = hitEffects_[i].timer - dt
        hitEffects_[i].y = hitEffects_[i].y - dt * 50
        if hitEffects_[i].timer <= 0 then
            table.remove(hitEffects_, i)
        else
            i = i + 1
        end
    end
end

--- 变形动画更新
UpdateTransformAnim = function(dt)
    if transformAnim_ > 0 then
        transformAnim_ = math.max(0, transformAnim_ - dt * 3)
    end
end

--- 检查波次清场
CheckWaveClear = function()
    for i = 1, #targets_ do
        if targets_[i].alive then return end
    end
    score_ = score_ + Config.Trial.ClearBonus
    hitEffects_[#hitEffects_ + 1] = {
        x = screenW_ / 2, y = screenH_ * 0.4,
        text = "全灭! +" .. Config.Trial.ClearBonus,
        timer = 1.5,
        color = Config.Colors.Gold,
    }
    SpawnTargets()
end

--- 更新 HUD 标签
UpdateHUD = function()
    if not uiRoot_ then return end
    
    local scoreLabel = uiRoot_:FindById("trialScoreLabel")
    if scoreLabel then scoreLabel:SetText(tostring(score_)) end
    
    local comboLabel = uiRoot_:FindById("trialComboLabel")
    if comboLabel then
        comboLabel:SetText(combo_ >= 2 and (combo_ .. "x") or "")
    end
    
    local attackLabel = uiRoot_:FindById("trialAttackLabel")
    local curAtk = Combat.GetCurrentAttack()
    if attackLabel and curAtk then
        attackLabel:SetText("招式: " .. curAtk.name)
    end
    
    -- 倒计时
    local timerLabel = uiRoot_:FindById("trialTimerLabel")
    if timerLabel then
        local remaining = math.max(0, math.ceil(trialTimeLimit_ - trialTimer_))
        timerLabel:SetText(string.format("%02d", remaining))
        if remaining <= 10 then
            timerLabel:SetFontColor({ 240, 80, 80, 255 })
        end
    end
    
    -- 累计伤害
    local dmgLabel = uiRoot_:FindById("trialDmgLabel")
    if dmgLabel then
        dmgLabel:SetText("伤害:" .. trialTotalDamage_)
    end
end

-- ============================================================================
-- 输入事件
-- ============================================================================

function TrialState.OnKeyDown(key)
    if KeyBindings.IsKey("jump", key) then
        DoJump()
    elseif KeyBindings.IsKey("attack1", key) then
        Combat.StartAttack(1)
    elseif KeyBindings.IsKey("attack2", key) then
        Combat.StartAttack(2)
    elseif KeyBindings.IsKey("transform", key) then
        DoTransform()
    end
end

function TrialState.OnMouseDown(button)
    if trialEnded_ then return end
    if button == MOUSEB_LEFT then
        Combat.StartAttack(1)  -- 左键 = 招式1
    elseif button == MOUSEB_RIGHT then
        Combat.StartAttack(2)  -- 右键 = 招式2
    end
end

function TrialState.OnMouseUp(button)
end

function TrialState.OnMouseMove()
end

-- 触摸事件委托给 VirtualPad 模块
function TrialState.OnTouchBegin(x, y, touchID)
    if trialEnded_ then return end
    VirtualPad.OnTouchBegin(x, y, touchID)
end

function TrialState.OnTouchMove(x, y, touchID)
    if trialEnded_ then return end
    VirtualPad.OnTouchMove(x, y, touchID)
end

function TrialState.OnTouchEnd(x, y, touchID)
    if trialEnded_ then return end
    VirtualPad.OnTouchEnd(x, y, touchID)
end

-- ============================================================================
-- NanoVG 渲染（委托给 Trial.Renderer 模块）
-- ============================================================================

function TrialState.Render(vg)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    
    local prevW = screenW_
    local prevH = screenH_
    screenW_ = w / dpr
    screenH_ = h / dpr
    groundY_ = screenH_ * Config.Trial.GroundY
    
    -- 屏幕尺寸变化时重算平台和靶子位置
    if prevW ~= screenW_ or prevH ~= screenH_ then
        physScale_ = screenH_ / DESIGN_HEIGHT
        if platformDefs_ then
            RecalcPlatforms()
            RecalcTargets()
            -- 玩家尺寸和位置按比例适配
            player_.width = Config.Trial.PlayerWidth * physScale_
            player_.height = Config.Trial.PlayerHeight * physScale_
            if prevW > 0 and prevH > 0 then
                player_.x = player_.x * (screenW_ / prevW)
                player_.y = player_.y * (screenH_ / prevH)
            end
            -- 确保不穿出地面
            if player_.y + player_.height > groundY_ then
                player_.y = groundY_ - player_.height
            end
            -- 史莱姆适配
            Slime.OnResize(screenW_, screenH_, groundY_, physScale_)
        end
    end
    
    -- 组装渲染状态表
    local S = {
        screenW = screenW_,
        screenH = screenH_,
        groundY = groundY_,
        physScale = physScale_,
        player = player_,
        platforms = platforms_,
        targets = targets_,
        dummy = dummy_,
        dummyWeapon = Combat.GetDummyWeapon(),
        dummyAttacking = Combat.IsDummyAttacking(),
        dummyCurrentAttack = Combat.GetDummyCurrentAttack(),
        dummyAttackProgress = Combat.GetDummyAttackProgress(),
        dummyFacingRight = Combat.IsDummyFacingRight(),
        dummyMoving = Combat.IsDummyMoving(),
        attacking = Combat.IsAttacking(),
        currentAttack = Combat.GetCurrentAttack(),
        attackTimer = Combat.GetAttackTimer(),
        attackDuration = Combat.GetAttackDuration(),
        weaponStrokes = weaponStrokes_,
        hitEffects = hitEffects_,
        combo = combo_,
        comboTimer = comboTimer_,
        transformAnim = transformAnim_,
        formNames = formNames_,
        currentForm = currentForm_,
        gameData = gameData_,
        enemyImage = enemyImage_,
        dummySwordImage = dummySwordImage_,
        targetDefs = targetDefs_,
        playerImage = playerImage_,
        playerRunFrames = playerRunFrames_,
        playerFrameIndex = playerFrameIndex_,
        weaponClashAnim = Combat.GetWeaponClashAnim(),
        weaponClashX = 0, -- filled below
        weaponClashY = 0,
        -- 弹开状态
        deflecting = Combat.IsDeflecting(),
        deflectTimer = 0,
        deflectDuration = 0.3,
        deflectStartX = 0, deflectStartY = 0,
        deflectAngle = 0, deflectSpin = 0,
        deflectWeaponAngle = 0,
    }
    -- 填充多返回值字段（避免重复调用）
    S.weaponClashX, S.weaponClashY = Combat.GetWeaponClashPos()
    local dd = Combat.GetDeflectData()
    if dd then
        S.deflectTimer = dd.timer or 0
        S.deflectDuration = dd.duration or 0.3
        S.deflectStartX = dd.startX or 0
        S.deflectStartY = dd.startY or 0
        S.deflectAngle = dd.angle or 0
        S.deflectSpin = dd.spin or 0
        S.deflectWeaponAngle = dd.weaponAngle or 0
        S.deflectTarget = dd.target or "player"
    end
    
    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)
    
    Renderer.RenderBackground(vg, S)
    Renderer.RenderPlatforms(vg, S)
    Renderer.RenderGround(vg, S)
    Renderer.RenderTargets(vg, S)
    Renderer.RenderTargetHPBars(vg, S)
    Renderer.RenderDummy(vg, S)
    Renderer.RenderDummyHPBar(vg, S)
    Renderer.RenderDummyWeapon(vg, S)
    Renderer.RenderAttack(vg, S)
    Renderer.RenderDeflectedWeapon(vg, S)
    Renderer.RenderWeaponClash(vg, S)
    Slime.Render(vg, player_)
    -- 玩家血条（受伤后显示）
    if player_.hp and player_.maxHp and player_.hp < player_.maxHp then
        local barY = player_.y - player_.height - 12 * physScale_
        local barW = Config.Combat.HPBarWidth * physScale_
        local barH = Config.Combat.HPBarHeight * physScale_
        local cx = player_.x + player_.width / 2
        local bx = cx - barW / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, barY, barW, barH, barH / 2)
        nvgFillColor(vg, nvgRGBA(20, 20, 20, 180))
        nvgFill(vg)
        local ratio = player_.hp / player_.maxHp
        local fillW = barW * ratio
        local r, g
        if ratio > 0.5 then r, g = 80, 200 else r, g = 240, math.floor(200 * ratio * 2) end
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bx, barY, fillW, barH, barH / 2)
        nvgFillColor(vg, nvgRGBA(r, g, 60, 220))
        nvgFill(vg)
    end
    Renderer.RenderHitEffects(vg, S)
    Renderer.RenderCombo(vg, S)
    Renderer.RenderTransformEffect(vg, S)
    
    -- 手机端虚拟操控绘制
    if VirtualPad.IsActive() then
        VirtualPad.UpdateLayout(screenW_, screenH_)
        VirtualPad.Render(vg)
    end
    
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

return TrialState
