import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}

/// A stream of values of type `a`.
pub type Stream(a) {
  Stream(pull: fn() -> Option(#(a, Stream(a))))
}

/// Creates an empty stream.
/// 
/// Example:
/// ```gleam
/// let stream = empty()
/// ```
pub fn empty() -> Stream(a) {
  Stream(pull: fn() { None })
}

/// Creates a stream with a single value.
/// 
/// Example:
/// ```gleam
/// let stream = pure(42)
/// ```
pub fn pure(value: a) -> Stream(a) {
  Stream(pull: fn() { Some(#(value, empty())) })
}

/// Creates a stream from a list of items.
/// 
/// Example:
/// ```gleam
/// [1, 2, 3] |> from_list
/// ```
pub fn from_list(items: List(a)) -> Stream(a) {
  case items {
    [] -> empty()
    [head, ..tail] -> Stream(pull: fn() { Some(#(head, from_list(tail))) })
  }
}

/// Creates a stream from an option.
/// 
/// Example:
/// ```gleam
/// Some(42) |> from_option
/// ```
pub fn from_option(option: Option(a)) -> Stream(a) {
  case option {
    Some(value) -> pure(value)
    None -> empty()
  }
}

/// Creates a stream from a result.
/// 
/// Example:
/// ```gleam
/// Ok(42) |> from_result
/// ```
pub fn from_result(result: Result(a, _)) -> Stream(a) {
  case result {
    Ok(value) -> pure(value)
    Error(_) -> empty()
  }
}

// pub fn from_bit_array(bits: BitArray) -> Stream(Int) {
//   Stream(pull: fn() {
//     case bits {
//       <<0 as b:size(8), rest:bytes>> -> Some(#(b, from_bit_array(rest)))
//       _ -> None
//     }
//   })
// }

/// Repeats a value indefinitely in a stream.
/// 
/// Example:
/// ```gleam
/// 42 |> repeat
/// ```
pub fn repeat(value: a) -> Stream(a) {
  Stream(pull: fn() { Some(#(value, repeat(value))) })
}

/// Repeats the result of a function indefinitely in a stream.
/// 
/// Example:
/// ```gleam
/// fn() { 42 } |> repeat_eval
/// ```
pub fn repeat_eval(f: fn() -> a) -> Stream(a) {
  Stream(pull: fn() { Some(#(f(), repeat_eval(f))) })
}

/// Maps a function over a stream.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> map(fn(x) { x + 1 })
/// ```
pub fn map(stream: Stream(a), f: fn(a) -> b) -> Stream(b) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> Some(#(f(value), map(next, f)))
      None -> None
    }
  })
}

/// Flat maps a function over a stream.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> flat_map(fn(x) { pure(x + 1) })
/// ```
pub fn flat_map(stream: Stream(a), f: fn(a) -> Stream(b)) -> Stream(b) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> concat(f(value), flat_map(next, f)).pull()
      None -> None
    }
  })
}

/// Filters a stream based on a predicate.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> filter(fn(x) { x > 0 })
/// ```
pub fn filter(stream: Stream(a), pred: fn(a) -> Bool) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) ->
        case pred(value) {
          True -> Some(#(value, filter(next, pred)))
          False -> filter(next, pred).pull()
        }
      None -> None
    }
  })
}

/// Takes the first `n` elements from a stream.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> take(5)
/// ```
pub fn take(stream: Stream(a), n: Int) -> Stream(a) {
  case n <= 0 {
    True -> empty()
    False ->
      Stream(pull: fn() {
        case stream.pull() {
          Some(#(value, next)) -> Some(#(value, take(next, n - 1)))
          None -> None
        }
      })
  }
}

/// Concatenates two streams.
/// 
/// Example:
/// ```gleam
/// pure(1) |> concat(pure(2))
/// ```
pub fn concat(first: Stream(a), second: Stream(a)) -> Stream(a) {
  Stream(pull: fn() {
    case first.pull() {
      Some(#(value, next)) -> Some(#(value, concat(next, second)))
      None -> second.pull()
    }
  })
}

/// Folds a stream into a single value.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> take(5) |> fold(0, fn(acc, x) { acc + x })
/// ```
pub fn fold(stream: Stream(a), initial: b, f: fn(b, a) -> b) -> b {
  case stream.pull() {
    Some(#(value, next)) -> fold(next, f(initial, value), f)
    None -> initial
  }
}

/// Collects a stream into a list.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> take(5) |> to_list
/// ```
pub fn to_list(stream: Stream(a)) -> List(a) {
  fold(stream, [], fn(acc, x) { list.append(acc, [x]) })
}

/// Collects a stream into a Nothing.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> take(5) |> to_nil
/// ```
pub fn to_nil(stream: Stream(a)) -> Nil {
  fold(stream, Nil, fn(_, _) { Nil })
}

/// Creates a stream that emits chunks of a given size.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> take(10) |> chunks(3)
/// ```
pub fn chunks(stream: Stream(a), size: Int) -> Stream(List(a)) {
  case size <= 0 {
    True -> empty()
    False ->
      Stream(pull: fn() {
        case take_chunk(stream, size, []) {
          Some(#(chunk, rest)) -> Some(#(chunk, chunks(rest, size)))
          None -> None
        }
      })
  }
}

fn take_chunk(
  stream: Stream(a),
  size: Int,
  acc: List(a),
) -> Option(#(List(a), Stream(a))) {
  case size == list.length(acc) {
    True -> Some(#(list.reverse(acc), stream))
    False ->
      case stream.pull() {
        Some(#(value, next)) -> take_chunk(next, size, [value, ..acc])
        None ->
          case acc {
            [] -> None
            _ -> Some(#(list.reverse(acc), empty()))
          }
      }
  }
}

/// Applies a function to each element of a stream for side effects.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> tap(fn(x) { io.println(x) })
/// ```
pub fn tap(stream: Stream(a), f: fn(a) -> b) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> {
        f(value)
        Some(#(value, tap(next, f)))
      }
      None -> None
    }
  })
}

/// Zips two streams together.
/// 
/// Example:
/// ```gleam
/// pure(1) |> zip(pure(2))
/// ```
pub fn zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) -> Some(#(#(v1, v2), zip(next1, next2)))
          None -> None
        }
      None -> None
    }
  })
}

/// Zips two streams together with a function.
/// 
/// Example:
/// ```gleam
/// pure(1) |> zip_with(pure(2), fn(x, y) { x + y })
/// ```
pub fn zip_with(
  left: Stream(a),
  right: Stream(b),
  f: fn(a, b) -> c,
) -> Stream(c) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) -> Some(#(f(v1, v2), zip_with(next1, next2, f)))
          None -> None
        }
      None -> None
    }
  })
}

