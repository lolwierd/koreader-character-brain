local util = require("util")
local CBUtil = require("characterbrain_util")

local Extractor = {}

local function moveBackward(document, xpointer, words)
    local current = xpointer
    for _ = 1, words do
        local previous = document:getPrevVisibleWordStart(current)
        if not previous then
            break
        end
        current = previous
    end
    return current
end

local function moveForward(document, xpointer, boundary, words)
    local current = xpointer
    for _ = 1, words do
        local following = document:getNextVisibleWordEnd(current)
        if not following then
            break
        end
        local order = document:compareXPointers(following, boundary)
        if order == nil or order == -1 then
            break
        end
        current = following
    end
    return current
end

local function isAtOrBefore(document, xpointer, boundary)
    local order = document:compareXPointers(xpointer, boundary)
    return order == 0 or order == 1
end

function Extractor.isSupported(document)
    local suffix = util.getFileNameSuffix(document.file):lower()
    return suffix == "epub" or suffix == "kepub"
end

function Extractor.collect(document, names, boundary, options)
    options = options or {}
    local context_before = options.context_before or 55
    local context_after = options.context_after or 75
    local max_hits_per_name = options.max_hits_per_name or 40
    local max_passages = options.max_passages or 60
    local max_total_characters = options.max_total_characters or 55000
    local passages = {}
    local seen = {}
    local total_characters = 0

    for _, name in ipairs(CBUtil.uniqueStrings(names)) do
        local hits = document:findAllText(name, true, 0, max_hits_per_name, false) or {}
        for _, hit in ipairs(hits) do
            if hit.start and hit["end"] and isAtOrBefore(document, hit["end"], boundary) then
                local start_xp = moveBackward(document, hit.start, context_before)
                local end_xp = moveForward(document, hit["end"], boundary, context_after)
                local normalized_start = document:getNormalizedXPointer(start_xp) or start_xp
                local normalized_end = document:getNormalizedXPointer(end_xp) or end_xp
                local key = normalized_start .. "\0" .. normalized_end
                if not seen[key] then
                    local text = document:getTextFromXPointers(start_xp, end_xp)
                    text = CBUtil.normalizeWhitespace(text)
                    if text ~= "" and total_characters + #text <= max_total_characters then
                        seen[key] = true
                        total_characters = total_characters + #text
                        table.insert(passages, {
                            id = "p" .. tostring(#passages + 1),
                            start_xpointer = normalized_start,
                            end_xpointer = normalized_end,
                            text = text,
                            matched_name = name,
                        })
                    end
                end
                if #passages >= max_passages then
                    return passages
                end
            end
        end
    end

    table.sort(passages, function(a, b)
        return document:compareXPointers(a.start_xpointer, b.start_xpointer) == 1
    end)
    for index, passage in ipairs(passages) do
        passage.id = "p" .. tostring(index)
    end
    return passages
end

return Extractor
