-- ============================================================================
-- States/TrialState.lua - 试炼场（横版）
-- 横版动作：左右移动 + 跳跃 + 武器攻击
-- PC: AD/方向键移动, 空格跳跃, 鼠标/J键攻击, Q键变形
-- 移动端: 左侧方向按钮, 右侧跳跃+攻击按钮, 左下变形按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")

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
local attackIndex_ = 1
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

-- 主角贴图
local playerImage_ = nil

-- UI 引用
local uiRoot_ = nil

--- 进入试炼状态
function TrialState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    
    screenW_ = graphics:GetWidth() / graphics:GetDPR()
    screenH_ = graphics:GetHeight() / graphics:GetDPR()
    
    -- 地面位置
    groundY_ = screenH_ * Config.Trial.GroundY
    
    -- 初始化玩家
    player_.width = Config.Trial.PlayerWidth
    player_.height = Config.Trial.PlayerHeight
    player_.x = screenW_ * 0.2
    player_.y = groundY_ - player_.height
    player_.vx = 0
    player_.vy = 0
    player_.onGround = true
    player_.facingRight = true
    
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
    
    -- 加载主角贴图
    playerImage_ = nvgCreateImage(NVG.Get(), Config.Trial.PlayerImage, 0)
    
    -- 生成平台和靶子
    GeneratePlatforms()
    SpawnTargets()
    
    local weaponType = gameData_.weaponData and gameData_.weaponData.type or "UNKNOWN"
    print("[TrialState] Entered. Weapon: " .. weaponType .. " Composite: " .. tostring(isComposite_))
end

--- 准备武器笔画（归一化到以原点为中心的坐标）
function PrepareWeaponStrokes()
    weaponStrokes_ = {}
    
    local strokes = gameData_.strokes
    if not strokes or #strokes == 0 then return end
    
    -- 计算所有笔画的整体包围盒
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
    
    local bw = allMaxX - allMinX
    local bh = allMaxY - allMinY
    if bw < 1 then bw = 1 end
    if bh < 1 then bh = 1 end
    
    -- 中心点
    local cx = (allMinX + allMaxX) / 2
    local cy = (allMinY + allMaxY) / 2
    
    -- 目标武器尺寸（根据攻击范围缩放）
    local targetSize = 60  -- 武器渲染目标尺寸（像素）
    weaponScale_ = targetSize / math.max(bw, bh)
    
    weaponBounds_ = { minX = allMinX, minY = allMinY, maxX = allMaxX, maxY = allMaxY }
    
    -- 归一化笔画：中心移到 (0, 0)，缩放到目标尺寸
    for i = 1, #strokes do
        local src = strokes[i]
        local normalizedPts = {}
        for j = 1, #src.points do
            normalizedPts[j] = {
                x = (src.points[j].x - cx) * weaponScale_,
                y = (src.points[j].y - cy) * weaponScale_,
            }
        end
        weaponStrokes_[i] = {
            points = normalizedPts,
            closed = src.closed,
        }
    end
    
    print("[TrialState] Weapon strokes: " .. #weaponStrokes_ .. " | Scale: " .. string.format("%.2f", weaponScale_))
end

--- 设置变形系统
function SetupTransformSystem()
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
    
    attackIndex_ = 1
    attacking_ = false
    currentAttack_ = nil
end

--- 根据主武器类型获取互补类型
function GetComplementaryType(primary)
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
function DoTransform()
    if not isComposite_ then return end
    if attacking_ then return end  -- 攻击中不可变形
    
    -- 切换形态
    currentForm_ = currentForm_ == 1 and 2 or 1
    attacks_ = formAttacks_[currentForm_]
    attackIndex_ = 1
    transformAnim_ = 1.0  -- 触发变形动画
    
    -- 更新 HUD
    local formLabel = uiRoot_ and uiRoot_:FindById("trialFormLabel")
    if formLabel then
        formLabel:SetText("形态: " .. formNames_[currentForm_])
    end
    
    print("[TrialState] Transform! Now form " .. currentForm_ .. ": " .. formNames_[currentForm_])
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
end

--- 生成平台
function GeneratePlatforms()
    platforms_ = {}
    local pw = Config.Trial.PlatformWidth
    local ph = Config.Trial.PlatformHeight
    local count = Config.Trial.PlatformCount
    
    for i = 1, count do
        local px = screenW_ * (0.2 + 0.6 * (i - 1) / (count - 1 + 0.001))
        local py = groundY_ - 80 - (i % 2 == 0 and 60 or 0) - math.random(0, 30)
        platforms_[#platforms_ + 1] = {
            x = px - pw / 2,
            y = py,
            w = pw,
            h = ph,
        }
    end
end

--- 生成靶子
function SpawnTargets()
    targets_ = {}
    local margin = 50
    for i = 1, Config.Trial.TargetCount do
        local size = Config.Trial.TargetMinSize + math.random() * (Config.Trial.TargetMaxSize - Config.Trial.TargetMinSize)
        local tx, ty
        if i <= #platforms_ and math.random() > 0.3 then
            local p = platforms_[i]
            tx = p.x + p.w / 2 + math.random(-20, 20)
            ty = p.y - size - 5
        else
            tx = margin + math.random() * (screenW_ - margin * 2)
            ty = groundY_ - size - math.random(5, 80)
        end
        targets_[#targets_ + 1] = {
            x = tx, y = ty,
            size = size,
            alive = true,
            hitAnim = 0,
            spawnAnim = 1.0,
            knockX = 0, knockY = 0,
        }
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
                        text = isComposite_ and "AD移动|空格跳|J攻击|Q变形" or "AD移动|空格跳|J攻击",
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
    UpdateCombo(dt)
    UpdateHitEffects(dt)
    UpdateTransformAnim(dt)
    CheckWaveClear()
    UpdateHUD()
end

--- 读取输入状态
function UpdateInput()
    inputLeft_ = input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT)
    inputRight_ = input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT)
