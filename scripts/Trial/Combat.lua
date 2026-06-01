-- ============================================================================
-- Trial/Combat.lua - 战斗系统（攻击、碰撞检测、木桩AI、武器格挡）
-- 职责：管理玩家攻击流程、碰撞判定、木桩攻击AI、武器碰撞特效
-- ============================================================================

local Config = require("Config")

local Combat = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

-- 玩家攻击
local attacks_ = {}
local attacking_ = false
local attackTimer_ = 0
local attackDuration_ = 0
local currentAttack_ = nil
local attackHitTargets_ = {}
local attackHitDummy_ = false

-- 木桩AI攻击
local dummyAttacking_ = false
local dummyAttackTimer_ = 0
local dummyAttackDuration_ = 0
local dummyCurrentAttack_ = nil
local dummyAttackCooldown_ = 0
local dummyAttackProgress_ = 0
local dummyFacingRight_ = false
local dummyHitPlayer_ = false
local dummyAttacks_ = {}
local dummyMoving_ = false
local dummyVx_ = 0

local DUMMY_ATTACK_INTERVAL_MIN = 0.15
local DUMMY_ATTACK_INTERVAL_MAX = 0.35

-- 武器碰撞
local weaponClashAnim_ = 0
local weaponClashX_ = 0
local weaponClashY_ = 0
local weaponClashCooldown_ = 0

-- 格挡弹开
local deflecting_ = false
local deflectTimer_ = 0
local deflectDuration_ = 0.4
local deflectStartX_ = 0
local deflectStartY_ = 0
local deflectAngle_ = 0
local deflectSpin_ = 0
local deflectWeaponAngle_ = 0

-- 木桩武器
local dummyWeapon_ = nil

-- ============================================================================
-- 外部依赖引用（通过 Init 注入）
-- ============================================================================
local ctx_ = nil  -- 游戏上下文

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化战斗系统
--- @param ctx table 游戏上下文 { player, dummy, targets, hitEffects, getCombo, setCombo, getScore, setScore, getPhysScale, getScreenW, getGameData, getMaterialEffect, getMaterialAtkMod, getGrowthBonus, setGrowthBonus, getTotalDamage, setTotalDamage, getAttacks, isTrialEnded, getDummyAttacks }
function Combat.Init(ctx)
    ctx_ = ctx
    attacks_ = ctx.getAttacks()
    dummyAttacks_ = ctx.getDummyAttacks()
    attacking_ = false
    attackTimer_ = 0
    attackDuration_ = 0
    currentAttack_ = nil
    attackHitTargets_ = {}
    attackHitDummy_ = false
    dummyAttacking_ = false
    dummyAttackTimer_ = 0
    dummyAttackDuration_ = 0
    dummyCurrentAttack_ = nil
    dummyAttackCooldown_ = 0
    dummyAttackProgress_ = 0
    dummyFacingRight_ = false
    dummyHitPlayer_ = false
    dummyMoving_ = false
    dummyVx_ = 0
    weaponClashAnim_ = 0
    weaponClashX_ = 0
    weaponClashY_ = 0
    weaponClashCooldown_ = 0
    deflecting_ = false
    deflectTimer_ = 0
    dummyWeapon_ = nil
    Combat.InitDummyWeapon()
end

--- 重新同步攻击组（变形后调用）
function Combat.SyncAttacks()
    attacks_ = ctx_.getAttacks()
end

-- ============================================================================
-- 公开查询接口
-- ============================================================================

function Combat.IsAttacking() return attacking_ end
function Combat.GetCurrentAttack() return currentAttack_ end
function Combat.GetAttackTimer() return attackTimer_ end
function Combat.GetAttackDuration() return attackDuration_ end
function Combat.GetAttackProgress()
    if not attacking_ or attackDuration_ == 0 then return 0 end
    return attackTimer_ / attackDuration_
end
function Combat.IsDeflecting() return deflecting_ end
function Combat.GetDeflectProgress()
    if not deflecting_ then return 0 end
    return deflectTimer_ / deflectDuration_
end
function Combat.GetDeflectData()
    return {
        startX = deflectStartX_, startY = deflectStartY_,
        angle = deflectAngle_, spin = deflectSpin_,
        weaponAngle = deflectWeaponAngle_, timer = deflectTimer_,
        duration = deflectDuration_,
    }
