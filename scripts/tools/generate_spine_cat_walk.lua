function Start()
    local ok, err = pcall(function()
        local CONFIG = {
            name = "cat_walk",
            frames = {
                "image/cat_walk_frame_1_20260530072720.png",
                "image/cat_walk_frame_2_20260530072737.png",
                "image/cat_walk_frame_3_20260530072721.png",
                "image/cat_walk_frame_4_20260530072725.png",
            },
            fps = 8,
            output_dir = "/workspace/assets/Spines",
        }

        local frameCount = #CONFIG.frames
        local frameDuration = 1.0 / CONFIG.fps

        local firstImg = cache:GetResource("Image", CONFIG.frames[1])
        assert(firstImg, "Cannot load first frame")
        local frameW = math.floor(firstImg.width)
        local frameH = math.floor(firstImg.height)
        print("[spine] Frame size: " .. frameW .. "x" .. frameH)

        fileSystem:CreateDir(CONFIG.output_dir)

        for i = 1, frameCount do
            local srcPath = "/workspace/assets/" .. CONFIG.frames[i]
            local dstPath = CONFIG.output_dir .. "/" .. CONFIG.name .. "_frame_" .. i .. ".png"
            fileSystem:Copy(srcPath, dstPath)
            print("[spine] Copied frame " .. i)
        end

        -- Generate .atlas (multi-page)
        local NL = "\n"
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

        -- Generate .json skeleton
        local cjson = require("cjson")

        local attachments = {}
        for i = 1, frameCount do
            attachments["frame_" .. i] = {
                x = 0, y = 0,
                width = frameW, height = frameH,
            }
        end

        local attachmentTimeline = {}
        for i = 1, frameCount do
            attachmentTimeline[#attachmentTimeline + 1] = {
                time = (i - 1) * frameDuration,
                name = "frame_" .. i,
            }
        end

        local skeleton = {
            skeleton = {
                hash = " ",
                spine = "3.8.75",
                x = 0, y = 0,
                width = frameW,
                height = frameH,
            },
            bones = { { name = "root" } },
            slots = { { name = "main", bone = "root", attachment = "frame_1" } },
            skins = { default = { main = attachments } },
            animations = {
                [CONFIG.name] = {
                    slots = {
                        main = {
                            attachment = attachmentTimeline,
                        }
                    }
                }
            },
        }

        local jsonStr = cjson.encode(skeleton)
        local jsonPath = CONFIG.output_dir .. "/" .. CONFIG.name .. ".json"
        local f2 = File(jsonPath, FILE_WRITE)
        f2:WriteString(jsonStr)
        f2:Close()
        print("[spine] JSON saved")
        print("[spine] DONE - all files in " .. CONFIG.output_dir)
    end)

    if not ok then
        print("[spine] ERROR: " .. tostring(err))
    end
    engine:Exit()
end
