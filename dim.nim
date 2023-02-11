import os
import binaryparse, streams
import strformat
import parseopt
import lists
import strutils

const TRACKS = 77
const SIDES = 2
const SECTORS_PER_TRACK = 8
const BYTES_PER_SECTOR = 1024
const TRACK_LENGTH = SECTORS_PER_TRACK * BYTES_PER_SECTOR
const DISK_DATA_LENGTH = TRACKS * TRACK_LENGTH * SIDES

const D88_DISK_LABEL_LENGTH = 16

proc changeFilenameExtension(filename: string, newExtension: string) : string =
    var chunks = filename.split(".")
    return join(chunks[0..^2], ".") & "." & newExtension

proc getRawFloppyData(dimImageContent : string) : string =
    var diskContent = dimImageContent[0x100..^1]
    assert(len(diskContent) == TRACKS * SIDES * SECTORS_PER_TRACK * BYTES_PER_SECTOR, "After removing the DIM header, the resulting image is the wrong size. Is it really a DIM?")
    return diskContent

type
    D88MediaType {.size: 1} = enum
        D88_2D = 0x00
        D88_2DD = 0x10
        D88_2HD = 0x20

type
    D88WriteProtectFlag {.size: 1} = enum
        D88_NO_WRITE_PROTECT = 0x00
        D88_WRITE_PROTECT = 0x10

type D88_X68000_Track = array[TRACK_LENGTH, uint8]

const D88_SECTOR_HEADER_SIZE = 0x10
type D88Image = ref object
    diskName: string
    writeProtected: bool
    useLegacyHeader: bool
    mediaFlag: D88MediaType
    tracks: seq[D88_X68000_Track]

proc newD88Image: D88Image = 
    new result
    result.writeProtected = false
    result.mediaFlag = D88_2HD
    result.useLegacyHeader = false
    result.tracks = newSeq[D88_X68000_Track]()

proc addTrack*(target: D88Image, track: D88_X68000_Track) =
    target.tracks.add(track)

proc setDiskName*(target: D88Image, newName: string) =
    var trimmed = newName[0 .. min(len(newName) - 1, 15)] # FIXME: This is clunky, does Nim not have an "up to" slice operator?
    var padded = alignLeft(trimmed, D88_DISK_LABEL_LENGTH, '\0')
    target.diskName = padded

proc getHeaderLength*(target: D88Image) : uint32 =
    # legacy headers are only 160 tracks, whereas
    # the "new" headers can be up to 164 tracks. this means that
    # the overall header size is different
    if target.useLegacyHeader:
        return 672
    else:
        return 688

proc getRealTrackLength*(target: D88Image) : uint32 =
    # Don't forget that sectors have headers of their own
    return (D88_SECTOR_HEADER_SIZE * SECTORS_PER_TRACK) + TRACK_LENGTH

proc getDiskSize*(target: D88Image) : uint32 =
    # including header size, this is the value we write out to the file
    # not the size of the actual data inside the disk
    var size = target.getHeaderLength()
    size += uint32(target.tracks.len) * target.getRealTrackLength()
    return size

proc writeD88*(source: D88Image, filename: string, verbose: bool) =
    var file = newFileStream(filename, fmWrite)
    # disk label
    assert(len(source.diskName) == 16)
    file.write(source.diskName)
    assert(file.getPosition() == 16)
    # termination byte
    file.write(cast[uint8](0))
    assert(file.getPosition() == 17)
    # reserved (9 bytes)
    for i in 0..<9:
        file.write(cast[uint8](0))
    assert(file.getPosition() == 26)
    if source.writeProtected:
        file.write(cast[uint8](D88_WRITE_PROTECT))
    else:
        file.write(cast[uint8](D88_NO_WRITE_PROTECT))
    assert(file.getPosition() == 27)
    #var mediaFlagValue : uint8 = cast[uint8](source.mediaFlag)
    #assert(sizeof(mediaFlagValue) == 1) # FIXME: WTF?
    file.write(cast[uint8](source.mediaFlag)) # just to be paranoid that it didn't go to an i32 or something
    assert(file.getPosition() == 28)
    file.write(cast[uint32](source.getDiskSize()))
    #echo fmt"Position = {getFilePos(file)}"
    assert(file.getPosition() == 32)

    # track pointer header
    var tracks_in_output = 164
    if source.useLegacyHeader:
        tracks_in_output = 160 # write fewer tracks

    var blank_track_count = 0
    
    for i in 0 ..< tracks_in_output:
        if i >= source.tracks.len:
            file.write(cast[uint32](0)) # this track does not exist
            blank_track_count += 1
        else:
            # each sector has a header on it now
            var real_track_length = source.getRealTrackLength();
            # sectors start after the disk header
            var offset = source.getHeaderLength() + (real_track_length * uint32(i))
     
            if verbose:
                echo fmt"Pointer for track #{i} -> {offset}"
            file.write(cast[uint32](offset))
    
    if verbose:
        echo fmt"Header written. Wrote {blank_track_count} blank tracks, now at {file.getPosition()} bytes"
    assert(cast[uint32](file.getPosition()) == source.getHeaderLength())

    # now we can actually write the real tracks
    var is_side_two = false

    for i, track in source.tracks.mpairs:
        # get each sector
        var j = 0
        assert(len(track) == BYTES_PER_SECTOR * SECTORS_PER_TRACK)
        while j < len(track):
            # write sector header
            var cylinder_number = uint8(i / 2)
            file.write(cylinder_number) # cylinder number

            var side_number : uint8 = 0
            if is_side_two: # head number
                side_number = 1
            file.write(side_number)

            # Sector IDs (1-indexed)
            var sector_index : uint8 = uint8(j / BYTES_PER_SECTOR)
            file.write(sector_index + 1) # sector number
            file.write(cast[uint8](3)) # sector size (128 << 3 = 1024)

            file.write(cast[uint16](SECTORS_PER_TRACK)) # number of sectors per track (why is this in the sector data, just validation?)
            file.write(cast[uint8](0x00)) # let's assume double density ($00) and not single ($40)
            file.write(cast[uint8](0)) # no deleted tracks here! (maybe)
            file.write(cast[uint8](0)) # FDC status code all okay. no damaged tracks here, copy protection!
            
            for i in 0..<4:
                file.write(cast[uint8](0)) # reserved

            var rpm : uint8 = 0 # 0 : 1.2, 1 : 1.44? MB?
            file.write(rpm)
            
            file.write(cast[uint16](BYTES_PER_SECTOR)) # size of the data following this header

            if verbose:
                echo fmt"Finished writing header for track {cylinder_number} side {side_number} sector {sector_index}: at position {file.getPosition()}" 
            
            # write sector data
            var before_writing_sector = file.getPosition()
            for k in 0 ..< BYTES_PER_SECTOR:
                file.write(cast[uint8](track[j + k]))
            var after_writing_sector = file.getPosition()
            assert(before_writing_sector + BYTES_PER_SECTOR == after_writing_sector)

            j += BYTES_PER_SECTOR
        is_side_two = not is_side_two

