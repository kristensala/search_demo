/*
   String matching with a damerau levenshtein distance function
   and trigram
 */
package main

damerau_levenshtein_distance :: proc(s1: string, s2: string) -> int {
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

// Gets the similarity of 2 strings in percentage,
// using damerau levenshtein distance
similarity :: proc(s1: string, s2: string) -> f64 {
    x := max(len(s1), len(s2))
    if x == 0 do return 1.0
    rune_level_distance := 1.0 - f64(damerau_levenshtein_distance(s1, s2)) / f64(x)
    return rune_level_distance
}

