// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors

// A luminance-only unsharp mask, run after the main scaler.
//
// This is the stage the AVPlayer-based upscaler ended with before this player
// replaced it: MetalFX or a CNN reconstructs the detail that is recoverable,
// and this restores the acutance that any resampling costs. Without it both
// providers are close to invisible at the 1.2x-2.8x factors a phone actually
// asks for, which is what the old implementation's `CISharpenLuminance` pass
// was there to solve.
//
// Sharpening luma alone is deliberate: applying it per channel turns chroma
// noise into coloured speckle, which is the artifact this player was already
// reported for.

//!PARAM amount
//!DESC Sharpening strength
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
0.0

//!DESC Swiftfin luminance unsharp mask
//!HOOK SCALED
//!BIND HOOKED

#define LUMA_WEIGHTS vec3(0.2126, 0.7152, 0.0722)

vec4 hook() {
    vec4 colour = HOOKED_texOff(vec2(0.0, 0.0));

    if (amount <= 0.0) {
        return colour;
    }

    // A 3x3 tent kernel: 4 at the centre, 2 on the edges, 1 on the corners,
    // summing to 16. A wider radius reads as a glow rather than as detail at
    // the distance a phone is held.
    float blurred = 0.0;

    for (float y = -1.0; y <= 1.0; y++) {
        for (float x = -1.0; x <= 1.0; x++) {
            float weight = 4.0 / pow(2.0, abs(x) + abs(y));
            blurred += weight * dot(HOOKED_texOff(vec2(x, y)).rgb, LUMA_WEIGHTS);
        }
    }

    blurred /= 16.0;

    float detail = dot(colour.rgb, LUMA_WEIGHTS) - blurred;

    // Halos are what makes sharpening look cheap, so the correction is capped
    // instead of staying proportional to however strong an edge it found.
    float limit = 0.1 * amount;

    colour.rgb = max(colour.rgb + clamp(amount * detail, -limit, limit), 0.0);

    return colour;
}
