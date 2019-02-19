--local mm = require("mm")
--mm(rawstring)

local std = terralib.includec("stdlib.h")
local str = terralib.includec("string.h")
local c = terralib.includec("stdio.h")

terralib.includepath = terralib.includepath 
                       .. ";external_dependencies/tommyds/tommyds"

local ht_lib = terralib.includec("src/hash_table.h")
terralib.linklibrary("bin/hash_table.so")

local function get_comparison_fn(terra_type)
    if terra_type.name == "rawstring" then
        return terra( a : &opaque, b : &opaque) : int
            return str.strcmp(@[&&int8](a), @[&&int8](b))
        end
    end
    if terra_type:isstruct() then
        return terra(arg : &opaque, key : &opaque) : int
           return str.strncmp(arg, key, sizeof(terra_type))
        end
    end
    if terra_type:isarray() then
        if terra_type.type.name == "uint8" then
            return terra(arg : &opaque, key : &opaque) : int
               return str.strncmp(arg, key, terra_type.N)
            end
        else
            error("Array type not supported: " .. terra_type.type.name 
                    .. "[" .. terra_type.N .. "]")
        end
    end
    if terra_type:isintegral() or terra_type:isfloat() then
        return terra(arg : &opaque, key : &opaque) : int
            return (@[&terra_type](arg)) ^ (@[&terra_type](key))
        end
    else
        error("unsuported terra type: " .. tostring(terra_type.name))
    end
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
        return terra(value : terra_type)
            var copy : terra_type = [terra_type](std.malloc(str.strlen(value) + 1))
            str.strcpy(copy, value)
            return copy
        end
    end
    return terra(v : terra_type)
        return v
    end
end

local function get_assignment_fn(terra_type)
    if terra_type.name == "rawstring" then
        return terra(a : &terra_type, b : terra_type)
            @a = [terra_type](std.malloc(str.strlen(b) + 1))
            str.strcpy(@a, b)
        end
    end
    return terra(a : &terra_type, b : terra_type)
       @a = b
    end
end

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

return function(key_type, value_type)
    local struct pair {
        key : key_type
        value : value_type
        padding : uint8[100]
        node : ht_lib.hash_node
    }
    
    local struct hash_table {
        ht : ht_lib.hash_table
    }

    local compare_fn = get_comparison_fn(key_type)
    local size_fn = get_size_fn(key_type)
    --local key_assignment_fn = get_assignment_fn(key_type)
    local key_copy_fn = get_copy_fn(key_type)
    --local value_assignment_fn = get_assignment_fn(value_type)
    local value_copy_fn = get_copy_fn(value_type)
    local key_hash_fn = get_key_hash_fn(key_type)

    terra hash_table:init()
        ht_lib.hash_table_init(&self.ht)
    end

    terra hash_table:size()
        return ht_lib.hash_table_size(&self.ht)
    end

    terra hash_table:is_empty() : bool
        return self:size() == 0
    end

    terra hash_table:put(key : key_type, value : value_type)
        var key_value_obj : &pair = [&pair](std.malloc(sizeof(pair)))
        --c.printf("assigning1\n")
        key_value_obj.key = key_copy_fn(key)
        --key_assignment_fn(&key_value_obj.key, key)
        --c.printf("assigned '%s'\n", key_value_obj.key)
        --c.printf("assigning2\n")
        --value_assignment_fn(&key_value_obj.value, value)
        key_value_obj.value = value_copy_fn(value)
        --c.printf("assigned '%s'\n", key_value_obj.value)
        --c.printf("hashing\n")
        var key_hash = key_hash_fn(key)
        --c.printf("puttin' on hash 0x%lx\n", key_hash)
        ht_lib.hash_table_put( &self.ht, 
                               &key_value_obj.node, 
                               key_value_obj, 
                               key_hash)
        --c.printf("done puttin'\n")
    end

    terra hash_table:get(key : key_type) : &pair
        var key_hash = key_hash_fn(key)
        --c.printf("gettin' with hash 0x%lx\n", key_hash)
        var key_value_obj = [&pair](ht_lib.hash_table_get(
                                        &self.ht,
                                        compare_fn,
                                        &key,
                                        key_hash))
        return key_value_obj
    end

    terra hash_table:del(key : key_type) : &pair
        var key_hash = key_hash_fn(key)
        var key_value_obj = [&pair](ht_lib.hash_table_del(
                                        &self.ht,
                                        compare_fn,
                                        &key,
                                        key_hash))
        return key_value_obj
    end

    return hash_table, pair
end
