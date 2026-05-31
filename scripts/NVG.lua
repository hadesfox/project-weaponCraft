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

-- ============================================================================
-- 全局 nvgFontSize 防护：量化到固定字号集合，防止字体图集膨胀
-- NanoVG 对每个 (字符, fontSize) 组合缓存独立字形；中文字符多，
-- 如果允许任意字号，图集会快速增长直到 GPU 显存耗尽。
-- ============================================================================
local ALLOWED_SIZES = { 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32, 36, 42 }
local SIZE_COUNT = #ALLOWED_SIZES

--- 将任意字号量化到最近的允许值（全局防御）
local function quantizeFontSize(size)
    if size <= ALLOWED_SIZES[1] then return ALLOWED_SIZES[1] end
    if size >= ALLOWED_SIZES[SIZE_COUNT] then return ALLOWED_SIZES[SIZE_COUNT] end
    -- 二分查找最近值
    local lo, hi = 1, SIZE_COUNT
    while lo < hi - 1 do
        local mid = math.floor((lo + hi) / 2)
        if ALLOWED_SIZES[mid] <= size then
            lo = mid
        else
            hi = mid
        end
    end
    -- lo 和 hi 相邻，选择更近的
    if (size - ALLOWED_SIZES[lo]) <= (ALLOWED_SIZES[hi] - size) then
        return ALLOWED_SIZES[lo]
    else
        return ALLOWED_SIZES[hi]
    end
end

-- 覆盖全局 nvgFontSize，强制量化
local _rawNvgFontSize = nvgFontSize
function nvgFontSize(vg, size)
    _rawNvgFontSize(vg, quantizeFontSize(math.floor(size)))
end

return NVG
