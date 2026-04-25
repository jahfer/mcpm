# MCPM Feature Ideas

## Mod management improvements

### Automatic dependency discovery when adding mods
- **Current gap:** `depends_on` is always written as an empty list in `add`.
- **Feature idea:** inspect Modrinth dependency metadata and pre-populate `depends_on` where possible.
- **Benefit:** Better upgrade planning and dependency awareness.

### Smarter mod selection flow
- Improve `add` search results with:
  - richer summaries
  - loader/version compatibility display
  - dependency indicators
  - optional side support notes
- Could also offer non-interactive selection flags for scripting.

### Better outdated reporting
- Show a richer report with:
  - installed version
  - latest compatible version
  - latest overall version
  - why an upgrade is blocked (loader, MC version, dependency)
- Could optionally export machine-readable output.

### Upgrade impact analysis
- Before applying an upgrade, show:
  - which mods will upgrade cleanly
  - which mods have no compatible target version
  - which optional mods are blocking upgrade
  - dependency/platform bottlenecks
- This would make `upgrade` more of a planner, not just an action.

## Safety and reliability

### Atomic single-mod updates
- Reuse the safer temp-download-and-swap flow for `update`.
- Include rollback if the final replace fails.

### Configurable retries/timeouts for network calls
- Add retry/backoff and timeout settings for Modrinth API and downloads.
- Could be exposed in config or environment variables.

### Backup/retention policy support
- The fixture suggests backup-related config exists (`auto_backup`, `max_backups`) but core code does not seem to use it meaningfully.
- Feature idea:
  - enable auto backups before destructive changes
  - honor max backup retention
  - list/restore backups

## Usability

### Dry-run support beyond current commands
- Expand dry-run behavior to more workflows:
  - `install`
  - `add`
  - full upgrade/download plans
- Show exactly what would change without modifying disk.

### Structured output mode
- Add JSON output for commands like:
  - `outdated`
  - `upgrade`
  - `install`
- Useful for automation and CI.

### Better unmanaged-mod reporting
- Upgrade already reports undeclared JARs.
- Extend this into a dedicated command or report mode to:
  - detect stray files
  - suggest matching declarations
  - optionally import them into config

### Configuration linting command
- Add a lint/check command for `mcpm.yml` that validates:
  - required fields
  - type values
  - dependency references
  - regex patterns
  - duplicate project IDs

## Longer-term ideas

### Provider abstraction beyond Modrinth
- Introduce a source/provider interface so MCPM is not tightly coupled to Modrinth.
- Could enable alternative ecosystems or internal mirrors.

### Local metadata/index caching
- Cache remote metadata to reduce repeated API calls and improve speed.
- Combine with expiration and forced refresh options.

### Upgrade recommendations engine
- When a full upgrade is blocked, suggest practical next steps:
  - remove optional blockers
  - replace abandoned mods
  - pin to nearest compatible Minecraft version
