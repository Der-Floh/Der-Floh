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
| `dotnet-test` | library, app | Builds and runs a test project in Release and keeps its results |
| `resolve-version` | all | Validates a release tag and reports the version it carries |
| `pack` | library | Restores, builds and packs deterministically |
| `verify-package` | library | Validates the `.nupkg` against NuGet packaging rules |
| `publish-nuget` | library | OIDC login and push of package + symbols |
| `dotnet-publish` | app | Publishes a project for one runtime into a folder |
| `setup-vpk` | app | Installs Velopack's `vpk` at a given version |
| `velopack-pack` | app | Packs a published folder into a Velopack installer and, unless turned off, a portable archive |
| `zip` | app | Zips the contents of a folder, or a list of files, into one archive, optionally inside a folder of the archive |
| `verify-velopack` | app | Installs the setup silently, checks registration, uninstalls |
| `resolve-winget-mode` | app | Decides create / update / skip |
| `setup-wingetcreate` | app | Downloads and hash-verifies `wingetcreate.exe` |
| `winget-update` | app | Submits a new version of an existing package |
| `extension-pack` | extension | Builds with npm, lints with Mozilla's add-on linter, zips the extension and archives its sources |
| `vsix-pack` | vscode-extension | Installs, optionally checks, builds and tests a VS Code extension, packs it with vsce and checks the VSIX's version and contents |
| `vscode-test` | vscode-extension, `vsix-pack` | Runs a VS Code extension's tests under a virtual display |
| `github-release-upload` | vscode-extension | Uploads files to the release that triggered the run and, in a public repository, attests them |
| `vs-marketplace-publish` | vscode-extension | Publishes a VSIX to the Visual Studio Marketplace through Microsoft Entra ID |
| `open-vsx-verify` | vscode-extension | Checks the token, the namespace and the dependencies before anything is released |
| `open-vsx-publish` | vscode-extension | Publishes a VSIX to Open VSX with a token |
| `nexus-pack` | nexus | Builds and zips a mod, then checks the zip, and optionally a version file inside it, against the release version |
| `tool-pack` | tool | Builds a .NET Framework app with MSBuild and checks that its exe carries the version and needs no other file |
| `dependabot-merge` | dependabot | Merges a Dependabot minor or patch update, and leaves any other update for a review |

| Reusable workflow | Purpose |
| --- | --- |
| `library-ci.yml` | Build matrix, optional test job, pack a preview, verify it |
| `app-ci.yml` | Build matrix, optional test job, optional Velopack packaging of the desktop project |
| `app-publish.yml` | Velopack installers per runtime, verified, uploaded, attested, then WinGet update |
| `app-publish-winget.yml` | Submit a release's installers to WinGet as a new version |
| `app-pages.yml` | Publish a .NET wasm app to GitHub Pages |
| `extension-ci.yml` | Optional project checks, and a linted preview zip of the browser extension |
| `extension-publish.yml` | Browser extension zip, uploaded, attested, then submitted to the Chrome Web Store and addons.mozilla.org |
| `vscode-extension-ci.yml` | Optional checks and VS Code tests, and a checked preview VSIX |
| `vscode-extension-publish.yml` | VSIX built and tested from the release tag, uploaded and, in a public repository, attested, then published to the Visual Studio Marketplace and Open VSX |
| `nexus-publish.yml` | Mod zip, uploaded, attested, then added to its file on Nexus Mods as a new version |
| `tool-ci.yml` | MSBuild build of a .NET Framework app, kept as a preview exe |
| `tool-publish.yml` | .NET Framework app built with MSBuild, its exe uploaded and attested |
| `dependabot-automerge.yml` | Squash-merge a Dependabot minor or patch update once the other jobs of the calling workflow passed |

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

`test-project` adds a `Test` job to `app-ci.yml`, which runs the tests the same way as for a library, so the repository needs the same `global.json` and `Microsoft.Testing.Extensions.TrxReport` reference.

