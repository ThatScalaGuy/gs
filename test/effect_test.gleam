import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import gs
import gs/effect

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// CONSTRUCTOR TESTS
// =============================================================================

pub fn succeed_test() {
  effect.succeed(42)
  |> effect.to_list
  |> should.equal(Ok([42]))
}

pub fn fail_test() {
  effect.fail("error")
  |> effect.to_list
  |> should.equal(Error("error"))
}

pub fn empty_test() {
  effect.empty()
  |> effect.to_list
  |> should.equal(Ok([]))
}

pub fn from_stream_test() {
  gs.from_list([1, 2, 3])
  |> effect.from_stream
  |> effect.to_list
  |> should.equal(Ok([1, 2, 3]))
}

pub fn from_results_test() {
  gs.from_list([Ok(1), Ok(2), Ok(3)])
  |> effect.from_results
  |> effect.to_list
  |> should.equal(Ok([1, 2, 3]))
}

pub fn from_results_with_error_test() {
  gs.from_list([Ok(1), Error("oops"), Ok(3)])
  |> effect.from_results
  |> effect.to_list
  |> should.equal(Error("oops"))
}

pub fn from_result_ok_test() {
  effect.from_result(Ok(42))
  |> effect.to_list
  |> should.equal(Ok([42]))
}

pub fn from_result_error_test() {
  effect.from_result(Error("failed"))
  |> effect.to_list
  |> should.equal(Error("failed"))
}

pub fn from_list_test() {
  effect.from_list([1, 2, 3])
  |> effect.to_list
  |> should.equal(Ok([1, 2, 3]))
}

// =============================================================================
// TRANSFORMATION TESTS
// =============================================================================

pub fn map_test() {
  effect.from_list([1, 2, 3])
  |> effect.map(fn(x) { x * 2 })
  |> effect.to_list
  |> should.equal(Ok([2, 4, 6]))
}

pub fn map_preserves_error_test() {
  effect.fail("error")
  |> effect.map(fn(x: Int) { x * 2 })
  |> effect.to_list
  |> should.equal(Error("error"))
}

pub fn flat_map_test() {
  effect.from_list([1, 2, 3])
  |> effect.flat_map(fn(x) { effect.from_list([x, x * 10]) })
  |> effect.to_list
  |> should.equal(Ok([1, 10, 2, 20, 3, 30]))
}

pub fn flat_map_error_test() {
  effect.from_list([1, 2, 3])
  |> effect.flat_map(fn(x) {
    case x == 2 {
      True -> effect.fail("found 2!")
      False -> effect.succeed(x)
    }
  })
  |> effect.to_list
  |> should.equal(Error("found 2!"))
}

pub fn filter_test() {
  effect.from_list([1, 2, 3, 4, 5])
  |> effect.filter(fn(x) { x % 2 == 0 })
  |> effect.to_list
  |> should.equal(Ok([2, 4]))
}

pub fn map_error_test() {
  effect.fail("error")
  |> effect.map_error(fn(e) { "wrapped: " <> e })
  |> effect.to_list
  |> should.equal(Error("wrapped: error"))
}

pub fn take_test() {
  effect.from_list([1, 2, 3, 4, 5])
  |> effect.take(3)
  |> effect.to_list
  |> should.equal(Ok([1, 2, 3]))
}

pub fn drop_test() {
  effect.from_list([1, 2, 3, 4, 5])
  |> effect.drop(2)
  |> effect.to_list
  |> should.equal(Ok([3, 4, 5]))
}

pub fn tap_test() {
  let result =
    effect.from_list([1, 2, 3])
    |> effect.tap(fn(_) { Nil })
    |> effect.to_list

  should.equal(result, Ok([1, 2, 3]))
}

// =============================================================================
// ERROR HANDLING TESTS
// =============================================================================

pub fn handle_error_test() {
  effect.from_list([1, 2])
  |> effect.flat_map(fn(x) {
    case x == 2 {
      True -> effect.fail("two!")
      False -> effect.succeed(x)
    }
  })
  |> effect.handle_error(fn(_) { effect.succeed(99) })
  |> effect.to_list
  |> should.equal(Ok([1, 99]))
}

