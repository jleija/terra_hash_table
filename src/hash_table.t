local std = terralib.includec("stdlib.h")
local str = terralib.includec("string.h")
local c = terralib.includec("stdio.h")

local variants = {
    fixed = "fixed",
    linear = "linear",
    dynamic = "dynamic"
}

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
    error("unsuported type: " .. tostring(terra_type.name))
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

local function load_tommyds()
    local function script_path()
       local str = debug.getinfo(2, "S").source:sub(2)
       return str:match("(.*/)")
    end

    local hash_table_home = script_path():gsub("/src/$", "")
    local tommyds_path = hash_table_home .. "/external_dependencies/tommyds/tommyds"

    local function include_tommyds(include_file, class_name)
        local include_h = tommyds_path .. "/" .. include_file
        local namespace = terralib.includec(include_h, {'-D', 'tommy_inline=inline'})
        return {
            init = namespace[class_name .. "_init"],
            done = namespace[class_name .. "_done"],
            insert = namespace[class_name .. "_insert"],
            remove = namespace[class_name .. "_remove"],
            bucket = namespace[class_name .. "_bucket"],
            search = namespace[class_name .. "_search"],
            foreach = namespace[class_name .. "_foreach"],
            foreach_arg = namespace[class_name .. "_foreach_arg"],
            count = namespace[class_name .. "_count"],
            memory_usage = namespace[class_name .. "_memory_usage"],
            hash_table = namespace[class_name],

            hash_node = namespace.tommy_node,
            hashing_fn = namespace.tommy_hash_u64,
        }
    end

    local bindings = {
        linear = include_tommyds("tommyhashlin.h", "tommy_hashlin"),
        fixed = include_tommyds("tommyhashtbl.h", "tommy_hashtable"),
        dynamic = include_tommyds("tommyhashdyn.h", "tommy_hashdyn"),
    }

    local hash_table_so = hash_table_home .. "/bin/tommyds.so"
    local status, err = pcall(function() terralib.linklibrary(hash_table_so) end)

    if not status then
        error("Could not load tommyds library " .. hash_table_so .. ". Make sure to run ./build.sh. Expecting library in " .. hash_table_so .. ":\n" .. err)
    end

    return bindings
end

local tommyds_lib = load_tommyds()

