import gleam/option
import gleeunit
import gleeunit/should
import gs

pub fn main() {
  gleeunit.main()
}

pub fn empty_test() {
  gs.empty()
  |> gs.to_list
  |> should.equal([])
}

pub fn pure_test() {
  gs.pure(42)
  |> gs.to_list
  |> should.equal([42])
}

pub fn from_list_test() {
  gs.from_list([1, 2, 3])
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_list([])
  |> gs.to_list
  |> should.equal([])
}

// pub fn from_bit_array_test() {
//   <<1, 2, 3>>
//   |> gs.from_bit_array
//   |> gs.to_list
//   |> should.equal([1, 2, 3])

//   <<>>
//   |> gs.from_bit_array
//   |> gs.to_list
//   |> should.equal([])
// }

pub fn from_option_test() {
  option.Some(42)
  |> gs.from_option
  |> gs.to_list
  |> should.equal([42])

  option.None
  |> gs.from_option
  |> gs.to_list
  |> should.equal([])
}

pub fn from_result_test() {
  Ok(42)
  |> gs.from_result
  |> gs.to_list
  |> should.equal([42])

  Error("error")
  |> gs.from_result
  |> gs.to_list
  |> should.equal([])
}

pub fn repeat_test() {
  gs.repeat(1)
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 1, 1])
}

pub fn map_test() {
  gs.from_list([1, 2, 3])
  |> gs.map(fn(x) { x * 2 })
  |> gs.to_list
  |> should.equal([2, 4, 6])
}

pub fn filter_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.filter(fn(x) { x % 2 == 0 })
  |> gs.to_list
  |> should.equal([2, 4])
}

pub fn take_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_list([1, 2])
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 2])

  gs.from_list([1, 2, 3])
  |> gs.take(0)
  |> gs.to_list
  |> should.equal([])
}

pub fn concat_test() {
  let s1 = gs.from_list([1, 2])
  let s2 = gs.from_list([3, 4])

  gs.concat(s1, s2)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4])

  gs.concat(gs.empty(), s2)
  |> gs.to_list
  |> should.equal([3, 4])

  gs.concat(s1, gs.empty())
  |> gs.to_list
  |> should.equal([1, 2])
}

pub fn chunks_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.chunks(2)
  |> gs.to_list
  |> should.equal([[1, 2], [3, 4], [5]])

  gs.from_list([1, 2, 3, 4])
  |> gs.chunks(2)
  |> gs.to_list
  |> should.equal([[1, 2], [3, 4]])

  gs.from_list([1, 2, 3])
  |> gs.chunks(0)
  |> gs.to_list
  |> should.equal([])
}

pub fn fold_test() {
  gs.from_list([1, 2, 3, 4])
  |> gs.fold(0, fn(acc, x) { acc + x })
  |> should.equal(10)

  gs.empty()
  |> gs.fold(42, fn(acc, x) { acc + x })
  |> should.equal(42)
}

pub fn zip_test() {
  let s1 = gs.from_list([1, 2, 3])
  let s2 = gs.from_list(["a", "b", "c"])
  gs.zip(s1, s2)
  |> gs.to_list
  |> should.equal([#(1, "a"), #(2, "b"), #(3, "c")])

  // Empty stream cases
  gs.zip(gs.empty(), s2)
  |> gs.to_list
  |> should.equal([])

  gs.zip(s1, gs.empty())
  |> gs.to_list
  |> should.equal([])
}

pub fn flat_map_test() {
  gs.from_list([1, 2])
  |> gs.flat_map(fn(x) { gs.pure(x * 2) })
  |> gs.to_list
  |> should.equal([2, 4])

  gs.from_list([[1, 2], [3, 4]])
  |> gs.flat_map(gs.from_list)
  |> gs.to_list
  |> should.equal([1, 2, 3, 4])

  gs.empty()
  |> gs.flat_map(gs.pure)
  |> gs.to_list
  |> should.equal([])
}

pub fn repeat_eval_test() {
  let counter =
    gs.repeat_eval(fn() { 1 })
    |> gs.take(3)
    |> gs.to_list

  should.equal(counter, [1, 1, 1])
}

pub fn zip_with_test() {
  let s1 = gs.from_list([1, 2, 3])
  let s2 = gs.from_list([4, 5, 6])
  gs.zip_with(s1, s2, fn(x, y) { x + y })
  |> gs.to_list
  |> should.equal([5, 7, 9])
}

pub fn to_nil_test() {
  gs.from_list([1, 2, 3])
  |> gs.to_nil
  |> should.equal(Nil)
}
