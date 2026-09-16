"""Audit local EPUB outputs without extracting or executing book contents."""

import argparse
import collections
import hashlib
import io
import json
import posixpath
import re
import struct
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

_decoded_images = {}


def local_target(source, href):
    uri = urllib.parse.urlsplit(href)
    if uri.scheme or uri.netloc:
        return None
    path = urllib.parse.unquote(uri.path)
    return (
        posixpath.normpath(posixpath.join(posixpath.dirname(source), path))
        if path else source
    )


def audit(path, check_images=False):
    result = {"path": str(path), "errors": [], "reference_warnings": []}
    errors = result["errors"]
    warnings = result["reference_warnings"]
    result["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    with zipfile.ZipFile(path) as z:
        entries = z.infolist()
        names = set(z.namelist())
        result["bytes"] = path.stat().st_size
        result["entries"] = len(entries)
        result["types"] = dict(collections.Counter(
            posixpath.splitext(n)[1] for n in names))
        if len(names) != len(entries):
            errors.append("Duplicate ZIP entries")
        if z.testzip():
            errors.append("ZIP CRC failure")
        with path.open("rb") as stream:
            header = stream.read(30)
        method, = struct.unpack_from("<H", header, 8)
        extra_len, = struct.unpack_from("<H", header, 28)
        if (entries[0].filename != "mimetype" or method != 0 or extra_len
                or z.read("mimetype") != b"application/epub+zip"):
            errors.append("Invalid first/stored mimetype local header")
        docs = {}
        for name in sorted(names):
            if name.endswith((".xml", ".opf", ".ncx", ".xhtml", ".html")):
                try:
                    docs[name] = ET.fromstring(z.read(name))
                except ET.ParseError as e:
                    errors.append(f"XML {name}: {e}")
        container = docs.get("META-INF/container.xml")
        if container is None:
            errors.append("Missing/invalid container")
            return result
        opf_path = next(x.attrib["full-path"] for x in container.iter()
                        if x.tag.endswith("}rootfile"))
        opf = docs.get(opf_path)
        if opf is None:
            errors.append("Missing/invalid OPF")
            return result
        ns = {"o": "http://www.idpf.org/2007/opf"}
        items = opf.findall("o:manifest/o:item", ns)
        item_ids = [x.get("id") for x in items]
        if len(set(item_ids)) != len(item_ids):
            errors.append("Duplicate manifest IDs")
        result["version"] = opf.get("version")
        result["manifest"] = len(items)
        spine = opf.findall("o:spine/o:itemref", ns)
        result["spine"] = len(spine)
        if result["version"].startswith("2"):
            spine_element = opf.find("o:spine", ns)
            toc_id = spine_element.get("toc") if spine_element is not None else None
            if not any(x.get("id") == toc_id and
                       x.get("media-type") == "application/x-dtbncx+xml"
                       for x in items):
                errors.append("EPUB2 spine is missing its NCX reference")
        elif result["version"].startswith("3"):
            navs = [x for x in items if "nav" in x.get("properties", "").split()]
            if len(navs) != 1:
                errors.append("EPUB3 must have exactly one manifest nav item")
        for item in items:
            target = local_target(opf_path, item.get("href", ""))
            if target is not None and target not in names:
                errors.append(f"Missing manifest resource: {target}")
        for item in spine:
            if item.get("idref") not in item_ids:
                errors.append(f"Missing spine ID: {item.get('idref')}")
        ids = {name: {e.get("id") for e in doc.iter() if e.get("id")}
               for name, doc in docs.items()}
        for name, doc in docs.items():
            doc_ids = [e.get("id") for e in doc.iter() if e.get("id")]
            if len(doc_ids) != len(set(doc_ids)):
                errors.append(f"Duplicate XML IDs: {name}")
            for element in doc.iter():
                for attr in ("href", "src", "{http://www.w3.org/1999/xlink}href"):
                    ref = element.get(attr)
                    if ref is None:
                        continue
                    target = local_target(name, ref)
                    if target is None:
                        continue
                    if target not in names:
                        warnings.append(f"{name}: missing resource {ref}")
                    fragment = urllib.parse.unquote(
                        urllib.parse.urlsplit(ref).fragment)
                    if fragment and target in ids and fragment not in ids[target]:
                        warnings.append(f"{name}: missing anchor {ref}")
        for name in names:
            if not name.endswith(".css"):
                continue
            css = z.read(name).decode("utf-8")
            for ref in re.findall(r"url\(\s*['\"]?([^)'\"\s]+)", css):
                target = local_target(name, ref)
                if target is not None and target not in names:
                    warnings.append(f"{name}: missing CSS resource {ref}")
        result["body_text_chars"] = sum(
            len("".join(e.itertext()))
            for doc in docs.values()
            for e in doc.iter()
            if e.tag == "{http://www.w3.org/1999/xhtml}body"
        )
        if check_images:
            from PIL import Image
            result["images_decoded"] = 0
            for name in names:
                if not name.lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".gif")):
                    continue
                data = z.read(name)
                digest = hashlib.sha256(data).hexdigest()
                if digest not in _decoded_images:
                    try:
                        with Image.open(io.BytesIO(data)) as image:
                            image.load()
                        _decoded_images[digest] = None
                    except Exception as exc:
                        _decoded_images[digest] = str(exc)
                if _decoded_images[digest]:
                    errors.append(f"Image {name}: {_decoded_images[digest]}")
                else:
                    result["images_decoded"] += 1
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("outputs", type=Path)
    parser.add_argument("--images", action="store_true",
                        help="Decode raster images using Pillow.")
    args = parser.parse_args()
    paths = [args.input] + sorted(
        p for p in args.outputs.rglob("*.epub")
        if p.name not in {"src.epub", "a.epub", "b.epub", "encrypted.epub"}
        and "library" not in p.parts
    )
    results = []
    for path in paths:
        try:
            result = audit(path, check_images=args.images)
        except Exception as exc:
            result = {"path": str(path), "errors": [str(exc)],
                      "reference_warnings": []}
        results.append(result)
        print(f"{path.parent.name}/{path.name}: "
              f"errors={len(result['errors'])}, "
              f"reference_warnings={len(result['reference_warnings'])}",
              flush=True)
    destination = args.outputs / "STRUCTURE_AUDIT.json"
    destination.write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print(destination)
    if any(r["errors"] or r["reference_warnings"] for r in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
