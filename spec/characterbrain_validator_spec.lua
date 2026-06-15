describe("Character Brain validator", function()
    local Validator

    setup(function()
        package.path = "characterbrain.koplugin/?.lua;" .. package.path
        Validator = require("characterbrain_validator")
    end)

    it("accepts exact quotes from allowed passages", function()
        local result = Validator.validate({
            canonical_name = "Strider",
            aliases = {},
            evidence = {
                {
                    kind = "description",
                    passage_id = "p1",
                    quote = "a strange-looking weather-beaten man",
                },
            },
            connections = {},
        }, "Strider", {
            {
                id = "p1",
                text = "In the corner sat a strange-looking weather-beaten man named Strider.",
            },
        })

        assert.are.equal(1, #result.evidence)
        assert.are.equal(0, result.rejected_count)
    end)

    it("rejects generated story prose even with a valid passage id", function()
        local result = Validator.validate({
            canonical_name = "Strider",
            aliases = {},
            evidence = {
                {
                    kind = "status",
                    passage_id = "p1",
                    quote = "Strider is secretly the king",
                },
            },
            connections = {},
        }, "Strider", {
            { id = "p1", text = "Strider watched the door." },
        })

        assert.are.equal(0, #result.evidence)
        assert.are.equal(1, result.rejected_count)
    end)

    it("requires explicit alias evidence containing both names", function()
        local result = Validator.validate({
            canonical_name = "Strider",
            aliases = {
                {
                    name = "Aragorn",
                    passage_id = "p1",
                    quote = "Aragorn was elsewhere.",
                },
                {
                    name = "Longshanks",
                    passage_id = "p2",
                    quote = "Strider, also called Longshanks, stood up.",
                },
            },
            evidence = {},
            connections = {},
        }, "Strider", {
            { id = "p1", text = "Aragorn was elsewhere." },
            { id = "p2", text = "Strider, also called Longshanks, stood up." },
        })

        assert.are.equal(1, #result.aliases)
        assert.are.equal("Longshanks", result.aliases[1].name)
    end)

    it("requires a connection name in its exact quote", function()
        local result = Validator.validate({
            canonical_name = "Strider",
            aliases = {},
            evidence = {},
            connections = {
                {
                    name = "Frodo",
                    passage_id = "p1",
                    quote = "Strider watched the door.",
                },
            },
        }, "Strider", {
            { id = "p1", text = "Strider watched the door." },
        })

        assert.are.equal(0, #result.connections)
        assert.are.equal(1, result.rejected_count)
    end)

    it("requires the selected character in a connection quote", function()
        local result = Validator.validate({
            canonical_name = "Strider",
            aliases = {},
            evidence = {},
            connections = {
                {
                    name = "Frodo",
                    passage_id = "p1",
                    quote = "Frodo spoke quietly to Sam.",
                },
            },
        }, "Strider", {
            { id = "p1", text = "Frodo spoke quietly to Sam." },
        })

        assert.are.equal(0, #result.connections)
        assert.are.equal(1, result.rejected_count)
    end)
end)
