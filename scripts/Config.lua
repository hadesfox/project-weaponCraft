-- ============================================================================
-- Config.lua - 全局配置
-- ============================================================================

local Config = {}

-- 游戏标题
Config.Title = "锻造师"
Config.Version = "v1.0.12"

-- 游戏状态枚举
Config.States = {
    MENU = "menu",
    DRAW = "draw",
    MATERIAL = "material",
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
    HammerDuration = 5.0,    -- 锤击阶段时长（秒）
    QuenchDuration = 5.0,    -- 淬火阶段时长（秒）
    PerfectHalf = 0.10,      -- 完美判定区域半宽（占节奏条比例）
    GoodHalf = 0.40,         -- 良好判定区域半宽（占节奏条比例）
    ZoneMargin = 0.40,       -- 判定区域随机范围边距
    GrindDuration = 3.0,     -- 砥砺阶段时长（秒）
    GrindKeys = { "J", "K", "L" },  -- 砥砺按键序列
    GrindScoreTable = {      -- 砥砺次数→得分映射
        [0] = 10, [1] = 30, [2] = 50, [3] = 65,
        [4] = 80, [5] = 90, [6] = 100,
    },
    GrindMaxCount = 6,       -- 超过此次数按满分计算
    FinishDelay = 1.5,       -- 锻造完成后延迟过渡（秒）
}

-- 试炼场时间选项（秒）
Config.TrialTimeOptions = { 30, 45, 60, 90, 120 }

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
    -- 敌人图片
    EnemyImage = "image/红色史莱姆敌人_20260530132628.png",
}

-- ============================================================================
-- 战斗系统配置
-- ============================================================================
Config.Combat = {
    BaseHP = 1000,            -- 敌人基础血量
    DummyHP = 2500,           -- 锻造师血量
    DummyMoveSpeed = 120,     -- 锻造师移动速度（px/秒）
    DummyChaseRange = 9999,   -- 锻造师追击范围（超出则不追）
    DummyAttackRange = 70,    -- 锻造师攻击距离（进入后停止移动）
    HPBarWidth = 50,          -- 血条宽度（基础px，按physScale缩放）
    HPBarHeight = 6,          -- 血条高度
    HPBarOffsetY = -12,       -- 血条在目标头顶的偏移
    DamageNumberDuration = 0.8,  -- 伤害数字显示时长
    TrialTimeLimit = 60,      -- 试炼场时间限制（秒）
}

