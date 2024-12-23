@external(erlang, "os", "system_time")
pub fn timestamp() -> Int

@external(erlang, "timer", "sleep")
pub fn sleep(_: Int) -> Nil
