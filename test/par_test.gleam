import gleam/int
import gleam/list
import gleeunit
import gleeunit/should
import gs
import gs/par

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// PAR_EVAL_MAP TESTS
// =============================================================================

pub fn par_eval_map_ordered_test() {
  let stream =
    [1, 2, 3, 4, 5, 6]
    |> gs.from_list

  let result =
    stream
    |> par.par_eval_map(concurrency: 3, preserve_order: True, with: fn(x) {
      x * 2
    })
    |> gs.to_list

  result
  |> should.equal([2, 4, 6, 8, 10, 12])
}

pub fn par_eval_map_unordered_test() {
  let stream =
    [1, 2, 3, 4, 5, 6]
    |> gs.from_list

  let result =
    stream
    |> par.par_eval_map(concurrency: 3, preserve_order: False, with: fn(x) {
      x * 2
    })
    |> gs.to_list
    |> list.sort(int.compare)

  // Unordered, but all elements should be present
  result
  |> should.equal([2, 4, 6, 8, 10, 12])
}

pub fn par_eval_map_empty_test() {
  let stream: gs.Stream(Int) = gs.from_empty()

  let result =
    stream
    |> par.par_eval_map(concurrency: 3, preserve_order: True, with: fn(x) {
      x * 2
    })
    |> gs.to_list

  result
  |> should.equal([])
}

pub fn par_eval_map_single_element_test() {
  let stream =
    [42]
    |> gs.from_list

  let result =
    stream
    |> par.par_eval_map(concurrency: 3, preserve_order: True, with: fn(x) {
      x * 2
    })
    |> gs.to_list

  result
  |> should.equal([84])
}

// =============================================================================
// RACE TESTS
// =============================================================================

pub fn race_single_stream_test() {
  let stream = gs.from_pure(42)

  let result =
    [stream]
    |> par.race
    |> gs.to_list

  result
  |> should.equal([42])
}

// =============================================================================
// DEPRECATED PAR_MAP TEST (kept for backwards compatibility)
// =============================================================================

@external(erlang, "gleam_stdlib", "identity")
fn suppress_warning(x: a) -> a

pub fn par_map_deprecated_test() {
  let stream =
    [1, 2, 3, 4, 5, 6]
    |> gs.from_list

  // Suppress the deprecation warning for this test
  let par_map_fn = suppress_warning(par.par_map)

  let result =
    stream
    |> par_map_fn(3, fn(x) { x * 2 })
    |> gs.to_list

  result
  |> should.equal([2, 4, 6, 8, 10, 12])
}
