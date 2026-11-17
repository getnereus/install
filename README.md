# Install the nereus CLI

The public channel of the `nereus` CLI, the CLI of Nereus, a composable API platform. On Linux (x86_64, aarch64):

```bash
curl -fsSL https://getnereus.github.io/install/install.sh | sh
```

It downloads the wheel the latest release names in `latest.json`, checks its sha256, installs [uv](https://docs.astral.sh/uv/) when it is missing and runs `uv tool install`. A pinned version: `NEREUS_VERSION=0.1.23`; every option: `sh -s -- --help`.

The CLI upgrades itself in the background; turn it off with `NEREUS_AUTO_UPGRADE=off` or `nereus config set auto_upgrade off`.

Each [release](https://github.com/getnereus/install/releases) holds the wheel, its manifest `latest.json` (`version`, `wheel`, `sha256`) and `install.sh`. This repository is generated: `install.sh`, `index.html` and this file come from `deploy/install/` of the Nereus repository, published by `scripts/registry/cli-publish`.
