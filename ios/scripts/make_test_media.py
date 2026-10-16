"""Builds Bilibili-like DASH test media (separate video/audio files with a sidx) with ffmpeg.

Usage: python make_test_media.py OUTPUT_DIR
Writes avc-video.mp4, avc-audio.mp4, hevc-video.mp4, hevc-audio.mp4 and meta.json.
"""
import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

VARIANTS = {
    "avc": ["-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-preset", "veryfast", "-b:v", "600k"],
    "hevc": ["-c:v", "libx265", "-tag:v", "hev1", "-pix_fmt", "yuv420p", "-preset", "veryfast", "-b:v", "600k",
             "-x265-params", "log-level=error"],
}


def boxes(data):
    offset = 0
    while offset + 8 <= len(data):
        size, kind = struct.unpack(">I4s", data[offset:offset + 8])
        if size == 1:
            size = struct.unpack(">Q", data[offset + 8:offset + 16])[0]
        if size < 8:
            break
        yield kind.decode("latin-1"), offset, size
        offset += size


def child(data, start, end, kind):
    for name, offset, size in boxes(data[start:end]):
        if name == kind:
            return start + offset, start + offset + size
    raise SystemExit(f"no {kind} box")


def hev1_codecs(path):
    """ffmpeg's MPD leaves codecs empty for hev1, so the RFC 6381 string is read from hvcC."""
    data = path.read_bytes()
    span = (0, len(data))
    for kind in ["moov", "trak", "mdia", "minf", "stbl"]:
        start, end = child(data, *span, kind)
        span = (start + 8, end)
    stsd_start, stsd_end = child(data, *span, "stsd")
    # stsd: header, version/flags, entry count; hev1 visual sample entry: header plus 78 bytes.
    entry_start, entry_end = child(data, stsd_start + 16, stsd_end, "hev1")
    hvcc_start, _ = child(data, entry_start + 86, entry_end, "hvcC")
    config = data[hvcc_start + 8:hvcc_start + 8 + 13]
    space = "" if config[1] >> 6 == 0 else "ABC"[(config[1] >> 6) - 1]
    tier = "H" if config[1] & 0x20 else "L"
    profile = config[1] & 0x1F
    compatibility = int(f"{struct.unpack('>I', config[2:6])[0]:032b}"[::-1], 2)
    constraints = list(config[6:12])
    while constraints and constraints[-1] == 0:
        constraints.pop()
    return ".".join([f"hev1.{space}{profile}", f"{compatibility:X}", f"{tier}{config[12]}", *(f"{b:X}" for b in constraints)])


def ranges(path):
    data = path.read_bytes()
    found = {kind: (offset, size) for kind, offset, size in boxes(data)}
    if "moov" not in found or "sidx" not in found:
        raise SystemExit(f"{path.name}: expected moov and sidx, found {sorted(found)}")
    moov_offset, moov_size = found["moov"]
    sidx_offset, sidx_size = found["sidx"]
    return {
        "initialization": f"0-{moov_offset + moov_size - 1}",
        "indexRange": f"{sidx_offset}-{sidx_offset + sidx_size - 1}",
        "size": len(data),
    }


def build(variant, codec_args, out):
    with tempfile.TemporaryDirectory() as work:
        work = pathlib.Path(work)
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
            "-t", "40", "-map", "0:v", "-map", "1:a",
            *codec_args, "-g", "60", "-keyint_min", "60", "-sc_threshold", "0",
            "-c:a", "aac", "-b:a", "128k",
            "-f", "dash", "-global_sidx", "1", "-single_file", "1", "-single_file_name", f"{variant}-$RepresentationID$.mp4",
            "-seg_duration", "2", str(work / f"{variant}.mpd"),
        ], check=True, cwd=work)
        manifest = ET.parse(work / f"{variant}.mpd").getroot()
        ns = {"d": "urn:mpeg:dash:schema:mpd:2011"}
        reps = {rep.get("id"): rep for rep in manifest.iterfind(".//d:Representation", ns)}
        result = {}
        for rep_id, rep in reps.items():
            kind = "video" if rep.get("width") else "audio"
            target = out / f"{variant}-{kind}.mp4"
            shutil.copy(work / f"{variant}-{rep_id}.mp4", target)
            result[kind] = {
                "file": target.name,
                "codecs": rep.get("codecs") or hev1_codecs(target),
                "bandwidth": int(rep.get("bandwidth")),
                "width": int(rep.get("width") or 0),
                "height": int(rep.get("height") or 0),
                **ranges(target),
            }
        result["duration"] = 40
        return result


def main():
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    meta = {variant: build(variant, args, out) for variant, args in VARIANTS.items()}
    (out / "meta.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
