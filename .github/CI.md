# Shared CI

Reusable workflows and composite actions shared across `Der-Floh` projects.

Consumers reference them by tag:

```yaml
uses: Der-Floh/Der-Floh/.github/actions/pack@v1
uses: Der-Floh/Der-Floh/.github/workflows/library-ci.yml@v1
```

## Layout

| Action | Used by | Purpose |
| --- | --- | --- |
| `setup-dotnet` | library, app | Installs the SDK and restores the NuGet cache |
| `resolve-version` | all | Validates a release tag and reports the version it carries |
| `pack` | library | Restores, builds and packs deterministically |
| `verify-package` | library | Validates the `.nupkg` against NuGet packaging rules |
| `publish-nuget` | library | OIDC login and push of package + symbols |
| `velopack-pack` | app | Publishes one runtime and packs a Velopack installer and portable archive |
| `verify-velopack` | app | Installs the setup silently, checks registration, uninstalls |
| `resolve-winget-mode` | app | Decides create / update / skip |
| `setup-wingetcreate` | app | Downloads and hash-verifies `wingetcreate.exe` |
| `winget-update` | app | Submits a new version of an existing package |
| `extension-pack` | extension | Builds with npm, lints with Mozilla's add-on linter, zips the extension and archives its sources |
| `nexus-pack` | nexus | Builds and zips a mod, then checks the zip, and optionally a version file inside it, against the release version |

| Reusable workflow | Purpose |
| --- | --- |
| `library-ci.yml` | Build matrix, optional test job, pack a preview, verify it |
| `app-ci.yml` | Build matrix, optional Velopack packaging of the desktop project |
| `app-publish.yml` | Velopack installers per runtime, verified, uploaded, attested, then WinGet update |
| `app-publish-winget.yml` | Submit a release's installers to WinGet as a new version |
| `app-pages.yml` | Publish a .NET wasm app to GitHub Pages |
| `extension-ci.yml` | Optional project checks, and a linted preview zip of the browser extension |
| `extension-publish.yml` | Browser extension zip, uploaded, attested, then submitted to the Chrome Web Store and addons.mozilla.org |
| `nexus-publish.yml` | Mod zip, uploaded, attested, then added to its file on Nexus Mods as a new version |

## Consuming: a library

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  ci:
    uses: Der-Floh/Der-Floh/.github/workflows/library-ci.yml@v1
    with:
      project-path: RegJump/RegJump.csproj
      package-id: RegJump
      test-project: RegJump.Test/RegJump.Test.csproj
```

`test-project` is optional. Leave it out and the `Test` job is skipped; the rest of the
workflow is unaffected. When it is set the job runs on `windows-latest`, so tests that need
the registry or a real process actually execute.

The test job runs `dotnet test` in **Microsoft.Testing.Platform mode**, which the .NET 10 SDK
requires for MTP-based frameworks such as xunit.v3 4. A consuming repository must therefore:

1. Opt in, with a `global.json` at its root:

   ```json
   {
     "test": {
       "runner": "Microsoft.Testing.Platform"
     }
   }
   ```

2. Reference `Microsoft.Testing.Extensions.TrxReport` from the test project. `--report-trx` is
   not built into the platform, and without the extension the run fails with exit code 5.

Without both, the job fails with *"Testing with VSTest target is no longer supported by
Microsoft.Testing.Platform on .NET 10 SDK and later"*.

`.github/workflows/publish.yml` — note this stays a real workflow in the product
repository rather than a reusable one, for the reason below:

```yaml
name: Publish Release

on:
  release:
    types: [published]

