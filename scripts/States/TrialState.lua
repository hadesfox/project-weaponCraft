-- ============================================================================
-- States/TrialState.lua - 试炼场（横版）
-- 横版动作：左右移动 + 跳跃 + 武器攻击
-- PC: AD/方向键移动, 空格跳跃, 鼠标/J键攻击, Q键变形
-- 移动端: 左侧方向按钮, 右侧跳跃+攻击按钮, 左下变形按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local KeyBindings = require("KeyBindings")
local GameSettings = require("GameSettings")
local Slime = require("Trial.Slime")
local Renderer = require("Trial.Renderer")

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

-- ============================================================================
-- 攻击系统
-- ============================================================================
local attacks_ = {}
local attacking_ = false
local attackTimer_ = 0
local attackDuration_ = 0
local currentAttack_ = nil
local attackHitTargets_ = {}

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

-- 木桩武器（预制，用于测试武器碰撞）
local dummyWeapon_ = nil  -- { x, y, angle, length, width, force, forceDir }

-- 木桩攻击系统（使用玩家同款攻击模组）
local dummyAttacking_ = false
local dummyAttackTimer_ = 0
local dummyAttackDuration_ = 0
local dummyCurrentAttack_ = nil
local dummyAttackCooldown_ = 0       -- 攻击间隔冷却
local dummyAttackProgress_ = 0       -- 当前攻击进度 0~1
local dummyFacingRight_ = false      -- 木桩面朝方向（朝向玩家）
local DUMMY_ATTACK_INTERVAL_MIN = 0.15 -- 最短攻击间隔（秒）
local DUMMY_ATTACK_INTERVAL_MAX = 0.35 -- 最长攻击间隔（秒）
local dummyHitPlayer_ = false        -- 本次攻击是否已命中玩家
local dummyAttacks_ = {}             -- 锻造师专用攻击组（斧）
local dummyMoving_ = false           -- 锻造师是否在移动
local dummyVx_ = 0                   -- 锻造师水平速度

-- 武器碰撞系统
local weaponClashAnim_ = 0      -- 武器碰撞特效计时
local weaponClashX_ = 0         -- 碰撞特效位置 X
local weaponClashY_ = 0         -- 碰撞特效位置 Y
local weaponClashCooldown_ = 0  -- 碰撞检测冷却

-- 格挡弹开系统（武器被弹飞动画）
local deflecting_ = false       -- 是否正在弹开
local deflectTimer_ = 0         -- 弹开计时
local deflectDuration_ = 0.4    -- 弹开动画持续时间
local deflectStartX_ = 0        -- 弹开起始位置 X
local deflectStartY_ = 0        -- 弹开起始位置 Y
local deflectAngle_ = 0         -- 弹开方向角度
local deflectSpin_ = 0          -- 武器旋转速度（弧度/秒）
local deflectWeaponAngle_ = 0   -- 弹开时武器初始角度

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

-- ============================================================================
-- 试炼场计时与结算系统
-- ============================================================================
local trialTimer_ = 0              -- 已消耗时间（秒）
local trialTimeLimit_ = 60         -- 时间限制
local trialTotalDamage_ = 0        -- 累计对锻造师造成的伤害
local trialEnded_ = false          -- 试炼是否已结束
local trialEndReason_ = ""         -- 结束原因: "kill" / "timeout"
local attackHitDummy_ = false      -- 当前攻击是否已命中锻造师（防止重复伤害）

-- 结算 UI 状态
local showEndScreen_ = false       -- 是否显示结算画面
local endScreenPhase_ = "input"    -- "input" / "submitting" / "leaderboard"
local playerInputId_ = ""          -- 玩家输入的ID
local leaderboardData_ = {}        -- 排行榜数据
local myRank_ = nil                -- 我的排名

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
local StartAttack
local UpdateAttack
local CheckAttackCollision
local CheckDummyCollision
local GetThrustLength
local HitTarget
local PointToSegmentDist
local UpdateTargets
local UpdateCombo
local UpdateHitEffects
local UpdateTransformAnim
local CheckWaveClear
local UpdateHUD
local InitDummyWeapon
local UpdateDummyWeapon
local UpdateDummyAttack
local UpdateDummyMovement
local CheckDummyAttackHitPlayer
local CheckWeaponClash
local GetPlayerWeaponCollider
local UpdateWeaponClash

local ShowEndScreen
local SubmitScore
local FetchLeaderboard
local BuildLeaderboardUI

--- 进入试炼状态
function TrialState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    
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
    attackHitDummy_ = false
    showEndScreen_ = false
    endScreenPhase_ = "input"
    playerInputId_ = ""
    leaderboardData_ = {}
    myRank_ = nil
    
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
    playerFrameIndex_ = 1
    playerFrameTimer_ = 0
    
    -- 生成平台和靶子
    GeneratePlatforms()
    SpawnTargets()
    
    -- 初始化史莱姆
    Slime.Init(screenW_, screenH_, groundY_, physScale_)
    
    -- 初始化木桩武器和碰撞系统
    weaponClashAnim_ = 0
    weaponClashCooldown_ = 0
    deflecting_ = false
    deflectTimer_ = 0
    InitDummyWeapon()
    
    -- 锻造师使用斧攻击组（独立于玩家武器）
    dummyAttacks_ = Config.Attacks.AXE
    dummyMoving_ = false
    dummyVx_ = 0
    
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
    
    attacking_ = false
    currentAttack_ = nil
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
    if attacking_ then return end  -- 攻击中不可变形
    
    -- 切换形态
    currentForm_ = currentForm_ == 1 and 2 or 1
    attacks_ = formAttacks_[currentForm_]
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
    targets_ = {}
    platforms_ = {}
    attacking_ = false
    weaponStrokes_ = {}
    if playerImage_ and playerImage_ ~= 0 then
        nvgDeleteImage(NVG.Get(), playerImage_)
        playerImage_ = nil
    end
    if enemyImage_ and enemyImage_ ~= 0 then
        nvgDeleteImage(NVG.Get(), enemyImage_)
        enemyImage_ = nil
    end
    -- 释放跑步帧
    for i = 1, #playerRunFrames_ do
        if playerRunFrames_[i] and playerRunFrames_[i] ~= 0 then
            nvgDeleteImage(NVG.Get(), playerRunFrames_[i])
        end
    end
    playerRunFrames_ = {}
    -- 释放史莱姆
    Slime.Shutdown()
    -- 释放渲染器图片（背景/dummy）
    Renderer.ReleaseImages(NVG.Get())
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
        attacking_ = false
        currentAttack_ = nil
        ShowEndScreen()
        return
    end
    
    -- 检测玩家血量归零（被锻造师击败）
    if player_.hp <= 0 and not trialEnded_ then
        trialEnded_ = true
        trialEndReason_ = "defeated"
        attacking_ = false
        currentAttack_ = nil
        ShowEndScreen()
        return
    end
    
    UpdateInput()
    UpdatePlayerPhysics(dt)
    UpdateAttack(dt)
    UpdateTargets(dt)
    UpdateDummyAttack(dt)
    UpdateDummyWeapon(dt)
    UpdateWeaponClash(dt)
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
        attacking_ = false
        currentAttack_ = nil
        ShowEndScreen()
        return
    end
    
    UpdateHUD()
