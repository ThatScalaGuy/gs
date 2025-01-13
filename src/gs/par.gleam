import gleam/erlang/process
import gs.{type Stream}
import gs/internal/par_map_actor

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
  |> gs.map(fn(ele) {
    let assert Ok(pid) = par_map_actor.start(mapper)
    process.call_forever(pid, fn(s) { par_map_actor.Dispatch(s, ele) })
    pid
  })
  |> gs.buffer(workers, gs.Wait)
  |> gs.map(fn(pid) { process.call_forever(pid, par_map_actor.GetResult) })
}
