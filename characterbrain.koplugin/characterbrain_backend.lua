local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")
local socket = require("socket")
local http = require("socket.http")
local socketutil = require("socketutil")

local Backend = {}

local function endpointUrl(backend_url)
    backend_url = tostring(backend_url or ""):gsub("/+$", "")
    if backend_url:match("/v1/analyze$") then
        return backend_url
    end
    return backend_url .. "/v1/analyze"
end

function Backend.buildPayload(query, passages)
    local payload = {
        version = 1,
        query = query,
        passages = {},
    }
    for _, passage in ipairs(passages) do
        table.insert(payload.passages, {
            id = passage.id,
            text = passage.text,
        })
    end
    return payload
end

function Backend.analyze(settings, query, passages)
    local body = Backend.buildPayload(query, passages)
    local encoded, encode_error = rapidjson.encode(body)
    if not encoded then
        return nil, "Could not encode backend request: " .. tostring(encode_error)
    end

    local sink = {}
    local headers = {
        ["Content-Length"] = #encoded,
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["User-Agent"] = socketutil.USER_AGENT,
    }
    if settings.access_token and settings.access_token ~= "" then
        headers["Authorization"] = "Bearer " .. settings.access_token
    end

    socketutil:set_timeout(
        settings.block_timeout or socketutil.LARGE_BLOCK_TIMEOUT,
        settings.total_timeout or socketutil.LARGE_TOTAL_TIMEOUT
    )
    local code, response_headers, status = socket.skip(1, http.request({
        url = endpointUrl(settings.backend_url),
        method = "POST",
        headers = headers,
        source = ltn12.source.string(encoded),
        sink = socketutil.table_sink(sink),
    }))
    socketutil:reset_timeout()

    local raw_response = table.concat(sink)
    local numeric_code = tonumber(code)
    if not numeric_code or numeric_code < 200 or numeric_code >= 300 then
        local message = "Backend returned " .. tostring(status or code)
        local error_envelope = rapidjson.decode(raw_response)
        if error_envelope and error_envelope.error then
            message = message .. ": " .. tostring(error_envelope.error)
        elseif raw_response ~= "" then
            message = message .. ": " .. raw_response:sub(1, 500)
        end
        return nil, message
    end

    local envelope, decode_error = rapidjson.decode(raw_response)
    if not envelope then
        return nil, "Could not decode backend response: " .. tostring(decode_error)
    end
    if type(envelope.analysis) ~= "table" then
        return nil, "Backend response did not contain an analysis object."
    end
    return envelope.analysis, nil, response_headers
end

return Backend
