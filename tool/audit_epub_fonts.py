"""Compare EPUB font coverage and SFNT checksums; requires fontTools."""

import argparse
import io
import json
import xml.etree.ElementTree as ET
import zipfile

from fontTools.ttLib import TTFont


def checksum_errors(data):
    errors = []
    with TTFont(io.BytesIO(data), checkChecksums=2) as font:
        for tag in font.reader.keys():
            try:
                font.reader[tag]
            except Exception as exc:
                errors.append(str(exc))
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original")
    parser.add_argument("processed")
    args = parser.parse_args()
    results = []
    with zipfile.ZipFile(args.original) as original, zipfile.ZipFile(args.processed) as processed:
        characters = set()
        for name in original.namelist():
            if name.endswith((".xhtml", ".html")):
                text = "".join(ET.fromstring(original.read(name)).itertext())
                characters.update(map(ord, text))
        for name in original.namelist():
            if not name.endswith((".ttf", ".otf")):
                continue
            before, after = original.read(name), processed.read(name)
            with TTFont(io.BytesIO(before)) as source, TTFont(io.BytesIO(after)) as target:
                used = characters & set(source.getBestCmap())
                missing = used - set(target.getBestCmap())
                order = set(target.getGlyphOrder())
                missing_glyphs = [
                    cp for cp in used if target.getBestCmap().get(cp) not in order
                ]
            results.append({
                "font": name,
                "source_bytes": len(before),
                "processed_bytes": len(after),
                "used_codepoints": len(used),
                "missing_codepoints": sorted(missing),
                "missing_glyphs": sorted(missing_glyphs),
                "source_checksum_errors": checksum_errors(before),
                "processed_checksum_errors": checksum_errors(after),
                "unchanged": before == after,
            })
    print(json.dumps(results, ensure_ascii=False, indent=2))
    if any(r["missing_codepoints"] or r["missing_glyphs"] or
           r["processed_checksum_errors"] for r in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
