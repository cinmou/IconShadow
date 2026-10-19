# Changelog

## 1.0.1 — 2026-10-19

- Fix finished icons becoming too small or vertically offset when trimming: fit the main artwork instead of including its faint exterior shadow.
- Validate the 824 px body against Affinity and Claude ICNS samples; retain support for fully translucent artwork.

## 1.0.0 — 2026-10-19

Initial release.

- Import PNG and ICNS artwork by drag and drop or file picker.
- Trim transparent edges, preserve aspect ratio and adjust scale/position.
- Apply a continuous-corner mask and configurable alpha-based Gaussian shadow.
- Compare the original and processed icon on light or dark backgrounds.
- Export a 1024 × 1024 PNG or a multi-resolution ICNS.
- Include macOS 26 and macOS 27 presets.
- Support English and Simplified Chinese.
- Add a layered Icon Composer application icon.
