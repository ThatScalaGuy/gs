import gleam/bit_array
import gleam/list
import gleeunit/should
import gs
import gs/text

pub fn text_utf8_decode_test() {
  let stream =
    ["hello", " ", "世界"]
    |> list.map(bit_array.from_string)
    |> gs.from_list

  stream
  |> text.utf8_decode
  |> gs.to_list
  |> should.equal([Ok("hello"), Ok(" "), Ok("世界")])
}

pub fn text_utf8_encode_test() {
  gs.from_list(["alpha", "β"])
  |> text.utf8_encode
  |> gs.map(bit_array.to_string)
  |> gs.to_list
  |> should.equal([Ok("alpha"), Ok("β")])
}

pub fn text_lines_simple_test() {
  gs.from_list(["foo\nbar", "\nbaz"])
  |> text.lines
  |> gs.to_list
  |> should.equal(["foo", "bar", "baz"])
}

pub fn text_lines_chunk_boundary_test() {
  gs.from_list(["foo", "bar\nba", "z\n", "qux"])
  |> text.lines
  |> gs.to_list
  |> should.equal(["foobar", "baz", "qux"])
}

pub fn text_split_multi_char_delimiter_test() {
  gs.from_list(["lorem--ips", "um--dol", "or"])
  |> text.split("--")
  |> gs.to_list
  |> should.equal(["lorem", "ipsum", "dolor"])
}

pub fn text_split_empty_string_test() {
  gs.from_list([""])
  |> text.split(",")
  |> gs.to_list
  |> should.equal([])
}

pub fn text_split_consecutive_delimiters_test() {
  gs.from_list([",,a,,b,,"])
  |> text.split(",")
  |> gs.to_list
  |> should.equal(["a", "b"])
}

pub fn text_split_starts_with_delimiter_test() {
  gs.from_list([",foo,bar"])
  |> text.split(",")
  |> gs.to_list
  |> should.equal(["foo", "bar"])
}

pub fn text_split_ends_with_delimiter_test() {
  gs.from_list(["foo,bar,"])
  |> text.split(",")
  |> gs.to_list
  |> should.equal(["foo", "bar"])
}
