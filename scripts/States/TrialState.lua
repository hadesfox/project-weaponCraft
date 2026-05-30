-- ============================================================================
-- States/TrialState.lua - 试炼场（横版）
-- 横版动作：左右移动 + 跳跃 + 武器攻击
-- PC: AD/方向键移动, 空格跳跃, 鼠标/J键攻击, Q键变形
-- 移动端: 左侧方向按钮, 右侧跳跃+攻击按钮, 左下变形按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local Slime = require("Trial.Slime")

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
local RenderBackground
local RenderGround
local RenderPlatforms
local RenderTargets
local RenderDummy
local RenderAttack
local RenderThrustAttack
local RenderSwingAttack
local RenderWeaponShape
local RenderDefaultWeapon
local RenderPlayer
local CalcPlayerAnimParams
local RenderPlayerSprite
local RenderRunDust
local RenderHitEffects
local RenderCombo
local RenderTransformEffect

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
    
    -- 处理武器绘图数据（归一化笔画）
    PrepareWeaponStrokes()
    
    -- 初始化变形系统
    SetupTransformSystem()
    
    -- 初始化分数
    score_ = 0
    combo_ = 0
    comboTimer_ = 0
    hitEffects_ = {}
    
    -- 输入重置
    inputLeft_ = false
    inputRight_ = false
    
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
        -- 形态一：主武器类型
        formAttacks_[1] = Config.Attacks[weaponType] or Config.Attacks.UNKNOWN
        formNames_[1] = (Config.WeaponTypes[weaponType] or Config.WeaponTypes.UNKNOWN).name
        
        -- 形态二：根据主类型确定互补类型
        local secondType = GetComplementaryType(weaponType)
        formAttacks_[2] = Config.Attacks[secondType] or Config.Attacks.UNKNOWN
        formNames_[2] = (Config.WeaponTypes[secondType] or Config.WeaponTypes.UNKNOWN).name
        
        -- 默认使用形态一
        attacks_ = formAttacks_[1]
        
        print("[TrialState] Composite! Form1: " .. formNames_[1] .. " Form2: " .. formNames_[2])
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
    
    -- 木桩（尺寸按 physScale_ 缩放）
    dummy_ = {
        x = screenW_ * dummyDef_.rx,
        y = groundY_,
        width = dummyDef_.baseW * physScale_,
        height = dummyDef_.baseH * physScale_,
        hitAnim = dummy_ and dummy_.hitAnim or 0,
        hitDir = dummy_ and dummy_.hitDir or 0,
        hp = 999,
    }
end

