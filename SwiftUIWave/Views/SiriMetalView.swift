import SwiftUI
import MetalKit

// The same struct we defined in SiriWave.metal
struct SiriWaveUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var talkingFactor: Float
}

public struct SiriMetalView: UIViewRepresentable {
    var talkingFactor: Double
    var phase: Double
    
    public init(talkingFactor: Double, phase: Double) {
        self.talkingFactor = talkingFactor
        self.phase = phase
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
        if let device = MTLCreateSystemDefaultDevice() {
            mtkView.device = device
        }
        
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.framebufferOnly = true
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.backgroundColor = .clear
        mtkView.isOpaque = false
        
        context.coordinator.setupMetal(mtkView: mtkView)
        
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.parent = self
    }
    
    public class Coordinator: NSObject, MTKViewDelegate {
        var parent: SiriMetalView
        
        var device: MTLDevice?
        var commandQueue: MTLCommandQueue?
        var pipelineState: MTLRenderPipelineState?
        
        init(_ parent: SiriMetalView) {
            self.parent = parent
        }
        
        func setupMetal(mtkView: MTKView) {
            self.device = mtkView.device
            guard let device = self.device else { return }
            
            self.commandQueue = device.makeCommandQueue()
            
            let metalSource = """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float2 uv;
            };

            struct Uniforms {
                float2 resolution;
                float time;
                float talkingFactor;
            };

            vertex VertexOut siriVertexShader(uint vertexID [[vertex_id]]) {
                float2 positions[6] = {
                    float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
                    float2( 1.0,  1.0), float2(-1.0,  1.0), float2( 1.0, -1.0)
                };
                float2 uvs[6] = {
                    float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
                    float2(1.0, 0.0), float2(0.0, 0.0), float2(1.0, 1.0)
                };
                VertexOut out;
                out.position = float4(positions[vertexID], 0.0, 1.0);
                out.uv = uvs[vertexID];
                return out;
            }

            constant float PI = 3.14159265359f;
            constant float AMPLITUDE   = 0.25f; // Low but visible idle wave
            constant float FREQ        = 0.8f; // Further lowered to make waves even wider horizontally
            constant float ABER_FREQ   = 0.7f;
            constant float SPEED       = 2.4f;
            constant float WAVE_SCALE  = 0.6f;
            constant float ABERRATION  = 2.6f;
            constant float THICKNESS   = 0.5f; // Made extremely sharp/solid
            constant float INTENSITY   = 2.0f; 
            constant float FALLOFF     = 0.8f; // Slightly more edge fading
            constant float EDGE_MASK   = 0.4f;
            constant float EDGE_INSET  = 0.0f;
            constant float BAND_FILL   = 25000.0f; // Moderately lighter
            constant float BAND_THICK  = 0.08f;
            constant float SOFTNESS    = 0.4f;
            constant float LOW_AMP     = 18.0f; // High enough for big waves
            constant float LOW_INT     = 1.5f;
            constant float MID_ABER    = 0.8f;
            constant float MID_ABAMP   = 0.05f;
            constant float MID_BAND    = 20.0f;
            constant float MID_SOFT    = 0.4f;
            constant float HIGH_ABER   = 0.5f;
            constant float HIGH_ABAMP  = 0.06f;
            constant float RESOLVED    = 1.0f;
            constant float UNRES_SCALE = 0.14f;
            constant float Y_OFFSET    = -0.08f; // Adjusted to be a tiny bit higher than -0.15f
            
            float3 spectral4(int s){
                float x = float(s);
                return clamp(float3(abs(x-3.0f)-1.0f, 2.0f-abs(x-2.0f), 2.0f-abs(x-4.0f)), 0.0f, 1.0f);
            }

            fragment half4 siriFragmentShader(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
                float2 uv = in.uv * 2.0f - 1.0f;
                float aspect = u.resolution.x / u.resolution.y;
                float2 p = uv;
                float yScreen = uv.y;
                p.y += Y_OFFSET;
                p.y *= 1.2f; // Squash the wave slightly to keep it inside the bubble
                p.x *= aspect;
                p /= max(WAVE_SCALE, 0.1f);
                float t = u.time;
                float talkingFactor = u.talkingFactor;
                
                // Generate base factors
                float low  = clamp(0.45f + 0.45f*sin(t*0.8f)*sin(t*0.37f+1.0f), 0.0f, 1.0f);
                float mid  = clamp(0.40f + 0.40f*sin(t*1.7f+2.0f)*sin(t*0.53f), 0.0f, 1.0f);
                float high = clamp(0.30f + 0.30f*sin(t*2.9f+4.0f)*sin(t*0.71f+2.0f), 0.0f, 1.0f);
                
                // talkingFactor idles at 0.15
                float activeFactor = max(0.0f, talkingFactor - 0.15f);
                activeFactor = min(activeFactor, 1.5f);
                
                float res   = clamp(RESOLVED, 0.0f, 1.0f);
                float drift = fmod(t, 20.0f * PI) * SPEED;
                float xN  = p.x / max(aspect, 1.0f);
                
                // Widen envelope horizontally but make it a tiny bit less wide
                // by multiplying uv.x by 1.15 so it fades out just before the edge.
                float xNorm = min(abs(uv.x * 1.15f), 1.0f);
                float env = cos(PI*0.5f * xNorm);
                
                // When idle, activeFactor is 0, making all amplitudes EXACTLY 0.
                float dynamicLowAmp = 0.0f + (activeFactor * LOW_AMP * 7.0f);
                float dynamicMidAmp = 0.0f + (activeFactor * MID_ABAMP * 7.0f);
                float dynamicHighAmp = 0.0f + (activeFactor * HIGH_ABAMP * 7.0f);
                
                float A1    = AMPLITUDE + 0.01f*low*dynamicLowAmp;
                float A2    = A1 + mid*dynamicMidAmp + high*dynamicHighAmp;
                float AB    = (ABERRATION + mid*MID_ABER + high*HIGH_ABER)*res;
                
                // Allow a tiny bit of rotation (0.15) when idle so colors are visible on the edges
                AB *= mix(0.15f, 1.0f, clamp(activeFactor * 4.0f, 0.0f, 1.0f));
                
                // Make it thicker when talking
                float currentThickness = THICKNESS + (activeFactor * 12.0f);
                float th    = mix(0.1f, 0.01f*currentThickness, res);
                float inten = mix(0.1f, 0.01f*(INTENSITY + low*LOW_INT), res);
                
                // Add more glow reflection around the wave, but only heavily when idle
                float idleGlowBoost = 5.5f * (1.0f - clamp(activeFactor * 2.0f, 0.0f, 1.0f));
                float soft  = 0.01f*res*max(0.0f, SOFTNESS + idleGlowBoost + mid*MID_SOFT);
                
                float dUnres = max(length(p) - mix(0.14f, UNRES_SCALE, res), 0.0f);
                float yMain = A1 * env * res * sin(p.x*FREQ + drift);
                float bandFillTh = max(BAND_THICK, 1e-4f);
                float bandAmt    = 1e-4f * BAND_FILL * inten;
                float3 num = float3(0.0f);
                float3 den = float3(0.0f);
                for(int s = 0; s < 4; s++){
                    float3 hue = mix(float3(1.0f), spectral4(s), res);
                    den += hue;
                    float ab = mix(-AB, AB, float(s)/3.0f);
                    float yL = A2 * env * res * sin(p.x*ABER_FREQ + drift + ab);
                    float d   = mix(dUnres, abs(p.y - yL), res);
                    float lor = mix(1.0f/(1.0f + (0.02f*d)*(0.02f*d)), 1.0f, res);
                    float line = inten / (sqrt(d*d + soft*soft) + th);
                    float lo = min(yMain, yL), hi = max(yMain, yL);
                    float dBand = max(0.0f, max(p.y - hi, lo - p.y));
                    float band  = bandAmt / (dBand + bandFillTh);
                    num += hue * lor * (line + band);
                }
                float3 col = num / den;
                float dM    = mix(dUnres, abs(p.y - yMain), res);
                float lorM  = mix(1.0f/(1.0f + (0.02f*dM)*(0.02f*dM)), 1.0f, res);
                float boostVal = (1.0f - res) * (14.0f*low + 4.0f);
                col += 0.5f * inten * (lorM + boostVal) / (sqrt(dM*dM + soft*soft) + th);
                col = pow(max(col, 0.0f), float3(1.5f));
                float3 preFadeCol = col; // Save raw vibrant color for the glass edge
                float emT = clamp((abs(yScreen) - 1.0f + EDGE_INSET) / (-max(EDGE_MASK, 1e-4f)), 0.0f, 1.0f);
                float em  = emT*emT*(3.0f - 2.0f*emT);
                float gauss = exp(-pow(xN*FALLOFF, 2.0f));
                col *= mix(1.0f, em*gauss, res);
                col *= res;
                col *= 1.0f + (talkingFactor * 1.1f); // Less extreme vibrancy boost when talking
                col *= 0.78f + (talkingFactor * 0.22f); // Tiny bit less vibrant colors when idle
                
                return half4(half3(col), 1.0);
            }
            """
            
            guard let validLibrary = try? device.makeLibrary(source: metalSource, options: nil) else {
                print("LiquidSiri: Failed to compile Metal string")
                return
            }
            
            guard let vertexFunc = validLibrary.makeFunction(name: "siriVertexShader"),
                  let fragmentFunc = validLibrary.makeFunction(name: "siriFragmentShader") else {
                print("LiquidSiri: Failed to find shader functions")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            
            // Enable additive blending so the black background becomes transparent
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("LiquidSiri: Failed to create pipeline state: \(error)")
            }
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize if needed
        }
        
        public func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let pipelineState = pipelineState,
                  let commandQueue = commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            
            // Set up uniforms
            let width = Float(view.drawableSize.width)
            let height = Float(view.drawableSize.height)
            
            var uniforms = SiriWaveUniforms(
                resolution: SIMD2<Float>(width, height),
                time: Float(parent.phase),
                talkingFactor: Float(parent.talkingFactor)
            )
            
            renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<SiriWaveUniforms>.stride, index: 0)
            
            // Draw full screen quad (6 vertices defined in vertex shader)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
