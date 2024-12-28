# gs - Gleam Streams

[![Package Version](https://img.shields.io/hexpm/v/gs)](https://hex.pm/packages/gs)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gs/)

`gs` - A lightweight Gleam library that introduces the `Stream` type for handling lazy value sequences. The library offers comprehensive functionality for creating, transforming, and processing streams, enabling efficient manipulation of sequential data.

## Concept

A `Stream` consists of a *Source* element that generates data, followed by zero or more *Pipe* elements that transform the data, and concludes with a *Sink* element that consumes the data to produce a result.

The *Source* is a lazy data structure that represents a sequence of values. It enables on-demand evaluation, making it highly efficient for processing large or infinite data sets. The library includes several built-in sources, such as **from_list**, **from_range**, and **from_tick**, which all follow the naming convention of starting with **from_**.

The *Pipe* elements are functions that transform the data in the stream. They can be used to map, or filter the data, among other operations like executing side effects. The library provides a variety of built-in pipe functions, such as **map**, **filter**, **fold**, and **take**, which can be combined to create complex data processing pipelines.
Except for the **fold** function, all pipe functions are lazy and only evaluate the data when needed.

The Sink is a function that processes data from a stream to generate a result. It can collect data into a list or subject. Additionally, a Sink can terminate an infinite stream by consuming elements until a specific termination condition is met, such as **to_nil_error_terminated**.

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
