---
name: generate-spine
description: "生成帧动 Spine 动画资产（.json + .atlas + 纹理图集）。Use when users need to (1) 生成 Spine 帧动画, (2) 把多帧图片打包成 Spine 动画, (3) 创建序列帧 Spine 资产, (4) generate spine animation, (5) 用户说'做一个帧动画'或'生成角色动画', (6) 需要为 UI.Spine 组件生成可播放的 Spine 动画资产, (7) 从 AI 生成图或现有图片制作 Spine 帧动画。当用户提到'帧动画'、'序列帧'、'Spine 动画'、'spine'、'骨骼动画帧图'等关键词时，即使没有明确说'生成 Spine'，也应该使用此 skill。"
---

# 生成帧动 Spine 动画

## 概述

本 skill 指导如何从多帧图片生成 UrhoX 可用的 Spine 帧动画资产。最终产物是一套标准 Spine 文件（`.json` skeleton + `.atlas` + 帧纹理 `.png`），可直接由 `UI.Spine` 组件加载播放。

**帧动 Spine 动画**的本质：把多张图片（序列帧）打包为一个 Spine skeleton，通过 attachment 切换实现逐帧播放——无需真正的骨骼绑定，结构简单但表现力完整。

---

## 工作流程

```
确定动画需求（帧数、尺寸、主题）
        ↓
生成/收集帧图片（AI 生成或用户提供）
        ↓
用 Lua headless 脚本打包为 Spine 资产
        ↓
在项目中用 UI.Spine 加载播放
```

---

## 第一步：准备帧图片

### 方式 A：AI 生成帧图片

使用 `batch_generate_images` 工具批量生成。关键原则：

- **透明背景**：帧动画通常需要透明底，prompt 中加入"透明背景"
- **一致性**：所有帧使用相同 seed 基础 + 描述变化，确保风格统一
- **尺寸统一**：所有帧使用相同 `target_size`（推荐 256x256 或 512x512）
- **命名规则**：`{动画名}_frame_{序号}`，从 1 开始

```
示例：4 帧跑步动画
- run_frame_1.png  (右脚前迈)
- run_frame_2.png  (腾空)
- run_frame_3.png  (左脚前迈)
- run_frame_4.png  (腾空2)
```

### 方式 B：用户提供帧图片

用户已有帧图片时，确认：
1. 所有帧尺寸一致
2. 格式为 PNG（推荐带透明通道）
3. 帧图片路径相对于 `assets/` 目录

---

## 第二步：用 Lua 脚本打包

创建打包脚本放在 `scripts/tools/` 目录下。脚本使用 **多页 atlas 方式**（每帧一个 PNG 文件），这是最稳定可靠的方案。

### 打包脚本模板

```lua
function Start()
    local ok, err = pcall(function()
        -- ============ 配置区 ============
        local CONFIG = {
            name = "run",           -- 动画名（也用作文件名前缀）
            frames = {              -- 帧图片路径（相对于 assets/ 的资源路径）
                "Textures/run_frame_1.png",
                "Textures/run_frame_2.png",
                "Textures/run_frame_3.png",
                "Textures/run_frame_4.png",
            },
            fps = 8,                -- 帧率
            output_dir = "/workspace/assets/Spines",  -- 输出目录（绝对路径）
        }
        -- ============ 配置区结束 ============

        local frameCount = #CONFIG.frames
        local frameDuration = 1.0 / CONFIG.fps

        -- 1. 读取第一帧获取尺寸
        local firstImg = cache:GetResource("Image", CONFIG.frames[1])
        assert(firstImg, "Cannot load first frame: " .. CONFIG.frames[1])
        local frameW = math.floor(firstImg.width)   -- 转整数！Image.width 返回浮点
        local frameH = math.floor(firstImg.height)
        print("[spine] Frame size: " .. frameW .. "x" .. frameH)

        -- 2. 创建输出目录
        fileSystem:CreateDir(CONFIG.output_dir)

        -- 3. 复制帧图片到输出目录（重命名为统一格式）
        for i = 1, frameCount do
            local srcPath = "/workspace/assets/" .. CONFIG.frames[i]
            local dstPath = CONFIG.output_dir .. "/" .. CONFIG.name .. "_frame_" .. i .. ".png"
            fileSystem:Copy(srcPath, dstPath)
            print("[spine] Copied frame " .. i)
        end

        -- 4. 生成 .atlas（多页格式，每帧一页）
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
        print("[spine] Atlas saved: " .. atlasPath)

        -- 5. 生成 .json skeleton
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
                spine = "4.2",
                x = 0, y = 0,
                width = frameW,
                height = frameH,
            },
            bones = { { name = "root" } },
            slots = { { name = "main", bone = "root", attachment = "frame_1" } },
            skins = { { name = "default", attachments = { main = attachments } } },
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
        print("[spine] JSON saved: " .. jsonPath)
        print("[spine] DONE - output: " .. CONFIG.output_dir)
    end)

    if not ok then
        print("[spine] ERROR: " .. tostring(err))
    end
    engine:Exit()
end
```

### 重要 API 细节

| API | 正确用法 | 常见错误 |
|-----|---------|---------|
| File 构造 | `File(path, FILE_WRITE)` | ~~`File:new(path, ...)`~~ |
| 写入字符串 | `f:WriteString(str)` | ~~`f:Write(str)`~~（会崩溃） |
| 创建目录 | `fileSystem:CreateDir(path)` | ~~`os.execute("mkdir -p")`~~ |
| Image 尺寸 | `math.floor(img.width)` | 直接用 `img.width`（浮点数） |
| 资源加载 | `cache:GetResource("Image", path)` | path 相对 assets/，不加前缀 |
| JSON 编码 | `require("cjson").encode(tbl)` | 可用，headless 环境已内置 |