end

--- 读取输入状态
UpdateInput = function()
    inputLeft_ = KeyBindings.IsDown("move_left")
    inputRight_ = KeyBindings.IsDown("move_right")
    inputDown_ = KeyBindings.IsDown("move_down")
end

--- 玩家物理（横版重力）
UpdatePlayerPhysics = function(dt)
    local speed = Config.Trial.MoveSpeed * physScale_
    -- agile 效果：攻击时移速不减；否则攻击时清零
    if attacking_ and materialEffect_ ~= "agile" then
        speed = 0
    end
    
    if inputLeft_ then
        player_.vx = -speed
        if not attacking_ then player_.facingRight = false end
    elseif inputRight_ then
        player_.vx = speed
        if not attacking_ then player_.facingRight = true end
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

--- 发起攻击
--- @param index number|nil 攻击索引（1=左键招式, 2=右键招式），nil时默认为1
StartAttack = function(index)
    if attacking_ then return end
    if #attacks_ == 0 then return end
    if trialEnded_ then return end  -- 试炼结束后不可攻击
    
    local idx = index or 1
    if idx > #attacks_ then idx = 1 end
    
    currentAttack_ = attacks_[idx]
    attacking_ = true
    attackTimer_ = 0
    -- 砥砺攻速加成：降低攻击持续时间（加成范围 0%~30%）
    local speedBonus = gameData_.attackSpeedBonus or 0
    -- 材质攻速修正：spdMod 正值加速（缩短持续时间），负值减速
    local totalSpeedMod = speedBonus + materialSpdMod_
    attackDuration_ = currentAttack_.duration * (1.0 - totalSpeedMod)
    attackHitTargets_ = {}
    attackHitDummy_ = false  -- 新攻击重置木桩命中标记
end

--- 攻击更新
UpdateAttack = function(dt)
    if not attacking_ then return end
    
    attackTimer_ = attackTimer_ + dt
    local progress = attackTimer_ / attackDuration_
    
    if progress >= 1.0 then
        attacking_ = false
        currentAttack_ = nil
        attackHitTargets_ = {}
        return
    end
    
    -- 冲撞前移
    if currentAttack_ and currentAttack_.isCharge then
        local dir = player_.facingRight and 1 or -1
        local chargeDist = (currentAttack_.chargeDistance or 40) * physScale_ * dt / attackDuration_
        player_.x = player_.x + dir * chargeDist
    end
    
    CheckAttackCollision(progress)
end

--- 碰撞检测
CheckAttackCollision = function(progress)
    if not currentAttack_ then return end
    
    local atk = currentAttack_
    local dir = player_.facingRight and 1 or -1
    local originX = player_.x + player_.width / 2 + dir * 10 * physScale_
    local originY = player_.y + player_.height * 0.4
    local range = atk.range * physScale_
    
    if atk.isThrust then
        local thrustLen = GetThrustLength(progress)
        local tipX = originX + dir * thrustLen
        local tipY = originY
        
        for i = 1, #targets_ do
            local t = targets_[i]
            if t.alive and not attackHitTargets_[i] then
                local dist = PointToSegmentDist(t.x, t.y, originX, originY, tipX, tipY)
                local hr = t.hitRadius or (t.size / 2)
                if dist < hr + 12 then
                    HitTarget(i, t, atk, dir)
                end
            end
        end
    else
        local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
        for i = 1, #targets_ do
            local t = targets_[i]
            if t.alive and not attackHitTargets_[i] then
                local dx = t.x - originX
                local dy = t.y - originY
                local dist = math.sqrt(dx * dx + dy * dy)
                local hr = t.hitRadius or (t.size / 2)
                if dist < range + hr then
                    -- 判断目标是否在角色面朝方向的前方
                    local inFront = (player_.facingRight and dx > -20) or (not player_.facingRight and dx < 20)
                    local vertOk = math.abs(dy) < range * 0.8
                    if inFront and vertOk then
                        HitTarget(i, t, atk, dir)
                    end
                end
            end
        end
    end
    
    -- 先检测武器间碰撞（格挡判定优先）
    CheckWeaponClash(progress)
    
    -- 如果未被格挡，才检测木桩碰撞造成伤害
    if not deflecting_ then
        CheckDummyCollision(progress)
    end
end

