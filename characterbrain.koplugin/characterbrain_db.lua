local DataStorage = require("datastorage")
local Device = require("device")
local SQ3 = require("lua-ljsqlite3/init")
local rapidjson = require("rapidjson")

local CBUtil = require("characterbrain_util")

local DB = {
    path = DataStorage:getSettingsDir() .. "/character_brain.sqlite3",
}

local SCHEMA_VERSION = 1
local SCHEMA = [[
CREATE TABLE IF NOT EXISTS books (
    id INTEGER PRIMARY KEY,
    fingerprint TEXT NOT NULL UNIQUE,
    path TEXT NOT NULL,
    title TEXT,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS analyses (
    id INTEGER PRIMARY KEY,
    book_id INTEGER NOT NULL,
    query_name TEXT NOT NULL,
    normalized_query TEXT NOT NULL,
    boundary_xpointer TEXT NOT NULL,
    result_json TEXT NOT NULL,
    passages_json TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    UNIQUE(book_id, normalized_query, boundary_xpointer),
    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS analyses_lookup
    ON analyses(book_id, normalized_query, created_at DESC);
]]

local function open()
    local connection = SQ3.open(DB.path)
    if Device:canUseWAL() then
        connection:exec("PRAGMA journal_mode=WAL;")
    else
        connection:exec("PRAGMA journal_mode=TRUNCATE;")
    end
    connection:exec("PRAGMA foreign_keys=ON;")
    return connection
end

function DB.init()
    local connection = open()
    connection:exec(SCHEMA)
    connection:exec("PRAGMA user_version=" .. tostring(SCHEMA_VERSION) .. ";")
    connection:close()
end

function DB.getOrCreateBook(fingerprint, path, title)
    local connection = open()
    local statement = connection:prepare("SELECT id FROM books WHERE fingerprint = ?;")
    local row = statement:reset():bind(fingerprint):step()
    local book_id = row and tonumber(row[1])
    statement:close()

    if not book_id then
        statement = connection:prepare(
            "INSERT INTO books(fingerprint, path, title, created_at) VALUES(?, ?, ?, ?);"
        )
        statement:reset():bind(fingerprint, path, title or "", os.time()):step()
        statement:close()
        book_id = tonumber(connection:rowexec("SELECT last_insert_rowid();"))
    end
    connection:close()
    return book_id
end

function DB.saveAnalysis(book_id, query, boundary, result, passages)
    local result_json, result_error = rapidjson.encode(result)
    local passages_json, passages_error = rapidjson.encode(passages)
    if not result_json or not passages_json then
        return nil, tostring(result_error or passages_error)
    end

    local connection = open()
    local statement = connection:prepare([[
        INSERT OR REPLACE INTO analyses(
            book_id, query_name, normalized_query, boundary_xpointer,
            result_json, passages_json, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?);
    ]])
    statement:reset():bind(
        book_id,
        query,
        CBUtil.normalizeName(query),
        boundary,
        result_json,
        passages_json,
        os.time()
    ):step()
    statement:close()
    connection:close()
    return true
end

function DB.getAnalysis(book_id, query, boundary)
    local connection = open()
    local statement = connection:prepare([[
        SELECT result_json, passages_json
        FROM analyses
        WHERE book_id = ? AND normalized_query = ? AND boundary_xpointer = ?
        LIMIT 1;
    ]])
    local row = statement:reset():bind(
        book_id,
        CBUtil.normalizeName(query),
        boundary
    ):step()
    statement:close()
    connection:close()
    if not row then
        return nil
    end

    local result = rapidjson.decode(row[1])
    local passages = rapidjson.decode(row[2])
    if not result or not passages then
        return nil
    end
    return result, passages
end

function DB.getKnownAliases(book_id, query)
    local connection = open()
    local rows = connection:exec(
        "SELECT result_json FROM analyses WHERE book_id = "
        .. tostring(tonumber(book_id))
        .. " AND normalized_query = "
        .. CBUtil.sqlQuote(CBUtil.normalizeName(query))
        .. " ORDER BY created_at DESC LIMIT 5;"
    )
    connection:close()

    local aliases = {}
    for _, encoded in ipairs(rows and rows.result_json or {}) do
        local result = rapidjson.decode(encoded)
        for _, alias in ipairs(result and result.aliases or {}) do
            table.insert(aliases, alias.name)
        end
    end
    return CBUtil.uniqueStrings(aliases)
end

function DB.deleteBook(book_id)
    local connection = open()
    local statement = connection:prepare("DELETE FROM books WHERE id = ?;")
    statement:reset():bind(book_id):step()
    statement:close()
    connection:close()
end

return DB