--- 生成靶子（使用比例坐标）
SpawnTargets = function()
    targets_ = {}
    targetDefs_ = {}
    local arenaH = groundY_
    
    for i = 1, Config.Trial.TargetCount do
        local baseSize = Config.Trial.TargetMinSize + math.random() * (Config.Trial.TargetMaxSize - Config.Trial.TargetMinSize)
        local size = baseSize * physScale_
        local rx, ry
        if i <= #platformDefs_ and math.random() > 0.3 then
            local pdef = platformDefs_[i]
            rx = pdef.rx + pdef.rw / 2 + (math.random() - 0.5) * 0.04
            ry = pdef.ry + size / arenaH + 0.01
        else
            -- 地面敌人：直接贴地（ry=0 表示站在地面线上）
            rx = 0.05 + math.random() * 0.9
            ry = 0
        end
        -- platformRy: 该敌人所站平台的 ry（用于渲染贴地），地面敌人为 0
        local platformRy = 0
        if ry ~= 0 and i <= #platformDefs_ then
            platformRy = platformDefs_[i].ry
        end
        targetDefs_[i] = { rx = rx, ry = ry, baseSize = baseSize, isGround = (ry == 0), platformRy = platformRy }
        local ty = groundY_ - arenaH * ry
        -- 地面敌人：碰撞中心对齐贴图视觉中心（贴图可见区域中心在地面线上方 size*0.8）
        if ry == 0 then
            ty = groundY_ - size * 0.8
        end
        targets_[i] = {
            x = screenW_ * rx,
            y = ty,
            size = size,
            hitRadius = (ry == 0) and (size * 0.8) or (size / 2),  -- 地面敌人碰撞半径匹配贴图宽度
            alive = true,
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
            -- 地面敌人：碰撞中心对齐贴图视觉中心
            if def.isGround then
                ty = groundY_ - size * 0.8
            end
            targets_[i].x = screenW_ * def.rx
            targets_[i].y = ty
            targets_[i].size = size
            targets_[i].hitRadius = def.isGround and (size * 0.8) or (size / 2)
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
    UpdateInput()
    UpdatePlayerPhysics(dt)
    UpdateAttack(dt)
    UpdateTargets(dt)
    Slime.Update(dt, player_)
    UpdateCombo(dt)
    UpdateHitEffects(dt)
    UpdateTransformAnim(dt)
    CheckWaveClear()
    UpdateHUD()
end

--- 读取输入状态
UpdateInput = function()
    inputLeft_ = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    inputRight_ = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
end

--- 玩家物理（横版重力）
UpdatePlayerPhysics = function(dt)
    local speed = Config.Trial.MoveSpeed * physScale_
    if attacking_ then speed = 0 end  -- 攻击时不能移动，避免惯性前冲
    
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
    
    -- 平台碰撞（仅下落时或静止站立时）
    if player_.vy >= 0 then
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

--- 跳跃
DoJump = function()
    if player_.onGround then
        player_.vy = Config.Trial.JumpVelocity * physScale_
        player_.onGround = false
        player_.landSquash = 0  -- 跳跃时立刻取消着地动画
    end
end

--- 发起攻击
--- @param index number|nil 攻击索引（1=左键招式, 2=右键招式），nil时默认为1
StartAttack = function(index)
    if attacking_ then return end
    if #attacks_ == 0 then return end
    
    local idx = index or 1
    if idx > #attacks_ then idx = 1 end
    
    currentAttack_ = attacks_[idx]
    attacking_ = true
    attackTimer_ = 0
    attackDuration_ = currentAttack_.duration
    attackHitTargets_ = {}
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
    
    -- 检测木桩碰撞
    CheckDummyCollision(progress)
end

--- 检测木桩碰撞
CheckDummyCollision = function(progress)
    if not dummy_ or not currentAttack_ then return end
    if dummy_.hitAnim > 0.5 then return end  -- 受击冷却中
    
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
        dummy_.hitAnim = 1.0
        dummy_.hitDir = dir
        -- 命中特效
        hitEffects_[#hitEffects_ + 1] = {
            x = dCx, y = dCy,
            text = "Hit!",
            timer = 0.8,
            color = {200, 200, 200},
        }
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

--- 命中靶子
HitTarget = function(index, target, atk, dir)
    attackHitTargets_[index] = true
    target.alive = false
    target.hitAnim = 1.0
    
    local kb = atk.knockback or 8
    target.knockX = dir * math.abs(kb)
    target.knockY = -math.abs(kb) * 0.5
    
    combo_ = combo_ + 1
    comboTimer_ = 0
    local points = Config.Trial.ComboMultiplier * combo_
    score_ = score_ + points
    
    hitEffects_[#hitEffects_ + 1] = {
        x = target.x, y = target.y,
        text = "+" .. points,
        timer = 1.0,
        color = combo_ >= 5 and Config.Colors.Gold or Config.Colors.Success,
    }
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
end

-- ============================================================================
-- 输入事件
-- ============================================================================

function TrialState.OnKeyDown(key)
    if key == KEY_SPACE or key == KEY_W or key == KEY_UP then
        DoJump()
    elseif key == KEY_J then
        StartAttack(1)  -- J键 = 招式1（同左键）
    elseif key == KEY_K then
        StartAttack(2)  -- K键 = 招式2（同右键）
    elseif key == KEY_Q then
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
-- NanoVG 渲染
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
    
    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)
    
    RenderBackground(vg)
    RenderPlatforms(vg)
    RenderGround(vg)
    RenderTargets(vg)
    RenderDummy(vg)
    RenderAttack(vg)
    Slime.Render(vg, player_)
    RenderHitEffects(vg)
    RenderCombo(vg)
    RenderTransformEffect(vg)
    
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

