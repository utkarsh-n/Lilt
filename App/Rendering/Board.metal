#include <metal_stdlib>
using namespace metal;

struct BoardPrimitive {
    float2 a;
    float2 b;
    float4 metrics;
    float4 detail;
};

struct BoardUniforms {
    float4 viewport;
    float4 board;
    float4 lighting;
    float4 appearance;
};

struct BoardVertexOut {
    float4 position [[position]];
    float2 world;
    float2 a;
    float2 b;
    float4 metrics;
    float4 detail;
};

float2 boardOrigin(constant BoardUniforms &u) {
    return (u.viewport.xy - u.board.xy * u.board.z) * 0.5;
}

float boardCornerRadius(constant BoardUniforms &u) {
    return u.appearance.x < 0.5 ? 0.009 : 0.039;
}

float roundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float2 closestSegment(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0000001), 0.0, 1.0);
    return a + ab * t;
}

float noise21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float smoothNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 s = f * f * (3.0 - 2.0 * f);
    return mix(mix(noise21(i), noise21(i + float2(1, 0)), s.x),
               mix(noise21(i + float2(0, 1)), noise21(i + float2(1, 1)), s.x), s.y);
}

float3 surfaceColor(float2 p, float theme) {
    if (theme < 0.5) {
        // Pale, close-grained plywood recalls a real tilt maze rather than stained furniture.
        float bend = sin(p.y * 4.1) * 0.012 + sin(p.y * 11.0 + p.x * 2.0) * 0.003;
        float grain = sin((p.x + bend) * 235.0 + sin(p.y * 3.0) * 2.4);
        float wide = smoothNoise(float2(p.x * 9.0, p.y * 1.2));
        float pores = smoothNoise(float2(p.x * 380.0, p.y * 36.0));
        float line = pow(0.5 + 0.5 * grain, 10.0);
        return float3(0.82, 0.75, 0.61) + wide * float3(0.115, 0.10, 0.075)
            - line * float3(0.016, 0.019, 0.017) + (pores - 0.5) * 0.012;
    }
    if (theme < 1.5) {
        float clouds = smoothNoise(p * 5.0) * 0.5 + smoothNoise(p * 17.0) * 0.16;
        float vein = pow(abs(sin(p.y * 14.0 + p.x * 11.0 + smoothNoise(p * 4.0) * 8.0)), 28.0);
        return float3(0.155, 0.40, 0.34) + clouds * float3(0.09, 0.20, 0.17) + vein * 0.019;
    }
    float stone = smoothNoise(p * 45.0) * 0.028 + smoothNoise(p * 200.0) * 0.012;
    return float3(0.064, 0.085, 0.115) + stone;
}

float3 brass(float2 radial, float3 light) {
    float a = atan2(radial.y, radial.x);
    float shine = 0.5 + 0.5 * dot(normalize(float3(radial, 0.55)), light);
    float brushing = sin(a * 220.0) * 0.02;
    return float3(0.48, 0.29, 0.105) + float3(0.45, 0.39, 0.25) * shine + brushing;
}

float4 over(float4 front, float4 back) {
    return front + back * (1.0 - front.a);
}

float4 paint(float3 color, float alpha) {
    alpha = clamp(alpha, 0.0, 1.0);
    return float4(color * alpha, alpha);
}

