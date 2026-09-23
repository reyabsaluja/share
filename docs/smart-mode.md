# Smart mode, .shareignore and secrets scanning

## What smart mode does

With `--smart` (or `smart: true` in config), each folder is copied to the scratch directory with exclusions applied, and the copy is what gets zipped or shared. The original is never touched.

The copy is built from, in order:

1. **Built-in rules** (`ExcludeRules.alwaysExcluded`): `.git`, `.hg`, `.svn`, `.DS_Store`, `Thumbs.db`, `.env` and `.env.*` (except `.env.example`, `.env.sample`, `.env.template`), `node_modules`, `.build`, `.swiftpm`, `DerivedData`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `target`, `dist`, `.next`, `.nuxt`, `Pods`, `.gradle`, `build`, `venv`, `.venv`, `.cache`, `.parcel-cache`, `.turbo`, `.idea`, `.vscode`, `*.pyc`, `*.log`, `.terraform`, `.direnv`.
2. **Project rules**, chosen by the files at the folder root:

   | Detected by | Type | Extra exclusions |
   |-------------|------|------------------|
   | `package.json` | node | `.svelte-kit`, `.output`, `coverage`, `.eslintcache`, `*.tsbuildinfo` |
   | `Package.swift` | swift | `Packages`, `xcuserdata` |
   | `*.xcodeproj` / `*.xcworkspace` | xcode | `xcuserdata`, `*.xcarchive`, `Carthage/Build` |
   | `Cargo.toml` | rust | `target` |
   | `go.mod` | go | `vendor`, `*.test` |
   | `Gemfile` | ruby | `vendor/bundle`, `.bundle`, `tmp`, `log`, `coverage` |
   | `mix.exs` | elixir | `_build`, `deps`, `.elixir_ls`, `*.beam` |
   | `composer.json` | php | `vendor`, `.phpunit.result.cache` |
   | `pubspec.yaml` | dart | `.dart_tool`, `.pub-cache`, `.flutter-plugins*` |
   | `requirements.txt`, `pyproject.toml`, `setup.py`, `Pipfile` | python | `*.egg-info`, `.tox`, `.nox`, `htmlcov`, `.coverage`, `.eggs`, `.ipynb_checkpoints` |
   | `pom.xml`, `build.gradle(.kts)` | java | `.gradle`, `out`, `*.class`, `.settings`, `.classpath`, `.project` |
   | `*.csproj`, `*.sln`, `*.fsproj` | dotnet | `bin`, `obj`, `*.user`, `.vs`, `packages`, `TestResults` |

3. **`.gitignore`**: when the folder is a git repository root and `gitignore` is not disabled, the file list comes from `git ls-files --cached --others --exclude-standard` (tracked + untracked-not-ignored). Deleted-but-tracked files are skipped. Submodules are walked with the same rules.
4. **`.shareignore`** in the folder root.
5. **`--exclude` patterns** from the command line.

`--exclude` without `--smart` applies only `.git`, `.DS_Store`, `.shareignore` and the given patterns.

Symlinks that point outside the folder are skipped; symlinks inside it are copied as symlinks.

## .shareignore syntax

Gitignore semantics, evaluated top to bottom with the last match winning:

```gitignore
# comments and blank lines are ignored
*.log            # any file or folder called *.log at any depth
build/           # only directories named build
/dist            # only the top-level dist
docs/*.pdf       # a slash in the middle anchors to the root
**/cache         # explicit "any depth"
!important.log   # re-include (unless a parent directory is excluded)
```

Patterns are matched with `fnmatch`; `*` also crosses `/` so `src/**/*.test.js` works as expected.

## Secrets scanning

Before any folder leaves the machine, it is scanned (after exclusions, so smart mode makes the scan quieter):

- **File names** (case-insensitive globs): `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `*.ppk`, `id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519`, `*.ovpn`, `credentials.json`, `service-account*.json`, `client_secret*.json`, `.npmrc`, `.pypirc`, `.netrc`, `.htpasswd`, `secrets.{yml,yaml,json}`, `*.kdbx`, `*.asc`, `*.gpg`, `known_hosts`. Names ending in `.example`, `.sample`, `.template`, `.dist`, `.pub` are considered safe.
- **File contents** (text files up to 512 KB, at most 5000 files, binaries skipped): private-key blocks, AWS access keys (`AKIA…`), GitHub (`ghp_`, `gho_`, `github_pat_`…), GitLab (`glpat-`), Slack (`xox…`), Stripe live keys (`sk_live_`), Google API keys (`AIza…`), Anthropic (`sk-ant-`), OpenAI (`sk-proj-`), npm (`npm_`), SendGrid (`SG.`), Hugging Face (`hf_`).

When something is found you see the list and a `Share anyway? [y/N]` prompt on `/dev/tty`. With `--yes` the share continues after printing the list; without a terminal it is refused (exit 6) unless `--yes`.

`share preview . --smart` shows both the exclusions and the remaining sensitive files without sharing anything. `skipSecretsScan: true` disables the scan entirely.

## Size guards

- Packaging `/`, `/Users`, `/Volumes`, `/System`, `/private` is always refused (exit 12).
- Packaging your home directory is refused unless `--yes`.
- Folders over 1 GB or 50 000 files (after exclusions) prompt before packaging.
- Email attachments over 25 MB prompt; Messages attachments over 100 MB warn.
