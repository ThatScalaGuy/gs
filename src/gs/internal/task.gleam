import gleam/dynamic
import gleam/erlang/process
import gleam/erlang/reference

pub type Task(a) {
  Task(subject: process.Subject(a))
}

pub fn async(run: fn() -> a) -> Task(a) {
  async_for(process.self(), run)
}

pub fn async_for(owner: process.Pid, run: fn() -> a) -> Task(a) {
  let subject = new_subject_for(owner)

  process.spawn(fn() {
    let result = run()
    process.send(subject, result)
  })

  Task(subject: subject)
}

pub fn await_forever(task: Task(a)) -> a {
  process.receive_forever(task.subject)
}

pub fn spawn(run: fn() -> Nil) -> Nil {
  process.spawn(fn() { run() })
  Nil
}

fn new_subject_for(owner: process.Pid) -> process.Subject(a) {
  process.unsafely_create_subject(owner, reference_to_dynamic(reference.new()))
}

@external(erlang, "gleam_erlang_ffi", "identity")
fn reference_to_dynamic(reference: reference.Reference) -> dynamic.Dynamic
