local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local rapidjson = require("rapidjson")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local DB = require("characterbrain_db")
local Extractor = require("characterbrain_extractor")
local Backend = require("characterbrain_backend")
local CBUtil = require("characterbrain_util")
local Validator = require("characterbrain_validator")

local CharacterBrain = WidgetContainer:extend{
    name = "characterbrain",
    is_doc_only = true,
}

local settings_path = DataStorage:getSettingsDir() .. "/character_brain.lua"

local default_settings = {
    backend_url = "",
    access_token = "",
    privacy_consent = false,
}

local evidence_kind_titles = {
    description = _("Description"),
    action = _("Action"),
    speech = _("Speech"),
    status = _("Status"),
}

local function copyDefaults(settings)
    for key, value in pairs(default_settings) do
        if settings[key] == nil then
            settings[key] = value
        end
    end
    return settings
end

function CharacterBrain:init()
    self.settings_store = LuaSettings:open(settings_path)
    self.settings = copyDefaults(self.settings_store:readSetting("provider", {}))
    DB.init()
    self.ui.menu:registerToMainMenu(self)
    self.ui.highlight:addToHighlightDialog("07_5_character_brain", function(highlight)
        return {
            text = _("Character Brain"),
            show_in_highlight_dialog_func = function()
                return Extractor.isSupported(self.ui.document)
                    and highlight.selected_text
                    and CBUtil.normalizeWhitespace(highlight.selected_text.text) ~= ""
            end,
            callback = function()
                local selected = highlight.selected_text
                local query = CBUtil.normalizeWhitespace(selected.text)
                local boundary = selected.pos1
                highlight:onClose(true)
                UIManager:scheduleIn(0.1, function()
                    self:lookup(query, boundary)
                end)
            end,
        }
    end)
end

function CharacterBrain:onCloseDocument()
    if self.ui and self.ui.highlight then
        self.ui.highlight:removeFromHighlightDialog("07_5_character_brain")
    end
end

function CharacterBrain:saveSettings()
    self.settings_store:saveSetting("provider", self.settings)
    self.settings_store:flush()
end

function CharacterBrain:getBookFingerprint()
    local attributes = lfs.attributes(self.ui.document.file) or {}
    return table.concat({
        util.partialMD5(self.ui.document.file) or "",
        tostring(attributes.size or ""),
        tostring(attributes.modification or ""),
        tostring(self.ui.doc_settings:readSetting("cre_dom_version", "")),
    }, ":")
end

function CharacterBrain:getBook()
    local fingerprint = self:getBookFingerprint()
    local title = self.ui.doc_props and self.ui.doc_props.display_title or self.ui.document.file
    local id = DB.getOrCreateBook(fingerprint, self.ui.document.file, title)
    return id, title
end

function CharacterBrain:normalizeBoundary(boundary)
    return self.ui.document:getNormalizedXPointer(boundary) or boundary
end

function CharacterBrain:lookup(query, boundary)
    if #query > 80 then
        UIManager:show(InfoMessage:new{
            text = _("Select a character name of 80 characters or fewer."),
        })
        return
    end
    if self.settings.backend_url == "" then
        self:showBackendSettings(_("Configure your Character Brain backend before the first lookup."))
        return
    end

    boundary = self:normalizeBoundary(boundary)
    if not self.ui.document:isXPointerInDocument(boundary) then
        UIManager:show(InfoMessage:new{
            text = _("The selected book location is not valid."),
        })
        return
    end

    local book_id = self:getBook()
    local cached, cached_passages = DB.getAnalysis(book_id, query, boundary)
    if cached then
        self:showProfile(query, boundary, cached, cached_passages)
        return
    end

    local names = { query }
    for _, alias in ipairs(DB.getKnownAliases(book_id, query)) do
        table.insert(names, alias)
    end
    local passages = Extractor.collect(self.ui.document, names, boundary)
    if #passages == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No earlier passages containing this name were found."),
        })
        return
    end

    if not self.settings.privacy_consent then
        self:showConsent(query, boundary, book_id, passages)
        return
    end
    self:runAnalysis(query, boundary, book_id, passages)
end