vertex BoardVertexOut liltBoardVertex(uint vertexID [[vertex_id]], constant BoardUniforms &u [[buffer(1)]]) {
    const float2 vertices[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    BoardVertexOut out;
    out.position = float4(vertices[vertexID], 0, 1);
    out.world = 0;
    out.a = 0;
    out.b = 0;
    out.metrics = 0;
    out.detail = 0;
    return out;
}

fragment float4 liltBoardFragment(BoardVertexOut in [[stage_in]], constant BoardUniforms &u [[buffer(1)]]) {
    float2 p = (in.position.xy / u.viewport.z - boardOrigin(u)) / u.board.z;
    float aa = 1.2 / (u.board.z * u.viewport.z);
    float2 center = u.board.xy * 0.5;
    float d = roundedBox(p - center, center, boardCornerRadius(u));
    float shadowD = roundedBox(p - center - float2(0.006, 0.009), center, boardCornerRadius(u));
    float4 result = paint(float3(0.008, 0.010, 0.012), (1.0 - smoothstep(0.0, 0.017, shadowD)) * 0.5);
    float mask = 1.0 - smoothstep(-aa, aa, d);
    if (mask < 0.001) { return result; }
    float3 base = surfaceColor(p, u.appearance.x);
    float vignette = 1.0 - dot((p - center) / u.board.xy, (p - center) / u.board.xy) * 0.13;
    float lightGradient = 1.025 - p.y / u.board.y * 0.040 - p.x * 0.018;
    base *= vignette * lightGradient;
    // A continuous chamfer is built into the edge rather than painted as four disconnected lines.
    float bevel = 1.0 - smoothstep(-0.016, -0.010, d);
    float frame = 1.0 - bevel;
    float edgeShade = clamp(0.55 + (center.x - p.x) * 0.3 + (center.y - p.y) * 0.23, 0.15, 1.0);
    float3 frameColor;
    if (u.appearance.x < 0.5) {
        frameColor = float3(0.67, 0.515, 0.32) * (0.83 + edgeShade * 0.37);
    } else if (u.appearance.x < 1.5) {
        frameColor = float3(0.12, 0.28, 0.235) * (0.7 + edgeShade * 0.65);
    } else {
        frameColor = float3(0.17, 0.205, 0.255) * (0.65 + edgeShade * 0.85);
    }
    base = mix(base, frameColor, frame);
    float edgeHighlight = exp(-abs(d + 0.0015) / 0.0012);
    base += edgeHighlight * float3(0.15, 0.13, 0.10) * edgeShade;
    float inset = exp(-abs(d + 0.016) / 0.0012);
    base *= 1.0 - inset * 0.28;
    // Four tiny fasteners give the frame scale and a tangible construction.
    float2 corner = min(p, u.board.xy - p) - float2(0.019);
    float screw = length(corner);
    if (screw < 0.006 && u.appearance.x > 0.5) {
        float ring = 1.0 - smoothstep(0.0035 - aa, 0.0035 + aa, screw);
        float3 metal = float3(0.42, 0.36, 0.24) + (0.004 - screw) * 40.0;
        float slot = (1.0 - smoothstep(0.0005, 0.001, abs(corner.y + corner.x * 0.35)))
                   * (1.0 - smoothstep(0.0025, 0.003, abs(corner.x)));
        base = mix(base, metal * (1.0 - slot * 0.75), ring);
    }
    return over(paint(base, mask), result);
}

vertex BoardVertexOut liltObjectVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                     const device BoardPrimitive *objects [[buffer(0)]],
                                     constant BoardUniforms &u [[buffer(1)]]) {
    BoardPrimitive object = objects[instanceID];
    const float2 corners[] = {float2(0, 0), float2(1, 0), float2(0, 1),
                              float2(0, 1), float2(1, 0), float2(1, 1)};
    float margin = object.metrics.y == 7.0 ? 0.003 : 0.032;
    float2 minimum = min(object.a, object.b) - object.metrics.x - margin;
    float2 maximum = max(object.a, object.b) + object.metrics.x + margin;
    float2 world = mix(minimum, maximum, corners[vertexID]);
    float2 point = world * u.board.z + boardOrigin(u);
    BoardVertexOut out;
    out.position = float4(point.x / u.viewport.x * 2.0 - 1.0,
                          1.0 - point.y / u.viewport.y * 2.0, 0, 1);
    out.world = world;
    out.a = object.a;
    out.b = object.b;
    out.metrics = object.metrics;
    out.detail = object.detail;
    return out;
}

