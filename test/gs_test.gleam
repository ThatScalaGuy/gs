import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import gs

pub fn main() {
  gleeunit.main()
}

pub fn empty_test() {
  gs.from_empty()
  |> gs.to_list
  |> should.equal([])
}

pub fn pure_test() {
  gs.from_pure(42)
  |> gs.to_list
  |> should.equal([42])
}

pub fn from_list_test() {
  gs.from_list([1, 2, 3])
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_list([])
  |> gs.to_list
  |> should.equal([])
}

// pub fn from_bit_array_test() {
//   <<1, 2, 3>>
//   |> gs.from_bit_array
//   |> gs.to_list
//   |> should.equal([1, 2, 3])

//   <<>>
//   |> gs.from_bit_array
//   |> gs.to_list
//   |> should.equal([])
// }

pub fn from_option_test() {
  option.Some(42)
  |> gs.from_option
  |> gs.to_list
  |> should.equal([42])

  option.None
  |> gs.from_option
  |> gs.to_list
  |> should.equal([])
}

pub fn from_result_test() {
  Ok(42)
  |> gs.from_result
  |> gs.to_list
  |> should.equal([42])

  Error("error")
  |> gs.from_result
  |> gs.to_list
  |> should.equal([])
}

pub fn repeat_test() {
  gs.from_repeat(1)
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 1, 1])
}

pub fn map_test() {
  gs.from_list([1, 2, 3])
  |> gs.map(fn(x) { x * 2 })
  |> gs.to_list
  |> should.equal([2, 4, 6])
}

pub fn filter_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.filter(fn(x) { x % 2 == 0 })
  |> gs.to_list
  |> should.equal([2, 4])
}

pub fn take_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_list([1, 2])
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 2])

  gs.from_list([1, 2, 3])
  |> gs.take(0)
  |> gs.to_list
  |> should.equal([])
}

pub fn concat_test() {
  let s1 = gs.from_list([1, 2])
  let s2 = gs.from_list([3, 4])

  gs.concat(s1, s2)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4])

  gs.concat(gs.from_empty(), s2)
  |> gs.to_list
  |> should.equal([3, 4])

  gs.concat(s1, gs.from_empty())
  |> gs.to_list
  |> should.equal([1, 2])
}

pub fn chunks_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.chunks(2)
  |> gs.to_list
  |> should.equal([[1, 2], [3, 4], [5]])

  gs.from_list([1, 2, 3, 4])
  |> gs.chunks(2)
  |> gs.to_list
  |> should.equal([[1, 2], [3, 4]])

  gs.from_list([1, 2, 3])
  |> gs.chunks(0)
  |> gs.to_list
  |> should.equal([])
}

pub fn to_fold_test() {
  gs.from_list([1, 2, 3, 4])
  |> gs.to_fold(0, fn(acc, x) { acc + x })
  |> should.equal(10)

  gs.from_empty()
  |> gs.to_fold(42, fn(acc, x) { acc + x })
  |> should.equal(42)
}

pub fn zip_test() {
  let s1 = gs.from_list([1, 2, 3])
  let s2 = gs.from_list(["a", "b", "c"])
  gs.zip(s1, s2)
  |> gs.to_list
  |> should.equal([#(1, "a"), #(2, "b"), #(3, "c")])

  // Empty stream cases
  gs.zip(gs.from_empty(), s2)
  |> gs.to_list
  |> should.equal([])

  gs.zip(s1, gs.from_empty())
  |> gs.to_list
  |> should.equal([])
}

pub fn flat_map_test() {
  gs.from_list([1, 2])
  |> gs.flat_map(fn(x) { gs.from_pure(x * 2) })
  |> gs.to_list
  |> should.equal([2, 4])

  gs.from_list([[1, 2], [3, 4]])
  |> gs.flat_map(gs.from_list)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4])

  gs.from_empty()
  |> gs.flat_map(gs.from_pure)
  |> gs.to_list
  |> should.equal([])
}

pub fn repeat_eval_test() {
  let counter =
    gs.from_repeat_eval(fn() { 1 })
    |> gs.take(3)
    |> gs.to_list

  should.equal(counter, [1, 1, 1])
}