### 执行打包脚本

使用 `run-lua-headless` skill 执行此脚本：

```bash
/workspace/.cli/UrhoXRuntime tools/generate_spine_frames.lua -tapcode_dir=/workspace -tool_mode
```

脚本产出的文件会出现在 `CONFIG.output_dir` 指定的目录下。

---

## 第三步：在项目中使用

生成的文件结构（多页 atlas 模式）：

```
assets/Spines/
├── run.json            ← skeleton 文件
├── run.atlas           ← 图集描述（多页）
├── run_frame_1.png     ← 帧纹理 1
├── run_frame_2.png     ← 帧纹理 2
├── run_frame_3.png     ← 帧纹理 3
└── run_frame_4.png     ← 帧纹理 4
```

在 Lua 中使用 `UI.Spine` 加载：

```lua
local UI = require("urhox-libs/UI")

local animSpine = UI.Spine {
    src = "Spines/run.json",    -- 引擎自动找同目录的 .atlas 和纹理
    animation = "run",          -- 与 CONFIG.name 一致
    loop = true,
    width = 256, height = 256,
}
```

**路径注意**：`src` 相对于 `assets/` 目录，不加 `assets/` 前缀（引擎规则 #1.5）。

---

## 关键参数参考

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| fps | 6-12 | 帧率越高越流畅，但需要更多帧 |
| 帧尺寸 | 256x256 或 512x512 | 根据游戏内显示大小决定 |
| 帧数 | 4-12 | 4 帧最简，8-12 帧流畅 |
| 图片格式 | PNG (RGBA) | 带透明通道 |

---

## Spine JSON 格式核心结构

帧动画的 Spine JSON 非常简洁：

```json
{
  "skeleton": { "spine": "4.2", "width": 256, "height": 256 },
  "bones": [{ "name": "root" }],
  "slots": [{ "name": "main", "bone": "root", "attachment": "frame_1" }],
  "skins": [
    {
      "name": "default",
      "attachments": {
        "main": {
          "frame_1": { "width": 256, "height": 256 },
          "frame_2": { "width": 256, "height": 256 }
        }
      }
    }
  ],
  "animations": {
    "idle": {
      "slots": {
        "main": {
          "attachment": [
            { "time": 0, "name": "frame_1" },
            { "time": 0.125, "name": "frame_2" }
          ]
        }
      }
    }
  }
}
```

核心原理：一个 slot 持有多个 attachment（每帧一个），动画通过 `attachment` timeline 按时间切换显示的 attachment。

---

## 多动画支持

一个 skeleton 可以包含多个动画（idle、run、attack），共享同一套帧资源：

```lua
-- 在打包脚本的 CONFIG 中定义多个动画
local CONFIG = {
    name = "character",
    all_frames = {
        "Textures/char_idle_1.png", "Textures/char_idle_2.png",     -- 帧 1-2 (idle)
        "Textures/char_run_1.png", "Textures/char_run_2.png",       -- 帧 3-4 (run)
        "Textures/char_run_3.png", "Textures/char_run_4.png",       -- 帧 5-6 (run)
    },
    animations = {
        idle = { frame_indices = {1, 2}, fps = 6 },
        run  = { frame_indices = {3, 4, 5, 6}, fps = 10 },
    },
    output_dir = "/workspace/assets/Spines",
}
```

生成多动画时，所有帧仍复制到同一目录，JSON 中 `animations` 表包含多个 key，每个动画引用自己的帧子集。

使用时切换动画：

```lua
animSpine:SetAnimation("idle", true)   -- 循环播放 idle
animSpine:SetAnimation("run", true)    -- 切换到 run
animSpine:SetAnimation("attack", false) -- 播放一次 attack
```

---

## 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| Spine 加载失败 | .atlas 和 .json 不在同目录 | 确保 .json .atlas 和帧 PNG 都在同一目录 |
| 动画不播放 | animation 名称不匹配 | 检查 JSON 的 animations key 与代码中 SetAnimation 参数一致 |
| 图片显示空白 | atlas 中 region 名或文件名不匹配 | atlas 页名必须与实际 PNG 文件名完全一致 |
| 帧图片风格不一致 | AI 生成未固定 seed | 使用 reference_images 确保一致性 |
| 脚本崩溃无输出 | `File:Write()` 而非 `WriteString` | 必须用 `f:WriteString(str)`！ |
| atlas 中尺寸带小数 | Image.width 返回浮点 | 用 `math.floor()` 转整数 |
| 资源路径找不到 | 路径前缀错误 | cache:GetResource 路径不要加 "assets/" 前缀 |

---

## 完整工作流示例

### 示例：为角色生成 4 帧跑步动画

```
1. 用 batch_generate_images 生成 4 帧透明背景跑步图
   - target_size: "256x256", transparent: true
   - prompt 依次描述每帧动作

2. 帧图片保存到 assets/image/ 下（AI 工具默认位置）

3. 将打包脚本写入 scripts/tools/generate_spine_run.lua
   - 修改 CONFIG.frames 指向实际帧图片路径
   - 设置 fps=8, name="run", output_dir="/workspace/assets/Spines"

4. 用 UrhoXRuntime headless 执行打包脚本

5. 产出: assets/Spines/run.{json,atlas} + run_frame_*.png

6. 游戏代码中加载:
   UI.Spine { src = "Spines/run.json", animation = "run", loop = true }
```
