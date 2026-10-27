/// The Metal shaders as text that the renderer compiles when it starts.
/// `swift build` does not compile `.metal` files, and the offline compiler
/// needs a download of the Metal toolchain, so the source lives in Swift.
/// `Quad` must have the layout of `CellQuad`, and each quad has 4 vertices.
enum ShaderSource {
    static let text = """
    #include <metal_stdlib>
    using namespace metal;

    struct Quad { float2 origin; float2 size; float2 atlasOrigin; uint isColor; uint column; float4 color; };
    struct Corner { float4 position [[position]]; float2 atlas; float4 color; uint isColor [[flat]]; };

    constant float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };

    vertex Corner quadVertex(uint corner [[vertex_id]], uint instance [[instance_id]],
                             constant float2 &viewport [[buffer(0)]], const device Quad *quads [[buffer(1)]]) {
        Quad quad = quads[instance];
        float2 pixel = quad.origin + corners[corner] * quad.size;
        Corner out;
        out.position = float4(pixel.x / viewport.x * 2.0 - 1.0, 1.0 - pixel.y / viewport.y * 2.0, 0, 1);
        out.atlas = quad.atlasOrigin + corners[corner] * quad.size;
        out.color = quad.color;
        out.isColor = quad.isColor;
        return out;
    }

    fragment float4 rectangleFragment(Corner in [[stage_in]]) {
        return float4(in.color.rgb * in.color.a, in.color.a);
    }

    fragment float4 glyphFragment(Corner in [[stage_in]], texture2d<float> coverage [[texture(0)]],
                                  texture2d<float> colors [[texture(1)]]) {
        constexpr sampler pixels(coord::pixel, filter::nearest);
        if (in.isColor != 0) {
            // An emoji keeps its own colors. Only the alpha of the quad fades it.
            return colors.sample(pixels, in.atlas) * in.color.a;
        }
        float alpha = coverage.sample(pixels, in.atlas).r * in.color.a;
        return float4(in.color.rgb * alpha, alpha);
    }
    """
}
