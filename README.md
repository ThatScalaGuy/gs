# gs - Gleam Streams

[![Package Version](https://img.shields.io/hexpm/v/gs)](https://hex.pm/packages/gs)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gs/)

`gs` - A lightweight Gleam library that introduces the `Stream` type for handling lazy value sequences. The library offers comprehensive functionality for creating, transforming, and processing streams, enabling efficient manipulation of sequential data.

## Concept

A `Stream` consists of a *Source* element that generates data, followed by zero or more *Pipe* elements that transform the data, and concludes with a *Sink* element that consumes the data to produce a result.

The *Source* is a lazy data structure that represents a sequence of values. It enables on-demand evaluation, making it highly efficient for processing large or infinite data sets. The library includes several built-in sources, such as **from_list**, **from_range**, and **from_tick**, which all follow the naming convention of starting with **from_**.

The *Pipe* elements are functions that transform the data in the stream. They can be used to map, or filter the data, among other operations like executing side effects. The library provides a variety of built-in pipe functions, such as **map**, **filter**, and **take**, which can be combined to create complex data processing pipelines.

The *Sink* is a function that processes data from a stream to generate a result. It can collect data into a list, subject or fold in a single value. Additionally, a Sink can terminate an infinite stream by consuming elements until a specific termination condition is met, such as **to_nil_error_terminated**.

## Installation

Add `gs` to your Gleam project:

```sh
gleam add gs
```

## Usage

Check out the `/examples` directory for sample implementations.
Further documentation can be found at <https://hexdocs.pm/gs>.

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
