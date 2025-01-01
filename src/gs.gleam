import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/task
import gleam/set.{type Set}
import gs/internal/utils

/// A Stream represents a lazy, pull-based sequence of elements.
/// Each element is computed only when requested, making it memory efficient
/// for large or infinite sequences.
///
/// Streams operate by "pulling" one element at a time:
///
/// ```
///  [Source] --> [Element 1] --> [Element 2] --> [Element 3] --> None
///                  ^              ^              ^
///                  |              |              |
///             Pull when      Pull when      Pull when 
///              needed         needed         needed
/// ```
///
/// Key characteristics:
/// - Pull-based: Elements are computed on demand
/// - Sequential: Only one element is processed at a time
/// - Lazy: Elements are not computed until requested
/// - Finite: Stream ends when None is returned
///
pub type Stream(a) {
  Stream(pull: fn() -> Option(#(a, Stream(a))))
}

/// Creates a new empty stream.
/// 
/// The stream will yield nothing and terminate immediately.
/// 
/// ## Example
/// ```gleam
/// let empty_stream = from_empty()
/// list.from_stream(empty_stream) // -> []
/// ```
/// 
/// ## Visualization
/// ```
/// from_empty() -> |
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to use
/// - When you need a stream that yields no elements
/// - As a base case for recursive stream operations
/// - When implementing stream operations that might need to return an empty result
/// - As a neutral element in stream concatenation operations
/// 
/// ## Description
/// The `from_empty` function creates a stream that immediately terminates without
/// yielding any values. This is useful as a base case in recursive operations,
/// when implementing stream combinators, or when you need to represent the absence
/// of values in a streaming context. The empty stream is analogous to an empty
/// list but in a lazy evaluation context.
pub fn from_empty() -> Stream(a) {
  Stream(pull: fn() { None })
}

/// Creates a new single-element stream from a given value.
/// 
/// ## Example
/// ```gleam
/// > 42 |> from_pure |> to_list
/// [42]
/// ```
/// 
/// ## Visual Representation
/// ```
/// 42 |> from_pure
/// 
///     +----+
///  -->| 42 |-->|
///     +----+
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When you need to create a stream with exactly one element
/// - When converting a single value into a stream
/// - As a building block for more complex stream operations
/// - When implementing monadic operations that require lifting a value into a stream
/// 
/// ## Description
/// The `from_pure` function creates a stream that yields exactly one value and then
/// terminates. It "lifts" a single value into the stream context. The resulting
/// stream will emit the given value once and then immediately terminate. This is
/// one of the fundamental stream constructors and is often used in combination
/// with other stream operations.
pub fn from_pure(value: a) -> Stream(a) {
  Stream(pull: fn() { Some(#(value, from_empty())) })
}

/// Given a counter integer, constructs an infinite stream of integers starting from
/// the counter and incrementing by 1.
///
/// ## Example
///
/// ```gleam
/// > let numbers = from_counter(1)
/// > numbers |> take(3) |> to_list()
/// [1, 2, 3]
/// ```
///
/// ## Visual Representation
///
/// ```
/// from_counter(1)
///
///     +---+    +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 3 |--->| 4 |-->...
///     +---+    +---+    +---+    +---+
/// ```
///
/// ## Description
///
/// Creates an infinite stream that yields consecutive integers starting from
/// the provided counter value. Each element in the stream is exactly one greater
/// than the previous element. The stream never terminates and will continue
/// producing values indefinitely.
///
/// ## When to Use
///
/// - When you need a source of sequential integers
/// - For generating unique identifiers
/// - For creating test data with sequential values
/// - When implementing pagination or indexing
///
/// Note: Since this creates an infinite stream, make sure to use it with
/// functions like `take`, `take_while`, or other stream terminators to avoid
/// infinite loops.
pub fn from_counter(start: Int) -> Stream(Int) {
  Stream(pull: fn() { Some(#(start, from_counter(start + 1))) })
}

/// Creates a stream by repeatedly applying a state transition function.
/// 
/// ## Example
/// ```gleam
/// // Generate Fibonacci numbers using state transitions
/// from_state_eval(
///   #(0, 1),  // Initial state: (current, next)
///   fn(state) {
///     let #(current, next) = state
///     #(current, #(next, current + next))  // Return (value, new_state)
///   }
/// )
/// |> take(8)
/// |> to_list()
/// // Returns [0, 1, 1, 2, 3, 5, 8, 13]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Initial State: (0,1)
///     +---+    +---+    +---+    +---+
///  -->| 0 |--->| 1 |--->| 1 |--->| 2 |-->...
///     +---+    +---+    +---+    +---+
///       ↑        ↑        ↑        ↑
///    f(0,1)   f(1,1)   f(1,2)   f(2,3)
///       ↓        ↓        ↓        ↓
///    (1,1)    (1,2)    (2,3)    (3,5)
///    state    state    state    state
/// ```
/// Where:
/// - Each element is produced by applying f to the current state
/// - State transitions drive the stream generation
/// - f returns both the current value and the next state
/// 
/// ## When to Use
/// - When generating sequences that depend on previous values
/// - For implementing stateful stream transformations
/// - When creating mathematical sequences (Fibonacci, etc.)
/// - For simulating state machines or systems with evolving state
/// - When implementing iterative algorithms that maintain state
/// - For creating streams with complex progression rules
/// - When you need to track auxiliary information between elements
/// 
/// ## Description
/// The `from_state_eval` function creates a stream by repeatedly applying a
/// state transition function to an initial state. The function takes:
/// 1. An initial state value of type `b`
/// 2. A function `f` that takes the current state and returns a tuple of:
///    - The value to emit in the stream
///    - The next state to use
/// 
/// Each time the stream is pulled, the state transition function is applied
/// to the current state to produce both the next value and the next state.
/// This allows for sophisticated sequence generation where each element can
/// depend on the history of previous elements through the maintained state.
/// 
/// The function is particularly useful for:
/// - Generating mathematical sequences
/// - Implementing stateful transformations
/// - Creating streams with complex progression rules
/// - Simulating systems with evolving state
/// - Building iterative algorithms that require state
/// 
/// The resulting stream continues indefinitely, driven by the state transitions,
/// until terminated by other stream operations.
pub fn from_state_eval(current: b, f: fn(b) -> #(a, b)) -> Stream(a) {
  Stream(pull: fn() {
    let #(value, next_state) = f(current)
    Some(#(value, from_state_eval(next_state, f)))
  })
}

/// Creates a stream of integers from a start value (inclusive) to an end value (inclusive).
/// 
/// ## Example
/// 
/// ```gleam
/// > from_range(from: 1, to: 5) |> to_list()
/// [1, 2, 3, 4, 5]
/// ```
/// 
/// ## Visual Representation
/// ```
/// from_range(from: 1, to: 5)
/// 
///     +---+    +---+    +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 3 |--->| 4 |--->| 5 |-->|
///     +---+    +---+    +---+    +---+    +---+
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When you need a finite sequence of consecutive integers
/// - For iteration over a known range of numbers
/// - For generating bounded sequences
/// - When implementing pagination with fixed bounds
/// - For creating test data with sequential values in a range
/// 
/// ## Description
/// The `from_range` function creates a finite stream that yields consecutive integers
/// from the start value up to and including the end value. If the start value is
/// greater than the end value, an empty stream is returned. Each element in the
/// stream is exactly one greater than the previous element. The stream terminates
/// after yielding the end value.
pub fn from_range(from start: Int, to end: Int) -> Stream(Int) {
  case start <= end {
    True -> Stream(pull: fn() { Some(#(start, from_range(start + 1, end))) })
    False -> from_empty()
  }
}

/// Creates a stream of integers from a start value (inclusive) to an end value (exclusive).
/// 
/// ## Example
/// 
/// ```gleam
/// > from_range_exclusive(from: 1, until: 5) |> to_list()
/// [1, 2, 3, 4]
/// ```
/// 
/// ## Visual Representation
/// ```
/// from_range_exclusive(from: 1, until: 5)
/// 
///     +---+    +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 3 |--->| 4 |-->|
///     +---+    +---+    +---+    +---+
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When you need a finite sequence of consecutive integers excluding the end value
/// - For zero-based indexing scenarios (e.g., array indices)
/// - For loops where you want to exclude the upper bound
/// - When implementing slice operations
/// - For range operations that follow Python-style slicing conventions
/// 
/// ## Description
/// The `from_range_exclusive` function creates a finite stream that yields consecutive
/// integers from the start value up to, but not including, the end value. If the
/// start value is greater than or equal to the end value, an empty stream is returned.
/// Each element in the stream is exactly one greater than the previous element.
/// The stream terminates after yielding the last value before the end value.
pub fn from_range_exclusive(from start: Int, until end: Int) -> Stream(Int) {
  case start < end {
    True ->
      Stream(pull: fn() { Some(#(start, from_range_exclusive(start + 1, end))) })
    False -> from_empty()
  }
}

/// Creates a new stream from a list.
/// 
/// ## Example
/// ```gleam
/// > [1, 2, 3] |> from_list |> to_list
/// [1, 2, 3]
/// ```
/// 
/// ## Visual Representation
/// ```
/// [1, 2, 3] |> from_list
/// 
///     +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 3 |-->|
///     +---+    +---+    +---+
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When converting an existing list to a stream
/// - When you want to process list elements lazily
/// - When implementing stream operations that build from lists
/// - When you need to transform eager evaluation (lists) into lazy evaluation (streams)
/// 
/// ## Description
/// The `from_list` function creates a stream that yields each element from the input
/// list in order. The stream maintains the original order of elements and terminates
/// after yielding the last element. This is useful when you want to process list
/// elements one at a time.
pub fn from_list(items: List(a)) -> Stream(a) {
  case items {
    [] -> from_empty()
    [head, ..tail] -> Stream(pull: fn() { Some(#(head, from_list(tail))) })
  }
}

/// Creates a new stream from a dictionary.
/// 
/// ## Example
/// ```gleam
/// > dict.from_list([#("a", 1), #("b", 2), #("c", 3)])
/// |> from_dict
/// |> to_list
/// [#("a", 1), #("b", 2), #("c", 3)]
/// ```
/// 
/// ## Visual Representation
/// ```
/// dict.from_list([#("a", 1), #("b", 2), #("c", 3)]) |> from_dict
/// 
///     +--------+    +--------+    +--------+
///  -->|"a": 1  |--->|"b": 2  |--->|"c": 3  |-->|
///     +--------+    +--------+    +--------+
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When you need to process dictionary entries one at a time
/// - When converting a dictionary to a stream of key-value pairs
/// - When you want to lazily iterate over dictionary entries
/// - When implementing operations that need to work with dictionaries as streams
/// 
/// ## Description
/// The `from_dict` function creates a stream that yields each key-value pair from 
/// the input dictionary as a tuple. The stream preserves the dictionary's entries
/// but processes them lazily, one at a time. Each element in the resulting stream
/// is a tuple containing a key and its associated value. The stream terminates
/// after yielding all dictionary entries. This is particularly useful when you
/// want to process large dictionaries efficiently or when you need to chain
/// dictionary operations in a streaming context.
pub fn from_dict(dict: Dict(a, b)) -> Stream(#(a, b)) {
  from_list(dict |> dict.to_list)
}

/// Creates a new stream from an option value.
/// 
/// ## Example
/// ```gleam
/// > Some(42) |> from_option |> to_list
/// [42]
/// 
/// > None |> from_option |> to_list
/// []
/// ```
/// 
/// ## Visual Representation
/// ```
/// Some(42) |> from_option
/// 
///     +----+
///  -->| 42 |-->|
///     +----+
/// 
/// None |> from_option
/// 
///  -->|
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When converting an optional value into a stream
/// - When you want to handle presence/absence of a value in a streaming context
/// - As a building block for stream operations that may or may not have values
/// 
/// ## Description
/// The `from_option` function creates a stream from an Option value.
pub fn from_option(option: Option(a)) -> Stream(a) {
  case option {
    Some(value) -> from_pure(value)
    None -> from_empty()
  }
}

/// Creates a stream that emits a value every `delay_ms` milliseconds.
/// 
/// ## Example
/// 
/// ```gleam
/// > 1000 
/// |> from_tick
/// |> take(3)  
/// |> to_list
/// // Emits [0, 0, 0] with 1 second delay between each value
/// ```
/// 
/// ## Visual Representation
/// ```
/// from_tick(1000)
/// 
///     +---+    +---+    +---+    +---+
///  -->| 0 |-1s>| 0 |-1s>| 0 |-1s>| 0 |-->...
///     +---+    +---+    +---+    +---+
/// ```
/// Where `-1s>` represents a 1 second delay
/// 
/// ## When to Use
/// - When implementing polling mechanisms
/// - For creating periodic events or heartbeats
/// - When building timer-based functionality
/// - For implementing rate-limiting or throttling
/// - When simulating time-based events in testing
/// 
/// ## Description
/// The `from_tick` function creates an infinite stream that emits values at 
/// regular intervals specified by `delay_ms`. Each emission is accompanied by
/// a delay of `delay_ms` milliseconds. The stream emits the number of
/// milliseconds that were actually delayed beyond the expected interval
/// (usually 0 unless system load causes delays).
/// 
/// The function will panic if `delay_ms` is less than or equal to 0.
pub fn from_tick(delay_ms: Int) -> Stream(Int) {
  case delay_ms <= 0 {
    True -> panic as "delay_ms must be greater than 0"
    False -> from_tick_loop(delay_ms, 0)
  }
}

fn from_tick_loop(delay_ms: Int, last_tick: Int) -> Stream(Int) {
  Stream(pull: fn() {
    let now = utils.timestamp()
    let diff = now - last_tick
    case diff >= delay_ms {
      True -> Some(#(diff - delay_ms, from_tick_loop(delay_ms, now)))
      False -> {
        process.sleep(delay_ms - diff)
        Some(#(0, from_tick_loop(delay_ms, now)))
      }
    }
  })
}

/// Creates a new stream from a Result value.
/// 
/// ## Example
/// ```gleam
/// > Ok(42) |> from_result |> to_list
/// [42]
/// 
/// > Error("oops") |> from_result |> to_list
/// []
/// ```
/// 
/// ## Visual Representation
/// ```
/// Ok(42) |> from_result
/// 
///     +----+
///  -->| 42 |-->|
///     +----+
/// 
/// Error("oops") |> from_result
/// 
///  -->|
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When converting a Result value into a stream
/// - When handling computations that may fail in a streaming context
/// - When filtering out error cases from a sequence of operations
/// - When transforming error-handling code into data processing pipelines
/// - As a building block for stream operations that work with Results
/// 
/// ## Description
/// The `from_result` function creates a stream from a Result value. If the Result
/// is `Ok`, it creates a single-element stream containing the value. If the Result
/// is `Error`, it creates an empty stream. This is useful for handling operations
/// that may fail and converting them into a streaming context where errors are
/// simply filtered out. The error value is discarded, making this function
/// appropriate when you want to proceed with successful values only.
pub fn from_result(result: Result(a, _)) -> Stream(a) {
  case result {
    Ok(value) -> from_pure(value)
    Error(_) -> from_empty()
  }
}

// pub fn from_bit_array(bits: BitArray) -> Stream(Int) {
//   Stream(pull: fn() {
//     case bits {
//       <<0 as b:size(8), rest:bytes>> -> Some(#(b, from_bit_array(rest)))
//       _ -> None
//     }
//   })
// }

/// Creates an infinite stream that repeatedly yields the same value.
///
/// ## Example
/// ```gleam
/// > 42 |> from_repeat |> take(3) |> to_list
/// [42, 42, 42]
/// ```
///
/// ## Visual Representation
/// ```
/// 42 |> from_repeat
///
///     +----+    +----+    +----+    +----+
///  -->| 42 |--->| 42 |--->| 42 |--->| 42 |-->...
///     +----+    +----+    +----+    +----+
/// ```
///
/// ## When to Use
/// - When you need a constant stream of the same value
/// - For testing stream operations with consistent input
/// - When implementing backpressure mechanisms with default values
/// - For creating placeholder or dummy data streams
/// - When you need an infinite source of identical values
///
/// ## Description
/// The `from_repeat` function creates an infinite stream that yields the same
/// value indefinitely. Each time the stream is pulled, it produces the original
/// value and a new stream that will continue to produce the same value. This
/// creates an endless sequence of identical values, useful for testing, default
/// values, or as a building block for more complex stream operations. Since the
/// stream is infinite, it should typically be used with functions like `take`
/// or `take_while` to limit the number of values produced.
pub fn from_repeat(value: a) -> Stream(a) {
  Stream(pull: fn() { Some(#(value, from_repeat(value))) })
}

/// Creates an infinite stream that repeatedly evaluates a function to generate values.
/// 
/// ## Example
/// ```gleam
/// > fn() { utils.timestamp() }
/// |> from_repeat_eval
/// |> take(3)
/// |> to_list
/// // Emits [1705123456, 1705123457, 1705123458]  // Different timestamps
/// ```
/// 
/// ## Visual Representation
/// ```
/// from_repeat_eval(fn() { random() })
/// 
///     +-----+    +-----+    +-----+    +-----+
///  -->| 42  |--->| 17  |--->| 33  |--->| 89  |-->...
///     +-----+    +-----+    +-----+    +-----+
///       ↑          ↑          ↑          ↑
///    f() call  f() call  f() call  f() call
/// ```
/// Where each value is generated by a fresh call to the function
/// 
/// ## When to Use
/// - When you need a stream of dynamically generated values
/// - For creating streams of random numbers
/// - For testing with varying data
/// - When you need to encapsulate side-effects in a stream
/// - For creating streams that reflect changing system state
/// 
/// ## Description
/// The `from_repeat_eval` function creates an infinite stream that generates values
/// by repeatedly calling the provided function. Unlike `from_repeat` which produces
/// the same value repeatedly, this function evaluates the given function each time
/// a new value is needed, making it suitable for dynamic content generation.
/// Each pull of the stream results in a fresh call to the function, potentially
/// producing different values each time. The stream continues indefinitely and
/// should typically be used with functions like `take` or `take_while` to limit
/// the number of evaluations.
pub fn from_repeat_eval(f: fn() -> a) -> Stream(a) {
  Stream(pull: fn() { Some(#(f(), from_repeat_eval(f))) })
}

/// Creates an infinite stream of Unix timestamps that evaluates the current time on each pull.
/// 
/// ## Example
/// ```gleam
/// > from_timestamp_eval()
/// |> take(3)
/// |> to_list
/// // Emits [1705123456, 1705123457, 1705123458]  // Different timestamps
/// ```
/// 
/// ## Visual Representation
/// ```
/// from_timestamp_eval()
/// 
///     +---------+    +---------+    +---------+    +---------+
///  -->| 1705123 |--->| 1705124 |--->| 1705125 |--->| 1705126 |-->...
///     +---------+    +---------+    +---------+    +---------+
///          ↑              ↑              ↑              ↑
///     timestamp()    timestamp()    timestamp()    timestamp()
/// ```
/// Where each value is a fresh timestamp evaluation
/// 
/// ## When to Use
/// - When you need a stream of current timestamps
/// - For logging with temporal information
/// - When implementing time-based monitoring
/// - For creating time series data
/// - When measuring elapsed time between operations
/// 
/// ## Description
/// The `from_timestamp_eval` function creates an infinite stream that generates 
/// Unix timestamps. Unlike a static stream, this evaluates the current timestamp
/// each time a value is pulled, ensuring each emitted value reflects the actual
/// time at the moment of access. The stream continues indefinitely and should
/// typically be used with functions like `take` or `take_while` to limit the
/// number of evaluations.
pub fn from_timestamp_eval() -> Stream(Int) {
  Stream(pull: fn() { Some(#(utils.timestamp(), from_timestamp_eval())) })
}

/// Creates a stream from a process Subject that receives values of type Option(a).
/// 
/// ## Example
/// ```gleam
/// let subject = process.new_subject()
/// process.send(subject, Some(1))
/// process.send(subject, Some(2))
/// process.send(subject, None)
/// 
/// subject
/// |> from_subject
/// |> to_list
/// // -> [1, 2]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Subject --> Stream
/// 
///      +---+    +---+    
/// ---->| 1 |--->| 2 |---> None
///      +---+    +---+    
///        ↑        ↑         ↑
///    Some(1)  Some(2)    None
/// ```
/// Where messages flow from the Subject into the Stream until None is received
/// 
/// ## When to Use
/// - When converting process messages into a stream
/// - For handling asynchronous data sources
/// - When bridging between process-based and stream-based code
/// - For implementing pub/sub patterns with streams
/// - When you need to process messages sequentially
/// 
/// ## Description
/// The `from_subject` function creates a stream that yields values received from
/// a process Subject. It expects messages of type `Option(a)` where:
/// - `Some(value)` represents a value to be emitted by the stream
/// - `None` signals the end of the stream
/// 
/// The stream will continuously wait for messages until a `None` is received,
/// at which point it terminates. This makes it useful for converting
/// asynchronous message-based communication into a sequential stream
/// of values.
pub fn from_subject(subject: Subject(Option(a))) -> Stream(a) {
  Stream(pull: fn() {
    case process.receive_forever(subject) {
      Some(value) -> Some(#(value, from_subject(subject)))
      None -> None
    }
  })
}

/// Creates a stream from a process Subject that times out after a specified duration.
/// 
/// ## Example
/// ```gleam
/// let subject = process.new_subject()
/// 
/// // In another process
/// process.send(subject, 1)
/// process.send(subject, 2)
/// // Wait more than timeout...
/// process.send(subject, 3)
/// 
/// subject
/// |> from_subject_timeout(1000)
/// |> to_list
/// // -> [1, 2]  // 3 is not received due to timeout
/// ```
/// 
/// ## Visual Representation
/// ```
/// Subject --> Stream (with timeout)
/// 
///      +---+    +---+         +---+
/// ---->| 1 |--->| 2 |----X----| 3 |
///      +---+    +---+    |    +---+
///        ↑        ↑      |      ↑
///     0.1s     0.2s   1.0s    1.1s
///                      timeout
/// ```
/// Where 'X' represents the timeout point that terminates the stream
/// 
/// ## When to Use
/// - When processing messages with time constraints
/// - For implementing timeout-based protocols
/// - When handling potentially slow or unreliable message sources
/// - For graceful shutdown of stream processing
/// - When implementing time-bounded operations
/// - For preventing infinite waiting on message streams
/// 
/// ## Description
/// The `from_subject_timeout` function creates a stream that yields values received
/// from a process Subject, but will terminate if no message is received within the
/// specified timeout period (`timeout_ms`). Each message receipt resets the timeout
/// window. This is particularly useful for handling scenarios where message flow
/// might be interrupted or when you need to ensure timely processing of messages.
/// 
/// The stream will:
/// - Emit each received message as a stream element
/// - Wait up to `timeout_ms` milliseconds for each new message
/// - Terminate if no message is received within the timeout period
/// - Reset the timeout window after each successful message receipt
pub fn from_subject_timeout(subject: Subject(a), timeout_ms: Int) -> Stream(a) {
  Stream(pull: fn() {
    case process.receive(subject, timeout_ms) {
      Ok(value) -> Some(#(value, from_subject_timeout(subject, timeout_ms)))
      Error(Nil) -> None
    }
  })
}

/// Maps a function over a stream.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> map(fn(x) { x * 2 })
/// |> to_list()
/// [2, 4, 6, 8, 10]
/// ```
/// 
/// ## Visual Representation
/// ```
/// stream:    [1]-->[2]-->[3]-->[4]-->[5]-->|
///             |     |     |     |     |
///           f(x)   f(x)  f(x)  f(x)  f(x)
///             |     |     |     |     |
///             v     v     v     v     v
/// result:    [2]-->[4]-->[6]-->[8]-->[10]-->|
/// ```
/// Where `|` represents the end of the stream and `f(x)` is the mapping function
/// 
/// ## When to Use
/// - When transforming each element of a stream without changing the stream structure
/// - For data conversion or formatting
/// - When applying calculations to each element
/// - For type conversion operations
/// - When preparing data for further processing
/// - As a building block in larger stream processing pipelines
/// 
/// ## Description
/// The `map` function transforms a stream by applying a function to each element,
/// creating a new stream with the transformed values. The stream maintains its
/// original structure (length and order) while transforming the elements. The
/// mapping function is applied lazily - only when elements are pulled from the
/// resulting stream.
pub fn map(over stream: Stream(a), with f: fn(a) -> b) -> Stream(b) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> Some(#(f(value), map(next, f)))
      None -> None
    }
  })
}

/// Transforms each element into a stream and flattens all streams into a single stream.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 3)
/// |> flat_map(fn(x) { from_range(1, x) })
/// |> to_list()
/// [1, 1, 2, 1, 2, 3]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-------->[2]-------->[3]------->|
///          |           |           |
///          v           v           v
///         [1]-->|    [1,2]-->|   [1,2,3]-->|
///          |       |   |     |   |   |   |
///          v       v   v     v   v   v   v
/// Output: [1]---->[1]--[2]-->[1]--[2]--[3]-->|
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When you need to generate multiple elements from each input element
/// - For handling nested or hierarchical data structures
/// - When implementing tree traversal or graph algorithms
/// - For expanding or exploding single elements into sequences
/// - When working with relationships where one item maps to many items
/// - For implementing more complex stream transformations
/// 
/// ## Description
/// The `flat_map` function applies a transformation to each element of the input
/// stream, where the transformation produces a new stream for each element. These
/// resulting streams are then flattened into a single output stream. The function
/// processes elements lazily, only generating new streams as elements are requested
/// from the result stream.
/// 
/// Key characteristics:
/// - One-to-many transformation: Each input element can produce multiple output elements
/// - Preserves order: Elements from earlier streams appear before elements from later streams
/// - Lazy evaluation: Streams are only generated and flattened when needed
pub fn flat_map(over stream: Stream(a), with f: fn(a) -> Stream(b)) -> Stream(b) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> concat(f(value), flat_map(next, f)).pull()
      None -> None
    }
  })
}

/// Filters elements from a stream based on a predicate function.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> filter(fn(x) { x > 5 })
/// |> to_list()
/// [6, 7, 8, 9, 10]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->[7]-->[8]-->|
///          |     |     |     |     |     |     |     |
///        p(x)   p(x)  p(x)  p(x)  p(x)  p(x)  p(x)  p(x)
///          ×     ×     ×     ×     ×     ✓     ✓     ✓
///                                         |     |     |
///                                         v     v     v
/// Output: ------------------------------>[6]-->[7]-->[8]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `p(x)` is the predicate function
/// - `×` indicates the element was filtered out
/// - `✓` indicates the element passed the filter
/// 
/// ## When to Use
/// - When you need to remove unwanted elements from a stream
/// - For implementing search or query operations
/// - When validating or sanitizing data streams
/// - For extracting specific patterns or values
/// - When implementing business logic filters
/// - For data cleanup operations
/// 
/// ## Description
/// The `filter` function creates a new stream that only includes elements from
/// the input stream that satisfy the given predicate function. Elements are
/// processed lazily - the predicate is only evaluated when elements are pulled
/// from the resulting stream.
/// 
/// The function:
/// - Preserves the order of elements that pass the filter
/// - Skips elements that don't satisfy the predicate
/// - Processes elements lazily (on-demand)
/// - Returns an empty stream if no elements satisfy the predicate
pub fn filter(stream: Stream(a), keeping pred: fn(a) -> Bool) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) ->
        case pred(value) {
          True -> Some(#(value, filter(next, pred)))
          False -> filter(next, pred).pull()
        }
      None -> None
    }
  })
}

/// Finds the first element in a stream that satisfies a predicate and returns a stream containing only that element.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> find(fn(x) { x > 5 })
/// |> to_list()
/// [6]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->[7]-->[8]-->|
///          |     |     |     |     |     |     |     |
///        p(x)   p(x)  p(x)  p(x)  p(x)  p(x)  p(x)  p(x)
///          ×     ×     ×     ×     ×     ✓     -     -
///                                         |
///                                         v
/// Output: ------------------------------>[6]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `p(x)` is the predicate function
/// - `×` indicates the element did not match
/// - `✓` indicates the first matching element
/// - `-` indicates elements not evaluated
/// 
/// ## When to Use
/// - When searching for the first occurrence of an element meeting specific criteria
/// - For implementing early termination in stream processing
/// - When you need only the first matching element from a potentially large stream
/// - For implementing search functionality
/// - When validating the existence of elements meeting certain conditions
/// - To optimize performance by stopping processing after finding a match
/// 
/// ## Description
/// The `find` function creates a new stream that contains only the first element
/// from the input stream that satisfies the given predicate function. The function
/// processes elements lazily and stops as soon as a matching element is found,
/// making it efficient for large streams. If no element satisfies the predicate,
/// an empty stream is returned.
/// 
/// The function:
/// - Processes elements sequentially until a match is found
/// - Stops processing after finding the first match
/// - Returns a stream with at most one element
/// - Returns an empty stream if no elements match the predicate
pub fn find(stream: Stream(a), pred: fn(a) -> Bool) -> Stream(a) {
  stream |> filter(pred) |> take(1)
}

/// Drops (skips) the first `n` elements from a stream.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> drop(5)
/// |> to_list()
/// [6, 7, 8, 9, 10]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->[7]-->[8]-->|
///          ×     ×     ×     ×     ×     |     |     |
///                                        v     v     v
/// Output: ----------------------------->[6]-->[7]-->[8]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `×` indicates dropped elements
/// - Elements after the drop point flow through unchanged
/// 
/// ## When to Use
/// - When you want to skip a known number of elements at the start of a stream
/// - For implementing pagination (skipping the first n pages)
/// - When processing data streams where header elements should be ignored
/// - For removing initialization or warm-up data
/// - When implementing offset-based operations
/// - To synchronize streams by dropping initial mismatched elements
/// 
/// ## Description
/// The `drop` function creates a new stream that skips the first `n` elements
/// from the input stream and yields all remaining elements. The function processes
/// elements lazily - only advancing through the dropped elements when the resulting
/// stream is pulled. This makes it memory efficient as dropped elements are never
/// materialized.
/// 
/// The function:
/// - Preserves the order of remaining elements
/// - Processes dropped elements lazily
/// - Returns an empty stream if n is greater than the stream length
/// - Returns the original stream if n is 0 or negative
pub fn drop(stream: Stream(a), n: Int) -> Stream(a) {
  case n <= 0 {
    True -> stream
    False ->
      case stream.pull() {
        Some(#(_, next)) -> drop(next, n - 1)
        None -> from_empty()
      }
  }
}

/// Takes the first `n` elements from a stream.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> take(5)
/// |> to_list()
/// [1, 2, 3, 4, 5]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->[7]-->[8]-->|
///          |     |     |     |     |     ×     ×     ×
///          v     v     v     v     v
/// Output: [1]-->[2]-->[3]-->[4]-->[5]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `×` indicates elements that are not taken
/// - Elements before the take limit flow through unchanged
/// 
/// ## When to Use
/// - When you need to limit the number of elements from a potentially infinite stream
/// - For implementing pagination (taking the first n items)
/// - When sampling or previewing data from a large stream
/// - For testing with a subset of stream elements
/// - When implementing batched processing
/// - To prevent infinite processing of endless streams
/// 
/// ## Description
/// The `take` function creates a new stream containing only the first `n` elements
/// from the input stream. Once `n` elements have been yielded, the resulting stream
/// terminates, even if more elements are available in the input stream. This is
/// particularly useful when working with infinite streams or when you need to limit
/// the number of elements processed.
/// 
/// The function:
/// - Preserves the order of elements
/// - Processes elements lazily
/// - Returns less than n elements if the input stream is shorter
/// - Returns an empty stream if n is 0 or negative
pub fn take(stream: Stream(a), n: Int) -> Stream(a) {
  case n <= 0 {
    True -> from_empty()
    False ->
      Stream(pull: fn() {
        case stream.pull() {
          Some(#(value, next)) -> Some(#(value, take(next, n - 1)))
          None -> None
        }
      })
  }
}

/// Takes elements from a stream as long as they satisfy a predicate.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> take_while(fn(x) { x <= 5 })
/// |> to_list()
/// [1, 2, 3, 4, 5]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->[7]-->[8]-->|
///          |     |     |     |     |     ×     ×     ×
///        p(x)   p(x)  p(x)  p(x)  p(x)  p(x)
///          ✓     ✓     ✓     ✓     ✓     ×
///          v     v     v     v     v
/// Output: [1]-->[2]-->[3]-->[4]-->[5]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `p(x)` is the predicate function
/// - `✓` indicates the predicate returned True
/// - `×` indicates where the stream terminates (predicate returned False)
/// 
/// ## When to Use
/// - When you need to collect elements until a condition is no longer met
/// - For processing sequences until a terminating condition occurs
/// - When implementing range filters with dynamic end conditions
/// - For handling sorted data where you want elements until a threshold
/// - When processing time-series data until a specific event
/// - For implementing early termination based on element values
/// 
/// ## Description
/// The `take_while` function creates a new stream that yields elements from the
/// input stream as long as they satisfy the given predicate function. Once an
/// element is encountered that fails the predicate, the stream terminates
/// immediately, ignoring any remaining elements. This is particularly useful
/// when working with sorted data or when you need to process elements until
/// a certain condition is met.
/// 
/// The function:
/// - Processes elements lazily
/// - Preserves the order of elements
/// - Stops immediately when the predicate returns False
/// - Returns an empty stream if the first element fails the predicate
/// - Never processes elements after the first failing predicate
pub fn take_while(stream: Stream(a), pred: fn(a) -> Bool) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) ->
        case pred(value) {
          True -> Some(#(value, take_while(next, pred)))
          False -> None
        }
      None -> None
    }
  })
}

/// Concatenates two streams into a single stream, yielding all elements from the first stream
/// followed by all elements from the second stream.
/// 
/// ## Example
/// ```gleam
/// > [1, 2, 3]
/// |> from_list
/// |> concat(from_list([4, 5, 6]))
/// |> to_list()
/// [1, 2, 3, 4, 5, 6]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Stream 1: [1]-->[2]-->[3]-->|
/// Stream 2: [4]-->[5]-->[6]-->|
/// 
///           [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->|
///           └── Stream 1 ──┘  └── Stream 2 ──┘
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When you need to combine two streams sequentially
/// - For appending data from different sources
/// - When implementing stream operations that need to chain multiple streams
/// - When building composite streams from smaller streams
/// - For implementing stream operations like `flat_map` or `flatten`
/// - When you want to process multiple streams in sequence
/// 
/// ## Description
/// The `concat` function combines two streams by first yielding all elements from
/// the first stream until it's exhausted, then yielding all elements from the
/// second stream. The concatenation is lazy - elements from the second stream
/// aren't processed until all elements from the first stream have been consumed.
/// 
/// The function:
/// - Preserves the order of elements from both streams
/// - Processes streams lazily
/// - Returns an empty stream if both input streams are empty
/// - Handles infinite streams in the first position correctly (second stream never reached)
pub fn concat(first: Stream(a), second: Stream(a)) -> Stream(a) {
  Stream(pull: fn() {
    case first.pull() {
      Some(#(value, next)) -> Some(#(value, concat(next, second)))
      None -> second.pull()
    }
  })
}

/// Groups elements from a stream into chunks of the specified size.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> chunks(3)
/// |> to_list()
/// [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->[7]-->[8]-->[9]-->[10]-->|
///          |     |     |     |     |     |     |     |     |
///          └─────┴─────┴     └─────┴─────┘     └─────┴─────┘     └─┘
///             chunk 1            chunk 2          chunk 3       chunk 4
///                ↓                 ↓                 ↓            ↓
/// Output:    [[1,2,3]]-------->[[4,5,6]]-------->[[7,8,9]]----->[[10]]-->|
/// ```
/// Where `|` represents the end of the stream and partial chunks are included
/// 
/// ## When to Use
/// - When processing data in fixed-size batches
/// - For implementing pagination or windowing operations
/// - When buffering or batching stream elements for bulk processing
/// - For grouping elements for parallel processing
/// - When implementing network protocols with fixed-size frames
/// - For chunking large datasets into manageable pieces
/// 
/// ## Description
/// The `chunks` function transforms a stream by grouping its elements into 
/// fixed-size chunks. Each chunk is emitted as a list containing `size` elements,
/// except possibly the last chunk which may contain fewer elements if the stream
/// length is not evenly divisible by the chunk size.
/// 
/// The function:
/// - Processes elements lazily, only forming chunks when requested
/// - Preserves the order of elements within and between chunks
/// - Returns empty stream if size <= 0
/// - Includes partial chunks at the end of the stream
/// - Never creates chunks larger than the specified size
/// - Creates a stream of lists, where each list is a chunk
pub fn chunks(stream: Stream(a), size: Int) -> Stream(List(a)) {
  case size <= 0 {
    True -> from_empty()
    False ->
      Stream(pull: fn() {
        case take_chunk(stream, size, []) {
          Some(#(chunk, rest)) -> Some(#(chunk, chunks(rest, size)))
          None -> None
        }
      })
  }
}

fn take_chunk(
  stream: Stream(a),
  size: Int,
  acc: List(a),
) -> Option(#(List(a), Stream(a))) {
  case size == list.length(acc) {
    True -> Some(#(list.reverse(acc), stream))
    False ->
      case stream.pull() {
        Some(#(value, next)) -> take_chunk(next, size, [value, ..acc])
        None ->
          case acc {
            [] -> None
            _ -> Some(#(list.reverse(acc), from_empty()))
          }
      }
  }
}

/// Applies a function to each element of a stream for side effects.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> tap(fn(x) { io.println(x) })
/// ```
pub fn tap(stream: Stream(a), f: fn(a) -> b) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> {
        f(value)
        Some(#(value, tap(next, f)))
      }
      None -> None
    }
  })
}

/// Zips two streams together into a stream of tuples.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 3)
/// |> zip(from_range(10, 12))
/// |> to_list()
/// [#(1, 10), #(2, 11), #(3, 12)]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Stream 1: [1]---->[2]---->[3]-->|
///           |       |       |
///           v       v       v
///          #(1,10) #(2,11) #(3,12)
///           ^       ^       ^
///           |       |       |
/// Stream 2: [10]--->[11]-->[12]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Vertical arrows show how elements are paired
/// - Each pair becomes a tuple in the output stream
/// 
/// ## When to Use
/// - When you need to combine elements from two streams pairwise
/// - For implementing parallel processing with synchronized streams
/// - When creating coordinate pairs from separate x and y streams
/// - For matching corresponding elements from different data sources
/// - When implementing stream operations that need element-wise combination
/// - For creating associations between related streams
/// 
/// ## Description
/// The `zip` function combines two streams by pairing their elements together into
/// tuples. It processes both streams in parallel, creating a new stream where each
/// element is a tuple containing corresponding elements from both input streams.
/// The resulting stream terminates when either input stream ends, making it safe
/// to use with streams of different lengths.
/// 
/// Key characteristics:
/// - Preserves ordering of elements from both streams
/// - Processes elements lazily (on-demand)
/// - Terminates when either stream ends
/// - Creates tuples of corresponding elements
/// - Maintains synchronization between streams
pub fn zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) -> Some(#(#(v1, v2), zip(next1, next2)))
          None -> None
        }
      None -> None
    }
  })
}

/// Zips two streams together using a function to combine their elements.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 3)
/// |> zip_with(
///   from_range(10, 12),
///   fn(x, y) { x + y }
/// )
/// |> to_list()
/// [11, 13, 15]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Stream 1: [1]---->[2]---->[3]-->|
///           |       |       |
///           v       v       v
///        f(1,10) f(2,11) f(3,12)
///           ^       ^       ^
///           |       |       |
/// Stream 2: [10]--->[11]-->[12]-->|
///           
/// Result:   [11]--->[13]-->[15]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Vertical arrows show how elements are paired
/// - `f(x,y)` represents the combining function
/// 
/// ## When to Use
/// - When you need to combine elements from two streams using custom logic
/// - For implementing mathematical operations between parallel streams
/// - When transforming coordinate pairs with a specific formula
/// - For combining time series data with a custom aggregation function
/// - When implementing stream operations that need element-wise computation
/// - For creating derived streams based on multiple input streams
/// 
/// ## Description
/// The `zip_with` function combines two streams by applying a custom function to
/// corresponding pairs of elements. It processes both streams in parallel,
/// creating a new stream where each element is the result of applying the
/// provided function to elements from both input streams. The resulting stream
/// terminates when either input stream ends.
/// 
/// Key characteristics:
/// - Processes elements lazily (on-demand)
/// - Applies the combining function only when elements are pulled
/// - Terminates when either stream ends
/// - Maintains synchronization between streams
/// - Allows custom transformation of paired elements
/// - Preserves the streaming nature of inputs
pub fn zip_with(
  left: Stream(a),
  right: Stream(b),
  f: fn(a, b) -> c,
) -> Stream(c) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) -> Some(#(f(v1, v2), zip_with(next1, next2, f)))
          None -> None
        }
      None -> None
    }
  })
}

/// Zips two streams together, continuing until both streams are exhausted and including
/// `None` values for elements when one stream ends before the other.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 3)
/// |> zip_all(from_range(10, 11))
/// |> to_list()
/// [
///   Some(#(Some(1), Some(10))),
///   Some(#(Some(2), Some(11))),
///   Some(#(Some(3), None))
/// ]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Stream 1: [1]-------->[2]-------->[3]------->|
///           |           |           |
///           v           v           v
///        #(S(1),S(10)) #(S(2),S(11)) #(S(3),N)
///           ^           ^
///           |           |
/// Stream 2: [10]------->[11]------->|
/// 
/// Where: S = Some, N = None
/// ```
/// 
/// ## When to Use
/// - When you need to process two streams of different lengths together
/// - For implementing full outer joins between streams
/// - When handling missing or incomplete data between streams
/// - For synchronizing streams with potential gaps
/// - When you need to know exactly where and how streams diverge
/// - For implementing fault-tolerant stream processing
/// 
/// ## Description
/// The `zip_all` function combines two streams by pairing their elements, but unlike
/// regular `zip` which stops at the shortest stream, this continues until both
/// streams are exhausted. When one stream ends before the other, the function
/// continues producing pairs with `None` for the exhausted stream's side.
/// 
/// Key characteristics:
/// - Produces values until both streams are exhausted
/// - Wraps each element pair in `Some` to distinguish from stream end
/// - Uses `None` to indicate when a stream has ended
/// - Maintains perfect tracking of stream alignment
/// - Preserves all elements from both streams
/// - Processes elements lazily (on-demand)
pub fn zip_all(
  left: Stream(a),
  right: Stream(b),
) -> Stream(Option(#(Option(a), Option(b)))) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(Some(#(Some(v1), Some(v2))), zip_all(next1, next2)))
          None -> Some(#(Some(#(Some(v1), None)), zip_all(next1, from_empty())))
        }
      None ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(Some(#(None, Some(v2))), zip_all(from_empty(), next2)))
          None -> None
        }
    }
  })
}

/// Zips two streams using a function to combine values, continuing until both streams are exhausted.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 3)
/// |> zip_all_with(
///   from_range(10, 11),
///   fn(x, y) {
///     case #(x, y) {
///       #(Some(a), Some(b)) -> a + b
///       #(Some(a), None) -> a
///       #(None, Some(b)) -> b
///       #(None, None) -> 0  // Never reached in this example
///     }
///   }
/// )
/// |> to_list()
/// // Returns [11, 13, 3]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Stream 1: [1]-------->[2]-------->[3]------->|
///           |           |           |
///           v           v           v
///        f(S(1),S(10)) f(S(2),S(11)) f(S(3),N)
///           ↓           ↓             ↓
///          [11]------->[13]-------->[3]------->|
///           ^           ^
///           |           |
/// Stream 2: [10]------->[11]------->|
/// 
/// Where: S = Some, N = None, f = combining function
/// ```
/// 
/// ## When to Use
/// - When combining streams of different lengths with custom logic
/// - For implementing full outer joins with transformation
/// - When handling missing data with specific fallback logic
/// - For stream synchronization with custom element combination
/// - When implementing fault-tolerant stream processing with data transformation
/// - For creating derived streams that handle gaps in source streams
/// 
/// ## Description
/// The `zip_all_with` function combines two streams by applying a custom function
/// to pairs of elements, continuing until both streams are exhausted. Unlike
/// regular `zip_with` which stops at the shortest stream, this continues
/// processing and provides `None` values for exhausted streams.
/// 
/// Key characteristics:
/// - Processes until both streams are complete
/// - Provides `None` for elements after a stream ends
/// - Allows custom handling of present/missing values
/// - Maintains stream alignment with transformation
/// - Processes elements lazily (on-demand)
/// - Preserves streaming semantics while allowing value combination
pub fn zip_all_with(
  left: Stream(a),
  right: Stream(b),
  f: fn(Option(a), Option(b)) -> c,
) -> Stream(c) {
  Stream(pull: fn() {
    case left.pull() {
      Some(#(v1, next1)) ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(f(Some(v1), Some(v2)), zip_all_with(next1, next2, f)))
          None ->
            Some(#(f(Some(v1), None), zip_all_with(next1, from_empty(), f)))
        }
      None ->
        case right.pull() {
          Some(#(v2, next2)) ->
            Some(#(f(None, Some(v2)), zip_all_with(from_empty(), next2, f)))
          None -> None
        }
    }
  })
}

/// Prints each element of a stream to the console.
/// 
/// Example:
/// ```gleam
/// pure("Hello, world!") |> println
/// ```
pub fn println(stream: Stream(String)) -> Stream(String) {
  tap(stream, fn(x) { io.println(x) })
}

/// Logs each element of a stream for debugging.
/// 
/// Example:
/// ```gleam
/// pure(42) |> debug
/// ```
pub fn debug(stream: Stream(a)) -> Stream(a) {
  tap(stream, fn(x) { io.debug(x) })
}

/// Transforms a stream of Results into a stream of values, using a recovery function for errors.
/// 
/// ## Example
/// ```gleam
/// from_list([Ok(1), Error("oops"), Ok(3)])
/// |> try_recover(fn(_) { from_pure(2) })
/// |> to_list()
/// // Returns [1, 2, 3]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:   [Ok(1)]---->[Err("oops")]---->[Ok(3)]-->|
///             |             |               |
///             v             v               v
///            [1]---->  f("oops")  ------>  [3]-->|
///                         |
///                         v
///                        [2]
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `f(err)` is the recovery function
/// - Errors are replaced with recovery stream values
/// 
/// ## When to Use
/// - When handling fallible operations in streams
/// - For implementing retry logic in streaming operations
/// - When providing fallback values for failed operations
/// - For graceful error recovery in data processing pipelines
/// - When implementing fault-tolerant stream processing
/// - For transforming error cases into alternative valid values
/// 
/// ## Description
/// The `try_recover` function transforms a stream of Results into a stream of
/// values by:
/// - Passing through successful values (`Ok`) unchanged
/// - Applying a recovery function to error values (`Error`)
/// - Flattening the recovery stream into the main stream
/// 
/// The recovery function takes the error value and returns a new stream,
/// allowing for flexible error handling strategies including:
/// - Providing default values
/// - Retrying failed operations
/// - Computing alternative values
/// - Logging errors while continuing processing
/// 
/// The function processes elements lazily, only applying recovery when
/// needed, making it efficient for large streams.
pub fn try_recover(
  stream: Stream(Result(a, e)),
  recover: fn(e) -> Stream(a),
) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(Ok(value), rest)) -> Some(#(value, try_recover(rest, recover)))
      Some(#(Error(error), _)) -> recover(error).pull()
      None -> None
    }
  })
}

/// Recovers from an error in a stream using the given function.
/// Alias for `try_recover`.
pub fn recover(
  stream: Stream(Result(a, e)),
  recover: fn(e) -> Stream(a),
) -> Stream(a) {
  try_recover(stream, recover)
}

/// Inserts a separator element between each element of a stream.
/// 
/// ## Example
/// ```gleam
/// > from_list([1, 2, 3])
/// |> intersperse(0)
/// |> to_list()
/// [1, 0, 2, 0, 3]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]----->[2]----->[3]-->|
/// 
/// Output: [1]-->[0]--->[2]--->[0]--->[3]-->|
///          ^     ^      ^      ^      ^
///          |     |      |      |      |
///       value   sep   value   sep   value
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `sep` represents the separator
/// - Elements flow from left to right
/// 
/// ## When to Use
/// - When formatting streams for display (e.g., adding commas between items)
/// - When implementing string join operations with streams
/// - For adding delimiters between stream elements
/// - When creating visual separations in streamed output
/// - For implementing protocol-specific element separation
/// - When generating formatted text from stream elements
/// 
/// ## Description
/// The `intersperse` function creates a new stream that contains all elements
/// from the input stream with a separator value inserted between each pair of
/// elements. The separator is not added before the first element or after the
/// last element. This is particularly useful when formatting streams for
/// display or when implementing protocols that require specific delimiters
/// between elements.
/// 
/// Key characteristics:
/// - Preserves original element order
/// - Only inserts separators between elements
/// - No separator before first or after last element
/// - Processes elements lazily
/// - Returns empty stream if input is empty
pub fn intersperse(stream: Stream(a), separator: a) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) ->
        case next.pull() {
          Some(_) ->
            Some(#(
              value,
              Stream(pull: fn() {
                Some(#(separator, intersperse(next, separator)))
              }),
            ))
          None -> Some(#(value, from_empty()))
        }
      None -> None
    }
  })
}

/// Adds a delay between each element in a stream.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 3)
/// |> sleep(1000)  // 1 second delay
/// |> to_list()
/// // Returns [1, 2, 3] with 1 second delay between each element
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->|
/// 
/// Output: [1]--1s-->[2]--1s-->[3]-->|
///          |         |         |
///          ↓         ↓         ↓
///        delay     delay     delay
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `--1s-->` represents a 1 second delay
/// - Elements flow from left to right with delays
/// 
/// ## When to Use
/// - When implementing rate limiting
/// - For throttling high-speed streams
/// - When simulating time-dependent processes
/// - For creating animated or time-based sequences
/// - When implementing backpressure mechanisms
/// - For testing timing-dependent operations
/// - When synchronizing with external time-based systems
/// 
/// ## Description
/// The `sleep` function creates a new stream that introduces a fixed delay
/// between each element of the input stream. Every time an element is pulled
/// from the stream, the function waits for the specified number of milliseconds
/// before yielding the next element. This is useful for controlling the rate
/// of stream processing or simulating time-dependent sequences.
/// 
/// Key characteristics:
/// - Maintains original element order
/// - Adds consistent delays between elements
/// - Processes elements lazily
/// - Delay occurs before each element
/// - Suitable for infinite streams
pub fn sleep(stream: Stream(a), delay_ms: Int) -> Stream(a) {
  Stream(pull: fn() {
    process.sleep(delay_ms)
    stream.pull()
  })
}

/// Flattens a stream of streams into a single stream.
/// 
/// ## Example
/// ```gleam
/// > [[1, 2], [3, 4], [5, 6]]
/// |> from_list
/// |> map(from_list)
/// |> flatten
/// |> to_list
/// [1, 2, 3, 4, 5, 6]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input stream of streams:
///     +----------+    +----------+    +----------+
///  -->|[1,2]     |--->|[3,4]     |--->|[5,6]     |-->|
///     +----------+    +----------+    +----------+
///          |              |              |
///          v              v              v
///     [1]-->[2]-->| [3]-->[4]-->| [5]-->[6]-->|
/// 
/// Flattened output:
///     +---+    +---+    +---+    +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 3 |--->| 4 |--->| 5 |--->| 6 |-->|
///     +---+    +---+    +---+    +---+    +---+    +---+
/// ```
/// Where `|` represents the end of the stream
/// 
/// ## When to Use
/// - When working with nested stream structures that need to be linearized
/// - For processing hierarchical data as a single sequence
/// - When implementing monadic operations (e.g., flat_map)
/// - For combining multiple data sources into a single stream
/// - When dealing with streams of collections that need to be concatenated
/// - For implementing stream operations that produce multiple elements per input
/// 
/// ## Description
/// The `flatten` function takes a stream of streams and flattens it into a single
/// stream by concatenating all inner streams in order. It processes streams lazily,
/// only pulling from the next inner stream when all elements from the current inner
/// stream have been consumed.
/// 
/// The function:
/// - Preserves the order of elements from both outer and inner streams
/// - Processes streams lazily (on-demand)
/// - Handles empty inner streams by skipping to the next one
/// - Returns an empty stream if all inner streams are empty
/// - Maintains the streaming nature of both levels
pub fn flatten(stream: Stream(Stream(a))) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(inner, rest)) ->
        case inner.pull() {
          Some(#(value, next)) -> Some(#(value, concat(next, flatten(rest))))
          None -> flatten(rest).pull()
        }
      None -> None
    }
  })
}

/// Creates a stream that terminates when encountering a None value.
/// 
/// ## Example
/// ```gleam
/// > [Some(1), Some(2), None, Some(3)]
/// |> from_list
/// |> none_terminated
/// |> to_list()
/// [1, 2]  // Terminates at None, ignoring Some(3)
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:   [Some(1)]-->[Some(2)]-->[None]-->[Some(3)]-->|
///             |           |           |         ×
///             v           v           v
/// Output:    [1]-------->[2]-------->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `×` represents values that are ignored after None
/// - Values flow from left to right until None
/// 
/// ## When to Use
/// - When processing streams that use None as a termination signal
/// - For implementing protocols with end-of-stream markers
/// - When working with optional values where None indicates completion
/// - For converting option-based sequences into regular streams
/// - When implementing early termination based on None values
/// - For handling streams with natural termination points
/// 
/// ## Description
/// The `none_terminated` function transforms a stream of Option values into a
/// stream that yields only the unwrapped Some values and terminates when it
/// encounters a None. Any values after the first None are ignored. This is
/// particularly useful when working with protocols or data sources that use
/// None as an end-of-stream marker.
/// 
/// Key characteristics:
/// - Unwraps Some values into regular values
/// - Terminates immediately on first None
/// - Ignores all values after None
/// - Processes elements lazily
/// - Preserves order of elements before None
/// - Returns empty stream if first element is None
pub fn none_terminated(stream: Stream(Option(a))) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(Some(value), next)) -> Some(#(value, none_terminated(next)))
      Some(#(None, _)) -> None
      None -> None
    }
  })
}

