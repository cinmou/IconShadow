# Icon Shadow artwork

Open [IconShadow.icon](IconShadow.icon) with Icon Composer. This is the editable application icon, already registered in `IconShadow.xcodeproj`.

The composition uses Apple's Liquid Glass Icon Composer format with a mint-teal automatic-gradient background (`extended-srgb:0.00,0.784,0.702,1.0`) and two overlapping continuous-curvature superellipse (`squircle`) vector groups rotated `−8°`:

- **Front Frosted Tile (`01-Front-Glass.svg`)**: A frosted Liquid Glass tile (`glass: true`, `opacity: 0.78`, `blur-material: 0.55`, `translucency: 0.24`, `specular: true`) with an 80% neutral depth shadow.
- **Shadow Echo (`02-Back-Echo.svg`)**: An offset luminous mint-white glass layer (`lighten` blend mode) refracted beneath the frosted front tile, representing layered icon depth and cast shadow.

All lighting, specular highlights, blur refraction, and appearance adaptations (Default, Dark, Clear, Tinted) are computed natively by Icon Composer / `actool`. `Preview.png` is exported from the compiled app bundle via `scripts/preview-app-icon.swift` for repository display.

Apple's workflow: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
