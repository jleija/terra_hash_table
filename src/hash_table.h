#include <stdint.h>
#include <tommyhashlin.h>

//typedef int (*comparison_function)(void*, void*);
typedef tommy_search_func comparison_function;
typedef tommy_hashlin hash_table;
typedef tommy_node hash_node;

void hash_table_init(hash_table* ht);
void hash_table_done(hash_table* ht);

uint64_t hash_table_hashing_fn(void* key, size_t size);

size_t hash_table_size(hash_table* ht);
size_t hash_table_memory_usage(hash_table* ht);

void hash_table_put(
    hash_table* ht, 
    hash_node* node, 
    void* obj, 
    uint64_t key_hash);

void* hash_table_get(
    hash_table* ht, 
    comparison_function compare, 
    void* key, 
    uint64_t key_hash);

hash_node* hash_table_bucket(
    hash_table* ht, 
    uint64_t key_hash);

void* hash_table_del(
    hash_table* ht, 
    comparison_function compare, 
    void* key, 
    uint64_t key_hash);

