-- ============================================================================
-- Config.lua - 全局配置
-- ============================================================================

local Config = {}

-- 游戏标题
Config.Title = "锻造师"

-- 游戏状态枚举
Config.States = {
    MENU = "menu",
    DRAW = "draw",
    FORGE = "forge",
    RESULT = "result",
    TRIAL = "trial",
}

-- 画布配置
Config.Canvas = {
    Width = 400,         -- 画布宽度（逻辑像素）
    Height = 400,        -- 画布高度
    BrushSize = 4,       -- 默认画笔大小
    MaxPoints = 2000,    -- 最大采样点数
    MinPointDistanceSq = 9,   -- 采样最小间距平方（3px²）
    CloseThresholdSq = 400,   -- 闭合判定距离平方（20px²）
    BackgroundColor = { 250, 248, 245, 255 },
    StrokeColor = { 40, 40, 50, 255 },
    GridColor = { 220, 215, 210, 80 },
}

-- 武器类型定义
Config.WeaponTypes = {
    SWORD = { name = "剑", icon = "⚔️", color = { 100, 180, 255 } },
    AXE = { name = "斧", icon = "🪓", color = { 200, 120, 80 } },
    SPEAR = { name = "矛", icon = "🔱", color = { 80, 200, 120 } },
    SHIELD = { name = "盾", icon = "🛡️", color = { 180, 160, 60 } },
    HOOK = { name = "钩", icon = "🪝", color = { 160, 80, 200 } },
    UNKNOWN = { name = "奇物", icon = "✨", color = { 255, 180, 60 } },
}

-- 锻造配置
Config.Forge = {
    HammerDuration = 10.0,   -- 锤击阶段时长（秒）
    QuenchDuration = 5.0,    -- 淬火阶段时长（秒）
    PerfectHalf = 0.10,      -- 完美判定区域半宽（占节奏条比例）
    GoodHalf = 0.40,         -- 良好判定区域半宽（占节奏条比例）
    ZoneMargin = 0.40,       -- 判定区域随机范围边距
    FinishDelay = 1.5,       -- 锻造完成后延迟过渡（秒）
}

-- 试炼场配置
Config.Trial = {
    TargetCount = 5,
    TargetMinSize = 25,
    TargetMaxSize = 40,
    ClearBonus = 50,           -- 清场奖励分数
    ComboMultiplier = 10,      -- 连击分数乘数
    ComboDecayTime = 2.0,      -- 连击衰减时间（秒无命中后重置）
    
    -- 玩家（横版）
    PlayerWidth = 32,          -- 玩家宽度
    PlayerHeight = 48,         -- 玩家高度
    MoveSpeed = 220,           -- 水平移动速度（px/秒）
    JumpVelocity = -420,       -- 跳跃初速度（负=向上）
    Gravity = 900,             -- 重力加速度（px/秒²）
    MaxFallSpeed = 600,        -- 最大下落速度
    GroundY = 0.82,            -- 地面 Y 位置（屏幕比例）
    
    -- 平台
    PlatformCount = 8,         -- 平台数量
    PlatformWidth = 90,        -- 平台宽度
    PlatformHeight = 10,       -- 平台厚度
    
    -- 主角图片
    PlayerImage = "image/主角_锻造师_20260530003547.png",
    RunFrames = {
        "image/run_frame_A_20260530070458.png",  -- 右腿前迈，左腿后蹬
        "image/run_frame_B_20260530070453.png",  -- 过渡（双腿收拢，身体上弹）
        "image/run_frame_C_20260530070452.png",  -- 左腿前迈，右腿后蹬
        "image/run_frame_D_20260530070559.png",  -- 过渡（双腿收拢，身体下沉）
    },
}

