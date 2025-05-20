local M = {}





-- 调用7z压缩
local function compress_by_7z(default_name, path)
    -- 调用7z压缩
    local cmd_output, err_code = Command("7z") --创建7z命令执行对象
            :args({ "a","-r", "-tzip", output_file, file_path }) -- 设置压缩命令参数
            :stderr(Command.PIPED)                            -- 将标准错误重定向到管道
            :output() 

end

--! 获取需要压缩的文件列表和默认的归档文件名
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


-- 压缩方式一：
local function compress_at1()
    local name = ya.input({
        title = "Enter archive name:",
        value = "archive",
        position = { "center", w = 50 },
    })
    local paths, _ = get_compression_target()
    compress_by_7z(name, paths)     
end

local function compress_1b1()
    
    
end

local function compress_each_file(paths)
    for _, path in ipairs(paths) do
        -- 获取目录和名称
        local dir, name = path:match("^(.*)[/\\]([^/\\]+)$")
        if not dir then
            dir = "." -- 当前目录
            name = path
        end
        local output_file = dir .. "/" .. name .. ".zip" -- 生成完整输出路径
        -- 构建命令字符串
        local cmd_output, err_code = Command("7z")
            :args({ "a", "-r", "-tzip", output_file, path })
            :stderr(Command.PIPED)
            :output()

        if err_code ~= nil then
            ya.notify({
                title = "Failed to run compress command",
                content = "Status: " .. err_code,
                timeout = 5.0,
                level = "error",
            })
        elseif not cmd_output.status.success then
            ya.notify({
                title = "Compression failed: status code " .. cmd_output.status.code,
                content = cmd_output.stderr,
                timeout = 5.0,
                level = "error",
            })
        end
    end
end
--! compress_each_file s
local function compress_each_file(paths)
    for _, path in ipairs(paths) do
        local name = path:match("([^/\\]+)$") -- 获取目录名称
        local output_file = name .. ".zip" -- 生成输出文件名
        -- 构建命令字符串
        local cmd_output, err_code = Command("7z") --创建7z命令执行对象
            :args({ "a","-r", "-tzip", output_file, path }) -- 设置压缩命令参数
            :stderr(Command.PIPED)                            -- 将标准错误重定向到管道
            :output()                                         -- 执行命令并获取输出

        if err_code ~= nil then
            -- 如果命令执行失败，显示错误通知
            ya.notify({
                title = "Failed to run compress command",
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

-- compress_all_to_one 压缩所有文件到一个归档文件
local function compress_all_to_one(paths)

end
-- entry 函数用于处理用户输入并创建归档文件
function M:entry(job)
    -- 获取默认的归档格式
    local action = job.args[1]
    local default_fmt = job.args[2]
    if action == "7z" then
        -- 定义候选项
        local cand_index = ya.which({
            cands = {
                { on = "y", desc = "Yes, create dwarfs archive" },
                { on = "n", desc = "No, cancel operation" },
            },
            silent = false, -- 显示按键指示器的 UI
        })

        -- 根据用户选择的候选项执行逻辑
        if cand_index == 1 then
            -- 用户选择了 "y"
            local paths, _ = get_compression_target()
            compress_each_file(paths)
        elseif cand_index == 2 then
            -- 用户选择了 "n"
            ya.notify({
                title = "Operation Cancelled",
                content = "You chose not to create dwarfs.",
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
    elseif action == "dwarfs" then
        local _, default_name = get_compression_target()
        -- 获取用户选择的 .dwarfs 文件
        local mount_point, mount_event = ya.input({
            title = "Enter mount point path:",
            value = "j:",
            position = { "top-center", y = 3, w = 40 },
        })
        if mount_event ~= 1 then
            return -- 如果用户取消输入，退出
        end
        invoke_mount_command(default_name, mount_point)
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
