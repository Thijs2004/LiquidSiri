import SwiftUI
import UIKit
import AVFoundation

@objc public class WaveManager: NSObject, ObservableObject {
    @objc public static let shared = WaveManager()
    
    // Smooth, visual powers
    @objc public var targetPower: Double = 0.15
    @Published public var phase: Double = 0.0
    @Published public var phases: [Double] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    @Published public var currentPower: Double = 0.15
    
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
    
    private var displayLink: CADisplayLink?
    
    private var lastTimestamp: CFTimeInterval = 0
    private var currentSpeed: Double = .pi
    @Published public var rawMicLevel: Double = 0.0
    
    // For debugging power levels
    private var minPowerObs: Double = 1000.0
    private var maxPowerObs: Double = -1000.0
    private var logTimer: Timer?
    
    private override init() {
        super.init()
        
        displayLink = CADisplayLink(target: self, selector: #selector(updatePower))
        displayLink?.add(to: .main, forMode: .common)
        
        // Debug logger
        logTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let logStr = String(format: "Raw: %.4f, Min: %.4f, Max: %.4f, Curr: %.4f\n", self.rawMicLevel, self.minPowerObs, self.maxPowerObs, self.currentPower)
            if let data = logStr.data(using: .utf8) {
                if let fileHandle = FileHandle(forWritingAtPath: "/tmp/siri_power.txt") {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    try? logStr.write(toFile: "/tmp/siri_power.txt", atomically: true, encoding: .utf8)
                }
            }
            // Reset min/max every second to track active levels
            self.minPowerObs = 1000.0
            self.maxPowerObs = -1000.0
        }
    }
    
    private var noiseFloor: Double = 1.0
    
    @objc private func updatePower(link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp }
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        
        var linearLevel = rawMicLevel
        if linearLevel < 0 {
            // If the system is sending decibels (e.g. -80dB to 0dB), convert to linear 0.0...1.0
            linearLevel = pow(10.0, max(-120.0, linearLevel) / 20.0)
        }
        
        // Ensure strictly positive bounds
        linearLevel = max(0.0, min(1.0, linearLevel))
        
        // We use a softer curve so it scales proportionally with loudness
        // e.g. pow(0.5) was too aggressive, pow(0.7) gives a more natural ramp
        let boostedLevel = pow(linearLevel, 0.7)
        
        // Strict deadzone at 0.15 on the boosted scale
        let deadzone = 0.15
        let signal = max(0.0, boostedLevel - deadzone)
        
        // Lower the multiplier so soft voices = small reaction, loud voices = large reaction
        // (Previously 35.0 was causing it to max out instantly)
        let targetVisualPower = 0.15 + min(4.0, signal * 12.0)
        
        // Smoothly interpolate power with an attack/release curve
        // Faster attack when getting louder, slower release when getting quieter to prevent choppiness
        let powerInterpolationBase = targetVisualPower > currentPower ? 0.01 : 0.15
        currentPower += (targetVisualPower - currentPower) * (1.0 - pow(powerInterpolationBase, dt))
        
        bassLevel = currentPower
        midLevel = currentPower
        trebleLevel = currentPower
        
        // 2. Calculate dynamic speed
        // Base speed is 1.0 (calm, matches ShaderToy iTime).
        // We add proportional amount of speed when talking.
        let targetSpeed = 1.0 + min(2.0, signal * 4.0)
        let speedInterpolationBase = targetSpeed > currentSpeed ? 0.01 : 0.15
        currentSpeed += (targetSpeed - currentSpeed) * (1.0 - pow(speedInterpolationBase, dt))
        
        phase += currentSpeed * dt
        if phase > .pi * 100 { phase = phase.truncatingRemainder(dividingBy: .pi * 2) }
        
        let extraSpeed = min(2.0, signal * 4.0)
        for i in 0..<7 {
            // When extraSpeed is 0, they all move at currentSpeed.
            // When extraSpeed is high, they spread out in speed so they roll out of sync!
            let individualSpeed = currentSpeed + extraSpeed * Double(i - 3) * 0.2
            phases[i] += individualSpeed * dt
            if phases[i] > .pi * 100 { phases[i] = phases[i].truncatingRemainder(dividingBy: .pi * 2) }
        }
        
        if abs(currentPower - power) > 0.001 {
            power = currentPower
        }
    }
    
    @objc public func updateTargetPower(_ newPowerObj: NSNumber) {
        let newPower = newPowerObj.doubleValue
        DispatchQueue.main.async {
            self.rawMicLevel = newPower
            if newPower < self.minPowerObs { self.minPowerObs = newPower }
            if newPower > self.maxPowerObs { self.maxPowerObs = newPower }
        }
    }
    
    @objc public func startRecording() {
        // Rely on Tweak.x's native Siri audio stealing to call updateTargetPower
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
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        if #available(iOS 16.4, *) {
            hostingController.safeAreaRegions = []
        }
        return hostingController.view
    }
}