--- 检测木桩碰撞
CheckDummyCollision = function(progress)
    if not dummy_ or not currentAttack_ then return end
    if attackHitDummy_ then return end  -- 本次攻击已命中，不再重复判定
    
    local atk = currentAttack_
    local dir = player_.facingRight and 1 or -1
    local originX = player_.x + player_.width / 2 + dir * 10 * physScale_
    local originY = player_.y + player_.height * 0.4
    local range = atk.range * physScale_
    
    -- 木桩中心
    local dCx = dummy_.x
    local dCy = dummy_.y - dummy_.height / 2
    local dRadius = dummy_.width / 2 + 10
    
    local hit = false
    if atk.isThrust then
        local thrustLen = GetThrustLength(progress)
        local tipX = originX + dir * thrustLen
        local dist = PointToSegmentDist(dCx, dCy, originX, originY, tipX, originY)
        hit = dist < dRadius + 8
    else
        local dx = dCx - originX
        local dy = dCy - originY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < range + dRadius then
            local inFront = (player_.facingRight and dx > -20) or (not player_.facingRight and dx < 20)
            hit = inFront and math.abs(dy) < range * 0.8
        end
    end
    
    if hit then
        attackHitDummy_ = true  -- 标记本次攻击已命中
        dummy_.hitAnim = 1.0
        dummy_.hitDir = dir
        -- 扣血（应用材质攻击力修正 + 成长加成）
        local baseDmg = atk.damage or 150
        local dmg = math.floor(baseDmg * (1.0 + materialAtkMod_) * (1.0 + growthBonus_))
        dummy_.hp = math.max(0, dummy_.hp - dmg)
        trialTotalDamage_ = trialTotalDamage_ + dmg
        -- 伤害数字
        hitEffects_[#hitEffects_ + 1] = {
            x = dCx, y = dCy - dummy_.height * 0.6,
            text = "-" .. dmg,
            timer = Config.Combat.DamageNumberDuration,
            color = dmg >= 200 and Config.Colors.Danger or { 255, 200, 100 },
        }
        -- 连击
        combo_ = combo_ + 1
        comboTimer_ = 0
        score_ = score_ + Config.Trial.ComboMultiplier * combo_
    end
end

--- 突刺延伸长度
GetThrustLength = function(progress)
    if not currentAttack_ then return 60 * physScale_ end
    local len = currentAttack_.range * physScale_
    if progress < 0.3 then
        return len * (progress / 0.3)
    elseif progress < 0.7 then
        return len
    else
        return len * (1.0 - (progress - 0.7) / 0.3)
    end
end

--- 命中靶子（HP伤害系统）
HitTarget = function(index, target, atk, dir)
    attackHitTargets_[index] = true
    
    -- 计算伤害（应用材质攻击力修正 + 成长加成）
    local baseDmg = atk.damage or 150
    local dmg = math.floor(baseDmg * (1.0 + materialAtkMod_) * (1.0 + growthBonus_))
    target.hp = target.hp - dmg
    target.hitAnim = 0.5  -- 受击闪烁
    
    -- 击退（heavy_blow: 击退距离+50%）
    local kb = atk.knockback or 8
    if materialEffect_ == "heavy_blow" then
        kb = kb * 1.5
    end
    target.knockX = dir * math.abs(kb)
    target.knockY = -math.abs(kb) * 0.5
    
    -- 材质效果：lifesteal（嗜血）- 伤害15%回血显示
    if materialEffect_ == "lifesteal" then
        local healAmt = math.floor(dmg * 0.15)
        hitEffects_[#hitEffects_ + 1] = {
            x = player_.x, y = player_.y - 10,
            text = "+" .. healAmt,
            timer = 0.8,
            color = { 80, 255, 80 },
        }
        -- 回复效果：减少下次受击的击退量（存储一个护盾值）
        player_.healShield = (player_.healShield or 0) + healAmt * 0.3
    end
    
    -- 材质效果：growth（成长）- 每次命中增加5%伤害，上限50%
    if materialEffect_ == "growth" then
        growthBonus_ = math.min(0.50, growthBonus_ + 0.05)
    end
    
    -- 显示伤害数字
    hitEffects_[#hitEffects_ + 1] = {
        x = target.x, y = target.y - (target.size or 30),
        text = "-" .. dmg,
        timer = Config.Combat.DamageNumberDuration,
        color = dmg >= 200 and Config.Colors.Danger or { 255, 200, 100 },
    }
    
    -- 判定死亡
    if target.hp <= 0 then
        target.alive = false
        target.hp = 0
        target.hitAnim = 1.0
        
        -- 击杀奖励
        combo_ = combo_ + 1
        comboTimer_ = 0
        local points = Config.Trial.ComboMultiplier * combo_
        score_ = score_ + points
        
        hitEffects_[#hitEffects_ + 1] = {
            x = target.x, y = target.y - (target.size or 30) - 20,
            text = "+" .. points,
            timer = 1.0,
            color = combo_ >= 5 and Config.Colors.Gold or Config.Colors.Success,
        }
    else
        -- 未击杀时也增加连击
        combo_ = combo_ + 1
        comboTimer_ = 0
    end
end

--- 点到线段距离
PointToSegmentDist = function(px, py, ax, ay, bx, by)
    local abx = bx - ax
    local aby = by - ay
    local apx = px - ax
    local apy = py - ay
    local ab2 = abx * abx + aby * aby
    if ab2 < 0.01 then return math.sqrt(apx * apx + apy * apy) end
    local t = math.max(0, math.min(1, (apx * abx + apy * aby) / ab2))
    local cx = ax + t * abx
    local cy = ay + t * aby
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
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
    if attackLabel and currentAttack_ then
        attackLabel:SetText("招式: " .. currentAttack_.name)
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
-- 结算画面
-- ============================================================================