/// Terminates a stream when encountering an Error value, yielding only Ok values until then.
/// 
/// ## Example
/// ```gleam
/// > [Ok(1), Ok(2), Error("oops"), Ok(3)]
/// |> from_list
/// |> error_terminated
/// |> to_list()
/// [1, 2]  // Terminates at Error, ignoring Ok(3)
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:   [Ok(1)]-->[Ok(2)]-->[Error("oops")]-->[Ok(3)]-->|
///             |         |            |              ×
///             v         v            v
/// Output:    [1]------>[2]---------->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `×` represents values that are ignored after Error
/// - Values flow from left to right until Error
/// 
/// ## When to Use
/// - When processing streams that should stop on first error
/// - For implementing fail-fast error handling
/// - When working with fallible operations where errors should terminate processing
/// - For converting result-based sequences into regular streams
/// - When implementing error-based early termination
/// - For handling streams with error conditions as termination points
/// 
/// ## Description
/// The `error_terminated` function transforms a stream of Result values into a
/// stream that yields only the unwrapped Ok values and terminates when it
/// encounters an Error. Any values after the first Error are ignored. This is
/// particularly useful when implementing fail-fast error handling or when working
/// with streams that should terminate on first error condition.
/// 
/// Key characteristics:
/// - Unwraps Ok values into regular values
/// - Terminates immediately on first Error
/// - Ignores all values after Error
/// - Processes elements lazily
/// - Preserves order of elements before Error
/// - Returns empty stream if first element is Error
pub fn error_terminated(stream: Stream(Result(a, e))) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(Ok(value), next)) -> Some(#(value, error_terminated(next)))
      Some(#(Error(_), _)) -> None
      None -> None
    }
  })
}

