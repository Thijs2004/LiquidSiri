 //
//  LiquidGlassView.swift
//  LiquidGlass
//
//  Created by Alexey Demin on 2025-12-05.
//

import UIKit
import Darwin  // dlopen / dlsym / RTLD_NOW for jbroot() runtime resolution
internal import simd
internal import MetalKit
internal import MetalPerformanceShaders

struct LiquidGlass {

    /// Maximum number of rectangles supported in the shader.
    static let maxRectangles = 16

    /// Mirror the Metal 'ShaderUniforms' exactly for buffer binding.
    struct ShaderUniforms {
        var resolution: SIMD2<Float> = .zero        // Frame size in pixels.
        var contentsScale: Float = .zero            // Scale factor. 2 for Retina; 3 for Super Retina.
        var touchPoint: SIMD2<Float> = .zero        // Touch position in points (upper-left origin).
        var shapeMergeSmoothness: Float = .zero     // Specifies the distance between elements at which they begin to merge (spacing).
        var cornerRadius: Float = .zero             // Base rounding (e.g., 24 for subtle chamfer). Circle if half the side.
        var cornerRoundnessExponent: Float = 2      // 1 = diamond; 2 = circle; 4 = squircle.
        var materialTint: SIMD4<Float> = .zero      // RGBA; e.g., subtle cyan (0.2, 0.8, 1.0, 1.0)
        var glassThickness: Float                   // Fake parallax depth (e.g., 8-16 px)
        var refractiveIndex: Float                  // 1.45-1.52 for borosilicate glass feel
        var dispersionStrength: Float               // 0.0-0.02; prismatic color split on edges
        var fresnelDistanceRange: Float             // px falloff from silhouette (e.g., 32)
        var fresnelIntensity: Float                 // 0.0-1.0; rim lighting boost
        var fresnelEdgeSharpness: Float             // Power 1.0=linear, 8.0=crisp
        var glareDistanceRange: Float               // Similar to fresnel, but for specular streaks
        var glareAngleConvergence: Float            // 0.0-π; focuses rays toward light dir
        var glareOppositeSideBias: Float            // >1.0 amplifies back-side highlights
        var glareIntensity: Float                   // 1.0-4.0; bloom-like edge fire
        var glareEdgeSharpness: Float               // Matches fresnel for consistency
        var glareDirectionOffset: Float             // Radians; tilts streak asymmetry
        var rectangleCount: Int32 = .zero           // Number of active rectangles
        var rectangles: (                           // Array of rectangles (x, y, width, height) in points, upper-left origin.
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
            SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>
        ) = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero,
             .zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
        /// Motion reprojection UV offset. Zero after a fresh capture;
        /// non-zero on throttled frames when the view has moved.
        /// Written per-frame in draw() — NOT via updateUniforms().
        var captureOffset: SIMD2<Float> = .zero
        /// Scale factor between the view size at the time of the last capture and
        /// the current view size. This lets the shader reprojection handle animated
        /// resize transitions without sampling the wrong portion of the capture.
        var captureScale: SIMD2<Float> = .init(x: 1, y: 1)
        /// Mirrors backgroundTextureSizeCoefficient. Passed to the shader so it can remap
        /// input.uv into the center fraction of the capture texture, preserving edge buffer
        /// for captureOffset to shift into without immediately hitting clamp_to_edge.
        var textureSizeCoefficient: Float = 1
        /// View top-left in screen logical points. Non-zero when the shared full-screen
        /// texture is in use (non-fullQuality views). The shader uses this to compute
        /// absolute screen-space UV, eliminating the need for motion reprojection.
        var viewOriginInScreen: SIMD2<Float> = .zero
        /// Screen size in logical points. Non-zero when using the shared screen texture.
        /// Combined with viewOriginInScreen and input.uv → exact screen-space sample UV.
        var screenSizePts: SIMD2<Float> = .zero
    }

    let shaderUniforms: ShaderUniforms
    let backgroundTextureSizeCoefficient: Double
    let backgroundTextureScaleCoefficient: Double
    let backgroundTextureBlurRadius: Double
    var tintColor: UIColor?
    var shadowOverlay: Bool = false
    /// When true this view always renders at native device FPS with full shader
    /// effects (no cheap-mode reduction). Used for interactive controls (sliders,
    /// switches) where animation quality matters more than background-glass savings.
    var fullQuality: Bool = false
    /// When false the capture scheduler never runs and no backdrop/screen capture
    /// is performed — the shader renders over a transparent background only.
    /// Used for thumb views (sliders/switches) to avoid the CABackdropLayer blur.
    var autoCapture: Bool = true
    /// When true, always use the root-view render path instead of CABackdropLayer.
    /// CABackdropLayer applies an OS-level compositor blur that cannot be turned off;
    /// root-view capture (layer.render) produces a clean, unblurred snapshot.
    /// Set on thumb presets so sliders/switches show sharp glass without any blur.
    var forceRootCapture: Bool = false

    static func thumb(magnification: Double = 1) -> Self {
        .init(
            shaderUniforms: .init(
                materialTint: .zero,
                // glassThickness 10 → 6pt rim, blurLogPx stays at 1pt (no added blur).
                // refractiveIndex 0.40: UV shift at rim = 1.292×0.40 = 0.52 UV (Y axis, no clamping;
                // clamp threshold for this view size is 0.677). Gives ~20pt visual displacement.
                glassThickness: 10,
                refractiveIndex: 0.40,
                dispersionStrength: 5,
                fresnelDistanceRange: 70,
                fresnelIntensity: 0,
                fresnelEdgeSharpness: 0,
                glareDistanceRange: 30,
                glareAngleConvergence: 0,
                glareOppositeSideBias: 0,
                glareIntensity: 0.01,
                glareEdgeSharpness: -0.2,
                glareDirectionOffset: .pi * 0.9,
            ),
            backgroundTextureSizeCoefficient: 1 / magnification,
            backgroundTextureScaleCoefficient: magnification,
            backgroundTextureBlurRadius: 0,
            shadowOverlay: true,
            fullQuality: true,  // Must be true: prevents thumb from using the shared blurred capture texture.
        )
    }

    /// Like thumb but tuned for small pill elements (switches).
    /// Transparent glass pill — wide background buffer to prevent UV overflow,
    /// moderate refraction, bright fresnel rim + glare streak like iOS 26 UISwitch.
    