--- 背景渐变
RenderBackground = function(vg)
    local bgPaint = nvgLinearGradient(vg, 0, 0, 0, screenH_,
        nvgRGBA(20, 22, 28, 255),
        nvgRGBA(50, 50, 55, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW_, screenH_)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)
    
    -- 远景星星
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 60))
    for i = 1, 8 do
        nvgBeginPath(vg)
        local sx = (i * 97 + 30) % math.floor(screenW_)
        local sy = (i * 53 + 10) % math.floor(screenH_ * 0.5)
        nvgCircle(vg, sx, sy, 1.5)
        nvgFill(vg)
    end
end

--- 地面
RenderGround = function(vg)
    local groundPaint = nvgLinearGradient(vg, 0, groundY_, 0, screenH_,
        nvgRGBA(40, 38, 35, 255),
        nvgRGBA(20, 22, 28, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, groundY_, screenW_, screenH_ - groundY_)
    nvgFillPaint(vg, groundPaint)
    nvgFill(vg)
    
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, groundY_)
    nvgLineTo(vg, screenW_, groundY_)
    nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

--- 平台
RenderPlatforms = function(vg)
    for i = 1, #platforms_ do
        local p = platforms_[i]
        nvgBeginPath(vg)
        nvgRoundedRect(vg, p.x, p.y, p.w, p.h, 4)
        nvgFillColor(vg, nvgRGBA(45, 42, 38, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(70, 60, 45, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 平台顶部高光线
        nvgBeginPath(vg)
        nvgMoveTo(vg, p.x + 2, p.y)
        nvgLineTo(vg, p.x + p.w - 2, p.y)
        nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 渲染靶子（哥布林）
RenderTargets = function(vg)
    for i = 1, #targets_ do
        local t = targets_[i]
        local tx = t.x + t.knockX
        local ty = t.y + t.knockY
        
        if t.alive then
            local scale = 1.0 - math.max(0, t.spawnAnim) * 0.5
            local sz = t.size * scale
            local imgW = sz * 1.6
            local imgH = sz * 2.0
            
            if enemyImage_ and enemyImage_ ~= 0 then
                -- 贴图底部对齐敌人站立面（平台表面）
                local def = targetDefs_[i]
                local standY  -- 敌人脚底位置（平台/地面表面）
                if def and def.isGround then
                    standY = groundY_
                else
                    -- 平台敌人：直接使用平台表面 Y 坐标
                    standY = groundY_ - groundY_ * (def and def.platformRy or 0)
                end
                local imgY = standY - imgH * 0.80
                local imgPaint = nvgImagePattern(vg, tx - imgW / 2, imgY, imgW, imgH, 0, enemyImage_, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, tx - imgW / 2, imgY, imgW, imgH)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                -- 无图时的备用矩形
                nvgBeginPath(vg)
                nvgRoundedRect(vg, tx - sz * 0.4, ty - sz, sz * 0.8, sz * 2, 3)
                nvgFillColor(vg, nvgRGBA(50, 50, 55, 230))
                nvgFill(vg)
            end
            
        elseif t.hitAnim > 0 then
            -- 死亡碎片效果（炭火红）
            local alpha = math.floor(t.hitAnim * 200)
            local expand = (1 - t.hitAnim) * 30
            for a = 0, 4 do
                local angle = a * math.pi * 2 / 5 + t.hitAnim * 3
                local fx = tx + math.cos(angle) * expand
                local fy = ty + math.sin(angle) * expand
                nvgBeginPath(vg)
                nvgRect(vg, fx - 4, fy - 4, 8, 8)
                nvgFillColor(vg, nvgRGBA(200, 80, 40, alpha))
                nvgFill(vg)
            end
        end
    end
end

--- 渲染木桩
RenderDummy = function(vg)
    if not dummy_ then return end
    
    local dx = dummy_.x
    local dy = dummy_.y
    local dw = dummy_.width
    local dh = dummy_.height
    
    -- 受击晃动偏移
    local shakeX = 0
    if dummy_.hitAnim > 0 then
        shakeX = math.sin(dummy_.hitAnim * 20) * 4 * dummy_.hitAnim * dummy_.hitDir
    end
    
    -- 木桩主体（圆柱形木桩）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx - dw / 2 + shakeX, dy - dh, dw, dh, 4)
    nvgFillColor(vg, nvgRGBA(50, 50, 55, 240))
    nvgFill(vg)
    
    -- 木纹
    nvgStrokeColor(vg, nvgRGBA(150, 200, 255, 150))
    nvgStrokeWidth(vg, 1)
    for i = 1, 3 do
        local ly = dy - dh * i / 4
        nvgBeginPath(vg)
        nvgMoveTo(vg, dx - dw / 2 + 3 + shakeX, ly)
        nvgLineTo(vg, dx + dw / 2 - 3 + shakeX, ly)
        nvgStroke(vg)
    end
    
    -- 顶部横梁（靶标区域）
    local armW = 36 * physScale_
    local armH = 8 * physScale_
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx - armW / 2 + shakeX, dy - dh - armH / 2, armW, armH, 3)
    nvgFillColor(vg, nvgRGBA(50, 50, 55, 240))
    nvgFill(vg)
    
    -- 受击闪光
    if dummy_.hitAnim > 0.5 then
        local alpha = math.floor((dummy_.hitAnim - 0.5) * 2 * 200)
        nvgBeginPath(vg)
        nvgCircle(vg, dx + shakeX, dy - dh / 2, 20 * physScale_)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, alpha))
        nvgFill(vg)
    end
    
    -- 底座
    nvgBeginPath(vg)
    nvgRoundedRect(vg, dx - dw * 0.8 + shakeX, dy - 6 * physScale_, dw * 1.6, 6 * physScale_, 2)
    nvgFillColor(vg, nvgRGBA(20, 22, 28, 240))
    nvgFill(vg)
    
    -- 标签
    local fontId = NVG.GetFont()
    if fontId ~= -1 then
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 10 * physScale_)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, 200))
        nvgText(vg, dx + shakeX, dy - dh - 10 * physScale_, "木桩", nil)
    end