`shortcuts` sets where the installer creates shortcuts to the app: a comma separated list of `Desktop`, `StartMenuRoot`, `StartMenu` and `Startup`, or `None`. Left empty, Velopack creates them on the desktop and in the Start menu. A command-line app passes `None`, since its shortcut would only open a console window that closes again. Velopack doesn't add the app to `PATH` either, so a command-line app does that itself in its install and uninstall hooks. For a NativeAOT app `vpk` can't inspect `Main` and skips its check for `VelopackApp.Build().Run()`, so nothing catches a missing call.

`plain-portable: true` makes the portable archive a zip of the published files instead of Velopack's portable package, whose launcher runs a command-line app in a window that closes right away. The files sit in a folder named after `package-name`, so extracting the archive gives that folder. The archive keeps its name, `<package-name>-<runtime>-Portable.zip`, and is uploaded and attested together with the setups once they are verified. Since it is the publish folder as it is, the project has to keep files it doesn't need to ship, such as `.pdb` files, out of it.

An app that uses ImageSharp 4 or later only builds in Release with its license key. Pass the repository secret `SIXLABORS_LICENSE_KEY` to `app-ci.yml` and `app-publish.yml`; they hand it to MSBuild as the environment variable `SixLaborsLicenseKey`, which also keeps the `;` inside the key intact. Dependabot's pull requests can't read Actions secrets, so set the key as a Dependabot secret as well, or their CI fails:

```bash
gh secret set SIXLABORS_LICENSE_KEY --app actions
gh secret set SIXLABORS_LICENSE_KEY --app dependabot
```

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

## Consuming: a VS Code extension

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
    uses: Der-Floh/Der-Floh/.github/workflows/vscode-extension-ci.yml@v1
    with:
      test-command: npm test
      required-files: |
        out/extension.js
```

`.github/workflows/publish.yml`:

```yaml
name: Publish Release

on:
  release:
    types: [published]

concurrency:
  group: vscode-extension-publish
  cancel-in-progress: false

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  publish:
    uses: Der-Floh/Der-Floh/.github/workflows/vscode-extension-publish.yml@v1
    with:
      test-command: npm test
      required-files: |
        out/extension.js
      vs-marketplace: true
      open-vsx: true
    secrets:
      OPEN_VSX_TOKEN: ${{ secrets.OPEN_VSX_TOKEN }}
