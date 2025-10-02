import gleam/io
import gleam/string
import gs.{
  debug, filter, from_list, map, take, to_fold, to_list, to_nil, zip_with,
}

pub fn main() {
  // Create a stream from a list
  let stream1 = [1, 2, 3, 4, 5] |> from_list

  // Create another stream from a list
  let stream2 = [10, 20, 30, 40, 50] |> from_list

  // Transform the first stream: multiply each element by 2
  let transformed_stream1 = stream1 |> map(fn(x) { x * 2 })

  // Filter the second stream: keep only elements greater than 25
  let filtered_stream2 = stream2 |> filter(fn(x) { x > 25 })

  // Zip the two streams together with addition
  let zipped_stream =
    transformed_stream1 |> zip_with(filtered_stream2, fn(x, y) { x + y })

  // Take the first 3 elements
  let result_stream = zipped_stream |> take(3)

  // Collect the stream into a list and print it
  let result_list = result_stream |> to_list
  string.inspect(result_list)
  |> io.println

  // Print each element of the stream
  result_stream |> debug |> to_nil

  // Fold the stream into a single value (sum)
  let sum = result_stream |> to_fold(0, fn(acc, x) { acc + x })
  string.inspect(sum)
  |> io.println
}
