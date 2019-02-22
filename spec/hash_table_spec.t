local hash_table = require("hash_table")
local ffi = require("ffi")

describe("hash table 'class' and instance creation", function()
    it("has new and delete operators to get heap instances", function()
        local int_int_map = hash_table(int, int)
        local hash_instance = int_int_map.new()

        assert.is.truthy(hash_instance)
        assert.is.truthy(hash_instance:is_empty())
        int_int_map.delete(hash_instance)
    end)
    it("can be created as a stack (non-heap) variable", function()
        local int_int_map = hash_table(int, int)

        local my_table = global(int_int_map.hash_type)

        -- has to be manually init'ed
        my_table:get():init()
    end)
end)

describe("hash table for integral types", function()
    local int_int_map = hash_table(int, int)

    local instance

    before_each(function() instance = int_int_map.new() end)
    after_each(function() int_int_map.delete(instance) end)

    it("should create an empty table", function()
        assert.is.equal(0, instance:size())
        assert.is.truthy(instance:is_empty())
    end)

    it("puts and gets an int value", function()
        instance:put(4, 44)
        assert.is.equal(1, instance:size())
        assert.is.equal(44, instance:get(4).value)

        instance:put(2, 22)
        assert.is.equal(22, instance:get(2).value)
        assert.is.equal(2, instance:size())
    end)

    it("puts and removes a key-value pair", function()
        instance:put(4, 44)
        assert.is.equal(1, instance:size())
        assert.is.equal(44, instance:get(4).value)

        instance:del(4)
        assert.is.falsy(instance:get(4))
        assert.is.truthy(instance:is_empty())
    end)
end)


describe("hash table for null-terminated strings", function()
    local str_str_map = hash_table(rawstring, rawstring)
    local my_table = global(str_str_map.hash_type)

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
    local struct point {
        x : int
        y : int
    }
    local point_point_map = hash_table(point, point)
    local instance

    before_each(function() instance = point_point_map.new() end)
    after_each(function() point_point_map.delete(instance) end)

    it("puts and gets a user struct", function()
        local key = global(point)
        local value = global(point)
        key.x = 5
        key.y = 3
        value.x = 8
        value.y = 7
        instance:put(key, value)
        assert.is.equal(1, instance:size())

        local key_2 = global(point)
        key_2.x = 5
        key_2.y = 3
        assert.is.truthy(instance:get(key_2) ~= nil)
        assert.is.equal(8, instance:get(key_2).value.x)
        assert.is.equal(7, instance:get(key_2).value.y)
    end)
end)

describe("hash table for strings to structs", function()
    local struct point {
        x : int
        y : int
    }
    local str_point_map = hash_table(rawstring, point)

    local instance

    before_each(function() instance = str_point_map.new() end)
    after_each(function() str_point_map.delete(instance) end)

    it("puts and gets a user struct", function()
        local value = global(point)
        value.x = 8
        value.y = 7
        instance:put("my_key", value)
        assert.is.equal(1, instance:size())

        assert.is.truthy(instance:get("my_key") ~= nil)
        assert.is.equal(8, instance:get("my_key").value.x)
        assert.is.equal(7, instance:get("my_key").value.y)
    end)
end)
