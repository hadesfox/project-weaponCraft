-- ============================================================================
-- Trial/EndScreen.lua — 试炼结算画面（视频 + 排行榜 + 成绩提交）
-- 从 TrialState.lua 抽取，减少主文件复杂度
-- ============================================================================

local UI = require("urhox-libs/UI")
local Video = require("urhox-libs/Video")
local Config = require("Config")

local EndScreen = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local showEndScreen_ = false
local endScreenPhase_ = "input"  -- "input" / "submitting" / "leaderboard"
local playerInputId_ = ""
local leaderboardData_ = {}
local endVideoPlaying_ = false
local endVideoPlayer_ = nil

local WIN_VIDEO_PATH  = "video/1780205172944-167941.mp4"
local LOSE_VIDEO_PATH = "video/1780204189075-776175.mp4"

-- 通过 Init 注入的外部上下文
local ctx_ = {}

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 初始化：注入外部依赖
--- @param ctx table { getTrialTimer, getTotalDamage, getEndReason, getCombo, getUIRoot, setUIRoot, onComplete }
function EndScreen.Init(ctx)
    ctx_ = ctx
    showEndScreen_ = false
    endScreenPhase_ = "input"
    playerInputId_ = ""
    leaderboardData_ = {}
    endVideoPlaying_ = false
    endVideoPlayer_ = nil
end

--- 重置状态（Leave 时调用）
function EndScreen.Reset()
    showEndScreen_ = false
    endScreenPhase_ = "input"
    playerInputId_ = ""
    leaderboardData_ = {}
    if endVideoPlayer_ then
        endVideoPlayer_:Destroy()
        endVideoPlayer_ = nil
    end
    endVideoPlaying_ = false
end

-- 查询
function EndScreen.IsShowing() return showEndScreen_ end
function EndScreen.IsVideoPlaying() return endVideoPlaying_ end
function EndScreen.GetPhase() return endScreenPhase_ end

-- ============================================================================
-- 播放结算视频
-- ============================================================================

function EndScreen.PlayEndVideo()
    local trialEndReason = ctx_.getEndReason()

    if not Video.isSupported then
        EndScreen.ShowEndScreen()
        return
    end

    endVideoPlaying_ = true
    local videoPath = trialEndReason == "kill" and WIN_VIDEO_PATH or LOSE_VIDEO_PATH

    local function onVideoFinished()
        if not endVideoPlaying_ then return end
        endVideoPlaying_ = false
        if endVideoPlayer_ then
            endVideoPlayer_:Destroy()
            endVideoPlayer_ = nil
        end
        EndScreen.ShowEndScreen()
    end

    -- 全屏视频 + 跳过按钮（禁用点击交互防止循环播放）
    endVideoPlayer_ = Video.VideoPlayer {
        id = "endVideo",
        src = videoPath,
        width = "100%",
        height = "100%",
        autoPlay = true,
        loop = false,
        objectFit = "cover",
        pointerEvents = "none",
        onEnded = onVideoFinished,
    }

    local skipBtn = UI.Button {
        text = "跳过 >>",
        size = "small",
        variant = "text",
        position = "absolute",
        right = 20, top = 20,
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 8, paddingBottom = 8,
        backgroundColor = { 0, 0, 0, 100 },
        borderWidth = 1,
        borderColor = { 200, 200, 200, 200 },
        borderRadius = 6,
        color = { 220, 220, 220, 200 },
        fontSize = 14,
        onClick = function()
            onVideoFinished()
        end,
    }

    local videoRoot = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 255 },
        children = {
            endVideoPlayer_,
            skipBtn,
        },
    }

    ctx_.setUIRoot(videoRoot)
    UI.SetRoot(videoRoot)
end

-- ============================================================================
-- 显示结算画面
-- ============================================================================

