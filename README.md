# LiquidSiri 🔮🌊

Make your Siri look smart! A premium liquid glass Siri interface with dynamic Metal wave visualizations for iOS.

## Features
- **Liquid Glass Orb Shader**: Real-time glass refractive rendering using Metal shaders (`Shared/SiriWave.metal`, `Runtime/LGLiquidGlassRuntime.m`).
- **Dynamic Wave Animations**: SwiftUI audio wave manager and visualization engine (`SwiftUIWave/`).
- **Interactive Preference Bundle**: Full customization UI with live editor panel in `liquidsiriprefs/`.
- **System Integration**: Hooks into `SUICOrbView`, `SiriUIBackgroundBlurViewController`, and SpringBoard audio levels (`Tweak.x`).

## Compatibility
- **iOS 14.0 - 16.x**
- Architectures: `arm64`, `arm64e`
- Supports both **Rootless** and **Rootful** jailbreaks.

## Building from Source

### Prerequisites
- [Theos](https://theos.dev) installed and configured in `$THEOS`.
- Xcode Command Line Tools with `xcrun` (`metal` shader compiler).

### Compilation
To build the tweak package:
```bash
make package FINALPACKAGE=1
```

For rootless build:
```bash
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

## Structure
- `Tweak.x` - Primary hooks for Siri UI & SpringBoard backdrop capture.
- `Shared/` - Glass rendering engine, back button support, and Metal shader source code (`SiriWave.metal`).
- `Runtime/` - C/Objective-C runtime hooks and screen/banner snapshotting.
- `SwiftUIWave/` - SwiftUI views & models driving the Siri voice wave response.
- `liquidsiriprefs/` - PreferenceLoader bundle for settings customization.

## Developer & Contributions
Developed by **Thijs Mussig**. Pull requests and contributions are welcome!
