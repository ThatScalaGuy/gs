import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

pub type Message(a) {
  Push(Subject(Bool), a)
  Pop(Subject(Option(a)))
  Peek(Subject(Option(a)))
  Size(Subject(Int))
}

type State(a) {
  State(items: List(a), current_size: Int, max_size: Int)
}

pub fn start(max_size: Int) {
  actor.start(
    State(items: [], current_size: 0, max_size: max_size),
    handle_message,
  )
}

fn handle_message(
  msg: Message(a),
  state: State(a),
) -> actor.Next(Message(a), State(a)) {
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