pub fn zip_with_test() {
  let s1 = gs.from_list([1, 2, 3])
  let s2 = gs.from_list([4, 5, 6])
  gs.zip_with(s1, s2, fn(x, y) { x + y })
  |> gs.to_list
  |> should.equal([5, 7, 9])
}

pub fn to_nil_test() {
  gs.from_list([1, 2, 3])
  |> gs.to_nil
  |> should.equal(Nil)
}

pub fn to_option_test() {
  gs.from_list([1, 2, 3])
  |> gs.to_option
  |> should.equal(option.Some(1))

  gs.from_empty()
  |> gs.to_option
  |> should.equal(option.None)
}

pub fn try_recover_test() {
  gs.from_list([1, 2, 3])
  |> gs.map(fn(x) { Ok(x) })
  |> gs.try_recover(fn(_) { gs.from_pure(0) })
  |> gs.to_list
  |> should.equal([1, 2, 3])

  Error(5)
  |> gs.from_pure
  |> gs.try_recover(fn(error) { gs.from_pure(error + 1) })
  |> gs.to_list
  |> should.equal([6])
}

pub fn take_while_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.take_while(fn(x) { x < 4 })
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_list([1, 2, 3])
  |> gs.take_while(fn(_) { False })
  |> gs.to_list
  |> should.equal([])

  gs.from_list([1, 2, 3])
  |> gs.take_while(fn(_) { True })
  |> gs.to_list
  |> should.equal([1, 2, 3])
}

pub fn drop_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.drop(2)
  |> gs.to_list
  |> should.equal([3, 4, 5])

  gs.from_list([1, 2])
  |> gs.drop(3)
  |> gs.to_list
  |> should.equal([])

  gs.from_list([1, 2, 3])
  |> gs.drop(0)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_empty()
  |> gs.drop(1)
  |> gs.to_list
  |> should.equal([])
}

pub fn intersperse_test() {
  gs.from_list([1, 2, 3])
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([1, 0, 2, 0, 3])

  gs.from_list([1])
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([1])

  gs.from_empty()
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([])

  gs.from_list([1, 2])
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([1, 0, 2])
}

pub fn from_counter_test() {
  gs.from_counter(1)
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_counter(0)
  |> gs.take(4)
  |> gs.to_list
  |> should.equal([0, 1, 2, 3])

  gs.from_counter(-2)
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([-2, -1, 0])
}

pub fn from_range_test() {
  gs.from_range(1, 3)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_range(0, 0)
  |> gs.to_list
  |> should.equal([0])

  gs.from_range(3, 1)
  |> gs.to_list
  |> should.equal([])

  gs.from_range(-2, 1)
  |> gs.to_list
  |> should.equal([-2, -1, 0, 1])
}

pub fn from_range_exclusive_test() {
  gs.from_range_exclusive(1, 4)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_range_exclusive(0, 1)
  |> gs.to_list
  |> should.equal([0])

  gs.from_range_exclusive(3, 1)
  |> gs.to_list
  |> should.equal([])

  gs.from_range_exclusive(-2, 1)
  |> gs.to_list
  |> should.equal([-2, -1, 0])

  gs.from_range_exclusive(1, 1)
  |> gs.to_list
  |> should.equal([])
}

// pub fn from_timestamp_eval_test() {
//   gs.from_timestamp_eval()
//   |> gs.take(2)
//   |> gs.tap(fn(x) { io.debug(x) })
//   |> gs.to_list
// }

pub fn from_tick_test() {
  // Test that ticks emit at roughly the right intervals
  gs.from_tick(1000)
  |> gs.take(3)
  |> gs.to_list
  |> list.length
  |> should.equal(3)
}

pub fn from_subject_test() {
  let subject = process.new_subject()
  let subject_stream =
    gs.from_subject(subject)
    |> gs.take(3)

  process.send(subject, Some(1))
  process.send(subject, Some(2))
  process.send(subject, Some(3))
  process.send(subject, Some(4))

  subject_stream
  |> gs.to_list
  |> should.equal([1, 2, 3])

  process.send(subject, None)
  gs.from_subject(subject) |> gs.to_list |> should.equal([4])
}