end
function Combat.GetWeaponClashAnim() return weaponClashAnim_ end
function Combat.GetWeaponClashPos() return weaponClashX_, weaponClashY_ end
function Combat.IsDummyAttacking() return dummyAttacking_ end
function Combat.GetDummyAttackProgress() return dummyAttackProgress_ end
function Combat.GetDummyCurrentAttack() return dummyCurrentAttack_ end
function Combat.IsDummyMoving() return dummyMoving_ end
function Combat.GetDummyVx() return dummyVx_ end
function Combat.IsDummyFacingRight() return dummyFacingRight_ end
function Combat.GetDummyWeapon() return dummyWeapon_ end

-- ============================================================================
-- 玩家攻击逻辑
-- ============================================================================

--- 发起攻击
function Combat.StartAttack(index)
    if attacking_ then return end
    if #attacks_ == 0 then return end
    if ctx_.isTrialEnded() then return end

    local idx = index or 1
    if idx > #attacks_ then idx = 1 end

    currentAttack_ = attacks_[idx]
    attacking_ = true
    attackTimer_ = 0
    local gameData = ctx_.getGameData()
    local speedBonus = gameData.attackSpeedBonus or 0
    local totalSpeedMod = speedBonus + ctx_.getMaterialSpdMod()
    attackDuration_ = currentAttack_.duration * (1.0 - totalSpeedMod)
    attackHitTargets_ = {}
    attackHitDummy_ = false
end

--- 更新攻击进度
function Combat.UpdateAttack(dt)
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
    local player = ctx_.player
    local physScale = ctx_.getPhysScale()
    if currentAttack_ and currentAttack_.isCharge then
        local dir = player.facingRight and 1 or -1
        local chargeDist = (currentAttack_.chargeDistance or 40) * physScale * dt / attackDuration_
        player.x = player.x + dir * chargeDist
    end

    Combat.CheckAttackCollision(progress)
end

--- 停止攻击（外部强制中断）
function Combat.StopAttack()
    attacking_ = false
    currentAttack_ = nil
    attackHitTargets_ = {}
end

-- ============================================================================
-- 碰撞检测
-- ============================================================================

--- 点到线段距离
local function PointToSegmentDist(px, py, ax, ay, bx, by)
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

