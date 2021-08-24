import os
import binaryparse, streams
import strformat
import parseopt
import strutils

const TRACKS = 77
const SIDES = 2
const SECTORS_PER_TRACK = 8
const BYTES_PER_SECTOR = 1024

proc changeFilenameExtension(filename: string, newExtension: string) : string =
    var chunks = filename.split(".");
    return join(chunks[0..^2], ".") & "." & newExtension;

proc stripHeader(filename : string) =
    # skip 512 bytes (the two headers)
    var imageContent = readFile(filename);
    var diskContent = imageContent[0x100..^1];
    assert(len(diskContent) == TRACKS * SIDES * SECTORS_PER_TRACK * BYTES_PER_SECTOR, "After removing the DIM header, the resulting image is the wrong size. Is it really a DIM?");
    var outputFilename = changeFilenameExtension(filename, "raw");
    writeFile(outputFilename, diskContent);

proc usage() =
    # TODO: Detect the "media type" bug from VFIC
    # described here: https://www.pc98.org/project/doc/dim.html
    echo fmt"Usage: {lastPathPart(paramStr(0))} [command] filename"
    echo "Commands: --help, --strip"
    echo "Options: --verbose"
    quit(1)

var filename: string
var verbose = false
type Mode = enum
    dimNil, dimStripHeader
var mode : Mode = dimNil

for kind, key, val in getopt(commandLineParams()):
    case kind
    of cmdArgument:
        # FIXME: this means that i have to put --media AFTER the filename
        if filename == "":
            filename = key
        else:
            usage()
    of cmdLongOption, cmdShortOption:
        case key
        of "help", "h": usage()
        of "strip", "s": mode = dimStripHeader
        of "verbose", "v": verbose = true
    of cmdEnd:
        assert(false)

if filename == "":
    usage()
else:
    # begin parsing
    case mode
    of dimStripHeader: stripHeader(filename)
    else: usage()
