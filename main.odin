package main

import "core:fmt"
import "core:time"
import "core:os"
import "core:sort"
import "core:strings"
import rl "vendor:raylib"

Rect :: rl.Rectangle
Q_GRAM_SIZE :: 3
EDIT_DISTANCE_THRESHOLD :: 5

Type :: enum {
    Damerau_Levenshtein_With_Trigram_And_Trigram_Filter,
    Damerau_Levenshtein_With_Trigram,
    Damerau_Levenshtein_No_Trigram,
    Linear,
}

App_State :: struct {
    frame_count: int,
    data: [dynamic]cstring,
    trigram_index: map[string][dynamic]i32,

    search_term: [dynamic]rune,
    search_results_v2: [dynamic]Row,

    last_input_at: int, // frame count
    do_search: bool,

    search_type: Type

}

Row :: struct {
    name: cstring,
    score: f64
}

Gui :: struct {
    input_rect: Rect,
    search_result_rect: Rect
}

BACKGROUND_COLOR   :: rl.DARKGRAY
TEXT_COLOR         :: rl.BLACK
FONT_SIZE          :: 20

@(private = "file") g_app_state : App_State
@(private = "file") g_gui       : Gui

get_state :: #force_inline proc() -> ^App_State { return &g_app_state }
get_gui :: #force_inline proc() -> ^Gui { return &g_gui }

main :: proc() {
    gui := init_gui()
    state := get_state()
    state.search_type = .Damerau_Levenshtein_With_Trigram_And_Trigram_Filter

    build_dataset()

    rl.SetConfigFlags({.WINDOW_RESIZABLE})
    rl.InitWindow(1800, 1250, "search_demo")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)
    rl.SetExitKey(.KEY_NULL)

    for !rl.WindowShouldClose() {
        update()

        rl.BeginDrawing()
        rl.ClearBackground(BACKGROUND_COLOR)

        // #draw
        {
            if state.search_type == .Damerau_Levenshtein_With_Trigram_And_Trigram_Filter {
                rl.DrawText("Damerau Levenshtein with trigram (and trigram filter)", 15, 10, 20, rl.WHITE)
            }

            if state.search_type == .Damerau_Levenshtein_With_Trigram {
                rl.DrawText("Damerau Levenshtein with trigram (no trigram filter)", 15, 10, 20, rl.WHITE)
            }

            if state.search_type == .Linear {
                rl.DrawText("Simple linear search", 15, 10, 20, rl.WHITE)
            }

            c_frame_count := fmt.ctprintf("%i", state.frame_count)
            rl.DrawText(c_frame_count, 1000, 15, 20, rl.ORANGE)

            c_results_count := fmt.ctprintf("Search results: %i/%i", len(state.search_results_v2), len(state.data))
            rl.DrawText(c_results_count, 600, 15, 20, rl.WHITE)

            rl.DrawRectangleRec(gui.input_rect, rl.WHITE)
            rl.DrawText(get_search_input(), 15, 40, 20, TEXT_COLOR)

            // Draw search results
            {
                screen_height := rl.GetScreenHeight()
                pos_y : i32 = 70
                for row, i in state.search_results_v2 {
                    txt := fmt.ctprintf("%s: %f", row.name, row.score)

                    rl.DrawText(txt, 15, pos_y, 20, rl.WHITE)
                    pos_y += 20

                    if pos_y >= screen_height do break
                }
            }
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }

    delete(state.data)
    delete(state.trigram_index)
    delete(state.search_results_v2)
}

@(private = "file")
update :: proc() {
    state := get_state()
    state.frame_count += 1

    if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
        if len(state.search_term) > 0 {
            pop(&state.search_term)
        }
    }

    if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
        input_as_cstring := get_search_input()

        // damerau levenshtein
        if string(input_as_cstring) == "/v1" {
            state.search_type = .Damerau_Levenshtein_With_Trigram_And_Trigram_Filter
            clear(&state.search_term)
            clear(&state.search_results_v2)
        } else if string(input_as_cstring) == "/v2" {
            state.search_type = .Damerau_Levenshtein_With_Trigram
            clear(&state.search_term)
            clear(&state.search_results_v2)
        } else if string(input_as_cstring) == "/v3" {
            state.search_type = .Linear
            clear(&state.search_term)
            clear(&state.search_results_v2)
        } else {
            state.do_search = true
        }


    }

    input := rl.GetCharPressed()
    if input > 0 {
        append(&state.search_term, input)
    }

    if state.do_search {
        if state.search_type == .Damerau_Levenshtein_With_Trigram_And_Trigram_Filter {
            start := time.tick_now()
            dl_search(true)
            elapsed := time.tick_since(start)
            fmt.println("=====> v1 Elapsed: ", time.duration_seconds(elapsed))
        }

        if state.search_type == .Damerau_Levenshtein_With_Trigram {
            start := time.tick_now()
            dl_search(false)
            elapsed := time.tick_since(start)
            fmt.println("=====> v2 Elapsed: ", time.duration_seconds(elapsed))
        }

        if state.search_type == .Linear {
            start := time.tick_now()
            search_linear()
            elapsed := time.tick_since(start)
            fmt.println("=====> v3 Elapsed: ", time.duration_seconds(elapsed))
        }
        state.do_search = false
    }
}

