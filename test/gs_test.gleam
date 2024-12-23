import gleam/io
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

pub fn to_option_test() {
  gs.from_list([1, 2, 3])
  |> gs.to_option
  |> should.equal(option.Some(1))

  gs.empty()
  |> gs.to_option
  |> should.equal(option.None)
}

pub fn try_recover_test() {
  gs.from_list([1, 2, 3])
  |> gs.map(fn(x) { Ok(x) })
  |> gs.try_recover(fn(_) { gs.pure(0) })
  |> gs.to_list
  |> should.equal([1, 2, 3])

  Error(5)
  |> gs.pure
  |> gs.try_recover(fn(error) { gs.pure(error + 1) })
  |> gs.to_list
  |> should.equal([6])
}

pub fn take_while_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.take_while(fn(x) { x < 4 })
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_list([1, 2, 3])
  |> gs.take_while(fn(_) { False })
  |> gs.to_list
  |> should.equal([])

  gs.from_list([1, 2, 3])
  |> gs.take_while(fn(_) { True })
  |> gs.to_list
  |> should.equal([1, 2, 3])
}

pub fn drop_test() {
  gs.from_list([1, 2, 3, 4, 5])
  |> gs.drop(2)
  |> gs.to_list
  |> should.equal([3, 4, 5])

  gs.from_list([1, 2])
  |> gs.drop(3)
  |> gs.to_list
  |> should.equal([])

  gs.from_list([1, 2, 3])
  |> gs.drop(0)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.empty()
  |> gs.drop(1)
  |> gs.to_list
  |> should.equal([])
}

pub fn intersperse_test() {
  gs.from_list([1, 2, 3])
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([1, 0, 2, 0, 3])

  gs.from_list([1])
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([1])

  gs.empty()
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([])

  gs.from_list([1, 2])
  |> gs.intersperse(0)
  |> gs.to_list
  |> should.equal([1, 0, 2])
}

pub fn from_counter_test() {
  gs.from_counter(1)
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_counter(0)
  |> gs.take(4)
  |> gs.to_list
  |> should.equal([0, 1, 2, 3])

  gs.from_counter(-2)
  |> gs.take(3)
  |> gs.to_list
  |> should.equal([-2, -1, 0])
}

pub fn from_range_test() {
  gs.from_range(1, 3)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_range(0, 0)
  |> gs.to_list
  |> should.equal([0])

  gs.from_range(3, 1)
  |> gs.to_list
  |> should.equal([])

  gs.from_range(-2, 1)
  |> gs.to_list
  |> should.equal([-2, -1, 0, 1])
}

pub fn from_range_exclusive_test() {
  gs.from_range_exclusive(1, 4)
  |> gs.to_list
  |> should.equal([1, 2, 3])

  gs.from_range_exclusive(0, 1)
  |> gs.to_list
  |> should.equal([0])

  gs.from_range_exclusive(3, 1)
  |> gs.to_list
  |> should.equal([])

  gs.from_range_exclusive(-2, 1)
  |> gs.to_list
  |> should.equal([-2, -1, 0])

  gs.from_range_exclusive(1, 1)
  |> gs.to_list
  |> should.equal([])
}

pub fn from_timestamp_eval_test() {
  gs.from_timestamp_eval()
  |> gs.take(2)
  |> gs.tap(fn(x) { io.debug(x) })
  |> gs.to_list
}
