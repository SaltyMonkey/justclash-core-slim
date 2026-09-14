# JustClash Core Builder

Unofficial downstream build automation for MetaCubeX/mihomo. This repository is
not affiliated with, endorsed by, or maintained by the upstream project.

It does **not** keep a persistent mirror of the upstream codebase. Once per day
the workflow checks:

- `MetaCubeX/mihomo:Alpha`
- the latest stable GitHub release

When a new version is found it:

1. clones the exact upstream ref into a temporary runner directory;
2. applies every `patches/*.patch`;
3. temporarily pushes the patched source to a `build/*` branch;
4. runs MetaCubeX/mihomo's original `.github/workflows/build.yml`;
5. downloads the resulting build artifacts;
6. attaches the corresponding patched source as `custom-core-source.tar.gz`
   and the vendored Go dependencies as `vendor.tar.gz`;
7. publishes/updates the downstream release while keeping the original versioned `mihomo-*` binary names and upstream-compatible `version.txt`;
8. deletes the temporary `build/*` branch.

## Release policy

### Alpha

There is only one rolling prerelease:

`Prerelease-Alpha`

Both its tag and release title are `Prerelease-Alpha`, matching upstream.

Its assets are replaced when `MetaCubeX/mihomo:Alpha` changes.

Alpha asset names include the build version, for example:

- `mihomo-linux-arm64-alpha-<short-sha>.gz` — with gVisor
- `mihomo-linux-arm64-nogvisor-alpha-<short-sha>.gz` — without gVisor

The rolling release replaces these assets on each new Alpha build, so their
names change together with the upstream commit.

### Stable

Each upstream stable release creates a separate downstream release using the
same version tag and title, for example:

`v1.19.31`

Stable releases are normally never replaced. A manual workflow run can force a
rebuild if required.

## Build tags

The upstream workflow produces two Linux variants for every Linux target:

- normal: `with_gvisor,no_easytier,no_tailscale,no_zerotier`
- lightweight `nogvisor`: `no_easytier,no_tailscale,no_zerotier`

There is no separate `no_gvisor` build tag. The lightweight variant disables
gVisor simply by omitting `with_gvisor`. Alpha and v1.19.31 provide all three
`no_easytier`, `no_tailscale`, and `no_zerotier` constraints. Version v1.19.30
predates EasyTier, so `no_easytier` is a harmless no-op there; the other two
constraints are present.

Both variants append `-tiny` to the version embedded in the executable. For
example, the API and `mihomo -v` report `v1.19.31-tiny`, while archive names keep
the original upstream version format.

Each release also contains an upstream-compatible `version.txt`. It stores the
build version without the downstream `-tiny` suffix: for example, `v1.19.31` for
a stable release or `alpha-<short-sha>` for an Alpha build. As in the upstream
workflow, `version.txt` is not included in `checksums.txt`.

`custom-core-source.tar.gz` contains the patched source, a dated downstream
modification notice, and its vendored Go dependencies. The same dependencies are
also published separately as `vendor.tar.gz`, matching the upstream release
convention. A copy of the upstream GPL-3.0 `LICENSE` is attached directly to the
release as well as being included in the source archive.

## Files in this repository

- `.github/workflows/sync.yml` — nightly version detection and orchestration.
- `.github/workflows/build.yml` — placeholder so GitHub registers the workflow
  path on the default branch. Temporary `build/*` branches contain upstream's
  full, patched `build.yml`.
- `patches/0001-build-without-easytier-tailscale.patch` — removes EasyTier,
  Tailscale and ZeroTier from upstream tests and regular builds.
- `patches/0002-add-linux-nogvisor-build.patch` — adds lightweight Linux builds
  without gVisor.
- `patches/0003-disable-upstream-publishing.patch` — disables upstream release and
  Docker jobs; publishing is handled by the builder workflow.
- `patches/0004-disable-core-self-update.patch` — disables only the core
  self-update API; UI and GEO database updates remain available.