```

Both files repeat the build inputs, since each workflow builds the extension on its own.

The extension is an npm project at the repository root. `vsix-pack` runs `npm ci` and then `vsce package`, which runs the extension's `vscode:prepublish` script, so whatever that script builds needs no input here. The VSIX is written as `artifacts/<name>-<version>.vsix`, and before anything else the action checks that `package-lock.json` carries the same version as `package.json`.

- `check-command` runs after `npm ci`, typically linting and unit tests that `vscode:prepublish` does not already cover.
- `build-command` runs after `npm ci` for anything else `vscode:prepublish` does not build.
- `test-command` runs the extension's tests, for example with `@vscode/test-electron`, after the build. It runs under `xvfb-run`, since VS Code needs a display even when it is tested.
- `required-files` lists paths or glob patterns, relative to the extension root, that must each match a file in the VSIX. The run fails if one is missing, and the log always shows what the VSIX contains.
- `pack-dependencies` stays `false` for a bundled extension, which vsce then packs with `--no-dependencies`. Set it for an extension that ships its `node_modules`.
- `artifact-name` names an artifact of an earlier job of the same run, such as helper binaries, that is downloaded into `artifact-path` before anything is built or tested. The extension's job has to need that job, and `.vscodeignore` must not exclude the files. Artifacts do not keep the executable bit, so the extension has to set it on a helper before running it on Linux and macOS.

In CI, the `Check` job runs `check-command` and the `Test` job runs `test-command`; each is skipped when its command is left out. The `Package` job packs every push and keeps the VSIX as an artifact for `retention-days`, so each push leaves a build to try out.

A release is built from its tag, which must be a plain version such as `v1.2.3`: VS Code extensions carry no prerelease labels in their version. `package.json` and `package-lock.json` must both carry that version, so bump them together with `npm version 1.2.3 --no-git-tag-version`; the run fails before releasing anything otherwise.

The `Pack` job runs everything the extension's CI runs, in one job: `check-command`, `build-command`, `test-command`, packing and the content check. The VSIX that passed is uploaded to the release and, in a public repository, attested. Unless the release is a prerelease, the same file then goes to every registry that is switched on:

- `vs-marketplace: true` publishes it to the **Visual Studio Marketplace** as the Entra app registration described below;
- `open-vsx: true` publishes it to **Open VSX** with the `OPEN_VSX_TOKEN` secret.

Both are off unless set. A prerelease only gets the VSIX on the GitHub release. Unticking *pre-release* afterwards does not publish it, since GitHub reports that as `released` rather than `published`; release a new version instead.

The registries skip a version they already have, so a failed registry job can be retried with **Re-run failed jobs**. Do not use *Re-run all jobs*: it rebuilds the VSIX, which replaces the file on the release while the registries keep the first build. Do not turn on immutable releases either, since the VSIX is attached after the release is published.

The Marketplace job runs in the environment `vs-marketplace`, which GitHub creates in the calling repository on the first run and which the app's federated credential requires; limiting its deployments to tags matching `v*` is optional hardening. Callers pass neither `azure-client-id` nor `azure-tenant-id`, whose defaults name the app all Der-Floh and Florian-Noever extensions share.

`OPEN_VSX_TOKEN` is an access token from *Settings > Access Tokens* at <https://open-vsx.org>. The publisher's namespace has to exist on Open VSX; create it once with `npx ovsx create-namespace <publisher> -p <token>`. Open VSX refuses an extension whose `extensionDependencies` it cannot resolve, and many extensions depend on one that is only on the Visual Studio Marketplace. So when `open-vsx` is on, `open-vsx-verify` fails the run before anything is released unless the namespace and every dependency are on Open VSX, and also if the token is missing; leave `open-vsx` off for such an extension. The Open VSX job runs without the `id-token` permission, since ovsx would otherwise try Open VSX's trusted publishing on its own instead of the token.

As for apps, the secrets and the permissions block belong to the calling repository.

## Setting up Visual Studio Marketplace publishing

Azure DevOps retires global personal access tokens on 2026-12-01, and a Marketplace token has to be one, so publishing with a token such as `VS_MARKETPLACE_TOKEN` stops working then. `vscode-extension-publish.yml` therefore publishes through Microsoft Entra ID: the Marketplace job exchanges its GitHub OIDC token for the identity of an Entra app registration through `azure/login`, and `vsce publish --azure-credential` publishes as that identity. No Marketplace secret is stored anywhere.

The Der-Floh and Florian-Noever extensions share one app registration, *Marketplace publishing* in the [Microsoft Entra admin center](https://entra.microsoft.com), set up in [Florian-Noever/Florian-Noever](https://github.com/Florian-Noever/Florian-Noever/blob/main/.github/CI.md). Its client and tenant ids are the defaults of `azure-client-id` and `azure-tenant-id`. The app publishes as its own identity, not as the Microsoft account that owns the publishers, so publishing for Der-Floh needs two things of its own:

1. A flexible federated credential for Der-Floh, next to the Florian-Noever one under *Certificates & secrets > Federated credentials*: scenario *Other issuer*, issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange` and this claims matching expression:

   ```text
   claims['sub'] matches 'repo:Der-Floh*:environment:vs-marketplace' and claims['repository_owner_id'] eq '65826571' and claims['job_workflow_ref'] matches 'Der-Floh/Der-Floh/.github/workflows/vscode-extension-publish.yml@*'
   ```

   One credential can't cover both accounts: the expression language only has `matches`, `eq` and `and`, and `repository_owner_id` only takes `eq`. Without a matching credential `azure/login` fails with AADSTS70021 or AADSTS700213 (no matching federated identity record); a new credential can also fail that way for a few minutes until it has propagated.
