local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local rapidjson = require("rapidjson")
local _ = require("gettext")

local Updater = {}

local REPO_SLUG = "lolwierd/koreader-character-brain"
local ASSET_NAME = "characterbrain.koplugin.zip"
local CHECK_INTERVAL = 3600

local cached_release
local last_check_time
local check_in_flight = false

local function githubApi(path)
    return "https://api.github.com/repos/" .. REPO_SLUG .. path
end

local function githubWeb(path)
    return "https://github.com/" .. REPO_SLUG .. path
end

local function getInstalledVersion()
    local path = DataStorage:getDataDir() .. "/plugins/characterbrain.koplugin/_meta.lua"
    local ok, metadata = pcall(dofile, path)
    return ok and metadata and metadata.version or "0.0.0"
end

local function parseVersion(version)
    local parts = {}
    for part in tostring(version):gsub("^v", ""):gmatch("([^.]+)") do
        table.insert(parts, tonumber(part) or 0)
    end
    return parts
end

local function isNewer(candidate, installed)
    local first = parseVersion(candidate)
    local second = parseVersion(installed)
    for index = 1, math.max(#first, #second) do
        local left = first[index] or 0
        local right = second[index] or 0
        if left > right then
            return true
        elseif left < right then
            return false
        end
    end
    return false
end

local function httpGetJson(url, user_agent)
    local http = require("socket/http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local body = {}

    local ok, code = pcall(function()
        socketutil:set_timeout(
            socketutil.LARGE_BLOCK_TIMEOUT,
            socketutil.LARGE_TOTAL_TIMEOUT
        )
        local status = socket.skip(1, http.request({
            url = url,
            method = "GET",
            headers = {
                ["User-Agent"] = user_agent,
                ["Accept"] = "application/vnd.github+json",
                ["X-GitHub-Api-Version"] = "2022-11-28",
            },
            sink = socketutil.table_sink(body),
            redirect = true,
        }))
        socketutil:reset_timeout()
        return status
    end)
    if not ok then
        pcall(function()
            socketutil:reset_timeout()
        end)
        return nil
    end
    if tonumber(code) ~= 200 then
        return nil
    end
    return rapidjson.decode(table.concat(body))
end

local function findAsset(release)
    for _, asset in ipairs(release.assets or {}) do
        if asset.name == ASSET_NAME then
            return asset.browser_download_url
        end
    end
end

local function fetchLatestRelease()
    local installed = getInstalledVersion()
    local release = httpGetJson(
        githubApi("/releases/latest"),
        "KOReader-CharacterBrain/" .. installed
    )
    if not release or not release.tag_name or release.draft or release.prerelease then
        return nil
    end
    local asset_url = findAsset(release)
    if not asset_url then
        return nil
    end
    return {
        version = release.tag_name:gsub("^v", ""),
        notes = release.body or "",
        asset_url = asset_url,
    }
end

local function offerReleasesPage(message)
    local url = githubWeb("/releases")
    if Device:canOpenLink() then
        UIManager:show(ConfirmBox:new{
            text = message .. "\n\n" .. _("Open the releases page?"),
            ok_text = _("Open"),
            ok_callback = function()
                Device:openLink(url)
            end,
        })
    else
        UIManager:show(InfoMessage:new{
            text = message .. "\n" .. url,
            timeout = 5,
        })
    end
end

local function download(url, destination)
    local http = require("socket/http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local file = io.open(destination, "wb")
    if not file then
        return false
    end

    local ok, code = pcall(function()
        socketutil:set_timeout(
            socketutil.FILE_BLOCK_TIMEOUT,
            socketutil.FILE_TOTAL_TIMEOUT
        )
        local status = socket.skip(1, http.request({
            url = url,
            method = "GET",
            headers = {
                ["User-Agent"] = "KOReader-CharacterBrain/" .. getInstalledVersion(),
            },
            sink = ltn12.sink.file(file),
            redirect = true,
        }))
        socketutil:reset_timeout()
        return status
    end)
    if not ok then
        pcall(function()
            socketutil:reset_timeout()
        end)
        pcall(file.close, file)
    end
    if not ok or tonumber(code) ~= 200 then
        pcall(os.remove, destination)
        return false
    end
    return true
end

local function install(release)
    UIManager:show(InfoMessage:new{
        text = _("Downloading Character Brain update…"),
        timeout = 1,
    })

    UIManager:scheduleIn(0.1, function()
        local cache_dir = DataStorage:getSettingsDir() .. "/character_brain_cache"
        if lfs.attributes(cache_dir, "mode") ~= "directory" then
            lfs.mkdir(cache_dir)
        end
        local zip_path = cache_dir .. "/" .. ASSET_NAME
        if not download(release.asset_url, zip_path) then
            offerReleasesPage(_("Character Brain update download failed."))
            return
        end

        local plugin_path = DataStorage:getDataDir() .. "/plugins/characterbrain.koplugin"
        local ok, error_message = Device:unpackArchive(zip_path, plugin_path, true)
        pcall(os.remove, zip_path)
        if not ok then
            UIManager:show(InfoMessage:new{
                text = _("Character Brain update failed: ")
                    .. tostring(error_message),
                timeout = 5,
            })
            return
        end

        UIManager:show(ConfirmBox:new{
            text = _("Character Brain updated to v")
                .. release.version
                .. ".\n\n"
                .. _("Restart KOReader now?"),
            ok_text = _("Restart"),
            ok_callback = function()
                UIManager:restartKOReader()
            end,
        })
    end)
end

function Updater.getInstalledVersion()
    return getInstalledVersion()
end

function Updater.getAvailableVersion()
    return cached_release and cached_release.version
end

function Updater.checkBackground(on_update_found)
    if check_in_flight then
        return
    end
    local now = os.time()
    if last_check_time and now - last_check_time < CHECK_INTERVAL then
        return
    end
    if not NetworkMgr:isWifiOn() then
        return
    end

    check_in_flight = true
    last_check_time = now
    UIManager:scheduleIn(0.1, function()
        local release = fetchLatestRelease()
        check_in_flight = false
        if release and isNewer(release.version, getInstalledVersion()) then
            cached_release = release
            if on_update_found then
                on_update_found(release.version)
            end
        else
            cached_release = nil
        end
    end)
end

function Updater.check()
    NetworkMgr:runWhenOnline(function()
        UIManager:show(InfoMessage:new{
            text = _("Checking for Character Brain updates…"),
            timeout = 1,
        })
        UIManager:scheduleIn(0.1, function()
            local release = fetchLatestRelease()
            last_check_time = os.time()
            if not release then
                offerReleasesPage(_("Could not check for Character Brain updates."))
                return
            end
            if not isNewer(release.version, getInstalledVersion()) then
                cached_release = nil
                UIManager:show(InfoMessage:new{
                    text = _("Character Brain is up to date.")
                        .. "\n\nv"
                        .. getInstalledVersion(),
                    timeout = 3,
                })
                return
            end

            cached_release = release
            local viewer
            viewer = TextViewer:new{
                title = _("Character Brain update available"),
                text = _("Installed: v")
                    .. getInstalledVersion()
                    .. "\n"
                    .. _("Latest: v")
                    .. release.version
                    .. "\n\n"
                    .. release.notes,
                add_default_buttons = false,
                buttons_table = {
                    {
                        {
                            text = _("Close"),
                            callback = function()
                                UIManager:close(viewer)
                            end,
                        },
                        {
                            text = _("Update and restart"),
                            callback = function()
                                UIManager:close(viewer)
                                install(release)
                            end,
                        },
                    },
                },
            }
            UIManager:show(viewer)
        end)
    end)
end

return Updater
