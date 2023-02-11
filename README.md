# X68000 floppy tools
Some utilities for dealing with common DIM disk images for the Sharp X68000, including those preserved by the Neo-Kobe group.

Most of the information used in the production of these utilities came from [the pc98.org documentation on the DIM image format](https://www.pc98.org/project/doc/dim.html) and [their documentation on the D88 image format](https://www.pc98.org/project/doc/d88.html).

Tested against images converted using the Virtual Floppy Image Converter (VFIC) tool.

## Basic Usage
Build with nim using `nim c dim.nim`.

### Strip
Strips the DIM header off of a disk image, converting it to a "raw" image. It will be saved as `yourimagename.raw`.

Example:
```
% ./dim --strip Human 68k v3.02 with WINDVR (1993)(Sharp - Hudson).dim
```

### Dump Header
Dumps the header in a (more) human-readable format. The DIM header is so thin that there is not much useful information contained in it.

Example:
```
% ./dim --dump Human 68k v3.02 with WINDVR (1993)(Sharp - Hudson).dim
```

### D88 conversion
Convert an X68000 DIM image directly to D88 format so it can be written by tools such as TransDisk. It will be saved as `yourimagename.d88`.

The encoding is X68000 standard (77 tracks, 2 sides, 8 sectors per track, 1024 bytes per sector.)

Options:
 * `--verbose`: Emits a lot of debug messages that may help with identifying problems with a weird source image.

Example:
```
% ./dim --d88 Human 68k v3.02 with WINDVR (1993)(Sharp - Hudson).dim
```
