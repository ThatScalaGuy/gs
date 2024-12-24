import gleam/erlang/process
import gleeunit
import gleeunit/should
import gs
import gs/par

pub fn main() {
  gleeunit.main()
}

pub fn par_map_test() {
  let stream =
    [1, 2, 3, 4, 5, 6]
    |> gs.from_list

  let result =
    stream
    |> par.par_map(6, fn(x) {
      process.sleep(1000)
      x * 2
    })
    |> gs.to_list

  result
  |> should.equal([2, 4, 6, 8, 10, 12])
}
