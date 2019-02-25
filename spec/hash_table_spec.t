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

describe("typical use cases", function()
    local std = terralib.includec("stdlib.h")

    local allocations_count = global(int, 0)
    local deallocations_count = global(int, 0)

    local terra alloc(n : int)
        allocations_count = allocations_count + 1
        return std.malloc(n)
    end

    local terra dealloc(p : &opaque)
        deallocations_count = deallocations_count + 1
        std.free(p)
    end

    local str_int_map = hash_table(rawstring, int, {
                                   alloc_fn = alloc,
                                   dealloc_fn = dealloc
                                 })
    local instance

    before_each(function() 
                    allocations_count:set(0)
                    deallocations_count:set(0)
                    instance = str_int_map.new() 
                end)
    after_each(function() 
                    str_int_map.delete(instance) 
                    assert.is.equal(allocations_count:get(),
                                    deallocations_count:get())
               end)

--    before_each(function() instance = str_int_map.new() end)
--    after_each(function() str_int_map.delete(instance) end)

    it("can put, get and del multiple times with the same key", function()
        instance:put("x", 1)
        instance:put("x", 2)
        assert.is.equal(1, instance:get("x").value)
        instance:del("x")
        assert.is.truthy(instance:get("x"))
        assert.is.equal(2, instance:get("x").value)
        instance:del("x")
        assert.is.falsy(instance:get("x"))
    end)

    it("can iterate through a bucket of repeated key hashes", function()
        instance:put("x", 1)
        instance:put("x", 2)
        instance:put("x", 3)
        instance:put("x", 4)
        local iter = instance:bucket("x")
        assert.is.truthy(iter)

        local v = 1
        while iter ~= nil do
            assert.is.equal("x", ffi.string(str_int_map.pair(iter).key))
            assert.is.equal(v, str_int_map.pair(iter).value)
            iter = iter.next
            v = v + 1
        end
        instance:del_all()
    end)
    it("should be able to iterate through all the elements in the hash-table", function()
        local str = terralib.includec("string.h")

        instance:put("a", 1)
        instance:put("a", 2)
        instance:put("a", 3)
        instance:put("b", 10)
        instance:put("b", 20)

        local a_sum = global(int, 0)
        local b_sum = global(int, 0)

        local terra sum_pairs( pair : &str_int_map.pair_type)
            if str.strcmp("a", pair.key) == 0 then
                a_sum = a_sum + pair.value
            else
                b_sum = b_sum + pair.value
            end
        end
        local fn_ptr = sum_pairs:compile()

        instance:for_each(fn_ptr)
        assert.is.equal(6, a_sum:get())
        assert.is.equal(30, b_sum:get())
        instance:del_all()
    end)

    it("should be able to iterate through all the elements in the hash-table, passing a user-given argument", function()
        local str = terralib.includec("string.h")

        instance:put("a", 1)
        instance:put("a", 2)
        instance:put("a", 3)
        instance:put("b", 10)
        instance:put("b", 20)

        local struct sums {
            a_sum : int
            b_sum : int
        }

        local my_state = global(sums)

        my_state:get().a_sum = 0
        my_state:get().b_sum = 0

        local terra sum_pairs_in_arg( sum_state : &sums, pair : &str_int_map.pair_type)
            if str.strcmp("a", pair.key) == 0 then
                sum_state.a_sum = sum_state.a_sum + pair.value
            else
                sum_state.b_sum = sum_state.b_sum + pair.value
            end
        end
        local fn_ptr = sum_pairs_in_arg:compile()

        instance:for_each_with_arg(fn_ptr, my_state:getpointer())
        assert.is.equal(6, my_state:get().a_sum)
        assert.is.equal(30, my_state:get().b_sum)
        instance:del_all()
    end)

    it("has same usage in terra and in lua", function()
        local terra put( key: str_int_map.key_type, value : str_int_map.value_type)
            instance:put(key, value)
        end

        local terra get( key: str_int_map.key_type)
            return instance:get(key).value
        end

        put("one", 1)
        assert.is.equal(1, get("one"))
        instance:del("one")
    end)

    it("should return the count of inserted elements", function()
        assert.is.equal(0, instance:size())
        instance:put("one", 1)
        assert.is.equal(1, instance:size())
        instance:put("two", 2)
        assert.is.equal(2, instance:size())
        instance:del("one")
        assert.is.equal(1, instance:size())
        instance:del("one")
        assert.is.equal(1, instance:size())
        instance:del("two")
        assert.is.equal(0, instance:size())
    end)
end)

describe("memory usage, custom allocator", function()
    local std = terralib.includec("stdlib.h")

    local allocations_count = global(int, 0)
    local deallocations_count = global(int, 0)

    local terra alloc(n : int)
        allocations_count = allocations_count + 1
        return std.malloc(n)
    end

    local terra dealloc(p : &opaque)
        deallocations_count = deallocations_count + 1
        std.free(p)
    end

    local str_str_map = hash_table(rawstring, rawstring, {
                                   alloc_fn = alloc,
                                   dealloc_fn = dealloc
                                 })

    local instance

    before_each(function() 
                    allocations_count:set(0)
                    deallocations_count:set(0)
                    instance = str_str_map.new() 
                end)
    after_each(function() 
                    str_str_map.delete(instance) 
                    assert.is.equal(allocations_count:get(),
                                    deallocations_count:get())
               end)

    it("should reclaim memory when items are removed", function()
        local original_bytes = instance:memory_usage()
        instance:put("one", "uno")
        assert.is.truthy(instance:memory_usage() > original_bytes)
        instance:del("one")
        assert.is.equal(original_bytes, instance:memory_usage())
    end)
    it("should dealloc as much as alloc, simple case", function()
        instance:put("a", "A")
        instance:del("a")
    end)
    it("should dealloc as much as alloc", function()
        instance:put("a", "A")
        instance:del("a")
        instance:put("a", "A")
        instance:put("a", "AA")
        instance:put("a", "AAA")
        instance:put("b", "B")
        instance:del("a")
        instance:put("b", "BB")
        instance:del("a")
        instance:del("b")
        instance:del("b")
        instance:del("a")
    end)
    it("should should not dealloc already deleted keys", function()
        instance:put("a", "A")
        instance:del("a")
        instance:del("a")
        instance:del("a")
    end)
end)