/// Splits a stream into two streams based on a predicate function, returning a tuple 
/// containing both streams and a task that manages the split operation.
/// 
/// ## Example
/// ```gleam
/// > let #(evens, odds, task) = 
/// >   from_range(1, 6)
/// >   |> to_split(fn(x) { x % 2 == 0 })
/// > 
/// > let even_list = evens |> to_list()  // [2, 4, 6]
/// > let odd_list = odds |> to_list()    // [1, 3, 5]
/// > task.await(task)
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->|
///             |     |     |     |     |     |
///           pred   pred  pred  pred  pred  pred
///             |     |     |     |     |     |
///             v     v     v     v     v     v
/// Evens:     ---->[2]---------->[4]---------->[6]-->|
/// Odds:      [1]---------->[3]---------->[5]------->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `pred` represents the predicate function evaluation
/// - Elements flow to either evens or odds based on predicate
/// 
/// ## When to Use
/// - When you need to partition a stream into two separate streams
/// - For implementing parallel processing of different data categories
/// - When separating elements based on a condition for different handling
/// - For implementing filter-based routing of stream elements
/// - When you need to process different categories of data independently
/// - For implementing stream-based data classification
/// 
/// ## Description
/// The `to_split` function divides an input stream into two separate streams based
/// on a predicate function. It returns a tuple containing:
/// 1. A stream of elements for which the predicate returns true
/// 2. A stream of elements for which the predicate returns false
/// 3. A task that manages the splitting operation
/// 
/// The function operates by:
/// - Creating two subjects to manage the split streams
/// - Asynchronously processing the input stream
/// - Routing each element to the appropriate subject based on the predicate
/// - Terminating both output streams when input is exhausted
/// 
/// The splitting operation is performed lazily and asynchronously, making it
/// efficient for large streams. Both resulting streams can be processed
/// independently and concurrently. The task ensures proper cleanup and
/// termination of both output streams.
pub fn to_split(
  stream: Stream(a),
  pred: fn(a) -> Bool,
) -> #(Stream(a), Stream(a), task.Task(Nil)) {
  let subject_left = process.new_subject()
  let subject_right = process.new_subject()

  let task =
    task.async(fn() {
      stream
      |> tap(fn(x) {
        case pred(x) {
          True -> process.send(subject_left, Some(x))
          False -> process.send(subject_right, Some(x))
        }
      })
      |> to_nil

      process.send(subject_left, None)
      process.send(subject_right, None)
    })

  let left = subject_left |> from_subject |> filter(pred)
  let right = subject_right |> from_subject |> filter(fn(a) { !pred(a) })
  #(left, right, task)
}

