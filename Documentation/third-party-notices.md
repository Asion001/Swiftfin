# Third-Party Notices

## MPVKit

Swiftfin Enhanced's MPV player embeds libmpv and its dependencies through
[`mpvkit/MPVKit`](https://github.com/mpvkit/MPVKit), pinned to version `1.0.0`.

Swiftfin links the **non-GPL** `MPVKit` product. The `MPVKit-GPL` product must not be used: it
would place the whole application under the GPL.

Pinned component versions at the time of writing:

| Component | Version | License |
|---|---|---|
| mpv (libmpv) | v0.41.0 | LGPL-2.1-or-later |
| FFmpeg | n8.1.2 | LGPL-2.1-or-later |
| libplacebo | 7.360.1 | LGPL-2.1-or-later |
| MoltenVK | 1.4.2 | Apache-2.0 |
| libass | 0.17.5 | ISC |
| dav1d | 1.5.3 | BSD-2-Clause |
| libdovi | 3.3.2 | MIT |
| little-CMS (lcms2) | 2.17.0 | MIT |

### LGPL compliance

`Libmpv.xcframework` and the FFmpeg xcframeworks are **static** archives, so the LGPL's relinking
requirement is satisfied by publishing complete corresponding source. Swiftfin Enhanced is
open source under the MPL, and the libmpv build — including any Swiftfin patches — is published in
the MPVKit fork referenced by this repository's package resolution. See
[the MPV player documentation](mpv.md) for how that build is produced.

Any modification Swiftfin makes to libmpv must remain publicly available on those same terms.

## ArtCNN

Shader upscaling bundles GLSL programs from
[`Artoriuz/ArtCNN`](https://github.com/Artoriuz/ArtCNN), pinned at commit
`c619fc3292d8867378e072f08bb0500c086440d5`:

- `Shared/Resources/ArtCNN/ArtCNN_C4F16.glsl`
- `Shared/Resources/ArtCNN/ArtCNN_C4F32.glsl`

The files are shipped unmodified and retain their original MIT headers. Users may supply their own
shaders in the MPV configuration directory, which take precedence over the bundled set.

MIT License

Copyright (c) 2024 Joao Chrisostomo, Kacper Michajłow

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