end

--- 渲染突刺攻击（武器沿水平方向延伸）
RenderThrustAttack = function(vg, atk, progress, originX, originY, wc)
    local dir = player_.facingRight and 1 or -1
    local len = GetThrustLength(progress)
    local tipX = originX + dir * len
    local tipY = originY

    -- 武器形状（尖端朝刺出方向）
    local weaponAngle = player_.facingRight and (math.pi / 2) or (-math.pi / 2)
    local flipX = not player_.facingRight
    RenderWeaponShape(vg, originX + dir * len * 0.5, originY, weaponAngle, wc, 0.8 * physScale_, flipX)

    -- 突刺轨迹线
    nvgBeginPath(vg)
    nvgMoveTo(vg, originX, originY)
    nvgLineTo(vg, tipX, tipY)
    nvgStrokeColor(vg, nvgRGBA(wc[1], wc[2], wc[3], 120))
    nvgStrokeWidth(vg, 3)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 尖端闪光
    nvgBeginPath(vg)
    nvgCircle(vg, tipX, tipY, 4 * (1 - progress) * physScale_)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(200 * (1 - progress))))
    nvgFill(vg)
end

--- 渲染挥动攻击（武器绕原点旋转）
RenderSwingAttack = function(vg, atk, progress, originX, originY, wc)
    local range = atk.range * physScale_
    local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
    local arcDir = (atk.direction or 1)
    local startAngle = math.rad(atk.startAngle or -60)
    local sweepAngle = math.rad(atk.arc) * arcDir * easedProgress

    -- 角度计算：朝右从startAngle顺时针扫；朝左镜像
    local currentAngle
    if player_.facingRight then
        currentAngle = startAngle + sweepAngle
    else
        currentAngle = math.pi - (startAngle + sweepAngle)
    end

    local tipX = originX + math.cos(currentAngle) * range
    local tipY = originY + math.sin(currentAngle) * range

    -- 挥动轨迹（半透明扇形）
    local trailAlpha = math.floor((1 - progress) * 40)
    nvgBeginPath(vg)
    nvgMoveTo(vg, originX, originY)
    local steps = 10
    for s = 0, steps do
        local t = easedProgress * s / steps
        local a
        if player_.facingRight then
            a = startAngle + math.rad(atk.arc) * arcDir * t
        else
            a = math.pi - (startAngle + math.rad(atk.arc) * arcDir * t)
        end
        nvgLineTo(vg, originX + math.cos(a) * range, originY + math.sin(a) * range)
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(wc[1], wc[2], wc[3], trailAlpha))
    nvgFill(vg)

    -- 武器形状（刃面朝外、柄面朝自己）
    local weaponAngle = currentAngle + math.pi / 2
    local weaponX = originX + math.cos(currentAngle) * range * 0.6
    local weaponY = originY + math.sin(currentAngle) * range * 0.6
    local flipX = not player_.facingRight
    RenderWeaponShape(vg, weaponX, weaponY, weaponAngle, wc, 1.0 * physScale_, flipX)

    -- 刃尖光芒
    local glowAlpha = math.floor(180 * (1 - progress))
    nvgBeginPath(vg)
    nvgCircle(vg, tipX, tipY, 5 * (1 - progress * 0.5) * physScale_)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, glowAlpha))
    nvgFill(vg)
