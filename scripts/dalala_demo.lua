-- ============================================================================
-- 嗒啦啦 Spine 帧动画展示
-- ============================================================================
local UI = require("urhox-libs/UI")

function Start()
    graphics.windowTitle = "嗒啦啦"

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    local root = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 30, 30, 50, 255 },
        children = {
            UI.Panel {
                alignItems = "center",
                gap = 20,
                children = {
                    UI.Label {
                        text = "嗒啦啦",
                        fontSize = 28,
                        fontColor = { 100, 200, 255, 255 },
                    },
                    UI.Spine {
                        src = "Spines/dalala/dalala_idle.json",
                        animation = "dalala_idle",
                        loop = true,
                        width = 256, height = 256,
                    },
                    UI.Label {
                        text = "Spine 帧动画 · 4帧 · 6fps",
                        fontSize = 14,
                        fontColor = { 150, 150, 170, 200 },
                    },
                },
            },
        },
    }
    UI.SetRoot(root)
end
