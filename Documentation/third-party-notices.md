# Third-Party Notices

## Anime4KMetal

Swiftfin's Enhanced iOS/iPadOS player uses
[`cinemore/anime4k-metal`](https://github.com/cinemore/anime4k-metal), pinned to
version `0.1.2` at commit `60915937f6f391b30d50102533ce6fd98d009174`.

MIT License

Copyright (c) 2026 xzhih

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

## Anime4K shaders

Anime4KMetal includes Anime4K v3/v4 GLSL shader programs derived from
[`bloc97/Anime4K`](https://github.com/bloc97/Anime4K). The shader files retain
their original MIT headers.

MIT License

Copyright (c) 2019-2021 bloc97

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

## Build-plugin security review

The pinned Anime4KMetal SwiftPM build-tool plugin was reviewed before adoption.
It enumerates only `.metal` files inside the package's `Shaders` directory,
locates Apple's `metal` and `metallib` tools through `/usr/bin/xcrun`, and
writes AIR and metallib outputs only into SwiftPM's plugin work directory. It
does not access the network, execute package-provided binaries, inspect user
data, or write outside the build workspace.
