-- ============================================================================
-- NVG.lua - 全局共享 NanoVG 上下文
-- 所有 State 共用同一个上下文，避免重复创建 GPU 资源
-- ============================================================================

local NVG = {}

local ctx_ = nil
local fontId_ = -1
local initialized_ = false

--- 初始化（只调用一次）
function NVG.Init()
    if initialized_ then return end
    
    ctx_ = nvgCreate(1)
    if not ctx_ then
        print("[NVG] ERROR: Failed to create context")
        return
    end
    
    fontId_ = nvgCreateFont(ctx_, "sans", "Fonts/MiSans-Regular.ttf")
    if fontId_ == -1 then
        print("[NVG] ERROR: Failed to load font")
    end
    
    initialized_ = true
    print("[NVG] Initialized. fontId=" .. fontId_)
end

--- 获取上下文
function NVG.Get()
    return ctx_
end

--- 获取字体 ID
function NVG.GetFont()
    return fontId_
end

--- 销毁
function NVG.Shutdown()
    if ctx_ then
        nvgDelete(ctx_)
        ctx_ = nil
    end
    initialized_ = false
end

return NVG
