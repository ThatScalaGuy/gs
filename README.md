# gs - Gleam Streams

[![Package Version](https://img.shields.io/hexpm/v/gs)](https://hex.pm/packages/gs)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gs/)

`gs` is a lightweight Gleam library for working with streams of data. It provides a variety of functions for creating, transforming, and consuming streams, making it easy to perform local transformations on lists.

## Installation

Add `gs` to your Gleam project:

```sh
gleam add gs
```

## Usage

Here are some examples of how to use `gs`:

### Creating Streams

```gleam
import gs.{empty, pure, from_list, from_option, from_result}

let empty_stream = empty()
let single_value_stream = pure(42)
let list_stream = [1, 2, 3] |> from_list
let option_stream = Some(42) |> from_option
let result_stream = Ok(42) |> from_result
```

### Transforming Streams

```gleam
import gs.{repeat, repeat_eval, map, flat_map, filter, take, concat}

let repeated_stream = 42 |> repeat
let evaluated_stream = fn() { 42 } |> repeat_eval
let mapped_stream = repeated_stream |> map(fn(x) { x + 1 })
let flat_mapped_stream = repeated_stream |> flat_map(fn(x) { pure(x + 1) })
let filtered_stream = repeated_stream |> filter(fn(x) { x > 0 })
let taken_stream = repeated_stream |> take(5)
let concatenated_stream = pure(1) |> concat(pure(2))
```

### Consuming Streams

```gleam
import gs.{fold, to_list, println, debug}

let sum = repeated_stream |> take(5) |> fold(0, fn(acc, x) { acc + x })
let list = repeated_stream |> take(5) |> to_list
let printed_stream = pure("Hello, world!") |> println
let debugged_stream = pure(42) |> debug
```

### Advanced Usage

```gleam
import gs.{chunks, tap, zip, zip_with, zip_all, zip_all_with}

let chunked_stream = repeated_stream |> take(10) |> chunks(3)
let tapped_stream = repeated_stream |> tap(fn(x) { io.println(x) })
let zipped_stream = pure(1) |> zip(pure(2))
let zipped_with_stream = pure(1) |> zip_with(pure(2), fn(x, y) { x + y })
let zipped_all_stream = pure(1) |> zip_all(empty())
let zipped_all_with_stream = pure(1) |> zip_all_with(empty(), fn(x, y) { #(x, y) })
```

Further documentation can be found at <https://hexdocs.pm/gs>.

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
