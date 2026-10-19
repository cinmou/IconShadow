# Static replacement icon rendering research

Research and measurements: 2026-10-19. Host: macOS 27.0.1, build 26A434; Xcode 27.1, Swift 6 language mode.

## Sources and what they establish

- [Apple Icon Composer](https://developer.apple.com/icon-composer/) and [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer): layered icon rendering, platform masks and separate 26/27 effects previews. The documented changes to materials/refraction do not establish a numeric exterior-shadow preset for a flattened replacement ICNS. No Apple-published numeric 26/27 drop-shadow specification was found in this research.
- [iccir's public-domain template generator](https://gist.github.com/iccir/053ebec1ad3a53fad3dbfbf76743ea94): an original reverse-engineering implementation, grouped explicitly as macOS 26–27. It uses `CALayer` continuous corners and a separately offset `CIGaussianBlur`, rather than assuming a graphics-context shadow has the same radius semantics. Its initial 256 px template uses a 208 px tile, 54 px continuous corner radius, black at 28%, offset 2 px and Gaussian radius 5 px. Those are the author's approximations, not Apple constants. Scaled to 1024: 832, 216, 28%, 8, 20.
- [macOS 26 exported icon archive](https://github.com/zagnut531/macOS-26-Icons), snapshot `2867e67ae2f12b972fc85e56707bea4b303bdf92`, `Calculator.png`; [macOS 27 archive](https://github.com/zagnut531/macOS-27-Icons), snapshot `f7b43e278c3726824bf662c704c10e96fc53ef97`, `Beta 5/Calculator.png`. The collector describes PNGs exported from their Mac, and records beta changes. The 27 sample is a beta snapshot; it is corroborated against this host's actual Icon Services rendering. These archives are community primary observations and can contain collection/version errors.
- [Community discussion linking the reverse engineering](https://www.reddit.com/r/MacOS/comments/1uyapb7/any_alternatives_for_macos_2627_icon_composer/), plus the [archive author's description of extraction](https://www.reddit.com/r/MacOS/comments/1u9f8x9/macos_27_icon_pack_1024x1024_png/): useful evidence about provenance and about application-bundle ICNS files differing from icons rendered by Icon Services.
- [macOSicons Toolkit](https://macosicons.com/editor/toolkit): trim, fit, mask, scale, position and shadow workflow. Publicly served Nuxt page code on the research date invokes `/api/toolkit/<tool>`; its exposed schema documents these controls, but the server-side shadow/mask algorithm was not found. Do not describe its implementation as open source. [Its submission guide](https://macosicons.com/resources/how-to-get-approved) recommends 824 px artwork.
- [macicon](https://github.com/DarkRader/macicon), snapshot `abec48e3ad9778474da033fbebee2ef902ebd949`: standard iconset names and `iconutil` export; its implementation uses 832 px tile, y offset -8 px, CGContext shadow 24%, 18 px blur and 16 px downward offset. Its mask is a circular rounded rectangle even though the README describes continuous geometry. Those defaults target an older visual baseline and are not macOS 26/27 normative values.

## Measurements and selected defaults

Read the actual icon through `NSWorkspace.icon(forFile:)`, rasterized at 1024, rather than reading the bundle's `AppIcon.icns`. The latter was only 256 px and represented the older compatibility artwork for the three local apps inspected.

For the exported 26 Calculator PNG, archived 27 Calculator PNG and this host's actual Calculator icon:

| Alpha threshold | Bounds, bottom-left origin |
| --- | --- |
| > 2/255 | x 74, y 66, width 876, height 876 |
| > 16/255 | x 90, y 82, width 844, height 844 |
| > 64/255 | x 100, y 100, width 824, height 824 |
| > 128/255 | x 100, y 100, width 824, height 824 |
| > 250/255 | x 100, y 100, width 824, height 824 |

Thus the opaque plate is 824 px, with 100 px margins and no vertical artwork shift. The shadow's low-alpha bounds are centered 8 px lower. This supersedes the initial macicon-derived defaults.

A native continuous-corner tile was compared with the host Calculator alpha silhouette. A 214 px corner radius differed in 162 binary pixels out of 1,048,576 at the >128 threshold. The renderer uses the source template's 54/208 ratio, giving 213.923 px at 824 px. This is a close approximation, not the private Icon Composer path.

For shadow calibration, compare the top and bottom straight edges at x=512, over y=40…99 and 924…983, outside the opaque plate. A coarse search was followed by a 14–17 px radius / 22–28% opacity search. The selected Core Image Gaussian model uses **25% opacity, 15 px radius and 8 px downward offset**. On the host Calculator sample its 120 alpha samples have total squared error 14 (RMSE ~0.34 on an 8-bit alpha scale). Low-alpha bounds match (74, 66, 876, 876). This fit is of a useful static model and does not establish Apple's internal implementation or pixel-perfect behavior around every corner.

This host's App Store alpha is identical to Calculator, and Notes/Preview each differ in 45 pixels. The archived 27 Calculator differs in one alpha pixel from the host sample. The archived 26 version differs in 1,941 alpha pixels but has the same bounds at every listed threshold; running the same calibration against it also selects 25%, 15 px and 8 px (SSE 14); its best 214 px continuous corner differs in 170 binary pixels. Differences in the artwork, lighting and internal highlights are visible between 26 and 27, but they do not justify inventing a separate external-shadow geometry here.

The app consequently offers separate **26** and **27** selectors with the same static values. Later evidence can change either preset independently. Parameters are baked into exported images; no private APIs or runtime Liquid Glass effects are used.

## Reproduce

```sh
swift scripts/extract-native-icons.swift build/validation/native
./scripts/calibrate.sh build/validation/native/native-Calculator.png build/validation
```

To compare archive samples, download the two PNG paths from the pinned GitHub revisions above, then pass a sample to `calibrate.sh`. Optional additional image paths after the output directory report alpha-channel differences. Generated reference images remain under ignored `build/`; Apple/community artwork is not bundled into the application or source repository.

The calibration uses an opaque application tile. It should not be applied blindly to translucent or irregular artwork, which still uses its actual alpha as the source of the shadow. Already baked shadows cannot be reliably removed automatically.

## Native UI

The window uses the system title bar/toolbar, a SwiftUI inspector, grouped Form controls and native open/save panels. There is no promotional copy. Layout decisions follow Apple's [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) and [Inspectors](https://developer.apple.com/design/human-interface-guidelines/inspectors) guidance; macOS supplies the controls' appearance. English and Simplified Chinese use system localization resources.


## 1.0.1: distinguish the body from its exterior shadow

The [macOSicons submission guide](https://macosicons.com/resources/how-to-get-approved) specifies a centered 824 × 824 px body on a 1024 × 1024 canvas, with 100 px margins, and explicitly says to measure the body rather than the shadow.

Two user-supplied finished ICNS samples confirm that size. Measurements below use the largest 1024 px representation; the input files are not redistributed.

| Sample | Alpha > 2 extent | Alpha > 128 body | 1.0.0 output body | 1.0.1 output body |
| --- | --- | --- | --- | --- |
| Affinity.icns | 876 × 876 | 824 × 824 | 776 × 775 | 824 × 824 |
| Claude.icns | 866 × 866 | 824 × 824 | 784 × 785 | 824 × 824 |

The old trim measured alpha > 2, including faint offset shadows. Fitting that rectangle to 824 px shrank and displaced the actual body. Trimming now uses alpha > 128 for artwork fitting and centering, falling back to the visible alpha > 2 rectangle when no pixels exceed 128. The full source image is retained for drawing; this change does not remove a baked-in shadow. The default scale remains 80.46875%, with opacity 25%, blur 15 px and downward offset 8 px. Both reference bodies now occupy (100, 100, 824, 824), including after ICNS export.

The regression tests use synthetic artwork with a faint offset shadow, plus a fully translucent sample; they do not depend on private local files.
