#!/bin/bash

mkdir -p bin

echo "tommyhashlin"
cc -I external_dependencies/tommyds/tommyds -I src -shared -o bin/tommyhashlin.so -Dtommy_inline=" " external_dependencies/tommyds/tommyds/tommyhashlin.c -Dtommy_inline=static external_dependencies/tommyds/tommyds/tommyhash.c 


#echo "Wrapper"

#cc -I external_dependencies/tommyds/tommyds -I src -shared -o bin/hash_table.so external_dependencies/tommyds/tommyds/tommyhashlin.c external_dependencies/tommyds/tommyds/tommyhash.c src/hash_table.c

#cc -I external_dependencies/tommyds/tommyds -I src -o bin/hash_table_test external_dependencies/tommyds/tommyds/tommyhashlin.c external_dependencies/tommyds/tommyds/tommyhash.c src/hash_table.c tests/hash_table_test.c

#bin/hash_table_test