end

--- 玩家物理（横版重力）
function UpdatePlayerPhysics(dt)
    local speed = Config.Trial.MoveSpeed
    if attacking_ then speed = speed * 0.5 end
    
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
        player_.vy = player_.vy + Config.Trial.Gravity * dt
        if player_.vy > Config.Trial.MaxFallSpeed then
            player_.vy = Config.Trial.MaxFallSpeed
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
    
    -- 平台碰撞（仅下落时）
    if player_.vy >= 0 then
        for i = 1, #platforms_ do
            local p = platforms_[i]
            local playerBottom = player_.y + player_.height
            local prevBottom = playerBottom - player_.vy * dt
            if player_.x + player_.width > p.x and player_.x < p.x + p.w then
                if prevBottom <= p.y + 2 and playerBottom >= p.y then
                    player_.y = p.y - player_.height
                    player_.vy = 0
                    player_.onGround = true
                    break
                end
            end
        end
    end
    
    player_.x = math.max(0, math.min(screenW_ - player_.width, player_.x))
end

--- 跳跃
function DoJump()
    if player_.onGround then
        player_.vy = Config.Trial.JumpVelocity
        player_.onGround = false
    end
end

--- 发起攻击
function StartAttack()
    if attacking_ then return end
    if #attacks_ == 0 then return end
    
    currentAttack_ = attacks_[attackIndex_]
    attackIndex_ = attackIndex_ + 1
    if attackIndex_ > #attacks_ then attackIndex_ = 1 end
    
    attacking_ = true
    attackTimer_ = 0
    attackDuration_ = currentAttack_.duration
    attackHitTargets_ = {}
end

--- 攻击更新
function UpdateAttack(dt)
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
        local chargeDist = (currentAttack_.chargeDistance or 40) * dt / attackDuration_
        player_.x = player_.x + dir * chargeDist
    end
    
    CheckAttackCollision(progress)
end

