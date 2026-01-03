import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

/// Configuration for the worker pool
pub type WorkerPoolConfig {
  WorkerPoolConfig(
    /// Number of concurrent workers
    concurrency: Int,
    /// Whether to preserve input order in output
    preserve_order: Bool,
  )
}

/// Messages for the result collector
pub type CollectorMessage(b) {
  /// A worker completed with a result
  WorkerResult(seq: Int, result: b)
  /// Get the next result (blocks until available)
  GetNext(reply: Subject(Option(b)))
  /// Signal all work has been submitted
  AllSubmitted(total: Int)
}

/// State for the result collector
type CollectorState(b) {
  CollectorState(
    /// Results by sequence for ordered output
    results_ordered: Dict(Int, b),
    /// Results as list for unordered output
    results_unordered: List(b),
    /// Next sequence to emit (ordered mode)
    next_emit: Int,
    /// Total expected results (-1 if unknown)
    total_expected: Int,
    /// Number of results received
    received_count: Int,
    /// Waiters for results
    waiters: List(Subject(Option(b))),
    /// Whether to preserve order
    preserve_order: Bool,
  )
}

/// A worker pool for parallel stream processing
pub type WorkerPool(a, b) {
  WorkerPool(
    collector: Subject(CollectorMessage(b)),
    config: WorkerPoolConfig,
    mapper: fn(a) -> b,
  )
}

/// Start a new worker pool
pub fn start(
  config: WorkerPoolConfig,
  mapper: fn(a) -> b,
) -> Result(WorkerPool(a, b), actor.StartError) {
  let initial_state =
    CollectorState(
      results_ordered: dict.new(),
      results_unordered: [],
      next_emit: 0,
      total_expected: -1,
      received_count: 0,
      waiters: [],
      preserve_order: config.preserve_order,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_collector_message)
  |> actor.start
  |> result.map(fn(started) {
    WorkerPool(collector: started.data, config: config, mapper: mapper)
  })
}

fn handle_collector_message(
  state: CollectorState(b),
  msg: CollectorMessage(b),
) -> actor.Next(CollectorState(b), CollectorMessage(b)) {
  case msg {
    WorkerResult(seq, result) -> handle_worker_result(state, seq, result)
    GetNext(reply) -> handle_get_next(state, reply)
    AllSubmitted(total) -> handle_all_submitted(state, total)
  }
}

fn handle_worker_result(
  state: CollectorState(b),
  seq: Int,
  result: b,
) -> actor.Next(CollectorState(b), CollectorMessage(b)) {
  // Store result
  let state = case state.preserve_order {
    True ->
      CollectorState(
        ..state,
        results_ordered: dict.insert(state.results_ordered, seq, result),
      )
    False ->
      CollectorState(..state, results_unordered: [
        result,
        ..state.results_unordered
      ])
  }
  let state = CollectorState(..state, received_count: state.received_count + 1)

  // Try to satisfy waiters
  let state = try_satisfy_waiters(state)

  actor.continue(state)
}

fn handle_get_next(
  state: CollectorState(b),
  reply: Subject(Option(b)),
) -> actor.Next(CollectorState(b), CollectorMessage(b)) {
  case try_get_result(state) {
    Some(#(result, new_state)) -> {
      process.send(reply, Some(result))
      actor.continue(new_state)
    }
    None -> {
      // Check if we're done
      case is_complete(state) {
        True -> {
          process.send(reply, None)
          actor.continue(state)
        }
        False -> {
          // Add to waiters
          actor.continue(
            CollectorState(
              ..state,
              waiters: list.append(state.waiters, [reply]),
            ),
          )
        }
      }
    }
  }
}

fn handle_all_submitted(
  state: CollectorState(b),
  total: Int,
) -> actor.Next(CollectorState(b), CollectorMessage(b)) {
  let state = CollectorState(..state, total_expected: total)
  // Try to satisfy waiters in case we're already done
  let state = try_satisfy_waiters(state)
  actor.continue(state)
}

