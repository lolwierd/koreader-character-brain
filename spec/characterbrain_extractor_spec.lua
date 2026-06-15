describe("Character Brain extractor", function()
    local Extractor

    setup(function()
        package.path = "characterbrain.koplugin/?.lua;" .. package.path
        package.loaded.util = {
            getFileNameSuffix = function()
                return "epub"
            end,
        }
        Extractor = require("characterbrain_extractor")
    end)

    it("drops hits after the selected XPointer", function()
        local positions = {
            before_start = 10,
            before_end = 12,
            boundary = 20,
            future_start = 30,
            future_end = 32,
        }
        local document = {
            file = "book.epub",
            findAllText = function()
                return {
                    { start = "before_start", ["end"] = "before_end" },
                    { start = "future_start", ["end"] = "future_end" },
                }
            end,
            compareXPointers = function(_, first, second)
                if positions[second] > positions[first] then
                    return 1
                elseif positions[second] < positions[first] then
                    return -1
                end
                return 0
            end,
            getPrevVisibleWordStart = function()
                return nil
            end,
            getNextVisibleWordEnd = function()
                return nil
            end,
            getNormalizedXPointer = function(_, value)
                return value
            end,
            getTextFromXPointers = function(_, first)
                if first == "before_start" then
                    return "Strider watched the door."
                end
                return "Future revelation."
            end,
        }

        local passages = Extractor.collect(document, { "Strider" }, "boundary")
        assert.are.equal(1, #passages)
        assert.are.equal("Strider watched the door.", passages[1].text)
    end)
end)
