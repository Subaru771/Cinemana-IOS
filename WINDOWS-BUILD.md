# GitHub Web build from Windows

1. Open your **Subaru771/Cinemana-IOS** repository.
2. On the Code tab use Add file > Upload files. Drag in the contents of this extracted directory, **not** the ZIP. Keep `CinemanaMobile/`, `Tests/` and `project.yml` at the repository root. Do not upload only README files.
3. Replace the existing source files (the whole `CinemanaMobile` directory including `PlaybackPlanner.swift`). Commit changes to `main`.
4. Keep your existing green GitHub Actions workflow. You can use `.github/workflows/ios.yml` from this archive if you need a separate compile/test workflow; do not create multiple identical workflows unnecessarily.
5. Open Actions and select the build, or run it manually. Read the compile log if the run is red.
6. If it succeeds, download the unsigned IPA in Artifacts. Installation/signing can be addressed separately later.

**Note:** Some web uploads of folders preserve file paths; confirm `CinemanaMobile/PlaybackPlanner.swift` is visible in the browser after committing. GitHub Actions macOS minutes on private repositories are metered.
