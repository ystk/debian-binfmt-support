/* kvhash.h - key/value hash
 *
 * Copyright (c) 2010 Colin Watson <cjwatson@debian.org>.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include <stdbool.h>

struct kvelem {
    char *key;
    void *value;
};

size_t kvhash_hasher (const void *data, size_t n);
bool kvhash_comparator (const void *a, const void *b);
Hash_table *kvhash_initialize (size_t candidate, const Hash_tuning *tuning,
			       Hash_data_freer data_freer);
bool kvhash_exists (const Hash_table *table, const char *key);
void *kvhash_lookup (const Hash_table *table, const char *key);
void *kvhash_insert (Hash_table *table, const char *key, const void *value);
void *kvhash_delete (Hash_table *table, const char *key);
