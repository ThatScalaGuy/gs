# gs - Gleam Streams

[![Package Version](https://img.shields.io/hexpm/v/gs)](https://hex.pm/packages/gs)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gs/)

`gs` - A lightweight Gleam library that introduces the `Stream` type for handling lazy value sequences. The library offers comprehensive functionality for creating, transforming, and processing streams, enabling efficient manipulation of sequential data.

## Concept

A `Stream` consists of a _Source_ element that generates data, followed by zero or more _Pipe_ elements that transform the data, and concludes with a _Sink_ element that consumes the data to produce a result.

The _Source_ is a lazy data structure that represents a sequence of values. It enables on-demand evaluation, making it highly efficient for processing large or infinite data sets. The library includes several built-in sources, such as **from_list**, **from_range**, and **from_tick**, which all follow the naming convention of starting with **from\_**.

The _Pipe_ elements are functions that transform the data in the stream. They can be used to map, or filter the data, among other operations like executing side effects. The library provides a variety of built-in pipe functions, such as **map**, **filter**, and **take**, which can be combined to create complex data processing pipelines.

The _Sink_ is a function that processes data from a stream to generate a result. It can collect data into a list, subject or fold in a single value. Additionally, a Sink can terminate an infinite stream by consuming elements until a specific termination condition is met, such as **to_nil_error_terminated**.

## Installation

Add `gs` to your Gleam project:

```sh
gleam add gs
```

## Usage

Check out the `/examples` directory for sample implementations.
Further documentation can be found at <https://hexdocs.pm/gs>.

### Text utilities

Import `gs/text` for convenience helpers when working with textual data:

- `utf8_decode` / `utf8_encode` convert between `Stream(BitArray)` and `Stream(String)`.
- `utf8_decode_drop` removes invalid UTF-8 sequences while decoding.
- `lines` turns a chunked stream of strings into a stream of complete lines.
- `split` supports custom delimiters that may span chunk boundaries.

```gleam
import gs
import gs/text

gs.from_list(["foo\nbar", "\nbaz"])
|> text.lines
|> gs.to_list
// -> ["foo", "bar", "baz"]
```

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
