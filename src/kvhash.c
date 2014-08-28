/* kvhash.c - key/value hash
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

#ifdef HAVE_CONFIG_H
#  include "config.h"
#endif

#include <stdlib.h>
#include <stdbool.h>
#include <string.h>

#include "hash.h"
#include "xalloc.h"

#include "kvhash.h"

size_t kvhash_hasher (const void *data, size_t n)
{
    const struct kvelem *kvdata = data;
    return hash_string (kvdata->key, n);
}

bool kvhash_comparator (const void *a, const void *b)
{
    const struct kvelem *kva = a, *kvb = b;
    return !strcmp (kva->key, kvb->key);
}

Hash_table *kvhash_initialize (size_t candidate, const Hash_tuning *tuning,
			       Hash_data_freer data_freer)
{
    return hash_initialize (candidate, tuning,
			    kvhash_hasher, kvhash_comparator, data_freer);
}

bool kvhash_exists (const Hash_table *table, const char *key)
{
    struct kvelem entry;

    entry.key = (char *) key; /* short lifetime, so don't bother to copy */
    entry.value = NULL;

    return hash_lookup (table, &entry) != NULL;
}

void *kvhash_lookup (const Hash_table *table, const char *key)
{
    struct kvelem entry, *lookup;

    entry.key = (char *) key; /* short lifetime, so don't bother to copy */
    entry.value = NULL;

    lookup = hash_lookup (table, &entry);
    return lookup ? lookup->value : NULL;
}

void *kvhash_insert (Hash_table *table, const char *key, const void *value)
{
    struct kvelem *entry, *ret;

    entry = xmalloc (sizeof *entry);
    entry->key = xstrdup (key);
    /* Caller should have duplicated value if necessary. */
    entry->value = (void *) value;

    ret = hash_insert (table, entry);
    if (ret != entry) {
	free (entry->key);
	free (entry);
    }
    return ret ? ret->value : NULL;
}

extern void *kvhash_delete (Hash_table *table, const char *key)
{
    struct kvelem entry, *deleted;

    entry.key = (char *) key; /* short lifetime, so don't bother to copy */
    entry.value = NULL;

    deleted = hash_delete (table, &entry);
    if (deleted) {
	void *value = deleted->value;
	free (deleted->key);
	free (deleted);
	return value;
    } else
	return NULL;
}
