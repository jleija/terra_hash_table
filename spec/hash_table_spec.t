local hash_table = require("hash_table")
local ffi = require("ffi")

describe("hash table", function()
    local hash_table_type, pair = hash_table(int, int)

    assert.is.truthy(hash_table_type)
    assert.is.truthy(pair)

    local my_table = global(hash_table_type)

    local terra instance()
        return &my_table
    end

    before_each(function()
        instance():init()
    end)

    it("should create an empty table", function()
        assert.is.equal(0, instance():size())
        assert.is.truthy(instance():is_empty())
    end)

    it("puts and gets an int value", function()
        instance():put(4, 44)
        assert.is.equal(1, instance():size())
        assert.is.equal(44, instance():get(4).value)

        instance():put(2, 22)
        assert.is.equal(22, instance():get(2).value)
        assert.is.equal(2, instance():size())
    end)

    it("puts and removes a key-value pair", function()
        instance():put(4, 44)
        assert.is.equal(1, instance():size())
        assert.is.equal(44, instance():get(4).value)

        instance():del(4)
        assert.is.falsy(instance():get(4))
        assert.is.truthy(instance():is_empty())
    end)

    it("puts and gets a string key and value", function()
        --local mm = require("mm")
        --mm(rawstring)

        local ht_type, ht_pair = hash_table(rawstring, rawstring)
        local my_table = global(ht_type)

        local terra instance()
            return &my_table
        end

        instance():init()

        instance():put("hello", "there")
        assert.is.equal(1, instance():size())
        assert.is.truthy(instance():get("hello") ~= nil)
        assert.is.equal("there", ffi.string(instance():get("hello").value))
    end)

end)

