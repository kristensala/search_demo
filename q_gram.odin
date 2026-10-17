/*
   String matching with only q-gram/n-gram
   and no distance algorithm

   q = 3 => trigram
 */
package main

import "core:strings"
import "core:sort"
import "core:fmt"

Q_GRAM_EDIT_DISTANCE_THRESHOLD :: 2

q_gram_distance_search :: proc(input_lower: string, input_trigram: [dynamic]string) {
    state := get_state()

    tmp_count : map[i32]i32 // data_idx and its count
    defer delete(tmp_count)

    for tri_g in input_trigram {
        indices, found := state.trigram_index[tri_g]
        if !found do continue

        for i in indices {
            tmp_count[i] += 1
        }
    }

    tmp_results_map : map[string]i32
    defer delete(tmp_results_map)

    for entry_idx, count in tmp_count {
        entry := state.data[entry_idx]
        q_gram_distance := len(input_lower) + len(entry) - int(2*count)

        th := 2 * Q_GRAM_SIZE * Q_GRAM_EDIT_DISTANCE_THRESHOLD
        if q_gram_distance > th do continue

        entry_lower := strings.to_lower(string(entry), context.temp_allocator)
        if len(input_lower) > len(entry_lower) do continue

        _, exists := tmp_results_map[entry_lower]
        if exists {
            continue
        }
        fmt.println("===> dist: ", q_gram_distance)

        row := Row{
            name = entry,
            score = f64(q_gram_distance)
        }

        tmp_results_map[entry_lower] = entry_idx
        append(&state.search_results_v2, row)
    }

    sort.quick_sort_proc(state.search_results_v2[:], proc(a, b: Row) -> int {
        if a.score < b.score do return 1
        if a.score > b.score do return -1
        return 0
    })
}
