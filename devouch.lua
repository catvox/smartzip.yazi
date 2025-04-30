local M = {}
-- 功能函数:file_exists 检查文件是否存在
local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

-- 功能函数:is_directory,判断选中的文件是文件夹还是文件
local function is_directory(file)
    -- 检查文件对象是否有 is_dir 属性
    if file and file.is_dir ~= nil then
        return file.is_dir -- 如果是文件夹，返回 true；否则返回 false
    end
    -- 如果没有 is_dir 属性，可以通过其他方式判断
    -- 例如检查文件路径是否以斜杠结尾（仅适用于某些系统）
    local path = tostring(file.url)
    return path:sub(-1) == "/" or path:sub(-1) == "\\"
end

-- 功能函数:get_selected_files,获取当前活动标签页的文件夹列表和文件列表,获得选择的文件夹列表fold_list和选择的文件列表file_list
-- local get_selected_files = ya.sync(function()
--     local tab = cx.active                  -- 获取当前活动标签页
--     local fold_list = {}                   -- 初始化文件夹列表
--     local file_list = {}                   -- 初始化文件列表

--     for _, file in ipairs(tab.selected) do -- 遍历选中的文件
--         if is_directory(file) then
--             table.insert(fold_list, file)  -- 如果是文件夹，添加到文件夹列表
--         else
--             table.insert(file_list, file)  -- 否则添加到文件列表
--         end
--     end

--     return fold_list, file_list -- 返回文件夹列表和文件列表
-- end)


-- 获取需要压缩的文件列表和默认的归档文件名
local get_compression_target = ya.sync(function()
    -- 获取当前活动标签页:
    local tab = cx.active
    -- 初始化变量:
    local default_name
    local paths = {}
    -- 检查选中的文件数量:如果没有选中的文件或文件夹，则进入此分支。
    if #tab.selected == 0 then
        -- 如果当前有悬停的文件或文件夹：
        if tab.current.hovered then
            -- 获取当前悬停(hovered)名称并赋值给 default_name。
            local name = tab.current.hovered.name
            default_name = name
            -- 将其名称插入到 paths 列表中。
            table.insert(paths, name)
        else
            return
        end
    else
        -- 获取当前工作目录的名称并赋值给 default_name。
        default_name = tab.current.cwd.name
        -- 遍历所有选中的文件或文件夹，
        for _, url in pairs(tab.selected) do
            -- 将其路径转换为字符串并插入到 paths 列表中。
            table.insert(paths, tostring(url))
        end
        -- 取消选中的文件
        ya.manager_emit("escape", {})
    end
    return paths, default_name
end)

local function invoke_7z_command(paths)
    for _, path in ipairs(path) do
        local file_name = path:match("([^/\\]+)$") -- 获取目录名称
        local archive_name = file_name .. ".zip"   -- 生成输出文件名
        local cmd_output, err_code = Command("7z") --创建7z命令执行对象
            :args({ "a","-r", archive_name, path })     -- 设置压缩命令参数
            :stderr(Command.PIPED)                 -- 将标准错误重定向到管道
            :output()

        if err_code ~= nil then
            -- 如果命令执行失败，显示错误通知
            ya.notify({
                title = "Failed to run 7z command",
                content = "Status: " .. err_code,
                timeout = 5.0,
                level = "error",
            })
        elseif not cmd_output.status.success then
            -- 如果命令执行失败，显示错误通知
            ya.notify({
                title = "Compression failed: status code " .. cmd_output.status.code,
                content = cmd_output.stderr,
                timeout = 5.0,
                level = "error",
            })
        end
    end
end


local function invoke_compress_command(paths)
    for _, path in ipairs(paths) do
        local name = path:match("([^/\\]+)$") -- 获取目录名称
        local output_file = name .. ".dwarfs" -- 生成输出文件名

        -- 构建命令字符串
        local cmd_output, err_code = Command("mkdwarfs")      --创建mkdwarfs命令执行对象
            :args({ "-i", path, "-o", output_file, "-N", 6 }) -- 设置压缩命令参数
            :stderr(Command.PIPED)                            -- 将标准错误重定向到管道
            :output()                                         -- 执行命令并获取输出

        if err_code ~= nil then
            -- 如果命令执行失败，显示错误通知
            ya.notify({
                title = "Failed to run dwarfs command",
                content = "Status: " .. err_code,
                timeout = 5.0,
                level = "error",
            })
        elseif not cmd_output.status.success then
            -- 如果命令执行失败，显示错误通知
            ya.notify({
                title = "Compression failed: status code " .. cmd_output.status.code,
                content = cmd_output.stderr,
                timeout = 5.0,
                level = "error",
            })
        end
    end
end


-- entry 主程入口函数格式
function M:entry(job)
    -- 获取默认的归档格式
    local action = job.args[1]
    local default_fmt = job.args[2]
    if action == "archive" then
        -- 定义候选项
        local cand_index = ya.which({
            cands = {
                { on = "y", desc = "Yes, create zip archive" },
                { on = "n", desc = "No, cancel operation" },
            },
            silent = false, -- 显示按键指示器的 UI
        })

        -- 根据用户选择的候选项执行逻辑
        if cand_index == 1 then
            -- 用户选择了 "y"
            local paths, _ = get_compression_target()
            ya.dbg("paths=","patherror"paths)
            ya.hide()
            invoke_7z_command(paths)
            ya.dbg("errir",invoke_7z_command(paths))
        elseif cand_index == 2 then
            -- 用户选择了 "n"
            ya.notify({
                title = "Operation Cancelled",
                content = "You chose not to create zip.",
                timeout = 3.0,
                level = "info",
            })
            return
        else
            -- 用户取消了操作或输入无效
            ya.notify({
                title = "No Action Selected",
                content = "You did not select a valid option.",
                timeout = 3.0,
                level = "warn",
            })
            return
        end
        -- if use dwarfs mount command
    else
        ya.notify({
            title = "Invalid action",
            content = "Unknown action: " .. action,
            timeout = 5.0,
            level = "error",
        })
    end
end

return M