fn try_get_result(state: CollectorState(b)) -> Option(#(b, CollectorState(b))) {
  case state.preserve_order {
    True -> {
      case dict.get(state.results_ordered, state.next_emit) {
        Ok(result) -> {
          Some(#(
            result,
            CollectorState(
              ..state,
              results_ordered: dict.delete(
                state.results_ordered,
                state.next_emit,
              ),
              next_emit: state.next_emit + 1,
            ),
          ))
        }
        Error(_) -> None
      }
    }
    False -> {
      case state.results_unordered {
        [result, ..rest] ->
          Some(#(result, CollectorState(..state, results_unordered: rest)))
        [] -> None
      }
    }
  }
}

fn is_complete(state: CollectorState(b)) -> Bool {
  state.total_expected >= 0 && state.received_count >= state.total_expected
}

fn try_satisfy_waiters(state: CollectorState(b)) -> CollectorState(b) {
  case state.waiters {
    [] -> state
    [waiter, ..rest] -> {
      case try_get_result(state) {
        Some(#(result, new_state)) -> {
          process.send(waiter, Some(result))
          try_satisfy_waiters(CollectorState(..new_state, waiters: rest))
        }
        None -> {
          case is_complete(state) {
            True -> {
              // Signal completion to all waiters
              list.each(state.waiters, fn(w) { process.send(w, None) })
              CollectorState(..state, waiters: [])
            }
            False -> state
          }
        }
      }
    }
  }
}

/// Submit a work item to the pool
/// This spawns a worker process that will send results to the collector
pub fn submit(pool: WorkerPool(a, b), seq: Int, item: a) -> Nil {
  let collector = pool.collector
  let mapper = pool.mapper

  process.spawn(fn() {
    let result = mapper(item)
    process.send(collector, WorkerResult(seq, result))
  })

  Nil
}

/// Signal that all work has been submitted
pub fn signal_complete(pool: WorkerPool(a, b), total_items: Int) -> Nil {
  process.send(pool.collector, AllSubmitted(total_items))
}

/// Get the next result from the pool (blocks until available or complete)
pub fn get_result(pool: WorkerPool(a, b)) -> Option(b) {
  process.call_forever(pool.collector, GetNext)
}

/// Process a stream with bounded parallelism
/// Returns a stream of results
pub fn process_stream(
  pool: WorkerPool(a, b),
  items: List(a),
  concurrency: Int,
) -> List(b) {
  // Submit all items with sequence numbers
  let indexed = list.index_map(items, fn(item, idx) { #(idx, item) })

  // Submit work in batches to limit concurrency
  submit_with_concurrency(pool, indexed, concurrency, 0)

  // Signal completion
  signal_complete(pool, list.length(items))

  // Collect results
  collect_results(pool, [])
}

fn submit_with_concurrency(
  pool: WorkerPool(a, b),
  items: List(#(Int, a)),
  max_concurrent: Int,
  active: Int,
) -> Nil {
  case items {
    [] -> Nil
    [#(seq, item), ..rest] -> {
      submit(pool, seq, item)
      let new_active = active + 1

      // If we've hit max concurrency, wait for a result before continuing
      case new_active >= max_concurrent {
        True -> {
          // Wait for one result to come back
          case get_result(pool) {
            Some(_) ->
              submit_with_concurrency(
                pool,
                rest,
                max_concurrent,
                new_active - 1,
              )
            None -> Nil
          }
        }
        False -> submit_with_concurrency(pool, rest, max_concurrent, new_active)
      }
    }
  }
}

fn collect_results(pool: WorkerPool(a, b), acc: List(b)) -> List(b) {
  case get_result(pool) {
    Some(result) -> collect_results(pool, list.append(acc, [result]))
    None -> acc
  }
}

/// Simple bounded parallel map over a list
pub fn par_map_list(
  items: List(a),
  concurrency: Int,
  preserve_order: Bool,
  mapper: fn(a) -> b,
) -> Result(List(b), actor.StartError) {
  let config =
    WorkerPoolConfig(concurrency: concurrency, preserve_order: preserve_order)

  use pool <- result.try(start(config, mapper))

  // Submit all items
  list.index_map(items, fn(item, idx) { submit(pool, idx, item) })

  // Signal complete
  signal_complete(pool, list.length(items))

  // Collect results
  Ok(collect_results(pool, []))
}
