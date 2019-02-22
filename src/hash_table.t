local std = terralib.includec("stdlib.h")
local str = terralib.includec("string.h")
local c = terralib.includec("stdio.h")

local function get_comparison_fn(terra_type)
    if terra_type.name == "rawstring" then
        return terra( a : &opaque, b : &opaque) : int
            return str.strcmp(@[&&int8](a), @[&&int8](b))
        end
    end
    if terra_type:isstruct() then
        return terra(arg : &opaque, key : &opaque) : int
           return str.memcmp(arg, key, sizeof(terra_type))
        end
    end
    if terra_type:isintegral() or terra_type:isfloat() then
        return terra(arg : &opaque, key : &opaque) : int
            return (@[&terra_type](arg)) ^ (@[&terra_type](key))
        end
    end
    error("unsuported terra type: " .. tostring(terra_type.name))
end

local function get_size_fn(terra_type)
    if terra_type.name == "rawstring" then
        return terra(key : &terra_type)
            return str.strlen(@key) + 1
        end
    end
    return terra(key : &terra_type) : int
       return sizeof(terra_type)
    end
end

local function get_copy_fn(terra_type)
    if terra_type.name == "rawstring" then
        return terra(value : &terra_type)
            var copy : terra_type = [terra_type](std.malloc(str.strlen(@value) + 1))
            str.strcpy(copy, @value)
            return copy
        end
    end
    return terra(v : &terra_type)
        return @v
    end
end

local function get_delete_fn(terra_type)
    if terra_type.name == "rawstring" then
        return terra(value : terra_type)
	    std.free(value)
        end
    end
    return terra(v : terra_type) end
end

return function(key_type, value_type)
    terralib.includepath = terralib.includepath 
                           .. ";external_dependencies/tommyds/tommyds"

    local ht_lib = terralib.includec("src/hash_table.h")
    terralib.linklibrary("bin/hash_table.so")

    local function get_key_hash_fn(terra_type)
        if terra_type.name == "rawstring" then
            return terra(key : terra_type)
                return ht_lib.hash_table_hashing_fn(
                                       key, 
                                       str.strlen(key))
            end
        end
        return terra(key : terra_type)
            -- TODO: get proper hash_fn for integral/float types
            return ht_lib.hash_table_hashing_fn(
                                   &key, 
                                   sizeof(terra_type))
        end
    end

    local struct pair_type {
        key : key_type
        value : value_type
    }

    local struct hash_node {
    	pair : pair_type
        ht_node : ht_lib.hash_node
    }
    
    local struct hash_table {
        ht : ht_lib.hash_table
    }

    local compare_fn = get_comparison_fn(key_type)
    local size_fn = get_size_fn(key_type)
    local key_copy_fn = get_copy_fn(key_type)
    local key_delete_fn = get_delete_fn(key_type)
    local value_copy_fn = get_copy_fn(value_type)
    local value_delete_fn = get_delete_fn(value_type)
    local key_hash_fn = get_key_hash_fn(key_type)

    terra hash_table:init()
        ht_lib.hash_table_init(&self.ht)
    end

    terra hash_table:size()
        return ht_lib.hash_table_size(&self.ht)
    end

    terra hash_table:memory_usage()
        return ht_lib.hash_table_memory_usage(&self.ht)
    end

    terra hash_table:is_empty() : bool
        return self:size() == 0
    end

    terra hash_table:put(key : key_type, value : value_type)
        var node : &hash_node = [&hash_node](std.malloc(sizeof(hash_node)))
        node.pair.key = key_copy_fn(&key)
        node.pair.value = value_copy_fn(&value)
        var key_hash = key_hash_fn(key)
        ht_lib.hash_table_put( &self.ht, 
                               &node.ht_node, 
                               node, 
                               key_hash)
    end

    terra hash_table:get(key : key_type) : &pair_type
        var key_hash = key_hash_fn(key)
        var node = [&hash_node](ht_lib.hash_table_get(
                                        &self.ht,
                                        compare_fn,
                                        &key,
                                        key_hash))
        if node == nil then
            return nil
        end
        return &node.pair
    end

    terra hash_table:bucket(key : key_type) : &ht_lib.hash_node
        var key_hash = key_hash_fn(key)
        var node = [&ht_lib.hash_node](ht_lib.hash_table_bucket(
                                        &self.ht,
                                        key_hash))
        return node
    end

    terra hash_table:del(key : key_type)
        var key_hash = key_hash_fn(key)
        var node = [&hash_node](ht_lib.hash_table_del(
                                        &self.ht,
                                        compare_fn,
                                        &key,
                                        key_hash))
        -- TODO: implement policy where the user owns the memory management
        -- should manual memory management be the default???
        if node ~= nil then
            key_delete_fn(node.pair.key)
            value_delete_fn(node.pair.value)
            std.free(node)
        end
    end

    local terra new() : &hash_table
        var instance = [&hash_table](std.malloc(sizeof(hash_table)))
        instance:init()
        return instance
    end

    local terra delete(instance : &hash_table) 
        ht_lib.hash_table_done(&instance.ht)
        std.free(instance)
    end

    local terra pair(node : &ht_lib.hash_node)
        return [&pair_type](node.data)
    end

    return {
        hash_type = hash_table,
        pair_type = pair_type,
        key_type = key_type,
        value_type = value_type,
        new = new,
        delete = delete,
        pair = pair
    }
end
