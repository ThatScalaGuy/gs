import gleam/erlang
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/string
import gs
import gs/par

pub fn measure(label: String, f: fn() -> a) -> a {
  let start = erlang.system_time(erlang.Millisecond)
  let result = f()
  let end = erlang.system_time(erlang.Millisecond)
  let duration = end - start

  io.println(label <> " took " <> int.to_string(duration) <> "ms")

  result
}

fn new_point() -> #(Float, Float) {
  #(float.random(), float.random())
}

fn is_inside_circle(point: #(Float, Float)) -> Bool {
  let #(x, y) = point
  x *. x +. y *. y <=. 1.0
}

pub fn main() {
  let num = 10

  measure("Parallel", fn() {
    let a =
      gs.from_counter(1)
      |> par.par_map(6, fn(num) { #(num, new_point()) })
      |> gs.filter(fn(num_point) { is_inside_circle(num_point.1) })
      |> gs.count()
      |> gs.map(fn(e) { #(e.1, e.0.0) })
      |> par.par_map(6, fn(element) {
        4.0 *. int.to_float(element.0) /. int.to_float(element.1)
      })
      |> gs.take(num)
      |> gs.to_last

    string.inspect(a)
    |> io.println
  })

  measure("Sequential", fn() {
    let b =
      gs.from_counter(1)
      |> gs.map(fn(num) { #(num, new_point()) })
      |> gs.filter(fn(num_point) { is_inside_circle(num_point.1) })
      |> gs.count()
      |> gs.map(fn(e) { #(e.1, e.0.0) })
      |> gs.map(fn(element) {
        4.0 *. int.to_float(element.0) /. int.to_float(element.1)
      })
      |> gs.take(num)
      |> gs.to_last

    string.inspect(b)
    |> io.println
  })
}