pub fn recover_test() {
  effect.fail("error")
  |> effect.recover(fn(_) { 0 })
  |> effect.to_list
  |> should.equal(Ok([0]))
}

pub fn recover_with_test() {
  effect.fail("error")
  |> effect.recover_with(fn(_) { effect.from_list([1, 2, 3]) })
  |> effect.to_list
  |> should.equal(Ok([1, 2, 3]))
}

pub fn catch_when_matching_test() {
  effect.fail("recoverable")
  |> effect.catch_when(fn(e) { e == "recoverable" }, fn(_) { effect.succeed(0) })
  |> effect.to_list
  |> should.equal(Ok([0]))
}

pub fn catch_when_not_matching_test() {
  effect.fail("fatal")
  |> effect.catch_when(fn(e) { e == "recoverable" }, fn(_) { effect.succeed(0) })
  |> effect.to_list
  |> should.equal(Error("fatal"))
}

pub fn catch_some_matching_test() {
  effect.fail(404)
  |> effect.catch_some(fn(code) {
    case code {
      404 -> Some(effect.succeed("not found"))
      _ -> None
    }
  })
  |> effect.to_list
  |> should.equal(Ok(["not found"]))
}

pub fn catch_some_not_matching_test() {
  effect.fail(500)
  |> effect.catch_some(fn(code) {
    case code {
      404 -> Some(effect.succeed("not found"))
      _ -> None
    }
  })
  |> effect.to_list
  |> should.equal(Error(500))
}

pub fn or_else_test() {
  effect.fail("first failed")
  |> effect.or_else(effect.succeed(42))
  |> effect.to_list
  |> should.equal(Ok([42]))
}

// =============================================================================
// SINK TESTS
// =============================================================================

pub fn to_fold_test() {
  effect.from_list([1, 2, 3, 4, 5])
  |> effect.to_fold(0, fn(acc, x) { acc + x })
  |> should.equal(Ok(15))
}

pub fn to_fold_with_error_test() {
  effect.from_results(gs.from_list([Ok(1), Ok(2), Error("stop"), Ok(4)]))
  |> effect.to_fold(0, fn(acc, x) { acc + x })
  |> should.equal(Error("stop"))
}

pub fn drain_test() {
  effect.from_list([1, 2, 3])
  |> effect.drain
  |> should.equal(Ok(Nil))
}

pub fn to_first_test() {
  effect.from_list([1, 2, 3])
  |> effect.to_first
  |> should.equal(Ok(Some(1)))
}

pub fn to_first_empty_test() {
  effect.empty()
  |> effect.to_first
  |> should.equal(Ok(None))
}

pub fn to_last_test() {
  effect.from_list([1, 2, 3])
  |> effect.to_last
  |> should.equal(Ok(Some(3)))
}

// =============================================================================
// CONVERSION TESTS
// =============================================================================

pub fn to_result_stream_test() {
  effect.from_list([1, 2, 3])
  |> effect.to_result_stream
  |> gs.to_list
  |> should.equal([Ok(1), Ok(2), Ok(3)])
}

pub fn to_stream_lossy_test() {
  effect.from_results(gs.from_list([Ok(1), Error("x"), Ok(3)]))
  |> effect.to_stream_lossy
  |> gs.to_list
  |> should.equal([1])
}

pub fn to_stream_with_default_test() {
  effect.from_results(gs.from_list([Ok(1), Error("x"), Ok(3)]))
  |> effect.to_stream_with_default(0)
  |> gs.to_list
  |> should.equal([1, 0, 3])
}

// =============================================================================
// COMBINATOR TESTS
// =============================================================================

pub fn zip_test() {
  let left = effect.from_list([1, 2])
  let right = effect.from_list(["a", "b"])

  effect.zip(left, right)
  |> effect.to_list
  |> should.equal(Ok([#(1, "a"), #(1, "b"), #(2, "a"), #(2, "b")]))
}

pub fn zip_with_test() {
  let left = effect.from_list([1, 2])
  let right = effect.from_list([10, 20])

  effect.zip_with(left, right, fn(a, b) { a + b })
  |> effect.to_list
  |> should.equal(Ok([11, 21, 12, 22]))
}