--- 线段-线段最短距离
local function SegmentToSegmentDist(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
    local function ptSegDist(px, py, sx1, sy1, sx2, sy2)
        local dx = sx2 - sx1
        local dy = sy2 - sy1
        local len2 = dx * dx + dy * dy
        if len2 < 0.01 then
            return math.sqrt((px - sx1) * (px - sx1) + (py - sy1) * (py - sy1))
        end
        local t2 = math.max(0, math.min(1, ((px - sx1) * dx + (py - sy1) * dy) / len2))
        local cx = sx1 + t2 * dx
        local cy = sy1 + t2 * dy
        return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
    end

    local midAx = (ax1 + ax2) / 2
    local midAy = (ay1 + ay2) / 2
    local d1 = ptSegDist(ax1, ay1, bx1, by1, bx2, by2)
    local d2 = ptSegDist(ax2, ay2, bx1, by1, bx2, by2)
    local d3 = ptSegDist(midAx, midAy, bx1, by1, bx2, by2)

    local midBx = (bx1 + bx2) / 2
    local midBy = (by1 + by2) / 2
    local d4 = ptSegDist(bx1, by1, ax1, ay1, ax2, ay2)
    local d5 = ptSegDist(bx2, by2, ax1, ay1, ax2, ay2)
    local d6 = ptSegDist(midBx, midBy, ax1, ay1, ax2, ay2)

    return math.min(d1, d2, d3, d4, d5, d6)
end

--- 突刺延伸长度
local function GetThrustLength(progress, physScale)
    if not currentAttack_ then return 60 * physScale end
    local len = currentAttack_.range * physScale
    if progress < 0.3 then
        return len * (progress / 0.3)
    elseif progress < 0.7 then
        return len
    else
        return len * (1.0 - (progress - 0.7) / 0.3)
    end
end

--- 命中靶子
local function HitTarget(index, target, atk, dir)
    attackHitTargets_[index] = true

    local materialEffect = ctx_.getMaterialEffect()
    local materialAtkMod = ctx_.getMaterialAtkMod()
    local growthBonus = ctx_.getGrowthBonus()
    local player = ctx_.player
    local hitEffects = ctx_.hitEffects

    local baseDmg = atk.damage or 150
    local dmg = math.floor(baseDmg * (1.0 + materialAtkMod) * (1.0 + growthBonus))
    target.hp = target.hp - dmg
    target.hitAnim = 0.5

    local kb = atk.knockback or 8
    if materialEffect == "heavy_blow" then
        kb = kb * 1.5
    end
    target.knockX = dir * math.abs(kb)
    target.knockY = -math.abs(kb) * 0.5

    if materialEffect == "lifesteal" then
        local healAmt = math.floor(dmg * 0.15)
        hitEffects[#hitEffects + 1] = {
            x = player.x, y = player.y - 10,
            text = "+" .. healAmt,
            timer = 0.8,
            color = { 80, 255, 80 },
        }
        player.healShield = (player.healShield or 0) + healAmt * 0.3
    end

    if materialEffect == "growth" then
        local newBonus = math.min(0.50, growthBonus + 0.05)
        ctx_.setGrowthBonus(newBonus)
    end

    hitEffects[#hitEffects + 1] = {
        x = target.x, y = target.y - (target.size or 30),
        text = "-" .. dmg,
        timer = Config.Combat.DamageNumberDuration,
        color = dmg >= 200 and Config.Colors.Danger or { 255, 200, 100 },
    }

    local combo = ctx_.getCombo()
    if target.hp <= 0 then
        target.alive = false
        target.hp = 0
        target.hitAnim = 1.0
        combo = combo + 1
        ctx_.setCombo(combo)
        local points = Config.Trial.ComboMultiplier * combo
        ctx_.setScore(ctx_.getScore() + points)
        hitEffects[#hitEffects + 1] = {
            x = target.x, y = target.y - (target.size or 30) - 20,
            text = "+" .. points,
            timer = 1.0,
            color = combo >= 5 and Config.Colors.Gold or Config.Colors.Success,
        }
    else
        combo = combo + 1
        ctx_.setCombo(combo)
    end
end

--- 检测攻击碰撞（靶子 + 武器格挡 + 木桩）
function Combat.CheckAttackCollision(progress)
    if not currentAttack_ then return end

    local player = ctx_.player
    local targets = ctx_.targets
    local physScale = ctx_.getPhysScale()

    local dir = player.facingRight and 1 or -1
    local originX = player.x + player.width / 2 + dir * 10 * physScale
    local originY = player.y + player.height * 0.4
    local range = currentAttack_.range * physScale

    if currentAttack_.isThrust then
        local thrustLen = GetThrustLength(progress, physScale)
        local tipX = originX + dir * thrustLen
        local tipY = originY

        for i = 1, #targets do
            local t = targets[i]
            if t.alive and not attackHitTargets_[i] then
                local dist = PointToSegmentDist(t.x, t.y, originX, originY, tipX, tipY)
                local hr = t.hitRadius or (t.size / 2)
                if dist < hr + 12 then
                    HitTarget(i, t, currentAttack_, dir)
                end
            end
        end
    else
        for i = 1, #targets do
            local t = targets[i]
            if t.alive and not attackHitTargets_[i] then
                local dx = t.x - originX
                local dy = t.y - originY
                local dist = math.sqrt(dx * dx + dy * dy)
                local hr = t.hitRadius or (t.size / 2)
                if dist < range + hr then
                    local inFront = (player.facingRight and dx > -20)
                        or (not player.facingRight and dx < 20)
                    local vertOk = math.abs(dy) < range * 0.8
                    if inFront and vertOk then
                        HitTarget(i, t, currentAttack_, dir)
                    end
                end
            end
        end
    end

    -- 先检测武器格挡
    Combat.CheckWeaponClash(progress)

    -- 未被格挡才检测木桩
    if not deflecting_ then
        Combat.CheckDummyCollision(progress)
    end
end

--- 检测木桩碰撞
function Combat.CheckDummyCollision(progress)
    local dummy = ctx_.dummy
    if not dummy or not currentAttack_ then return end
    if attackHitDummy_ then return end

    local player = ctx_.player
    local physScale = ctx_.getPhysScale()
    local hitEffects = ctx_.hitEffects

    local atk = currentAttack_
    local dir = player.facingRight and 1 or -1
    local originX = player.x + player.width / 2 + dir * 10 * physScale
    local originY = player.y + player.height * 0.4
    local range = atk.range * physScale

    local dCx = dummy.x
    local dCy = dummy.y - dummy.height / 2
    local dRadius = dummy.width / 2 + 10

    local hit = false
    if atk.isThrust then
        local thrustLen = GetThrustLength(progress, physScale)
        local tipX = originX + dir * thrustLen
        local dist = PointToSegmentDist(dCx, dCy, originX, originY, tipX, originY)
        hit = dist < dRadius + 8
    else
        local dx = dCx - originX
        local dy = dCy - originY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < range + dRadius then
            local inFront = (player.facingRight and dx > -20)
                or (not player.facingRight and dx < 20)
            hit = inFront and math.abs(dy) < range * 0.8
        end
    end

    if hit then
        attackHitDummy_ = true
        dummy.hitAnim = 1.0
        dummy.hitDir = dir
        local baseDmg = atk.damage or 150
        local materialAtkMod = ctx_.getMaterialAtkMod()
        local growthBonus = ctx_.getGrowthBonus()
        local dmg = math.floor(baseDmg * (1.0 + materialAtkMod) * (1.0 + growthBonus))
        dummy.hp = math.max(0, dummy.hp - dmg)
        local totalDmg = ctx_.getTotalDamage() + dmg
        ctx_.setTotalDamage(totalDmg)
        hitEffects[#hitEffects + 1] = {
            x = dCx, y = dCy - dummy.height * 0.6,
            text = "-" .. dmg,
            timer = Config.Combat.DamageNumberDuration,
            color = dmg >= 200 and Config.Colors.Danger or { 255, 200, 100 },
        }
        local combo = ctx_.getCombo() + 1
        ctx_.setCombo(combo)
        ctx_.setScore(ctx_.getScore() + Config.Trial.ComboMultiplier * combo)
    end
end

-- ============================================================================
-- 木桩AI（攻击 + 移动）
-- ============================================================================

--- 更新木桩攻击AI
function Combat.UpdateDummyAttack(dt)
    local dummy = ctx_.dummy
    if not dummy or not dummyWeapon_ then return end
    if #dummyAttacks_ == 0 then return end

    local player = ctx_.player
    dummyFacingRight_ = player.x > dummy.x

    if dummyAttacking_ then
        dummyMoving_ = false
        dummyVx_ = 0
        dummyAttackTimer_ = dummyAttackTimer_ + dt
        dummyAttackProgress_ = dummyAttackTimer_ / dummyAttackDuration_

        if dummyAttackProgress_ >= 1.0 then
            dummyAttacking_ = false
            dummyCurrentAttack_ = nil
            dummyAttackProgress_ = 0
            dummyHitPlayer_ = false
            dummyAttackCooldown_ = DUMMY_ATTACK_INTERVAL_MIN
                + math.random() * (DUMMY_ATTACK_INTERVAL_MAX - DUMMY_ATTACK_INTERVAL_MIN)
        else
            Combat.CheckDummyAttackHitPlayer()
        end
        return
    end

    if dummyAttackCooldown_ > 0 then
        dummyAttackCooldown_ = dummyAttackCooldown_ - dt
        Combat.UpdateDummyMovement(dt)
        if dummyAttackCooldown_ > 0 then return end
    end

    Combat.UpdateDummyMovement(dt)
    local idx = math.random(1, #dummyAttacks_)
    dummyCurrentAttack_ = dummyAttacks_[idx]
    dummyAttacking_ = true
    dummyAttackTimer_ = 0
    dummyAttackProgress_ = 0
    dummyHitPlayer_ = false
    dummyAttackDuration_ = dummyCurrentAttack_.duration * 0.7
end

--- 锻造师移动追击
function Combat.UpdateDummyMovement(dt)
    local dummy = ctx_.dummy
    if not dummy then return end

    local player = ctx_.player
    local physScale = ctx_.getPhysScale()
    local screenW = ctx_.getScreenW()

    local distToPlayer = math.abs(player.x - dummy.x)
    local atkRange = Config.Combat.DummyAttackRange * physScale

    if distToPlayer <= atkRange then
        dummyMoving_ = false
        dummyVx_ = 0
        return
    end

    dummyMoving_ = true
    local speed = Config.Combat.DummyMoveSpeed * physScale
    local dir = dummyFacingRight_ and 1 or -1
    dummyVx_ = dir * speed
    dummy.x = dummy.x + dummyVx_ * dt

    local margin = dummy.width * 0.5
    if dummy.x < margin then dummy.x = margin end
    if dummy.x > screenW - margin then dummy.x = screenW - margin end
end

--- 检测木桩攻击命中玩家
function Combat.CheckDummyAttackHitPlayer()
    if not dummyAttacking_ or not dummyCurrentAttack_ then return end
    if dummyHitPlayer_ then return end

    local dummy = ctx_.dummy
    if not dummy then return end

    local player = ctx_.player
    local physScale = ctx_.getPhysScale()
    local hitEffects = ctx_.hitEffects
    local materialEffect = ctx_.getMaterialEffect()

    local atk = dummyCurrentAttack_
    local dir = dummyFacingRight_ and 1 or -1
    local originX = dummy.x + dir * 10 * physScale
    local originY = dummy.y - dummy.height * 0.6
    local range = atk.range * physScale
    local progress = dummyAttackProgress_

    local tipX, tipY
    if atk.isThrust then
        local eased = math.sin(progress * math.pi)
        local thrustLen = range * eased
        tipX = originX + dir * thrustLen
        tipY = originY
    else
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

    local pw = player.width
    local ph = player.height
    local pcx = player.x + pw / 2
    local pcy = player.y - ph / 2

    local midX = (originX + tipX) / 2
    local midY = (originY + tipY) / 2
    local dx = math.abs(midX - pcx)
    local dy = math.abs(midY - pcy)
    local hitRadius = range * 0.5 + pw * 0.3

    if dx < hitRadius and dy < ph * 0.6 then
        dummyHitPlayer_ = true
        local knockDir = dummyFacingRight_ and 1 or -1
        local kb = (atk.knockback or 8) * physScale
        local dmg = atk.damage or 150

        if materialEffect == "shatter" then
            kb = kb * 1.2
            dmg = math.floor(dmg * 1.2)
        end

        local shield = player.healShield or 0
        if shield > 0 then
            local reduction = math.min(shield, kb * 0.3)
            kb = kb - reduction
            player.healShield = shield - reduction
        end

        player.hp = math.max(0, player.hp - dmg)
        player.hitAnim = 0.5

        player.vx = knockDir * kb * 6
        player.vy = -kb * 2.5
        player.onGround = false

        hitEffects[#hitEffects + 1] = {
            x = pcx + 25 * physScale,
            y = pcy - 15,
            text = "-" .. dmg,
            timer = Config.Combat.DamageNumberDuration,
            color = { 255, 80, 80 },
        }
        hitEffects[#hitEffects + 1] = {
            x = pcx - 25 * physScale,
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

--- 初始化木桩武器
function Combat.InitDummyWeapon()
    dummyWeapon_ = {
        localOffsetX = 0,
        localOffsetY = -0.6,
        angle = -0.3,
        length = 50,
        width = 8,
        force = 12,
        forceDir = 1,
        rootX = 0, rootY = 0,
        tipX = 0, tipY = 0,
    }
end

--- 更新木桩武器位置
function Combat.UpdateDummyWeapon(dt)
    if not dummyWeapon_ then return end
    local dummy = ctx_.dummy
    if not dummy then return end

    local physScale = ctx_.getPhysScale()
    local dw = dummyWeapon_
    local dh = dummy.height

    local shakeX = 0
    if dummy.hitAnim > 0 then
        shakeX = math.sin(dummy.hitAnim * 20) * 4 * dummy.hitAnim * dummy.hitDir
    end

    local len = dw.length * physScale
    local dir = dummyFacingRight_ and 1 or -1
    dw.forceDir = dir
    dw.rootX = dummy.x + shakeX + dir * 10 * physScale
    dw.rootY = dummy.y + dw.localOffsetY * dh

    if dummyAttacking_ and dummyCurrentAttack_ then
        local atk = dummyCurrentAttack_
        local range = atk.range * physScale
        local progress = dummyAttackProgress_

        if atk.isThrust then
            local eased = math.sin(progress * math.pi)
            local thrustLen = range * eased
            dw.tipX = dw.rootX + dir * thrustLen
            dw.tipY = dw.rootY
            dw.angle = dummyFacingRight_ and 0 or math.pi
        else
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
        local idleAngle = dummyFacingRight_ and (-0.3) or (math.pi + 0.3)
        dw.angle = idleAngle
        dw.tipX = dw.rootX + math.cos(idleAngle) * len
        dw.tipY = dw.rootY + math.sin(idleAngle) * len
    end
end

--- 获取玩家武器碰撞体
function Combat.GetPlayerWeaponCollider(progress)
    if not attacking_ or not currentAttack_ then return nil end

    local player = ctx_.player
    local physScale = ctx_.getPhysScale()
    local atk = currentAttack_
    local dir = player.facingRight and 1 or -1
    local originX = player.x + player.width / 2 + dir * 10 * physScale
    local originY = player.y + player.height * 0.4
    local range = atk.range * physScale

    local tipX, tipY
    if atk.isThrust then
        local thrustLen = GetThrustLength(progress, physScale)
        tipX = originX + dir * thrustLen
        tipY = originY
    else
        local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
        local arcDir = (atk.direction or 1)
        local startAngle = math.rad(atk.startAngle or -60)
        local sweepAngle = math.rad(atk.arc) * arcDir * easedProgress
        local currentAngle
        if player.facingRight then
            currentAngle = startAngle + sweepAngle
        else
            currentAngle = math.pi - (startAngle + sweepAngle)
        end
        tipX = originX + math.cos(currentAngle) * range
        tipY = originY + math.sin(currentAngle) * range
    end

    return {
        rootX = originX, rootY = originY,
        tipX = tipX, tipY = tipY,
        width = 12 * physScale,
        force = atk.knockback or 8,
        forceDir = dir,
    }
end

--- 检测武器碰撞（格挡）
function Combat.CheckWeaponClash(progress)
    local dummy = ctx_.dummy
    if not dummyWeapon_ or not dummy then return end
    if not dummyAttacking_ then return end
    if weaponClashCooldown_ > 0 then return end

    local playerWeapon = Combat.GetPlayerWeaponCollider(progress)
    if not playerWeapon then return end

    local dw = dummyWeapon_
    local physScale = ctx_.getPhysScale()
    local player = ctx_.player
    local hitEffects = ctx_.hitEffects
    local gameData = ctx_.getGameData()

    local dist = SegmentToSegmentDist(
        playerWeapon.rootX, playerWeapon.rootY, playerWeapon.tipX, playerWeapon.tipY,
        dw.rootX, dw.rootY, dw.tipX, dw.tipY
    )

    local collisionThreshold = (playerWeapon.width + dw.width * physScale) / 2

    if dist < collisionThreshold then
        weaponClashCooldown_ = 0.4

        local midPX = (playerWeapon.rootX + playerWeapon.tipX) / 2
        local midPY = (playerWeapon.rootY + playerWeapon.tipY) / 2
        local midDX = (dw.rootX + dw.tipX) / 2
        local midDY = (dw.rootY + dw.tipY) / 2
        weaponClashX_ = (midPX + midDX) / 2
        weaponClashY_ = (midPY + midDY) / 2
        weaponClashAnim_ = 1.0

        local pushDir = player.facingRight and -1 or 1
        player.vx = pushDir * dw.force * physScale * 8
        player.vy = -dw.force * physScale * 3
        player.onGround = false

        dummy.hitAnim = 0.6
        dummy.hitDir = playerWeapon.forceDir

        hitEffects[#hitEffects + 1] = {
            x = weaponClashX_, y = weaponClashY_ - 20,
            text = "格挡!",
            timer = 1.0,
            color = { 255, 200, 80 },
        }

        local mat = gameData and gameData.material or nil
        if mat and mat.effect == "thorns" then
            local thornsDmg = 100
            dummy.hp = math.max(0, dummy.hp - thornsDmg)
            hitEffects[#hitEffects + 1] = {
                x = dummy.x,
                y = dummy.y - (dummy.height or 60) * 0.7,
                text = "反伤-" .. thornsDmg,
                timer = 1.2,
                color = { 255, 160, 50 },
            }
        end

        deflecting_ = true
        deflectTimer_ = 0
        deflectStartX_ = weaponClashX_
        deflectStartY_ = weaponClashY_
        deflectAngle_ = dw.angle
        local pdir = player.facingRight and 1 or -1
        deflectWeaponAngle_ = pdir * math.pi / 4
        deflectSpin_ = pdir * (-12)
        attacking_ = false
        currentAttack_ = nil
    end
end

--- 更新武器碰撞（动画衰减 + 弹开）
function Combat.UpdateWeaponClash(dt)
    if weaponClashAnim_ > 0 then
        weaponClashAnim_ = weaponClashAnim_ - dt * 3
    end
    if weaponClashCooldown_ > 0 then
        weaponClashCooldown_ = weaponClashCooldown_ - dt
    end
    if deflecting_ then
        deflectTimer_ = deflectTimer_ + dt
        if deflectTimer_ >= deflectDuration_ then
            deflecting_ = false
            deflectTimer_ = 0
        end
    end
end

-- ============================================================================
-- 供外部使用的工具函数
-- ============================================================================

Combat.PointToSegmentDist = PointToSegmentDist

return Combat
