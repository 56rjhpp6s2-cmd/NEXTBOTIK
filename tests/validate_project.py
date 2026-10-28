"""Dependency-free integrity and level-design checks; does not replace Godot tests."""
from __future__ import annotations

import ast
import hashlib
from collections import deque
from pathlib import Path
import re
import textwrap
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
WORLD = (ROOT / "scripts/world.gd").read_text(encoding="utf-8")


def layout(source=WORLD):
    """Execute only the authored layout DSL, after restricting its AST."""
    body = source.split("func _layout() -> void:\n", 1)[1].split("\nfunc ", 1)[0]
    body = textwrap.dedent(body).replace("_rect(", "rect(")
    body = body.replace("Vector3i(", "cell(").replace("true", "True")
    body = re.sub(r"tiles\.erase\((cell\([^\n]+?\))\)", r"tiles.pop(\1, None)", body)
    tree = ast.parse(body)
    allowed_calls = {"rect", "cell", "range"}
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                assert node.func.id in allowed_calls, node.func.id
            else:
                assert isinstance(node.func, ast.Attribute) and node.func.attr == "pop"
        assert not isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.While))
    tiles = {}

    def rect(x0, x1, z0, z1, floor, zone):
        for x in range(x0, x1 + 1):
            for z in range(z0, z1 + 1):
                tiles[x, floor, z] = {"zone": zone}

    namespace = {"rect": rect, "cell": lambda x, y, z: (x, y, z), "tiles": tiles, "range": range}
    exec(compile(tree, "world layout", "exec"), {"__builtins__": {}}, namespace)
    return tiles


def height(tiles, key, edge_z):
    if tiles[key].get("ramp"):
        return max(0.0, min(6.0, (13.5 * 6 - edge_z) * 0.25))
    return key[1] * 6.0


def neighbors(tiles, key):
    x, floor, z = key
    for dx, dz in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        edge_z = z * 6 + dz * 3
        for other_floor in [0, 1]:
            other = x + dx, other_floor, z + dz
            if other not in tiles:
                continue
            if dx and (tiles[key].get("ramp") or tiles[other].get("ramp")):
                continue
            if abs(height(tiles, key, edge_z) - height(tiles, other, edge_z)) < 0.1:
                yield other


def reachable(tiles, start, excluded=()):
    seen = {start}
    queue = deque([start])
    while queue:
        for other in neighbors(tiles, queue.popleft()):
            if other not in seen and other not in excluded:
                seen.add(other)
                queue.append(other)
    return seen


def syntax_shape(source):
    """Check this project's Python-like GDScript subset using Python's parser.

    Godot type checking, API resolution and execution still require the engine.
    This catches malformed expressions, unbalanced delimiters and bad indentation.
    """
    output = []
    matches = []
    for line in source.splitlines():
        indent = len(line) - len(line.lstrip("\t"))
        stripped = line.lstrip("\t")
        if not stripped or stripped.startswith("#"):
            output.append(line)
            continue
        while matches and indent <= matches[-1]:
            matches.pop()
        if matches and indent == matches[-1] + 1:
            stripped = "case " + stripped
        if stripped.startswith("match "):
            matches.append(indent)
        if stripped.startswith("@"):
            if ") var " in stripped:
                stripped = stripped.split(") ", 1)[1]
            else:
                stripped = "pass  # " + stripped
        stripped = re.sub(r"^@export\s+", "", stripped)
        stripped = re.sub(r"^(?:static )?func ", "def ", stripped)
        stripped = re.sub(r"^(?:static )?(?:var|const) ", "", stripped)
        stripped = re.sub(r"func\(([^)]*)\): return (.+)\)$", r"lambda \1: \2)", stripped)
        stripped = stripped.replace(":=", "=")
        if stripped.startswith(("extends ", "class_name ", "signal ")):
            stripped = "pass  # " + stripped
        if stripped.startswith("enum "):
            stripped = stripped.split()[1] + " = None"
        stripped = re.sub(r"\btrue\b", "True", stripped)
        stripped = re.sub(r"\bfalse\b", "False", stripped)
        stripped = re.sub(r"\bnull\b", "None", stripped)
        stripped = re.sub(r"\s+as\s+[A-Za-z_][A-Za-z0-9_]*", "", stripped)
        output.append("\t" * indent + stripped)
    ast.parse("\n".join(output))


class ProjectChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tiles = layout()

    def test_resource_references_exist(self):
        count = 0
        for path in ROOT.rglob("*"):
            if path.suffix not in {".gd", ".tscn", ".godot"}:
                continue
            source = path.read_text(encoding="utf-8")
            for reference in re.findall(r'["\'](res://[^"\']+)["\']', source):
                if reference.endswith(("nextbot_face.", "tests/captures")):
                    continue  # Optional user image prefix and generated capture directory.
                self.assertTrue((ROOT / reference[6:]).exists(), (path.name, reference))
                count += 1
        self.assertGreater(count, 5)

    def test_gdscript_structure(self):
        for path in [*ROOT.glob("scripts/**/*.gd"), *ROOT.glob("tests/*.gd")]:
            with self.subTest(script=path.name):
                syntax_shape(path.read_text(encoding="utf-8"))

    def test_original_svg_assets_are_valid(self):
        for path in ROOT.glob("assets/**/*.svg"):
            self.assertEqual(ET.parse(path).getroot().tag, "{http://www.w3.org/2000/svg}svg")

    def test_bundled_projectiles_are_actual_transparent_pngs(self):
        paths = [ROOT / "assets/projectiles" / (name + ".png") for name in ("anomaly", "warning", "star")]
        for path in paths:
            data = path.read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(data[12:16], b"IHDR")
            self.assertEqual(data[25], 6, "Bundled PNG must be RGBA")
            self.assertEqual(int.from_bytes(data[16:20], "big"), 256)
            self.assertEqual(int.from_bytes(data[20:24], "big"), 256)

    def test_current_user_png_is_bundled_without_changes(self):
        data = (ROOT / "assets/projectiles/Без имени.png").read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), "38811007ae70b305730a38133e2272e09d0e164545e58891812f459ca329fe6d")

    def test_added_nextbot_photo_is_preserved(self):
        data = (ROOT / "assets/nextbot_faces/elena_finkelshteyn.jpg").read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), "05d1f97ab2741a06b081e028e8de083f00949753f979ab0802ef82a92d1fc3f6")

    def test_latest_nextbot_photo_is_preserved(self):
        data = (ROOT / "assets/nextbot_faces/5402324111498878359.jpg").read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), "528395702258bc3c963bc48e5ffa4ebbb82e33f67359b51f7c01f6aafc3a9ba8")

    def test_no_machine_specific_paths(self):
        paths = [*ROOT.glob("scripts/**/*.gd"), *ROOT.glob("tools/*.ps1"), *ROOT.glob("*.cmd")]
        for path in paths:
            with self.subTest(file=path.name):
                self.assertIsNone(re.search(r"(?<![A-Za-z])[A-Za-z]:[\\/]|/(?:Users|home)/|popik", path.read_text(encoding="utf-8"), re.I))

    def test_full_map_is_connected(self):
        self.assertGreater(len(self.tiles), 200)
        seen = reachable(self.tiles, (9, 0, 9))
        self.assertEqual(set(self.tiles), seen, f"Disconnected tiles: {set(self.tiles) - seen}")

    def test_ai_has_routes_without_crouch_tunnel(self):
        excluded = {(5, 0, 14), (5, 0, 15)}
        seen = reachable(self.tiles, (9, 0, 9), excluded)
        self.assertEqual(set(self.tiles) - excluded, seen)

    def test_two_staircases_are_continuous(self):
        for x in [3, 15]:
            for z in range(10, 14):
                key = x, 0, z
                north = (x, 1, 9) if z == 10 else (x, 0, z - 1)
                south = x, 0, z + 1
                self.assertIn(north, list(neighbors(self.tiles, key)))
                self.assertIn(south, list(neighbors(self.tiles, key)))
                self.assertLessEqual(abs(height(self.tiles, key, z * 6 - 3) - height(self.tiles, key, z * 6 + 3)), 1.5)
                self.assertTrue(all(other[0] == x for other in neighbors(self.tiles, key)))

    def test_spawn_and_interaction_locations_are_reachable(self):
        cells = re.findall(r"Vector3i\((\d+), (\d+), (\d+)\)", WORLD)
        seen = reachable(self.tiles, (9, 0, 9))
        for cell in cells:
            key = tuple(map(int, cell))
            self.assertIn(key, seen, f"Unreachable authored marker: {key}")

    def test_sufficient_loops_and_environment_variety(self):
        edges = sum(len(list(neighbors(self.tiles, k))) for k in self.tiles) // 2
        loops = edges - len(self.tiles) + 1
        self.assertGreater(loops, 50)
        zones = {tile["zone"] for tile in self.tiles.values()}
        self.assertGreaterEqual(len(zones), 12)

    def test_navigation_divisions_have_exact_shared_boundaries(self):
        source = (ROOT / "scripts/navigation.gd").read_text(encoding="utf-8")
        divisions = ast.literal_eval(re.search(r"var divisions = (\[[^\n]+\])", source).group(1))
        self.assertEqual(divisions[0], 0)
        self.assertEqual(divisions[-1], 6)
        self.assertEqual(sorted(set(divisions)), divisions)
        self.assertGreaterEqual(divisions[1], 0.42 + 0.15)
        self.assertGreaterEqual(6 - divisions[-2], 0.42 + 0.15)

    def test_construct_layout_and_markers_are_connected(self):
        source = (ROOT / "scripts/construct_world.gd").read_text(encoding="utf-8")
        tiles = layout(source)
        seen = reachable(tiles, (9, 0, 12))
        self.assertGreater(len(tiles), 450)
        self.assertEqual(set(tiles), seen)
        for cell in re.findall(r"Vector3i\((\d+), (\d+), (\d+)\)", source):
            self.assertIn(tuple(map(int, cell)), seen)

    def test_construct_has_two_independent_roof_routes(self):
        tiles = layout((ROOT / "scripts/construct_world.gd").read_text(encoding="utf-8"))
        for x in [3, 15]:
            blocked_ramp = {(x, 0, z) for z in range(10, 14)}
            seen = reachable(tiles, (9, 0, 12), blocked_ramp)
            self.assertIn((18, 1, 2), seen)
            self.assertIn((10, 0, 21), seen)


if __name__ == "__main__":
    unittest.main(verbosity=2)
