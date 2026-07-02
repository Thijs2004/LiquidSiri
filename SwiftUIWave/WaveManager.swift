import SwiftUI
import UIKit

@objc public class WaveManager: NSObject, ObservableObject {
    @objc public static let shared = WaveManager()
    
    // Smooth, visual powers
    @objc public var targetPower: Double = 0.15
    private var currentPower: Double = 0.15
    
    // Frequency bands for multi-wave reactivity
    @Published public var bassLevel: Double = 0.15
    @Published public var midLevel: Double = 0.15
    @Published public var trebleLevel: Double = 0.15
    
    private var targetBass: Double = 0.15
    private var targetMid: Double = 0.15
    private var targetTreble: Double = 0.15
    
    @objc public var power: Double = 0.15 {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("UpdateSiriPower"), object: power)
        }
    }
    
    private var timer: Timer?
    
    private override init() {
        super.init()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Fast interpolation for the main power
            self.currentPower += (self.targetPower - self.currentPower) * 0.35
            
            // Fast interpolation for the frequency bands
            self.bassLevel += (self.targetBass - self.bassLevel) * 0.35
            self.midLevel += (self.targetMid - self.midLevel) * 0.35
            self.trebleLevel += (self.targetTreble - self.trebleLevel) * 0.35
            
            if abs(self.currentPower - self.power) > 0.001 {
                self.power = self.currentPower
            }
        }
    }
    
    @objc public func updateTargetPower(_ newPower: Double) {
        // Siri provides very low raw power (0.0 to ~0.3)
        // We boost it using exponential scaling just like AudioAnalyzer
        let punchyPower = min(2.5, pow(newPower * 10.0, 2.0) * 2.0)
        let visualPower = min(2.5, 0.15 + punchyPower)
        
        DispatchQueue.main.async {
            self.targetPower = visualPower
            
            // Synthesize multi-band reactivity from the single mic level to avoid TCC crashes
            // Bass reacts heavily to big spikes
            self.targetBass = visualPower * 1.3
            // Mid reacts smoothly to average voice
            self.targetMid = visualPower * 0.9
            // Treble flickers rapidly to give texture
            let flicker = Double.random(in: 0.8...1.2)
            self.targetTreble = visualPower * flicker
        }
    }
    
    @objc public func startRecording() {
        // Dummy method so Tweak.x doesn't crash
    }
    
    @objc public func stopRecording() {
        DispatchQueue.main.async {
            self.targetPower = 0.15
            self.targetBass = 0.15
            self.targetMid = 0.15
            self.targetTreble = 0.15
        }
    }
    
    @objc public func createWaveView(frame: CGRect) -> UIView {
        let waveView = SiriWaveView()
        let hostingController = UIHostingController(rootView: waveView)
        hostingController.view.frame = frame
        hostingController.view.backgroundColor = .clear
        return hostingController.view
    }
}
