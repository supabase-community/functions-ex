# Changelog

## [Unreleased]

### Added
- Dynamic auth token updates feature for better token rotation support
  - `Supabase.Functions.update_auth/2` function for functional client updates
  - `:auth` option in `Supabase.Functions.invoke/3` for per-request auth token overrides
  - Feature parity with JavaScript client's `setAuth(token)` method
  - Comprehensive test coverage for both update methods
- Enhanced documentation with examples for both auth update approaches
