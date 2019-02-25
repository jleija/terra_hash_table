#include "hash_table.h"
#include <tommyhashlin.h>
#include <tommyhash.h>

uint64_t hash_table_hashing_fn(void* key, size_t size)
{
  return tommy_hash_u64(0, key, size);
}

void hash_table_init(hash_table* ht)
{
  tommy_hashlin_init(ht);
}

void hash_table_done(hash_table* ht)
{
  tommy_hashlin_done(ht);
}

size_t hash_table_size(hash_table* ht)
{
  return tommy_hashlin_count(ht);
}

size_t hash_table_memory_usage(hash_table* ht)
{
  return tommy_hashlin_memory_usage(ht);
}

void hash_table_put( hash_table* ht, hash_node* node, void* obj, uint64_t key_hash)
{
	tommy_hashlin_insert(ht, node, obj, key_hash);
}

void* hash_table_get( hash_table* ht, comparison_function compare, void* key, uint64_t key_hash)
{
  return tommy_hashlin_search(ht, compare, key, key_hash);
}

hash_node* hash_table_bucket( hash_table* ht, uint64_t key_hash)
{
  return tommy_hashlin_bucket(ht, key_hash);
}

void* hash_table_del( hash_table* ht, comparison_function compare, void* key, uint64_t key_hash)
{
  return tommy_hashlin_remove(ht, compare, key, key_hash);
}

void hash_table_for_each( hash_table* ht, for_each_function fn)
{
  tommy_hashlin_foreach(ht, fn);
}

void hash_table_for_each_with_arg( hash_table* ht, for_each_arg_function fn, void* arg)
{
  tommy_hashlin_foreach_arg(ht, fn, arg);
}
