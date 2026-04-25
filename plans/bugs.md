# MCPM Bug List

## High priority

### Version compatibility fallback is likely broken
- **File:** `lib/mods/minecraft_version.rb`
- **Problem:** `MinecraftVersion.compatible_version` uses `PATCHFIX_VERSIONS.rassoc(version)`, which returns a key/value pair instead of a `MinecraftVersion`.
- **Impact:** Fallback logic in update/version lookup may return the wrong type or behave unexpectedly.
- **Used by:**
  - `lib/mods/mods.rb`
  - `lib/mods/modrinth.rb`

### `latest_version_supported` can call methods on `nil`
- **File:** `lib/mods/minecraft_version.rb`
- **Problem:** `lists.reduce(...).max.normalized` assumes `.max` is non-nil.
- **Impact:** If there is no common version across lists, this can raise unexpectedly.

### Update comparison is too naive
- **File:** `lib/mods/mods.rb`
- **Problem:** `can_update?` compares version strings directly.
- **Known symptom:** Already noted in source for cases like `0.25.7` vs `fabric-1.21.10-0.25.7`.
- **Impact:** False positives for updates.

### `add` command can continue with a nil selection
- **File:** `lib/mcpm/commands/add.rb`
- **Problem:** `choose` returns early when there are no search results, but `invoke` still calls `config.add_mod!(mod)`.
- **Impact:** Possible runtime error when no mods are found.

### Modrinth supported-version cache key is incomplete
- **File:** `lib/mods/modrinth.rb`
- **Problem:** `fetch_supported_versions` cache key includes project ID and loader, but not `minecraft_version`.
- **Impact:** Incorrect cached results when the same project is queried with different version filters.

## Medium priority

### Updater errors are swallowed
- **File:** `lib/mods/updater.rb`
- **Problem:** `attempt_update` rescues `Mods::Updater::Error` without surfacing it.
- **Impact:** Failures become harder to diagnose and may lead to confusing CLI behavior.

### Concurrent mutation of shared state
- **Files:**
  - `lib/mcpm/commands/install.rb`
  - `lib/mcpm/commands/outdated.rb`
- **Problem:** Parallel work mutates shared arrays/hashes directly.
- **Impact:** Potential race conditions or nondeterministic output if execution is truly concurrent.

### Broad rescue clauses hide root causes
- **Files:** multiple
- **Examples:**
  - `lib/mods/downloader.rb`
  - `lib/mods/mods.rb`
  - `lib/mcpm/commands/upgrade.rb`
- **Impact:** Harder debugging and less precise recovery behavior.

## Low priority

### Leftover debug output in `add`
- **File:** `lib/mcpm/commands/add.rb`
- **Problem:** `puts "results: #{results.inspect}"`
- **Impact:** Noisy CLI output.

### Error message references `mods.yml` instead of `mcpm.yml`
- **File:** `lib/mods/mods.rb`
- **Problem:** Invalid-config error text mentions the wrong file name.
- **Impact:** Confusing diagnostics.