-- 武器攻击配置（每种武器的攻击招式）
Config.Attacks = {
    SWORD = {
        {
            name = "横斩",
            duration = 0.3,       -- 攻击持续时间（秒）
            range = 70,           -- 攻击范围（px）
            arc = 150,            -- 扫过弧度（度）
            damage = 1.0,         -- 伤害倍率
            knockback = 5,        -- 击退距离
            startAngle = -75,     -- 起始偏移角（相对面朝方向）
        },
        {
            name = "上挑",
            duration = 0.25,
            range = 60,
            arc = 100,
            damage = 1.2,
            knockback = 10,
            startAngle = 50,      -- 从下往上挑
            direction = -1,       -- 反向挥动
        },
    },
    AXE = {
        {
            name = "劈砍",
            duration = 0.5,       -- 慢但重
            range = 80,
            arc = 90,
            damage = 2.0,
            knockback = 15,
            startAngle = -45,
        },
        {
            name = "横扫",
            duration = 0.45,
            range = 90,
            arc = 200,            -- 超大范围扫
            damage = 1.5,
            knockback = 20,
            startAngle = -100,
        },
    },
    SPEAR = {
        {
            name = "突刺",
            duration = 0.2,       -- 极快
            range = 120,          -- 超远
            arc = 20,             -- 极窄（刺）
            damage = 1.3,
            knockback = 8,
            startAngle = -10,
            isThrust = true,      -- 突刺类攻击（特殊动画）
        },
        {
            name = "横扫",
            duration = 0.4,
            range = 100,
            arc = 160,
            damage = 1.0,
            knockback = 12,
            startAngle = -80,
        },
    },
    SHIELD = {
        {
            name = "盾击",
            duration = 0.3,
            range = 45,           -- 近身
            arc = 80,
            damage = 0.8,
            knockback = 25,       -- 超强击退
            startAngle = -40,
        },
        {
            name = "冲撞",
            duration = 0.4,
            range = 55,
            arc = 60,
            damage = 1.5,
            knockback = 30,
            startAngle = -30,
            isCharge = true,      -- 冲撞（玩家前移）
            chargeDistance = 40,
        },
    },
    HOOK = {
        {
            name = "钩击",
            duration = 0.3,
            range = 100,          -- 长距
            arc = 40,             -- 窄弧
            damage = 1.0,
            knockback = -20,      -- 负数 = 拉近
            startAngle = -20,
        },
        {
            name = "回旋",
            duration = 0.5,
            range = 80,
            arc = 360,            -- 360 度全方位
            damage = 0.8,
            knockback = 5,
            startAngle = 0,
        },
    },
    UNKNOWN = {
        {
            name = "挥击",
            duration = 0.35,
            range = 65,
            arc = 130,
            damage = 1.0,
            knockback = 8,
            startAngle = -65,
        },
    },
}

-- 形状分析配置
Config.Analyzer = {
    SharpAngleDeg = 60,            -- 尖锐角度阈值（度）
    MinEdgeLength = 3,             -- 计算转折角度的最小边长（px）
    ConnectionDistanceSq = 900,    -- 笔画连接判定距离平方（30px²）
}

-- 颜色主题（扁平卡通风格）
Config.Colors = {
    Primary = { 75, 135, 255, 255 },
    Secondary = { 255, 140, 60, 255 },
    Success = { 80, 200, 120, 255 },
    Danger = { 240, 80, 80, 255 },
    BgDark = { 30, 32, 40, 255 },
    BgMedium = { 45, 48, 60, 255 },
    BgLight = { 245, 242, 238, 255 },
    TextLight = { 255, 255, 255, 255 },
    TextDark = { 40, 40, 50, 255 },
    Gold = { 255, 200, 50, 255 },
    Silver = { 180, 190, 200, 255 },
}

-- 品质定义
Config.Quality = {
    { name = "粗制", color = { 160, 160, 160 }, threshold = 0 },
    { name = "普通", color = { 255, 255, 255 }, threshold = 30 },
    { name = "精良", color = { 80, 200, 120 }, threshold = 50 },
    { name = "史诗", color = { 160, 100, 255 }, threshold = 75 },
    { name = "传说", color = { 255, 180, 50 }, threshold = 90 },
}

return Config