pub fn split_test() {
  let #(left, right, _) =
    gs.from_list([1, 2, 3, 4, 5])
    |> gs.to_split(fn(x) { x % 2 == 0 })

  left
  |> gs.to_list
  |> should.equal([2, 4])

  right
  |> gs.to_list
  |> should.equal([1, 3, 5])

  // Test empty stream
  let #(left2, right2, _) =
    gs.from_empty()
    |> gs.to_split(fn(_) { True })

  left2
  |> gs.to_list
  |> should.equal([])

  right2
  |> gs.to_list
  |> should.equal([])

  // Test single element
  let #(left3, right3, _) =
    gs.from_pure(1)
    |> gs.to_split(fn(x) { x == 1 })

  left3
  |> gs.to_list
  |> should.equal([1])

  right3
  |> gs.to_list
  |> should.equal([])
}

pub fn from_state_eval_test() {
  // Basic counter example
  gs.from_state_eval(0, fn(state) { #(state, state + 1) })
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([0, 1, 2])

  // Fibonacci sequence example
  gs.from_state_eval(#(0, 1), fn(state) {
    let #(current, next) = state
    #(current, #(next, current + next))
  })
  |> gs.take(6)
  |> gs.to_list
  |> should.equal([0, 1, 1, 2, 3, 5])

  // String state example
  gs.from_state_eval("a", fn(state) { #(state, state <> "a") })
  |> gs.take(3)
  |> gs.to_list
  |> should.equal(["a", "aa", "aaa"])

  // Empty stream if never pulled
  gs.from_state_eval(0, fn(state) { #(state, state + 1) })
  |> gs.take(0)
  |> gs.to_list
  |> should.equal([])
}

pub fn rate_limit_linear_test() {
  // Test basic functionality - should emit 2 elements per second
  gs.from_list([1, 2, 3, 4])
  |> gs.rate_limit_linear(2, 1000)
  |> gs.take(4)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4])

  // Test empty stream
  gs.from_empty()
  |> gs.rate_limit_linear(2, 1000)
  |> gs.to_list
  |> should.equal([])

  // Test single element
  gs.from_pure(1)
  |> gs.rate_limit_linear(1, 1000)
  |> gs.to_list
  |> should.equal([1])

  // Test with faster rate (500ms interval)
  gs.from_list([1, 2])
  |> gs.rate_limit_linear(2, 500)
  |> gs.to_list
  |> should.equal([1, 2])
}

pub fn count_test() {
  // Basic counting
  gs.from_list([1, 2, 3])
  |> gs.count()
  |> gs.to_list
  |> should.equal([#(1, 1), #(2, 2), #(3, 3)])

  // Empty stream
  gs.from_empty()
  |> gs.count()
  |> gs.to_list
  |> should.equal([])

  // Single element 
  gs.from_pure(42)
  |> gs.count()
  |> gs.to_list
  |> should.equal([#(42, 1)])

  // Test with take
  gs.from_counter(1)
  |> gs.count()
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([#(1, 1), #(2, 2), #(3, 3)])
}

pub fn window_test() {
  // Basic windowing with complete windows
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.window(3)
  |> gs.to_list
  |> should.equal([[1, 2, 3], [2, 3, 4], [3, 4, 5]])

  // Empty stream
  gs.from_empty()
  |> gs.window(3)
  |> gs.to_list
  |> should.equal([])

  // Stream shorter than window size
  gs.from_list([1, 2])
  |> gs.window(3)
  |> gs.to_list
  |> should.equal([])

  // Single element stream
  gs.from_pure(1)
  |> gs.window(2)
  |> gs.to_list
  |> should.equal([])

  // Window size of 1 (should return single element lists)
  gs.from_list([1, 2, 3])
  |> gs.window(1)
  |> gs.to_list
  |> should.equal([[1], [2], [3]])

  // Invalid window size
  gs.from_list([1, 2, 3])
  |> gs.window(0)
  |> gs.to_list
  |> should.equal([])

  gs.from_list([1, 2, 3])
  |> gs.window(-1)
  |> gs.to_list
  |> should.equal([])

  // Window size exactly matches stream length
  gs.from_list([1, 2, 3])
  |> gs.window(3)
  |> gs.to_list
  |> should.equal([[1, 2, 3]])
}

pub fn buffer_test() {
  // Basic buffering with Wait strategy
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.buffer(3, gs.Wait)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4, 5])

  // Empty stream
  gs.from_empty()
  |> gs.buffer(3, gs.Wait)
  |> gs.to_list
  |> should.equal([])

  // Single element
  gs.from_pure(42)
  |> gs.buffer(2, gs.Wait)
  |> gs.to_list
  |> should.equal([42])

  // Drop strategy
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.buffer(2, gs.Drop)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4, 5])

  // Stop strategy
  gs.from_list([1, 2, 3])
  |> gs.buffer(2, gs.Stop)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  // Test with infinite stream and take
  gs.from_counter(1)
  |> gs.buffer(3, gs.Wait)
  |> gs.take(5)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4, 5])

  // Test with slow consumer using sleep
  gs.from_list([1, 2, 3])
  |> gs.buffer(2, gs.Wait)
  |> gs.map(fn(x) {
    process.sleep(100)
    // Simulate slow processing
    x
  })
  |> gs.to_list
  |> should.equal([1, 2, 3])
}

pub fn bracket_test() {
  // Test counter for tracking resource cleanup
  let counter = process.new_subject()

  // Basic bracket usage with resource tracking
  gs.from_list([1, 2, 3])
  |> gs.bracket(
    acquire: fn() {
      process.send(counter, "acquired")
      "resource"
    },
    cleanup: fn(_resource) {
      process.send(counter, "cleaned")
      Nil
    },
  )
  |> gs.map(fn(pair) { pair.1 })
  |> gs.to_list
  |> should.equal([1, 2, 3])

  // Verify resource lifecycle (acquire once, cleanup once)
  process.receive(counter, 0)
  |> should.equal(Ok("acquired"))
  process.receive(counter, 0)
  |> should.equal(Ok("cleaned"))

  // Test with empty stream
  gs.from_empty()
  |> gs.bracket(
    acquire: fn() {
      process.send(counter, "acquired")
      "resource"
    },
    cleanup: fn(_resource) {
      process.send(counter, "cleaned")
      Nil
    },
  )
  |> gs.to_list
  |> should.equal([])

  // Verify resource cleanup for empty stream
  process.receive(counter, 0)
  |> should.equal(Ok("acquired"))
  process.receive(counter, 0)
  |> should.equal(Ok("cleaned"))

  // Test with take operation
  gs.from_counter(1)
  |> gs.bracket(
    acquire: fn() {
      process.send(counter, "acquired")
      "resource"
    },
    cleanup: fn(_resource) {
      process.send(counter, "cleaned")
      Nil
    },
  )
}

pub fn filter_with_previous_test() {
  // Test basic filtering (keep only increasing values)
  gs.from_list([1, 2, 2, 3, 2, 4])
  |> gs.filter_with_previous(fn(prev, current) {
    case prev {
      Some(p) -> current > p
      None -> True
    }
  })
  |> gs.to_list
  |> should.equal([1, 2, 3, 4])

  // Test empty stream
  gs.from_empty()
  |> gs.filter_with_previous(fn(_, _) { True })
  |> gs.to_list
  |> should.equal([])
  // Test single element (first element always passes with None)
  gs.from_pure(42)
  |> gs.filter_with_previous(fn(prev, _) {
    case prev {
      Some(_) -> False
      None -> True
    }
  })
  |> gs.to_list
  |> should.equal([42])
  // Test filtering all elements except first
  gs.from_list([1, 2, 3])
  |> gs.filter_with_previous(fn(prev, _) {
    case prev {
      Some(_) -> False
      None -> True
    }
  })
  |> gs.to_list
  |> should.equal([1])
  // Test keeping only duplicates
  gs.from_list([1, 1, 2, 2, 2, 3, 4, 4])
  |> gs.filter_with_previous(fn(prev, current) {
    case prev {
      Some(p) -> {
        current == p
      }

      None -> False
    }
  })
  |> gs.to_list
  |> should.equal([1, 2, 2, 4])
  // Test with take
  gs.from_counter(1)
  |> gs.filter_with_previous(fn(prev, current) {
    case prev {
      Some(p) -> current == p + 1
      None -> True
    }
  })
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 2, 3])
}
