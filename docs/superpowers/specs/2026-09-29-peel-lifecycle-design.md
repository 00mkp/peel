# peel — Lifecycle commands (mutewake-style) — Design Spec

**Date:** 2026-09-29 · **Decision:** keep the shared engine (the app calls ConvertKit directly; every
conversion is also a CLI command); add terminal commands to manage peel itself, like mutewake.

## Commands
```
peel status                 version; install record (source, git commit); CLI path; Quick Actions
                            installed (n/5); Peel.app path + version; app running; Open at Login;
                            optional tools summary
peel update                 git pull --ff-only the recorded source, rerun its install.sh
peel update <dir|archive>   install from a directory or .tar.gz/.tgz/.zip instead
peel uninstall              quit Peel.app (turning Open at Login off first), remove Quick Actions,
                            Peel.app, the CLI and peel's records/preferences
peel app start|stop         launch / quit the menu-bar app
peel app panel              open the menu-bar panel
peel app login on|off       Open at Login, from the terminal
```

## Mechanics
- **VERSION** file at the repo root (`0.3.0`) is the one version: `PeelVersion.current` (Swift) must
  equal it (test-enforced); `build-app.sh` reads it for Info.plist.
- **Install record** `~/Library/Application Support/peel/install.conf` (key=value: `source`, `prefix`,
  `app_dir`, `version`), written by `install.sh` from the directory it runs in, unless
  `PEEL_NO_RECORD=1`. Update-from-archive runs the extracted `install.sh` with `PEEL_NO_RECORD=1`, so
  a deleted temp dir is never recorded (mutewake's lesson).
- **CLI ↔ app**: the app registers the `peel://` URL scheme (`peel://login/on|off`, `peel://panel`);
  `peel app …` opens those URLs (LaunchServices starts the app if needed). The app writes
  `~/Library/Application Support/peel/app-state.conf` (`version`, `login`) at launch and on change, which
  `peel status` reads. (A CLI process can't query another app's SMAppService login item.)
- `peel update` relaunches Peel.app afterwards if it was running.
- All lifecycle logic takes injectable paths/actions so tests run against temp dirs and never touch
  the real install, app or login item.

## Errors (mutewake wording style)
No recorded source → how to point update at a dir/archive or clone and reinstall. Recorded source
missing → same. `git pull` fails → "resolve it in <dir> and retry". Not a peel source tree → says so.
Unsupported archive → lists supported types. Every command exits 0 on success, 1 on failure, 2 usage.

## Testing
Version sync; install record round trip; status output from a fake install (record, services dir with
bundles, fake app bundle, app-state file); update from dir (fake install.sh writes a marker and sees
`PEEL_NO_RECORD` unset), from archive (runs with `PEEL_NO_RECORD=1`, record's source restored), no
record / missing source / bad tree / unsupported archive messages; uninstall removes exactly peel's
files in a fake home and calls the injected quit/login-off hooks; URL command parsing in the app core.
