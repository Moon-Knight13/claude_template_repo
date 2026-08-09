# CI Script Hooks

`ci.yml` detects language markers at the **repository root** and runs the
matching hook from this folder.

| Marker at repo root | Hooks run |
| --- | --- |
| `package.json` | `lint-node.sh`, `test-node.sh` |
| `pyproject.toml` or `requirements.txt` | `lint-python.sh`, `test-python.sh` |
| `go.mod` | `lint-go.sh`, `test-go.sh` |
| `Cargo.toml` | `lint-rust.sh`, `test-rust.sh` |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | `lint-java.sh`, `test-java.sh` |

The template ships no hooks — each project writes the ones matching its stack.
If a marker is detected and its hook is absent, CI logs a notice naming the
missing script and continues. Add the script to turn that gate on.

Detection is **root-only**. A package nested in a subdirectory is invisible to
it, so a project whose only `package.json` lives at, say, `tools/build/` gets no
Node gate and no warning. Give those their own workflow rather than trying to
make detection recurse — this is an easy way to end up with a test suite that
silently never runs in CI.
