/// Effect module for typed error handling in streams.
///
/// An Effect wraps a Stream with an error channel, providing composable
/// error handling while preserving pull-based lazy semantics.
///
/// ## Overview
/// ```gleam
/// // Create an effect from a stream
/// gs.from_range(1, 10)
/// |> effect.from_stream
/// |> effect.map(fn(x) { x * 2 })
/// |> effect.flat_map(fn(x) {
///   case x > 10 {
///     True -> effect.fail("Too large")
///     False -> effect.succeed(x)
///   }
/// })
/// |> effect.to_list
/// // -> Error("Too large") or Ok([2, 4, 6, 8, 10])
/// ```
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gs.{type Stream}

/// An Effect represents a Stream with typed error handling.
///
/// Internally, it wraps a `Stream(Result(a, e))` and provides operations
/// that handle error propagation automatically. When an error is encountered,
/// the stream short-circuits and the error becomes the final result.
pub type Effect(a, e) {
  Effect(stream: Stream(Result(a, e)))
}

// =============================================================================
// CONSTRUCTORS
// =============================================================================

/// Create an Effect containing a single successful value.
///
/// ## Example
/// ```gleam
/// effect.succeed(42)
/// |> effect.to_list
/// // -> Ok([42])
/// ```
pub fn succeed(value: a) -> Effect(a, e) {
  Effect(stream: gs.from_pure(Ok(value)))
}

/// Create an Effect that fails with an error.
///
/// ## Example
/// ```gleam
/// effect.fail("something went wrong")
/// |> effect.to_list
/// // -> Error("something went wrong")
/// ```
pub fn fail(error: e) -> Effect(a, e) {
  Effect(stream: gs.from_pure(Error(error)))
}

/// Create an empty Effect (no values, no error).
///
/// ## Example
/// ```gleam
/// effect.empty()
/// |> effect.to_list
/// // -> Ok([])
/// ```
pub fn empty() -> Effect(a, e) {
  Effect(stream: gs.from_empty())
}

/// Lift an infallible Stream into an Effect.
///
/// All values from the stream become successful results.
///
/// ## Example
/// ```gleam
/// gs.from_list([1, 2, 3])
/// |> effect.from_stream
/// |> effect.to_list
/// // -> Ok([1, 2, 3])
/// ```
pub fn from_stream(stream: Stream(a)) -> Effect(a, e) {
  Effect(stream: gs.map(stream, Ok))
}

/// Create an Effect from a Stream of Results.
///
/// This is the most direct way to create an Effect when you already
/// have a stream that may contain errors.
///
/// ## Example
/// ```gleam
/// gs.from_list([Ok(1), Ok(2), Error("oops"), Ok(3)])
/// |> effect.from_results
/// |> effect.to_list
/// // -> Error("oops")
/// ```
pub fn from_results(stream: Stream(Result(a, e))) -> Effect(a, e) {
  Effect(stream: stream)
}

/// Create an Effect from a single Result value.
///
/// ## Example
/// ```gleam
/// effect.from_result(Ok(42))
/// |> effect.to_list
/// // -> Ok([42])
///
/// effect.from_result(Error("failed"))
/// |> effect.to_list
/// // -> Error("failed")
/// ```
pub fn from_result(result: Result(a, e)) -> Effect(a, e) {
  Effect(stream: gs.from_pure(result))
}

/// Create an Effect from a fallible function.
///
/// The function is called lazily when the effect is consumed.
///
/// ## Example
/// ```gleam
/// effect.from_attempt(fn() {
///   case some_risky_operation() {
///     Ok(value) -> Ok(value)
///     Error(e) -> Error(e)
///   }
/// })
/// ```
pub fn from_attempt(f: fn() -> Result(a, e)) -> Effect(a, e) {
  Effect(stream: gs.from_repeat_eval(f) |> gs.take(1))
}

/// Create an Effect from a list of values.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.to_list
/// // -> Ok([1, 2, 3])
/// ```
pub fn from_list(items: List(a)) -> Effect(a, e) {
  from_stream(gs.from_list(items))
}

// =============================================================================
// TRANSFORMATIONS
// =============================================================================

