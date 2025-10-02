/// Text utilities built on top of gs streams.

import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gs

/// Decode a stream of UTF-8 encoded bit arrays into a stream of results.
///
/// ## Example
/// ```gleam
/// let stream =
///   ["Hello", " 世界"]
///   |> list.map(bit_array.from_string)
///   |> gs.from_list
///
/// utf8_decode(stream)
/// |> gs.to_list
/// // -> [Ok("Hello"), Ok(" 世界")]
/// ```
pub fn utf8_decode(
  stream: gs.Stream(BitArray),
) -> gs.Stream(Result(String, Nil)) {
  gs.map(stream, bit_array.to_string)
}

/// Decode a stream of UTF-8 encoded bit arrays, dropping invalid chunks.
///
/// Invalid UTF-8 sequences are discarded, keeping successful results only.
///
/// ## Example
/// ```gleam
/// utf8_decode_drop(stream_of_bytes)
/// |> gs.to_list
/// // -> ["ok part", "another"]
/// ```
pub fn utf8_decode_drop(stream: gs.Stream(BitArray)) -> gs.Stream(String) {
  stream
  |> utf8_decode
  |> gs.flat_map(fn(result) {
    case result {
      Ok(value) -> gs.from_pure(value)
      Error(_) -> gs.from_empty()
    }
  })
}

/// Encode a stream of strings into UTF-8 bit arrays.
///
/// ## Example
/// ```gleam
/// gs.from_list(["One", "Two"])
/// |> utf8_encode
/// |> gs.map(bit_array.to_string)
/// |> gs.to_list
/// // -> [Ok("One"), Ok("Two")]
/// ```
pub fn utf8_encode(stream: gs.Stream(String)) -> gs.Stream(BitArray) {
  gs.map(stream, bit_array.from_string)
}

/// Split a stream of strings on the newline character, emitting one line at a
/// time. Trailing newline characters are discarded rather than producing empty
/// entries at the end of the stream.
///
/// ## Example
/// ```gleam
/// gs.from_list(["foo\nbar", "\nbaz"])
/// |> lines
/// |> gs.to_list
/// // -> ["foo", "bar", "baz"]
/// ```
pub fn lines(stream: gs.Stream(String)) -> gs.Stream(String) {
  split(stream, "\n")
}

/// Split a stream of strings on an arbitrary substring delimiter.
///
/// The delimiter may span across chunk boundaries. The final partial segment is
/// emitted if non-empty once the source stream ends.
///
/// ## Example
/// ```gleam
/// gs.from_list(["lorem|ips", "um|dolor"])
/// |> split("|")
/// |> gs.to_list
/// // -> ["lorem", "ipsum", "dolor"]
/// ```
pub fn split(stream: gs.Stream(String), delimiter: String) -> gs.Stream(String) {
  case delimiter {
    "" -> stream
    _ -> split_internal(stream, delimiter, "")
  }
}

fn split_internal(
  stream: gs.Stream(String),
  delimiter: String,
  buffer: String,
) -> gs.Stream(String) {
  gs.Stream(pull: fn() {
    case stream.pull() {
      None ->
        case buffer {
          "" -> None
          leftover -> Some(#(leftover, gs.from_empty()))
        }

      Some(#(chunk, next_stream)) -> {
        let combined = buffer <> chunk
        let parts = string.split(combined, on: delimiter)
        let reversed = list.reverse(parts)

        case reversed {
          [] -> split_internal(next_stream, delimiter, buffer).pull()

          [new_buffer, ..reversed_ready] -> {
            let ready =
              reversed_ready
              |> list.reverse
              |> list.filter(fn(segment) { segment != "" })

            case ready {
              [] -> split_internal(next_stream, delimiter, new_buffer).pull()

              [first, ..rest] -> {
                let tail_stream = case rest {
                  [] -> split_internal(next_stream, delimiter, new_buffer)
                  _ ->
                    gs.concat(
                      gs.from_list(rest),
                      split_internal(next_stream, delimiter, new_buffer),
                    )
                }

                Some(#(first, tail_stream))
              }
            }
          }
        }
      }
    }
  })
}
