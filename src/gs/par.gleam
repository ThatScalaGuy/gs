import gleam/list
import gleam/otp/task
import gs.{type Stream}

/// Experimental parallel map operation over a stream.
///
/// ## Examples
///
/// ```gleam
/// let numbers = gs.from_list([1, 2, 3, 4, 5])
/// let doubled = 
///   par_map(numbers, 
///     workers: 2, 
///     with: fn(x) { x * 2 }
///   )
/// // -> #[2, 4, 6, 8, 10]
/// ```
///
/// Warning: This is an experimental feature and should not be used in production!
pub fn par_map(
  stream: Stream(a),
  workers workers: Int,
  with mapper: fn(a) -> b,
) -> Stream(b) {
  stream
  |> gs.chunks(workers)
  |> gs.flat_map(fn(elms) {
    elms 
    |> list.map(fn(elm) { task.async(fn() { mapper(elm) }) })
    |> list.map(fn(t) { task.await_forever(t) })
    |> gs.from_list
  })
}
