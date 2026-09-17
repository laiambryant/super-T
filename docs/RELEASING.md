# Releasing Super T

The plugin is interpreted QML, JavaScript, and Python. Releases contain a
portable source archive rather than architecture-specific binaries.

## Prepare

1. Set the version in `manifest.json` and add its `## <version>` section to
   `CHANGELOG.md`. Keep the stable plugin ID `liambryant.todo`.
2. Run the release checks:

   ```sh
   make test
   make test-qml
   make validate
   make lint
   make test-dist
   WAYLAND_SMOKE=1 make test-qml
   ```

3. Inspect the UI on your desktop with a temporary task directory. Check
   creation, editing, selection, nesting, reordering, transfer, undo, and help.
4. Review and commit the intended files, including new runtime components.
   Push the commit to the default branch so Git installations receive it.

## Publish

For version `1.1.0`, after the reviewed commit is on the default branch:

```sh
git tag -a v1.1.0 -m "Super T 1.1.0"
git push origin v1.1.0
```

Use a new version for every release. Do not move or reuse published tags.
Prerelease versions such as `1.2.0-rc.1` create prereleases on GitHub.

The [release workflow](../.github/workflows/release.yml) runs the reusable CI
workflow before publication:

- Parser and backend tests on Python 3.10 and 3.14, shell lint, and manifest checks.
- Native Qt Quick and Quickshell integration tests in an Arch Linux container,
  using a pinned Omarchy shell commit and its official manifest validator.
- Archive reproducibility, checksum, content, and extracted-plugin checks.

The publish job validates the tag against the manifest, builds the package,
extracts release notes from the changelog, and uploads the archive and checksum
to a draft release. It publishes only after upload succeeds. It uses the
repository’s automatic `GITHUB_TOKEN`; no personal access token is needed.
Repository policies must permit that job’s `contents: write` permission.

If publication fails after creating a draft, inspect and remove that incomplete
draft before rerunning the job. Never replace assets on a published release.

For local builds:

```sh
make dist
cd dist
sha256sum --check super-t-1.1.0.tar.gz.sha256
```

The archive includes runtime modules, the manifest, Makefile, documentation,
license, packaging scripts, and tests. It excludes Git state and Python caches.
File order, timestamps, ownership, permissions, and gzip headers are normalized.

## List it in the Omarchy marketplace

The [official publishing guide](https://plugins.omarchy.org/publish.html)
requires a public GitHub repository, a valid root manifest, README, license,
and safe installation and removal. A preview is optional.

Submit through the [plugin issue form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml):

| Field | Value |
| --- | --- |
| Repository | `https://github.com/laiambryant/super-T` |
| Name | Super T |
| Description | A minimal, keyboard-driven Markdown task manager for Omarchy |
| Category | Choose the available productivity category |
| Suggested tags | `todo`, `markdown`, `productivity`, `quickshell` |
| Preview | `docs/preview.png` in the repository |
| Install | `omarchy plugin add https://github.com/laiambryant/super-T.git --enable` |
| Remove | `omarchy plugin remove liambryant.todo` |

The marketplace validates the current repository commit, then a maintainer
reviews the listing. Releases do not automatically submit or approve it.
Removal preserves the user’s task directory and saved state.
