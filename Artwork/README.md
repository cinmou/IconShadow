# Icon Shadow artwork

Open [IconShadow.icon](IconShadow.icon) with Icon Composer. This is the editable application icon, already registered in `IconShadow.xcodeproj`.

The composition uses the native automatic-gradient background (#A6C3DD), a white SVG face (#F8FBFF) and a blue SVG edge (#AEC4DA). The face sits above the edge in the layer list; the SVGs share a 1024 × 1024 coordinate system and a −10° rotation. Keep the face above the edge when reordering. There are no letters, slogans, baked shadows or raster textures. The application-window mark uses the separately attributed Lucide vector.

The two artwork layers form one physical tile, so their group uses Combined lighting and a neutral shadow at 80%. The white face has glass off to keep its surface opaque; the edge retains native material effects. Background, enclosure, group shadow and appearance behavior belong to Icon Composer. The preview is a flattened image only for review.

The document has been opened in Icon Composer 27.1 and compiled with Xcode 27.1 on macOS 27.0.1. The compiled app contains an `Assets.car` and a compatibility ICNS; the modern image was checked via Icon Services using a disposable application copy to avoid the previous icon's system cache.

Apple's workflow: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer

## Application symbol

`Assets/03-App-Window.svg` adapts Lucide's `app-window-mac` geometry, under the ISC License (see `ThirdParty/Lucide-LICENSE.txt`), with a deep blue-gray stroke. It is a separate foreground layer. Its scale and horizontal position follow the existing Tile Face layer, with a 75 pt downward optical adjustment to center the symbol in the visible, top-cropped face; the outer plate layers are unchanged. The symbol artwork shares the tile's −10° tilt.

Source: https://github.com/lucide-icons/lucide/blob/main/icons/app-window-mac.svg

Apple's SF Symbols are not included in the logo because Apple's HIG prohibits their use in app icons/logos: https://developer.apple.com/design/human-interface-guidelines/sf-symbols