--- 碰撞检测
function CheckAttackCollision(progress)
    if not currentAttack_ then return end
    
    local atk = currentAttack_
    local dir = player_.facingRight and 1 or -1
    local originX = player_.x + player_.width / 2 + dir * 10
    local originY = player_.y + player_.height * 0.4
    local range = atk.range
    
    if atk.isThrust then
        local thrustLen = GetThrustLength(progress)
        local tipX = originX + dir * thrustLen
        local tipY = originY
        
        for i = 1, #targets_ do
            local t = targets_[i]
            if t.alive and not attackHitTargets_[i] then
                local dist = PointToSegmentDist(t.x, t.y, originX, originY, tipX, tipY)
                if dist < t.size / 2 + 12 then
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
                if dist < range + t.size / 2 then
                    local inFront = (dir > 0 and dx > -20) or (dir < 0 and dx < 20)
                    local vertOk = math.abs(dy) < range * 0.8
                    if inFront and vertOk then
                        HitTarget(i, t, atk, dir)
                    end
                end
            end
        end
    end
end

--- 突刺延伸长度
function GetThrustLength(progress)
    if not currentAttack_ then return 60 end
    local len = currentAttack_.range
    if progress < 0.3 then
        return len * (progress / 0.3)
    elseif progress < 0.7 then
        return len
    else
        return len * (1.0 - (progress - 0.7) / 0.3)
    end
end

--- 命中靶子
function HitTarget(index, target, atk, dir)
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
function PointToSegmentDist(px, py, ax, ay, bx, by)
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
function UpdateTargets(dt)
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
end

--- 连击衰减
function UpdateCombo(dt)
    if combo_ > 0 then
        comboTimer_ = comboTimer_ + dt
        if comboTimer_ >= Config.Trial.ComboDecayTime then
            combo_ = 0
            comboTimer_ = 0
        end
    end
end

--- 命中特效更新
function UpdateHitEffects(dt)
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
function UpdateTransformAnim(dt)
    if transformAnim_ > 0 then
        transformAnim_ = math.max(0, transformAnim_ - dt * 3)
    end
end

--- 检查波次清场
function CheckWaveClear()
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
function UpdateHUD()
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
    elseif key == KEY_J or key == KEY_K then
        StartAttack()
    elseif key == KEY_Q then
        DoTransform()
    end
end

function TrialState.OnMouseDown(button)
    if button == MOUSEB_LEFT then
        StartAttack()
    end
end

function TrialState.OnMouseUp(button)
end

function TrialState.OnMouseMove()
end

function TrialState.OnTouchBegin(x, y)
    local dpr = graphics:GetDPR()
    local tx = x / dpr
    
    if tx > screenW_ * 0.6 then
        StartAttack()
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
    
    screenW_ = w / dpr
    screenH_ = h / dpr
    groundY_ = screenH_ * Config.Trial.GroundY
    
    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)
    
    RenderBackground(vg)
    RenderPlatforms(vg)
    RenderGround(vg)
    RenderTargets(vg)
    RenderAttack(vg)
    RenderPlayer(vg)
    RenderHitEffects(vg)
    RenderCombo(vg)
    RenderTransformEffect(vg)
    
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

