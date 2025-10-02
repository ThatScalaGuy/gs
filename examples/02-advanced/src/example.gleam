import gleam/io
import gleam/string
import gs.{debug, from_repeat, take, to_list, to_nil, zip_with}

pub fn main() {
  // Create two streams: one repeating 1 and another repeating 2
  let stream1 = 1 |> from_repeat
  let stream2 = 2 |> from_repeat

  // Zip the two streams together with addition
  let zipped_stream = stream1 |> zip_with(stream2, fn(x, y) { x + y })

  // Take the first 5 elements
  let result_stream = zipped_stream |> take(5)

  // Collect the stream into a list and print it
  let result_list = result_stream |> to_list
  string.inspect(result_list)
  |> io.println

  // Print each element of the stream
  result_stream |> debug |> to_nil
}
