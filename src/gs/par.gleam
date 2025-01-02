import gleam/list
import gleam/otp/task
import gs.{type Stream}

/// Do not use it !!! EXPERIMENTAL !!!
pub fn par_map(stream: Stream(a), num_worker: Int, f: fn(a) -> b) -> Stream(b) {
  stream
  |> gs.chunks(num_worker)
  |> gs.flat_map(fn(elms) {
    elms
    |> list.map(fn(elm) { task.async(fn() { f(elm) }) })
    |> list.map(fn(t) { task.await_forever(t) })
    |> gs.from_list
  })
}
