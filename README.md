# Smartentry

<!-- Keep these links. Translations will automatically update with the README. -->
[Deutsch](https://zdoc.app/de/gaoyifan/smartentry) | 
[English](https://zdoc.app/en/gaoyifan/smartentry) | 
[Español](https://zdoc.app/es/gaoyifan/smartentry) | 
[français](https://zdoc.app/fr/gaoyifan/smartentry) | 
[日本語](https://zdoc.app/ja/gaoyifan/smartentry) | 
[한국어](https://zdoc.app/ko/gaoyifan/smartentry) | 
[Português](https://zdoc.app/pt/gaoyifan/smartentry) | 
[Русский](https://zdoc.app/ru/gaoyifan/smartentry) | 
[中文](https://zdoc.app/zh/gaoyifan/smartentry)

Smartentry is a generic, batteries-included Docker entrypoint implemented as a single shell script: `smartentry.sh`. It assembles your container at runtime from an "assets" directory, with templating, patching, volume initialization, and permission reconciliation.

- License: MIT (see `LICENSE`)
- Main program: `smartentry.sh`
- Optional CI helper for maintainers: `smartentry-build` (used in `.github/workflows/build.yml`)

---

## What Smartentry does

At container start, Smartentry can:
- Load environment variables from an `env` file (with optional overrides) and verify required ones.
- Materialize a `rootfs/` template into `/`, with variable substitution of `{{VARNAME}}` from the environment.
- Apply `patch`/diff files from `patch/` either at build-time or runtime.
- Initialize persistent volumes from an archive on first run and optionally fix ownership.
- Reconcile file modes and ownership based on a captured `chmod.list`.
- Run optional hooks before templating and before executing your main process.
- Execute your main program as a specific user or UID/GID.

All of this is controlled using environment variables (see below) and an assets directory (default `/opt/smartentry/HEAD`).

## Quick start

Minimal Dockerfile:

```Dockerfile
FROM debian:bookworm
COPY smartentry.sh /sbin/smartentry.sh
ENV ASSETS_DIR=/opt/smartentry/HEAD
ENTRYPOINT ["/sbin/smartentry.sh"]
CMD ["run"]
```

Example assets mounted or baked into the image:

```
/opt/smartentry/HEAD/
  env
  rootfs/
    etc/myapp/config.yaml   # may contain {{MYAPP_PORT}}
  run                       # executable main program
  pre-entry.sh              # optional
  pre-run                   # optional
  patch/                    # optional (runtime or build-time)
  volumes.list              # optional
```

Run:

```bash
docker run --rm \
  -e MYAPP_PORT=8080 \
  -v $(pwd)/assets:/opt/smartentry/HEAD \
  smartentry/debian:bookworm
```

## Pre-built images

This repository publishes pre-built images via GitHub Actions (see `.github/workflows/build.yml`). Images are tagged as `smartentry/<base>:<tag>` (e.g., `smartentry/debian:bookworm`) and are rebuilt when upstream tags update. These images include `smartentry.sh` as the entrypoint and are suitable for direct use with an `ASSETS_DIR` volume.

## Assets directory layout

- `env`: environment configuration (see next sections)
- `rootfs/`: template tree copied to `/` (with templating)
- `patch/`: unified diff files applied on top of `/` (build-time or runtime)
- `pre-entry.sh`: sourced prior to templating
- `pre-run`: executed just before the main program
- `run`: main program invoked by `CMD ["run"]`
- `volumes.list`: newline-separated list of paths to archive/restore
- Generated at build-time (optional):
  - `checklist.md5`: checksum list used to preserve user edits
  - `chmod.list`: captured file mode and ownership data
  - `volumes.tar`: archive of listed volumes

Default base path is `ASSETS_DIR=/opt/smartentry/HEAD` (configurable).

## Runtime flow (build vs run modes)

Smartentry supports two entry modes:

- Build-mode: `smartentry.sh build`
  - Optionally generate `checklist.md5` from existing target files to preserve user modifications
  - Capture `chmod.list` when `ENABLE_CHMOD_AUTO_FIX=true`
  - Apply build-time patching (`PATCH_MODE=buildtime`)
  - Append paths from `volumes.list` to `volumes.tar`

- Run-mode (default): `smartentry.sh run [args...]` or `smartentry.sh <command>`
  - Detect first-run via `INITIALIZED_FLAG`
  - Source `pre-entry.sh`
  - Load/verify env, apply template (`rootfs/`) and runtime patching
  - Initialize volumes and fix ownership if enabled
  - Apply chmod/chown fixes from `chmod.list`
  - Run `pre-run` (if enabled), then exec the main program or supplied command

## Hooks and scripts

- `BUILD_SCRIPT` (`$ASSETS_DIR/build`): optional script executed in build-mode before other steps.
- `PRE_ENTRY_SCRIPT` (`$ASSETS_DIR/pre-entry.sh`): sourced at runtime before templating.
- `PRE_RUN_SCRIPT` (`$ASSETS_DIR/pre-run`): executed just before main program.
- `RUN_SCRIPT` (`$ASSETS_DIR/run`): main program when using `CMD ["run"]`.

Enable/disable with `ENABLE_PRE_RUN_SCRIPT`, etc. (see toggles below).

---

## Environment loading and required variables

- `ENV_FILE` defaults to `$ASSETS_DIR/env`.
- Lines with `KEY=VALUE` export variables (unless `ENABLE_OVERRIDE_ENV=false` and the variable is already set in the environment).
- Lines with just `KEY` declare required variables. If `ENABLE_MANDATORY_CHECK_ENV=true`, Smartentry exits if any required variable is missing.

Tip: You can provide `.env`-style files via bind mount to `$ASSETS_DIR/env`.

---

## Templating (`{{VAR}}`) and variable discovery

- Files copied from `rootfs/` to `/` undergo string substitution: each `{{VARNAME}}` is replaced with the value of `$VARNAME`.
- Replacement is literal for `/` to avoid breaking paths.
- Variables with no value are replaced by an empty string.
- A helper script is provided to list variables referenced in templates:

  ```bash
  tools/get_template_variable.sh /path/to/rootfs
  ```

## Patching (build-time vs runtime)

- Store GNU `patch`-compatible diffs under `patch/`, using destination paths relative to `/`. Smartentry runs `patch <destination> <diff-file>` for each file, so the diff must describe how to transform the existing destination file.
- Choose when to apply with `PATCH_MODE`:
  - `buildtime`: applied by `smartentry.sh build`
  - `runtime`: applied on every container start
- Example layout:

  ```
  patch/
    etc/myapp/config.yaml.diff
    usr/local/bin/tool.sh.patch
  ```

- To create a diff from a modified file:

  ```bash
  diff -u /etc/myapp/config.yaml new-config.yaml > patch/etc/myapp/config.yaml.diff
  ```

## Preserving user modifications (checksums)

- When `ENABLE_KEEP_USER_MODIFICATION=true` and `checklist.md5` exists, Smartentry only overwrites a target file if its checksum still matches the recorded value (i.e., user has not modified it). New files are always created.
- Generate `checklist.md5` in build-mode: for each file under `rootfs/`, record the checksum of the destination path if it exists.

## Volume initialization and permissions

- List paths to persist in `volumes.list`. Build-mode appends each to `volumes.tar`.
- On first run, if a listed path is empty or missing (or when `ENABLE_FORCE_INIT_VOLUMES_DATA=true`), extract it from `volumes.tar`.
- Ownership fixes for non-root users:
  - `ENABLE_FIX_OWNER_OF_VOLUMES=true` changes the top-level path owner
  - `ENABLE_FIX_OWNER_OF_VOLUMES_DATA=true` changes ownership recursively

## File modes and ownership reconciliation

- If `ENABLE_CHMOD_AUTO_FIX=true` during build-mode, Smartentry captures file mode, owner, group into `chmod.list` for all files/dirs under `rootfs/` that exist at the destination.
- At runtime with `ENABLE_CHMOD_FIX=true`, it applies the recorded modes and ownership where paths exist.

## User and home directory mapping

You can run the main program as:
- A specific UID (`DOCKER_UID`): Smartentry maps or creates a passwd entry.
- A specific username (`DOCKER_USER`): Smartentry resolves UID/GID.
- Default: root (UID/GID 0).

`DOCKER_HOME` may be overridden; Smartentry updates `/etc/passwd` to reflect the new home for the chosen user.

## Environment hardening (optional unset)

Set `ENABLE_UNSET_ENV_VARIBLES=true` to clear the environment before executing the main program, preserving only `TERM`, `PATH`, `HOME`, and `SHLVL`.

Use this to reduce accidental leakage of build-time secrets into runtime.

## Configuration reference (tables)

### Base paths and files

| Variable | Default |
|---|---|
| `ASSETS_DIR` | `/opt/smartentry/HEAD` |
| `ENV_FILE` | `$ASSETS_DIR/env` |
| `ROOTFS_DIR` | `$ASSETS_DIR/rootfs` |
| `PATCH_DIR` | `$ASSETS_DIR/patch` |
| `PATCH_MODE` | `buildtime` (or `runtime`) |
| `CHECKLIST_FILE` | `$ASSETS_DIR/checklist.md5` |
| `CHMOD_FILE` | `$ASSETS_DIR/chmod.list` |
| `RUN_SCRIPT` | `$ASSETS_DIR/run` |
| `BUILD_SCRIPT` | `$ASSETS_DIR/build` |
| `PRE_ENTRY_SCRIPT` | `$ASSETS_DIR/pre-entry.sh` |
| `PRE_RUN_SCRIPT` | `$ASSETS_DIR/pre-run` |
| `VOLUMES_LIST` | `$ASSETS_DIR/volumes.list` |
| `VOLUMES_ARCHIVE` | `$ASSETS_DIR/volumes.tar` |
| `INITIALIZED_FLAG` | `/var/run/smartentry.initialized` |
| `DOCKER_SHELL` | `/bin/bash` |

### Feature toggles

| Variable | Default |
|---|---|
| `ENABLE_OVERRIDE_ENV` | `false` |
| `ENABLE_KEEP_USER_MODIFICATION` | `true` |
| `ENABLE_CHMOD_AUTO_FIX` | `true` |
| `ENABLE_INIT_VOLUMES_DATA` | `true` |
| `ENABLE_ROOTFS` | `true` |
| `ENABLE_PATCH` | `true` |
| `ENABLE_CHMOD_FIX` | `true` |
| `ENABLE_UNSET_ENV_VARIBLES` | `true` |
| `ENABLE_PRE_RUN_SCRIPT` | `true` |
| `ENABLE_FORCE_INIT_VOLUMES_DATA` | `false` |
| `ENABLE_FIX_OWNER_OF_VOLUMES` | `false` |
| `ENABLE_FIX_OWNER_OF_VOLUMES_DATA` | `false` |
| `ENABLE_MANDATORY_CHECK_ENV` | `true` |

### User selection

| Variable |
|---|
| `DOCKER_UID` |
| `DOCKER_GID` |
| `DOCKER_USER` |
| `DOCKER_HOME` |

## Maintenance note: CI helper

For repository maintainers, a small Python helper (`smartentry-build`) orchestrates differential multi-arch builds in CI. It is used by the GitHub Action defined in `.github/workflows/build.yml`. End-users of `smartentry.sh` do not need this helper.

## License

MIT License. See `LICENSE`.
