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
bin/testunit                                      # run all tests
bin/testunit test/mcpm/commands/install_test.rb   # run a single file
bin/testunit --affected lib/mods/updater.rb       # run only affected methods
bin/testunit --watch                              # watch for changes
```

---

## Incremental Test Running

> **For contributors.** This section documents the system that runs only the
> test methods whose source dependencies have actually changed.

### How It Works

Each test method is traced with [Rotoscope](https://github.com/Shopify/rotoscope)
to discover which source files have code that **actually executes** during that
method. File-level `require` is ignored — only runtime calls matter. If a file
is loaded but no code in it runs during a test method, changing that file won't
trigger that method.

#### Tracing

`bin/trace-deps` runs each test in an isolated subprocess and wraps every test
method with Rotoscope. setup/teardown are traced separately as shared deps for
all methods in a class.

```bash
bin/trace-deps --all        # trace every test file
bin/trace-deps test/foo.rb  # trace a single file
```

Output is per-method JSON in `.test-deps/`:

```json
{
  "test_file": "test/mod_config_cache_test.rb",
  "method": "ModConfigCacheTest#test_apply_updates",
  "type": "test",
  "deps": ["lib/mods/mods.rb", "lib/mods/updater.rb", "test/mod_config_cache_test.rb"],
  "dep_hashes": {
    "lib/mods/mods.rb": "d874035...",
    "lib/mods/updater.rb": "a1b2c3d...",
    "test/mod_config_cache_test.rb": "d012bb2..."
  },
  "boot_deps": ["lib/mods/downloader.rb", "lib/mods/modrinth.rb", "..."],
  "setup": "ModConfigCacheTest#_setup"
}
```

- **deps** — files whose code ran during this method (Rotoscope `caller_path`)
- **dep_hashes** — SHA256 of each dep at trace time (for staleness detection)
- **boot_deps** — files loaded via `require` at file load time (needed to run
  but not for invalidation)
- **setup** — reference to the shared setup/teardown trace for this class

#### Affected Resolution

`bin/testunit --affected` reads the dep graph and runs only methods whose
runtime deps include the changed files:

```bash
$ bin/testunit --affected lib/mods/updater.rb
Running 1 affected method(s):
  ModConfigCacheTest#test_apply_updates_invalidates_the_cached_jar_list_after_replacing_the_mods_directory

# (the other 2 ModConfigCacheTest methods don't call updater.rb at runtime — skipped)
```

Individual methods are run via minitest's `--name` flag.

#### Content Hashing & Self-Healing

Each dep stores a SHA256 content hash from when it was traced. On `--affected`:

1. Find methods whose deps include the changed files
2. Check if any dep's current hash differs from the traced hash
3. **If stale** — the dep graph might be outdated (a `require` could have been
   added). The method is re-traced inline during execution: Rotoscope wraps the
   test, captures the new dep graph, and writes it back to `.test-deps/`.
4. **If fresh** — just run the test, no tracing overhead.

This makes the dep graph **self-healing** — it converges to accuracy through
normal use. After the initial `bin/trace-deps --all`, you rarely need to
re-trace manually.

#### Watch Mode

```bash
bin/testunit --watch
```

Polls `lib/` and `test/` for mtime changes, runs affected methods in a
subprocess on each change. Stale methods are re-traced inline automatically.

### Ruby::Box (Experimental)

`bin/trace-deps` supports an experimental `--box` mode that uses
[Ruby::Box](https://docs.ruby-lang.org/en/master/Ruby/Box.html) for
in-process isolation instead of subprocesses:

```bash
RUBY_BOX=1 ruby bin/trace-deps --all --box
```

Each test gets its own `Ruby::Box.new` with isolated `$LOADED_FEATURES`.
All native extensions are pre-loaded in the main box to work around the CoW
mechanism in Ruby 4.0.x, which can crash after several boxes are created.
When Box stabilizes, it would eliminate subprocess overhead during tracing.

### File Overview

```
bin/trace-deps      # Trace per-method runtime deps (Rotoscope)
bin/testunit        # Test runner with --affected, --watch
.test-deps/         # Cached per-method dependency graphs (JSON)
```
