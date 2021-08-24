# X68000 floppy tools
Some utilities for dealing with common DIM disk images for the Sharp X68000, including those preserved by the Neo-Kobe group.

Most of the information used in the production of these utilities came from [the pc98.org documentation on the DIM image format](/https://www.pc98.org/project/doc/dim.html).

Tested against images converted using the Virtual Floppy Image Converter (VFIC) tool.

## Basic Usage
Build with nim using `nim c dim.nim`.

### Strip
Strips the DIM header off of a disk image, converting it to a "raw" image. It will be saved as `yourimagename.raw`.

Example:
```
% ./dim --strip Human 68k v3.02 with WINDVR (1993)(Sharp - Hudson).dim
```