/// Reduces a stream to a single value by applying a function to each element.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> to_fold(0, fn(acc, x) { acc + x })
/// // Returns 15 (sum of 1 to 5)
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]---->[2]---->[3]---->[4]---->[5]-->|
///             |       |       |       |       |
///           f(0,1)  f(1,2)  f(3,3)  f(6,4) f(10,5)
///             |       |       |       |       |
///             v       v       v       v       v
/// Acc:     0 -> 1 -> 3 -> 6 -> 10 -> 15
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `f(acc,x)` shows each fold operation
/// - Values flow from left to right, accumulating results
/// 
/// ## When to Use
/// - When you need to combine all stream elements into a single value
/// - For calculating aggregates (sum, product, etc.)
/// - When implementing custom collection operations
/// - For transforming streams into non-stream data structures
/// - When you need to maintain state while processing a stream
/// - For implementing reduction operations over streams
/// 
/// ## Description
/// The `to_fold` function processes a stream by applying a folding function to
/// each element, maintaining an accumulator value throughout the operation. It:
/// - Takes an initial accumulator value
/// - Processes each stream element in order
/// - Updates the accumulator using the provided function
/// - Returns the final accumulator value
/// 
/// The folding function receives two arguments:
/// 1. The current accumulator value
/// 2. The current stream element
/// 
/// This is a terminal operation that consumes the entire stream and produces
/// a single result. It's commonly used as the foundation for other stream
/// termination operations like `to_list`, `to_set`, etc.
pub fn to_fold(stream: Stream(a), initial: b, f: fn(b, a) -> b) -> b {
  case stream.pull() {
    Some(#(value, next)) -> to_fold(next, f(initial, value), f)
    None -> initial
  }
}

/// Collects all elements from a stream into a list.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> to_list()
/// [1, 2, 3, 4, 5]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input Stream:
/// 
///     +---+    +---+    +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 3 |--->| 4 |--->| 5 |-->|
///     +---+    +---+    +---+    +---+    +---+
///       |       |        |        |        |
///       v       v        v        v        v
///      [1] -> [1,2] -> [1,2,3] -> [1,2,3,4] -> [1,2,3,4,5]
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Each element is accumulated into the growing list
/// 
/// ## When to Use
/// - When you need to collect all stream elements into memory
/// - For processing finite streams where total size is manageable
/// - When you need random access to stream elements
/// - For converting lazy evaluation (streams) to eager evaluation (lists)
/// - When implementing terminal operations that need all elements at once
/// - For testing or debugging stream operations
/// 
/// ## Description
/// The `to_list` function is a terminal operation that consumes the entire stream
/// and collects all elements into a list. It processes elements sequentially,
/// maintaining their original order. This operation requires enough memory to
/// hold all stream elements simultaneously, so it should be used carefully with
/// large or infinite streams.
/// 
/// Key characteristics:
/// - Preserves element order
/// - Consumes the entire stream
/// - Requires memory proportional to stream length
/// - Creates a new list containing all elements
/// - Terminal operation (ends stream processing)
/// - Suitable for finite streams
pub fn to_list(stream: Stream(a)) -> List(a) {
  to_fold(stream, [], fn(acc, x) { list.append(acc, [x]) })
}

/// Collects all elements from a stream into a set.
/// 
/// ## Example
/// ```gleam
/// > from_list([1, 2, 2, 3, 3, 3])
/// |> to_set()
/// |> set.to_list()
/// [1, 2, 3]  // Duplicates removed
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input Stream:
/// 
///     +---+    +---+    +---+    +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 2 |--->| 3 |--->| 3 |--->| 3 |-->|
///     +---+    +---+    +---+    +---+    +---+    +---+
///       |       |        |        |        |        |
///       v       v        v        v        v        v
///      {1} -> {1,2} -> {1,2} -> {1,2,3} -> {1,2,3} -> {1,2,3}
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Each element is added to the set, duplicates are automatically removed
/// - `{...}` represents the growing set
/// 
/// ## When to Use
/// - When you need to collect unique elements from a stream
/// - For removing duplicates from a stream efficiently
/// - When order doesn't matter but uniqueness does
/// - For implementing set operations on streams
/// - When building unique collections from potentially redundant data
/// - For counting unique elements in a stream
/// 
/// ## Description
/// The `to_set` function is a terminal operation that consumes the entire stream
/// and collects all unique elements into a set. It automatically handles
/// deduplication as elements are added to the set. The resulting set provides
/// efficient membership testing and ensures each value appears only once.
/// 
/// Key characteristics:
/// - Removes duplicates automatically
/// - Unordered collection (set semantics)
/// - Consumes the entire stream
/// - Efficient membership testing
/// - Terminal operation (ends stream processing)
pub fn to_set(stream: Stream(a)) -> Set(a) {
  to_fold(stream, set.new(), fn(acc, x) { set.insert(acc, x) })
}

/// Processes a stream completely, discarding all values and returning Nil.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> tap(io.println)
/// |> to_nil
/// // Prints: 1, 2, 3, 4, 5
/// // Returns: Nil
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]-->[2]-->[3]-->[4]-->[5]-->|
///             ↓     ↓     ↓     ↓     ↓
///           process process process process process
///             ↓     ↓     ↓     ↓     ↓
/// Output:    Nil   Nil   Nil   Nil   Nil
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Each element is processed but discarded
/// - Only side effects (if any) remain
/// 
/// ## When to Use
/// - When you only care about side effects (logging, printing, etc.)
/// - For consuming a stream without keeping results
/// - When implementing fire-and-forget operations
/// - For triggering stream processing without collecting results
/// - When memory usage is critical and results aren't needed
/// - For testing stream processing without result validation
/// 
/// ## Description
/// The `to_nil` function is a terminal operation that processes an entire stream
/// but discards all values, returning Nil. It's particularly useful when you're
/// interested in the side effects of processing a stream (like printing or
/// logging) but don't need the actual values. This operation is memory efficient
/// as it doesn't accumulate any results.
/// 
/// Key characteristics:
/// - Processes all elements sequentially
/// - Discards all values
/// - Returns Nil regardless of input
/// - Preserves side effects from stream processing
/// - Terminal operation (ends stream processing)
/// - Memory efficient (no accumulation)
pub fn to_nil(stream: Stream(a)) -> Nil {
  to_fold(stream, Nil, fn(_, _) { Nil })
}

