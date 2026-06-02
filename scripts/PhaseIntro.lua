-- ============================================================================
-- PhaseIntro.lua - 环节说明黑屏界面
-- 每个环节开始前显示玩法说明，玩家点击确认后进入
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")

local PhaseIntro = {}

local active_ = false

--- 判断是否正在显示环节说明
function PhaseIntro.IsActive()
    return active_
end

--- 各环节说明数据
local PHASE_INFO = {
    [Config.States.DRAW] = {
        title = "✏️ 绘制武器",
        desc = "在画布上绘制你的武器形状\n系统将根据你的绘制识别武器类型\n尽量画得清晰完整！",
    },
    [Config.States.MATERIAL] = {
        title = "🧱 选择材质",
        desc = "材质方块将以弹幕方式从屏幕飞过\n点击你想要的材质方块即可选中\n不同材质赋予武器不同属性加成",
    },
    [Config.States.FORGE] = {
        title = "🔨 锤击锻打",
        desc = "节奏条上有一个移动的光标\n在光标经过黄色区域时点击屏幕\n踩准节拍获得更高锻造评分！",
    },
    -- 锻造子阶段说明（由 ForgeState 内部触发）
    ["forge_quench"] = {
        title = "💧 淬火冷却",
        desc = "按住屏幕对武器进行冷却\n将温度降至目标区间后松手\n按住越久降温越快，注意别过冷！",
    },
    ["forge_grind"] = {
        title = "✨ 砥砺打磨",
        desc = "在方块区域内长按来回滑动\n完成一个来回即为一次打磨\n在时限内尽可能多地完成打磨！",
    },
    [Config.States.RESULT] = {
        title = "⚔️ 锻造完成",
        desc = "查看你锻造的武器属性和品质评级\n准备好后即将进入试炼场！",
    },
    [Config.States.TRIAL] = {
        title = "⚔️ 试炼场",
        desc = "横版动作战斗！击败锻造师获得胜利\nPC: AD移动 / 空格跳跃 / 鼠标攻击\n手机: 左侧方向键 / 右侧跳跃和攻击",
    },
}

--- 显示环节说明界面
--- @param state string 目标环节状态名
--- @param onConfirm function 玩家确认后的回调
function PhaseIntro.Show(state, onConfirm)
    local info = PHASE_INFO[state]
    if not info then
        -- 没有说明的环节直接进入
        if onConfirm then onConfirm() end
        return
    end

    active_ = true

    local root = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 10, 12, 18, 255 },
        justifyContent = "center",
        alignItems = "center",
        gap = 24,
        children = {
            -- 标题
            UI.Label {
                text = info.title,
                fontSize = 28,
                fontColor = Config.Colors.Gold,
            },
            -- 分割线
            UI.Panel {
                width = 200, height = 1,
                backgroundColor = { 80, 80, 100, 150 },
            },
            -- 说明文字
            UI.Label {
                text = info.desc,
                fontSize = 16,
                fontColor = { 200, 210, 220, 255 },
                textAlign = "center",
                lineHeight = 1.6,
            },
            -- 确认按钮
            UI.Button {
                text = "开始",
                variant = "primary",
                width = 160,
                marginTop = 16,
                onClick = function()
                    active_ = false
                    if onConfirm then onConfirm() end
                end,
            },
        },
    }

    UI.SetRoot(root)
end

return PhaseIntro