fragment float4 liltObjectFragment(BoardVertexOut in [[stage_in]], constant BoardUniforms &u [[buffer(1)]]) {
    float2 p = in.world;
    float radius = in.metrics.x;
    int kind = int(in.metrics.y + 0.5);
    float aa = 1.25 / (u.board.z * u.viewport.z);
    float3 light = normalize(float3(-0.55 + u.lighting.x * 0.16, -0.72 + u.lighting.y * 0.16, 1.05));
    float2 center = closestSegment(p, in.a, in.b);
    float2 relative = p - center;
    float distance = length(relative);
    float2 normal2 = relative / max(distance, 0.000001);
    float d = distance - radius;
    float mask = 1.0 - smoothstep(-aa, aa, d);
    float4 result = float4(0);
    float boardMask = 1.0 - smoothstep(-aa, aa, roundedBox(p - u.board.xy * 0.5, u.board.xy * 0.5, boardCornerRadius(u)));

    if (kind == 0) {
        float2 displaced = p - float2(0.005, 0.009) + u.lighting.xy * 0.002;
        float sd = length(displaced - closestSegment(displaced, in.a, in.b)) - radius;
        float contact = 1.0 - smoothstep(-0.001, 0.007, d);
        float soft = 1.0 - smoothstep(-0.001, 0.009, sd);
        result = paint(float3(0.065, 0.045, 0.025), max(soft * 0.31, contact * 0.19));
    } else if (kind == 1) {
        float3 base = surfaceColor(p + float2(in.metrics.z * 0.041, 0), u.appearance.x);
        if (u.appearance.x > 1.5) {
            base = float3(0.15, 0.195, 0.25) + smoothNoise(p * 45.0) * 0.016;
        } else if (u.appearance.x < 0.5) {
            base = mix(base, float3(0.88, 0.705, 0.43), 0.40) * 1.05;
        } else {
            base *= 1.26;
        }
        // A broad, flat top and a narrow upright side read as a raised wood block.
        // Its base remains the exact capsule used by collision detection.
        float facing = dot(normal2, light.xy);
        float3 side = base * (0.54 + max(facing, 0.0) * 0.17);
        result = paint(side, mask);
        float2 topPoint = p - float2(-0.00065, -0.00125);
        float2 topRelative = topPoint - closestSegment(topPoint, in.a, in.b);
        float topDistance = length(topRelative);
        float topRadius = max(radius * 0.76, radius - 0.0017);
        float topD = topDistance - topRadius;
        float topMask = 1.0 - smoothstep(-aa, aa, topD);
        float2 topNormal = topRelative / max(topDistance, 0.000001);
        float bevel = smoothstep(-0.0011, -0.00015, topD);
        float topFacing = dot(topNormal, light.xy);
        float3 topColor = mix(base * 1.035, base * (0.80 + topFacing * 0.18), bevel);
        topColor += exp(-abs(topD + 0.0010) / 0.00045) * max(topFacing, 0.0) * 0.10;
        result = over(paint(topColor, topMask), result);
    } else if (kind == 2) {
        // A drilled recess: the wood itself forms the rim, with no decorative metal collar.
        float outer = 1.0 - smoothstep(radius + 0.0025 - aa, radius + 0.0025 + aa, distance);
        float3 cutEdge = surfaceColor(in.a, u.appearance.x) * (0.47 + max(dot(normal2, light.xy), 0.0) * 0.18);
        if (u.appearance.x > 1.5) {
            cutEdge = float3(0.24, 0.27, 0.31) * (0.65 + max(dot(normal2, light.xy), 0.0) * 0.24);
        }
        result = paint(cutEdge, outer);
        float innerSlope = smoothstep(radius * 0.72, radius, distance);
        float3 dark = mix(float3(0.007, 0.008, 0.009), float3(0.072, 0.059, 0.043), innerSlope * 0.65);
        dark += max(dot(-normal2, light.xy), 0.0) * innerSlope * float3(0.060, 0.052, 0.038);
        result = over(paint(dark, mask), result);
    } else if (kind == 3) {
        // The classic finish is a simple checkered disc, legible even in a tiny level preview.
        float border = 1.0 - smoothstep(radius + 0.0020 - aa, radius + 0.0020 + aa, distance);
        result = paint(float3(0.10, 0.092, 0.073), border);
        float2 cell = floor((relative + radius) / (radius * 0.4));
        float checker = fmod(cell.x + cell.y, 2.0);
        float3 checkerColor = mix(float3(0.055, 0.058, 0.056), float3(0.96, 0.95, 0.89), checker);
        float edgeInset = smoothstep(radius * 0.80, radius, distance);
        checkerColor *= 1.0 - edgeInset * 0.15;
        float finishMask = 1.0 - smoothstep(radius - 0.0015 - aa, radius - 0.0015 + aa, distance);
        result = over(paint(checkerColor, finishMask), result);
    } else if (kind == 4 || kind == 5 || kind == 6) {
        float shadowDistance = length(p - in.a - float2(0.007, 0.010)) - radius;
        result = paint(float3(0.02, 0.025, 0.028), (1.0 - smoothstep(0.0, 0.012, shadowDistance)) * 0.32);
        float3 base = brass(normal2, light);
        float lip = 1.0 - smoothstep(radius * 0.69, radius * 0.83, distance);
        float3 interior = kind == 4 ? float3(0.18, 0.43, 0.38)
                            : kind == 5 ? float3(0.11, 0.16, 0.24) : float3(0.22, 0.31, 0.30);
        base = mix(base, interior, lip);
        base *= 0.78 + max(dot(normal2, light.xy), 0.0) * 0.35;
        if (kind == 4) {
            float circular = exp(-abs(distance - radius * 0.53) / 0.0017);
            base += circular * float3(0.15, 0.25, 0.20);
            float top = exp(-dot(p - in.a - float2(-radius * 0.2, -radius * 0.22),
                                 p - in.a - float2(-radius * 0.2, -radius * 0.22)) / (radius * radius * 0.32));
            base += top * float3(0.17, 0.25, 0.22);
        } else if (kind == 5) {
            // Two machined pole bars distinguish a magnet at thumbnail scale.
            float2 q = (p - in.a) / radius;
            float poles = (1.0 - smoothstep(0.14, 0.18, abs(abs(q.x) - 0.28)))
                          * (1.0 - smoothstep(0.38, 0.44, abs(q.y)));
            base = mix(base, q.x < 0 ? float3(0.8, 0.26, 0.15) : float3(0.35, 0.69, 0.76), poles);
            float field = exp(-abs(distance - radius - 0.016) / 0.0012) * 0.12;
            result = over(paint(float3(0.38, 0.70, 0.78), field), result);
        } else {
            // Static slots are readable with reduced motion; the rotor animates only during play.
            float angle = atan2(relative.y, relative.x);
            float spin = u.lighting.w > 0.5 ? 0.0 : u.viewport.w * 2.0;
            float blades = pow(max(0.0, cos(angle * 5.0 + spin)), 9.0)
                           * smoothstep(radius * 0.18, radius * 0.4, distance)
                           * (1.0 - smoothstep(radius * 0.57, radius * 0.64, distance));
            base += blades * float3(0.25, 0.31, 0.29);
            float2 direction = normalize(in.detail.xy + float2(0.00001));
            float2 arrowPoint = relative / radius;
            float projection = dot(arrowPoint, direction);
            float perpendicular = abs(dot(arrowPoint, float2(-direction.y, direction.x)));
            float arrow = (1.0 - smoothstep(0.025, 0.06, perpendicular))
                          * smoothstep(-0.15, -0.1, projection) * (1.0 - smoothstep(0.18, 0.24, projection));
            base += arrow * 0.3;
        }
        result = over(paint(base, mask), result);
    } else if (kind == 7) {
        float segmentDistance = length(center - in.a);
        float dash = step(0.28, fract((in.detail.z + segmentDistance) / 0.035));
        result = paint(float3(0.17, 0.72, 0.50), mask * dash * 0.72);
    } else if (kind == 8 || kind == 9) {
        float fall = kind == 8 ? clamp(in.metrics.z, 0.0, 1.0) : 0.0;
        float sphereRadius = radius * (1.0 - fall * 0.75);
        float2 sphereCenter = in.a + float2(0.0, fall * radius * 0.36);
        float2 sphereDelta = p - sphereCenter;
        float sphereDistance = length(sphereDelta);
        float sphereMask = 1.0 - smoothstep(sphereRadius - aa, sphereRadius + aa, sphereDistance);
        float2 shadowDelta = (p - in.a - float2(radius * 0.28, radius * 0.43) + u.lighting.xy * 0.001)
                             / float2(radius * 1.27, radius * 0.84);
        float contactShadow = exp(-dot(shadowDelta, shadowDelta) * 1.6) * 0.44 * (1.0 - fall);
        result = paint(float3(0.012, 0.016, 0.019), contactShadow);
        if (kind == 9) {
            float outline = 1.0 - smoothstep(0.001, 0.0027, abs(sphereDistance - radius));
            result = over(paint(float3(0.61, 0.88, 0.85), sphereMask * 0.09 + outline * in.metrics.w), result);
        } else if (sphereMask > 0.001) {
            float2 xy = sphereDelta / sphereRadius;
            float z = sqrt(max(0.0, 1.0 - dot(xy, xy)));
            float3 normal = normalize(float3(xy, z));
            float3 view = float3(0, 0, 1);
            float3 reflection = reflect(-view, normal);
            // Steel gets its form from reflected ceiling strips, a dark horizon, and warm floor bounce.
            float sky = smoothstep(-0.4, 0.9, -reflection.y);
            float3 steel = mix(float3(0.19, 0.22, 0.25), float3(0.85, 0.89, 0.93), sky);
            float horizon = exp(-pow((reflection.y - 0.15) * 6.0, 2.0));
            steel *= 1.0 - horizon * 0.43;
            float ceiling = exp(-pow((reflection.x + 0.38 + reflection.y * 0.18) * 8.0, 2.0))
                            * smoothstep(-0.2, 0.6, reflection.z);
            steel += ceiling * float3(0.55, 0.58, 0.61);
            float ceiling2 = exp(-pow((reflection.x - 0.66) * 18.0, 2.0)) * 0.24;
            steel += ceiling2;
            float fresnel = pow(1.0 - z, 3.0);
            steel = mix(steel, float3(0.38, 0.42, 0.45), fresnel * 0.5);
            steel += max(reflection.y, 0.0) * float3(0.095, 0.073, 0.041) * (u.appearance.x < 0.5 ? 1.0 : 0.25);
            float diffuse = 0.82 + max(dot(normal, light), 0.0) * 0.18;
            steel *= diffuse;
            float specular = pow(max(dot(normal, normalize(light + view)), 0.0), 115.0);
            steel += specular * 1.15;
            steel *= 1.0 - fall * 0.57;
            result = over(paint(steel, sphereMask * (1.0 - pow(fall, 4.0))), result);
        }
    } else if (kind == 10) {
        float ring = 1.0 - smoothstep(0.00065, 0.0015, abs(distance - radius));
        float angle = atan2(relative.y, relative.x);
        float dash = step(0.3, fract(angle * 5.0));
        result = paint(float3(0.24, 0.20, 0.115), ring * dash * 0.28);
    }
    return result * boardMask;
}