return function(params)
    local key_type = params[1] or error("No key-type argument for hash")
    local value_type = params[2] -- optional: treat as set when not provided

    local variant = params.variant or variants.linear
    assert(variants[variant], "Invalid variant selection. Select either fixed or linear or dynamic")

    local bucket_max = params.bucket_max or 1024
    local tommyds = tommyds_lib[variant]

    local alloc_fn = params.alloc_fn or std.malloc
    local dealloc_fn = params.dealloc_fn or std.free

    local function get_copy_fn(terra_type)
        if terra_type.name == "rawstring" then
            return terra(target : &terra_type, value : &terra_type)
                -- TODO: actually should only allocate when the new value is bigger
                -- than the existing value, but to do that, we would need to
                -- keep the allocated size somewhere here, without interfering
                -- with a basic string usage/interface
                @target = [terra_type](alloc_fn(str.strlen(@value) + 1))
                str.strcpy(@target, @value)
            end
        end
        return terra(target : &terra_type, v : &terra_type)
            str.memcpy(target, v, sizeof(terra_type))
        end
    end

    local function get_delete_fn(terra_type)
        if terra_type.name == "rawstring" then
            return terra(value : terra_type)
            dealloc_fn(value)
            end
        end
        return terra(v : terra_type) end
    end

    local function get_key_hash_fn(terra_type)
        if terra_type.name == "rawstring" then
            return terra(key : terra_type)
                return tommyds.hashing_fn(
                                       0,
                                       key, 
                                       str.strlen(key))
            end
        end
        return terra(key : terra_type)
            -- TODO: get proper hash_fn for integral/float types
            return tommyds.hashing_fn(
                                   0,
                                   &key, 
                                   sizeof(terra_type))
        end
    end

    local element_type
    if value_type then
        element_type = struct {
            key : key_type
            value : value_type
        }
    else
        element_type = struct {
            key : key_type
        }
    end

    local struct hash_node {
    	element : element_type
        ht_node : tommyds.hash_node
    }
    
    local compare_fn = params.compare_fn or get_comparison_fn(key_type)
    local size_fn = params.size_fn or get_size_fn(key_type)
    local key_copy_fn = params.key_copy_fn or get_copy_fn(key_type)
    local key_delete_fn = params.key_delete_fn or get_delete_fn(key_type)

    local value_copy_fn
    local value_delete_code
    if value_type then
        value_copy_fn = params.value_copy_fn or get_copy_fn(value_type)
        local value_delete_fn = params.value_delete_fn or get_delete_fn(value_type)
        value_delete_code = function(node)
                                return quote value_delete_fn(node.element.value) end
                             end
    else
        value_delete_code = function() return quote end end
    end

    local key_hash_fn = params.key_hash_fn or get_key_hash_fn(key_type)

    local terra element(iter : &opaque) : &element_type
        return [&element_type]([&tommyds.hash_node](iter).data)
    end

    local struct hash_table {
        ht : tommyds.hash_table
    }

    if variant == variants.fixed then
        terra hash_table:init()
            tommyds.init(&self.ht, bucket_max)
        end
    else
        terra hash_table:init()
            tommyds.init(&self.ht)
        end
    end

    terra hash_table:done()
        tommyds.done(&self.ht)
    end

    terra hash_table:count()
        return tommyds.count(&self.ht)
    end

    terra hash_table:memory_usage()
        return tommyds.memory_usage(&self.ht)
    end

    terra hash_table:is_empty() : bool
        return self:count() == 0
    end

    if value_type then
        terra hash_table:insert(key : key_type, value : value_type)
            var node : &hash_node = [&hash_node](alloc_fn(sizeof(hash_node)))
            key_copy_fn(&node.element.key, &key)
            value_copy_fn(&node.element.value, &value)
            var key_hash = key_hash_fn(key)
            tommyds.insert( &self.ht, 
                                   &node.ht_node, 
                                   node, 
                                   key_hash)
        end
    else
        terra hash_table:insert(key : key_type)
            var node : &hash_node = [&hash_node](alloc_fn(sizeof(hash_node)))
            key_copy_fn(&node.element.key, &key)
            var key_hash = key_hash_fn(key)
            tommyds.insert( &self.ht, 
                                   &node.ht_node, 
                                   node, 
                                   key_hash)
        end
    end

    terra hash_table:search(key : key_type) : &element_type
        var key_hash = key_hash_fn(key)
        var node = [&hash_node](tommyds.search(
                                        &self.ht,
                                        compare_fn,
                                        &key,
                                        key_hash))
        if node == nil then
            return nil
        end
        return &node.element
    end

    terra hash_table:bucket(key : key_type) : &tommyds.hash_node
        var key_hash = key_hash_fn(key)
        var node = [&tommyds.hash_node](tommyds.bucket(
                                        &self.ht,
                                        key_hash))
        return node
    end

    local terra del_node(node : &hash_node)
        key_delete_fn(node.element.key)
        [ value_delete_code(node) ]
        dealloc_fn(node)
    end

    terra hash_table:remove(key : key_type)
        var key_hash = key_hash_fn(key)
        var node = [&hash_node](tommyds.remove(
                                        &self.ht,
                                        compare_fn,
                                        &key,
                                        key_hash))
        -- TODO: implement policy where the user owns the memory management
        -- should manual memory management be the default???
        if node ~= nil then
            del_node(node)
        end
    end

    terra hash_table:foreach(user_fn : {&opaque} -> {})
        tommyds.foreach(&self.ht, user_fn)
    end

    terra hash_table:foreach_arg(user_fn : {&opaque, &opaque} -> {}, arg : &opaque)
        tommyds.foreach_arg(&self.ht, user_fn, arg)
    end

    terra hash_table:remove_all()
        self:foreach([{&opaque}->{}](del_node))
    end

    local terra new() : &hash_table
        var instance = [&hash_table](alloc_fn(sizeof(hash_table)))
        instance:init()
        return instance
    end

    local terra delete(instance : &hash_table) 
        instance:done()
        dealloc_fn(instance)
    end

    return {
        hash_type = hash_table,
        element_type = element_type,
        key_type = key_type,
        value_type = value_type,
        iter_type = tommyds.hash_node,
        new = new,
        delete = delete,
        element = element,
        variants = variants
    }
end