- `scripts/build-upstream.sh` — creates the temporary source branch, dispatches
  the original CI, waits for it, publishes assets, then removes that branch.

## Setup

Create an empty public GitHub repository with a name that does not use the word
`mihomo`, unpack these files into it, commit and push them to the default branch.

Then open:

Settings -> Actions -> General -> Workflow permissions

and allow read/write permissions if your repository or organization policy does
not allow the explicit workflow permissions to grant them.

The builder also needs a token that is allowed to create and update workflow
files. The built-in `GITHUB_TOKEN` cannot push the patched upstream
`.github/workflows/build.yml` to the temporary `build/*` branch, even when
`contents: write` and `actions: write` are enabled.

Create a repository secret named `BUILDER_TOKEN`. Prefer a fine-grained token
limited to this repository with read/write access to Contents and Actions, plus
write access to Workflows. A classic token needs repository access
(`public_repo` for a public repository, or `repo` where appropriate) together
with the `workflow` scope.
The token is used only by the Alpha and stable build jobs; version detection
continues to use the built-in `GITHUB_TOKEN`.

Never commit the token to this repository or place it in workflow arguments.
Store it only as the `BUILDER_TOKEN` Actions secret and rotate it before it
expires.

The build script attributes its temporary patched-source commit to the standard
Actions bot identity by default. Manual callers can override it with
`--git-user-name` and `--git-user-email`. These values are applied only to the
single `git commit-tree` invocation; the cloned repository's Git configuration
is not modified.

## Schedule

The workflow runs at:

`30 2 * * *`

GitHub cron is UTC.

You can also run `Sync upstream builds` manually. The manual form contains
switches to force an Alpha or stable rebuild.

## Patch safety and reproducibility

The nightly build deliberately fails if an upstream change makes the patch stop
applying. That is preferable to silently publishing a binary built with
different options.

The release contains `custom-core-source.tar.gz`, a corresponding-source
snapshot assembled from the patched commit and the canonical packaging job. It
includes vendored Go dependencies. Transient runner state and regenerated build
data, such as the refreshed CA bundle, are reproducibly described by the patched
workflow rather than included in this archive.

## Upstream ownership and licensing

This repository does not claim ownership of MetaCubeX/mihomo, its name, source
code, version numbers, release metadata, documentation, or other upstream
materials. All rights to the upstream project and its releases remain with their
respective authors and copyright holders. Releases published by this repository
are unofficial downstream rebuilds and must not be presented as official
MetaCubeX/mihomo releases.

MetaCubeX/mihomo is distributed under the GNU General Public License version 3
(GPL-3.0). A verbatim copy of the upstream license is included in [`LICENSE`](LICENSE).
This downstream repository and its patches follow the same GPL-3.0 terms.

Bundled third-party components remain subject to their own licenses, copyright
notices, and attribution requirements. The corresponding source distributed
with each binary release retains those files and notices and includes a dated
`DOWNSTREAM.md` describing the modifications. Nothing in this repository
replaces, overrides, or grants rights beyond the applicable upstream and
third-party licenses.

Each release provides the corresponding patched source in
`custom-core-source.tar.gz` and the standalone `vendor.tar.gz` alongside the
modified binaries. Keep those source archives, the license text, and all
copyright notices available when redistributing a build.

## Disclaimer

This project and its release artifacts are provided "as is", without warranties
of any kind, express or implied. Builds are automated and may contain upstream
defects, downstream patch defects, security vulnerabilities, regressions, or
platform-specific incompatibilities.

You use the scripts, source code, binaries, networking features, and update
mechanisms entirely at your own risk. You are responsible for reviewing the
source and configuration, testing the build in your environment, protecting
your data, and complying with all laws, licenses, service terms, and network
policies applicable to you.

To the maximum extent permitted by applicable law, the maintainer and
contributors of this repository are not liable for any direct or indirect loss,
data loss, service interruption, security incident, account restriction, or
other damage resulting from the use of, or inability to use, this project or its
release artifacts.