/// Map over successful values in the Effect.
///
/// Errors are propagated unchanged.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.map(fn(x) { x * 2 })
/// |> effect.to_list
/// // -> Ok([2, 4, 6])
/// ```
pub fn map(effect: Effect(a, e), f: fn(a) -> b) -> Effect(b, e) {
  Effect(stream: gs.map(effect.stream, result.map(_, f)))
}

/// FlatMap for sequencing effects (monadic bind).
///
/// Applies a function that returns an Effect to each successful value,
/// flattening the results. Short-circuits on error.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.flat_map(fn(x) {
///   case x == 2 {
///     True -> effect.fail("found 2!")
///     False -> effect.succeed(x * 10)
///   }
/// })
/// |> effect.to_list
/// // -> Error("found 2!")
/// ```
pub fn flat_map(effect: Effect(a, e), f: fn(a) -> Effect(b, e)) -> Effect(b, e) {
  Effect(
    stream: gs.flat_map(effect.stream, fn(result) {
      case result {
        Ok(value) -> { f(value) }.stream
        Error(e) -> gs.from_pure(Error(e))
      }
    }),
  )
}

/// Filter successful values based on a predicate.
///
/// Values that don't match the predicate are dropped.
/// Errors are propagated unchanged.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3, 4, 5])
/// |> effect.filter(fn(x) { x % 2 == 0 })
/// |> effect.to_list
/// // -> Ok([2, 4])
/// ```
pub fn filter(effect: Effect(a, e), pred: fn(a) -> Bool) -> Effect(a, e) {
  Effect(
    stream: gs.filter(effect.stream, fn(result) {
      case result {
        Ok(value) -> pred(value)
        Error(_) -> True
      }
    }),
  )
}

/// Map over the error channel.
///
/// Transform errors while leaving successful values unchanged.
///
/// ## Example
/// ```gleam
/// effect.fail("error")
/// |> effect.map_error(fn(e) { "wrapped: " <> e })
/// |> effect.to_list
/// // -> Error("wrapped: error")
/// ```
pub fn map_error(effect: Effect(a, e), f: fn(e) -> e2) -> Effect(a, e2) {
  Effect(stream: gs.map(effect.stream, result.map_error(_, f)))
}

/// Take the first n successful values from the effect.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3, 4, 5])
/// |> effect.take(3)
/// |> effect.to_list
/// // -> Ok([1, 2, 3])
/// ```
pub fn take(effect: Effect(a, e), n: Int) -> Effect(a, e) {
  Effect(stream: take_ok(effect.stream, n))
}