concurrency:
  group: nuget-publish
  cancel-in-progress: false

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v7

      - id: version
        uses: Der-Floh/Der-Floh/.github/actions/resolve-version@v1
        with:
          tag: ${{ github.event.release.tag_name }}

      - uses: Der-Floh/Der-Floh/.github/actions/setup-dotnet@v1

      - uses: Der-Floh/Der-Floh/.github/actions/pack@v1
        with:
          project-path: RegJump/RegJump.csproj
          version: ${{ steps.version.outputs.value }}

      - id: package
        uses: Der-Floh/Der-Floh/.github/actions/verify-package@v1
        with:
          package-id: RegJump
          version: ${{ steps.version.outputs.value }}

      - uses: softprops/action-gh-release@v3
        with:
          fail_on_unmatched_files: true
          files: |
            ./artifacts/*.nupkg
            ./artifacts/*.snupkg

      - uses: actions/attest-build-provenance@v4
        with:
          subject-path: |
            ./artifacts/*.nupkg
            ./artifacts/*.snupkg

      - uses: Der-Floh/Der-Floh/.github/actions/publish-nuget@v1
        with:
          package-path: ${{ steps.package.outputs.package-path }}
          symbols-path: ${{ steps.package.outputs.symbols-path }}
          nuget-user: Der-Floh
```

## Consuming: an app

`.github/workflows/publish.yml`:

```yaml
name: Publish Release

on:
  release:
    types: [published]

concurrency:
  group: winget-publish
  cancel-in-progress: false

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  publish:
    uses: Der-Floh/Der-Floh/.github/workflows/app-publish.yml@v1
    with:
      project-path: Cursor_Installer_Creator.Desktop/Cursor_Installer_Creator.Desktop.csproj
      author: Der_Floh
      package-name: CursorInstallerCreator
      splash-image: Cursor_Installer_Creator/Assets/icon-x256.png
    secrets:
      WINGET_CREATE_GITHUB_TOKEN: ${{ secrets.WINGET_CREATE_GITHUB_TOKEN }}
```

Apps are packaged with [Velopack](https://velopack.io). The desktop project must reference the
`Velopack` package and call `VelopackApp.Build().Run()` first in `Main`; `vpk pack` refuses to
pack it otherwise. `vpk` is installed at the Velopack version the project resolves, so updating
the package updates the tool with it.

For each entry in `runtimes` (by default `win-x64`, `win-x86` and `win-arm64`) the workflow
publishes with `publish-profile`, packs, installs and uninstalls the setup on a runner of that
architecture (`windows-11-arm` for `win-arm64`), and then uploads
`<package-name>-<runtime>-Setup.exe` and `<package-name>-<runtime>-Portable.zip` to the release.
The installer's title, main executable and icon come from the project's `Product`,
`AssemblyName` and `ApplicationIcon`; its publisher is `author`.

`package-name` names the install folder (`%LocalAppData%\<package-name>`) and the Apps & Features
entry, and the WinGet identifier is `<author>.<package-name>`. Changing `package-name` after a
release installs the app side by side instead of upgrading it. Velopack's update feed is not
released, so installed apps do not update themselves.

`app-ci.yml` packs every runtime the same way on each push, without releasing anything, when
`publish-project` and `package-name` are set.

WinGet only receives **new versions** of a package that already exists there. Submit the first
version by hand, for example with `komac new`; until it is merged, the WinGet job only leaves a
notice. `WINGET_CREATE_GITHUB_TOKEN` must be a classic PAT with the `public_repo` and `workflow`
scopes: submitting syncs your fork of `microsoft/winget-pkgs`, which fails without `workflow`
whenever upstream has changed its workflow files.

App publishing can be a reusable workflow, unlike NuGet publishing below, because the WinGet
submission authenticates with that PAT rather than an OIDC trust policy.

The secrets have to be set on the **calling** repository. A reusable workflow never sees the
secrets of the repository that stores it — this repository is public, so if it did, anyone
could call the workflow and run it with these credentials. The permissions block is also
required on the caller: a reusable workflow cannot grant itself more than the caller has.

## Consuming: a browser extension

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ['**']
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  ci:
    uses: Der-Floh/Der-Floh/.github/workflows/extension-ci.yml@v1
    with:
      extension-dir: extension
      package-name: little-alchemy-coop
      check-command: npm run check
```

The extension is an npm project at the repository root. `extension-pack` runs `npm ci` and
`build-command` (by default `npm run build`), which must leave the extension, `manifest.json`
included, in `extension-dir`. It then lints the extension with Mozilla's add-on linter, zips it
as `<package-name>-<version>.zip` and archives the sources next to it. Linting and zipping go
through [kewisch/action-web-ext](https://github.com/kewisch/action-web-ext), which runs Mozilla's
`web-ext`.

The `Package` job packs every push that way and keeps the zip as an artifact for
`retention-days`, so each push leaves a build to try out. `check-command` is optional. It runs
after `npm ci` in a `Check` job of its own, typically the project's type check, linting and unit
tests; leave it out and that job is skipped.

`.github/workflows/publish.yml`:

```yaml
name: Publish Release

on:
  release:
    types: [published]

concurrency:
  group: extension-publish
  cancel-in-progress: false

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  publish:
    uses: Der-Floh/Der-Floh/.github/workflows/extension-publish.yml@v1
    with:
      extension-dir: extension
      package-name: little-alchemy-coop
      chrome-extension-id: ${{ vars.CHROME_EXTENSION_ID }}
      chrome-publisher-id: ${{ vars.CHROME_PUBLISHER_ID }}
      firefox-addon-id: ${{ vars.FIREFOX_ADDON_ID }}
    secrets:
      CHROME_CLIENT_ID: ${{ secrets.CHROME_CLIENT_ID }}
      CHROME_CLIENT_SECRET: ${{ secrets.CHROME_CLIENT_SECRET }}
      CHROME_REFRESH_TOKEN: ${{ secrets.CHROME_REFRESH_TOKEN }}
      AMO_API_KEY: ${{ secrets.AMO_API_KEY }}
      AMO_API_SECRET: ${{ secrets.AMO_API_SECRET }}
```

A release is packed the same way, from the tagged sources, after checking that the manifest
carries the release's version. The release tag must be a plain version such as `v1.2.3`: neither
store accepts a prerelease label in an extension's version.

The zip is uploaded to the release and attested. Unless the release is a prerelease, the same
zip then goes to both stores:

- the **Chrome Web Store** through
  [mnao305/chrome-extension-upload](https://github.com/mnao305/chrome-extension-upload), which
  uses the Chrome Web Store API v2 and submits the new version for review;
- **addons.mozilla.org** through `web-ext sign` as a listed version, with the source archive
  attached. AMO requires the sources of bundled or transpiled code and its reviewers rebuild the
  add-on from them, so the README must say how to build it. The job ends once AMO has
  validated the upload; the review happens afterwards.

Both stores only receive **new versions** of an extension they already have. Upload the first
version by hand, for example the zip the first release attached, in the
[Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole) and the
[AMO Developer Hub](https://addons.mozilla.org/developers/), where each store asks for its listing
details. Until `chrome-extension-id` or `firefox-addon-id` is set, that store's job only leaves a
notice, so passing them as repository variables, as above, switches a store on without editing
the workflow. `firefox-addon-id` is the manifest's `browser_specific_settings.gecko.id`; the run
fails before releasing anything if the two differ, since AMO would take a changed id for a new
add-on.

The store credentials:

- `CHROME_CLIENT_ID`, `CHROME_CLIENT_SECRET` and `CHROME_REFRESH_TOKEN` belong to an OAuth client
  of a Google Cloud project with the Chrome Web Store API enabled.
  [chrome-webstore-upload-keys](https://github.com/fregante/chrome-webstore-upload-keys) walks
  through creating one and prints the refresh token. Set the consent screen's publishing status
  to *In production*: while it is *Testing*, Google expires the refresh token after seven days.
  `chrome-publisher-id` is shown under *Publisher > Settings* in the Developer Dashboard.
- `AMO_API_KEY` and `AMO_API_SECRET` are the JWT issuer and JWT secret from
  <https://addons.mozilla.org/developers/addon/api/key/>.

As for apps, the secrets and the permissions block belong to the calling repository.

## Consuming: a mod on Nexus Mods

`.github/workflows/publish.yml`, here for a Vortex extension:

```yaml
name: Publish Release

on:
  release:
    types: [published]

concurrency:
  group: nexus-publish
  cancel-in-progress: false

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  publish:
    uses: Der-Floh/Der-Floh/.github/workflows/nexus-publish.yml@v1
    with:
      package-name: vs-support
      version-file: info.json
      file-id: ${{ vars.NEXUSMODS_FILE_ID }}
      file-name: Vampire Survivors Support
      file-description: Adds support for Vampire Survivors to Vortex
      primary-mod-manager-download: true
      mod-id: ${{ vars.NEXUSMODS_MOD_ID }}
      changelog: ${{ github.event.release.html_url }}
    secrets:
      NEXUSMODS_API_KEY: ${{ secrets.NEXUSMODS_API_KEY }}
```

`nexus-pack` runs `build-command` (by default `npm ci && npm run package`, with Node.js set up),
which must leave the mod zipped as `<package-name>-<version>.zip` in `package-dir` (by default
`dist`). The run fails before releasing anything unless that zip exists for the release's
version. `version-file` names a JSON file inside the zip whose `version` must match as well,
such as `info.json` for a Vortex extension, which is the version Vortex reads.

The zip is uploaded to the release and attested. Unless the release is a prerelease, it then
goes to **Nexus Mods** through [Nexus-Mods/upload-action](https://github.com/Nexus-Mods/upload-action)
as a new version of the file `file-id` names, listed as `<file-name> v<version>`. By default
the upload also sets the mod's version on Nexus Mods (`update-mod-version`), but doesn't make
the file the default download for mod managers (`primary-mod-manager-download`), which the
example turns on. `changelog` adds text to the mod's changelog for the version and needs
`mod-id`; the example adds a link to the GitHub release, and
`${{ github.event.release.body }}` would add the release notes themselves. The action has no
test mode, so every run that gets this far uploads for real.

Nexus Mods only receives **new versions** of a file the mod already has. Upload the first
version by hand on the mod's *Manage Files* page; the file id and the mod id are then shown by
the *Advanced* option on the mod's *Files* tab, or in the file's edit menu on *Manage Files*.
Until `file-id` is set, the Nexus Mods job only leaves a notice, so passing it as a repository
variable, as above, switches the upload on without editing the workflow; the example passes
`mod-id` the same way. Once it is set, the
run fails before releasing anything if `NEXUSMODS_API_KEY` is missing, or if `changelog` is set
without `mod-id`.

`NEXUSMODS_API_KEY` is a personal API key of the mod's author, from
<https://www.nexusmods.com/settings/api-keys>. As for apps, the secret and the permissions
block belong to the calling repository.

## Why NuGet publishing is not a reusable workflow

nuget.org's trusted publishing matches the repository embedded in the OIDC
`job_workflow_ref` claim against the `repository` claim, and requires them to agree.
A reusable workflow in this repository makes them disagree:

```text
repository       = Der-Floh/RegJump
job_workflow_ref = Der-Floh/Der-Floh/.github/workflows/library-publish.yml@v1
```

which fails with `401: No matching trust policy`. A composite action is not a job
identity — it runs as steps inside the caller's job — so `publish-nuget` keeps the
claims pointing at the product repository and the existing policy keeps working.

The same applies within a single repository: if a publish job is moved into a
same-repo reusable workflow, the nuget.org policy must name *that* file, not the
caller.

## Versioning

Consumers track a moving major tag:

```bash
git tag -f v1 && git push -f origin v1
```

Two things to remember when cutting a new major:

- `winget-update` references `setup-wingetcreate` by an **absolute** path pinned to
  `@v1`. A relative `./` path would resolve against the *calling* repository, which does
  not contain these actions. Bump that ref with the tag.
- `library-ci.yml`, `app-ci.yml`, `app-publish.yml`, `app-publish-winget.yml`,
  `extension-ci.yml`, `extension-publish.yml` and `nexus-publish.yml` reference the actions
  the same way, for the same reason, and `app-publish.yml` calls `app-publish-winget.yml` by
  its `@v1` path.

### Pinning `publish-nuget`

`publish-nuget` is the one action holding a publishing credential. Anything able to
push here or retarget `v1` could mint short-lived nuget.org keys for every library
that references it. Pin that one action to a commit SHA if you would rather not have
it move implicitly:

```yaml
uses: Der-Floh/Der-Floh/.github/actions/publish-nuget@<sha>
```

Dependabot updates SHA pins and annotates them with the version.
