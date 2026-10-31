# Third-party notices

The release ZIP includes UE4SS and its proxy DLL from the official project:

- Project: [UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)
- Version: `3.0.1-1188-gf885e8d2`
- Upstream archive: `UE4SS_v3.0.1-1188-gf885e8d2.zip`
- Upstream archive SHA256: `4a594fb5c6e1aa794b06a770730e072c53fb92b741f95a5f0601080d80f4a6c1`
- License: MIT, Copyright (c) 2022 Narknon
- Full license: [third-party/UE4SS-LICENSE.txt](third-party/UE4SS-LICENSE.txt)

The release also retains the upstream license at `DS/Binaries/Win64/ue4ss/LICENSE`. Its configuration disables the GUI console, hot reload, and automatic Lua reload. The default bundled console and cheat-related example mods are not included in this mod's release.

Python dependencies are used only for development and tests. They are not included in the release ZIP. `lupa` is pinned in `tests/requirements.txt`.