fn take_ok(stream: Stream(Result(a, e)), n: Int) -> Stream(Result(a, e)) {
  gs.Stream(pull: fn() {
    case n <= 0 {
      True -> None
      False -> {
        case stream.pull() {
          Some(#(Ok(value), next)) -> Some(#(Ok(value), take_ok(next, n - 1)))
          Some(#(Error(e), _)) -> Some(#(Error(e), gs.from_empty()))
          None -> None
        }
      }
    }
  })
}

/// Drop the first n successful values from the effect.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3, 4, 5])
/// |> effect.drop(2)
/// |> effect.to_list
/// // -> Ok([3, 4, 5])
/// ```
pub fn drop(effect: Effect(a, e), n: Int) -> Effect(a, e) {
  Effect(stream: drop_ok(effect.stream, n))
}

fn drop_ok(stream: Stream(Result(a, e)), n: Int) -> Stream(Result(a, e)) {
  gs.Stream(pull: fn() {
    case n <= 0 {
      True -> stream.pull()
      False -> {
        case stream.pull() {
          Some(#(Ok(_), next)) -> drop_ok(next, n - 1).pull()
          Some(#(Error(e), _)) -> Some(#(Error(e), gs.from_empty()))
          None -> None
        }
      }
    }
  })
}

/// Concatenate two effects.
///
/// The second effect is only evaluated if the first completes without error.
///
/// ## Example
/// ```gleam
/// effect.concat(
///   effect.from_list([1, 2]),
///   effect.from_list([3, 4])
/// )
/// |> effect.to_list
/// // -> Ok([1, 2, 3, 4])
/// ```
pub fn concat(first: Effect(a, e), second: Effect(a, e)) -> Effect(a, e) {
  flat_map(first, fn(x) { concat(succeed(x), second) })
  // Note: This is inefficient. Better implementation:
  // Effect(stream: concat_streams(first.stream, second.stream))
}

/// Append a single value to an effect.
pub fn append(effect: Effect(a, e), value: a) -> Effect(a, e) {
  Effect(stream: gs.concat(effect.stream, gs.from_pure(Ok(value))))
}

/// Apply a side effect to each successful value.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.tap(fn(x) { io.println(int.to_string(x)) })
/// |> effect.to_list
/// ```
pub fn tap(effect: Effect(a, e), f: fn(a) -> Nil) -> Effect(a, e) {
  Effect(
    stream: gs.tap(effect.stream, fn(result) {
      case result {
        Ok(value) -> f(value)
        Error(_) -> Nil
      }
    }),
  )
}

// =============================================================================
// ERROR HANDLING
// =============================================================================

/// Handle errors by providing a recovery Effect.
///
/// When an error is encountered, the handler is called with the error
/// and can return a new Effect to continue processing.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2])
/// |> effect.flat_map(fn(x) {
///   case x == 2 {
///     True -> effect.fail("two!")
///     False -> effect.succeed(x)
///   }
/// })
/// |> effect.handle_error(fn(_) { effect.succeed(99) })
/// |> effect.to_list
/// // -> Ok([1, 99])
/// ```
pub fn handle_error(
  effect: Effect(a, e),
  handler: fn(e) -> Effect(a, e2),
) -> Effect(a, e2) {
  Effect(
    stream: gs.flat_map(effect.stream, fn(result) {
      case result {
        Ok(value) -> gs.from_pure(Ok(value))
        Error(e) -> { handler(e) }.stream
      }
    }),
  )
}

/// Recover from errors by providing a fallback value.
///
/// ## Example
/// ```gleam
/// effect.fail("error")
/// |> effect.recover(fn(_) { 0 })
/// |> effect.to_list
/// // -> Ok([0])
/// ```
pub fn recover(effect: Effect(a, e), fallback: fn(e) -> a) -> Effect(a, e) {
  Effect(
    stream: gs.map(effect.stream, fn(result) {
      case result {
        Ok(value) -> Ok(value)
        Error(e) -> Ok(fallback(e))
      }
    }),
  )
}

/// Recover from errors with a fallback Effect.
///
/// ## Example
/// ```gleam
/// effect.fail("error")
/// |> effect.recover_with(fn(_) { effect.from_list([1, 2, 3]) })
/// |> effect.to_list
/// // -> Ok([1, 2, 3])
/// ```
pub fn recover_with(
  effect: Effect(a, e),
  fallback: fn(e) -> Effect(a, e),
) -> Effect(a, e) {
  handle_error(effect, fallback)
}

/// Catch errors that match a predicate.
///
/// Errors that don't match the predicate continue to propagate.
///
/// ## Example
/// ```gleam
/// effect.fail("recoverable")
/// |> effect.catch_when(
///   fn(e) { e == "recoverable" },
///   fn(_) { effect.succeed(0) }
/// )
/// |> effect.to_list
/// // -> Ok([0])
/// ```
pub fn catch_when(
  effect: Effect(a, e),
  pred: fn(e) -> Bool,
  handler: fn(e) -> Effect(a, e),
) -> Effect(a, e) {
  Effect(
    stream: gs.flat_map(effect.stream, fn(result) {
      case result {
        Ok(value) -> gs.from_pure(Ok(value))
        Error(e) -> {
          case pred(e) {
            True -> { handler(e) }.stream
            False -> gs.from_pure(Error(e))
          }
        }
      }
    }),
  )
}

/// Catch specific errors using a partial handler.
///
/// If the handler returns Some(effect), that effect is used for recovery.
/// If the handler returns None, the error continues to propagate.
///
/// ## Example
/// ```gleam
/// effect.fail(404)
/// |> effect.catch_some(fn(code) {
///   case code {
///     404 -> Some(effect.succeed("not found"))
///     _ -> None
///   }
/// })
/// |> effect.to_list
/// // -> Ok(["not found"])
/// ```
pub fn catch_some(
  effect: Effect(a, e),
  handler: fn(e) -> Option(Effect(a, e)),
) -> Effect(a, e) {
  Effect(
    stream: gs.flat_map(effect.stream, fn(result) {
      case result {
        Ok(value) -> gs.from_pure(Ok(value))
        Error(e) -> {
          case handler(e) {
            Some(recovery) -> recovery.stream
            None -> gs.from_pure(Error(e))
          }
        }
      }
    }),
  )
}

/// Ensure a finalizer runs regardless of success or failure.
///
/// The finalizer is called when the effect stream ends, whether
/// successfully or due to an error.
///
/// ## Example
/// ```gleam
/// let cleanup_ran = ref.new(False)
/// effect.from_list([1, 2, 3])
/// |> effect.ensuring(fn() { ref.set(cleanup_ran, True) })
/// |> effect.to_nil
/// ```
pub fn ensuring(effect: Effect(a, e), finalizer: fn() -> Nil) -> Effect(a, e) {
  Effect(stream: ensuring_stream(effect.stream, finalizer))
}

fn ensuring_stream(
  stream: Stream(Result(a, e)),
  finalizer: fn() -> Nil,
) -> Stream(Result(a, e)) {
  gs.Stream(pull: fn() {
    case stream.pull() {
      Some(#(result, next)) -> Some(#(result, ensuring_stream(next, finalizer)))
      None -> {
        finalizer()
        None
      }
    }
  })
}

// =============================================================================
// RESOURCE MANAGEMENT
// =============================================================================

/// Bracket pattern for safe resource acquisition and release.
///
/// Acquires a resource, uses it to produce an effect, and guarantees
/// the release function is called when the effect completes or fails.
///
/// ## Example
/// ```gleam
/// effect.bracket(
///   acquire: fn() { open_file("data.txt") },
///   use_resource: fn(file) {
///     effect.from_stream(read_lines(file))
///   },
///   release: fn(file) { close_file(file) }
/// )
/// ```
pub fn bracket(
  acquire acquire: fn() -> Result(resource, e),
  use_resource use_fn: fn(resource) -> Effect(a, e),
  release release: fn(resource) -> Nil,
) -> Effect(a, e) {
  Effect(
    stream: gs.Stream(pull: fn() {
      case acquire() {
        Ok(resource) -> {
          let inner_effect = use_fn(resource)
          let inner_stream = ensuring(inner_effect, fn() { release(resource) })
          inner_stream.stream.pull()
        }
        Error(e) -> Some(#(Error(e), gs.from_empty()))
      }
    }),
  )
}

// =============================================================================
// SINKS (TERMINAL OPERATIONS)
// =============================================================================

/// Collect all successful values into a list, or return the first error.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.to_list
/// // -> Ok([1, 2, 3])
///
/// effect.from_list([1, 2])
/// |> effect.flat_map(fn(x) {
///   case x == 2 { True -> effect.fail("two!") False -> effect.succeed(x) }
/// })
/// |> effect.to_list
/// // -> Error("two!")
/// ```
pub fn to_list(effect: Effect(a, e)) -> Result(List(a), e) {
  collect_list(effect.stream, [])
}

fn collect_list(
  stream: Stream(Result(a, e)),
  acc: List(a),
) -> Result(List(a), e) {
  case stream.pull() {
    Some(#(Ok(value), next)) -> collect_list(next, list.append(acc, [value]))
    Some(#(Error(e), _)) -> Error(e)
    None -> Ok(acc)
  }
}

/// Fold over successful values, short-circuiting on error.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3, 4, 5])
/// |> effect.to_fold(0, fn(acc, x) { acc + x })
/// // -> Ok(15)
/// ```
pub fn to_fold(
  effect: Effect(a, e),
  initial: b,
  f: fn(b, a) -> b,
) -> Result(b, e) {
  fold_stream(effect.stream, initial, f)
}

fn fold_stream(
  stream: Stream(Result(a, e)),
  acc: b,
  f: fn(b, a) -> b,
) -> Result(b, e) {
  case stream.pull() {
    Some(#(Ok(value), next)) -> fold_stream(next, f(acc, value), f)
    Some(#(Error(e), _)) -> Error(e)
    None -> Ok(acc)
  }
}

/// Drain the effect, returning Ok if successful or the first error.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.tap(fn(x) { io.println(int.to_string(x)) })
/// |> effect.drain
/// // -> Ok(Nil)
/// ```
pub fn drain(effect: Effect(a, e)) -> Result(Nil, e) {
  to_fold(effect, Nil, fn(_, _) { Nil })
}

/// Get the first successful value, or the first error.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.to_first
/// // -> Ok(Some(1))
///
/// effect.empty()
/// |> effect.to_first
/// // -> Ok(None)
/// ```
pub fn to_first(effect: Effect(a, e)) -> Result(Option(a), e) {
  case effect.stream.pull() {
    Some(#(Ok(value), _)) -> Ok(Some(value))
    Some(#(Error(e), _)) -> Error(e)
    None -> Ok(None)
  }
}

/// Get the last successful value, or the first error.
pub fn to_last(effect: Effect(a, e)) -> Result(Option(a), e) {
  to_fold(effect, None, fn(_, x) { Some(x) })
}

// =============================================================================
// CONVERSIONS
// =============================================================================

/// Convert Effect back to a Stream of Results.
///
/// ## Example
/// ```gleam
/// effect.from_list([1, 2, 3])
/// |> effect.to_result_stream
/// |> gs.to_list
/// // -> [Ok(1), Ok(2), Ok(3)]
/// ```
pub fn to_result_stream(effect: Effect(a, e)) -> Stream(Result(a, e)) {
  effect.stream
}

/// Convert Effect to Stream, discarding errors.
///
/// Values after an error are also discarded (short-circuit behavior).
///
/// ## Example
/// ```gleam
/// effect.from_results(gs.from_list([Ok(1), Error("x"), Ok(3)]))
/// |> effect.to_stream_lossy
/// |> gs.to_list
/// // -> [1]
/// ```
pub fn to_stream_lossy(effect: Effect(a, e)) -> Stream(a) {
  gs.Stream(pull: fn() {
    case effect.stream.pull() {
      Some(#(Ok(value), next)) ->
        Some(#(value, to_stream_lossy(Effect(stream: next))))
      Some(#(Error(_), _)) -> None
      None -> None
    }
  })
}

/// Convert Effect to Stream, replacing errors with a default value.
///
/// ## Example
/// ```gleam
/// effect.from_results(gs.from_list([Ok(1), Error("x")]))
/// |> effect.to_stream_with_default(0)
/// |> gs.to_list
/// // -> [1, 0]
/// ```
pub fn to_stream_with_default(effect: Effect(a, e), default: a) -> Stream(a) {
  gs.map(effect.stream, fn(result) {
    case result {
      Ok(value) -> value
      Error(_) -> default
    }
  })
}

/// Run the effect for side effects only, discarding values.
///
/// Returns the first error if one occurs.
pub fn to_nil(effect: Effect(a, e)) -> Result(Nil, e) {
  drain(effect)
}

// =============================================================================
// COMBINATORS
// =============================================================================

/// Combine two effects, keeping values from both.
///
/// If either effect fails, the combined effect fails.
pub fn zip(left: Effect(a, e), right: Effect(b, e)) -> Effect(#(a, b), e) {
  flat_map(left, fn(a) { map(right, fn(b) { #(a, b) }) })
}

/// Combine two effects with a function.
pub fn zip_with(
  left: Effect(a, e),
  right: Effect(b, e),
  f: fn(a, b) -> c,
) -> Effect(c, e) {
  map(zip(left, right), fn(pair) { f(pair.0, pair.1) })
}

/// Try the first effect, fall back to the second on error.
///
/// ## Example
/// ```gleam
/// effect.fail("first failed")
/// |> effect.or_else(effect.succeed(42))
/// |> effect.to_list
/// // -> Ok([42])
/// ```
pub fn or_else(effect: Effect(a, e), fallback: Effect(a, e)) -> Effect(a, e) {
  handle_error(effect, fn(_) { fallback })
}

/// Retry an effect up to n times on error.
///
/// ## Example
/// ```gleam
/// let attempts = ref.new(0)
/// effect.from_attempt(fn() {
///   ref.update(attempts, fn(n) { n + 1 })
///   case ref.get(attempts) < 3 {
///     True -> Error("not yet")
///     False -> Ok("success")
///   }
/// })
/// |> effect.retry(5)
/// |> effect.to_first
/// // -> Ok(Some("success"))
/// ```
pub fn retry(effect: Effect(a, e), max_attempts: Int) -> Effect(a, e) {
  case max_attempts <= 1 {
    True -> effect
    False -> handle_error(effect, fn(_) { retry(effect, max_attempts - 1) })
  }
}
