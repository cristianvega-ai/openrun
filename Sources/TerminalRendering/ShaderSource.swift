/// The Metal shaders as text that the renderer compiles when it starts.
/// `swift build` does not compile `.metal` files, and the offline compiler
/// needs a download of the Metal toolchain, so the source lives in Swift.
/// `Quadrilateral` must have the layout of `CellQuadrilateral`, and each quadrilateral has 4 vertices.
enum ShaderSource {
    static let text = """
    #include <metal_stdlib>
    using namespace metal;

    struct Quadrilateral { float2 origin; float2 size; float2 atlasOrigin; uint isColor; uint column; float4 color; };
    struct Corner { float4 position [[position]]; float2 atlas; float4 color; uint isColor [[flat]]; };

    constant float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };

    vertex Corner quadrilateralVertex(uint corner [[vertex_id]], uint instance [[instance_id]],
                             constant float2 &viewport [[buffer(0)]], const device Quadrilateral *quadrilaterals [[buffer(1)]]) {
        Quadrilateral quadrilateral = quadrilaterals[instance];
        float2 pixel = quadrilateral.origin + corners[corner] * quadrilateral.size;
        Corner vertexOutput;
        vertexOutput.position = float4(pixel.x / viewport.x * 2.0 - 1.0, 1.0 - pixel.y / viewport.y * 2.0, 0, 1);
        vertexOutput.atlas = quadrilateral.atlasOrigin + corners[corner] * quadrilateral.size;
        vertexOutput.color = quadrilateral.color;
        vertexOutput.isColor = quadrilateral.isColor;
        return vertexOutput;
    }

    fragment float4 rectangleFragment(Corner fragmentInput [[stage_in]]) {
        return float4(fragmentInput.color.rgb * fragmentInput.color.a, fragmentInput.color.a);
    }

    fragment float4 glyphFragment(Corner fragmentInput [[stage_in]], texture2d<float> coverage [[texture(0)]],
                                  texture2d<float> colors [[texture(1)]]) {
        constexpr sampler pixels(coord::pixel, filter::nearest);
        if (fragmentInput.isColor != 0) {
            // An emoji keeps its own colors. Only the alpha of the quadrilateral fades it.
            return colors.sample(pixels, fragmentInput.atlas) * fragmentInput.color.a;
        }
        float alpha = coverage.sample(pixels, fragmentInput.atlas).r * fragmentInput.color.a;
        return float4(fragmentInput.color.rgb * alpha, alpha);
    }
    """
}
