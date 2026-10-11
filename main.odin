package main

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

Rect :: rl.Rectangle

App_State :: struct {
    frame_count: int,
    data: [dynamic]cstring,
    trigram_index: map[string][dynamic]i32,

    search_term: [dynamic]rune,
    search_results: [dynamic]cstring,
    search_results_v2: [dynamic]Row,

    last_input_at: int, // frame count
    do_search: bool

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
            c_frame_count := fmt.ctprintf("%i", state.frame_count)
            rl.DrawText(c_frame_count, 1000, 15, 20, rl.ORANGE)

            c_results_count := fmt.ctprintf("Search results: %i/%i", len(state.search_results_v2), len(state.data))
            rl.DrawText(c_results_count, 600, 15, 20, rl.WHITE)

            rl.DrawRectangleRec(gui.input_rect, rl.WHITE)
            rl.DrawText(get_search_input(), 15, 15, 20, TEXT_COLOR)

            screen_height := rl.GetScreenHeight()
            pos_y : i32 = 50
            for row, i in state.search_results_v2 {
                txt := fmt.ctprintf("%s: %f", row.name, row.score)

                rl.DrawText(txt, 15, pos_y, 20, rl.WHITE)
                pos_y += 20

                if pos_y >= screen_height do break

            }

        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }

    delete(state.data)
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

    input := rl.GetCharPressed()
    if input > 0 {
        state.last_input_at = state.frame_count
        state.do_search = true

        append(&state.search_term, input)
        //search_linear()

        /*fmt.println(state.frame_count - state.last_input_at)
        if state.frame_count - state.last_input_at > 60 {
            trigram_search()
        }*/
    }

    if state.frame_count - state.last_input_at > 30 && state.do_search {
        fmt.println("=======> SEARCH <=========")
        trigram_search()
        //search_linear()
        state.do_search = false
        
    }


}

// Rune level "Damerau-Levenshtein distance"
measure_string_distance :: proc(s1: string, s2: string) -> int {
    rows := len(s1) + 1
    cols := len(s2) + 1

    dp := make([]int, rows*cols)
    defer delete(dp)

    for i := 0; i <= len(s1); i+=1 {
        dp[i * cols] = i
    }

    for j := 0; j <= len(s2); j+=1 {
        dp[j] = j
    }

    for i := 1; i <= len(s1); i+=1 {
        for j := 1; j <= len(s2); j+=1 {
            if s1[i-1] == s2[j-1] {
                dp[i * cols + j] = dp[(i - 1) * cols + (j - 1)]
            } else {
                // dp[i][j] = min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                dp[i * cols + j] = 1 + min(dp[(i - 1) * cols + j], dp[i * cols + (j - 1)], dp[(i - 1) * cols + (j - 1)])
            }
        }
    }

    distance := dp[(rows - 1) * cols + (cols - 1)]
    return distance
}

similarity :: proc(s1: string, s2: string) -> f64 {
    x := max(len(s1), len(s2))
    if x == 0 do return 1.0
    rune_level_distance := 1.0 - f64(measure_string_distance(s1, s2)) / f64(x)
    return rune_level_distance
}

trigram_search :: proc() {
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

    min_trigram_count := i32(f64(len(input_lower)) * 0.70)
    fmt.println("=========> MIN: ", min_trigram_count)

    tmp_count : map[i32]i32 // data_idx and its count
    defer delete(tmp_count)

    for tri_g in input_trigram {
        indices, found := state.trigram_index[tri_g]
        if !found do continue

        for i in indices {
            //_, exists := tmp_count[i]
            tmp_count[i] += 1
        }
    }

    for entry_idx, count in tmp_count {
        if count < min_trigram_count do continue

        foo := state.data[entry_idx]
        foo_lower := strings.to_lower(string(foo), context.temp_allocator)
        if len(input_lower) > len(foo_lower) do continue

            _, exists := tmp_results_map[foo_lower]
            if exists {
                continue
            }

            score := similarity(input_lower, foo_lower)
            if score < 0.1 do continue

            row := Row{
                name = foo,
                score = score
            }

            tmp_results_map[foo_lower] = entry_idx
            //append(&state.search_results, foo)
            append(&state.search_results_v2, row)


    }

    /*clear(&state.search_results_v2)
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
            //append(&state.search_results, foo)
            append(&state.search_results_v2, row)
        }
    }*/

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
    clear(&state.search_results)

    for it in state.data {
        lower_it := strings.to_lower(string(it), context.temp_allocator)
        if strings.contains(lower_it, input_lower) {
            append(&state.search_results, it)
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
    gui.input_rect = rl.Rectangle{ 10, 10, 500, 30 }
    return gui
}