--- 背景渐变
function RenderBackground(vg)
    local bgPaint = nvgLinearGradient(vg, 0, 0, 0, screenH_,
        nvgRGBA(30, 35, 60, 255),
        nvgRGBA(60, 50, 80, 255))
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
function RenderGround(vg)
    local groundPaint = nvgLinearGradient(vg, 0, groundY_, 0, screenH_,
        nvgRGBA(60, 80, 50, 255),
        nvgRGBA(40, 55, 35, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, groundY_, screenW_, screenH_ - groundY_)
    nvgFillPaint(vg, groundPaint)
    nvgFill(vg)
    
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, groundY_)
    nvgLineTo(vg, screenW_, groundY_)
    nvgStrokeColor(vg, nvgRGBA(90, 120, 70, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

--- 平台
function RenderPlatforms(vg)
    for i = 1, #platforms_ do
        local p = platforms_[i]
        nvgBeginPath(vg)
        nvgRoundedRect(vg, p.x, p.y, p.w, p.h, 4)
        nvgFillColor(vg, nvgRGBA(80, 70, 60, 230))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, p.x + 2, p.y)
        nvgLineTo(vg, p.x + p.w - 2, p.y)
        nvgStrokeColor(vg, nvgRGBA(140, 130, 110, 200))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 渲染靶子
function RenderTargets(vg)
    for i = 1, #targets_ do
        local t = targets_[i]
        local tx = t.x + t.knockX
        local ty = t.y + t.knockY
        
        if t.alive then
            local scale = 1.0 - math.max(0, t.spawnAnim) * 0.5
            local sz = t.size * scale
            
            nvgBeginPath(vg)
            nvgRoundedRect(vg, tx - sz * 0.4, ty - sz, sz * 0.8, sz * 2, 3)
            nvgFillColor(vg, nvgRGBA(140, 90, 50, 230))
            nvgFill(vg)
            
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, sz * 0.3)
            nvgFillColor(vg, nvgRGBA(200, 60, 60, 200))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, tx, ty, sz * 0.15)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgFill(vg)
            
        elseif t.hitAnim > 0 then
            local alpha = math.floor(t.hitAnim * 200)
            local expand = (1 - t.hitAnim) * 30
            for a = 0, 4 do
                local angle = a * math.pi * 2 / 5 + t.hitAnim * 3
                local fx = tx + math.cos(angle) * expand
                local fy = ty + math.sin(angle) * expand
                nvgBeginPath(vg)
                nvgRect(vg, fx - 4, fy - 4, 8, 8)
                nvgFillColor(vg, nvgRGBA(180, 120, 60, alpha))
                nvgFill(vg)
            end
        end
    end
end

--- 渲染攻击效果（使用玩家绘制的武器形状）
function RenderAttack(vg)
    if not attacking_ or not currentAttack_ then return end
    
    local atk = currentAttack_
    local progress = attackTimer_ / attackDuration_
    local dir = player_.facingRight and 1 or -1
    local originX = player_.x + player_.width / 2 + dir * 10
    local originY = player_.y + player_.height * 0.4
    local wc = gameData_.weaponData and gameData_.weaponData.typeInfo.color or {200, 200, 200}
    
    if atk.isThrust then
        -- 突刺：武器沿水平方向延伸
        local len = GetThrustLength(progress)
        local tipX = originX + dir * len
        local tipY = originY
        
        -- 渲染玩家绘制的武器形状（旋转90度作为刺击）
        local weaponAngle = player_.facingRight and 0 or math.pi
        RenderWeaponShape(vg, originX + dir * len * 0.5, originY, weaponAngle, wc, 0.8)
        
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
        nvgCircle(vg, tipX, tipY, 4 * (1 - progress))
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(200 * (1 - progress))))
        nvgFill(vg)
    else
        -- 挥动：武器绕原点旋转
        local range = atk.range
        local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
        local arcDir = (atk.direction or 1)
        local startAngle = math.rad(atk.startAngle or -60)
        local sweep = math.rad(atk.arc) * arcDir * easedProgress
        
        local baseAngle = player_.facingRight and 0 or math.pi
        local currentAngle = baseAngle + (startAngle + sweep) * dir
        
        local tipX = originX + math.cos(currentAngle) * range
        local tipY = originY + math.sin(currentAngle) * range
        
        -- 挥动轨迹（半透明扇形）
        local trailAlpha = math.floor((1 - progress) * 40)
        nvgBeginPath(vg)
        nvgMoveTo(vg, originX, originY)
        local steps = 10
        for s = 0, steps do
            local t = easedProgress * s / steps
            local a = baseAngle + (startAngle + math.rad(atk.arc) * arcDir * t) * dir
            nvgLineTo(vg, originX + math.cos(a) * range, originY + math.sin(a) * range)
        end
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(wc[1], wc[2], wc[3], trailAlpha))
        nvgFill(vg)
        
        -- 渲染玩家绘制的武器形状（在尖端位置，朝攻击方向旋转）
        local weaponAngle = currentAngle - math.pi / 2  -- 武器尖端朝外
        local weaponX = originX + math.cos(currentAngle) * range * 0.6
        local weaponY = originY + math.sin(currentAngle) * range * 0.6
        RenderWeaponShape(vg, weaponX, weaponY, weaponAngle, wc, 1.0)
        
        -- 刃尖光芒
        local glowAlpha = math.floor(180 * (1 - progress))
        nvgBeginPath(vg)
        nvgCircle(vg, tipX, tipY, 5 * (1 - progress * 0.5))
        nvgFillColor(vg, nvgRGBA(255, 255, 255, glowAlpha))
        nvgFill(vg)
    end
