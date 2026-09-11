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
| `setup-dotnet` | both | Installs the SDK and restores the NuGet cache |
| `resolve-version` | both | Validates a release tag and reports the version it carries |
| `pack` | library | Restores, builds and packs deterministically |
| `verify-package` | library | Validates the `.nupkg` against NuGet packaging rules |
| `publish-nuget` | library | OIDC login and push of package + symbols |
| `create-zip` | app | High-compression archive of a publish directory |
| `create-msi` | app | Builds an MSI with Advanced Installer |
| `verify-msi` | app | Installs, checks registration, uninstalls |
| `resolve-release-asset` | app | Finds a released asset and its digest |
| `verify-manifest` | app | Asserts WinGet manifests match the released installer |
| `resolve-winget-mode` | app | Decides create / update / skip |
| `setup-wingetcreate` | app | Downloads and hash-verifies `wingetcreate.exe` |
| `winget-publish` | app | Submits manifests for a new package |
| `winget-update` | app | Submits a new version of an existing package |

| Reusable workflow | Purpose |
| --- | --- |
| `library-ci.yml` | Build matrix, optional test job, pack a preview, verify it |
| `app-ci.yml` | Build matrix, optional Windows publish smoke test |
| `app-publish.yml` | Publish, MSI, archive, attest, release upload and WinGet submission |

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
      publish-path: Cursor_Installer_Creator.Desktop/bin/Publish
      aip-path: .github/CursorInstallerCreator.aip
      product-name: Cursor Installer Creator
      package-name: CursorInstallerCreator
      winget-package-id: Der_Floh.CursorInstallerCreator
    secrets:
      ADVINST_LICENSE_KEY: ${{ secrets.ADVINST_LICENSE_KEY }}
      WINGET_CREATE_GITHUB_TOKEN: ${{ secrets.WINGET_CREATE_GITHUB_TOKEN }}
```

The secrets have to be set on the **calling** repository. A reusable workflow never sees the
secrets of the repository that stores it — this repository is public, so if it did, anyone
could call the workflow and run it with these credentials. The permissions block is also
required on the caller: a reusable workflow cannot grant itself more than the caller has.

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

- `winget-publish` and `winget-update` reference `setup-wingetcreate` by an **absolute**
  path pinned to `@v1`. A relative `./` path would resolve against the *calling*
  repository, which does not contain these actions. Bump those refs with the tag.
- `library-ci.yml` and `app-ci.yml` reference the actions the same way, for the same
  reason.

### Pinning `publish-nuget`

`publish-nuget` is the one action holding a publishing credential. Anything able to
push here or retarget `v1` could mint short-lived nuget.org keys for every library
that references it. Pin that one action to a commit SHA if you would rather not have
it move implicitly:

```yaml
uses: Der-Floh/Der-Floh/.github/actions/publish-nuget@<sha>
```

Dependabot updates SHA pins and annotates them with the version.
