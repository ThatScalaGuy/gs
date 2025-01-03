import gleam/float
import gleam/int
import gs

fn new_point() -> #(Float, Float) {
  #(float.random(), float.random())
}

fn is_inside_circle(point: #(Float, Float)) -> Bool {
  let #(x, y) = point
  x *. x +. y *. y <=. 1.0
}

pub fn main() {
  gs.from_counter(1)
  |> gs.map(fn(num) { #(num, new_point()) })
  |> gs.filter(fn(num_point) { is_inside_circle(num_point.1) })
  |> gs.count()
  |> gs.map(fn(e) { #(e.1, e.0.0) })
  |> gs.map(fn(element) {
    4.0 *. int.to_float(element.0) /. int.to_float(element.1)
  })
  |> gs.debug()
  |> gs.to_nil()
}
