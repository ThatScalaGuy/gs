# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2. Oct 2024

### Changed

- Migrated queue and parallel map actors to the Gleam 1.1 builder API, ensuring compatibility with current `gleam_otp`.
- Upgraded runtime dependencies to `gleam_erlang` 1.3.0 and `gleam_otp` 1.1.0.
- Updated examples to use `io.println(string.inspect(...))` instead of the deprecated `io.debug/1` helper.
- Adjusted `tree_filter/2` traversal to return matches in breadth-first order, aligning output with documented expectations.
- Optimised `chunks/2` to track chunk size without repeated length checks, reducing per-element overhead for large streams.
- Optimised `window/2` to reuse window counts and avoid repeated list traversals while sliding, improving performance of moving-window workloads.

### Fixed

- Ensured `buffer/3` instantiates its queue once per buffered stream and treats non-positive capacities as pass-through, preventing actor leaks and making the API more predictable.

- Prevented buffered streams and parallel pipelines from leaking actors by reusing a single queue per stream and scoping async tasks to the caller process.

### Added

- Introduced internal `task` helper module with lightweight async utilities, replacing the removed `gleam/otp/task` dependency.
- Add `bracket` pipe function
- Add `filter_with_previous` pipe function
- Add `to_last` sink function
- Add `Tree` type for representing hierarchical data structures
- Add `from_tree_dfs` source function for depth-first tree traversal
- Add `from_tree_bfs` source function for breadth-first tree traversal
- Add `tree_map` function for transforming tree values
- Add `tree_paths` function for extracting root-to-leaf paths
- Add `tree_filter` function for filtering tree nodes based on predicates
- Add `tree_levels` function for grouping tree nodes by depth level
- Add `to_tree` sink function for constructing trees from flat data structures

### Changed

- Add actor based par_map implementation
- Refactor `from_tree_bfs` to use simple list instead of queue for better performance

## [1.0.0] - 7. Jan 2024

### Added

- Add `from_state_eval` source function
- Add `rate_limit_linear` pipe function
- Add `rate_limit_backoff` pipe function
  = Add `count` pipe function
- Add `window` pipe function
- Add `buffer` pipe function

### Changed

- None

### Deprecated

- None

### Removed

- None

### Fixed

- None

### Security

- None
