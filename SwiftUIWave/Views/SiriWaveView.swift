import SwiftUI

struct ThickWaveShape: Shape {
    var phase: Double
    var power: Double
    var thicknessMultiplier: Double = 1.0
    
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
        let height = rect.height
        let midY = height / 2.0
        
        let frequency = 1.0 // One smooth sweeping wave
        let maxAmplitude = height * 0.3
        
        let currentPower = max(0.15, power)
        let amplitude = maxAmplitude * currentPower
        
        // Base thickness for the filled band (made significantly thinner)
        let maxThickness = height * 0.20 * thicknessMultiplier
        
        // Draw top curve (left to right)
        path.move(to: CGPoint(x: 0, y: midY))
        for x in stride(from: 0, through: width, by: 2.0) {
            let normalizedX = x / width
            
            // Attenuation perfectly tapers both amplitude and thickness at the edges
            let attenuation = pow(4.0 * normalizedX * (1.0 - normalizedX), 2.0)
            
            let angle = (normalizedX * .pi * 2.0 * frequency) + phase
            let sine = sin(angle)
            
            let yCenter = midY + (sine * amplitude * attenuation)
            let thickness = (maxThickness / 2.0) * attenuation
            
            // Top edge
            path.addLine(to: CGPoint(x: x, y: yCenter - thickness))
        }
        
        // Draw bottom curve (right to left)
        for x in stride(from: width, through: 0, by: -2.0) {
            let normalizedX = x / width
            let attenuation = pow(4.0 * normalizedX * (1.0 - normalizedX), 2.0)
            
            let angle = (normalizedX * .pi * 2.0 * frequency) + phase
            let sine = sin(angle)
            
            let yCenter = midY + (sine * amplitude * attenuation)
            let thickness = (maxThickness / 2.0) * attenuation
            
            // Bottom edge
            path.addLine(to: CGPoint(x: x, y: yCenter + thickness))
        }
        
        path.closeSubpath()
        return path
    }
}

public struct SiriWaveView: View {
    @ObservedObject var manager = WaveManager.shared
    @State private var phase: Double = 0.0
    
    private let verticalSpectrum = LinearGradient(
        stops: [
            .init(color: Color(red: 0.3, green: 0.7, blue: 1.0), location: 0.35), // Light blue (Top)
            .init(color: Color(red: 0.4, green: 1.0, blue: 0.7), location: 0.45), // Mint green
            .init(color: .white, location: 0.5),                                  // White (Center)
            .init(color: Color(red: 1.0, green: 0.9, blue: 0.2), location: 0.55), // Yellow
            .init(color: Color(red: 1.0, green: 0.1, blue: 0.1), location: 0.65)  // Red (Bottom)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background wider wave - BASS
                ThickWaveShape(phase: phase + 1.5, power: manager.bassLevel, thicknessMultiplier: 1.2)
                    .fill(verticalSpectrum)
                    .blur(radius: 3)
                    .opacity(0.8)
                
                // Middle weaving wave - MID
                ThickWaveShape(phase: phase, power: manager.midLevel, thicknessMultiplier: 0.8)
                    .fill(verticalSpectrum)
                    .blur(radius: 1.5)
                    .opacity(0.9)
                
                // Foreground sharp core wave - TREBLE
                ThickWaveShape(phase: phase - 1.0, power: manager.trebleLevel, thicknessMultiplier: 0.25)
                    .fill(verticalSpectrum)
            }
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = .pi * 2.0
                }
            }
        }
        .drawingGroup()
    }
}