--- 显示结算画面（替换 UI 为结算面板）
--- 左侧：击败信息 + 玩家输入提交
--- 右侧：排行榜
ShowEndScreen = function()
    showEndScreen_ = true
    endScreenPhase_ = "input"
    playerInputId_ = ""

    -- 计算用时（秒，取整）
    local timeUsed = math.ceil(trialTimer_)
    local reasonText = trialEndReason_ == "kill" and "锻造师被击败!"
        or trialEndReason_ == "defeated" and "你被击败了!" or "时间到!"
    local borderColor = trialEndReason_ == "kill" and Config.Colors.Gold or { 200, 80, 80, 255 }

    -- 左侧：结算信息 + 名字输入
    local inputField = UI.TextField {
        id = "endPlayerInput",
        placeholder = "输入你的昵称",
        value = "",
        maxLength = 12,
        width = "100%",
        height = 36,
        fontSize = 14,
        onChange = function(self, val)
            playerInputId_ = val
        end,
    }

    local submitBtn = UI.Button {
        id = "endSubmitBtn",
        text = "提交成绩",
        variant = "primary",
        width = "100%",
        onClick = function(self)
            if #playerInputId_ == 0 then return end
            self:SetDisabled(true)
            endScreenPhase_ = "submitting"
            SubmitScore(timeUsed)
        end,
    }

    local leftPanel = UI.Panel {
        flex = 1,
        padding = 20, gap = 12,
        backgroundColor = { 30, 32, 42, 255 },
        borderRadius = 14,
        borderWidth = 2,
        borderColor = borderColor,
        alignItems = "center",
        justifyContent = "center",
        children = {
            -- 标题
            UI.Label {
                text = reasonText,
                fontSize = 20,
                fontColor = trialEndReason_ == "kill" and Config.Colors.Gold or { 240, 100, 100, 255 },
            },
            -- 战绩信息
            UI.Panel {
                width = "100%", gap = 6,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "用时", fontSize = 14, fontColor = { 160, 170, 180, 255 } },
                            UI.Label { text = timeUsed .. " 秒", fontSize = 14, fontColor = Config.Colors.TextLight },
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "总伤害", fontSize = 14, fontColor = { 160, 170, 180, 255 } },
                            UI.Label { text = tostring(trialTotalDamage_), fontSize = 14, fontColor = { 255, 180, 80, 255 } },
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "最高连击", fontSize = 14, fontColor = { 160, 170, 180, 255 } },
                            UI.Label { text = tostring(combo_), fontSize = 14, fontColor = Config.Colors.Secondary },
                        },
                    },
                },
            },
            -- 分割线
            UI.Panel { width = "80%", height = 1, backgroundColor = { 60, 60, 70, 150 } },
            -- 输入昵称
            UI.Label {
                text = "输入你的名字上榜:",
                fontSize = 12,
                fontColor = { 140, 150, 160, 220 },
            },
            inputField,
            submitBtn,
            -- 返回菜单按钮
            UI.Button {
                text = "返回菜单",
                size = "small",
                variant = "outline",
                marginTop = 8,
                width = "100%",
                onClick = function()
                    if onComplete_ then onComplete_() end
                end,
            },
        },
    }

    -- 右侧：排行榜
    local leaderboardPanel = UI.Panel {
        id = "endLeaderboard",
        width = "100%",
        gap = 4,
        children = {},
    }

    local rightPanel = UI.Panel {
        flex = 1,
        padding = 20, gap = 10,
        backgroundColor = { 25, 28, 38, 255 },
        borderRadius = 14,
        borderWidth = 1,
        borderColor = { 80, 80, 100, 180 },
        children = {
            UI.Label {
                text = "排行榜 (用时优先)",
                fontSize = 16,
                fontColor = Config.Colors.Gold,
                marginBottom = 6,
            },
            leaderboardPanel,
        },
    }

    local endRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 10, 12, 20, 230 },
        justifyContent = "center",
        alignItems = "center",
        padding = 20,
        children = {
            UI.Panel {
                width = "100%", maxWidth = 700,
                height = "90%", maxHeight = 420,
                flexDirection = "row",
                gap = 16,
                children = {
                    leftPanel,
                    rightPanel,
                },
            },
        },
    }

    -- 替换整个 UI
    uiRoot_ = endRoot
    UI.SetRoot(uiRoot_)

    -- 立即拉取排行榜数据显示在右侧
    FetchLeaderboard()
end

