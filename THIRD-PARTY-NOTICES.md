# Third-party notices and credits

`ModRunner` itself has no third-party code dependencies — it builds against
Apple's SDK frameworks only. The material listed here is documentation and
reference source that shaped the implementation, plus the people whose work made
any of this possible. Credit where credit is due.

---

## MED / OctaMED file format specification

**Teijo Kinnunen** — author of MED and OctaMED, and of the format specification
that this player is built on.

| File | Document | Status |
|---|---|---|
| `docs/MED-Format-rev1.txt` | *MED/OctaMED MMD0 and MMD1 file formats*, Revision 1, 25.04.1992 | Explicitly placed in the **public domain** by the author |
| `docs/MMD_FileFormat.txt` | *MED/OctaMED MMD0/MMD1/MMD2/MMD3 file formats*, Revision 6, 01.02.1996 | No licence statement; see note below |

Revision 1 closes with:

> "NOTE! This text file is PUBLIC DOMAIN. All distribution of this file, via the
> pd is strongly encouraged. Thank you!"

Revision 6 carries no equivalent statement. It is the same author and the same
document lineage, it has been redistributed with development materials for three
decades, and the author explicitly encouraged distribution of the earlier
revision — so it is included here. If the rights holder objects, it will be
removed on request and replaced with a link.

Upstream copy of Revision 6:
<https://github.com/dv1/ion_player/blob/master/extern/uade-2.13/amigasrc/players/med/MMD_FileFormat.doc>

---

## OpenMPT — `soundlib/Load_med.cpp`

**The OpenMPT developers.** Their MED loader was the cross-check for the tempo
conversion and the effect command mapping. A copy is included at
`docs/openmpt_Load_med.cpp` for reference.

> Copyright (c) OpenMPT Developers
>
> OpenMPT is released under the BSD 3-Clause License.

```
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

Upstream: <https://github.com/OpenMPT/openmpt>

No OpenMPT code is compiled into this project.

---

## OctaMED SoundStudio manual — cited, not included

**Ed Wiles / RBF Software**, *OctaMED SoundStudio V1.03c Manual*, © RBF Software
1997. Appendices A and B are the authoritative reference for the player command
set, which the format specification does not document, and this player's effect
handling was built and corrected against them.

The manual is marked **"NOT PUBLIC DOMAIN"** and carries no licence permitting
redistribution, so it is **not included** in this repository. Attribution does
not substitute for a licence.

---

## libxmp / Extended Module Player

**Claudio Matsuoka and Hipolito Carraro Jr.** libxmp was used as the independent
reference renderer to verify playback accuracy — duration, note timing and
spectral content were compared against its output. No libxmp code is included.

Upstream: <https://xmp.sourceforge.net/>

---

## Example modules

`Examples/*.med` are compositions by **Lars Gossard** (© 2026 incūdex, Lars
Gossard), written in 1993 with MED V1.30 and originally released as the *Magic
Noises* collection. They are included by the author. See `Examples/README.md`.

---

## Trademarks

Amiga, AmigaOS and Workbench are trademarks of their respective owners. MED and
OctaMED are the work of Teijo Kinnunen and RBF Software. References to them here
are descriptive, to say what this software reads and what visual idiom it
follows. No affiliation or endorsement is claimed or implied. No Amiga artwork,
icons, fonts or ROM code are included in this repository.