    static let lens = Self.init(
        shaderUniforms: .init(
            glassThickness: 6,
            refractiveIndex: 1.1,
            dispersionStrength: 15,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.1,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.1,
        backgroundTextureScaleCoefficient: 0.8,
        backgroundTextureBlurRadius: 0,
        shadowOverlay: true,
    )

    static let regular = Self.init(
        shaderUniforms: .init(
            glassThickness: 10,
            refractiveIndex: 1.5,
            dispersionStrength: 5,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.15,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.5,
        backgroundTextureScaleCoefficient: 0.5,
        backgroundTextureBlurRadius: 0.5,
        tintColor: UIColor { $0.userInterfaceStyle == .dark ? #colorLiteral(red: 0.28, green: 0.28, blue: 0.28, alpha: 0.80) : #colorLiteral(red: 0.9023525731, green: 0.9509486998, blue: 1, alpha: 0.8002892298) }
    )

    /// A deeper frosted version of regular for Home Screen banners.
    static let regularHighBlur = Self.init(
        shaderUniforms: .init(
            glassThickness: 10,
            refractiveIndex: 1.5,
            dispersionStrength: 5,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.15,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.5,
        backgroundTextureScaleCoefficient: 0.5,
        backgroundTextureBlurRadius: 0.7,
        tintColor: UIColor { $0.userInterfaceStyle == .dark ? #colorLiteral(red: 0.28, green: 0.28, blue: 0.28, alpha: 0.80) : #colorLiteral(red: 0.9023525731, green: 0.9509486998, blue: 1, alpha: 0.8002892298) }
    )

    /// Same as regular but with no material tint — fully-transparent glass with only refraction.
    /// Quality settings match .regular so blur/capture quality is identical, just without the frosted fill.
    static let clear = Self.init(
        shaderUniforms: .init(
            materialTint: .zero,  // Explicitly zero — no white/dark tint at all
            glassThickness: 10,
            refractiveIndex: 1.5,
            dispersionStrength: 5,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.1,
            glareEdgeSharpness: -0.15,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.5,
        backgroundTextureScaleCoefficient: 0.5,
        backgroundTextureBlurRadius: 0.5,
        tintColor: nil
    )

    /// Like clear but with heavier blur and no tint — for panels that sit over busy content.
    static let clearBlur = Self.init(
        shaderUniforms: .init(
            materialTint: .zero,
            glassThickness: 10,
            refractiveIndex: 1.45,
            dispersionStrength: 4,
            fresnelDistanceRange: 70,
            fresnelIntensity: 0,
            fresnelEdgeSharpness: 0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.08,
            glareEdgeSharpness: -0.15,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.5,
        backgroundTextureScaleCoefficient: 0.15,
        backgroundTextureBlurRadius: 1.2,
        tintColor: nil
    )

    /// Fully transparent — zero fill, no blur, no tint. Only edge refraction/glare.
    static let transparent = Self.init(
        shaderUniforms: .init(
            materialTint: .zero,
            glassThickness: 10,
            refractiveIndex: 1.45,
            dispersionStrength: 4,
            fresnelDistanceRange: 60,
            fresnelIntensity: 0.5,
            fresnelEdgeSharpness: 3.0,
            glareDistanceRange: 30,
            glareAngleConvergence: 0.1,
            glareOppositeSideBias: 1,
            glareIntensity: 0.5,
            glareEdgeSharpness: 0.1,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.2,
        backgroundTextureScaleCoefficient: 0.9,
        backgroundTextureBlurRadius: 0.0,
        tintColor: nil
    )

    /// Crystal-clear glass for overlaying text — strong fresnel rim + glare, zero fill/tint.
    static let clockGlass = Self.init(
        shaderUniforms: .init(
            materialTint: .zero,
            glassThickness: 14,
            refractiveIndex: 1.52,
            dispersionStrength: 10,
            fresnelDistanceRange: 60,
            fresnelIntensity: 0.85,
            fresnelEdgeSharpness: 4.0,
            glareDistanceRange: 45,
            glareAngleConvergence: 0.2,
            glareOppositeSideBias: 1.5,
            glareIntensity: 1.2,
            glareEdgeSharpness: 0.3,
            glareDirectionOffset: -.pi / 4,
        ),
        backgroundTextureSizeCoefficient: 1.2,
        backgroundTextureScaleCoefficient: 0.85,
        backgroundTextureBlurRadius: 0.0,
        tintColor: nil
    )

    /// No background capture at all — shader renders over transparent base.
    static let noCapture: Self = {
        var lg = Self.init(
            shaderUniforms: .init(
                materialTint: .zero,
                glassThickness: 10,
                refractiveIndex: 1.45,
                dispersionStrength: 4,
                fresnelDistanceRange: 60,
                fresnelIntensity: 0.5,
                fresnelEdgeSharpness: 3.0,
                glareDistanceRange: 30,
                glareAngleConvergence: 0.1,
                glareOppositeSideBias: 1,
                glareIntensity: 0.5,
                glareEdgeSharpness: 0.1,
                glareDirectionOffset: -.pi / 4,
            ),
            backgroundTextureSizeCoefficient: 1.0,
            backgroundTextureScaleCoefficient: 1.0,
            backgroundTextureBlurRadius: 0.0,
            tintColor: nil
        )
        lg.autoCapture = false
        return lg
    }()
}

final class BackdropView: UIView {

    override class var layerClass: AnyClass {
        // CABackdropLayer is a private API that captures content behind the layer
        NSClassFromString("CABackdropLayer") ?? CALayer.self
    }

    init() {
        super.init(frame: .zero)

        // Configure backdrop view
        isUserInteractionEnabled = false
        layer.setValue(false, forKey: "layerUsesCoreImageFilters")

        // Configure backdrop layer properties (private API)
        layer.setValue(true, forKey: "windowServerAware")
        // Shared group name: all LiquidGlassViews share one CABackdropLayer capture group.
        // The WindowServer only composites the background once for all views in the same group
        // instead of N separate captures — the single biggest GPU win on A11/A12.
        // Each BackdropView MUST have a unique groupName. Sharing a groupName tells
        // WindowServer to use one composited capture region for all views in the group —
        // every view would then show the same background position, causing the glass to
        // be misaligned on any view that isn't at the capture origin.
        layer.setValue(UUID().uuidString, forKey: "groupName")
//        layer.setValue(1.0, forKey: "scale")  // Full resolution for capture
//        layer.setValue(0.0, forKey: "bleedAmount")
//        layer.setValue(false, forKey: "allowsHitTesting")
//        layer.setValue(true, forKey: "captureOnly")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ShadowView: UIView {

    init() {
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.compositingFilter = "multiplyBlendMode"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let shadowRadius = 3.5
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -shadowRadius / 2), cornerRadius: bounds.height / 2)
        let innerPill = UIBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: shadowRadius / 2), cornerRadius: bounds.height / 2).reversing()
        path.append(innerPill)
        layer.shadowPath = path.cgPath
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = 0.2
        layer.shadowOffset = .init(width: 0, height: shadowRadius + 2)
    }
}

final class LiquidGlassRenderer {
    @MainActor static let shared = LiquidGlassRenderer()

    let device: MTLDevice
    let pipelineState: MTLRenderPipelineState

    /// One shared command queue for ALL LiquidGlassViews.
    /// The Metal driver serializes work per-queue; sharing one queue reduces driver overhead
    /// compared to N independent queues, and lets Metal track cross-view texture dependencies
    /// automatically (crucial for the shared async blur → render ordering).
    let commandQueue: MTLCommandQueue

    /// True on A11/A12-class hardware (iPhone X/8/11). Detected via GPU memory budget.
    /// These devices have ≤1.5 GB recommended working set vs 4 GB+ on A14+.
    let isLowPerformanceDevice: Bool

    /// Resolve a jailbreak-relative path (e.g. "/Library/LiquidGlass/…") to its real
    /// filesystem path under the active bootstrap:
    ///
    ///  • RootHide — calls jbroot() from libroothide (pre-loaded by the bootstrap) via
    ///    dlsym. RootHide installs files to /var/jb in the .deb but remaps that prefix
    ///    to a UUID-randomised hidden location at runtime; only jbroot() gives the real path.
    ///
    ///  • Rootless (Palera1n / Dopamine) — /var/jb prefix, no remapping needed.
    ///
    ///  • Rootful (Unc0ver / Taurine) — no prefix.
    static func jbRealPath(_ relativePath: String) -> String {
        // 1. Try RootHide's jbroot() — pre-loaded into every process, resolved by dlsym.
        //    libroothide exports the symbol "jbroot" as a C function: const char*(const char*)
        if let sym = dlsym(dlopen(nil, RTLD_NOW), "jbroot") {
            typealias JBRootFn = @convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?
            let fn = unsafeBitCast(sym, to: JBRootFn.self)
            if let result = relativePath.withCString({ fn($0) }) {
                return String(cString: result)
            }
        }
        // 2. Rootless: prepend /var/jb
        if FileManager.default.fileExists(atPath: "/var/jb") {
            return "/var/jb" + relativePath
        }
        // 3. Rootful: use path as-is
        return relativePath
    }

    // MARK: - View Registry

    /// Weak reference box so we can store LiquidGlassView references without
    /// preventing deallocation.
    private struct WeakViewRef {
        weak var view: LiquidGlassView?
    }
    private var activeViewRefs: [ObjectIdentifier: WeakViewRef] = [:]

    /// Number of LiquidGlassViews currently attached to a window.
    /// Used to auto-switch to cheap mode when many glass views are visible at once.
    var activeViewCount: Int { activeViewRefs.values.filter { $0.view != nil }.count }

    /// When true, shaders skip expensive dispersion/glare and capture runs at reduced scale.
    /// Automatically true on low-perf devices or when > 2 views are active.
    var shouldUseCheapMode: Bool {
        isLowPerformanceDevice || activeViewCount > 2
    }

    func registerView(_ view: LiquidGlassView) {
        activeViewRefs[ObjectIdentifier(view)] = WeakViewRef(view: view)
    }
    func unregisterView(_ view: LiquidGlassView) {
        activeViewRefs.removeValue(forKey: ObjectIdentifier(view))
    }

    /// Temporarily hide every registered glass view from UIKit's layer tree while
    /// `body()` runs, then immediately restore them.
    ///
    /// Purpose: `layer.render(in:)` reads MODEL-layer state, not the compositor state.
    /// Setting `layer.isHidden = true` here is seen by the render call but the
    /// compositor never processes the transient hidden state — the two CALayer assignments
    /// cancel out in the same implicit CATransaction, so zero visual flash occurs.
    ///
    /// This prevents the self-sampling feedback loop where a glass view's own Metal
    /// output is captured as its new background texture, which causes visual echoing
    /// and flickering (most visible during folder-glass fade-in and CC module captures).
    func withGlassViewsHidden(_ body: () -> Void) {
        let visible = activeViewRefs.values.compactMap(\.view).filter { !$0.layer.isHidden }
        visible.forEach { $0.layer.isHidden = true }
        body()
        visible.forEach { $0.layer.isHidden = false }
    }

    // MARK: - Global burst capture

    /// Increment this to signal ALL active LiquidGlassViews to enter burst-capture mode
    /// on their next captureSchedulerFired() tick. Use triggerGlobalBurst() to set it.
    /// Each view tracks the generation it last observed; any mismatch triggers a burst.
    private(set) var burstGeneration: Int = 0

    /// Tell every active LiquidGlassView to enter burst-capture mode.
    /// Call before a transition (CC open, folder open, App Library appear) so all glass
    /// views refresh rapidly during the animation instead of showing stale content.
    func triggerGlobalBurst() { burstGeneration += 1 }

    // MARK: - Capture suspension

    /// Absolute timestamp after which captures are no longer suspended.
    /// Views with an existing background texture skip their capture tick while
    /// CACurrentMediaTime() < capturesSuspendedUntil, keeping the last good frame
    /// instead of sampling mid-transition animated content.
    /// Views with no texture (first appearance) are exempt and always capture.
    /// After the deadline each view auto-enters burst mode to refresh cleanly.
    private(set) var capturesSuspendedUntil: CFTimeInterval = 0

    /// Freeze all existing-texture glass captures for `duration` seconds.
    /// After the window expires every view bursts to repaint with settled content.
    /// Use instead of triggerGlobalBurst() for CC/folder/App Library transitions.
    ///
    /// The shared screen texture is intentionally kept frozen during the suspension
    /// window so that any new glass views created while the animation is in flight
    /// (e.g. App Library pods, folder background) can immediately render using the
    /// pre-animation background instead of going black. Invalidation is deferred to
    /// just after the window expires, so the first post-suspension captureSharedScreen()
    /// call performs a genuine render of the settled UI rather than returning stale
    /// mid-animation content.
    func suspendCaptures(for duration: CFTimeInterval) {
        capturesSuspendedUntil = CACurrentMediaTime() + duration
        // Defer cache invalidation: cancel any previously scheduled invalidation,
        // then schedule a new one for exactly when this suspension window closes.
        pendingInvalidationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.invalidateSharedScreenCache()
            // Immediately wake all paused glass views so Metal rendering + UV tracking
            // resume without waiting for the next idle-rate display-link tick (up to 83ms).
            // Each view's next captureSchedulerFired() will detect the new burstGeneration
            // and fire a full recapture within ~16ms of waking.
            self.activeViewRefs.values.compactMap(\.view).forEach { $0.wakeFromSuspension() }
        }
        pendingInvalidationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
    private var pendingInvalidationWork: DispatchWorkItem?

    // MARK: - Shared Screen Capture
    // ONE layer.render(in:) per display frame, shared by ALL non-fullQuality glass views.
    // N glass views = N×render/frame → 1×render/frame. Eliminates CPU heat and jitter.
    private var sharedCaptureBridge: ZeroCopyBridge?
    private(set) var sharedScreenTexture: MTLTexture?
    private(set) var sharedScreenSizePts: CGSize = .zero
    private var sharedCaptureLastTimestamp: CFTimeInterval = -1

    /// True after the first successful shared screen capture.
    /// When frozen, captureSharedScreen() returns the cached texture immediately —
    /// zero layer.render(in:) or MPS blur work. Liquidass-style: "blur is baked once
    /// and reused until settings or source content actually require a rebake."
    /// Reset by invalidateSharedScreenCache() on content changes (LGSuspendCaptures, etc.).
    private(set) var sharedScreenFrozen = false

    /// Discard the shared screen texture so the next captureSharedScreen() call re-captures.
    /// Call whenever the content behind the glass changes (CC transition, folder open,
    /// wallpaper change). LGSuspendCaptures() already calls this automatically.
    func invalidateSharedScreenCache() {
        sharedScreenTexture = nil
        sharedScreenSizePts = .zero
        sharedCaptureLastTimestamp = -1
        sharedScreenFrozen = false
        // sharedCaptureBridge is reused; it will be reconfigured on the next capture.
    }

    /// Capture the full screen into a shared texture. Call from any glass view's capture tick.
    /// The FIRST call in a given display frame does the actual render; every subsequent call
    /// in the same frame returns the cached texture instantly — no duplicate renders.
    /// After the first successful capture the texture is frozen (no further re-renders) until
    /// invalidateSharedScreenCache() is called.
    func captureSharedScreen(from rootView: UIView, timestamp: CFTimeInterval) -> MTLTexture? {
        // Frozen: skip render entirely — return the cached blurred texture.
        // The homescreen wallpaper virtually never changes between transitions; re-rendering
        // 30× per second is pure heat generation with no visual benefit.
        if sharedScreenFrozen, let tex = sharedScreenTexture { return tex }
        if timestamp == sharedCaptureLastTimestamp, let tex = sharedScreenTexture { return tex }
        sharedCaptureLastTimestamp = timestamp
        let screenBounds = rootView.bounds
        guard screenBounds.width > 0, screenBounds.height > 0 else { return nil }
        // 35% of native resolution: high enough to retain background detail while
        // keeping the per-capture-tick render fast (runs ~20fps, shared by all views).
        let pxScale = rootView.layer.contentsScale * 0.35
        let pw = Int(screenBounds.width * pxScale)
        let ph = Int(screenBounds.height * pxScale)
        if sharedCaptureBridge == nil { sharedCaptureBridge = ZeroCopyBridge(device: device) }
        _ = sharedCaptureBridge!.setupBuffer(width: pw, height: ph)

        // captureSharedScreen is only called on iOS 26.2+, where layer.render(in:)
        // correctly captures the UIKit hierarchy including wallpaper blur.
        // Hide all registered glass views so their Metal output is not captured into
        // the shared texture — prevents the feedback loop that causes echoing/flickering.
        var tex: MTLTexture?
        withGlassViewsHidden {
            tex = sharedCaptureBridge!.render(actions: { ctx in
                ctx.scaleBy(x: pxScale, y: pxScale)
                (rootView.layer.presentation() ?? rootView.layer).render(in: ctx)
            })
        }
        guard let tex else { return nil }
        sharedScreenTexture = tex
        // Single MPS blur pass shared by ALL glass views — runs once per capture tick
        // (~20fps), never per render frame. sigma 10px at 35% scale ≈ 11pt in screen-space,
        // giving deep frosted glass on top of the shader's 4-tap spread.
        if var blurTarget = sharedScreenTexture,
           let cb = commandQueue.makeCommandBuffer() {
            let blurFilter = MPSImageGaussianBlur(device: device,
                                                  sigma: isLowPerformanceDevice ? 6.0 : 10.0)
            blurFilter.edgeMode = .clamp
            blurFilter.encode(commandBuffer: cb, inPlaceTexture: &blurTarget,
                              fallbackCopyAllocator: nil)
            cb.commit()
            sharedScreenTexture = blurTarget
        }

        sharedScreenSizePts = screenBounds.size
        // Freeze: now that we have a valid snapshot, stop re-capturing.
        // Future calls return immediately without any render work until invalidated.
        sharedScreenFrozen = true
        return sharedScreenTexture
    }

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported")
        }
        self.device = device

        // Shared command queue — created once, reused by all LiquidGlassViews.
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        // A11/A12 GPU family (apple4/apple5) cannot run the full glass effect stack
        // across many simultaneous views without dropping frames. apple6 = A13+.
        // supportsFamily(_:) is available on iOS 13+, safe for our iOS 14 deployment target.
        self.isLowPerformanceDevice = !device.supportsFamily(.apple6)

#if SWIFT_PACKAGE
        let library = try! device.makeDefaultLibrary(bundle: .module)
#else
        // Resolve shader bundle: prefer a bundle embedded next to the binary (normal app / Swift Package
        // non-module builds), then fall back to the jailbreak tweak installation path.
        let mainBundle = Bundle(for: LiquidGlassView.self)
        let resolvedBundleURL: URL
        if let embeddedURL = mainBundle.url(forResource: "LiquidGlassKitShaderResources", withExtension: "bundle") {
            resolvedBundleURL = embeddedURL
        } else {
            // Jailbreak tweak layout. Resolve the path using whichever bootstrap is active:
            //
            //  • RootHide: files are installed to /var/jb/ in the .deb, but RootHide's detection
            //    bypass remaps /var/jb to a UUID-randomised hidden path at runtime. The only
            //    correct way to get the real path is via jbroot() from libroothide, which is
            //    pre-loaded into every process by the bootstrap. We call it through dlsym so
            //    we don't need to link against libroothide at build time.
            //
            //  • Rootless (Palera1n / Dopamine): plain /var/jb prefix, no remapping.
            //
            //  • Rootful (legacy Unc0ver / Taurine): no prefix at all.
            let relative = "/Library/LiquidGlass/LiquidGlassKitShaderResources.bundle"
            resolvedBundleURL = URL(fileURLWithPath: LiquidGlassRenderer.jbRealPath(relative))
        }
        guard let shaderBundle = Bundle(url: resolvedBundleURL) else {
            fatalError("[LiquidGlass] Could not open shader bundle at \(resolvedBundleURL.path)")
        }
        let library = try! device.makeDefaultLibrary(bundle: shaderBundle)
#endif

        let vertexFunction = library.makeFunction(name: "fullscreenQuad")!
        let fragmentFunction = library.makeFunction(name: "liquidGlassEffect")!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm  // Match MTKView

        self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
}

final class LiquidGlassView: MTKView {

    let liquidGlass: LiquidGlass

    // No per-instance commandQueue — use LiquidGlassRenderer.shared.commandQueue.
    // Removing N per-instance queues eliminates N×(driver setup + scheduling overhead).
    var uniformsBuffer: MTLBuffer!
    var zeroCopyBridge: ZeroCopyBridge!

    // Background texture for the shader
    private var backgroundTexture: MTLTexture?

    /// Whether to automatically capture superview on a background schedule.
    /// Set to false for manual control via `captureBackground()`.
    var autoCapture: Bool = true {
        didSet {
            if autoCapture { startCaptureScheduler() } else { stopCaptureScheduler() }
        }
    }

    var touchPoint: CGPoint? = nil

    var frames: [CGRect] = []

    // Shadow overlay subview
    private weak var shadowView: ShadowView?

    // Backdrop capture view (stays in superview, contains only CABackdropLayer)
    private let backdropView = BackdropView()

    // MARK: - Capture scheduler (fully decoupled from the render CADisplayLink)
    //
    // The MTKView display link drives draw() at 30 fps — pure GPU work only.
    // A *separate* CADisplayLink runs and is solely responsible for CPU-side
    // background captures. This guarantees the render loop never waits on a capture.
    //
    // Rate: every 4th display-link tick → ~11 captures/sec.
    // Capture ticks are staggered per-instance so multiple glass views never fire
    // their expensive drawHierarchy call on the same display-link tick.
    private var captureDisplayLink: CADisplayLink?
    private var captureTick: Int = 0
    private var captureTickInterval: Int {
        // Reduced from 2/3 to 8/12: iOS < 26.2 uses drawHierarchy() which is the primary
        // CPU cost. Motion reprojection (captureOffset) in draw() keeps the glass
        // pixel-aligned between explicit captures, so longer intervals are invisible.
        // A11/A12: 12 frames (~5fps at 60Hz) — within thermal budget.
        // Modern:  8 frames (~7.5fps at 60Hz) — margin trigger fires faster if the view
        //          moves more than 25% of its size between ticks anyway.
        // iOS 26.2+ shared-screen views: timer never triggers (sharedScreenActive guard);
        // this value only matters for burst-interval math on those devices.
        LiquidGlassRenderer.shared.isLowPerformanceDevice ? 12 : 8
    }

    // Burst-capture mode: captures every display-link tick for the given frame count.
    // Used when the glass first becomes visible (transitions, folder-open, CC-open)
    // so it refreshes rapidly during the opening animation instead of showing stale content.
    private var burstFramesRemaining: Int = 0
    // Tracks opacity so we detect the exact tick when the glass becomes visible.
    private var lastPresentationOpacity: Float = 1.0
    // Tracks the last renderer burst generation this view has responded to.
    // When LiquidGlassRenderer.shared.burstGeneration > lastObservedBurstGeneration,
    // this view enters burst mode (global transition triggered via LGTriggerBurstCapture).
    private var lastObservedBurstGeneration: Int = 0
    // Tracks the capturesSuspendedUntil value we last acted on for auto-burst-on-resume.
    private var lastObservedSuspendUntil: CFTimeInterval = 0

    /// Timestamp of the last detected view motion (or burst/first-appear trigger).
    /// The MTKView is paused when now - lastMotionTimestamp > idlePauseDelay.
    private var lastMotionTimestamp: CFTimeInterval = 0
    private let idlePauseDelay: CFTimeInterval = 0.32  // avoid rapid idle/active flapping

    /// Put this glass view into burst-capture mode.
    /// Captures every frame for `frames` ticks (~25 frames ≈ 300ms at 60fps).
    /// Call before an animation that changes the content behind this glass.
    public func forceCaptureBurst(frames: Int = 25) {
        burstFramesRemaining = max(burstFramesRemaining, frames)
    }

    /// Immediately resume Metal rendering and switch the capture scheduler to active rate.
    /// Called by LiquidGlassRenderer when a suspension window expires so the glass view
    /// reacts within one 60fps display-link tick (~16ms) rather than waiting up to 83ms
    /// for the next idle-rate (12fps) tick while the MTKView is paused.
    func wakeFromSuspension() {
        guard autoCapture else { return }
        lastMotionTimestamp = CACurrentMediaTime()
        let hz = UIScreen.main.maximumFramesPerSecond
        captureDisplayLink?.preferredFramesPerSecond = hz >= 90 ? 80 : 60
        if isPaused { isPaused = false }
    }

    /// Effective texture scale coefficient.
    /// On A11/A12: hard cap at 7% (~5× bandwidth savings vs. preset default).
    /// On modern devices: capped at 8% regardless of preset — keeps each capture cheap
    /// enough to run every single display frame without heating the device.
    /// fullQuality views (sliders, switches) are exempt — they need full-res texture.
    private var effectiveTextureScaleCoefficient: Double {
        if liquidGlass.fullQuality { return liquidGlass.backgroundTextureScaleCoefficient }
        if LiquidGlassRenderer.shared.isLowPerformanceDevice {
            // 12% gives 71% more pixels per axis vs the old 7% cap, reducing the pixelated
            // look without pushing the A11 past its thermal budget at the new 15fps rate.
            return min(liquidGlass.backgroundTextureScaleCoefficient, 0.12)
        }
        // Modern devices: cap at 8% so every-frame captures stay CPU-cheap.
        // The glass is blurry by design, so lower resolution is not visible.
        return min(liquidGlass.backgroundTextureScaleCoefficient, 0.08)
    }

    // Motion reprojection state — records where the background was last captured from.
    // draw() computes the UV delta each frame and injects it as captureOffset so the
    // glass stays aligned between captures (important on A11 with 7 captures/sec).
    private var lastCapturedBounds: CGRect = .zero
    private var lastCapturedTransform: CATransform3D = CATransform3DIdentity
    private var lastCapturedCenter: CGPoint = .zero

    // App-state pause observers — held strongly so they stay active; removed on window leave.
    // NOTE: SpringBoard (the target process) never receives didEnterBackgroundNotification
    // because it is always the frontmost process. willResignActiveNotification fires for
    // all scenarios that should pause glass (screen lock, CC/NC overlay, app launch).
    private var appInactiveObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?

    init(_ liquidGlass: LiquidGlass) {
        self.liquidGlass = liquidGlass

        super.init(frame: .zero, device: LiquidGlassRenderer.shared.device)

        // Apply preset's autoCapture flag before willMove fires.
        autoCapture = liquidGlass.autoCapture

        if liquidGlass.shadowOverlay {
            let shadowView = ShadowView()
            addSubview(shadowView)
            self.shadowView = shadowView
        }
        setupMetal()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow != nil {
            LiquidGlassRenderer.shared.registerView(self)
            // Suppress the transparent-then-glass flash and UV-readjustment flicker
            // that occur on first appearance.
            //  • Inside a suspension window: the view is appearing during an animated
            //    transition (folder open, CC slide-in). First capture returns frozen
            //    pre-animation content; we reveal once the capture is in hand.
            //  • Zero bounds: layout hasn't fired yet; captureBackground() will fail
            //    on the first synchronous call. Hide until the scheduler fires and
            //    layout has given us real bounds.
            // After the first successful captureBackground() call the view fades in
            // smoothly over 0.15 s (see captureBackground() below).
            if backgroundTexture == nil {
                // Hide only when capture will be delayed: suspension (mid-transition)
                // or zero bounds (layout not yet done). In both cases the glass would
                // flicker wrong-content for 1-2 frames, so we wait for first capture.
                // Normal case (non-suspension, non-zero bounds): draw() returns early
                // when backgroundTexture is nil — the MTKView is transparent, no flash.
                let insideSuspension = CACurrentMediaTime() < LiquidGlassRenderer.shared.capturesSuspendedUntil
                let boundsEmpty = bounds.width == 0 || bounds.height == 0
                if insideSuspension || boundsEmpty {
                    layer.opacity = 0
                }
            }
            startCaptureScheduler()
            appInactiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                // Screen locked (power button) or app entering background — stop everything.
                // CADisplayLink callbacks may continue in SpringBoard even with display off,
                // so we explicitly stop the scheduler and pause the render link here.
                // backgroundTexture is kept so the first draw after wake has valid content.
                self?.isPaused = true
                self?.stopCaptureScheduler()
            }
            appActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                // Screen unlocked or app foregrounded — resume and refresh.
                self?.isPaused = false
                self?.lastMotionTimestamp = CACurrentMediaTime()
                // Force an immediate capture on the very next tick so the stale texture
                // is refreshed before it becomes visually noticeable.
                self?.captureTick = self?.captureTickInterval ?? 4
                self?.startCaptureScheduler()
            }
        } else {
            LiquidGlassRenderer.shared.unregisterView(self)
            stopCaptureScheduler()
            // Remove backdropView from the window when the glass view leaves the hierarchy.
            // Leaving it behind would keep a stale blur overlay in the window indefinitely.
            backdropView.removeFromSuperview()
            if let t = appInactiveObserver { NotificationCenter.default.removeObserver(t) }
            if let t = appActiveObserver  { NotificationCenter.default.removeObserver(t) }
            appInactiveObserver = nil
            appActiveObserver   = nil
        }
    }

    // MARK: - Capture scheduler

    private func startCaptureScheduler() {
        guard autoCapture, captureDisplayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(captureSchedulerFired))
        // Use .common so the scheduler fires even while a UIScrollView is tracking.
        dl.add(to: .main, forMode: .common)
        // On ProMotion (120 Hz) run the scheduler at 80 fps: better position-detection
        // for iOS <26.2 capture reprojection (12.5 ms latency vs 16.7 ms at 60 fps),
        // while still being 33% cheaper than device-max on sharedScreenActive views.
        // On 60 Hz devices keep at 60 fps (device max, no change).
        let screenHz = UIScreen.main.maximumFramesPerSecond
        dl.preferredFramesPerSecond = screenHz >= 90 ? 80 : 60
        captureDisplayLink = dl
        // Stagger the initial tick offset so multiple glass views (e.g. folder icons)
        // never all fire captureBackground() on the same display-link tick.
        captureTick = Int.random(in: 0..<captureTickInterval)

        // Reset motion timestamp so the idle-pause window starts fresh — prevents the
        // view from being paused immediately on the first scheduler tick before any
        // content has been rendered.
        lastMotionTimestamp = CACurrentMediaTime()

        // Prime the texture synchronously so the very first draw() already has a valid
        // background — eliminates the one-frame black/transparent flash on first appear.
        // Only capture when there is no existing texture (foreground re-entry keeps stale
        // texture until the display link refreshes it, avoiding a visible blank frame).
        //
        // NOTE: We intentionally do NOT check capturesSuspendedUntil here.
        // Suspension is meant for *re-captures* on existing-texture views (preventing
        // them from baking mid-animation content). For a brand-new view with no texture
        // yet, captureRootView() on iOS 26.2+ immediately returns the frozen
        // pre-animation shared texture — the view renders correctly from frame 1
        // without any animated content. On iOS < 26.2, captureBackdrop() is called;
        // any content is better than 500 ms of black.
        if backgroundTexture == nil {
            captureBackground()
            captureTick = 0  // start a fresh interval from this capture
        }
    }

    private func stopCaptureScheduler() {
        captureDisplayLink?.invalidate()
        captureDisplayLink = nil
    }

    private var captureReprojectionMargin: CGSize {
        let c = CGFloat(liquidGlass.backgroundTextureSizeCoefficient)
        let margin = max(0, (c - 1) / 2)
        return CGSize(width: bounds.width * margin, height: bounds.height * margin)
    }

    @objc private func captureSchedulerFired() {
        // Suspension check: freeze existing-texture views during transitions (CC dismiss,
        // folder open, App Library slide-in) to prevent capturing mid-animation content.
        // Views with no texture yet (first appearance) skip the suspension so they still
        // get their first capture immediately.
        let renderer = LiquidGlassRenderer.shared
        let suspendedUntil = renderer.capturesSuspendedUntil
        let now = CACurrentMediaTime()
        if now < suspendedUntil && backgroundTexture != nil {
            return  // mid-suspension — keep showing last good frame
        }
        // If a new suspension window just ended, auto-burst to repaint with settled content.
        if suspendedUntil > lastObservedSuspendUntil {
            lastObservedSuspendUntil = suspendedUntil
            burstFramesRemaining = max(burstFramesRemaining, 25)
        }

        captureTick += 1
        let presentationLayer = layer.presentation() ?? layer
        let presentationBounds = presentationLayer.bounds
        let boundsChanged = abs(presentationBounds.width  - lastCapturedBounds.width)  > 1.0
                         || abs(presentationBounds.height - lastCapturedBounds.height) > 1.0
        let transformChanged = !CATransform3DEqualToTransform(presentationLayer.transform, lastCapturedTransform)
        let needsFirst = backgroundTexture == nil

        // Detect visibility transition: when the glass goes from invisible to visible
        // (e.g. folder opening, CC sliding in), enter burst mode so the background
        // refreshes rapidly during the animation instead of showing the pre-animation frame.
        let currentOpacity = presentationLayer.opacity
        let justBecameVisible = lastPresentationOpacity <= 0.02 && currentOpacity > 0.02
        lastPresentationOpacity = currentOpacity
        // Only start burst on first-appear / visibility-restore when NOT inside a
        // suspension window. If suspended, the existing auto-burst-on-resume path fires
        // correctly once the window expires, so starting burst now would just cause
        // captures of mid-animation content → flicker.
        if (justBecameVisible || needsFirst) && now >= suspendedUntil {
            burstFramesRemaining = max(burstFramesRemaining, 25)
        }
        // When the glass view resizes (e.g. a CC module expanding), enter burst mode so
        // the background texture tracks the animated bounds change at ~30fps instead of
        // updating only once per captureTickInterval. 15 frames ≈ 250ms at 60fps.
        if boundsChanged {
            burstFramesRemaining = max(burstFramesRemaining, 15)
        }

        // Global burst: triggered by LGTriggerBurstCapture (e.g. CC opens, folder opens).
        // Every already-visible glass view enters burst mode so content behind it refreshes
        // rapidly during the transition animation — no need to hide+show every glass view.
        let rendererGeneration = LiquidGlassRenderer.shared.burstGeneration
        if rendererGeneration != lastObservedBurstGeneration {
            lastObservedBurstGeneration = rendererGeneration
            burstFramesRemaining = max(burstFramesRemaining, 25)
        }

        // iOS 26.2+ shared-screen fast path: after first capture the shared texture is
        // frozen. viewOriginInScreen updated every draw() tick gives exact screen-space UV
        // for any glass position — no per-view recapture ever needed until a suspension
        // window expires and invalidateSharedScreenCache() resets sharedScreenFrozen.
        // Skipping timer-based recaptures here is the biggest single CPU saving: it
        // removes ~60fps × N-views of captureBackground() overhead that previously ran
        // even though each call returned the frozen texture immediately.
        let sharedScreenActive = !liquidGlass.fullQuality
            && renderer.sharedScreenFrozen
            && renderer.sharedScreenSizePts.width > 0
            && backgroundTexture != nil

        // Suppress time-based capture when idle. If nothing has moved for longer than
        // idlePauseDelay the content behind the glass is static — re-capturing it wastes CPU
        // (on A11 each captureBackdrop() costs ~3 ms; with 10+ views that's 40–60% CPU idle).
        // The margin/burst/bounds triggers below still fire immediately when something changes.
        // sharedScreenActive views skip the timer entirely — the frozen texture + UV
        // reprojection in draw() handles all position tracking without recapture.
        let idleCapture = !sharedScreenActive
            && captureTick >= captureTickInterval
            && (now - lastMotionTimestamp <= idlePauseDelay || needsFirst)
        var needsCapture = needsFirst || boundsChanged || transformChanged || idleCapture

        // Burst mode: capture every ~4 frames (~15fps at 60Hz) during transitions.
        // With captureTickInterval raised to 8, captureTickInterval/2=4 gives 15fps —
        // smooth enough to track opening animations while halving drawHierarchy overhead
        // vs the previous ~30fps burst rate.
        // sharedScreenActive views enter burst logic too (keeps isPaused=false so Metal
        // renders at full rate during transitions), but captureBackground() returns the
        // frozen shared texture immediately — zero extra CPU per burst tick.
        if burstFramesRemaining > 0 {
            let burstInterval = max(captureTickInterval / 2, 4)
            if captureTick >= burstInterval { needsCapture = true }
            burstFramesRemaining -= 1
        }

        // positionChangedThisTick: true when the glass view moved since the last
        // scheduler tick. This drives needsActiveRender even for sharedScreenActive
        // views (which skip needsCapture for position), ensuring draw() keeps running
        // during scroll so viewOriginInScreen is updated every frame — the fix for
        // glass appearing "stuck then snap" (jitter) during App Library / notification
        // list scrolling.
        var positionChangedThisTick = false
        if !needsCapture, let window {
            // Use presentation layer hierarchy so position is accurate during
            // UIScrollView deceleration animations (model layer = resting position).
            let wl = window.layer.presentation() ?? window.layer
            let currentCenter = presentationLayer.convert(CGPoint(x: presentationLayer.bounds.midX, y: presentationLayer.bounds.midY), to: wl)
            let dx = abs(currentCenter.x - lastCapturedCenter.x)
            let dy = abs(currentCenter.y - lastCapturedCenter.y)
            // Track position changes: keep idle-pause window open AND flag that the
            // render loop must stay active this tick (see needsActiveRender below).
            if dx > 1 || dy > 1 {
                lastMotionTimestamp = now
                positionChangedThisTick = true
            }
            // Shared-screen views use viewOriginInScreen for pixel-exact UV regardless of
            // glass position — no reprojection buffer limit applies, skip margin check.
            // iOS < 26.2 (captureBackdrop): enforce buffer margin only.
            // The small-movement (dx > 2pt) per-frame trigger has been removed — it was
            // the primary cause of 90% CPU, re-running drawHierarchy every frame during
            // any scroll. captureOffset in draw() handles sub-capture-interval drift;
            // the margin trigger below fires when the buffer is truly exhausted.
            if !sharedScreenActive {
                let margin = captureReprojectionMargin
                if dx >= margin.width || dy >= margin.height {
                    // MUST recapture: reprojection buffer exhausted — shader would clamp
                    // to edge pixels, visibly stretching the glass content at the border.
                    needsCapture = true
                }
            }
        }

        if needsCapture {
            captureTick = 0
            if captureBackground() {
                lastCapturedBounds = presentationBounds
                lastCapturedTransform = presentationLayer.transform
            }
        }

        // Idle-pause: when the view is stationary and content is frozen, stop submitting
        // Metal frames. The last presented drawable stays on screen. This eliminates GPU
        // work (draw call + command buffer submission) for every static glass view —
        // e.g. the dock background renders 0 fps instead of 120 fps while the user is idle.
        // Resume immediately when movement is detected or a burst begins.
        let needsActiveRender = justBecameVisible || needsFirst || boundsChanged
            || transformChanged || burstFramesRemaining > 0 || needsCapture
            || positionChangedThisTick  // view moved → keep draw() running to update UV
        if needsActiveRender {
            lastMotionTimestamp = now
            if isPaused {
                isPaused = false
                // Restore capture link: 80 fps on ProMotion, 60 fps on 60 Hz.
                let hz = UIScreen.main.maximumFramesPerSecond
                captureDisplayLink?.preferredFramesPerSecond = hz >= 90 ? 80 : 60
            }
        } else if !isPaused && !sharedScreenActive && now - lastMotionTimestamp > idlePauseDelay {
            // sharedScreenActive views (iOS 26.2+) are NEVER idle-paused: their per-frame
            // cost is a viewOriginInScreen uniform write + 1 draw call — microseconds of GPU
            // time per glass view. Pausing them causes a ≤17 ms stale-UV window at every
            // scroll start (glass content appears "stuck" for 1 frame then snaps) with no
            // meaningful battery saving. Non-shared views (iOS < 26.2, drawHierarchy path)
            // are still paused — their per-capture cost (~3 ms CPU) is worth avoiding at idle.
            isPaused = true
            let hz = UIScreen.main.maximumFramesPerSecond
            captureDisplayLink?.preferredFramesPerSecond = hz >= 90 ? 80 : 60
        }
    }

    func setupMetal() {
        guard let device else { return }

        // Use the shared command queue instead of a per-instance one.
        // One queue means fewer Metal driver serialisation points across all glass views.

        // Uniforms buffer (update per frame)
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<LiquidGlass.ShaderUniforms>.stride, options: [])!

        zeroCopyBridge = .init(device: device)

        // Make view transparent so we can see the effect
        isOpaque = false
        layer.isOpaque = false
        // Transparent clear color: when the render pass clears the drawable (e.g. on the
        // first frame before backgroundTexture is ready) it writes (0,0,0,0) so the glass
        // shows see-through instead of the default opaque-black clear.
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        layer.backgroundColor = nil

        // framebufferOnly = true lets the driver skip the extra copy needed for
        // sampling the drawable — valid here because we never read the framebuffer.
        framebufferOnly = true

        // Target ~75% of device refresh rate: smooth UV tracking with less GPU overhead
        // than device max. On 60 Hz LCDs the only standard rates are 30 and 60 fps; nearest
        // to the 45 fps target is 60 fps, so we run at device max there. On 120 Hz ProMotion
        // the nearest standard rate to 75 fps is 80 fps — saves ~33% GPU draw-call overhead
        // vs 120 fps while keeping UV-update lag ≤12.5 ms (one Metal frame), imperceptible
        // during normal scroll. sharedScreenActive views run continuously (never paused)
        // so 80 fps gives them a predictable, battery-friendly baseline with no jitter.
        // Run the Metal render link at device max (preferredFramesPerSecond = 0).
        // On 60 Hz this stays at 60 fps. On 120 Hz ProMotion this runs at 120 fps,
        // which is critical for sharedScreenActive views: viewOriginInScreen is read
        // from layer.presentation() in every draw() call, so 120 fps render = UV
        // updates phase-aligned with the 120 Hz scroll → no per-frame UV lag jitter.
        // sharedScreenActive views are zero-copy (just a UV transform per draw) so the
        // extra 40 fps vs the old 80 fps cap costs negligible CPU.
        preferredFramesPerSecond = 0

        isPaused = false
    }