2. Membership of the publisher `der-floh`. The app has to be a member of every publisher it publishes for: add its Azure DevOps profile id `2d606464-bbba-692d-82a1-8a8087448ef0` under *Members* of the publisher at <https://marketplace.visualstudio.com/manage/publishers> with the *Contributor* role. The id belongs to the app, so it is the same for every publisher. Without the membership the Marketplace refuses the app with `The requested operation is not allowed`, and the failed job prints the id in a notice.

The credential accepts the Marketplace job of this workflow in any repository of the account, and nothing else. The owner is matched by its numeric id, which survives renames, and `repo:Der-Floh*` covers both the name-based subject of repositories created before 2026-07-15 and the immutable `repo:Der-Floh@65826571/<repository>@<id>` subject of newer ones. So a new extension needs no setup in Entra or in its repository's settings. Once an extension publishes through the app, its `VS_MARKETPLACE_TOKEN` secret and the token behind it can go.

Flexible federated credentials are still a preview. Should they stop working, give each repository a classic credential instead (scenario *GitHub Actions deploying Azure resources*, entity type *Environment*, environment `vs-marketplace`) and check its subject: the portal proposes the immutable format, which only matches repositories created after 2026-07-15 or opted in to it. `gh api /repos/Der-Floh/<repository>/actions/oidc/customization/sub` shows which format a repository uses.

Marketplace publishing can be a reusable workflow, unlike NuGet publishing below, because a federated credential only checks the claims it names. In a reusable workflow the subject names the calling repository and its environment, while `job_workflow_ref` names the shared workflow:

```text
sub              = repo:Der-Floh/Vortex-Extension-Helper:environment:vs-marketplace
job_workflow_ref = Der-Floh/Der-Floh/.github/workflows/vscode-extension-publish.yml@refs/tags/v1
```

so the Marketplace job can stay in the shared workflow, and the credential even requires it to.

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

## Consuming: a tool

A tool is a .NET Framework app whose only release is its exe on GitHub, without an installer or a store.

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
    uses: Der-Floh/Der-Floh/.github/workflows/tool-ci.yml@v1
    with:
      project-path: M918DAB-Formatter/M918DAB-Formatter.csproj
```

`.github/workflows/publish.yml`:

```yaml
name: Publish Release

on:
  release:
    types: [published]

concurrency:
  group: tool-publish
  cancel-in-progress: false

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  publish:
    uses: Der-Floh/Der-Floh/.github/workflows/tool-publish.yml@v1
    with:
      project-path: M918DAB-Formatter/M918DAB-Formatter.csproj
```

`tool-pack` builds the project with the .NET Framework MSBuild of the runner's Visual Studio rather than `dotnet build`, whose MSBuild cannot embed non-string resources, such as a form's icon, in a .NET Framework app and fails with `MSB3822`/`MSB3823`. `windows-latest` has run Visual Studio 2026 since June 2026, so projects on C# 14 build as well.

A release is built from its tag, which must be a version such as `v1.2.3` or `v1.2.3-beta.1`. The version reaches the exe through `-p:Version`, so the project has to generate its assembly info, as SDK-style projects do by default. The run fails before releasing anything if the exe's product version differs from the tag.

The exe is the only file released, so it has to embed every library it uses, for example with [Costura.Fody](https://github.com/Fody/Costura), and the run fails before releasing anything if the build leaves a DLL next to it. The `.exe.config` and the `.pdb` stay behind as well, so the app has to run without them; Costura resolves the embedded libraries by name, which makes the binding redirects in the `.exe.config` unnecessary. The exe keeps its name, so a new version can replace the old file in place.

The exe is uploaded to the release and attested, prereleases included, since there is no store to hold them back from. `tool-ci.yml` builds every push the same way, as version `0.0.0-ci.<run number>`, and keeps the exe as an artifact for `retention-days`, so each push leaves a build to try out. As for apps, the permissions block belongs to the calling repository.

## Consuming: Dependabot auto-merge

`dependabot-automerge.yml` merges a Dependabot pull request once the repository's own checks passed. Add it to the repository's CI after every other job, here for an app:

```yaml
  automerge:
    needs: ci
    permissions:
      contents: write
      pull-requests: write
    uses: Der-Floh/Der-Floh/.github/workflows/dependabot-automerge.yml@v1
