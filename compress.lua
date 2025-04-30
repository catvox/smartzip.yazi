-- 定义一个辅助函数 `fail`，用于抛出格式化的错误信息
local function fail(s, ...) 
    error(string.format(s, ...)) 
end

-- 定义模块 `M`，用于封装插件的功能
local M = {}

-- 插件的初始化函数，设置远程子命令 "extract"
function M:setup()
    ps.sub_remote("extract", function(args)
        -- 如果参数只有一个，则添加 `--noisy` 标志，否则为空字符串
        local noisy = #args == 1 and ' "" --noisy' or ' ""'
        -- 遍历所有参数，向 `ya` 事件系统发送插件事件
        for _, arg in ipairs(args) do
            ya.emit("plugin", { self._id, ya.quote(arg, true) .. noisy })
        end
    end)
end

-- 插件的主要入口函数，用于处理解压任务
function M:entry(job)
    -- 从任务参数中获取源 URL 和目标 URL
    local from = job.args[1] and Url(job.args[1])
    local to = job.args[2] ~= "" and Url(job.args[2]) or nil
    -- 如果没有提供源 URL，则抛出错误
    if not from then
        fail("No URL provided")
    end

    -- 初始化密码为空字符串
    local pwd = ""
    while true do
        -- 尝试使用当前密码解压文件
        if not M:try_with(from, pwd, to) then
            break -- 如果解压成功或无需重试，则退出循环
        elseif not job.args.noisy then
            -- 如果文件需要密码且未提供，则抛出错误
            fail("'%s' is password-protected, please extract it individually and enter the password", from)
        end

        -- 弹出密码输入框，提示用户输入密码
        local value, event = ya.input {
            title = string.format('Password for "%s":', from.name),
            obscure = true, -- 隐藏输入内容（密码模式）
            position = { "center", w = 50 }, -- 设置输入框位置和宽度
        }
        if event == 1 then
            pwd = value -- 用户输入密码后更新密码变量
        else
            break -- 用户取消输入时退出循环
        end
    end
end

-- 尝试使用指定密码解压文件
function M:try_with(from, pwd, to)
    -- 如果未指定目标路径，则使用源文件的父目录
    to = to or from.parent
    if not to then
        fail("Invalid URL '%s'", from)
    end

    -- 生成临时目录名称
    local tmp = fs.unique_name(to:join(self.tmp_name(from)))
    if not tmp then
        fail("Failed to determine a temporary directory for %s", from)
    end

    -- 使用 `archive` 模块调用 7zip 解压工具
    local archive = require("archive")
    local child, err = archive.spawn_7z { "x", "-aou", "-sccUTF-8", "-p" .. pwd, "-o" .. tostring(tmp), tostring(from) }
    if not child then
        fail("Failed to start both `7zz` and `7z`, error: " .. err)
    end

    -- 等待解压完成并获取输出
    local output, err = child:wait_with_output()
    -- 如果解压失败且文件被加密，则清理临时目录并返回需要重试
    if output and output.status.code == 2 and archive.is_encrypted(output.stderr) then
        fs.remove("dir_all", tmp)
        return true -- 需要重试
    end

    -- 解压成功后整理文件
    self:tidy(from, to, tmp)
    -- 如果解压失败，则抛出错误
    if not output then
        fail("7zip failed to output when extracting '%s', error: %s", from, err)
    elseif output.status.code ~= 0 then
        fail("7zip exited when extracting '%s', error code %s", from, output.status.code)
    end
end

-- 整理解压后的文件
function M:tidy(from, to, tmp)
    -- 读取临时目录中的文件列表
    local outs = fs.read_dir(tmp, { limit = 2 })
    if not outs then
        fail("Failed to read the temporary directory '%s' when extracting '%s'", tmp, from)
    elseif #outs == 0 then
        fs.remove("dir", tmp)
        fail("No files extracted from '%s'", from)
    end

    -- 如果只有一个文件且是 tar 格式，则递归解压
    local only = #outs == 1
    if only and not outs[1].cha.is_dir and require("archive").is_tar(outs[1].url) then
        self:entry { args = { tostring(outs[1].url), tostring(to) } }
        fs.remove("file", outs[1].url)
        fs.remove("dir", tmp)
        return
    end

    -- 确定目标路径
    local target
    if only then
        target = to:join(outs[1].name)
    else
        target = to:join(self.trim_ext(from.name))
    end

    -- 确保目标路径唯一
    target = fs.unique_name(target)
    if not target then
        fail("Failed to determine a target for '%s'", from)
    end

    -- 移动文件或目录到目标路径
    target = tostring(target)
    if only and not os.rename(tostring(outs[1].url), target) then
        fail('Failed to move "%s" to "%s"', outs[1].url, target)
    elseif not only and not os.rename(tostring(tmp), target) then
        fail('Failed to move "%s" to "%s"', tmp, target)
    end
    fs.remove("dir", tmp) -- 删除临时目录
end

-- 生成临时目录名称
function M.tmp_name(url) 
    return ".tmp_" .. ya.hash(string.format("extract//%s//%.10f", url, ya.time())) 
end

-- 去除文件名的扩展名
function M.trim_ext(name)
    -- 定义支持的扩展名列表
    local exts = { ["7z"] = true, apk = true, bz2 = true, bzip2 = true, cbr = true, cbz = true, exe = true, gz = true, gzip = true, iso = true, jar = true, rar = true, tar = true, tgz = true, xz = true, zip = true, zst = true }

    -- 循环去除扩展名，直到文件名不再变化
    while true do
        local s = name:gsub("%.([a-zA-Z0-9]+)$", function(s) return (exts[s] or exts[s:lower()]) and "" end)
        if s == name or s == "" then
            break
        else
            name = s
        end
    end
    return name
end

-- 返回模块
return M