/// Collects the first element of a stream into an option.
/// 
/// Example:
/// ```gleam
/// repeat(1) |> take(5) |> to_option
/// ```
pub fn to_option(stream: Stream(a)) -> Option(a) {
  case stream.pull() {
    Some(#(value, _)) -> Some(value)
    None -> None
  }
}

/// Converts a stream into a process Subject and returns it along with a task that manages the conversion.
/// 
/// ## Example
/// ```gleam
/// > let #(subject, task) = 
/// >   from_range(1, 3)
/// >   |> to_subject()
/// > 
/// > process.receive(subject, 100)  // -> Ok(Some(1))
/// > process.receive(subject, 100)  // -> Ok(Some(2))
/// > process.receive(subject, 100)  // -> Ok(Some(3))
/// > process.receive(subject, 100)  // -> Ok(None)
/// > task.await(task)
/// ```
/// 
/// ## Visual Representation
/// ```
/// Stream to Subject conversion:
/// 
///     +---+    +---+    +---+
///  -->| 1 |--->| 2 |--->| 3 |-->|     Stream
///     +---+    +---+    +---+
///       |        |        |
///       v        v        v
///    Subject: Some(1), Some(2), Some(3), None
///       |        |        |        |
///       v        v        v        v
///    Receive  Receive  Receive  Receive     Process
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Each element is sent to the subject as Some(value)
/// - Stream end is signaled with None
/// 
/// ## When to Use
/// - When converting from pull-based (Stream) to push-based (Subject) processing
/// - For bridging synchronous streams with asynchronous message passing
/// - When implementing pub/sub patterns with stream sources
/// - For distributing stream elements to multiple consumers
/// - When you need to buffer stream elements for later processing
/// - For implementing backpressure mechanisms
/// - When integrating streams with OTP process patterns
/// 
/// ## Description
/// The `to_subject` function transforms a stream into a process Subject, which
/// allows for asynchronous message-based communication. It returns a tuple
/// containing:
/// 1. A Subject that will receive stream elements as Option(a) messages
/// 2. A Task that manages the conversion process
/// 
/// The function:
/// - Creates a new Subject for receiving stream elements
/// - Asynchronously processes the stream, sending each element as Some(value)
/// - Signals stream completion by sending None
/// - Manages the conversion process in a separate task
/// - Allows for multiple consumers to receive stream elements
/// 
/// The returned task ensures proper cleanup and should be awaited when the
/// stream processing is complete. Recipients can receive values from the
/// subject using `process.receive` or similar functions.
pub fn to_subject(stream: Stream(a)) -> #(Subject(Option(a)), task.Task(Nil)) {
  let subject = process.new_subject()
  let task =
    task.async(fn() {
      to_fold(stream, Nil, fn(_, x) { process.send(subject, Some(x)) })
      process.send(subject, None)
    })
  #(subject, task)
}