end

--- 渲染攻击效果（入口分派）
RenderAttack = function(vg)
    if not attacking_ or not currentAttack_ then return end

    local atk = currentAttack_
    local progress = attackTimer_ / attackDuration_
    local dir = player_.facingRight and 1 or -1
    local originX = player_.x + player_.width / 2 + dir * 10 * physScale_
    local originY = player_.y + player_.height * 0.4
    local wc = gameData_.weaponData and gameData_.weaponData.typeInfo.color or {200, 200, 200}

    if atk.isThrust then
        RenderThrustAttack(vg, atk, progress, originX, originY, wc)
    else
        RenderSwingAttack(vg, atk, progress, originX, originY, wc)
    end
end

--- 渲染玩家绘制的武器形状
--- @param vg userdata NanoVG上下文
--- @param cx number 中心X
--- @param cy number 中心Y
--- @param angle number 旋转角度（弧度）
--- @param color table 颜色 {r, g, b}
--- @param scale number 额外缩放
RenderWeaponShape = function(vg, cx, cy, angle, color, scale, flipX)
    if #weaponStrokes_ == 0 then
        -- 无笔画时：渲染默认武器线条
        RenderDefaultWeapon(vg, cx, cy, angle, color)
        return
    end
    
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)
    -- flipX 时翻转 X 轴实现镜像（朝左时刃面朝外）
    if flipX then
        nvgScale(vg, -scale, scale)
    else
        nvgScale(vg, scale, scale)
    end
    
    -- 渲染所有笔画
    for i = 1, #weaponStrokes_ do
        local stroke = weaponStrokes_[i]
        local pts = stroke.points
        if #pts >= 2 then
            nvgBeginPath(vg)
            nvgMoveTo(vg, pts[1].x, pts[1].y)
            
            for j = 2, #pts do
                if j < #pts then
                    local mx = (pts[j].x + pts[j + 1].x) * 0.5
                    local my = (pts[j].y + pts[j + 1].y) * 0.5
                    nvgQuadTo(vg, pts[j].x, pts[j].y, mx, my)
                else
                    nvgLineTo(vg, pts[j].x, pts[j].y)
                end
            end
            
            if stroke.closed then
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 80))
                nvgFill(vg)
            end
            
            nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
            nvgStrokeWidth(vg, 3)
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)
        end
    end
    
    nvgRestore(vg)