end

--- 渲染玩家绘制的武器形状
--- @param vg userdata NanoVG上下文
--- @param cx number 中心X
--- @param cy number 中心Y
--- @param angle number 旋转角度（弧度）
--- @param color table 颜色 {r, g, b}
--- @param scale number 额外缩放
function RenderWeaponShape(vg, cx, cy, angle, color, scale)
    if #weaponStrokes_ == 0 then
        -- 无笔画时：渲染默认武器线条
        RenderDefaultWeapon(vg, cx, cy, angle, color)
        return
    end
    
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)
    nvgScale(vg, scale, scale)
    
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
function RenderDefaultWeapon(vg, cx, cy, angle, color)
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

--- 渲染玩家
function RenderPlayer(vg)
    local px = player_.x
    local py = player_.y
    local pw = player_.width
    local ph = player_.height
    
    if playerImage_ and playerImage_ ~= 0 then
        nvgSave(vg)
        if not player_.facingRight then
            nvgTranslate(vg, px + pw, py)
            nvgScale(vg, -1, 1)
        else
            nvgTranslate(vg, px, py)
        end
        
        local imgPaint = nvgImagePattern(vg, 0, 0, pw, ph, 0, playerImage_, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, pw, ph)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgRestore(vg)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py, pw, ph, 4)
        nvgFillColor(vg, nvgRGBA(80, 160, 255, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
    
    -- 方向指示
    local dir = player_.facingRight and 1 or -1
    local cx = px + pw / 2 + dir * (pw / 2 + 5)
    local cy = py + ph * 0.4
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx + dir * 6, cy)
    nvgLineTo(vg, cx, cy - 4)
    nvgLineTo(vg, cx, cy + 4)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 150))
    nvgFill(vg)
end

--- 命中特效渲染
function RenderHitEffects(vg)
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
function RenderCombo(vg)
    if combo_ < 2 then return end
    
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    
    nvgFontFaceId(vg, fontId)
    local size = math.min(32, 16 + combo_ * 2)
    local pulse = 1.0 + math.sin(comboTimer_ * 8) * 0.08
    nvgFontSize(vg, size * pulse)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    
    local alpha = math.floor(255 * math.max(0, 1.0 - comboTimer_ / Config.Trial.ComboDecayTime))
    nvgFillColor(vg, nvgRGBA(255, 200, 50, alpha))
    nvgText(vg, screenW_ / 2, 45, combo_ .. " COMBO!", nil)
end

--- 变形特效渲染
function RenderTransformEffect(vg)
    if transformAnim_ <= 0 then return end
    
    local alpha = math.floor(transformAnim_ * 200)
    local expand = (1 - transformAnim_) * 40
    local cx = player_.x + player_.width / 2
    local cy = player_.y + player_.height / 2
    
    -- 变形光环
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 20 + expand)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 50, alpha))
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
        nvgFillColor(vg, nvgRGBA(255, 220, 80, alpha))
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
            nvgFillColor(vg, nvgRGBA(255, 220, 80, textAlpha))
            nvgText(vg, cx, cy - 35, formNames_[currentForm_], nil)
        end
    end
end

return TrialState
