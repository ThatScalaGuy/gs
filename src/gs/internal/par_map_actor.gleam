import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

pub type Message(a, b) {
  Dispatch(process.Subject(Bool), a)
  GetResult(process.Subject(b))
}

type State(b) {
  State(result: Option(b))
}

pub fn start(
  f: fn(a) -> b,
) -> Result(process.Subject(Message(a, b)), actor.StartError) {
  actor.new(State(result: None))
  |> actor.on_message(handle_message(f))
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle_message(f: fn(a) -> b) {
  fn(state: State(b), msg: Message(a, b)) -> actor.Next(State(b), Message(a, b)) {
    case msg {
      Dispatch(reply_with, item) -> {
        process.send(reply_with, True)
        actor.continue(State(result: Some(f(item))))
      }

      GetResult(reply_with) -> {
        case state.result {
          Some(result) -> {
            process.send(reply_with, result)
            actor.stop()
          }
          None -> {
            actor.continue(state)
          }
        }
      }
    }
  }
}