function EndScreen.ShowEndScreen()
    showEndScreen_ = true
    endScreenPhase_ = "input"
    playerInputId_ = ""

    local timeUsed = math.ceil(ctx_.getTrialTimer())
    local trialEndReason = ctx_.getEndReason()
    local trialTotalDamage = ctx_.getTotalDamage()
    local combo = ctx_.getCombo()

    local reasonText = trialEndReason == "kill" and "锻造师被击败!"
        or trialEndReason == "defeated" and "你被击败了!" or "时间到!"
    local borderColor = trialEndReason == "kill" and Config.Colors.Gold or { 200, 80, 80, 255 }

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
            EndScreen.SubmitScore(timeUsed)
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
            UI.Label {
                text = reasonText,
                fontSize = 20,
                fontColor = trialEndReason == "kill" and Config.Colors.Gold or { 240, 100, 100, 255 },
            },
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
                            UI.Label { text = tostring(trialTotalDamage), fontSize = 14, fontColor = { 255, 180, 80, 255 } },
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "最高连击", fontSize = 14, fontColor = { 160, 170, 180, 255 } },
                            UI.Label { text = tostring(combo), fontSize = 14, fontColor = Config.Colors.Secondary },
                        },
                    },
                },
            },
            UI.Panel { width = "80%", height = 1, backgroundColor = { 60, 60, 70, 150 } },
            UI.Label {
                text = "输入你的名字上榜:",
                fontSize = 12,
                fontColor = { 140, 150, 160, 220 },
            },
            inputField,
            submitBtn,
            UI.Button {
                text = "返回菜单",
                size = "small",
                variant = "outline",
                marginTop = 8,
                width = "100%",
                onClick = function()
                    local cb = ctx_.onComplete
                    if cb then cb() end
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

    ctx_.setUIRoot(endRoot)
    UI.SetRoot(endRoot)

    -- 立即拉取排行榜数据
    EndScreen.FetchLeaderboard()
end

-- ============================================================================
-- 分数提交 + 排行榜
-- ============================================================================

--- 提交分数到云排行榜
function EndScreen.SubmitScore(timeUsed)
    local cjson = require("cjson")

    local newEntry = {
        name = playerInputId_,
        time = timeUsed,
        damage = ctx_.getTotalDamage(),
        ts = os.time(),
    }

    clientCloud:Get("leaderboard_history", {
        ok = function(values)
            local history = {}
            if values and values.leaderboard_history then
                local ok2, decoded = pcall(cjson.decode, values.leaderboard_history)
                if ok2 and type(decoded) == "table" then
                    history = decoded
                end
            end
            history[#history + 1] = newEntry
            table.sort(history, function(a, b)
                if a.time ~= b.time then return a.time < b.time end
                return a.damage < b.damage
            end)
            if #history > 50 then
                local trimmed = {}
                for i = 1, 50 do trimmed[i] = history[i] end
                history = trimmed
            end
            clientCloud:Set("leaderboard_history", cjson.encode(history), {
                ok = function()
                    print("[EndScreen] Leaderboard saved, count=" .. #history)
                    leaderboardData_ = history
                    EndScreen.BuildLeaderboardUI()
                end,
                error = function(code, reason)
                    print("[EndScreen] Save error: " .. tostring(reason))
                    leaderboardData_ = history
                    EndScreen.BuildLeaderboardUI()
                end,
            })
        end,
        error = function(code, reason)
            print("[EndScreen] Get history error: " .. tostring(reason))
            local history = { newEntry }
            clientCloud:Set("leaderboard_history", cjson.encode(history), {
                ok = function()
                    leaderboardData_ = history
                    EndScreen.BuildLeaderboardUI()
                end,
                error = function()
                    leaderboardData_ = history
                    EndScreen.BuildLeaderboardUI()
                end,
            })
        end,
    })
end

--- 拉取排行榜数据
function EndScreen.FetchLeaderboard()
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
            table.sort(history, function(a, b)
                if a.time ~= b.time then return a.time < b.time end
                return a.damage < b.damage
            end)
            print("[EndScreen] Leaderboard fetched, count=" .. #history)
            leaderboardData_ = history
            EndScreen.BuildLeaderboardUI()
        end,
        error = function(code, reason)
            print("[EndScreen] Fetch error: " .. tostring(reason))
            leaderboardData_ = {}
            EndScreen.BuildLeaderboardUI()
        end,
    })
end

--- 构建排行榜 UI 内容
function EndScreen.BuildLeaderboardUI()
    local uiRoot = ctx_.getUIRoot()
    local panel = uiRoot and uiRoot:FindById("endLeaderboard")
    if not panel then return end

    local children = {}

    if #leaderboardData_ == 0 then
        children[#children + 1] = UI.Label {
            text = "暂无数据",
            fontSize = 12,
            fontColor = { 120, 120, 130, 180 },
        }
    else
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

return EndScreen