dl_search :: proc(filter_trigram: bool = true) {
    state := get_state()

    tmp_results_map : map[string]i32
    defer delete(tmp_results_map)

    input_as_cstring := get_search_input()
    input_lower := strings.to_lower(string(input_as_cstring), context.temp_allocator)

    input_trigram: [dynamic]string
    for i := 0; i < len(input_lower); i += 1 {
        end := i+3
        if len(input_lower) < 3 {
            end = i+2
        }
        if end > len(input_lower) do break

        trigram := input_lower[i:end]
        append(&input_trigram, trigram)
    }

    clear(&state.search_results_v2)

    /*q_gram_distance_search(input_lower, input_trigram)
    if true do return*/

    // @todo: read about Ukkonen/Gravano q-gram count filter
    // https://scispace.com/pdf/a-comparison-of-approximate-string-matching-algorithms-1gmqex4nwx.pdf

    // The Count Filtering Rule (Lemma)
    // min shared q-grams = max(|s|, |t|) - q + 1 - q * k
    // s and t are word lengths
    // q = the size of the q-gram
    // what is k? (max allowed edit distance)
    if filter_trigram {
        tmp_count : map[i32]i32 // data_idx and its count
        defer delete(tmp_count)

        for tri_g in input_trigram {
            indices, found := state.trigram_index[tri_g]
            if !found do continue

            for i in indices {
                tmp_count[i] += 1
            }
        }

        for entry_idx, count in tmp_count {
            entry := state.data[entry_idx]
            min_trigram_count := (max(len(input_lower), len(entry)) + Q_GRAM_SIZE - 1) - Q_GRAM_SIZE*EDIT_DISTANCE_THRESHOLD

            if count < i32(min_trigram_count) do continue

            entry_lower := strings.to_lower(string(entry), context.temp_allocator)
            if len(input_lower) > len(entry_lower) do continue

            _, exists := tmp_results_map[entry_lower]
            if exists {
                continue
            }

            score := similarity(input_lower, entry_lower)
            if score < 0.1 do continue

            row := Row{
                name = entry,
                score = score
            }

            tmp_results_map[entry_lower] = entry_idx
            append(&state.search_results_v2, row)
        }
    } else {
        // no q-gram
        for substring in input_trigram {
            entries, found := state.trigram_index[substring]
            if !found do continue

            for entry_idx in entries {
                foo := state.data[entry_idx]
                foo_lower := strings.to_lower(string(foo), context.temp_allocator)
                if len(input_lower) > len(foo_lower) do continue

                _, exists := tmp_results_map[foo_lower]
                if exists {
                    continue
                }

                score := similarity(input_lower, foo_lower)
                if score == 0 do continue

                row := Row{
                    name = foo,
                    score = score
                }

                tmp_results_map[foo_lower] = entry_idx
                append(&state.search_results_v2, row)
            }
        }
    }

    sort.quick_sort_proc(state.search_results_v2[:], proc(a, b: Row) -> int {
        if a.score < b.score do return 1
        if a.score > b.score do return -1
        return 0
    })
}


search_linear :: proc() {
    input_as_cstring := get_search_input()
    input_lower := strings.to_lower(string(input_as_cstring), context.temp_allocator)

    state := get_state()
    clear(&state.search_results_v2)

    for it in state.data {
        lower_it := strings.to_lower(string(it), context.temp_allocator)
        if strings.contains(lower_it, input_lower) {
            row := Row{
                name = it,
                score = 0
            }
            append(&state.search_results_v2, row)
        }
    }
}

// @todo
build_dataset :: proc() {
    state := get_state()

    result: [dynamic]cstring
    defer delete(result)

    data, err := os.read_entire_file("./assets/books_raw.txt", context.allocator)
	if err != nil {
		// could not read file
		return
	}
	defer delete(data, context.allocator)

	it := string(data)
	for line in strings.split_lines_iterator(&it) {
        c_line := strings.clone_to_cstring(line)

        idx := len(result)
        trigram_from_string(line, i32(idx))
        append(&result, c_line)
	}

    append(&state.data, ..result[:])
}

trigram_from_string :: proc(input: string, input_idx: i32) {
    state := get_state()

    for i := 0; i < len(input); i += 1 {
        end := i+3
        if len(input) < 3 {
            end = i+2
        }

        if end > len(input) do break

        trigram_lower := strings.to_lower(input[i:end])
        track_idx_array, trigram_exists := state.trigram_index[trigram_lower]
        if trigram_exists {
            append(&track_idx_array, input_idx)
            state.trigram_index[trigram_lower] = track_idx_array
        } else {
            array := make([dynamic]i32)
            append(&array, input_idx)
            state.trigram_index[trigram_lower] = array
        }
    }
}

get_search_input :: proc() -> cstring {
    state := get_state()
    cinput := fmt.ctprintf("%s", state.search_term)
    return cinput
}

init_gui :: proc() -> ^Gui {
    gui := get_gui()
    gui.input_rect = rl.Rectangle{ 10, 35, 500, 30 }
    return gui
}

