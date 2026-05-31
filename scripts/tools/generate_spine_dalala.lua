function Start()
    local ok, err = pcall(function()
        local CONFIG = {
            name = "dalala_idle",
            frames = {
                "image/dalala_idle_1_20260530081411.png",
                "image/dalala_idle_2_20260530081411.png",
                "image/dalala_idle_3_20260530081423.png",
                "image/dalala_idle_4_20260530081432.png",
            },
            fps = 6,
            output_dir = "/workspace/assets/Spines/dalala",
        }

        local frameCount = #CONFIG.frames
        local frameDuration = 1.0 / CONFIG.fps

        -- 1. 读取第一帧获取尺寸
        local firstImg = cache:GetResource("Image", CONFIG.frames[1])
        assert(firstImg, "Cannot load first frame: " .. CONFIG.frames[1])
        local frameW = math.floor(firstImg.width)
        local frameH = math.floor(firstImg.height)
        print("[spine] Frame size: " .. frameW .. "x" .. frameH)

        -- 2. 创建输出目录
        fileSystem:CreateDir(CONFIG.output_dir)

        -- 3. 复制帧图片到输出目录
        for i = 1, frameCount do
            local srcPath = "/workspace/assets/" .. CONFIG.frames[i]
            local dstPath = CONFIG.output_dir .. "/" .. CONFIG.name .. "_frame_" .. i .. ".png"
            fileSystem:Copy(srcPath, dstPath)
        end
        print("[spine] Copied " .. frameCount .. " frames")

        -- 4. 生成 .atlas（多页格式）
        local NL = string.char(10)
        local atlasText = ""
        for i = 1, frameCount do
            local pageName = CONFIG.name .. "_frame_" .. i .. ".png"
            atlasText = atlasText .. pageName .. NL
            atlasText = atlasText .. "size: " .. frameW .. "," .. frameH .. NL
            atlasText = atlasText .. "format: RGBA8888" .. NL
            atlasText = atlasText .. "filter: Linear,Linear" .. NL
            atlasText = atlasText .. "repeat: none" .. NL
            atlasText = atlasText .. "frame_" .. i .. NL
            atlasText = atlasText .. "  rotate: false" .. NL
            atlasText = atlasText .. "  xy: 0, 0" .. NL
            atlasText = atlasText .. "  size: " .. frameW .. ", " .. frameH .. NL
            atlasText = atlasText .. "  orig: " .. frameW .. ", " .. frameH .. NL
            atlasText = atlasText .. "  offset: 0, 0" .. NL
            atlasText = atlasText .. "  index: -1" .. NL
        end

        local atlasPath = CONFIG.output_dir .. "/" .. CONFIG.name .. ".atlas"
        local f1 = File(atlasPath, FILE_WRITE)
        f1:WriteString(atlasText)
        f1:Close()
        print("[spine] Atlas saved")

        -- 5. 生成 .json skeleton
        local cjson = require("cjson")
        local attachments = {}
        for i = 1, frameCount do
            attachments["frame_" .. i] = { x = 0, y = 0, width = frameW, height = frameH }
        end

        local attachmentTimeline = {}
        for i = 1, frameCount do
            attachmentTimeline[#attachmentTimeline + 1] = {
                time = (i - 1) * frameDuration,
                name = "frame_" .. i,
            }
        end

        local skeleton = {
            skeleton = { hash = " ", spine = "4.2", x = 0, y = 0, width = frameW, height = frameH },
            bones = { { name = "root" } },
            slots = { { name = "main", bone = "root", attachment = "frame_1" } },
            skins = { { name = "default", attachments = { main = attachments } } },
            animations = {
                [CONFIG.name] = {
                    slots = { main = { attachment = attachmentTimeline } }
                }
            },
        }

        local jsonStr = cjson.encode(skeleton)
        local jsonPath = CONFIG.output_dir .. "/" .. CONFIG.name .. ".json"
        local f2 = File(jsonPath, FILE_WRITE)
        f2:WriteString(jsonStr)
        f2:Close()
        print("[spine] JSON saved")
        print("[spine] DONE - assets/Spines/dalala/")
    end)
    if not ok then
        print("[spine] ERROR: " .. tostring(err))
    end
    engine:Exit()
end
