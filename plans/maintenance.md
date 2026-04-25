# MCPM Maintenance Plan

## Refactors

### Split `lib/mods/mods.rb` into focused classes
- **Current issue:** One file mixes models, config parsing, validation, filesystem access, JAR inspection, and update logic.
- **Suggested split:**
  - `lib/mods/mod_config.rb`
  - `lib/mods/mod_declaration.rb`
  - `lib/mods/installed_mod.rb`
  - `lib/mods/version_info.rb`
  - `lib/mods/jar_inspector.rb`
- **Benefits:** Easier testing, clearer ownership, lower coupling.

### Introduce a shared command base
- **Current issue:** Every command duplicates:
  - `--dir` option
  - `File.expand_path`
  - `mod_config(dir)` helper
- **Suggested refactor:** create `MCPM::Commands::Base` or a shared mixin for common options/helpers.
- **Benefits:** Less duplication, more consistent command behavior.

### Properly namespace all commands
- **Current issue:** command classes are top-level (`Add`, `Install`, etc.).
- **Suggested refactor:** define them under `MCPM::Commands`.
- **Benefits:** Avoids global namespace pollution and makes constant loading cleaner.

### Move business logic out of command classes
- **Current issue:** commands, especially `upgrade`, mix UI rendering with domain logic.
- **Suggested services:**
  - `UpgradePlanner`
  - `InstallPlanner`
  - `VersionChecker`
  - `ModSelection` / `AddFlow`
- **Benefits:** Better testability and smaller commands.

### Finish centralizing cache invalidation in `ModConfig`
- **Current issue:** JAR cache invalidation is now centralized, but other memoized state is still reset manually.
- **Suggested refactor:** extend the cache API into a broader `invalidate_caches!`/targeted invalidation strategy.
- **Remaining caches to unify:**
  - `@config_data`
  - `@mod_declarations`
  - `@dependents_of`
- **Benefits:** Fewer stale-state bugs and less duplicated reset logic.

### Extract version logic into a dedicated component
- **Current issue:** normalization, compatibility, and update comparisons are scattered.
- **Suggested refactor:** add a `VersionResolver` / `VersionPolicy` object.
- **Benefits:** Easier reasoning and safer upgrade decisions.

### Unify HTTP access
- **Current issue:** `modrinth.rb` and `downloader.rb` both hand-roll HTTP calls.
- **Suggested refactor:** shared HTTP client wrapper for:
  - headers
  - timeouts
  - retries
  - logging
  - error mapping
- **Benefits:** Consistent network behavior and easier debugging.

## Cleanup

### Replace `puts`/`exit` inside library code with exceptions
- **Current issue:** lower-level classes print and terminate the process.
- **Suggested cleanup:** raise typed errors from library/service layers; let commands format output and exit.
- **Benefits:** Better reuse and easier tests.

### Tighten rescue clauses
- Replace broad `rescue => e` / bare `rescue` with targeted error classes where possible.
- Preserve backtraces and root causes.

### Remove dead or unused utilities
- `Utility::YAML.load_file` appears unused.
- Decide whether to remove it or route all YAML reads through it.

### Review gem dependencies
- Audit whether explicit gems are needed for items typically available through Ruby stdlib/default gems:
  - `net-http`
  - `json`
  - `fileutils`
  - `yaml`
  - `openssl`
- Keep only what is truly required.

### Standardize output style
- Some commands use `puts`, others `CLI::UI.fmt`, others spinners/frames.
- Standardize success/warning/error output patterns.

### Fix minor wording/consistency issues
- Error messages should consistently refer to `mcpm.yml`.
- User-Agent strings should be consistent across network code.
- Remove leftover debug logging.

## Test maintenance

### Expand unit coverage around core logic
- Focus on:
  - version normalization/comparison
  - cache invalidation
  - missing/ambiguous JAR handling
  - config validation
  - updater failure behavior

### Test service objects instead of CLI-heavy paths
- Once logic is extracted from commands, write focused tests against service classes.
- Keep command tests narrower and oriented around argument flow/output.

### Stub external API calls consistently
- Modrinth interactions should be isolated in tests.
- Avoid tests that depend on real network responses.
