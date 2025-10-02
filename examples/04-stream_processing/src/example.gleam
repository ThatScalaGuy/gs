import gleam/io
import gleam/string
import gs.{
  concat, debug, filter, from_list, map, take_while, to_fold, to_list, to_nil,
}

pub fn main() {
  // Create a stream from a list
  let stream1 = [1, 2, 3, 4, 5] |> from_list

  // Create another stream from a list
  let stream2 = [6, 7, 8, 9, 10] |> from_list

  // Concatenate the two streams
  let concatenated_stream = stream1 |> concat(stream2)

  // Transform the stream: add 1 to each element
  let transformed_stream = concatenated_stream |> map(fn(x) { x + 1 })

  // Filter the stream: keep only even numbers
  let filtered_stream = transformed_stream |> filter(fn(x) { x % 2 == 0 })

  // Take elements from the stream while they are less than 10
  let result_stream = filtered_stream |> take_while(fn(x) { x < 10 })

  // Collect the stream into a list and print it
  let result_list = result_stream |> to_list
  string.inspect(result_list)
  |> io.println

  // Print each element of the stream
  result_stream |> debug |> to_nil

  // Fold the stream into a single value (product)
  let product = result_stream |> to_fold(1, fn(acc, x) { acc * x })
  string.inspect(product)
  |> io.println
}