-- 武器攻击配置（每种武器的攻击招式）
-- damage: 绝对伤害值（基于BaseHP=1000设计）
-- 设计目标: 普通攻击6-7下击杀，重击3下击杀
Config.Attacks = {
    SWORD = {
        -- 均衡型：攻速与伤害平衡，连击流畅
        {
            name = "横斩",
            duration = 0.3,       -- 攻击持续时间（秒）
            range = 70,           -- 攻击范围（px）
            arc = 150,            -- 扫过弧度（度）
            damage = 150,         -- 伤害值
            knockback = 5,        -- 击退距离
            startAngle = -75,     -- 起始偏移角（相对面朝方向）
        },
        {
            name = "上挑",
            duration = 0.25,
            range = 60,
            arc = 100,
            damage = 110,
            knockback = 10,
            startAngle = 50,      -- 从下往上挑
            direction = -1,       -- 反向挥动
        },
    },
    AXE = {
        -- 爆发型：慢速高伤，单发毁灭
        {
            name = "劈砍",
            duration = 0.5,       -- 慢但重
            range = 80,
            arc = 90,
            damage = 320,
            knockback = 15,
            startAngle = -45,
        },
        {
            name = "横扫",
            duration = 0.45,
            range = 90,
            arc = 200,            -- 超大范围扫
            damage = 220,
            knockback = 20,
            startAngle = -100,
        },
    },
    SPEAR = {
        -- 风筝型：极快极远，持续输出
        {
            name = "突刺",
            duration = 0.2,       -- 极快
            range = 120,          -- 超远
            arc = 20,             -- 极窄（刺）
            damage = 130,
            knockback = 8,
            startAngle = -10,
            isThrust = true,      -- 突刺类攻击（特殊动画）
        },
        {
            name = "横扫",
            duration = 0.4,
            range = 100,
            arc = 160,
            damage = 160,
            knockback = 12,
            startAngle = -80,
        },
    },
    SHIELD = {
        -- 控制型：低伤高击退，安全输出
        {
            name = "盾击",
            duration = 0.3,
            range = 45,           -- 近身
            arc = 80,
            damage = 80,
            knockback = 25,       -- 超强击退
            startAngle = -40,
        },
        {
            name = "冲撞",
            duration = 0.4,
            range = 55,
            arc = 60,
            damage = 120,
            knockback = 30,
            startAngle = -30,
            isCharge = true,      -- 冲撞（玩家前移）
            chargeDistance = 40,
        },
    },
    HOOK = {
        -- 连击型：低单伤，拉近+360度高伤combo
        {
            name = "钩击",
            duration = 0.3,
            range = 100,          -- 长距
            arc = 40,             -- 窄弧
            damage = 70,
            knockback = -20,      -- 负数 = 拉近
            startAngle = -20,
        },
        {
            name = "回旋",
            duration = 0.5,
            range = 80,
            arc = 360,            -- 360 度全方位
            damage = 240,
            knockback = 5,
            startAngle = 0,
        },
    },
    UNKNOWN = {
        -- 奇物：仅单招但素材加成最高
        {
            name = "挥击",
            duration = 0.35,
            range = 65,
            arc = 130,
            damage = 170,
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

-- 颜色主题（锻造暗色风格）
Config.Colors = {
    Primary = { 150, 200, 255, 255 },     -- 冰霜蓝（交互：长剑光效、符文冷光）
    Secondary = { 200, 80, 40, 255 },     -- 炭火红（氛围：炉火余烬、灼热高光）
    Success = { 80, 200, 120, 255 },      -- 成功绿
    Danger = { 240, 80, 80, 255 },        -- 危险红
    BgDark = { 20, 22, 28, 255 },         -- 压抑黑蓝（环境阴影、深邃底色）
    BgMedium = { 50, 50, 55, 255 },       -- 铁锈灰（UI面板、按钮底座）
    BgLight = { 170, 150, 110, 255 },     -- 羊皮黄（卷轴、提示标签）
    TextLight = { 200, 205, 210, 255 },   -- 哑光银（UI文字、偏冷灰白）
    TextDark = { 30, 30, 35, 255 },       -- 焦黑（文字描边、雕刻阴影）
    Gold = { 160, 140, 90, 255 },         -- 旧金（金属装饰、低饱和氧化质感）
    Silver = { 120, 130, 140, 255 },      -- 钢灰（银色金属、铁器氧化）
}

-- ============================================================================
-- 材质系统配置
-- ============================================================================
Config.Materials = {
    {
        id = "black_iron",
        name = "黑铁",
        color = { 60, 60, 80 },
        atkMod = 0.20,       -- +20% 攻击
        spdMod = -0.10,      -- -10% 攻速
        penalty = nil,
        effect = "heavy_blow", -- 重击：击退+50%
        desc = "重击：击退距离+50%",
    },
    {
        id = "mithril",
        name = "秘银",
        color = { 180, 220, 255 },
        atkMod = -0.10,
        spdMod = 0.25,
        penalty = "hp_minus_10", -- -10% HP
        effect = "agile",        -- 灵动：攻击时不减速
        desc = "灵动：攻击时移速不减",
    },
    {
        id = "obsidian",
        name = "黑曜石",
        color = { 30, 10, 50 },
        atkMod = 0.40,
        spdMod = 0,
        penalty = "fragile",     -- 易损
        effect = "shatter",      -- 碎裂：受击伤害+20%
        desc = "碎裂：自身受伤+20%",
    },
    {
        id = "blood_ore",
        name = "血矿",
        color = { 180, 30, 30 },
        atkMod = -0.15,
        spdMod = 0,
        penalty = "hp_cost_start", -- 开局扣血
        effect = "lifesteal",      -- 嗜血：伤害15%转HP
        desc = "嗜血：伤害15%回血",
    },
    {
        id = "radiant_meteor",
        name = "陨星",
        color = { 100, 255, 80 },
        atkMod = -0.30,
        spdMod = 0,
        penalty = nil,
        effect = "burn",           -- 灼烧：真实伤害 2%/s
        desc = "灼烧：每秒2%真伤",
    },
    {
        id = "inverse_alloy",
        name = "逆鳞",
        color = { 200, 160, 50 },
        atkMod = -0.20,
        spdMod = 0,
        penalty = nil,
        effect = "thorns",         -- 反震：格挡反弹100伤害
        desc = "反震：格挡反伤100",
    },
    {
        id = "spirit_wood",
        name = "灵木",
        color = { 80, 200, 120 },
        atkMod = 0,
        spdMod = 0,
        penalty = "combo_fragile", -- 易断链
        effect = "growth",         -- 成长：连击+5%伤害(上限50%)
        desc = "成长：连击+5%伤害",
    },
}

-- 材质弹幕配置
Config.MaterialDanmaku = {
    Duration = 5.0,          -- 弹幕持续秒数（超时自动随机选一个）
    SpawnInterval = 0.035,   -- 生成间隔（极密集）
    Speed = { 700, 1200 },   -- 飞行速度范围（极快）
    BoxWidth = 85,           -- 材质框宽度
    BoxHeight = 30,          -- 材质框高度
    Lanes = 6,               -- 弹道数量（行数，增加一行）
    LanePadding = 4,         -- 行间距
    BoxColor = { 55, 58, 68 },  -- 统一方块颜色（不可辨认）
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
