#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Diagnostic shader to tint the source layer red.
[[ stitchable ]] half4 liquidGlass(float2 position, SwiftUI::Layer source) {
    // Get the original color from the image.
    half4 original_color = source.sample(position);
    
    // Define a semi-transparent red color.
    half4 red_tint = half4(1.0, 0.0, 0.0, 0.5); // R, G, B, Alpha
    
    // Mix the original color with the red tint.
    // This will make the entire image reddish.
    return mix(original_color, red_tint, red_tint.a);
}