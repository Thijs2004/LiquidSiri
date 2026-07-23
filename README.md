# LiquidSiri 🔮🌊

Make your Siri look smart! A premium liquid glass Siri interface with dynamic Metal wave visualizations and Swift glass orb rendering for iOS.

## Features
- **Liquid Glass Orb Framework (`LiquidGlassKit/`)**: Pure Swift & Metal implementation of the glass orb UI, effect views, sliders, switches, and lens views (`LiquidGlassView.swift`, `LiquidGlassEffectView.swift`, `LiquidLensView.swift`).
- **Liquid Glass Shader Engine**: Real-time glass refractive rendering using Metal shaders (`LiquidGlassKit/Sources/LiquidGlassKit/LiquidGlassFragment.metal`, `Shared/SiriWave.metal`).
- **Dynamic Wave Animations**: SwiftUI audio wave manager and visualization engine (`SwiftUIWave/`).
- **Interactive Preference Bundle**: Full customization UI with live editor panel in `liquidsiriprefs/`.
- **System Integration**: Hooks into `SUICOrbView`, `SiriUIBackgroundBlurViewController`, and SpringBoard audio levels (`Tweak.x`).

## Compatibility
- **iOS 14.0 - 16.x**
- Architectures: `arm64`, `arm64e`
- Supports both **Rootless** and **Rootful** jailbreaks.

## Repository Structure
- 📁 **`LiquidGlassKit/`**: The complete **Swift Glass Orb** framework (`LiquidGlassView.swift`, `LiquidGlassSlider.swift`, `LiquidLensView.swift`, `ZeroCopyBridge.swift`, `Package.swift`).
- 📁 **`SwiftUIWave/`**: SwiftUI views & models driving the Siri voice wave response.
- 📁 **`Shared/`**: Glass rendering engine, back button support, and Metal shader source code (`SiriWave.metal`).
- 📁 **`Runtime/`**: C/Objective-C runtime hooks and screen/banner snapshotting.
- 📁 **`liquidsiriprefs/`**: PreferenceLoader bundle for settings customization.
- 📄 **`Tweak.x`**: Primary hooks for Siri UI & SpringBoard backdrop capture.

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

## Developer & Contributions
Developed by **Thijs Mussig**. Pull requests and contributions are welcome!
