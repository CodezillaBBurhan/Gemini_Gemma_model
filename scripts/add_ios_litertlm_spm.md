# Add LiteRT-LM to the iOS Runner (manual)

Automatic SPM resolution of `google-ai-edge/LiteRT-LM` can hang `xcodebuild -list` in CI/headless environments. Add the package in Xcode once on a developer machine:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. File → Add Package Dependencies…
3. URL: `https://github.com/google-ai-edge/LiteRT-LM`
4. Version: Up to Next Major from `0.12.0` (or pin `0.15.0` when available as a tag).
5. Add product **LiteRTLM** to the **Runner** target.
6. Build & run on a **physical iPhone** (simulator is insufficient for validation).

Until LiteRTLM is linked, `ModelManager.checkCompatibility()` reports unsupported / `RUNTIME_UNAVAILABLE`. There is **no cloud fallback**.
