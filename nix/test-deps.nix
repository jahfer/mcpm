# Test dependency manifest
#
# Maps each test file to its source dependencies.
# When any source file (or the test itself, or shared infra like
# test_helper.rb / fixtures) changes, Nix invalidates the cached
# test result and re-runs it. Unchanged tests are skipped.
#
# Think of this like a Makefile: test_file : src_deps
#
# TODO: Auto-generate this from `require` statements or runtime tracing.

{
  "test/example_test.rb" = {
    srcs = [
      # example_test only requires test_helper (shared infra, auto-included)
      # No additional source deps — it tests CLI::Kit::System directly
    ];
  };
}
