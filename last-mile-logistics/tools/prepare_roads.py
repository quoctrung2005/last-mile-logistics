"""Download a reproducible OSM snapshot (or package a supplied OSM XML file).

No generated/synthetic road network. The API runs Dijkstra locally on this XML.
"""
import argparse
import gzip
import hashlib
import json
import pathlib
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--input", type=pathlib.Path)
parser.add_argument("--download", action="store_true")
parser.add_argument("--bbox", default="10.70,106.56,10.85,106.75", help="south,west,north,east")
parser.add_argument("--endpoint", default="https://overpass-api.de/api/interpreter")
parser.add_argument("--output", type=pathlib.Path, default=ROOT / "backend/LastMile/LastMile.Api/Data/roads.osm.gz")
args = parser.parse_args()
if bool(args.input) == args.download:
    parser.error("Choose exactly one: --input file.osm or --download")
bounds = [float(n) for n in args.bbox.split(",")]
if len(bounds) != 4 or not (-90 <= bounds[0] < bounds[2] <= 90 and -180 <= bounds[1] < bounds[3] <= 180):
    parser.error("Invalid bbox")
query = f'''[out:xml][timeout:90];way["highway"~"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|residential|unclassified|living_street|service)$"]({args.bbox})->.roads;(.roads;rel(bw.roads)["type"="restriction"];);(._;>;);out body;'''
if args.download:
    req = urllib.request.Request(args.endpoint, data=urllib.parse.urlencode({"data": query}).encode(), headers={"User-Agent": "TVDLogistics-RoadSnapshot/1.0 (local research application)"})
    with urllib.request.urlopen(req, timeout=120) as response:
        data = response.read(100_000_001)
else:
    data = args.input.read_bytes()
if len(data) > 100_000_000:
    raise ValueError("OSM XML exceeds 100MB")
root = ET.fromstring(data)
if root.tag != "osm" or root.find("remark") is not None or root.find("way") is None:
    raise ValueError("Incomplete OSM response, no usable ways, or server returned an error")
args.output.parent.mkdir(parents=True, exist_ok=True)
# Fixed mtime makes the compressed artifact identical for the same XML.
compressed = gzip.compress(data, compresslevel=9, mtime=0)
args.output.write_bytes(compressed)
metadata = {"source": args.endpoint if args.download else str(args.input), "query": query if args.download else None,
            "osmTimestamp": root.find("meta").get("osm_base") if root.find("meta") is not None else None,
            "bbox": bounds, "xmlSha256": hashlib.sha256(data).hexdigest(), "gzipSha256": hashlib.sha256(compressed).hexdigest(),
            "nodes": len(root.findall("node")), "ways": len(root.findall("way")), "relations": len(root.findall("relation")),
            "attribution": "© OpenStreetMap contributors", "license": "https://www.openstreetmap.org/copyright"}
args.output.with_suffix(".metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(metadata, ensure_ascii=False))
