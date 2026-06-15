local CharacterBrainUtil = {}

function CharacterBrainUtil.trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$")
end

function CharacterBrainUtil.normalizeWhitespace(value)
    return CharacterBrainUtil.trim(value):gsub("%s+", " ")
end

function CharacterBrainUtil.normalizeName(value)
    return CharacterBrainUtil.normalizeWhitespace(value):lower()
end

function CharacterBrainUtil.containsLiteral(haystack, needle)
    haystack = CharacterBrainUtil.normalizeWhitespace(haystack)
    needle = CharacterBrainUtil.normalizeWhitespace(needle)
    return needle ~= "" and haystack:find(needle, 1, true) ~= nil
end

function CharacterBrainUtil.uniqueStrings(values)
    local result = {}
    local seen = {}
    for _, value in ipairs(values or {}) do
        value = CharacterBrainUtil.normalizeWhitespace(value)
        local key = value:lower()
        if value ~= "" and not seen[key] then
            seen[key] = true
            table.insert(result, value)
        end
    end
    return result
end

function CharacterBrainUtil.sqlQuote(value)
    return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

return CharacterBrainUtil
