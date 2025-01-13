import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

pub type Message(a, b) {
  Dispatch(Subject(Bool), a)
  GetResult(Subject(b))
}

type State(b) {
  State(result: Option(b))
}

pub fn start(f: fn(a) -> b) {
  actor.start(State(result: None), handle_message(f))
}

fn handle_message(f: fn(a) -> b) {
  fn(msg: Message(a, b), state: State(b)) -> actor.Next(Message(a, b), State(b)) {
    case msg {
      Dispatch(reply_with, item) -> {
        process.send(reply_with, True)
        actor.continue(State(result: Some(f(item))))
      }

      GetResult(reply_with) -> {
        case state.result {
          Some(result) -> {
            process.send(reply_with, result)
            actor.Stop(process.Normal)
          }
          None -> {
            actor.continue(state)
          }
        }
      }
    }
  }
}