/// Processes a stream of Options until encountering None, discarding all values and returning Nil.
/// 
/// ## Example
/// ```gleam
/// [Some(1), Some(2), None, Some(3)]
/// |> from_list
/// |> to_nil_none_terminated
/// // Processes 1, 2, stops at None, ignores 3
/// // Returns: Nil
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:   [Some(1)]-->[Some(2)]-->[None]-->[Some(3)]-->|
///             |           |           |         ×
///             ↓           ↓           ↓
///            Nil        Nil         Nil
///                                    |
/// Output:                           Nil
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `×` represents values that are ignored after None
/// - Each Some value is processed but discarded
/// - Processing stops at None
/// 
/// ## When to Use
/// - When processing Option streams for side effects until termination
/// - For consuming streams with None as termination signal
/// - When implementing fire-and-forget operations with early termination
/// - For processing streams where None indicates completion
/// - When you need to execute side effects but don't need values
/// - For testing Option stream processing without result validation
/// 
/// ## Description
/// The `to_nil_none_terminated` function is a terminal operation that processes
/// a stream of Options until it encounters a None value. It combines the behavior
/// of `none_terminated` and `to_nil`, processing each Some value but discarding
/// the results. The operation stops immediately when None is encountered, ignoring
/// any subsequent elements.
/// 
/// Key characteristics:
/// - Processes Some values sequentially until None
/// - Discards all values
/// - Stops processing at first None
/// - Ignores elements after None
/// - Returns Nil regardless of input
/// - Memory efficient (no accumulation)
/// - Preserves side effects from stream processing
/// - Terminal operation (ends stream processing)
pub fn to_nil_none_terminated(stream: Stream(Option(a))) -> Nil {
  stream |> none_terminated |> to_nil
}