end

--- 没有笔画时的默认武器渲染
RenderDefaultWeapon = function(vg, cx, cy, angle, color)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)
    
    -- 简单的剑形
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -25)
    nvgLineTo(vg, 0, 25)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
    nvgStrokeWidth(vg, 4)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
    
    -- 护手
    nvgBeginPath(vg)
    nvgMoveTo(vg, -8, 15)
    nvgLineTo(vg, 8, 15)
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
    
    nvgRestore(vg)
end

--- 计算玩家程序化动画参数（弹跳、倾斜、缩放）
--- @return number bobY, number lean, number scaleX, number scaleY
CalcPlayerAnimParams = function()
    local state = player_.state
    local t = player_.animTime
    local bobY = 0
    local lean = 0
    local scaleX = 1.0
    local scaleY = 1.0

    if state == "run" then
        bobY = math.sin(t) * 3 * physScale_
        lean = (player_.facingRight and 1 or -1) * 0.06
        local squishPhase = math.sin(t * 2)
        scaleX = 1.0 + squishPhase * 0.03
        scaleY = 1.0 - squishPhase * 0.03
    elseif state == "idle" then
        bobY = math.sin(t) * 1 * physScale_
        scaleY = 1.0 + math.sin(t) * 0.015
        scaleX = 1.0 - math.sin(t) * 0.01
    end

    -- 着地压缩回弹（弹性曲线：压缩→回弹→恢复）
    if player_.landSquash > 0 then
        local total = 0.15
        local t_norm = 1.0 - (player_.landSquash / total)
        local squash
        if t_norm < 0.35 then
            squash = (t_norm / 0.35) * 0.12
        elseif t_norm < 0.65 then
            local p = (t_norm - 0.35) / 0.3
            squash = 0.12 * (1.0 - p * 2.0)
        else
            local p = (t_norm - 0.65) / 0.35
            squash = -0.12 * (1.0 - p)
        end
        scaleX = 1.0 + squash * 0.5
        scaleY = 1.0 - squash
    end

    return bobY, lean, scaleX, scaleY
end

--- 渲染玩家精灵（含帧选择和变换）
RenderPlayerSprite = function(vg, bobY, lean, scaleX, scaleY)
    local px = player_.x
    local py = player_.y
    local pw = player_.width
    local ph = player_.height

    -- 根据状态选择当前显示帧
    local currentFrame = playerImage_
    if player_.state == "run" and #playerRunFrames_ > 0 then
        local idx = math.max(1, math.min(playerFrameIndex_, #playerRunFrames_))
        local frame = playerRunFrames_[idx]
        if frame and frame ~= 0 then
            local fw, fh = nvgImageSize(vg, frame)
            if fw > 0 and fh > 0 then
                currentFrame = frame
            end
        end
    end

    if currentFrame and currentFrame ~= 0 then
        nvgSave(vg)
        local imgSize = ph / scaleY

        local anchorX = px + pw / 2
        local anchorY = py + ph
        nvgTranslate(vg, anchorX, anchorY + bobY)
        nvgRotate(vg, lean)
        nvgScale(vg, scaleX, scaleY)
        if player_.facingRight then nvgScale(vg, -1, 1) end

        local drawX = -imgSize / 2
        local drawY = -imgSize
        local imgPaint = nvgImagePattern(vg, drawX, drawY, imgSize, imgSize, 0, currentFrame, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, drawX, drawY, imgSize, imgSize)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgRestore(vg)
    else
        -- 无图片时的备用矩形
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py + bobY, pw, ph, 4)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 渲染跑步烟尘粒子
RenderRunDust = function(vg, bobY)
    if player_.state ~= "run" or not player_.onGround then return end

    local footX = player_.x + player_.width / 2
    local footY = player_.y + player_.height + bobY
    local dustPhase = math.sin(player_.animTime + 1.5)
    if dustPhase > 0.7 then
        local alpha = math.floor((dustPhase - 0.7) / 0.3 * 80)
        local dustDir = player_.facingRight and -1 or 1
        nvgBeginPath(vg)
        nvgCircle(vg, footX + dustDir * 6 * physScale_, footY - 2 * physScale_, 3 * physScale_)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, footX + dustDir * 12 * physScale_, footY - 4 * physScale_, 2 * physScale_)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, math.floor(alpha * 0.6)))
        nvgFill(vg)
    end