proc hex_dump_track(track : D88_X68000_Track) =
    for i in 0 ..< len(track):
        stdout.write(fmt("{toHex(track[i], 2)} "))
        if (i + 1) mod 8 == 0:
            stdout.write("\n")
        if (i + 1) mod BYTES_PER_SECTOR == 0:
            stdout.write("\n")

proc convertToD88(filename : string, verbose : bool, legacy_160track_mode : bool) =
    # Strip DIM header and go
    var diskContent = getRawFloppyData(readFile(filename))
    assert(len(diskContent) == DISK_DATA_LENGTH) # make sure we got it all
    var result = newD88Image()
    
    var i = 0;
    while i < len(diskContent):
        # split diskContent into 8192 byte chunks (one track)
        # and create a new D88Image
        var track = diskContent[i .. i + SECTORS_PER_TRACK * BYTES_PER_SECTOR - 1]
        assert(len(track) == SECTORS_PER_TRACK * BYTES_PER_SECTOR);

        # I can't do a straight cast for cast[D88_X68000_Track], it mangles the stride
        var t : D88_X68000_Track;
        for j in 0 ..< TRACK_LENGTH:
            t[j] = uint8(track[j])

        if verbose:
            echo fmt"Track {int(i / (SECTORS_PER_TRACK * BYTES_PER_SECTOR))}:"
            hex_dump_track(t)
        
        result.addTrack(t)
        
        i += SECTORS_PER_TRACK * BYTES_PER_SECTOR

    if verbose:
        echo fmt"{result.tracks.len} track(s) in d88, preparing write"
    
    result.setDiskName(filename)

    if legacy_160track_mode:
        result.useLegacyHeader = true

    result.writeD88(changeFilenameExtension(filename, "d88"), verbose)

proc stripHeader(filename : string) =
    # skip 512 bytes (the two headers)
    var imageContent = readFile(filename);
    var diskContent = getRawFloppyData(imageContent);
    var outputFilename = changeFilenameExtension(filename, "raw");
    writeFile(outputFilename, diskContent);

proc guess_media_type(t : uint8) : string =
    return case t:
        of 0x00, 0x01: "2HS (9sec/trk 1440k)"
        of 0x02: "2HC (15sec/trk 1200k) [80/2/15/512]"
        of 0x03: "2HQ (18sec/trk 1440k) IBM 1.44MB 2HD format"
        else: "unknown"

proc dump(filename : string) =
    createParser(dim_parser):
        u8: media_type
        u8: track_present[160]
        u8: reserved[10]
        u8: header_string[13]
        u16: reserved2
    
    var file = newFileStream(filename, fmRead)
    if file != nil:
        defer: file.close()
        var dim_header = dim_parser.get(file)

        echo fmt"Media type: ${toHex(dim_header.media_type, 2)} ({guess_media_type(dim_header.media_type)})"

        var track_count = 160

        for i in 0 ..< len(dim_header.track_present):
            if dim_header.track_present[i] < 1:
                echo fmt"Track {i} is first missing"
                track_count = i + 1
                break

        echo fmt"Reserved 1 = '{dim_header.reserved}'"
        echo fmt"Header string = '{cast[string](dim_header.header_string)}'"
        echo fmt"Reserved 2 = '{dim_header.reserved2}'"

proc usage() =
    # TODO: Detect the "media type" bug from VFIC
    # described here: https://www.pc98.org/project/doc/dim.html
    echo fmt"Usage: {lastPathPart(paramStr(0))} [command] filename"
    echo "Commands: --help, --strip --d88 --dump"
    echo "Options: --verbose"
    quit(1)

var filename: string
var verbose = false
var legacy_d88_construction = false
type Mode = enum
    dimNil, dimStripHeader, dimConvertD88, dimDumpHeader
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
        of "dump", "d": mode = dimDumpHeader
        of "d88": mode = dimConvertD88
        of "verbose", "v": verbose = true
        of "legacy", "l": legacy_d88_construction = true
    of cmdEnd:
        assert(false)

if filename == "":
    usage()
else:
    # begin parsing
    case mode
    of dimStripHeader: stripHeader(filename)
    of dimConvertD88: convertToD88(filename, verbose, legacy_d88_construction)
    of dimDumpHeader: dump(filename)
    else: usage()
