local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")

local Updater = {
    REPO_OWNER = "olundberg",
    REPO_NAME = "koreader_tabata_timer",
    BRANCH = "main",
}

function Updater.fetch(url)
    local resp = {}
    socketutil:set_timeout(10, 25)
    local _, code, headers, status = https.request{
        url = url,
        sink = ltn12.sink.table(resp),
        headers = {
            ["User-Agent"] = "KOReader-Tabata-Timer",
            ["Accept"] = "application/vnd.github.v3+json",
        }
    }
    return code, table.concat(resp)
end

function Updater.checkAndUpdate(plugin_path, on_finish)
    NetworkMgr:runWhenOnline(function()
        local info = InfoMessage:new{
            text = _("Checking for Tabata Timer updates..."),
            timeout = 5,
        }
        UIManager:show(info)

        local apiUrl = string.format("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1",
            Updater.REPO_OWNER, Updater.REPO_NAME, Updater.BRANCH)

        local code, body = Updater.fetch(apiUrl)
        UIManager:close(info)

        if code ~= 200 then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Could not check for updates.\nHTTP error: %s"), tostring(code)),
            })
            if on_finish then on_finish(false) end
            return
        end

        local ok, data = pcall(JSON.decode, body)
        if not ok or not data or not data.tree then
            UIManager:show(InfoMessage:new{
                text = _("Invalid response received from GitHub API."),
            })
            if on_finish then on_finish(false) end
            return
        end

        local remote_tree_sha = data.sha
        local version_file = plugin_path .. "/.version"
        local local_version = util.readFromFile(version_file, "rb") or ""
        local_version = local_version:gsub("%s+", "")

        -- Filter core files & workout files from tree
        local core_files = {}
        local remote_workouts = {}

        for _, item in ipairs(data.tree) do
            if item.type == "blob" then
                if item.path == "main.lua" or item.path == "parser.lua" or item.path == "_meta.lua" or item.path == "updater.lua" then
                    table.insert(core_files, item.path)
                elseif item.path:match("^workouts/[^/]+%.[cC][sS][vV]$") then
                    local filename = item.path:match("^workouts/(.+)$")
                    table.insert(remote_workouts, {
                        path = item.path,
                        filename = filename,
                    })
                end
            end
        end

        -- Check if anything is new/modified or if versions differ
        if local_version == remote_tree_sha and local_version ~= "" then
            UIManager:show(InfoMessage:new{
                text = _("Tabata Timer is already up to date!"),
                timeout = 3,
            })
            if on_finish then on_finish(false) end
            return
        end

        UIManager:show(ConfirmBox:new{
            text = _("An update for Tabata Timer is available.\n\nDo you want to download and install it now?"),
            ok_text = _("Update"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                Updater.performDownload(plugin_path, remote_tree_sha, core_files, remote_workouts, on_finish)
            end,
            cancel_callback = function()
                if on_finish then on_finish(false) end
            end,
        })
    end)
end

function Updater.performDownload(plugin_path, remote_tree_sha, core_files, remote_workouts, on_finish)
    local progress_info = InfoMessage:new{
        text = _("Downloading Tabata Timer update..."),
        timeout = 10,
    }
    UIManager:show(progress_info)

    local rawBase = string.format("https://raw.githubusercontent.com/%s/%s/%s/",
        Updater.REPO_OWNER, Updater.REPO_NAME, Updater.BRANCH)

    -- 1. Download core files
    for _, path in ipairs(core_files) do
        local code, content = Updater.fetch(rawBase .. path)
        if code == 200 and content and content ~= "" then
            local target_path = plugin_path .. "/" .. path
            util.writeToFile(content, target_path)
        end
    end

    -- 2. Process workouts with Option 3 (Conflict Prompting / .new backup)
    local conflicts = {}
    for _, workout in ipairs(remote_workouts) do
        local local_path = plugin_path .. "/workouts/" .. workout.filename
        local local_content = util.readFromFile(local_path, "rb")

        local code, remote_content = Updater.fetch(rawBase .. workout.path)
        if code == 200 and remote_content and remote_content ~= "" then
            if not local_content or local_content == "" then
                -- New workout from repository: add directly
                util.writeToFile(remote_content, local_path)
            elseif local_content ~= remote_content then
                -- Conflict: local workout exists and differs from repository
                table.insert(conflicts, {
                    filename = workout.filename,
                    local_path = local_path,
                    remote_content = remote_content,
                })
            end
        end
    end

    UIManager:close(progress_info)

    local function finalizeUpdate()
        util.writeToFile(remote_tree_sha, plugin_path .. "/.version")
        UIManager:show(ConfirmBox:new{
            text = _("Update installed successfully!\n\nRestart KOReader now to apply the changes?"),
            ok_text = _("Restart"),
            cancel_text = _("Later"),
            ok_callback = function()
                UIManager:restartKOReader()
            end,
            cancel_callback = function()
                if on_finish then on_finish(true) end
            end,
        })
    end

    local function resolveConflict(index)
        if index > #conflicts then
            finalizeUpdate()
            return
        end

        local conflict = conflicts[index]
        local conflict_dialog
        conflict_dialog = ButtonDialog:new{
            title = string.format(_("Workout Conflict: %s"), conflict.filename),
            buttons = {
                {
                    {
                        text = _("Keep My Local Version"),
                        callback = function()
                            UIManager:close(conflict_dialog)
                            resolveConflict(index + 1)
                        end,
                    },
                },
                {
                    {
                        text = _("Overwrite with Online Version"),
                        callback = function()
                            UIManager:close(conflict_dialog)
                            util.writeToFile(conflict.remote_content, conflict.local_path)
                            resolveConflict(index + 1)
                        end,
                    },
                },
                {
                    {
                        text = _("Save Online Version as .new.csv"),
                        callback = function()
                            UIManager:close(conflict_dialog)
                            local new_path = conflict.local_path:gsub("%.[cC][sS][vV]$", ".new.csv")
                            util.writeToFile(conflict.remote_content, new_path)
                            resolveConflict(index + 1)
                        end,
                    },
                },
            },
        }
        UIManager:show(conflict_dialog)
    end

    if #conflicts > 0 then
        resolveConflict(1)
    else
        finalizeUpdate()
    end
end

return Updater
