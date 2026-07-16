import SwiftUI

struct ThickWaveShape: Shape {
    var phase: Double
    var power: Double
    var thicknessMultiplier: Double = 1.0
    var frequency: Double = 1.0
    var amplitudeMultiplier: Double = 1.0
    var isTwisting: Bool = false
    
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, power) }
        set { 
            phase = newValue.first
            power = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let referenceHeight = 80.0 // Keep wave size consistent regardless of canvas size
        let midY = rect.height / 2.0
        
        let maxAmplitude = referenceHeight * 0.3
        
        let currentPower = max(0.15, power)
        let amplitude = maxAmplitude * currentPower * amplitudeMultiplier
        
        // Base thickness for the filled band (made significantly thinner)
        let maxThickness = referenceHeight * 0.20 * thicknessMultiplier
        
        // Draw top curve (left to right)
        path.move(to: CGPoint(x: 0, y: midY))
        for x in stride(from: 0, through: width, by: 2.0) {
            let normalizedX = x / width
            
            // Attenuation perfectly tapers both amplitude and thickness at the edges
            let attenuation = pow(4.0 * normalizedX * (1.0 - normalizedX), 2.0)
            
            let angle = (normalizedX * .pi * 2.0 * frequency) + phase
            let sine = sin(angle)
            
            let twistFactor = isTwisting ? abs(cos(angle)) : 1.0
            
            let yCenter = midY + (sine * amplitude * attenuation)
            let thickness = (maxThickness / 2.0) * attenuation * (0.15 + 0.85 * twistFactor)
            
            // Top edge
            path.addLine(to: CGPoint(x: x, y: yCenter - thickness))
        }
        
        // Draw bottom curve (right to left)
        for x in stride(from: width, through: 0, by: -2.0) {
            let normalizedX = x / width
            let attenuation = pow(4.0 * normalizedX * (1.0 - normalizedX), 2.0)
            
            let angle = (normalizedX * .pi * 2.0 * frequency) + phase
            let sine = sin(angle)
            
            let twistFactor = isTwisting ? abs(cos(angle)) : 1.0
            
            let yCenter = midY + (sine * amplitude * attenuation)
            let thickness = (maxThickness / 2.0) * attenuation * (0.15 + 0.85 * twistFactor)
            
            // Bottom edge
            path.addLine(to: CGPoint(x: x, y: yCenter + thickness))
        }
        
        path.closeSubpath()
        return path
    }
}

public struct SiriWaveView: View {
    @ObservedObject var manager = WaveManager.shared
    
    public init() {}
    
    private var talkingFactor: Double {
        // When bassLevel is > 0.15 (the idle level), we consider it talking.
        let t = (manager.bassLevel - 0.15) * 8.0
        return min(1.0, max(0.0, t))
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Use the custom Metal GLSL port wrapped in MTKView for iOS 14+ compatibility
                SiriMetalView(talkingFactor: talkingFactor, phase: manager.phase)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blendMode(.screen)
                
                // BOTTOM WHITE RIM GLOW (Matches the image's bottom glass reflection)
                Ellipse()
                    .fill(Color.white)
                    .frame(width: geo.size.width * 0.7, height: 12)
                    .blur(radius: 8)
                    .opacity(0.6)
                    .offset(y: (geo.size.height / 2.0) + 20.0)
            }
            .edgesIgnoringSafeArea(.all)
        }
        .edgesIgnoringSafeArea(.all)
    }
}
