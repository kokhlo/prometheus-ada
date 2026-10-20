# Contributing

Thanks for considering a contribution!

## Getting started

You need [Alire](https://alire.ada.dev) with a GNAT toolchain (`alr toolchain`).

```bash
git clone https://github.com/kokhlo/prometheus-ada
cd prometheus-ada
alr build
```

## Running the tests

The suite must pass before any change is merged:

```bash
gprbuild -p -P prometheus_tests.gpr && ./bin/prometheus-tests
```

Note: `alr test` only checks compilation — it does not run the binary.

## What gets reviewed

- **Text-format correctness.** Cite the section of the [Prometheus
  exposition format](https://prometheus.io/docs/instrumenting/exposition_formats/)
  your change relates to, both in code comments and in the PR description.
  Value rendering must stay token-valid: `NaN`, `+Inf`, `-Inf`, decimals
  with a leading `-` for negatives.
- **Tests.** Bug fixes need a regression test that fails without the fix.
  New features need tests covering the normative cases (valid input
  accepted, each invalid class rejected).
- **Style.** The test build runs with `-gnatwa` — all warnings on. A change
  that compiles with a warning does not build.
- **No new dependencies.** Stdlib/GNAT only.

## Commit style

Conventional commits (`fix:`, `feat:`, `docs:`, `chore:`, `test:`),
one logical change per commit.

## Releasing

Maintainers only: bump `version` in `alire.toml`, commit, tag `vX.Y.Z`,
push the tag — the [release workflow](.github/workflows/release.yml)
checks the tag against the manifest version, reruns the tests, and
publishes the GitHub Release with a source archive and its sha512.
Afterwards submit the new version to the
[Alire index](https://github.com/alire-project/alire-index).
