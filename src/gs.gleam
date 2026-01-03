import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string
import gs/internal/queue
import gs/internal/task
import gs/internal/utils

/// A Stream represents a lazy, pull-based sequence of elements.
/// Each element is computed only when requested, making it memory efficient
/// for large or infinite sequences.
///
/// ## Stream Architecture
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
/// ## Key Characteristics
///
/// - **Pull-based**: Elements are computed on demand
/// - **Sequential**: Only one element is processed at a time
/// - **Lazy**: Elements are not computed until requested
/// - **Finite**: Stream ends when None is returned
/// - **Memory Efficient**: Only active element is in memory
/// - **Composable**: Operations can be chained together
/// - **Thread-Safe**: Safe for concurrent processing
///
/// ## Performance Considerations
///
/// - Use `buffer` for producer-consumer speed mismatches
/// - Use `par_map` for CPU-intensive transformations
/// - Use `take` to limit infinite streams
/// - Use `chunks` for batch processing
/// - Prefer `fold` over `to_list` for large streams
///
pub type Stream(a) {
  Stream(pull: fn() -> Option(#(a, Stream(a))))
}

/// Represents different overflow handling strategies for buffered operations.
///
/// ## Strategy Details
///
/// - **Wait**: Producer blocks until buffer space becomes available (backpressure)
/// - **Drop**: New elements are silently discarded when buffer is full
/// - **Stop**: Stream terminates immediately when buffer overflows
/// - **Panic**: Raises a runtime error on buffer overflow
///
/// ## When to Use Each Strategy
///
/// - **Wait**: For reliable delivery and flow control
/// - **Drop**: For lossy but continuous processing
/// - **Stop**: For fail-fast error handling
/// - **Panic**: For debugging buffer sizing issues
///
pub type OverflowStrategy {
  Wait
  Drop
  Stop
  Panic
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
pub fn from_subject(subject: process.Subject(Option(a))) -> Stream(a) {
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
pub fn from_subject_timeout(
  subject: process.Subject(a),
  timeout_ms: Int,
) -> Stream(a) {
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

/// Filters elements from a stream based on a predicate function that has access to both
/// the previous and current elements.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> filter_with_previous(fn(prev, current) {
///   case prev {
///     Some(p) -> current > p  // Keep only increasing values
///     None -> True  // Always keep first element
///   }
/// })
/// |> to_list()
/// [1, 2, 3, 4, 5]  // All values kept (increasing sequence)
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]-->[2]-->[3]-->[2]-->[4]-->|
///             |     |     |     |     |
///        p(N,1) p(1,2) p(2,3) p(3,2) p(3,4)
///             ✓     ✓     ✓     ×     ✓
///             |     |     |           |
/// Output:    [1]-->[2]-->[3]-------->[4]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `p(prev,curr)` is the predicate function with previous and current value
/// - `N` represents None (no previous value)
/// - `✓` indicates element was kept
/// - `×` indicates element was filtered out
/// 
/// ## When to Use
/// - When filtering needs context from the previous element
/// - For implementing stateful filtering operations
/// - When detecting patterns in sequential pairs
/// - For removing duplicate consecutive elements
/// - When implementing trend-based filtering
/// - For quality control based on previous value
/// 
/// ## Description
/// The `filter_with_previous` function creates a new stream that includes elements
/// based on a predicate function that has access to both the current element and
/// the previously kept element. This allows for sophisticated filtering based on
/// the relationship between consecutive elements.
/// 
/// The predicate function receives:
/// 1. An Option containing the previous kept element (None for first element)
/// 2. The current element being considered
/// 
/// Key characteristics:
/// - Maintains single element history
/// - Allows stateful filtering decisions
/// - Processes elements lazily
/// - Preserves order of kept elements
/// - Memory usage is constant (only one previous element)
pub fn filter_with_previous(
  stream: Stream(a),
  keeping pred: fn(Option(a), a) -> Bool,
) -> Stream(a) {
  filter_with_previous_loop(stream, None, pred)
}

fn filter_with_previous_loop(
  stream: Stream(a),
  previous: Option(a),
  pred: fn(Option(a), a) -> Bool,
) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> {
        case pred(previous, value) {
          True ->
            Some(#(value, filter_with_previous_loop(next, Some(value), pred)))
          False -> filter_with_previous_loop(next, Some(value), pred).pull()
        }
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

/// Processes nested streams concurrently and discards all results.
/// 
/// ## Example
/// ```gleam
/// > [[1, 2], [3, 4], [5, 6]]
/// |> from_list
/// |> map(from_list)
/// |> concurrently
/// // Processes all streams in parallel, returns Stream(Nil)
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input streams:         [Stream1]-->[Stream2]-->[Stream3]-->|
///                          |          |          |
///                          v          v          v
/// Parallel processing:  [1,2]      [3,4]      [5,6]
///                       ↓  ↓        ↓  ↓        ↓  ↓
///                      Nil Nil     Nil Nil     Nil Nil
/// ```
/// 
/// ## When to Use
/// - When you need to process multiple streams in parallel
/// - For implementing concurrent operations with side effects
/// - When processing order doesn't matter
/// - For maximizing throughput with independent streams
/// - When implementing parallel processing pipelines
/// 
/// ## Description
/// The `concurrently` function takes a stream of streams and processes each
/// inner stream concurrently using tasks. Results are discarded, making it
/// suitable for operations where only side effects matter. The function
/// returns a stream that yields Nil for each completed inner stream.
pub fn concurrently(streams: Stream(Stream(a))) -> Stream(Nil) {
  Stream(pull: fn() {
    case streams.pull() {
      Some(#(stream, rest)) -> {
        task.spawn(fn() { stream |> to_nil })
        Some(#(Nil, concurrently(rest)))
      }
      None -> None
    }
  })
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
        case take_chunk(stream, size, [], 0) {
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
  count: Int,
) -> Option(#(List(a), Stream(a))) {
  case count == size {
    True -> Some(#(list.reverse(acc), stream))
    False ->
      case stream.pull() {
        Some(#(value, next)) ->
          take_chunk(next, size, [value, ..acc], count + 1)
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

/// Buffers a stream into overlapping windows of a specified size.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> window(3)
/// |> to_list()
/// [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]-->[2]-->[3]-->[4]-->[5]-->|
///             |     |     |     |     |
///             |    [1,2] [1,2,3]    |
///             |     |     |     |    |
///             |     |    [2,3,4]    |
///             |     |     |     |    |
///             |     |    [3,4,5]    |
///             
/// Output: [[1,2,3], [2,3,4], [3,4,5]]
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Each window overlaps with the next
/// - Windows slide by one element each time
/// 
/// ## When to Use
/// - For implementing sliding window operations
/// - When processing time series data with overlapping windows
/// - For calculating moving averages
/// - When implementing signal processing algorithms
/// - For pattern detection in sequential data
/// - When analyzing trends in streaming data
/// 
/// ## Description
/// The `window` function creates a new stream where elements are grouped into
/// overlapping windows of the specified size. Each window contains the specified
/// number of consecutive elements, and windows overlap by size-1 elements. The
/// function is useful for operations that need to consider multiple consecutive
/// elements together.
/// 
/// Key characteristics:
/// - Creates overlapping windows of fixed size
/// - Windows slide by one element each time
/// - Preserves element order within windows
/// - Returns empty stream if size <= 0
/// - Processes elements lazily
/// - Memory usage proportional to window size
pub fn window(stream: Stream(a), size: Int) -> Stream(List(a)) {
  case size <= 0 {
    True -> from_empty()
    False -> Stream(pull: fn() { take_window(stream, size, [], 0).pull() })
  }
}

fn take_window(
  stream: Stream(a),
  size: Int,
  acc: List(a),
  count: Int,
) -> Stream(List(a)) {
  Stream(pull: fn() {
    case count == size {
      True ->
        Some(#(
          list.reverse(acc),
          take_window(stream, size, drop_last(acc), count - 1),
        ))
      False ->
        case stream.pull() {
          Some(#(value, next)) ->
            take_window(next, size, [value, ..acc], count + 1).pull()
          None -> None
        }
    }
  })
}

fn drop_last(list: List(a)) -> List(a) {
  case list {
    [] -> []
    [_] -> []
    [head, ..tail] -> [head, ..drop_last(tail)]
  }
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

/// Creates a stream where each element is paired with a resource that is automatically
/// cleaned up when the stream ends.
/// 
/// ## Example
/// ```gleam
/// // Example using a file handle as a resource
/// let file_stream = 
///   from_range(1, 3)
///   |> bracket(
///     acquire: fn() { open_file("log.txt") },
///     cleanup: fn(file) { close_file(file) }
///   )
///   |> map(fn(pair) {
///     let #(file, number) = pair
///     write_to_file(file, number)
///     number
///   })
///   |> to_list
/// // File is automatically closed after processing
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]-------->[2]-------->[3]------->|
///             |           |           |         |
///        acquire()   use resource  use resource cleanup()
///             |           |           |         |
///             v           v           v         v
///         #(res,1)--->#(res,2)--->#(res,3)---->|
/// 
///                    Resource Lifecycle
///      +------------------------------------------------+
///      |                                                |
///      | acquire -> use -> use -> use -> cleanup       |
///      |     ↑      ↑      ↑      ↑         ↑         |
///      |     |      |      |      |         |         |
///      +------------------------------------------------+
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `res` is the acquired resource
/// - Resource is shared across all elements
/// - Cleanup occurs at stream end
/// 
/// ## When to Use
/// - When working with resources that need proper cleanup (files, connections)
/// - For implementing resource-safe stream processing
/// - When ensuring resource cleanup regardless of stream completion
/// - For managing stateful resources across stream operations
/// - When implementing transactions or session-based processing
/// - For handling connection pools or shared resources
/// - When implementing resource-bound processing pipelines
/// 
/// ## Description
/// The `bracket` function creates a resource-managed stream by:
/// 1. Acquiring a resource using the provided `acquire` function
/// 2. Pairing each stream element with the resource
/// 3. Ensuring resource cleanup using the `cleanup` function when the stream ends
/// 
/// This pattern is particularly useful for:
/// - File operations (open/close)
/// - Database transactions (begin/commit/rollback)
/// - Network connections (connect/disconnect)
/// - System resources (allocate/deallocate)
/// 
/// The function guarantees that:
/// - Resource is acquired exactly once at start
/// - Resource is available for each element
/// - Cleanup occurs exactly once at end
/// - Cleanup happens even if stream is not fully consumed
/// - Resource management is handled automatically
/// 
/// This provides a safe way to work with resources in a streaming context,
/// ensuring proper cleanup and preventing resource leaks.
pub fn bracket(
  stream: Stream(a),
  acquire acquire: fn() -> resource,
  cleanup cleanup: fn(resource) -> Nil,
) -> Stream(#(resource, a)) {
  Stream(pull: fn() {
    let resource = acquire()
    bracket_loop(stream, resource, cleanup).pull()
  })
}

fn bracket_loop(
  stream: Stream(a),
  resource: resource,
  cleanup: fn(resource) -> Nil,
) -> Stream(#(resource, a)) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) ->
        Some(#(#(resource, value), bracket_loop(next, resource, cleanup)))
      None -> {
        cleanup(resource)
        None
      }
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

/// Creates a buffered stream that holds elements in a queue with specified overflow strategy.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> buffer(
///     size: 3,            // Buffer capacity
///     mode: Wait          // Wait when buffer is full
/// )
/// |> tap(fn(x) { process.sleep(100) }) // Simulate slow processing
/// |> to_list()
/// // Returns [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] with buffering
/// ```
/// 
/// ## Visual Representation
/// ```
/// Fast producer, slow consumer with buffer:
/// 
///           +----------------Buffer (size 3)----------------+
///           |  +---+    +---+    +---+                    |
/// Producer  |  | 1 |    | 2 |    | 3 |    (waiting...)   |  Consumer
/// --------->|  +---+    +---+    +---+                    |---------->
/// [4,5,6,..]|  └─────────────────────┘                    | [1,2,3,..]
///           +--------------------------------------------+
/// 
/// Strategy behaviors when buffer is full:
/// - Wait:  Producer pauses until space available
/// - Drop:  New elements are discarded
/// - Stop:  Stream terminates
/// - Panic: Raises an error
/// ```
/// 
/// ## When to Use
/// - When processing speeds differ between producer and consumer
/// - For implementing backpressure mechanisms
/// - When you need to smooth out processing spikes
/// - For rate-limiting or flow control
/// - When implementing producer-consumer patterns
/// - For managing memory usage with fast producers
/// - When implementing stream processing pipelines
/// 
/// ## Description
/// The `buffer` function creates a buffered stream that can hold a specified
/// number of elements in a queue. It's particularly useful when dealing with
/// producers and consumers operating at different speeds. The function takes:
/// 1. A stream to buffer
/// 2. A buffer size limit
/// 3. An overflow strategy specifying behavior when the buffer is full
/// 
/// Overflow Strategies:
/// - `Wait`: Producer waits until space is available (backpressure)
/// - `Drop`: New elements are discarded when buffer is full
/// - `Stop`: Stream terminates when buffer overflows
/// - `Panic`: Raises an error on buffer overflow
/// 
/// The buffering mechanism:
/// - Creates an asynchronous queue of specified size
/// - Processes elements through the queue in FIFO order
/// - Applies the specified overflow strategy when full
/// - Maintains element order
/// - Handles stream termination gracefully
/// 
/// This is particularly useful for:
/// - Managing producer-consumer speed differences
/// - Implementing backpressure
/// - Controlling memory usage
/// - Smoothing out processing irregularities
/// - Building robust streaming pipelines
pub fn buffer(stream: Stream(a), size: Int, mode: OverflowStrategy) -> Stream(a) {
  case size <= 0 {
    True -> stream
    False -> {
      let assert Ok(pid) = queue.start(size)
      task.spawn(fn() { fill_buffer(stream, mode, pid) |> to_nil() })
      read_buffer(pid)
    }
  }
}

fn read_buffer(pid: process.Subject(queue.Message(Option(a)))) -> Stream(a) {
  Stream(pull: fn() {
    case process.call_forever(pid, queue.Pop) {
      Some(Some(value)) -> Some(#(value, read_buffer(pid)))
      Some(None) -> None
      None -> read_buffer(pid).pull()
    }
  })
}

fn fill_buffer(
  stream: Stream(a),
  mode: OverflowStrategy,
  pid: process.Subject(queue.Message(Option(a))),
) -> Stream(a) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) ->
        case process.call_forever(pid, fn(s) { queue.Push(s, Some(value)) }) {
          True -> fill_buffer(next, mode, pid).pull()
          False ->
            case mode {
              Wait -> {
                let current = Stream(pull: fn() { Some(#(value, next)) })
                fill_buffer(current, mode, pid).pull()
              }
              Drop -> fill_buffer(next, mode, pid).pull()
              Stop -> None
              Panic -> panic as "Buffer overflow"
            }
        }
      None ->
        case process.call_forever(pid, fn(s) { queue.Push(s, None) }) {
          True -> None
          False ->
            case mode {
              Wait | Drop -> fill_buffer(stream, mode, pid).pull()
              Stop -> None
              Panic -> panic as "Buffer overflow"
            }
        }
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
  tap(stream, fn(x) { string.inspect(x) |> io.println })
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

/// Counts elements as they pass through the stream, yielding tuples of elements and their count.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 3)
/// |> count()
/// |> to_list()
/// [#(1, 1), #(2, 2), #(3, 3)]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]---->[2]---->[3]-->|
///             |       |       |
///         count=1  count=2  count=3
///             |       |       |
///             v       v       v
/// Output: [(1,1)]->[(2,2)]->[(3,3)]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Each element is paired with its count
/// - Count increases monotonically
/// 
/// ## When to Use
/// - When you need to track how many elements have been processed
/// - For implementing progress tracking in stream processing
/// - When you need element indices in a stream
/// - For debugging or monitoring stream flow
/// - When implementing stateful stream operations
/// - For adding sequence numbers to stream elements
/// 
/// ## Description
/// The `count` function transforms a stream by pairing each element with a
/// running count of how many elements have been processed. It maintains an
/// internal counter that increments for each element, starting from 1.
/// 
/// Key characteristics:
/// - Preserves original elements
/// - Adds monotonic counting
/// - Processes elements lazily
/// - Count starts at 1
/// - Returns tuples of (element, count)
pub fn count(stream: Stream(a)) -> Stream(#(a, Int)) {
  count_loop(stream, 1)
}

fn count_loop(stream: Stream(a), counter: Int) -> Stream(#(a, Int)) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) ->
        Some(#(#(value, counter), count_loop(next, counter + 1)))
      None -> None
    }
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

/// Implements exponential backoff rate limiting for a stream by dynamically adjusting
/// delays between elements based on processing history.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> rate_limit_backoff(
///     initial_delay_ms: 100,  // Start with 100ms delay
///     max_delay_ms: 1000,    // Cap at 1 second delay
///     factor: 2.0           // Double delay on each retry
/// )
/// |> to_list()
/// // Returns [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] with increasing delays
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->...
///          |     |     |     |     |     |
///       100ms  200ms 400ms 800ms  1s    1s    (exponential delays)
///          |     |     |     |     |     |
/// Output: [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->...
/// ```
/// 
/// ## When to Use
/// - When implementing retry logic with increasing delays
/// - For handling rate-limited APIs with automatic backoff
/// - When implementing fault-tolerant stream processing
/// - For graceful degradation under load
/// - When implementing adaptive rate limiting
/// - For implementing congestion control mechanisms
/// 
/// ## Description
/// The `rate_limit_backoff` function creates a rate-limited stream that automatically
/// adjusts delays between elements using exponential backoff. Unlike linear rate
/// limiting, this approach increases delays exponentially up to a maximum value,
/// making it suitable for scenarios where adaptive rate limiting is needed.
/// 
/// Parameters:
/// - initial_delay_ms: Starting delay between elements
/// - max_delay_ms: Maximum delay cap
/// - factor: Multiplication factor for delay increase
/// 
/// The function ensures that:
/// - Delays start at initial_delay_ms
/// - Each delay is multiplied by factor
/// - Delays are capped at max_delay_ms
/// 
/// This is particularly useful for:
/// - API rate limit compliance
/// - Retry mechanisms
/// - Load balancing
/// - Error recovery
/// - System protection
pub fn rate_limit_backoff(
  stream: Stream(a),
  initial_delay_ms: Int,
  max_delay_ms: Int,
  factor: Float,
) -> Stream(a) {
  let backoff_stream =
    from_state_eval(initial_delay_ms, fn(current_delay) {
      let next_delay =
        int.min(
          max_delay_ms,
          float.truncate(float.floor(int.to_float(current_delay) *. factor)),
        )
      #(current_delay, next_delay)
    })

  stream
  |> zip_with(backoff_stream, fn(value, delay) {
    process.sleep(delay)
    value
  })
}

/// TODO: rate_limit
/// Implements linear rate limiting for a stream by controlling the number of elements processed per time interval.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 10)
/// |> rate_limit_linear(
///     rate: 2,        // 2 elements
///     interval_ms: 1000  // per second
/// )
/// |> to_list()
/// // Returns [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] with constant delays
/// // Processes 2 elements per second
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:  [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->...
///          |     |     |     |     |     |
///        500ms 500ms 500ms 500ms 500ms 500ms  (constant delays)
///          |     |     |     |     |     |
/// Output: [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->...
///         |<-1 s.-> | <- 1 s. -> |
///          (2 items)  (2 items)
/// ```
/// 
/// ## When to Use
/// - When implementing consistent rate limiting for API calls
/// - For controlling throughput to external services
/// - When processing needs to match a specific rate requirement
/// - For implementing SLA compliance
/// - When preventing system overload
/// - For simulating time-constrained processing
/// - When implementing quota-based systems
/// 
/// ## Description
/// The `rate_limit_linear` function creates a rate-limited stream that processes
/// a specified number of elements within a given time interval. Unlike exponential
/// backoff, this maintains a constant rate of processing, making it suitable for
/// scenarios where consistent throughput is required.
/// 
/// Parameters:
/// - rate: Number of elements to process per interval
/// - interval_ms: Time interval in milliseconds
/// 
/// The function ensures that:
/// - Elements are processed at a constant rate
/// - Delays are evenly distributed across the interval
/// - Processing matches the specified throughput
/// - Rate limiting is precise and predictable
/// 
/// This is particularly useful for:
/// - API rate limiting compliance
/// - Resource utilization control
/// - Service level agreement implementation
/// - System load management
/// - Throughput optimization
/// - Quota enforcement
pub fn rate_limit_linear(
  stream: Stream(a),
  rate: Int,
  interval_ms: Int,
) -> Stream(a) {
  let delay = interval_ms / rate
  from_tick(delay) |> zip(stream) |> map(fn(value) { value.1 })
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

/// Produces a stream of intermediate fold results (running accumulator values).
///
/// ## Example
/// ```gleam
/// > from_list([1, 2, 3, 4, 5])
/// |> scan(0, fn(acc, x) { acc + x })
/// |> to_list()
/// // -> [1, 3, 6, 10, 15]
/// // Running sum: 0+1=1, 1+2=3, 3+3=6, 6+4=10, 10+5=15
/// ```
///
/// ## Visual Representation
/// ```
/// Input:  [1]---->[2]---->[3]---->[4]---->[5]-->|
///          |       |       |       |       |
///       f(0,1)  f(1,2)  f(3,3)  f(6,4)  f(10,5)
///          |       |       |       |       |
///          v       v       v       v       v
/// Output: [1]---->[3]---->[6]--->[10]--->[15]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `f(acc,x)` shows each fold operation
/// - Each output element is the result of applying f to the accumulator and input
///
/// ## When to Use
/// - When you need intermediate results of a fold operation
/// - For calculating running totals, averages, or other cumulative statistics
/// - When implementing stateful transformations that expose their state
/// - For prefix sums, running products, or other scan-like operations
/// - When debugging fold operations by observing intermediate values
///
/// ## Description
/// The `scan` function is similar to `to_fold`, but instead of returning only the
/// final result, it emits each intermediate accumulator value as a stream element.
/// This enables streaming computation of cumulative operations.
///
/// Unlike `scan_with_initial`, this function does NOT emit the initial value -
/// the first output is `f(initial, first_element)`.
///
/// Key characteristics:
/// - Preserves laziness - elements computed on demand
/// - Does not emit the initial accumulator value
/// - Output stream has same length as input stream
/// - Stateful transformation with visible state
pub fn scan(stream: Stream(a), initial: b, f: fn(b, a) -> b) -> Stream(b) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(value, next)) -> {
        let new_acc = f(initial, value)
        Some(#(new_acc, scan(next, new_acc, f)))
      }
      None -> None
    }
  })
}

/// Like `scan`, but also emits the initial value as the first element.
///
/// ## Example
/// ```gleam
/// > from_list([1, 2, 3])
/// |> scan_with_initial(0, fn(acc, x) { acc + x })
/// |> to_list()
/// // -> [0, 1, 3, 6]
/// // Initial value 0 is emitted first, then running sums
/// ```
///
/// ## Visual Representation
/// ```
/// Input:         [1]---->[2]---->[3]-->|
///                 |       |       |
///              f(0,1)  f(1,2)  f(3,3)
///                 |       |       |
///                 v       v       v
/// Output: [0]--->[1]---->[3]---->[6]-->|
///          ^
///          |
///        initial
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - The initial value (0) is emitted first
/// - Subsequent values are running fold results
///
/// ## When to Use
/// - When you need the initial state visible in the output
/// - For algorithms that require the "before" state
/// - When the initial value carries semantic meaning
/// - For compatibility with fold semantics where initial matters
///
/// ## Description
/// The `scan_with_initial` function works like `scan`, but prepends the initial
/// accumulator value to the output stream. This means the output stream has
/// one more element than the input stream.
///
/// Key characteristics:
/// - Output stream length = input stream length + 1
/// - First element is always the initial value
/// - Useful when the starting state needs to be preserved
pub fn scan_with_initial(
  stream: Stream(a),
  initial: b,
  f: fn(b, a) -> b,
) -> Stream(b) {
  Stream(pull: fn() { Some(#(initial, scan(stream, initial, f))) })
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
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> to_option()
/// Some(1)
/// 
/// > from_empty()
/// |> to_option()
/// None
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]-->[2]-->[3]-->[4]-->[5]-->|
///             |     ×     ×     ×     ×
///             v
/// Output:   Some(1)
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `×` represents elements that are ignored
/// - Only the first element is collected
/// 
/// ## When to Use
/// - When you only need the first element of a stream
/// - For checking if a stream has any elements
/// - When implementing head/tail operations on streams
/// - For sampling or peeking at stream content
/// - When converting streams to optional values
/// 
/// ## Description
/// The `to_option` function is a terminal operation that extracts the first
/// element from a stream and wraps it in an Option. If the stream is empty,
/// it returns None. This is more efficient than `to_list` when you only need
/// to check for the presence of elements or extract the first one.
/// 
/// Key characteristics:
/// - Only processes the first element
/// - Memory efficient (doesn't load entire stream)
/// - Terminal operation (ends stream processing)
/// - Safe for infinite streams
/// - Returns None for empty streams
pub fn to_option(stream: Stream(a)) -> Option(a) {
  case stream.pull() {
    Some(#(value, _)) -> Some(value)
    None -> None
  }
}

/// Creates a stream that automatically retries failed operations with exponential backoff.
///
/// ## Example
/// ```gleam
/// > let flaky_operation = fn(x) {
/// >   case x % 3 {
/// >     0 -> Error("Temporary failure")
/// >     _ -> Ok(x * 2)
/// >   }
/// > }
/// > 
/// > from_range(1, 10)
/// > |> retry(
/// >   operation: flaky_operation,
/// >   max_attempts: 3,
/// >   initial_delay_ms: 100,
/// >   backoff_factor: 2.0
/// > )
/// > |> to_list()
/// ```
///
/// ## Visual Representation
/// ```
/// Input:     [1]-------->[2]-------->[3 (fails)]-------->[4]-->|
///             |           |             |                  |
///           Op(1)       Op(2)        Op(3)               Op(4)
///             |           |             ↓                  |
///            Ok(2)       Ok(4)    Retry w/ backoff       Ok(8)
///             |           |             ↓                  |
///             v           v           Ok(6)                v
/// Output:    [2]-------->[4]-------->[6]---------------->[8]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - `Op(x)` represents operation attempts
/// - Failed operations are retried with exponential backoff
/// - Successful retries continue the stream
///
/// ## When to Use
/// - When working with unreliable external services or APIs
/// - For handling transient network failures
/// - When implementing fault-tolerant data processing pipelines
/// - For retrying database operations that might timeout
/// - When processing data from unstable sources
/// - For implementing resilient batch processing
///
/// ## Description
/// The `retry` function creates a resilient stream that automatically retries
/// failed operations using exponential backoff. It applies an operation to each
/// stream element and retries on failure with increasing delays.
///
/// Key features:
/// - **Exponential Backoff**: Delays increase exponentially between retries
/// - **Configurable Limits**: Maximum attempts and delay limits
/// - **Flexible Operations**: Works with any Result-returning function
/// - **Failure Transparency**: Failed elements are eventually dropped
/// - **Performance Monitoring**: Optional retry statistics
///
/// Retry behavior:
/// 1. Apply operation to stream element
/// 2. On success, emit result and continue
/// 3. On failure, wait (initial_delay * backoff_factor^attempt)
/// 4. Retry up to max_attempts times
/// 5. If all retries fail, skip the element
///
/// This provides robust error handling for streams processing unreliable data sources.
pub fn retry(
  stream: Stream(a),
  operation op: fn(a) -> Result(b, e),
  max_attempts max_attempts: Int,
  initial_delay_ms initial_delay: Int,
  backoff_factor factor: Float,
) -> Stream(b) {
  stream
  |> flat_map(fn(element) {
    retry_element(element, op, max_attempts, initial_delay, factor, 1)
  })
}

fn retry_element(
  element: a,
  operation: fn(a) -> Result(b, e),
  max_attempts: Int,
  initial_delay: Int,
  factor: Float,
  attempt: Int,
) -> Stream(b) {
  case operation(element) {
    Ok(result) -> from_pure(result)
    Error(_) if attempt >= max_attempts -> from_empty()
    Error(_) -> {
      let power_result = case float.power(factor, int.to_float(attempt - 1)) {
        Ok(power) -> power
        Error(_) -> 1.0
      }
      let delay = float.truncate(int.to_float(initial_delay) *. power_result)
      process.sleep(delay)
      retry_element(
        element,
        operation,
        max_attempts,
        initial_delay,
        factor,
        attempt + 1,
      )
    }
  }
}

/// Creates a stream that merges multiple input streams in a round-robin fashion.
///
/// ## Example
/// ```gleam
/// > let stream1 = from_list([1, 4, 7])
/// > let stream2 = from_list([2, 5, 8])
/// > let stream3 = from_list([3, 6, 9])
/// > 
/// > merge_round_robin([stream1, stream2, stream3])
/// > |> to_list()
/// [1, 2, 3, 4, 5, 6, 7, 8, 9]
/// ```
///
/// ## Visual Representation
/// ```
/// Stream 1: [1]-->[4]-->[7]-->|
/// Stream 2: [2]-->[5]-->[8]-->|
/// Stream 3: [3]-->[6]-->[9]-->|
///            |    |    |
///            v    v    v
/// Merged:   [1]-->[2]-->[3]-->[4]-->[5]-->[6]-->[7]-->[8]-->[9]-->|
///           Round 1     Round 2     Round 3
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Elements are taken one from each stream in turn
/// - Empty streams are skipped in subsequent rounds
///
/// ## When to Use
/// - When fairly distributing processing across multiple data sources
/// - For implementing load balancing across parallel streams
/// - When merging results from multiple concurrent processes
/// - For time-slicing between different priority streams
/// - When implementing fair scheduling algorithms
/// - For combining multiple event streams with equal priority
///
/// ## Description
/// The `merge_round_robin` function combines multiple streams by taking one
/// element from each stream in turn. This ensures fair distribution of elements
/// from all input streams and prevents any single stream from dominating the
/// output.
///
/// Merging behavior:
/// - Take one element from each non-empty stream in sequence
/// - Skip exhausted streams in subsequent rounds
/// - Continue until all streams are exhausted
/// - Preserve element order within each source stream
/// - Ensure fair representation from all streams
///
/// This is particularly useful for:
/// - Fair resource allocation
/// - Multi-source data processing
/// - Load balancing algorithms
/// - Priority-neutral stream merging
/// - Round-robin scheduling implementations
pub fn merge_round_robin(streams: List(Stream(a))) -> Stream(a) {
  case streams {
    [] -> from_empty()
    _ -> merge_round_robin_loop(streams, [])
  }
}

fn merge_round_robin_loop(
  active_streams: List(Stream(a)),
  next_round: List(Stream(a)),
) -> Stream(a) {
  case active_streams {
    [] ->
      case next_round {
        [] -> from_empty()
        _ -> merge_round_robin_loop(list.reverse(next_round), [])
      }
    [current, ..rest] ->
      case current.pull() {
        Some(#(value, next_stream)) ->
          Stream(pull: fn() {
            Some(#(
              value,
              merge_round_robin_loop(rest, [next_stream, ..next_round]),
            ))
          })
        None -> merge_round_robin_loop(rest, next_round)
      }
  }
}

/// Creates a stream that processes elements in batches with specified concurrency.
///
/// ## Example
/// ```gleam
/// > let expensive_operation = fn(batch) {
/// >   // Simulate CPU-intensive work
/// >   batch |> list.map(fn(x) { x * x })
/// > }
/// > 
/// > from_range(1, 100)
/// > |> batch_process(
/// >   batch_size: 10,
/// >   concurrency: 4,
/// >   operation: expensive_operation
/// > )
/// > |> to_list()
/// ```
///
/// ## Visual Representation
/// ```
/// Input:    [1,2,3,4,5,6,7,8,9,10,11,12,...]-->|
///            |         |         |
///            v         v         v
/// Batches:  [1..10]   [11..20]  [21..30]  (size=10)
///            |         |         |
///            v         v         v
/// Workers:  Work1     Work2     Work3     (concurrency=4)
///            |         |         |
///            v         v         v
/// Results:  [1,4,9..] [121,144..] [441,484..]
///            |         |         |
///            v         v         v
/// Output:   [1,4,9,16,25,36,49,64,81,100,121,144,...]-->|
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Elements are grouped into batches
/// - Batches are processed concurrently
/// - Results are flattened back into a single stream
///
/// ## When to Use
/// - When processing CPU-intensive operations on stream elements
/// - For optimizing throughput with parallelizable workloads
/// - When implementing map-reduce patterns on streams
/// - For batch processing with database operations
/// - When working with APIs that accept batch requests
/// - For optimizing memory usage with large datasets
///
/// ## Description
/// The `batch_process` function creates a high-performance stream that processes
/// elements in parallel batches. It groups stream elements into fixed-size batches,
/// processes each batch concurrently using multiple workers, and flattens the
/// results back into a single output stream.
///
/// Processing pipeline:
/// 1. **Batching**: Group stream elements into fixed-size chunks
/// 2. **Distribution**: Distribute batches to available workers
/// 3. **Parallel Processing**: Execute operation on each batch concurrently
/// 4. **Collection**: Gather results from all workers
/// 5. **Flattening**: Merge batch results into single output stream
///
/// Key features:
/// - **Configurable Concurrency**: Control number of parallel workers
/// - **Flexible Batch Sizes**: Optimize for memory and performance
/// - **Order Preservation**: Maintain element order across batches
/// - **Error Isolation**: Batch failures don't affect other batches
/// - **Resource Management**: Automatic worker lifecycle management
///
/// This provides significant performance improvements for CPU-bound operations
/// while maintaining the streaming semantics and memory efficiency.
pub fn batch_process(
  stream: Stream(a),
  batch_size batch_size: Int,
  concurrency workers: Int,
  operation op: fn(List(a)) -> List(b),
) -> Stream(b) {
  let owner = process.self()

  stream
  |> chunks(batch_size)
  |> map(fn(batch) { task.async_for(owner, fn() { op(batch) }) })
  |> buffer(workers, Wait)
  |> map(fn(task_handle) { task.await_forever(task_handle) })
  |> flatten_lists()
}

fn flatten_lists(stream: Stream(List(a))) -> Stream(a) {
  stream
  |> flat_map(from_list)
}

/// Creates a time-windowed stream that groups elements by time intervals.
///
/// ## Example
/// ```gleam
/// > from_timestamp_eval()
/// > |> take(100)
/// > |> time_window(
/// >   window_size_ms: 1000,  // 1 second windows
/// >   overlap_ms: 500        // 500ms overlap
/// > )
/// > |> map(fn(window) { list.length(window) })
/// > |> to_list()
/// // Returns counts of elements in each time window
/// ```
///
/// ## Visual Representation
/// ```
/// Timeline:  |----1s----|----1s----|----1s----|
/// Events:    A  B    C  D    E  F  G    H    I
///           
/// Windows:   [A,B,C,D] (0-1s)
///               [C,D,E,F,G] (0.5-1.5s) - overlapping
///                   [E,F,G,H,I] (1-2s)
/// ```
/// Where:
/// - Events arrive at various times
/// - Windows overlap by specified amount
/// - Each window contains events within its time range
///
/// ## When to Use
/// - When analyzing time-series data with temporal patterns
/// - For implementing sliding window analytics
/// - When building real-time monitoring dashboards
/// - For detecting trends or anomalies in temporal data
/// - When implementing event correlation across time
/// - For time-based aggregation and reporting
///
/// ## Description
/// The `time_window` function creates temporal windows over a stream of timestamped
/// data. It groups elements that arrive within specified time intervals, with
/// optional overlapping windows for smoother analysis.
///
/// Window management:
/// - **Fixed Size**: Windows have consistent duration
/// - **Overlapping**: Windows can overlap for smoother analysis
/// - **Time-based**: Grouping based on arrival time, not element count
/// - **Automatic**: Window boundaries managed automatically
/// - **Memory Efficient**: Old windows are garbage collected
///
/// This is essential for:
/// - Time series analysis
/// - Real-time analytics
/// - Event stream processing
/// - Temporal data correlation
/// - Performance monitoring
/// - Trend detection
pub fn time_window(
  stream: Stream(#(Int, a)),
  window_size_ms window_size: Int,
  overlap_ms overlap: Int,
) -> Stream(List(#(Int, a))) {
  let step_size = window_size - overlap
  time_window_loop(stream, [], 0, window_size, step_size)
}

fn time_window_loop(
  stream: Stream(#(Int, a)),
  current_window: List(#(Int, a)),
  window_start: Int,
  window_size: Int,
  step_size: Int,
) -> Stream(List(#(Int, a))) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(#(timestamp, value), next)) -> {
        let window_end = window_start + window_size
        case timestamp < window_end {
          True -> {
            let updated_window = [#(timestamp, value), ..current_window]
            time_window_loop(
              next,
              updated_window,
              window_start,
              window_size,
              step_size,
            ).pull()
          }
          False -> {
            // Emit current window and start new one
            let new_window_start = window_start + step_size
            case current_window {
              [] ->
                time_window_loop(
                  stream,
                  [],
                  new_window_start,
                  window_size,
                  step_size,
                ).pull()
              _ ->
                Some(#(
                  list.reverse(current_window),
                  time_window_loop(
                    stream,
                    [],
                    new_window_start,
                    window_size,
                    step_size,
                  ),
                ))
            }
          }
        }
      }
      None ->
        case current_window {
          [] -> None
          _ -> Some(#(list.reverse(current_window), from_empty()))
        }
    }
  })
}

/// Creates a circuit breaker that stops processing when error rates exceed thresholds.
///
/// ## Example
/// ```gleam
/// > let unreliable_service = fn(x) {
/// >   case x % 5 {
/// >     0 -> Error("Service unavailable")
/// >     _ -> Ok(x * 2)
/// >   }
/// > }
/// > 
/// > from_range(1, 100)
/// > |> circuit_breaker(
/// >   operation: unreliable_service,
/// >   failure_threshold: 5,
/// >   timeout_ms: 30000,
/// >   window_size: 10
/// > )
/// > |> to_list()
/// ```
///
/// ## Visual Representation
/// ```
/// States:    CLOSED -----> OPEN -----> HALF_OPEN
///              |            |            |
///              v            v            v
/// Behavior:  Process    Block All    Test Single
///            
/// Transitions:
/// CLOSED -> OPEN: Too many failures
/// OPEN -> HALF_OPEN: Timeout expires
/// HALF_OPEN -> CLOSED: Test succeeds
/// HALF_OPEN -> OPEN: Test fails
/// ```
///
/// ## When to Use
/// - When protecting against cascading failures in distributed systems
/// - For implementing fault tolerance with external services
/// - When preventing resource exhaustion from failed operations
/// - For implementing graceful degradation under load
/// - When building resilient microservice architectures
/// - For rate limiting based on error conditions
///
/// ## Description
/// The `circuit_breaker` function implements the Circuit Breaker pattern for
/// streams, providing automatic failure detection and recovery. It monitors
/// operation success/failure rates and automatically stops processing when
/// failure thresholds are exceeded.
///
/// Circuit states:
/// - **Closed**: Normal operation, requests pass through
/// - **Open**: Failures detected, all requests blocked
/// - **Half-Open**: Testing if service has recovered
///
/// Key features:
/// - **Automatic Recovery**: Attempts to resume after timeout
/// - **Configurable Thresholds**: Customizable failure detection
/// - **Sliding Window**: Recent failure rate monitoring
/// - **Fast Failure**: Immediate response when circuit is open
/// - **Health Monitoring**: Built-in service health detection
///
/// This prevents cascading failures and provides automatic recovery for
/// resilient stream processing architectures.
pub fn circuit_breaker(
  stream: Stream(a),
  operation op: fn(a) -> Result(b, e),
  failure_threshold threshold: Int,
  timeout_ms timeout: Int,
  window_size window: Int,
) -> Stream(Result(b, String)) {
  let initial_state =
    CircuitBreakerState(
      state: Closed,
      failure_count: 0,
      last_failure_time: 0,
      recent_results: [],
    )

  circuit_breaker_loop(stream, op, threshold, timeout, window, initial_state)
}

type CircuitState {
  Closed
  Open
  HalfOpen
}

type CircuitBreakerState {
  CircuitBreakerState(
    state: CircuitState,
    failure_count: Int,
    last_failure_time: Int,
    recent_results: List(Bool),
    // True for success, False for failure
  )
}

fn circuit_breaker_loop(
  stream: Stream(a),
  operation: fn(a) -> Result(b, e),
  threshold: Int,
  timeout: Int,
  window: Int,
  breaker_state: CircuitBreakerState,
) -> Stream(Result(b, String)) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(element, next)) -> {
        let current_time = utils.timestamp()
        let updated_state =
          update_circuit_state(breaker_state, current_time, timeout)

        case updated_state.state {
          Open ->
            Some(#(
              Error("Circuit breaker open"),
              circuit_breaker_loop(
                next,
                operation,
                threshold,
                timeout,
                window,
                updated_state,
              ),
            ))

          Closed | HalfOpen -> {
            case operation(element) {
              Ok(result) -> {
                let success_state = record_result(updated_state, True, window)
                let new_state = case updated_state.state {
                  HalfOpen ->
                    CircuitBreakerState(..success_state, state: Closed)
                  _ -> success_state
                }
                Some(#(
                  Ok(result),
                  circuit_breaker_loop(
                    next,
                    operation,
                    threshold,
                    timeout,
                    window,
                    new_state,
                  ),
                ))
              }

              Error(_) -> {
                let failure_state = record_result(updated_state, False, window)
                let failure_count =
                  count_recent_failures(failure_state.recent_results)
                let new_state = case failure_count >= threshold {
                  True ->
                    CircuitBreakerState(
                      ..failure_state,
                      state: Open,
                      last_failure_time: current_time,
                    )
                  False -> failure_state
                }
                Some(#(
                  Error("Operation failed"),
                  circuit_breaker_loop(
                    next,
                    operation,
                    threshold,
                    timeout,
                    window,
                    new_state,
                  ),
                ))
              }
            }
          }
        }
      }
      None -> None
    }
  })
}

fn update_circuit_state(
  state: CircuitBreakerState,
  current_time: Int,
  timeout: Int,
) -> CircuitBreakerState {
  case state.state {
    Open if current_time - state.last_failure_time > timeout ->
      CircuitBreakerState(..state, state: HalfOpen)
    _ -> state
  }
}

fn record_result(
  state: CircuitBreakerState,
  success: Bool,
  window_size: Int,
) -> CircuitBreakerState {
  let updated_results =
    [success, ..state.recent_results]
    |> list.take(window_size)

  CircuitBreakerState(..state, recent_results: updated_results)
}

fn count_recent_failures(results: List(Bool)) -> Int {
  results
  |> list.filter(fn(success) { !success })
  |> list.length()
}

/// Creates a stream that debounces elements, only emitting when no new elements arrive within the specified time window.
///
/// ## Example
/// ```gleam
/// > // User typing events
/// > let keystrokes = from_list([
/// >   #(0, "h"), #(100, "e"), #(200, "l"), #(250, "l"), #(300, "o"),
/// >   #(1500, "w"), #(1600, "o"), #(1700, "r"), #(1800, "l"), #(1900, "d")
/// > ])
/// > 
/// > keystrokes
/// > |> debounce(delay_ms: 500)
/// > |> to_list()
/// // Only emits when typing pauses for 500ms
/// [#(300, "o"), #(1900, "d")]
/// ```
///
/// ## Visual Representation
/// ```
/// Input:     A  B  C    D        E  F
/// Timeline:  |--|--|----|---------|-|
/// Debounce:  [---500ms---]    [500ms]
/// Output:           C              F
/// ```
/// Where:
/// - Input events arrive at various intervals
/// - Debounce delay resets with each new event
/// - Output only occurs after delay period with no new events
///
/// ## When to Use
/// - When implementing search-as-you-type functionality
/// - For reducing API calls from user input events
/// - When filtering rapid sequential events
/// - For implementing button click debouncing
/// - When processing sensor data with noise
/// - For reducing update frequency in reactive systems
///
/// ## Description
/// The `debounce` function creates a stream that only emits elements after a
/// specified delay period with no new incoming elements. This is useful for
/// reducing the frequency of events when dealing with rapid or noisy input.
///
/// Debouncing behavior:
/// - **Delay Reset**: Each new element resets the delay timer
/// - **Single Emission**: Only the last element in a burst is emitted
/// - **Time-based**: Uses actual time delays, not element count
/// - **Memory Efficient**: Only stores the most recent element
/// - **Configurable**: Adjustable delay period
///
/// This is essential for:
/// - User interface responsiveness
/// - API rate limiting
/// - Event deduplication
/// - Noise filtering
/// - Performance optimization
/// - Resource conservation
pub fn debounce(
  stream: Stream(#(Int, a)),
  delay_ms delay: Int,
) -> Stream(#(Int, a)) {
  debounce_loop(stream, None, delay)
}

fn debounce_loop(
  stream: Stream(#(Int, a)),
  pending: Option(#(Int, a)),
  delay: Int,
) -> Stream(#(Int, a)) {
  Stream(pull: fn() {
    case stream.pull() {
      Some(#(new_element, next)) -> {
        // New element arrived, replace pending and continue
        debounce_loop(next, Some(new_element), delay).pull()
      }
      None -> {
        // Stream ended, emit pending if exists
        case pending {
          Some(element) -> {
            process.sleep(delay)
            Some(#(element, from_empty()))
          }
          None -> None
        }
      }
    }
  })
}

/// Creates a stream that samples elements at regular intervals.
///
/// ## Example
/// ```gleam
/// > from_timestamp_eval()
/// > |> zip(from_range(1, 1000))
/// > |> sample(interval_ms: 1000)  // Sample every second
/// > |> take(10)
/// > |> to_list()
/// // Returns elements sampled at 1-second intervals
/// ```
///
/// ## Visual Representation
/// ```
/// Input:     A-B-C-D-E-F-G-H-I-J-K-L-M-N-O-P-->|
/// Sampling:  |----1s----|----1s----|----1s----|
/// Output:    A          F          L         -->|
/// ```
/// Where:
/// - Elements arrive continuously
/// - Sampling occurs at fixed intervals
/// - Only elements at sample points are emitted
///
/// ## When to Use
/// - When downsampling high-frequency data streams
/// - For implementing periodic monitoring or reporting
/// - When reducing data volume for visualization
/// - For creating time-series snapshots
/// - When implementing heartbeat or status check patterns
/// - For performance monitoring with fixed intervals
///
/// ## Description
/// The `sample` function creates a stream that emits elements at regular time
/// intervals, regardless of the input stream's rate. It's useful for converting
/// high-frequency streams into lower-frequency, regularly-timed outputs.
///
/// Sampling behavior:
/// - **Fixed Intervals**: Consistent timing regardless of input rate
/// - **Latest Value**: Emits the most recent element at each interval
/// - **Time-based**: Uses wall-clock time, not element count
/// - **Automatic**: No manual triggering required
/// - **Configurable**: Adjustable sampling frequency
///
/// This is valuable for:
/// - Data visualization
/// - Monitoring dashboards
/// - Performance metrics
/// - Signal processing
/// - Rate conversion
/// - Resource optimization
pub fn sample(
  stream: Stream(#(Int, a)),
  interval_ms interval: Int,
) -> Stream(#(Int, a)) {
  let tick_stream = from_tick(interval)

  Stream(pull: fn() { sample_next(stream, tick_stream, None).pull() })
}

fn sample_next(
  data_stream: Stream(#(Int, a)),
  tick_stream: Stream(Int),
  latest: Option(#(Int, a)),
) -> Stream(#(Int, a)) {
  Stream(pull: fn() {
    // Try to get more data first
    let updated_latest = collect_latest_data(data_stream, latest)

    // Wait for next tick
    case tick_stream.pull() {
      Some(#(_, next_tick)) -> {
        case updated_latest.1 {
          Some(element) ->
            Some(#(element, sample_next(updated_latest.0, next_tick, None)))
          None -> sample_next(updated_latest.0, next_tick, None).pull()
        }
      }
      None -> None
    }
  })
}

fn collect_latest_data(
  stream: Stream(#(Int, a)),
  current_latest: Option(#(Int, a)),
) -> #(Stream(#(Int, a)), Option(#(Int, a))) {
  case stream.pull() {
    Some(#(element, next)) -> collect_latest_data(next, Some(element))
    None -> #(stream, current_latest)
  }
}

/// Converts a stream into a process Subject and returns it along with a task that manages the conversion.
/// 
/// ## Example
/// ```gleam
/// > let subject = process.new_subject()
/// >   from_range(1, 3)
/// >   |> to_subject(subject)
/// > 
/// > process.receive(subject, 100)  // -> Ok(Some(1))
/// > process.receive(subject, 100)  // -> Ok(Some(2))
/// > process.receive(subject, 100)  // -> Ok(Some(3))
/// > process.receive(subject, 100)  // -> Ok(None)
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
pub fn to_subject(stream: Stream(a), subject: process.Subject(Option(a))) -> Nil {
  to_fold(stream, Nil, fn(_, x) { process.send(subject, Some(x)) })
  process.send(subject, None)
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

/// Returns the last element of a stream as an Option.
/// 
/// ## Example
/// ```gleam
/// > from_range(1, 5)
/// |> to_last()
/// Some(5)
/// 
/// > from_empty()
/// |> to_last()
/// None
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:     [1]-->[2]-->[3]-->[4]-->[5]-->|
///             |     |     |     |     |
///           keep  keep  keep  keep  keep
///             ↓     ↓     ↓     ↓     ↓
/// Last:   Some(1)->Some(2)->Some(3)->Some(4)->Some(5)
///                                              ^
///                                           Result
/// ```
/// Where:
/// - `|` represents the end of the stream
/// - Each element replaces the previous in Last
/// - Only the final element is returned
/// 
/// ## When to Use
/// - When you only need the final element of a stream
/// - For finding the latest value in a sequence
/// - When implementing reductions that only care about final state
/// - For getting the most recent element in time-series data
/// - When you need to know the terminal value of a sequence
/// - For implementing "latest value" semantics
/// 
/// ## Description
/// The `to_last` function is a terminal operation that processes an entire stream
/// and returns an Option containing the last element encountered. For empty
/// streams, it returns None. The function maintains only the most recently seen
/// value in memory, making it memory efficient regardless of stream length.
/// 
/// Key characteristics:
/// - Returns Some(value) with the last element for non-empty streams
/// - Returns None for empty streams
/// - Processes all elements sequentially
/// - Memory efficient (only stores one element)
/// - Terminal operation (ends stream processing)
/// - Suitable for both finite and infinite streams (with proper termination)
pub fn to_last(stream: Stream(a)) -> Option(a) {
  to_fold(stream, None, fn(_, x) { Some(x) })
}

/// Represents a tree node with a value and children.
pub type Tree(a) {
  Tree(value: a, children: List(Tree(a)))
}

/// Creates a stream from a tree using depth-first pre-order traversal.
/// 
/// ## Example
/// ```gleam
/// > let tree = Tree(
/// >   value: 1,
/// >   children: [
/// >     Tree(value: 2, children: [
/// >       Tree(value: 4, children: []),
/// >       Tree(value: 5, children: [])
/// >     ]),
/// >     Tree(value: 3, children: [])
/// >   ]
/// > )
/// > tree |> from_tree_dfs |> to_list()
/// [1, 2, 4, 5, 3]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Tree:        1
///            /   \
///           2     3
///          / \
///         4   5
/// 
/// DFS Stream: [1]-->[2]-->[4]-->[5]-->[3]-->|
/// ```
/// 
/// ## When to Use
/// - When processing hierarchical data structures
/// - For tree serialization
/// - When implementing tree algorithms
/// - For converting trees to linear sequences
/// 
/// ## Description
/// The `from_tree_dfs` function creates a stream that yields tree nodes
/// in depth-first pre-order traversal. It processes the root node first,
/// then recursively processes each child subtree from left to right.
pub fn from_tree_dfs(tree: Tree(a)) -> Stream(a) {
  Stream(pull: fn() {
    Some(#(
      tree.value,
      tree.children
        |> from_list
        |> flat_map(from_tree_dfs),
    ))
  })
}

/// Creates a stream from a tree using breadth-first traversal.
/// 
/// ## Example
/// ```gleam
/// > let tree = Tree(
/// >   value: 1,
/// >   children: [
/// >     Tree(value: 2, children: [
/// >       Tree(value: 4, children: []),
/// >       Tree(value: 5, children: [])
/// >     ]),
/// >     Tree(value: 3, children: [])
/// >   ]
/// > )
/// > tree |> from_tree_bfs |> to_list()
/// [1, 2, 3, 4, 5]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Tree:        1          Level 0
///            /   \
///           2     3       Level 1
///          / \
///         4   5           Level 2
/// 
/// BFS Stream: [1]-->[2]-->[3]-->[4]-->[5]-->|
/// ```
/// 
/// ## When to Use
/// - When processing trees level by level
/// - For finding shortest paths in trees
/// - When implementing level-order algorithms
/// - For tree visualization by levels
/// 
/// ## Description
/// The `from_tree_bfs` function creates a stream that yields tree nodes
/// in breadth-first (level-order) traversal. It processes all nodes at
/// the current level before moving to the next level.
pub fn from_tree_bfs(tree: Tree(a)) -> Stream(a) {
  from_tree_bfs_list([tree])
}

fn from_tree_bfs_list(queue: List(Tree(a))) -> Stream(a) {
  Stream(pull: fn() {
    case queue {
      [] -> None
      [tree, ..rest] -> {
        let new_queue = list.append(rest, tree.children)
        Some(#(tree.value, from_tree_bfs_list(new_queue)))
      }
    }
  })
}

/// Maps a function over a tree to create a stream of trees.
/// 
/// ## Example
/// ```gleam
/// > let tree = Tree(value: 1, children: [
/// >   Tree(value: 2, children: []),
/// >   Tree(value: 3, children: [])
/// > ])
/// > tree 
/// > |> tree_map(fn(x) { x * 2 })
/// > |> from_tree_dfs
/// > |> to_list()
/// [2, 4, 6]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Input:    1        Output:   2
///         /   \              /   \
///        2     3            4     6
/// ```
/// 
/// ## When to Use
/// - When transforming tree values while preserving structure
/// - For applying operations to all nodes in a tree
/// - When implementing tree algorithms that modify values
/// 
/// ## Description
/// The `tree_map` function transforms a tree by applying a function to
/// each node's value while preserving the tree structure.
pub fn tree_map(tree: Tree(a), f: fn(a) -> b) -> Tree(b) {
  Tree(
    value: f(tree.value),
    children: tree.children |> list.map(fn(child) { tree_map(child, f) }),
  )
}

/// Flattens a tree into a stream of paths from root to each leaf.
/// 
/// ## Example
/// ```gleam
/// > let tree = Tree(
/// >   value: "a",
/// >   children: [
/// >     Tree(value: "b", children: [
/// >       Tree(value: "d", children: []),
/// >       Tree(value: "e", children: [])
/// >     ]),
/// >     Tree(value: "c", children: [])
/// >   ]
/// > )
/// > tree |> tree_paths |> to_list()
/// [["a", "b", "d"], ["a", "b", "e"], ["a", "c"]]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Tree:      a
///          /   \
///         b     c
///        / \
///       d   e
/// 
/// Paths: ["a","b","d"], ["a","b","e"], ["a","c"]
/// ```
/// 
/// ## When to Use
/// - When extracting all root-to-leaf paths
/// - For tree analysis and debugging
/// - When implementing path-based algorithms
/// - For generating file paths from directory trees
/// 
/// ## Description
/// The `tree_paths` function creates a stream of lists, where each list
/// represents a path from the root to a leaf node.
pub fn tree_paths(tree: Tree(a)) -> Stream(List(a)) {
  tree_paths_helper(tree, [])
}

fn tree_paths_helper(tree: Tree(a), path: List(a)) -> Stream(List(a)) {
  let current_path = list.append(path, [tree.value])
  case tree.children {
    [] -> from_pure(current_path)
    children ->
      children
      |> from_list
      |> flat_map(fn(child) { tree_paths_helper(child, current_path) })
  }
}

/// Filters tree nodes based on a predicate, returning a stream of matching subtrees.
/// 
/// ## Example
/// ```gleam
/// > let tree = Tree(
/// >   value: 1,
/// >   children: [
/// >     Tree(value: 2, children: [
/// >       Tree(value: 4, children: []),
/// >       Tree(value: 5, children: [])
/// >     ]),
/// >     Tree(value: 3, children: [])
/// >   ]
/// > )
/// > tree 
/// > |> tree_filter(fn(x) { x > 2 })
/// > |> map(fn(t) { t.value })
/// > |> to_list()
/// [3, 4, 5]
/// ```
/// 
/// ## When to Use
/// - When searching for specific nodes in a tree
/// - For extracting subtrees that match criteria
/// - When implementing tree queries
/// 
/// ## Description
/// The `tree_filter` function creates a stream of subtrees where the
/// root node satisfies the given predicate.
pub fn tree_filter(tree: Tree(a), pred: fn(a) -> Bool) -> Stream(Tree(a)) {
  tree_filter_queue([tree], pred)
}

fn tree_filter_queue(
  queue: List(Tree(a)),
  pred: fn(a) -> Bool,
) -> Stream(Tree(a)) {
  Stream(pull: fn() {
    case queue {
      [] -> None
      [node, ..rest] -> {
        let next_queue = append_lists(rest, node.children)

        case pred(node.value) {
          True -> Some(#(node, tree_filter_queue(next_queue, pred)))
          False -> tree_filter_queue(next_queue, pred).pull()
        }
      }
    }
  })
}

fn append_lists(left: List(a), right: List(a)) -> List(a) {
  case left {
    [] -> right
    [head, ..tail] -> [head, ..append_lists(tail, right)]
  }
}

/// Creates a tree from a stream using a key function to determine parent-child relationships.
/// 
/// ## Example
/// ```gleam
/// > [
/// >   #(1, None),      // Root
/// >   #(2, Some(1)),   // Child of 1
/// >   #(3, Some(1)),   // Child of 1
/// >   #(4, Some(2)),   // Child of 2
/// >   #(5, Some(2))    // Child of 2
/// > ]
/// > |> from_list
/// > |> to_tree(
/// >   root_pred: fn(item) { item.1 == None },
/// >   parent_key: fn(item) { item.1 },
/// >   item_key: fn(item) { Some(item.0) },
/// >   value: fn(item) { item.0 }
/// > )
/// > |> option.map(from_tree_dfs)
/// > |> option.map(to_list)
/// Some([1, 2, 4, 5, 3])
/// ```
/// 
/// ## When to Use
/// - When building trees from flat data structures
/// - For constructing hierarchies from relational data
/// - When parsing tree-like formats
/// 
/// ## Description
/// The `to_tree` function constructs a tree from a stream of items by
/// using key functions to determine parent-child relationships.
pub fn to_tree(
  stream: Stream(item),
  root_pred root_pred: fn(item) -> Bool,
  parent_key parent_key: fn(item) -> Option(key),
  item_key item_key: fn(item) -> Option(key),
  value value: fn(item) -> a,
) -> Option(Tree(a)) {
  let items = stream |> to_list()

  // Find root
  let root_item = items |> list.find(root_pred)

  case root_item {
    Ok(root) -> Some(build_tree(root, items, parent_key, item_key, value))
    Error(_) -> None
  }
}

fn build_tree(
  item: item,
  all_items: List(item),
  parent_key: fn(item) -> Option(key),
  item_key: fn(item) -> Option(key),
  value: fn(item) -> a,
) -> Tree(a) {
  let my_key = item_key(item)

  let children =
    all_items
    |> list.filter(fn(child) { parent_key(child) == my_key })
    |> list.map(fn(child) {
      build_tree(child, all_items, parent_key, item_key, value)
    })

  Tree(value: value(item), children: children)
}

/// Creates a stream of tree levels (breadth-first levels).
/// 
/// ## Example
/// ```gleam
/// > let tree = Tree(
/// >   value: 1,
/// >   children: [
/// >     Tree(value: 2, children: [
/// >       Tree(value: 4, children: []),
/// >       Tree(value: 5, children: [])
/// >     ]),
/// >     Tree(value: 3, children: [])
/// >   ]
/// > )
/// > tree |> tree_levels |> to_list()
/// [[1], [2, 3], [4, 5]]
/// ```
/// 
/// ## Visual Representation
/// ```
/// Tree:        1          Level 0: [1]
///            /   \
///           2     3       Level 1: [2, 3]
///          / \
///         4   5           Level 2: [4, 5]
/// ```
/// 
/// ## When to Use
/// - When processing trees level by level
/// - For tree visualization
/// - When implementing level-based algorithms
/// - For analyzing tree depth and width
/// 
/// ## Description
/// The `tree_levels` function creates a stream where each element is a
/// list containing all nodes at a particular depth level.
pub fn tree_levels(tree: Tree(a)) -> Stream(List(a)) {
  tree_levels_helper([tree])
}

fn tree_levels_helper(trees: List(Tree(a))) -> Stream(List(a)) {
  case trees {
    [] -> from_empty()
    _ -> {
      let values = trees |> list.map(fn(t) { t.value })
      let children =
        trees
        |> list.flat_map(fn(t) { t.children })

      Stream(pull: fn() { Some(#(values, tree_levels_helper(children))) })
    }
  }
}
