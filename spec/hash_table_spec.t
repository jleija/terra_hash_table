local hash_table = require("hash_table")
local ffi = require("ffi")

describe("hash table 'class' and instance creation", function()
    it("has new and delete operators to get heap instances", function()
        local int_int_map = hash_table(int, int)
        local hash_instance = int_int_map.new()

        assert.is.truthy(hash_instance)
        assert.is.truthy(hash_instance:is_empty())
        -- if you new an instance, remenber to delete it too
        int_int_map.delete(hash_instance)
    end)
    it("can be created as a stack (non-heap) variable", function()
        local int_int_map = hash_table(int, int)

        local my_table = global(int_int_map.hash_type)

        -- has to be manually init'ed and done
        my_table:get():init()
        my_table:get():done()
    end)
end)

describe("hash table for integral types", function()
    local int_int_map = hash_table(int, int)

    local instance

    before_each(function() instance = int_int_map.new() end)
    after_each(function() int_int_map.delete(instance) end)

    it("should create an empty table", function()
        assert.is.equal(0, instance:count())
        assert.is.truthy(instance:is_empty())
    end)

    it("inserts and searches an int value", function()
        instance:insert(4, 44)
        assert.is.equal(1, instance:count())
        assert.is.equal(44, instance:search(4).value)

        instance:insert(2, 22)
        assert.is.equal(22, instance:search(2).value)
        assert.is.equal(2, instance:count())
    end)

    it("inserts and removes a key-value pair", function()
        instance:insert(4, 44)
        assert.is.equal(1, instance:count())
        assert.is.equal(44, instance:search(4).value)

        instance:remove(4)
        assert.is.falsy(instance:search(4))
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

    it("inserts and searches a string key and value", function()
        instance():insert("hello", "there")
        assert.is.equal(1, instance():count())
        assert.is.truthy(instance():search("hello") ~= nil)
        assert.is.equal("there", ffi.string(instance():search("hello").value))
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

    it("inserts and searches a user struct", function()
        local key = global(point)
        local value = global(point)
        key.x = 5
        key.y = 3
        value.x = 8
        value.y = 7
        instance:insert(key, value)
        assert.is.equal(1, instance:count())

        local key_2 = global(point)
        key_2.x = 5
        key_2.y = 3
        assert.is.truthy(instance:search(key_2) ~= nil)
        assert.is.equal(8, instance:search(key_2).value.x)
        assert.is.equal(7, instance:search(key_2).value.y)
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

    it("inserts and searches a user struct", function()
        local value = global(point)
        value.x = 8
        value.y = 7
        instance:insert("my_key", value)
        assert.is.equal(1, instance:count())

        assert.is.truthy(instance:search("my_key") ~= nil)
        assert.is.equal(8, instance:search("my_key").value.x)
        assert.is.equal(7, instance:search("my_key").value.y)
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

    it("can insert, search and remove multiple times with the same key", function()
        instance:insert("x", 1)
        instance:insert("x", 2)
        assert.is.equal(1, instance:search("x").value)
        instance:remove("x")
        assert.is.truthy(instance:search("x"))
        assert.is.equal(2, instance:search("x").value)
        instance:remove("x")
        assert.is.falsy(instance:search("x"))
    end)

    it("can iterate through a bucket of repeated key hashes", function()
        instance:insert("x", 1)
        instance:insert("x", 2)
        instance:insert("x", 3)
        instance:insert("x", 4)
        local iter = instance:bucket("x")
        assert.is.truthy(iter)

        local v = 1
        while iter ~= nil do
            assert.is.equal("x", ffi.string(str_int_map.pair(iter).key))
            assert.is.equal(v, str_int_map.pair(iter).value)
            iter = iter.next
            v = v + 1
        end
        instance:remove_all()
    end)
    it("should be able to iterate through all the elements in the hash-table", function()
        local str = terralib.includec("string.h")

        instance:insert("a", 1)
        instance:insert("a", 2)
        instance:insert("a", 3)
        instance:insert("b", 10)
        instance:insert("b", 20)

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

        instance:foreach(fn_ptr)
        assert.is.equal(6, a_sum:get())
        assert.is.equal(30, b_sum:get())
        instance:remove_all()
    end)

    it("should be able to iterate through all the elements in the hash-table, passing a user-given argument", function()
        local str = terralib.includec("string.h")

        instance:insert("a", 1)
        instance:insert("a", 2)
        instance:insert("a", 3)
        instance:insert("b", 10)
        instance:insert("b", 20)

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

        instance:foreach_arg(fn_ptr, my_state:getpointer())
        assert.is.equal(6, my_state:get().a_sum)
        assert.is.equal(30, my_state:get().b_sum)
        instance:remove_all()
    end)

    it("has same usage in terra and in lua", function()
        local terra insert( key: str_int_map.key_type, value : str_int_map.value_type)
            instance:insert(key, value)
        end

        local terra search( key: str_int_map.key_type)
            return instance:search(key).value
        end

        insert("one", 1)
        assert.is.equal(1, search("one"))
        instance:remove("one")
    end)

    it("should return the count of inserted elements", function()
        assert.is.equal(0, instance:count())
        instance:insert("one", 1)
        assert.is.equal(1, instance:count())
        instance:insert("two", 2)
        assert.is.equal(2, instance:count())
        instance:remove("one")
        assert.is.equal(1, instance:count())
        instance:remove("one")
        assert.is.equal(1, instance:count())
        instance:remove("two")
        assert.is.equal(0, instance:count())
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
        instance:insert("one", "uno")
        assert.is.truthy(instance:memory_usage() > original_bytes)
        instance:remove("one")
        assert.is.equal(original_bytes, instance:memory_usage())
    end)
    it("should dealloc as much as alloc, simple case", function()
        instance:insert("a", "A")
        instance:remove("a")
    end)
    it("should dealloc as much as alloc", function()
        instance:insert("a", "A")
        instance:remove("a")
        instance:insert("a", "A")
        instance:insert("a", "AA")
        instance:insert("a", "AAA")
        instance:insert("b", "B")
        instance:remove("a")
        instance:insert("b", "BB")
        instance:remove("a")
        instance:remove("b")
        instance:remove("b")
        instance:remove("a")
    end)
    it("should should not dealloc already removed keys", function()
        instance:insert("a", "A")
        instance:remove("a")
        instance:remove("a")
        instance:remove("a")
    end)
end)