/// Processes a stream of Results until encountering an Error, discarding all values and returning Nil.
/// 
/// ## Example
/// ```gleam
/// > [Ok(1), Ok(2), Error("oops"), Ok(3)]
/// |> from_list
/// |> to_nil_error_terminated
/// // Processes 1, 2, stops at Error("oops"), ignores 3
/// // Returns: Nil
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:   [Ok(1)]-->[Ok(2)]-->[Error]-->[Ok(3)]-->|
///             |         |          |         ×
///             ↓         ↓          ↓
///            Nil       Nil        Nil
///                                  |
/// Output:                         Nil
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `×` represents values that are ignored after Error
/// - Each Ok value is processed but discarded
/// - Processing stops at Error
/// 
/// ## When to Use
/// - When processing Result streams for side effects until first error
/// - For consuming streams with Error as termination signal
/// - When implementing fail-fast operations with side effects
/// - For processing streams where errors indicate critical failures
/// - When you need to execute side effects but don't need values
/// - For testing error handling without result validation
/// - When implementing fault-tolerant processing pipelines
/// 
/// ## Description
/// The `to_nil_error_terminated` function is a terminal operation that processes
/// a stream of Results until it encounters an Error value. It combines the behavior
/// of `error_terminated` and `to_nil`, processing each Ok value but discarding
/// the results. The operation stops immediately when an Error is encountered,
/// ignoring any subsequent elements.
/// 
/// Key characteristics:
/// - Processes Ok values sequentially until Error
/// - Discards all values
/// - Stops processing at first Error
/// - Ignores elements after Error
/// - Returns Nil regardless of input
/// - Memory efficient (no accumulation)
/// - Preserves side effects from stream processing
/// - Terminal operation (ends stream processing)
pub fn to_nil_error_terminated(stream: Stream(Result(a, e))) -> Nil {
  stream |> error_terminated |> to_nil
}
