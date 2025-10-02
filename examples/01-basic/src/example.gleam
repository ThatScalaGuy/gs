import gleam/io
import gleam/string
import gs.{filter, from_list, map, take, to_list}

pub fn main() {
  // Create a stream from a list
  let stream = [1, 2, 3, 4, 5] |> from_list

  // Transform the stream: multiply each element by 2
  let transformed_stream = stream |> map(fn(x) { x * 2 })

  // Filter the stream: keep only even numbers
  let filtered_stream = transformed_stream |> filter(fn(x) { x % 2 == 0 })

  // Take the first 3 elements
  let result_stream = filtered_stream |> take(3)

  // Collect the stream into a list and print it
  let result_list = result_stream |> to_list
  string.inspect(result_list)
  |> io.println
}
