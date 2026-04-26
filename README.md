# mcpm

A Minecraft mod package manager. Manages Fabric mods for Minecraft servers
using a declarative YAML configuration file (`mcpm.yml`).

## Usage

mcpm operates on a `mcpm.yml` file in your Minecraft server directory. The
config declares your Minecraft version, mod loader, and the mods you want:

```yaml
minecraft_version: 1.21.8
loader: fabric
mods:
  - project_id: P7dR8mSH
    name: Fabric API
    type: client_and_server
    is_platform: true
  - project_id: 6AQIaxuO
    name: WTHIT
    type: client_and_server
    depends_on:
      - P7dR8mSH
```

### Commands

```
mcpm install              Install all mods from mcpm.yml
mcpm add --query <name>   Search for and add a mod
mcpm update <mod_id>      Update a specific mod to latest compatible version
mcpm outdated             Check for outdated mods
mcpm upgrade [--dry-run]  Check if a Minecraft version upgrade is possible
mcpm fmt                  Format the mcpm.yml configuration file
mcpm help [command]       Show help
```

All commands accept `--dir <path>` to specify the server directory (defaults
to the current directory).

Mod metadata is resolved from [Modrinth](https://modrinth.com/).

## Development

### Setup

This project uses [devenv](https://devenv.sh/) for development. With devenv
installed:

```bash
devenv shell
```

This gives you Ruby 4.0, bundler, and all dependencies.

### Running Tests

```bash
devenv tasks run mcpm:test                        # run all tests
devenv tasks run mcpm:test test/example_test.rb   # run a single file
```

---

## Incremental Test Builds

> **For contributors.** This section documents an experimental system that
> treats tests like incremental compilation — only re-running tests whose
> source dependencies have changed.

mcpm models each test as a Nix derivation whose inputs are the source files
it depends on. If none of those files change, the test result is cached in the
Nix store and the test doesn't re-run.

This is powered by two systems working together:

1. **Dependency tracing** — [Rotoscope](https://github.com/Shopify/rotoscope)
   + `$LOADED_FEATURES` diffing to discover which source files each test
   actually touches at runtime
2. **Nix derivations** — each test becomes a content-addressed Nix derivation
   whose inputs are its traced dependencies; Nix's store handles caching

### Quick Start

```bash
# 1. Trace all test dependencies (writes .test-deps/*.json)
bin/trace-deps --all

# 2. Compile traced deps into a Nix manifest
bin/compile-test-deps

# 3. Run tests — only changed tests execute
nix build .#tests --print-build-logs
```

On the first run, all tests execute. On subsequent runs, only tests whose
source dependencies changed will re-run. Everything else is served from the
Nix store cache (~0.6s for a fully cached run).

### How It Works

#### Dependency Tracing

`bin/trace-deps` runs each test in isolation and records every project-local
file that was loaded during execution. It uses two complementary strategies:

- **Rotoscope** traces method calls and captures `caller_path` — the file
  where each call originates
- **`$LOADED_FEATURES` diffing** catches files that were `require`'d but
  may not have had methods called on them

Each test is traced in a **subprocess** to ensure a clean `$LOADED_FEATURES`
(see [Ruby::Box mode](#rubybox-experimental) for an in-process alternative).

The output is a set of JSON files in `.test-deps/`:

```json
{
  "test_file": "test/mcpm/commands/install_test.rb",
  "deps": [
    "lib/mcpm/commands/install.rb",
    "lib/mods/downloader.rb",
    "lib/mods/mods.rb",
    "lib/mods/updater.rb",
    "lib/utility/yaml.rb",
    "test/mcpm/commands/install_test.rb",
    "test/test_helper.rb"
  ],
  "traced_at": "2026-04-26T13:45:44Z"
}
```

#### Tiered Dependencies

`bin/compile-test-deps` reads the traced JSON and generates `nix/test-deps.nix`
with a two-tier structure:

- **Tier 1 (shared):** Dependencies from `test_helper.rb` — loaded by every
  test. Changing these invalidates all test caches.
- **Tier 2 (per-test):** The delta between a test's full deps and the shared
  set. Changing `lib/mcpm/commands/outdated.rb` only invalidates `outdated_test`.

```
Shared (tier 1):          Per-test (tier 2):
  test/test_helper.rb       install_test → install.rb, downloader.rb, mods.rb, ...
  lib/mods/modrinth.rb      outdated_test → outdated.rb
  lib/mods/minecraft_version.rb  upgrade_test → upgrade.rb
```

#### Nix Derivations

`flake.nix` maps each test to a Nix derivation whose `src` is the precise
set of files from its dependency manifest. Nix's content-addressed store means:

| What changed | What re-runs |
|---|---|
| `lib/mcpm/commands/outdated.rb` | Only `outdated_test` |
| `lib/mods/mods.rb` | Tests that depend on it (install, outdated, upgrade, mod_config_cache) |
| `test/test_helper.rb` | All tests (shared tier 1 dep) |
| Nothing | Nothing (~0.6s) |

### When to Re-trace

The dependency graph needs to be re-traced when:

- **A test file changes** — it might have new `require` statements
- **Any file in a test's dep graph changes** — it might add a `require`
  (e.g., `install.rb` starts requiring a new module)
- **`test_helper.rb` changes** — re-trace tier 1, then diff; only cascade
  to per-test re-tracing if the shared dep set actually changed

For now, re-tracing is manual (`bin/trace-deps --all`). A future improvement
would be to detect stale traces by comparing file mtimes or git SHAs against
the `traced_at` timestamps.

### Ruby::Box (Experimental)

`bin/trace-deps` supports an experimental `--box` mode that uses
[Ruby::Box](https://docs.ruby-lang.org/en/master/Ruby/Box.html) for
in-process isolation instead of subprocesses:

```bash
RUBY_BOX=1 ruby bin/trace-deps --all --box
```

Ruby::Box (introduced in Ruby 4.0, `RUBY_BOX=1` env var) provides isolated
`$LOADED_FEATURES`, constants, and global variables per box — exactly what's
needed for dependency tracing without fork overhead.

**How it works:**

1. All native extensions (json, psych, zlib, openssl, etc.) are pre-loaded
   in the main box before any test boxes are created
2. Each test gets its own `Ruby::Box.new` with the project's load paths
3. `$LOADED_FEATURES` is diffed before/after `box.load(test_file)` to
   capture dependencies
4. Each box sees a fresh Ruby environment — no cross-contamination between
   tests

**Current limitations (Ruby 4.0.x):**

- The Box copy-on-write (CoW) mechanism copies native `.bundle`/`.so` files
  for each new box, which can cause crashes after several boxes are created
  (`"Installing native extensions may fail under RUBY_BOX=1"`)
- Pre-loading native extensions in the main box reduces but doesn't eliminate
  this — the VM still CoW's extension metadata per box
- In testing, the mechanism successfully traced all 5 test files before
  crashing on process cleanup, producing correct results identical to
  subprocess mode

**When Box stabilizes**, it would eliminate ~200ms of subprocess startup per
test during tracing — significant at scale (hundreds of tests).

### File Overview

```
bin/trace-deps          # Trace test dependencies (Rotoscope + $LOADED_FEATURES)
bin/compile-test-deps   # Compile .test-deps/*.json → nix/test-deps.nix
.test-deps/             # Cached dependency graphs (JSON)
nix/test-deps.nix       # Auto-generated Nix manifest (do not edit)
flake.nix               # Nix flake with per-test derivations
gemset.nix              # Nix gem environment (generated by bundix)
```