/// Zips two streams together, filling with `None` when one stream ends.
/// 
/// Example:
/// ```gleam
/// pure(1) |> zip_all(empty())
/// ```
pub fn zip_all(
  left: Stream(a),
  right: Stream(b),
) -> Stream(Option(#(Option(a), Option(b)))) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(Some(#(Some(v1), Some(v2))), zip_all(next1, next2)))
          None -> Some(#(Some(#(Some(v1), None)), zip_all(next1, empty())))
        }
      None ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(Some(#(None, Some(v2))), zip_all(empty(), next2)))
          None -> None
        }
    }
  })
}

/// Zips two streams together with a function, filling with `None` when one stream ends.
/// 
/// Example:
/// ```gleam
/// pure(1) |> zip_all_with(empty(), fn(x, y) { #(x, y) })
/// ```
pub fn zip_all_with(
  left: Stream(a),
  right: Stream(b),
  f: fn(Option(a), Option(b)) -> c,
) -> Stream(c) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(f(Some(v1), Some(v2)), zip_all_with(next1, next2, f)))
          None -> Some(#(f(Some(v1), None), zip_all_with(next1, empty(), f)))
        }
      None ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(f(None, Some(v2)), zip_all_with(empty(), next2, f)))
          None -> None
        }
    }
  })
}

/// Prints each element of a stream to the console.
/// 
/// Example:
/// ```gleam
/// pure("Hello, world!") |> println
/// ```
pub fn println(stream: Stream(String)) -> Stream(String) {
  tap(stream, fn(x) { io.println(x) })
}

/// Logs each element of a stream for debugging.
/// 
/// Example:
/// ```gleam
/// pure(42) |> debug
/// ```
pub fn debug(stream: Stream(a)) -> Stream(a) {
  tap(stream, fn(x) { io.debug(x) })
}