end

--- 渲染玩家（入口：动画参数 → 精灵 → 烟尘）
RenderPlayer = function(vg)
    local bobY, lean, scaleX, scaleY = CalcPlayerAnimParams()
    RenderPlayerSprite(vg, bobY, lean, scaleX, scaleY)
    RenderRunDust(vg, bobY)
end

--- 命中特效渲染
RenderHitEffects = function(vg)
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    
    nvgFontFaceId(vg, fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    
    for i = 1, #hitEffects_ do
        local e = hitEffects_[i]
        local alpha = math.floor(e.timer * 255)
        local size = 14 + (1 - e.timer) * 4
        nvgFontSize(vg, size)
        nvgFillColor(vg, nvgRGBA(e.color[1], e.color[2], e.color[3], alpha))
        nvgText(vg, e.x, e.y, e.text, nil)
    end
end

--- 连击渲染
RenderCombo = function(vg)
    if combo_ < 2 then return end
    
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    
    nvgFontFaceId(vg, fontId)
    local size = math.min(32, 16 + combo_ * 2)
    local pulse = 1.0 + math.sin(comboTimer_ * 8) * 0.08
    nvgFontSize(vg, size * pulse)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    
    local alpha = math.floor(255 * math.max(0, 1.0 - comboTimer_ / Config.Trial.ComboDecayTime))
    nvgFillColor(vg, nvgRGBA(160, 140, 90, alpha))
    nvgText(vg, screenW_ / 2, 90, combo_ .. " COMBO!", nil)

end

--- 变形特效渲染
RenderTransformEffect = function(vg)
    if transformAnim_ <= 0 then return end
    
    local alpha = math.floor(transformAnim_ * 200)
    local expand = (1 - transformAnim_) * 40
    local cx = player_.x + player_.width / 2
    local cy = player_.y + player_.height / 2
    
    -- 变形光环
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 20 + expand)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 90, alpha))

    nvgStrokeWidth(vg, 3 * transformAnim_)
    nvgStroke(vg)
    
    -- 粒子
    for i = 0, 5 do
        local angle = i * math.pi * 2 / 6 + transformAnim_ * 5
        local r = 15 + expand * 0.5
        local px = cx + math.cos(angle) * r
        local py = cy + math.sin(angle) * r
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, 3 * transformAnim_)
        nvgFillColor(vg, nvgRGBA(160, 140, 90, alpha))
        nvgFill(vg)
    end
    
    -- 形态名称闪现
    if transformAnim_ > 0.5 then
        local fontId = NVG.GetFont()
        if fontId ~= -1 then
            nvgFontFaceId(vg, fontId)
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local textAlpha = math.floor((transformAnim_ - 0.5) * 2 * 255)
            nvgFillColor(vg, nvgRGBA(160, 140, 90, textAlpha))
            nvgText(vg, cx, cy - 35, formNames_[currentForm_], nil)
        end
    end
end

return TrialState