    // MARK: - Background Capture

    /// Captures the background content. Chooses backdrop vs root-view path based on preset.
    /// Returns true if a new texture was stored. Can be called synchronously (e.g. before
    /// making the glass visible for the first time) or by the capture display link.
    @discardableResult public func captureBackground() -> Bool {
        // iOS 26.2+: captureRootView() — UIKit's layer tree includes the wallpaper blur
        //   on this version, so a CPU layer.render(in:) gives correct content.
        // iOS < 26.2: captureBackdrop() — wallpaper blur lives in a private WindowServer
        //   compositor layer; only CABackdropLayer + drawHierarchy can reach it.
        let wasNil = backgroundTexture == nil
        let success: Bool
        if #available(iOS 26.2, *) {
            success = captureRootView()
        } else {
            success = captureBackdrop()
        }
        // First successful capture: if the view was hidden to prevent initial flicker
        // (layer.opacity == 0 set in willMove), fade it in now that we have valid content.
        if success && wasNil && layer.opacity < 0.1 {
            DispatchQueue.main.async { [weak self] in
                UIView.animate(withDuration: 0.15) { self?.alpha = 1.0 }
            }
        }
        return success
    }

    /// Captures the background content via root View using (presentation) Layer render.
    /// High CPU usage.
    func captureRootView() -> Bool {
        guard let rootView = findRootView() else { return false }

        // Non-fullQuality views use the shared full-screen texture instead of an
        // individual per-view render. The renderer de-duplicates the expensive
        // layer.render(in:) call so that N glass views cause only ONE render per
        // display frame (the first caller captures; all others get the cache).
        if !liquidGlass.fullQuality {
            let ts = captureDisplayLink?.timestamp ?? CACurrentMediaTime()
            guard let tex = LiquidGlassRenderer.shared.captureSharedScreen(from: rootView, timestamp: ts) else { return false }
            backgroundTexture = tex
            recordCaptureCenter()
            lastCapturedBounds = (layer.presentation() ?? layer).bounds
            return true
        }

        // fullQuality views (sliders, switches) keep their own high-res per-view capture.
        let sizeCoefficient = liquidGlass.backgroundTextureSizeCoefficient
        let scaleCoefficient = layer.contentsScale * effectiveTextureScaleCoefficient

        // Determine our on-screen rect in the root view coordinate space.
        // IMPORTANT: During `UIView.animate`, the view's *model* layer jumps to the final frame
        // immediately; the in-flight position lives in the *presentation* layer. Using the
        // presentation layer makes the captured background track the view while it animates.
        let currentLayer = layer.presentation() ?? layer
        let frameInRoot = currentLayer.convert(currentLayer.bounds, to: rootView.layer)

        // Expand capture area around the MTKView center (in root view coordinates)
        let captureSize = CGSize(width: frameInRoot.width * sizeCoefficient,
                                 height: frameInRoot.height * sizeCoefficient)
        let captureRectInRoot = CGRect(x: frameInRoot.midX - captureSize.width / 2,
                                       y: frameInRoot.midY - captureSize.height / 2,
                                       width: captureSize.width,
                                       height: captureSize.height)

        // Same NaN guard as captureBackdrop — presentation layer can have NaN position.
        guard captureSize.width.isFinite, captureSize.height.isFinite,
              captureSize.width > 0, captureSize.height > 0,
              captureRectInRoot.origin.x.isFinite, captureRectInRoot.origin.y.isFinite else { return false }

        // captureRootView fullQuality is only reached on iOS 26.2+ (captureBackdrop() handles
        // iOS < 26.2). On 26.2+, layer.render(in:) correctly includes wallpaper blur.
        // Hide all glass views so they don't appear in their own background texture
        // (self-sampling feedback loop → visual echoing and flicker during fade-ins).
        var newTexture: MTLTexture?
        LiquidGlassRenderer.shared.withGlassViewsHidden {
            newTexture = zeroCopyBridge.render(actions: { context in
                context.scaleBy(x: scaleCoefficient, y: scaleCoefficient)
                context.translateBy(x: -captureRectInRoot.origin.x, y: -captureRectInRoot.origin.y)
                (rootView.layer.presentation() ?? rootView.layer).render(in: context)
            })
        }
        guard let newTexture else { return false }

        backgroundTexture = newTexture
        blurTexture()
        recordCaptureCenter()
        return true
    }

    /// Captures the background content via CABackdropLayer using drawHierarchy.
    /// Noticeable rendering delay.
    func captureBackdrop() -> Bool {
        guard let superview, let window else { return false }

        let sizeCoefficient = liquidGlass.backgroundTextureSizeCoefficient
        let scaleCoefficient = layer.contentsScale * effectiveTextureScaleCoefficient

        // During an active suspension window a new glass view (backgroundTexture == nil)
        // should sample the wallpaper at its FINAL (model-layer) position rather than the
        // current presentation-layer position, which is mid-animation.  Using the
        // presentation layer during a slide-in (NC, CC module, folder) gives the wrong
        // compositor region and produces mismatched / "flickery" reflections that
        // visually "jump" once the animation settles.  After the suspension window the
        // presentation layer resumes so that existing glass correctly tracks live movement
        // (dock during homescreen swipe, scrolling notification cells, etc.).
        let suspendedUntil = LiquidGlassRenderer.shared.capturesSuspendedUntil
        let useModelLayer = backgroundTexture == nil && CACurrentMediaTime() < suspendedUntil
        let currentLayer = useModelLayer ? layer : (layer.presentation() ?? layer)
        let frameInSuperview = currentLayer.convert(currentLayer.bounds, to: superview.layer)
        let captureSize = CGSize(width: frameInSuperview.width * sizeCoefficient,
                                 height: frameInSuperview.height * sizeCoefficient)
        let captureOrigin = CGPoint(x: frameInSuperview.midX - captureSize.width / 2,
                                    y: frameInSuperview.midY - captureSize.height / 2)

        // Guard against NaN — presentation layer can return NaN position during
        // mid-animation transitions (e.g. iPhone X home-screen). Setting a NaN frame
        // on CABackdropLayer throws CALayerInvalidGeometry and crashes SpringBoard.
        guard captureSize.width.isFinite, captureSize.height.isFinite,
              captureSize.width > 0, captureSize.height > 0,
              captureOrigin.x.isFinite, captureOrigin.y.isFinite else { return false }

        // Suppress implicit animations: CABackdropLayer frame changes can be picked up by
        // an active UIView animation context, delaying the frame update and making the first
        // capture sample the wrong screen region.
        UIView.performWithoutAnimation {
            backdropView.frame = CGRect(origin: captureOrigin, size: captureSize)
        }

        // Keep backdropView in the glass view’s own superview (not the window root).
        // CABackdropLayer’s compositor sampling — the environmental tint, frosted blur, and
        // colour vibrancy that makes the glass look correct — depends on its position in the
        // layer tree. Moving it to the window root changes what the compositor samples and
        // produces a plain wallpaper-only blur instead of the full liquid-glass appearance.
        if backdropView.superview !== superview {
            superview.insertSubview(backdropView, belowSubview: self)
        }

        // MUST use drawHierarchy — CABackdropLayer content comes from WindowServer compositing
        // and is NOT accessible via layer.render(in:). Only drawHierarchy captures it.
        guard let newTexture = zeroCopyBridge.render(actions: { context in
            context.scaleBy(x: scaleCoefficient, y: scaleCoefficient)
            UIGraphicsPushContext(context)
            backdropView.drawHierarchy(in: backdropView.bounds, afterScreenUpdates: false)
            UIGraphicsPopContext()
        }) else { return false }

        backgroundTexture = newTexture
        blurTexture()
        recordCaptureCenter()
        return true
    }

    func blurTexture() {
        guard liquidGlass.backgroundTextureBlurRadius > 0,
              let device,
              let commandBuffer = LiquidGlassRenderer.shared.commandQueue.makeCommandBuffer(),
              var backgroundTexture else { return }

        // Apply GPU-accelerated Gaussian blur via MPS
        // On A11/A12 textures are captured at 7% scale. A small blur multiplier smooths
        // pixelation without washing out detail. 0.8× is a subtle polish pass — heavy
        // blur (≥1.2×) makes the glass look foggy and hides the refractive distortion.
        let blurRadius = LiquidGlassRenderer.shared.isLowPerformanceDevice
            ? liquidGlass.backgroundTextureBlurRadius * 0.8
            : liquidGlass.backgroundTextureBlurRadius
        let sigma = Float(blurRadius * layer.contentsScale)
        let blur = MPSImageGaussianBlur(device: device, sigma: sigma)
        blur.edgeMode = .clamp

        blur.encode(commandBuffer: commandBuffer, inPlaceTexture: &backgroundTexture, fallbackCopyAllocator: nil)
        // Do NOT call waitUntilCompleted() here — that blocks the main thread for the full
        // blur duration every frame. Committing without waiting is safe: the shared command
        // queue serialises the blur before the render encoder that reads backgroundTexture,
        // so Metal's dependency tracking guarantees ordering automatically.
        commandBuffer.commit()
    }

    /// Records the view's current presentation-layer midpoint in **window** coordinates
    /// as the anchor for motion reprojection. Using the window (screen) coordinate space
    /// means parent UIScrollView scrolling is visible as a position delta — superview
    /// coordinates do NOT change when a scroll view's contentOffset changes because the
    /// glass view's frame in its direct parent is fixed; only the window position moves.
    private func recordCaptureCenter() {
        guard let window else { return }
        let l = layer.presentation() ?? layer
        lastCapturedCenter = l.convert(CGPoint(x: l.bounds.midX, y: l.bounds.midY), to: window.layer)
    }

    private var renderingScaleCoefficient: CGFloat {
        // Scale down on high-DPI devices to save fragment work.
        // A11 (iPhone X) now renders at 0.80x (middle ground for high quality/speed).
        if liquidGlass.fullQuality { return 1.0 }
        return layer.contentsScale > 2.0 ? 0.80 : 1.0
    }

    func updateUniforms() {
        var uniforms = liquidGlass.shaderUniforms
        let scaleFactor = layer.contentsScale * renderingScaleCoefficient

        uniforms.resolution = .init(x: Float(bounds.width * scaleFactor),
                                    y: Float(bounds.height * scaleFactor))
        uniforms.contentsScale = Float(scaleFactor)

        uniforms.shapeMergeSmoothness = 0.2

        // Assign rectangles from frames array, or use bounds if empty
        let effectiveFrames = frames.isEmpty ? [bounds] : frames
        uniforms.rectangleCount = Int32(min(effectiveFrames.count, LiquidGlass.maxRectangles))

        // Convert CGRect frames to SIMD4<Float> (x, y, width, height)
        var rects: [SIMD4<Float>] = []
        for i in 0..<LiquidGlass.maxRectangles {
            if i < effectiveFrames.count {
                let frame = effectiveFrames[i]
                rects.append(SIMD4<Float>(
                    Float(frame.origin.x),
                    Float(frame.origin.y),
                    Float(frame.width),
                    Float(frame.height)
                ))
            } else {
                rects.append(.zero)
            }
        }
        uniforms.rectangles = (
            rects[0], rects[1], rects[2], rects[3],
            rects[4], rects[5], rects[6], rects[7],
            rects[8], rects[9], rects[10], rects[11],
            rects[12], rects[13], rects[14], rects[15]
        )

        if let touchPoint {
            uniforms.touchPoint = .init(x: Float(touchPoint.x), y: Float(touchPoint.y))
        }

        uniforms.cornerRadius = Float(layer.cornerRadius)

        if let tintColor = liquidGlass.tintColor {
            uniforms.materialTint = tintColor.toSimdFloat4()
        }

        // Cheap mode: when many glass views are active or on low-perf devices
        if !liquidGlass.fullQuality && LiquidGlassRenderer.shared.shouldUseCheapMode {
            uniforms.dispersionStrength = 0
            uniforms.glareIntensity = 0
        }

        uniforms.textureSizeCoefficient = Float(liquidGlass.backgroundTextureSizeCoefficient)

        // Use the PRESENTATION layer bounds for captureScale so that the ratio is correct
        // even during Core Animation animations (model layer jumps to final size immediately,
        // but the presentation layer reflects the in-flight animated position/size).
        // draw() will overwrite this per-frame via the autoCapture path below; this fallback
        // applies when autoCapture is off or window is nil.
        let _presLayer = layer.presentation() ?? layer
        let scaleX = lastCapturedBounds.width > 0 && _presLayer.bounds.width > 0
            ? Float(lastCapturedBounds.width / _presLayer.bounds.width) : 1
        let scaleY = lastCapturedBounds.height > 0 && _presLayer.bounds.height > 0
            ? Float(lastCapturedBounds.height / _presLayer.bounds.height) : 1
        uniforms.captureScale = .init(x: scaleX, y: scaleY)

        uniformsBuffer.contents().assumingMemoryBound(to: LiquidGlass.ShaderUniforms.self).pointee = uniforms
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Optimize rendering resolution on high-DPI screens
        let renderScale = layer.contentsScale * renderingScaleCoefficient
        drawableSize = CGSize(width: bounds.width * renderScale, 
                              height: bounds.height * renderScale)

        updateUniforms()

        // All views need a zeroCopyBridge buffer: fullQuality views use it directly for
        // per-view captures; non-fullQuality views use it via captureBackdrop() on iOS < 26.2
        // (on 26.2+ captureRootView() is called instead and uses the shared renderer bridge).
        let captureScale = layer.contentsScale * liquidGlass.backgroundTextureSizeCoefficient * effectiveTextureScaleCoefficient
        let width = Int(bounds.width * captureScale)
        let height = Int(bounds.height * captureScale)
        let bufferChanged = zeroCopyBridge.setupBuffer(width: width, height: height)
        if bufferChanged {
            // Do NOT urgently reschedule a capture here. The old backgroundTexture stays valid
            // (its CVMetalTexture chain is ARC-retained). boundsChanged detection in
            // captureSchedulerFired() fires a fresh capture on the very next display-link tick
            // when the presentation-layer size differs from lastCapturedBounds. Forcing
            // captureTick = captureTickInterval here made ALL glass views in the same layout
            // pass (triggered by insertSubview cascade) fire captureBackdrop() simultaneously
            // on the same tick — a CPU spike that dropped a frame and appeared as a flicker.
            _ = bufferChanged  // suppress unused-result warning
        }

        shadowView?.frame = bounds
    }

    override func draw(_ rect: CGRect) {
        guard alpha > 0, !isHidden else { return }

        // Always acquire a drawable first so we can ALWAYS present a frame.
        // Returning without presenting leaves the CAMetalLayer in its previous state
        // (black on cold-start), causing visible black bars while the texture loads.
        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandBuffer = LiquidGlassRenderer.shared.commandQueue.makeCommandBuffer() else { return }

        // If no texture yet, attempt one synchronous capture inline.
        // The pre-capture in startCaptureScheduler() fires during willMove(toWindow:)
        // before the view is laid out; by the time draw() fires the view IS on-screen
        // and positioned, so captureBackdrop() / captureRootView() can succeed.
        // We intentionally do NOT check capturesSuspendedUntil here: suspension only
        // blocks *re-captures* on views that already have a texture. For a first-time
        // render, captureRootView() on iOS 26.2+ returns the frozen pre-animation
        // shared texture immediately — no animated content baked in.
        if backgroundTexture == nil {
            captureBackground()
        }

        guard let texture = backgroundTexture else {
            // Still no texture — present a transparent cleared frame so the glass shows
            // see-through rather than lingering black (clearColor = (0,0,0,0) set above).
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) { enc.endEncoding() }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

        // Per-frame uniform update: either motion-reprojection (fullQuality) or screen-space
        // origin (non-fullQuality shared texture). Both paths write directly into the buffer
        // rather than going through updateUniforms() to avoid a full struct copy per frame.
        if autoCapture, let window {
            let l = layer.presentation() ?? layer
            let ptr = uniformsBuffer.contents().assumingMemoryBound(to: LiquidGlass.ShaderUniforms.self)
            if liquidGlass.fullQuality {
                // Motion reprojection: compensate for the view moving since the last capture.
                // Use window.layer.presentation() so the convert traverses the presentation
                // layer hierarchy — critical for correct UV during UIScrollView deceleration
                // where model-layer position has already snapped to the resting point.
                let wl = window.layer.presentation() ?? window.layer
                let screenPos = l.convert(CGPoint(x: l.bounds.midX, y: l.bounds.midY), to: wl)
                let captureW = Float(lastCapturedBounds.width * liquidGlass.backgroundTextureSizeCoefficient)
                let captureH = Float(lastCapturedBounds.height * liquidGlass.backgroundTextureSizeCoefficient)
                ptr.pointee.captureOffset = SIMD2<Float>(
                    captureW > 0 ? Float(screenPos.x - lastCapturedCenter.x) / captureW : 0,
                    captureH > 0 ? Float(screenPos.y - lastCapturedCenter.y) / captureH : 0
                )
                // Per-frame captureScale using presentation bounds — prevents the "stretched"
                // artifact during folder open/close where model bounds jump to final size
                // immediately while presentation bounds are still animating.
                let presBoundsF = l.bounds
                if presBoundsF.width > 0 && presBoundsF.height > 0 {
                    ptr.pointee.captureScale = SIMD2<Float>(
                        lastCapturedBounds.width > 0 ? Float(lastCapturedBounds.width / presBoundsF.width) : 1,
                        lastCapturedBounds.height > 0 ? Float(lastCapturedBounds.height / presBoundsF.height) : 1
                    )
                }
            } else {
                let renderer = LiquidGlassRenderer.shared
                if renderer.sharedScreenSizePts.width > 0 {
                    // Screen-space mode (iOS 26.2+): absolute UV positioning per fragment.
                    // Convert through the PRESENTATION layer hierarchy so position is correct
                    // during UIScrollView deceleration (model layer position = resting point,
                    // presentation layer position = current animated position).
                    let wl = window.layer.presentation() ?? window.layer
                    let origin = l.convert(CGPoint.zero, to: wl)
                    ptr.pointee.viewOriginInScreen = SIMD2<Float>(Float(origin.x), Float(origin.y))
                    ptr.pointee.screenSizePts = SIMD2<Float>(
                        Float(renderer.sharedScreenSizePts.width),
                        Float(renderer.sharedScreenSizePts.height)
                    )
                } else {
                    // Per-view fallback (iOS < 26.2, e.g. iPhone X): update captureOffset
                    // every frame so the glass tracks the view's movement between backdrop
                    // captures — same reprojection used by fullQuality views.
                    let wl = window.layer.presentation() ?? window.layer
                    let screenPos = l.convert(CGPoint(x: l.bounds.midX, y: l.bounds.midY), to: wl)
                    let captureW = Float(lastCapturedBounds.width * liquidGlass.backgroundTextureSizeCoefficient)
                    let captureH = Float(lastCapturedBounds.height * liquidGlass.backgroundTextureSizeCoefficient)
                    ptr.pointee.captureOffset = SIMD2<Float>(
                        captureW > 0 ? Float(screenPos.x - lastCapturedCenter.x) / captureW : 0,
                        captureH > 0 ? Float(screenPos.y - lastCapturedCenter.y) / captureH : 0
                    )
                    // Same per-frame captureScale fix as fullQuality: presentation bounds
                    // stay correct during folder-open/close animations on iOS < 26.2.
                    let presBoundsV = l.bounds
                    if presBoundsV.width > 0 && presBoundsV.height > 0 {
                        ptr.pointee.captureScale = SIMD2<Float>(
                            lastCapturedBounds.width > 0 ? Float(lastCapturedBounds.width / presBoundsV.width) : 1,
                            lastCapturedBounds.height > 0 ? Float(lastCapturedBounds.height / presBoundsV.height) : 1
                        )
                    }
                }
            }
        }

        encoder.setRenderPipelineState(LiquidGlassRenderer.shared.pipelineState)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        
        encoder.setFragmentTexture(texture, index: 0)

        // Draw fullscreen quad (vertices generated in vertex shader)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

extension UIColor {
    func toSimdFloat4() -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return .init(x: Float(r), y: Float(g), z: Float(b), w: Float(a))
    }
}

// Helpers: Lerp for damping, UIColor to Half4
//private func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
//    return a * (1 - t) + b * t
//}

extension UIView {
    /// Finds the root view in the view hierarchy.
    func findRootView() -> UIView? {
        var current: UIView? = superview
        while let parent = current?.superview {
            current = parent
        }
        return current
    }
}
