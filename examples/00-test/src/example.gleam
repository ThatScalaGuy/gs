import gleam/io
import gs

pub fn main() {
  // Create a stream from a list
  io.println("Starting")
  gs.from_tick(40)
  |> gs.tap(fn(i) {
    case i % 10_000 {
      0 -> io.debug(i)
      _ -> 0
    }
  })
  |> gs.take(10_000_000)
  |> gs.to_nil()
  io.println("Done")
}
