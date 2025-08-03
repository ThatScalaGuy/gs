# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0-beta.1] - next

### Added

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
