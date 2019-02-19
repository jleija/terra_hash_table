#include <assert.h>
#include "hash_table.h"

typedef struct {
  int key;
  int value;
  hash_node node;
} object;

int int_compare(const void* arg, const void* key)
{
  return *(int*)arg ^ *(int*)key;
}

void test_hash_fn()
{
  // test that it can be called
  int k = 0;
  hash_table_hashing_fn(&k, sizeof(k));
}

void test_put_and_get()
{
  hash_table ht;

  hash_table_init(&ht);

  object obj;
  obj.key = 3;
  obj.value = 33;

  hash_table_put(&ht, &obj.node, &obj, 3);

  assert(1 == hash_table_size(&ht));

  int key = 3;
  
  object* found_object = (object*)hash_table_get(&ht, int_compare, &key, 3);

  assert(33 == found_object->value);
}

void test_put_and_del()
{
  hash_table ht;

  hash_table_init(&ht);

  object obj;
  obj.key = 3;
  obj.value = 33;

  hash_table_put(&ht, &obj.node, &obj, 3);

  assert(1 == hash_table_size(&ht));

  int key = 3;
  
  object* found_object = (object*)hash_table_del(&ht, int_compare, &key, 3);

  assert(33 == found_object->value);

  found_object = (object*)hash_table_get(&ht, int_compare, &key, 3);
  assert(found_object == NULL);
}

void main()
{
  test_put_and_get();
  test_put_and_del();
  test_hash_fn();
}
