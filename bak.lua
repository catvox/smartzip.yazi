local M = {}
-- 发送错误通知
local function notify_error(message, urgency)
    ya.notify({
        title = "Archive", -- 压缩
        content = message, -- 消息内容
        level = urgency,   -- 紧急程度
        timeout = 5,       -- 超时时间为5秒
    })
end

-- 检查是否为 Windows 系统
local is_windows = ya.target_family() == "windows"

-- 创建选中或悬停的文件路径表：path = 文件名
local selected_or_hovered = ya.sync(function()
    local tab, paths, names, path_fnames = cx.active, {}, {}, {}
    for _, u in pairs(tab.selected) do
        paths[#paths + 1] = tostring(u:parent()) -- 获取文件的父路径
        names[#names + 1] = tostring(u:name())   -- 获取文件名
    end
    if #paths == 0 and tab.current.hovered then
        paths[1] = tostring(tab.current.hovered.url:parent()) -- 如果没有选中，获取悬停文件的父路径
        names[1] = tostring(tab.current.hovered.name)         -- 获取悬停文件名
    end
    for idx, name in ipairs(names) do
        if not path_fnames[paths[idx]] then
            path_fnames[paths[idx]] = {}
        end
        table.insert(path_fnames[paths[idx]], name) -- 将文件名插入对应路径的表中
    end
    return path_fnames, tostring(tab.current.cwd)   -- 返回路径-文件名表和当前工作目录
end)

-- 检查命令是否可用
local function is_command_available(cmd)
    local stat_cmd

    if is_windows then
        stat_cmd = string.format("where %s > nul 2>&1", cmd)           -- Windows 系统使用 `where` 检查命令
    else
        stat_cmd = string.format("command -v %s >/dev/null 2>&1", cmd) -- 非 Windows 系统使用 `command -v`
    end

    local cmd_exists = os.execute(stat_cmd)
    if cmd_exists then
        return true  -- 命令可用
    else
        return false -- 命令不可用
    end
end

-- 在命令列表中查找可用的命令
local function find_binary(cmd_list)
    for _, cmd in ipairs(cmd_list) do
        if is_command_available(cmd) then
            return cmd -- 返回第一个可用的命令
        end
    end
    return cmd_list[1] -- 如果没有可用命令，返回列表中的第一个命令作为回退
end

-- 检查文件是否存在
local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true  -- 文件存在
    else
        return false -- 文件不存在
    end
end

-- 将文件名附加到其父目录
local function combine_url(path, file)
    path, file = Url(path), Url(file)
    return tostring(path:join(file)) -- 返回拼接后的路径
end

function M:entry(job)
    -- 定义文件表和输出目录（当前工作目录）
    local path_fnames, output_dir = selected_or_hovered()

    -- 获取模式选择的输入
    local mode, event = ya.input({
        title = "选择模式：(1) 单一压缩包, (2) 分别压缩",
        position = { "top-center", y = 3, w = 40 },
    })
    if event ~= 1 then
        return
    end

    -- 获取输出文件名的输入
    local output_name, event = ya.input({
        title = "创建压缩包：",
        position = { "top-center", y = 3, w = 40 },
    })
    if event ~= 1 then
        return
    end

    -- 使用适当的压缩命令
    local archive_commands = {
        ["%.zip$"] = { command = "zip", args = { "-r" } },
        ["%.7z$"] = { command = { "7z", "7zz" }, args = { "a" } },
        ["%.tar.gz$"] = { command = "tar", args = { "rpf" }, compress = "gzip" },
        ["%.tar.xz$"] = { command = "tar", args = { "rpf" }, compress = "xz" },
        ["%.tar.bz2$"] = { command = "tar", args = { "rpf" }, compress = "bzip2" },
        ["%.tar.zst$"] = { command = "tar", args = { "rpf" }, compress = "zstd", compress_args = { "--rm" } },
        ["%.tar$"] = { command = "tar", args = { "rpf" } },
    }

    if is_windows then
        archive_commands = {
            ["%.zip$"] = { command = "7z", args = { "a", "-tzip" } },
            ["%.7z$"] = { command = "7z", args = { "a" } },
            ["%.tar.gz$"] = {
                command = "tar",
                args = { "rpf" },
                compress = "7z",
                compress_args = { "a", "-tgzip", "-sdel", output_name },
            },
            ["%.tar.xz$"] = {
                command = "tar",
                args = { "rpf" },
                compress = "7z",
                compress_args = { "a", "-txz", "-sdel", output_name },
            },
            ["%.tar.bz2$"] = {
                command = "tar",
                args = { "rpf" },
                compress = "7z",
                compress_args = { "a", "-tbzip2", "-sdel", output_name },
            },
            ["%.tar.zst$"] = { command = "tar", args = { "rpf" }, compress = "zstd", compress_args = { "--rm" } },
            ["%.tar$"] = { command = "tar", args = { "rpf" } },
        }
    end

    -- 匹配用户输入的压缩命令
    local archive_cmd, archive_args, archive_compress, archive_compress_args
    for pattern, cmd_pair in pairs(archive_commands) do
        if output_name:match(pattern) then
            archive_cmd = cmd_pair.command
            archive_args = cmd_pair.args
            archive_compress = cmd_pair.compress
            archive_compress_args = cmd_pair.compress_args or {}
        end
    end

    -- 检查压缩命令是否有多个名称
    if type(archive_cmd) == "table" then
        archive_cmd = find_binary(archive_cmd)
    end

    -- 检查是否没有可用的压缩命令
    if not archive_cmd then
        notify_error("不支持的文件扩展名", "error")
        return
    end

    -- 如果压缩命令不可用则退出
    if not is_command_available(archive_cmd) then
        notify_error(string.format("%s 不可用", archive_cmd), "error")
        return
    end

    -- 如果压缩工具不可用则退出
    if archive_compress and not is_command_available(archive_compress) then
        notify_error(string.format("%s 压缩不可用", archive_compress), "error")
        return
    end

    if mode == "1" then
        -- 单一压缩包模式
        local output_url = combine_url(output_dir, output_name)
        while true do
            if file_exists(output_url) then
                local overwrite_answer = ya.input({
                    title = "覆盖 " .. output_name .. "? y/N:",
                    position = { "top-center", y = 3, w = 40 },
                })
                if overwrite_answer:lower() ~= "y" then
                    notify_error("操作已取消", "warn")
                    return     -- 如果不覆盖则退出
                else
                    local rm_status, rm_err = os.remove(output_url)
                    if not rm_status then
                        notify_error(string.format("删除 %s 失败，错误码 %s", output_name, rm_err), "error")
                        return
                    end     -- 如果覆盖失败则退出
                end
            end
            if archive_compress and not output_name:match("%.tar$") then
                output_name = output_name:match("(.*%.tar)")          -- 测试 .tar 和 .tar.*
                output_url = combine_url(output_dir, output_name)     -- 更新输出路径
            else
                break
            end
        end

        -- 将每个路径中的文件添加到输出压缩包
        for path, names in pairs(path_fnames) do
            local archive_status, archive_err =
                Command(archive_cmd):args(archive_args):arg(output_url):args(names):cwd(path):spawn():wait()
            if not archive_status or not archive_status.success then
                notify_error(
                    string.format(
                        "%s 处理选中文件失败，错误码 %s",
                        archive_args,
                        archive_status and archive_status.code or archive_err
                    ),
                    "error"
                )
            end
        end

        -- 如果需要，使用压缩工具
        if archive_compress then
            local compress_status, compress_err =
                Command(archive_compress):args(archive_compress_args):arg(output_name):cwd(output_dir):spawn():wait()
            if not compress_status or not compress_status.success then
                notify_error(
                    string.format(
                        "%s 处理 %s 失败，错误码 %s",
                        archive_compress,
                        output_name,
                        compress_status and compress_status.code or compress_err
                    ),
                    "error"
                )
            end
        end
    elseif mode == "2" then
        -- 分别压缩模式
        for path, names in pairs(path_fnames) do
            local individual_output_name = output_name:gsub("%%s", path:match("([^/\\]+)$"))
            local output_url = combine_url(output_dir, individual_output_name)

            while true do
                if file_exists(output_url) then
                    local overwrite_answer = ya.input({
                        title = "覆盖 " .. individual_output_name .. "? y/N:",
                        position = { "top-center", y = 3, w = 40 },
                    })
                    if overwrite_answer:lower() ~= "y" then
                        notify_error("操作已取消", "warn")
                        return     -- 如果不覆盖则退出
                    else
                        local rm_status, rm_err = os.remove(output_url)
                        if not rm_status then
                            notify_error(string.format("删除 %s 失败，错误码 %s", individual_output_name, rm_err), "error")
                            return
                        end     -- 如果覆盖失败则退出
                    end
                end
                if archive_compress and not individual_output_name:match("%.tar$") then
                    individual_output_name = individual_output_name:match("(.*%.tar)")     -- 测试 .tar 和 .tar.*
                    output_url = combine_url(output_dir, individual_output_name)           -- 更新输出路径
                else
                    break
                end
            end

            local archive_status, archive_err =
                Command(archive_cmd):args(archive_args):arg(output_url):args(names):cwd(path):spawn():wait()
            if not archive_status or not archive_status.success then
                notify_error(
                    string.format(
                        "%s 处理选中文件失败，错误码 %s",
                        archive_args,
                        archive_status and archive_status.code or archive_err
                    ),
                    "error"
                )
            end

            -- 如果需要，使用压缩工具
            if archive_compress then
                local compress_status, compress_err =
                    Command(archive_compress):args(archive_compress_args):arg(individual_output_name):cwd(output_dir)
                    :spawn():wait()
                if not compress_status or not compress_status.success then
                    notify_error(
                        string.format(
                            "%s 处理 %s 失败，错误码 %s",
                            archive_compress,
                            individual_output_name,
                            compress_status and compress_status.code or compress_err
                        ),
                        "error"
                    )
                end
            end
        end
    else
        notify_error("选择的模式无效", "error")
    end
end

return M
