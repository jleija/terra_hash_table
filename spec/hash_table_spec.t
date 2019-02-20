local hash_table = require("hash_table")
local ffi = require("ffi")

describe("hash table for integral types", function()
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
end)


describe("hash table for null-terminated strings", function()
    local ht_type, ht_pair = hash_table(rawstring, rawstring)
    local my_table = global(ht_type)

    local terra instance()
        return &my_table
    end

    before_each(function()
        instance():init()
    end)

    it("puts and gets a string key and value", function()
        instance():put("hello", "there")
        assert.is.equal(1, instance():size())
        assert.is.truthy(instance():get("hello") ~= nil)
        assert.is.equal("there", ffi.string(instance():get("hello").value))
    end)
end)

describe("hash table for structs", function()
    local struct my_struct {
        x : int
        y : int
    }
    local ht_type, ht_pair = hash_table(my_struct, my_struct)
    local my_table = global(ht_type)

    local terra instance()
        return &my_table
    end

    before_each(function()
        instance():init()
    end)

    it("puts and gets a user struct", function()
        local key = global(my_struct)
        local value = global(my_struct)
        key.x = 5
        key.y = 3
        value.x = 8
        value.y = 7
        instance():put(key, value)
        assert.is.equal(1, instance():size())

        local key_2 = global(my_struct)
        key_2.x = 5
        key_2.y = 3
        assert.is.truthy(instance():get(key_2) ~= nil)
        assert.is.equal(8, instance():get(key_2).value.x)
        assert.is.equal(7, instance():get(key_2).value.y)
    end)
end)

describe("hash table for strings to structs", function()
    local struct my_struct {
        x : int
        y : int
    }
    local ht_type, ht_pair = hash_table(rawstring, my_struct)
    local my_table = global(ht_type)

    local terra instance()
        return &my_table
    end

    before_each(function()
        instance():init()
    end)

    it("puts and gets a user struct", function()
        local value = global(my_struct)
        value.x = 8
        value.y = 7
        instance():put("my_key", value)
        assert.is.equal(1, instance():size())

        assert.is.truthy(instance():get("my_key") ~= nil)
        assert.is.equal(8, instance():get("my_key").value.x)
        assert.is.equal(7, instance():get("my_key").value.y)
    end)
end)
