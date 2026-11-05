# Automation: the `nxforge` command line and MCP server

`scripts/nxforge.py` runs the converter app's core functions from a terminal, a scheduled job or an agent: status, builds and rebuilds (with the `--plan` dry run), background build jobs, engine updates, a tool check, and a disk report with cleanup. `scripts/nxforge_mcp.py` offers the same functions as tools of an [MCP](https://modelcontextprotocol.io) server. Both use the standard library only, so any `python3` runs them.

They read the converter's own state, so the app and the command line agree: `settings.json` and `builds.json` in `~/Library/Application Support/NXForge Converter` (`NXC_SUPPORT_DIR` moves it, as for the app), the engine checkout named by the `repo` setting, the game folders of the recorded builds, and the `<title ID>_build` folders in them, beside them, and at the top of `~/Documents`, `~/Downloads` and `~/Desktop` (a Switch 2 dump's build folder can sit there). A build started here is recorded in `builds.json` as one from the app is, and a rebuild moves the old app to `app-backups/` first.

## Commands

Every command takes `--json` (before the command) for one JSON document on standard output.

| Command | What it does |
|---|---|
| `status` | Engine version and branch, running builds and games, free space, recorded builds, running background jobs |
| `builds` | Recorded builds: app, whether it still exists, game folder, engine, backups |
| `doctor` | The tools a build needs: engine checkout, Python with the script's modules, git, dotnet, xcrun |
| `disk [--all] [--only …] [--game …]` | What NXForge uses on disk (game folders, build folders and their entries, caches, checkouts) and what each cleanup category would free; deletes nothing |
| `clean --safe` / `clean --only <categories>` `[--dry-run] [--game …]` | Deletes what the categories hold; `--dry-run` lists it instead |
| `clean --worktree <path>` | Removes one engine worktree, only when it is clean, pushed and not the engine |
| `build <game folder> [--plan] [--rebuild <app>] [--background]` | Builds the game's Mac app as the converter does (keys: the folder's `prod.keys`, else the settings'); `--plan` is the dry run that lists the stages that will be reused or redone (engines that have it); `--background` starts a job |
| `jobs`, `job <id>`, `stop <id>` | Background builds: stage, progress, result and the last log lines; `stop` is the app's Stop |
| `update [--apply]` | Fetches the engine and lists the commits waiting on its update branch; `--apply` fast-forwards (refused while a build runs or with uncommitted changes) |

Exit codes: 0 on success (also when there is nothing to delete), 1 on an error or a file that could not be deleted, 2 when the request was refused (a build already running, another cleanup running, no keys, a worktree that is not removable).

## Disk cleanup

| Category | Safe | What goes |
|---|---|---|
| `gpuarchiver` | yes | Metal's pipeline archive build folders in `getconf DARWIN_USER_CACHE_DIR`/`com.apple.gpuarchiver`, idle for an hour and older than every running game (as `scripts/clean_metal_cache.py`) |
| `build-temp` | yes | `tmp/`, `tmp.noindex/` and `*.partial` in every build folder (left by a stopped or failed step) |
| `metal-cache` | yes | The shared compiled-shader cache (`~/Library/Caches/NXForge/metallib.db`, or the older `metallib/` folder) trimmed to 12 GB (`--metal-cache-gb`, `DMSH_MTLCACHE_GB`) by removing the entries unused the longest; nothing while it is under that |
| `app-backups` | yes | Apps a rebuild moved to `app-backups/`: all but the newest one per game (`--backup-keep`, default 1), and only ones older than `--backup-days` (default 3) |
| `old-logs` | yes | Files in `~/Library/Logs/nxnative` older than `--log-days` (default 30) |
| `build-unused` | no | Each build folder's rewritten modules of versions other than the last packed one (`patched_<v>`, `nro_<v>`) and the game's survey folder. Other versions' `extract/` folders stay: which ones a build needs only the build knows (`--cleanup unused` on a build removes them) |
| `build-cache` | no | Each build folder except `logs/`, `profile/` and `run/`: the next build extracts the game and compiles every shader again (30 minutes or more) and needs the game files and `prod.keys` |
| `swift-build` | no | The converter app's Swift build folder (`app/.build`) in each checkout of the engine; the next `app/install.sh` rebuilds it |
| `worktrees` | no | Reported only, with whether each is removable; `clean --worktree <path>` removes one |

`clean --safe` is the set an hourly job can run without asking: `python3 scripts/nxforge.py clean --safe` (dry run: add `--dry-run`). What it never touches, whatever the category: NSPs, `.nup` files, dumps, `prod.keys`, any `.app` outside `app-backups/` (installed or recorded), saves (`~/Library/Application Support/nxnative`, `Saves/`), profiles, `logs/` of a build folder, and the engine's checkout. The build-folder, Metal cache and Swift categories are skipped while a build runs (the script, `dmsh_build.py`, `pso_offline.py`, `pack_app.py`, `nx_extract` or `metal-pack`), and a second cleanup waits for none: it is refused while one runs (a lock in the support folder). Each deletion is logged to `cli-clean.log` in the support folder.

Space freed on APFS can be less than a size shown: a Mac app's game files are clones of `extract/<version>`, and a clone frees nothing while the other copy is there.

## MCP server

Register it with Claude Code:

```sh
claude mcp add --scope user nxforge -- python3 ~/Development/NXForge/scripts/nxforge_mcp.py
```

or in Claude Desktop's `claude_desktop_config.json`:

```json
{"mcpServers": {"nxforge": {"command": "python3", "args": ["/Users/<you>/Development/NXForge/scripts/nxforge_mcp.py"]}}}
```

Tools: `nxforge_status`, `nxforge_builds`, `nxforge_doctor`, `nxforge_disk_report`, `nxforge_clean` (`dry_run` defaults to true; `categories` defaults to the safe set), `nxforge_build` (starts a background job), `nxforge_jobs`, `nxforge_job`, `nxforge_stop_job` and `nxforge_update`. A refusal comes back as a tool error with its reason. `dm/tools/tests/test_nxforge_cli.py` tests the categories, the guards and the protocol on a fake home folder.
