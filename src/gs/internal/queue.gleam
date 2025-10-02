import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

pub type Message(a) {
  Push(process.Subject(Bool), a)
  Pop(process.Subject(Option(a)))
  Peek(process.Subject(Option(a)))
  Size(process.Subject(Int))
}

type State(a) {
  State(items: List(a), current_size: Int, max_size: Int)
}

pub fn start(
  max_size: Int,
) -> Result(process.Subject(Message(a)), actor.StartError) {
  actor.new(State(items: [], current_size: 0, max_size: max_size))
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn handle_message(
  state: State(a),
  msg: Message(a),
) -> actor.Next(State(a), Message(a)) {
  case msg {
    Push(reply_with, item) -> {
      case state.current_size < state.max_size {
        True -> {
          process.send(reply_with, True)
          actor.continue(
            State(
              ..state,
              current_size: state.current_size + 1,
              items: list.append(state.items, [item]),
            ),
          )
        }
        False -> {
          process.send(reply_with, False)
          actor.continue(state)
        }
      }
    }

    Pop(reply_with) -> {
      case state.items {
        [] -> {
          process.send(reply_with, None)
          actor.continue(state)
        }
        [first, ..rest] -> {
          process.send(reply_with, Some(first))
          actor.continue(
            State(..state, current_size: state.current_size - 1, items: rest),
          )
        }
      }
    }

    Peek(reply_with) -> {
      case state.items {
        [] -> process.send(reply_with, None)
        [first, ..] -> process.send(reply_with, Some(first))
      }
      actor.continue(state)
    }

    Size(reply_with) -> {
      process.send(reply_with, state.current_size)
      actor.continue(state)
    }
  }
}