function CharacterBrain:showConsent(query, boundary, book_id, passages)
    local request_preview = rapidjson.encode(
        Backend.buildPayload(query, passages),
        { pretty = true }
    )
    local viewer
    viewer = TextViewer:new{
        title = _("Character Brain request preview"),
        text = request_preview,
        text_type = "code",
        buttons_table = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        viewer:onClose()
                    end,
                },
                {
                    text = _("Send and remember"),
                    callback = function()
                        self.settings.privacy_consent = true
                        self:saveSettings()
                        viewer:onClose()
                        UIManager:scheduleIn(0.1, function()
                            self:runAnalysis(query, boundary, book_id, passages)
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function CharacterBrain:runAnalysis(query, boundary, book_id, passages)
    if NetworkMgr:willRerunWhenOnline(function()
        self:runAnalysis(query, boundary, book_id, passages)
    end) then
        return
    end

    local progress = InfoMessage:new{
        text = T(_("Analyzing %1 spoiler-safe passages…"), #passages),
    }
    UIManager:show(progress)
    UIManager:scheduleIn(0.1, function()
        local raw_result, request_error = Backend.analyze(
            self.settings,
            query,
            passages
        )
        UIManager:close(progress)
        if not raw_result then
            logger.warn("Character Brain request failed:", request_error)
            UIManager:show(InfoMessage:new{
                text = T(_("Character analysis failed:\n%1"), request_error),
            })
            return
        end

        local accepted, validation_error = Validator.validate(raw_result, query, passages)
        if not accepted then
            UIManager:show(InfoMessage:new{
                text = T(_("Character analysis was rejected:\n%1"), validation_error),
            })
            return
        end

        local saved, save_error = DB.saveAnalysis(book_id, query, boundary, accepted, passages)
        if not saved then
            UIManager:show(InfoMessage:new{
                text = T(_("Could not save character analysis:\n%1"), save_error),
            })
            return
        end
        self:showProfile(query, boundary, accepted, passages)
    end)
end

function CharacterBrain:formatProfile(query, result)
    local lines = {
        result.canonical_name or query,
        "",
        _("Strict evidence mode"),
        _("All story text below is copied exactly from passages before your selection."),
    }

    if #result.aliases > 0 then
        table.insert(lines, "")
        table.insert(lines, _("Explicit aliases"))
        for _, alias in ipairs(result.aliases) do
            table.insert(lines, "• " .. alias.name)
            table.insert(lines, "  “" .. alias.quote .. "”")
        end
    end

    if #result.evidence > 0 then
        table.insert(lines, "")
        table.insert(lines, _("What the book has established"))
        for _, item in ipairs(result.evidence) do
            table.insert(lines, "• " .. (evidence_kind_titles[item.kind] or _("Evidence")))
            table.insert(lines, "  “" .. item.quote .. "”")
        end
    end

    if #result.connections > 0 then
        table.insert(lines, "")
        table.insert(lines, _("Known connections"))
        for _, connection in ipairs(result.connections) do
            table.insert(lines, "• " .. connection.name)
            table.insert(lines, "  “" .. connection.quote .. "”")
        end
    end

    if #result.aliases == 0 and #result.evidence == 0 and #result.connections == 0 then
        table.insert(lines, "")
        table.insert(lines, _("Nothing could be established from verified evidence yet."))
    end
    if result.rejected_count and result.rejected_count > 0 then
        table.insert(lines, "")
        table.insert(lines, T(_("%1 unsupported AI suggestions were hidden."), result.rejected_count))
    end
    return table.concat(lines, "\n")
end

function CharacterBrain:showProfile(query, boundary, result, passages)
    local viewer
    viewer = TextViewer:new{
        title = _("Character Brain"),
        text = self:formatProfile(query, result),
        text_type = "lookup",
        buttons_table = {
            {
                {
                    text = _("Evidence"),
                    callback = function()
                        viewer:onClose()
                        self:showEvidence(result, passages)
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        viewer:onClose()
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function CharacterBrain:showEvidence(result, passages)
    local passages_by_id = {}
    for _, passage in ipairs(passages) do
        passages_by_id[passage.id] = passage
    end

    local items = {}
    local function addItems(group, label)
        for _, item in ipairs(group or {}) do
            local passage = passages_by_id[item.passage_id]
            if passage then
                table.insert(items, {
                    text = item.name and (item.name .. ": " .. item.quote) or item.quote,
                    mandatory = label,
                    xpointer = passage.start_xpointer,
                })
            end
        end
    end
    addItems(result.aliases, _("Alias"))
    addItems(result.evidence, _("Evidence"))
    addItems(result.connections, _("Connection"))

    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = _("No accepted evidence.") })
        return
    end

    local menu
    menu = Menu:new{
        title = _("Character evidence"),
        item_table = items,
        covers_fullscreen = true,
        onMenuChoice = function(_, item)
            UIManager:close(menu)
            self.ui:handleEvent(Event:new("GotoXPointer", item.xpointer, item.xpointer))
        end,
    }
    UIManager:show(menu)
end

function CharacterBrain:showBackendSettings(message)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Character Brain backend"),
        fields = {
            {
                description = message or _("Backend URL"),
                text = self.settings.backend_url,
                hint = "https://character-brain.example.com",
            },
            {
                description = _("Backend access token (stored unencrypted in KOReader settings)"),
                text = self.settings.access_token,
                hint = "shared-secret",
                text_type = "password",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = dialog:getFields()
                        self.settings.backend_url = CBUtil.trim(fields[1])
                        self.settings.access_token = CBUtil.trim(fields[2])
                        self.settings.privacy_consent = false
                        self:saveSettings()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CharacterBrain:deleteCurrentBookData()
    local book_id = self:getBook()
    UIManager:show(ConfirmBox:new{
        text = _("Delete all Character Brain data for this book?"),
        ok_text = _("Delete"),
        ok_callback = function()
            DB.deleteBook(book_id)
            UIManager:show(InfoMessage:new{
                text = _("Character Brain data deleted."),
            })
        end,
    })
end

function CharacterBrain:addToMainMenu(menu_items)
    menu_items.character_brain = {
        text = _("Character Brain"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Backend settings"),
                callback = function()
                    self:showBackendSettings()
                end,
            },
            {
                text = _("Delete data for this book"),
                callback = function()
                    self:deleteCurrentBookData()
                end,
            },
            {
                text = _("About spoiler safety"),
                callback = function()
                    UIManager:show(TextViewer:new{
                        title = _("Character Brain spoiler safety"),
                        text = _([[
The AI receives only passages whose ending XPointer is at or before your selected word.

The AI response is treated as untrusted. Character Brain displays story text only when it is an exact quote found in one of those allowed passages. Unsupported generated prose is never displayed.

The prompt also forbids outside knowledge, but the XPointer filter and exact-quote validator are the actual enforcement mechanisms.]]),
                    })
                end,
            },
        },
    }
end

return CharacterBrain
