# CI build workflow (not yet active)

`build.yml` here is the GitHub Actions workflow that builds the per-board Suicide
bundles (`bootloader.bin` / `partitions.bin` / `boot_app0.bin` / `app.bin`) the
headless flasher downloads. It lives under `ci/` rather than `.github/workflows/`
because the token used for the initial push lacked the `workflow` OAuth scope.

**To activate it:**

```bash
gh auth refresh -s workflow          # grant the workflow scope (interactive)
git mv ci/build.yml .github/workflows/build.yml
git commit -m "Enable CI: per-board suicide bundle builds"
git push
```

CI builds are always `SUICIDE_SAFE_MODE` and never a live-`brick` build (see
`docs/SPIKE-PLAN.md` and `docs/SAFETY.md`).