--- 提交分数到云排行榜
--- 排序规则：用时少优先(升序)，同时间伤害高优先
--- 使用复合分数: compositeScore = timeUsed * 100000 + (99999 - clampedDamage)
--- 这样升序排列时 → 时间小的在前；同时间伤害高的在前
SubmitScore = function(timeUsed)
    local cjson = require("cjson")

    -- 新记录
    local newEntry = {
        name = playerInputId_,
        time = timeUsed,
        damage = trialTotalDamage_,
        ts = os.time(),
    }

    -- 先拉取已有排行榜历史
    clientCloud:Get("leaderboard_history", {
        ok = function(values)
            local history = {}
            if values and values.leaderboard_history then
                local ok2, decoded = pcall(cjson.decode, values.leaderboard_history)
                if ok2 and type(decoded) == "table" then
                    history = decoded
                end
            end
            -- 追加新记录
            history[#history + 1] = newEntry
            -- 按复合分数排序（用时优先，伤害越少越好）
            table.sort(history, function(a, b)
                if a.time ~= b.time then return a.time < b.time end
                return a.damage < b.damage
            end)
            -- 保留前 50 条
            if #history > 50 then
                local trimmed = {}
                for i = 1, 50 do trimmed[i] = history[i] end
                history = trimmed
            end
            -- 存回云端
            clientCloud:Set("leaderboard_history", cjson.encode(history), {
                ok = function()
                    print("[TrialState] Leaderboard history saved, count=" .. #history)
                    leaderboardData_ = history
                    BuildLeaderboardUI()
                end,
                error = function(code, reason)
                    print("[TrialState] Save leaderboard error: " .. tostring(reason))
                    leaderboardData_ = history
                    BuildLeaderboardUI()
                end,
            })
        end,
        error = function(code, reason)
            print("[TrialState] Get history error: " .. tostring(reason))
            -- 无法拉取旧数据，直接存新记录
            local history = { newEntry }
            clientCloud:Set("leaderboard_history", cjson.encode(history), {
                ok = function()
                    leaderboardData_ = history
                    BuildLeaderboardUI()
                end,
                error = function()
                    leaderboardData_ = history
                    BuildLeaderboardUI()
                end,
            })
        end,
    })
end

--- 拉取排行榜数据
FetchLeaderboard = function()
    endScreenPhase_ = "leaderboard"
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
            -- 排序
            table.sort(history, function(a, b)
                if a.time ~= b.time then return a.time < b.time end
                return a.damage < b.damage
            end)
            print("[TrialState] Leaderboard fetched from history, count=" .. #history)
            leaderboardData_ = history
            BuildLeaderboardUI()
        end,
        error = function(code, reason)
            print("[TrialState] Leaderboard fetch error: " .. tostring(reason))
            leaderboardData_ = {}
            BuildLeaderboardUI()
        end,
    })
end

--- 构建排行榜 UI 内容
BuildLeaderboardUI = function()
    local panel = uiRoot_ and uiRoot_:FindById("endLeaderboard")
    if not panel then return end

    -- 清空并重建
    local children = {}

    if #leaderboardData_ == 0 then
        children[#children + 1] = UI.Label {
            text = "暂无数据",
            fontSize = 12,
            fontColor = { 120, 120, 130, 180 },
        }
    else
        -- 显示前 10 条
        local showCount = math.min(10, #leaderboardData_)
        for i = 1, showCount do
            local item = leaderboardData_[i]
            local name = item.name or "未知"
            local t = item.time or 0
            local d = item.damage or 0
            local isMe = (name == playerInputId_)

            local rowColor = isMe and { 255, 220, 100, 255 } or { 200, 205, 210, 220 }
            children[#children + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                paddingLeft = 4, paddingRight = 4,
                paddingTop = 3, paddingBottom = 3,
                backgroundColor = isMe and { 60, 55, 30, 100 } or { 0, 0, 0, 0 },
                borderRadius = 4,
                children = {
                    UI.Label {
                        text = "#" .. i .. " " .. name,
                        fontSize = 11,
                        fontColor = rowColor,
                    },
                    UI.Label {
                        text = t .. "秒 " .. d .. "伤害",
                        fontSize = 11,
                        fontColor = { 160, 170, 180, 200 },
                    },
                },
            }
        end
    end

    panel:ClearChildren()
    for _, child in ipairs(children) do
        panel:AddChild(child)
    end
end

-- ============================================================================
-- 输入事件
-- ============================================================================

function TrialState.OnKeyDown(key)
    if KeyBindings.IsKey("jump", key) then
        DoJump()
    elseif KeyBindings.IsKey("attack1", key) then
        StartAttack(1)
    elseif KeyBindings.IsKey("attack2", key) then
        StartAttack(2)
    elseif KeyBindings.IsKey("transform", key) then
        DoTransform()
    end
end

function TrialState.OnMouseDown(button)
    if button == MOUSEB_LEFT then
        StartAttack(1)  -- 左键 = 招式1
    elseif button == MOUSEB_RIGHT then
        StartAttack(2)  -- 右键 = 招式2
    end
end

function TrialState.OnMouseUp(button)
end

function TrialState.OnMouseMove()
end

function TrialState.OnTouchBegin(x, y)
    local dpr = graphics:GetDPR()
    local tx = x / dpr
    
    if tx > screenW_ * 0.75 then
        StartAttack(2)  -- 右侧区域 = 招式2
    elseif tx > screenW_ * 0.55 then
        StartAttack(1)  -- 中右区域 = 招式1
    elseif tx > screenW_ * 0.3 then
        DoJump()
    end
end

function TrialState.OnTouchMove(x, y)
    local dpr = graphics:GetDPR()
    local tx = x / dpr
    
    if tx < screenW_ * 0.2 then
        inputLeft_ = true
        inputRight_ = false
    elseif tx < screenW_ * 0.4 then
        inputRight_ = true
        inputLeft_ = false
    end
end

function TrialState.OnTouchEnd(x, y)
    inputLeft_ = false
    inputRight_ = false
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
        dummyWeapon = dummyWeapon_,
        dummyAttacking = dummyAttacking_,
        dummyCurrentAttack = dummyCurrentAttack_,
        dummyAttackProgress = dummyAttackProgress_,
        dummyFacingRight = dummyFacingRight_,
        dummyMoving = dummyMoving_,
        attacking = attacking_,
        currentAttack = currentAttack_,
        attackTimer = attackTimer_,
        attackDuration = attackDuration_,
        weaponStrokes = weaponStrokes_,
        hitEffects = hitEffects_,
        combo = combo_,
        comboTimer = comboTimer_,
        transformAnim = transformAnim_,
        formNames = formNames_,
        currentForm = currentForm_,
        gameData = gameData_,
        enemyImage = enemyImage_,
        targetDefs = targetDefs_,
        playerImage = playerImage_,
        playerRunFrames = playerRunFrames_,
        playerFrameIndex = playerFrameIndex_,
        weaponClashAnim = weaponClashAnim_,
        weaponClashX = weaponClashX_,
        weaponClashY = weaponClashY_,
        -- 弹开状态
        deflecting = deflecting_,
        deflectTimer = deflectTimer_,
        deflectDuration = deflectDuration_,
        deflectStartX = deflectStartX_,
        deflectStartY = deflectStartY_,
        deflectAngle = deflectAngle_,
        deflectSpin = deflectSpin_,
        deflectWeaponAngle = deflectWeaponAngle_,
    }
    
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
    
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

-- ============================================================================
-- 木桩攻击系统
-- ============================================================================

--- 更新木桩攻击AI（随机挥剑，使用与玩家相同的攻击模组）
UpdateDummyAttack = function(dt)
    if not dummy_ or not dummyWeapon_ then return end
    if #dummyAttacks_ == 0 then return end

    -- 木桩朝向玩家
    dummyFacingRight_ = player_.x > dummy_.x

    -- 攻击中：更新进度（攻击时不移动）
    if dummyAttacking_ then
        dummyMoving_ = false
        dummyVx_ = 0
        dummyAttackTimer_ = dummyAttackTimer_ + dt
        dummyAttackProgress_ = dummyAttackTimer_ / dummyAttackDuration_

        if dummyAttackProgress_ >= 1.0 then
            -- 攻击结束
            dummyAttacking_ = false
            dummyCurrentAttack_ = nil
            dummyAttackProgress_ = 0
            dummyHitPlayer_ = false
            -- 设置下次攻击冷却
            dummyAttackCooldown_ = DUMMY_ATTACK_INTERVAL_MIN
                + math.random() * (DUMMY_ATTACK_INTERVAL_MAX - DUMMY_ATTACK_INTERVAL_MIN)
        else
            -- 检测是否命中玩家
            CheckDummyAttackHitPlayer()
        end
        return
    end

    -- 冷却中：边追击边等待
    if dummyAttackCooldown_ > 0 then
        dummyAttackCooldown_ = dummyAttackCooldown_ - dt
        UpdateDummyMovement(dt)
        if dummyAttackCooldown_ > 0 then return end
    end

    -- 冷却结束：立即发起攻击（无需距离判断）
    UpdateDummyMovement(dt)
    local idx = math.random(1, #dummyAttacks_)
    dummyCurrentAttack_ = dummyAttacks_[idx]
    dummyAttacking_ = true
    dummyAttackTimer_ = 0
    dummyAttackProgress_ = 0
    dummyHitPlayer_ = false
    dummyAttackDuration_ = dummyCurrentAttack_.duration * 0.7
end

--- 锻造师移动追击玩家
UpdateDummyMovement = function(dt)
    if not dummy_ then return end
    
    local distToPlayer = math.abs(player_.x - dummy_.x)
    local atkRange = Config.Combat.DummyAttackRange * physScale_
    
    -- 在攻击范围内则停止
    if distToPlayer <= atkRange then
        dummyMoving_ = false
        dummyVx_ = 0
        return
    end
    
    -- 追击玩家
    dummyMoving_ = true
    local speed = Config.Combat.DummyMoveSpeed * physScale_
    local dir = dummyFacingRight_ and 1 or -1
    dummyVx_ = dir * speed
    
    -- 更新位置
    dummy_.x = dummy_.x + dummyVx_ * dt
    
    -- 边界限制（不超出屏幕）
    local margin = dummy_.width * 0.5
    if dummy_.x < margin then dummy_.x = margin end
    if dummy_.x > screenW_ - margin then dummy_.x = screenW_ - margin end
end

--- 检测木桩攻击是否命中玩家
CheckDummyAttackHitPlayer = function()
    if not dummyAttacking_ or not dummyCurrentAttack_ then return end
    if dummyHitPlayer_ then return end  -- 本次攻击已命中
    if not dummy_ then return end

    local atk = dummyCurrentAttack_
    local dir = dummyFacingRight_ and 1 or -1
    local originX = dummy_.x + dir * 10 * physScale_
    local originY = dummy_.y - dummy_.height * 0.6
    local range = atk.range * physScale_
    local progress = dummyAttackProgress_

    -- 计算木桩武器尖端位置
    local tipX, tipY
    if atk.isThrust then
        -- 突刺
        local eased = math.sin(progress * math.pi)  -- 0→1→0 前冲后收
        local thrustLen = range * eased
        tipX = originX + dir * thrustLen
        tipY = originY
    else
        -- 挥动
        local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
        local arcDir = (atk.direction or 1)
        local startAngle = math.rad(atk.startAngle or -60)
        local sweepAngle = math.rad(atk.arc) * arcDir * easedProgress
        local currentAngle
        if dummyFacingRight_ then
            currentAngle = startAngle + sweepAngle
        else
            currentAngle = math.pi - (startAngle + sweepAngle)
        end
        tipX = originX + math.cos(currentAngle) * range
        tipY = originY + math.sin(currentAngle) * range
    end

    -- 检测是否命中玩家（简化：点到矩形距离）
    local px = player_.x
    local py = player_.y
    local pw = player_.width
    local ph = player_.height

    -- 玩家中心
    local pcx = px + pw / 2
    local pcy = py - ph / 2

    -- 武器线段中点到玩家中心距离
    local midX = (originX + tipX) / 2
    local midY = (originY + tipY) / 2
    local dx = math.abs(midX - pcx)
    local dy = math.abs(midY - pcy)
    local hitRadius = range * 0.5 + pw * 0.3

    if dx < hitRadius and dy < ph * 0.6 then
        -- 命中！击退玩家
        dummyHitPlayer_ = true
        local knockDir = dummyFacingRight_ and 1 or -1
        local kb = (atk.knockback or 8) * physScale_
        
        -- 计算伤害
        local dmg = atk.damage or 150
        
        -- 材质效果：shatter（碎裂）- 受击伤害/击退+20%
        if materialEffect_ == "shatter" then
            kb = kb * 1.2
            dmg = math.floor(dmg * 1.2)
        end
        
        -- 材质效果：lifesteal 护盾减免击退和伤害
        local shield = player_.healShield or 0
        if shield > 0 then
            local reduction = math.min(shield, kb * 0.3)
            kb = kb - reduction
            player_.healShield = shield - reduction
        end
        
        -- 扣除玩家血量
        player_.hp = math.max(0, player_.hp - dmg)
        player_.hitAnim = 0.5  -- 受击闪烁
        
        player_.vx = knockDir * kb * 6
        player_.vy = -kb * 2.5
        player_.onGround = false

        -- 伤害数字特效（右侧偏移）
        hitEffects_[#hitEffects_ + 1] = {
            x = pcx + 25 * physScale_,
            y = pcy - 15,
            text = "-" .. dmg,
            timer = Config.Combat.DamageNumberDuration,
            color = { 255, 80, 80 },
        }
        -- 招式名称特效（左侧偏移）
        hitEffects_[#hitEffects_ + 1] = {
            x = pcx - 25 * physScale_,
            y = pcy - 15,
            text = atk.name .. "!",
            timer = 1.0,
            color = { 255, 100, 80 },
        }
    end
end

-- ============================================================================
-- 武器碰撞系统
-- ============================================================================

--- 初始化木桩预制武器（模拟木桩手持一把剑，向右伸出）
InitDummyWeapon = function()
    -- 武器参数（相对于木桩的局部定义，实际位置在 UpdateDummyWeapon 中计算）
    dummyWeapon_ = {
        -- 碰撞体定义（线段：从根部到尖端）
        localOffsetX = 0,            -- 相对木桩中心的 X 偏移（渲染时计算）
        localOffsetY = -0.6,         -- 相对木桩高度的比例偏移（0.6 = 60% 高度处）
        angle = -0.3,                -- 武器角度（弧度，略微上扬向右）
        length = 50,                 -- 武器长度（基础值，会乘以 physScale_）
        width = 8,                   -- 碰撞宽度（基础值）
        -- 力属性
        force = 12,                  -- 力的大小（击退力度）
        forceDir = 1,                -- 力的方向（1=向右，-1=向左）
        -- 运行时计算的世界坐标
        rootX = 0, rootY = 0,        -- 根部位置
        tipX = 0, tipY = 0,          -- 尖端位置
    }
    print("[TrialState] Dummy weapon initialized (right side)")
end

--- 更新木桩武器位置（跟随木桩 + 攻击动画）
UpdateDummyWeapon = function(dt)
    if not dummyWeapon_ or not dummy_ then return end
    
    local dw = dummyWeapon_
    local dx = dummy_.x
    local dy = dummy_.y
    local dh = dummy_.height
    
    -- 受击时武器也跟随晃动
    local shakeX = 0
    if dummy_.hitAnim > 0 then
        shakeX = math.sin(dummy_.hitAnim * 20) * 4 * dummy_.hitAnim * dummy_.hitDir
    end
    
    -- 根部位置：木桩手持武器位置
    local len = dw.length * physScale_
    local dir = dummyFacingRight_ and 1 or -1
    dw.forceDir = dir
    dw.rootX = dx + shakeX + dir * 10 * physScale_
    dw.rootY = dy + dw.localOffsetY * dh
    
    -- 攻击中：武器跟随攻击弧度运动
    if dummyAttacking_ and dummyCurrentAttack_ then
        local atk = dummyCurrentAttack_
        local range = atk.range * physScale_
        local progress = dummyAttackProgress_
        
        if atk.isThrust then
            -- 突刺动画
            local eased = math.sin(progress * math.pi)
            local thrustLen = range * eased
            dw.tipX = dw.rootX + dir * thrustLen
            dw.tipY = dw.rootY
            dw.angle = dummyFacingRight_ and 0 or math.pi
        else
            -- 挥动动画（与玩家渲染逻辑一致）
            local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
            local arcDir = (atk.direction or 1)
            local startAngle = math.rad(atk.startAngle or -60)
            local sweepAngle = math.rad(atk.arc) * arcDir * easedProgress
            local currentAngle
            if dummyFacingRight_ then
                currentAngle = startAngle + sweepAngle
            else
                currentAngle = math.pi - (startAngle + sweepAngle)
            end
            dw.tipX = dw.rootX + math.cos(currentAngle) * range
            dw.tipY = dw.rootY + math.sin(currentAngle) * range
            dw.angle = currentAngle
        end
    else
        -- 静止/待机状态：武器斜持朝前
        local idleAngle = dummyFacingRight_ and (-0.3) or (math.pi + 0.3)
        dw.angle = idleAngle
        dw.tipX = dw.rootX + math.cos(idleAngle) * len
        dw.tipY = dw.rootY + math.sin(idleAngle) * len
    end
end

--- 获取玩家武器当前碰撞数据（攻击时有效）
--- @return table|nil 碰撞体 { rootX, rootY, tipX, tipY, width, force, forceDir }
GetPlayerWeaponCollider = function(progress)
    if not attacking_ or not currentAttack_ then return nil end
    
    local atk = currentAttack_
    local dir = player_.facingRight and 1 or -1
    local originX = player_.x + player_.width / 2 + dir * 10 * physScale_
    local originY = player_.y + player_.height * 0.4
    local range = atk.range * physScale_
    
    local tipX, tipY
    
    if atk.isThrust then
        -- 突刺：线段碰撞体
        local thrustLen = GetThrustLength(progress)
        tipX = originX + dir * thrustLen
        tipY = originY
    else
        -- 挥动：刃尖位置
        local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
        local arcDir = (atk.direction or 1)
        local startAngle = math.rad(atk.startAngle or -60)
        local sweepAngle = math.rad(atk.arc) * arcDir * easedProgress
        local currentAngle
        if player_.facingRight then
            currentAngle = startAngle + sweepAngle
        else
            currentAngle = math.pi - (startAngle + sweepAngle)
        end
        tipX = originX + math.cos(currentAngle) * range
        tipY = originY + math.sin(currentAngle) * range
    end
    
    return {
        rootX = originX,
        rootY = originY,
        tipX = tipX,
        tipY = tipY,
        width = 12 * physScale_,
        force = atk.knockback or 8,
        forceDir = dir,
    }
end

--- 线段-线段最短距离（用于武器碰撞检测）
local function SegmentToSegmentDist(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
    -- 简化实现：检测每个线段的端点和中点到对方线段的距离，取最小
    local function ptSegDist(px, py, sx1, sy1, sx2, sy2)
        local dx = sx2 - sx1
        local dy = sy2 - sy1
        local len2 = dx * dx + dy * dy
        if len2 < 0.01 then
            return math.sqrt((px - sx1) * (px - sx1) + (py - sy1) * (py - sy1))
        end
        local t = math.max(0, math.min(1, ((px - sx1) * dx + (py - sy1) * dy) / len2))
        local cx = sx1 + t * dx
        local cy = sy1 + t * dy
        return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
    end

    -- A段的3个采样点到B段的距离
    local midAx = (ax1 + ax2) / 2
    local midAy = (ay1 + ay2) / 2
    local d1 = ptSegDist(ax1, ay1, bx1, by1, bx2, by2)
    local d2 = ptSegDist(ax2, ay2, bx1, by1, bx2, by2)
    local d3 = ptSegDist(midAx, midAy, bx1, by1, bx2, by2)

    -- B段的3个采样点到A段的距离
    local midBx = (bx1 + bx2) / 2
    local midBy = (by1 + by2) / 2
    local d4 = ptSegDist(bx1, by1, ax1, ay1, ax2, ay2)
    local d5 = ptSegDist(bx2, by2, ax1, ay1, ax2, ay2)
    local d6 = ptSegDist(midBx, midBy, ax1, ay1, ax2, ay2)

    return math.min(d1, d2, d3, d4, d5, d6)
end

--- 检测玩家武器与木桩武器的碰撞
CheckWeaponClash = function(progress)
    if not dummyWeapon_ or not dummy_ then return end
    -- 木桩未攻击时武器隐藏，无法格挡
    if not dummyAttacking_ then return end
    if weaponClashCooldown_ > 0 then return end
    
    local playerWeapon = GetPlayerWeaponCollider(progress)
    if not playerWeapon then return end
    
    -- 线段-线段最近距离检测
    local dw = dummyWeapon_
    local dist = SegmentToSegmentDist(
        playerWeapon.rootX, playerWeapon.rootY, playerWeapon.tipX, playerWeapon.tipY,
        dw.rootX, dw.rootY, dw.tipX, dw.tipY
    )
    
    local collisionThreshold = (playerWeapon.width + dw.width * physScale_) / 2
    
    if dist < collisionThreshold then
        -- 碰撞发生！
        weaponClashCooldown_ = 0.4  -- 冷却，避免连续触发
        
        -- 碰撞点（两线段中点的中点）
        local midPX = (playerWeapon.rootX + playerWeapon.tipX) / 2
        local midPY = (playerWeapon.rootY + playerWeapon.tipY) / 2
        local midDX = (dw.rootX + dw.tipX) / 2
        local midDY = (dw.rootY + dw.tipY) / 2
        weaponClashX_ = (midPX + midDX) / 2
        weaponClashY_ = (midPY + midDY) / 2
        weaponClashAnim_ = 1.0
        
        -- 力的反馈：玩家被弹开（木桩武器的 force 反作用于玩家）
        local pushDir = player_.facingRight and -1 or 1
        player_.vx = pushDir * dw.force * physScale_ * 8
        player_.vy = -dw.force * physScale_ * 3
        player_.onGround = false
        
        -- 同时木桩受到力的反馈（被推的方向）
        dummy_.hitAnim = 0.6
        dummy_.hitDir = playerWeapon.forceDir
        
        -- 特效文字
        hitEffects_[#hitEffects_ + 1] = {
            x = weaponClashX_,
            y = weaponClashY_ - 20,
            text = "格挡!",
            timer = 1.0,
            color = { 255, 200, 80 },
        }
        
        -- 材质效果：thorns（反震）- 格挡时对木桩造成反伤
        local mat = gameData_ and gameData_.material or nil
        if mat and mat.effect == "thorns" then
            local thornsDmg = 100
            dummy_.hp = math.max(0, dummy_.hp - thornsDmg)
            hitEffects_[#hitEffects_ + 1] = {
                x = dummy_.x,
                y = dummy_.y - (dummy_.height or 60) * 0.7,
                text = "反伤-" .. thornsDmg,
                timer = 1.2,
                color = { 255, 160, 50 },
            }
            print("[WeaponClash] Thorns triggered! Dummy takes " .. thornsDmg .. " damage")
        end
        
        -- 进入弹开状态（武器不直接消失，被弹向对方挥动方向）
        deflecting_ = true
        deflectTimer_ = 0
        -- 弹开起点 = 碰撞点
        deflectStartX_ = weaponClashX_
        deflectStartY_ = weaponClashY_
        -- 弹开方向 = 木桩武器挥动方向（对方挥动方向）
        deflectAngle_ = dw.angle
        -- 武器当前角度（用于渲染旋转中的武器）
        local dir = player_.facingRight and 1 or -1
        deflectWeaponAngle_ = dir * math.pi / 4  -- 近似挥砍角度
        -- 旋转速度：快速旋转表示被弹飞
        deflectSpin_ = dir * (-12)  -- 反方向旋转
        -- 中断攻击逻辑（但保留渲染数据用于弹开动画）
        attacking_ = false
        currentAttack_ = nil
        
        print("[WeaponClash] Weapons collided! Weapon deflected with force: " .. dw.force)
    end
end

--- 更新武器碰撞系统（动画衰减、冷却、弹开动画）
UpdateWeaponClash = function(dt)
    if weaponClashAnim_ > 0 then
        weaponClashAnim_ = weaponClashAnim_ - dt * 3
    end
    if weaponClashCooldown_ > 0 then
        weaponClashCooldown_ = weaponClashCooldown_ - dt
    end
    -- 弹开动画更新
    if deflecting_ then
        deflectTimer_ = deflectTimer_ + dt
        if deflectTimer_ >= deflectDuration_ then
            deflecting_ = false
            deflectTimer_ = 0
        end
    end
end

return TrialState