```

Nothing is merged unless every job in `needs` succeeded. The merge only happens on `pull_request` runs that Dependabot started for its own pull request; on every other run the job is skipped, and a pull request that someone else pushed commits to is left for a review. Dependabot's runs get a read-only token, and the `permissions` of the calling job are what let this one merge. The repository has to allow squash merging.

`dependabot-merge` only merges minor and patch updates, judged by the update type [dependabot/fetch-metadata](https://github.com/dependabot/fetch-metadata) reports; for a group it is the largest change in the group. Major updates, and updates whose type is unknown, stay open with a notice, since a green CI does not prove that nothing the tests miss broke. When several pull requests finish together, GitHub refuses a merge while it still settles the base branch another one just changed, so the merge is tried up to five times, ten seconds apart. A pull request that conflicts after all is rebased by Dependabot, which runs the checks and this job again.

Dependabot itself is set up in the repository's `.github/dependabot.yml`. For NuGet, `directory` or `directories` must point at the folders that directly hold the solution or project files: Dependabot does not search subfolders for them.

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

Consumers track a moving major tag. Tags are annotated:

```bash
git tag -a vX.Y.Z -m "Short summary of the change"
git tag -fa v1 -m "Latest v1.x of the shared CI workflows and composite actions" "vX.Y.Z^{commit}"
git push origin vX.Y.Z && git push -f origin v1
```

`^{commit}` points `v1` at the release's commit. Naming the annotated tag `vX.Y.Z` itself would make `v1` a tag of a tag.

Two things to remember when cutting a new major:

- `winget-update` references `setup-wingetcreate`, `velopack-pack` references `setup-vpk`, and `vsix-pack` references `vscode-test`, by an **absolute** path pinned to `@v1`. A relative `./` path would resolve against the *calling* repository, which does not contain these actions. Bump those refs with the tag.
- `library-ci.yml`, `app-ci.yml`, `app-publish.yml`, `app-publish-winget.yml`, `extension-ci.yml`, `extension-publish.yml`, `vscode-extension-ci.yml`, `vscode-extension-publish.yml`, `nexus-publish.yml`, `tool-ci.yml`, `tool-publish.yml` and `dependabot-automerge.yml` reference the actions the same way, for the same reason, and `app-publish.yml` calls `app-publish-winget.yml` by its `@v1` path.

The vsce and ovsx versions are pinned as input defaults, which Dependabot does not see, so bump them by hand and keep the two vsce pins equal:

- `vsce-version` of `vsix-pack`, default `4.0.0`;
- `vsce-version` of `vs-marketplace-publish`, default `4.0.0`;
- `ovsx-version` of `open-vsx-publish`, default `1.2.0`.

### Pinning `publish-nuget`

`publish-nuget` is the one action holding a nuget.org publishing credential. Anything able to
push here or retarget `v1` could mint short-lived nuget.org keys for every library
that references it. Pin that one action to a commit SHA if you would rather not have
it move implicitly:

```yaml
uses: Der-Floh/Der-Floh/.github/actions/publish-nuget@<sha>
```

Dependabot updates SHA pins and annotates them with the version.

The Marketplace identity is held the same way: anything able to push here or retarget `v1` decides what runs as the Entra app for every extension that calls `vscode-extension-publish.yml@v1`. Pinning that call to a SHA only freezes the workflow itself, since it uses its actions by `@v1`. The app is shared with Florian-Noever and is a member of both publishers, and the publisher comes from the VSIX, so this repository and Florian-Noever/Florian-Noever can each publish for both publishers.
