class_name LevelNavigation
extends NavigationRegion3D
## A continuous NavigationMesh built from the same tile surfaces as collision.
## Boundary edges are inset by the agent radius; ramps share exact edge vertices.
var polygon_count: int = 0
var synchronized: bool = false

func build(tiles: Dictionary, world) -> void:
	synchronized = false
	var mesh = NavigationMesh.new()
	var navigation_map = get_world_3d().navigation_map
	mesh.cell_size = NavigationServer3D.map_get_cell_size(navigation_map)
	mesh.cell_height = NavigationServer3D.map_get_cell_height(navigation_map)
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.7
	var vertices = PackedVector3Array()
	var polygons: Array = []
	var indices: Dictionary = {}
	var divisions = [0.0, 0.8, 1.6, 2.4, 3.0, 3.6, 4.4, 5.2, 6.0]
	for key in tiles:
		if world.nav_blocked(key):
			continue
		var left: float = key.x * world.CELL - world.CELL / 2.0
		var front: float = key.z * world.CELL - world.CELL / 2.0
		# Fixed subdivisions make adjoining edges identical even at inset corners.
		var xs: Array = []
		var zs: Array = []
		for distance in divisions:
			xs.append(left + distance)
			zs.append(front + distance)
		for xi in range(8):
			for zi in range(8):
				if (xi == 0 and not world.connected(key, Vector2i(-1, 0))) or (xi == 7 and not world.connected(key, Vector2i(1, 0))):
					continue
				if (zi == 0 and not world.connected(key, Vector2i(0, -1))) or (zi == 7 and not world.connected(key, Vector2i(0, 1))):
					continue
				var bounds = AABB(Vector3(xs[xi], world.height_at(key, (zs[zi] + zs[zi + 1]) / 2.0) + 0.3, zs[zi]), Vector3(xs[xi + 1] - xs[xi], 1.1, zs[zi + 1] - zs[zi]))
				if not world.navigation_clear(bounds):
					continue
				var corners = [Vector3(xs[xi], world.height_at(key, zs[zi + 1]), zs[zi + 1]), Vector3(xs[xi + 1], world.height_at(key, zs[zi + 1]), zs[zi + 1]), Vector3(xs[xi + 1], world.height_at(key, zs[zi]), zs[zi]), Vector3(xs[xi], world.height_at(key, zs[zi]), zs[zi])]
				var polygon = PackedInt32Array()
				for corner in corners:
					var vertex_key = "%0.3f,%0.3f,%0.3f" % [corner.x, corner.y, corner.z]
					if not indices.has(vertex_key):
						indices[vertex_key] = vertices.size()
						vertices.append(corner)
					polygon.append(indices[vertex_key])
				polygons.append(polygon)
	mesh.vertices = vertices
	for polygon in polygons:
		mesh.add_polygon(polygon)
	navigation_mesh = mesh
	polygon_count = polygons.size()
	NavigationServer3D.map_set_edge_connection_margin(get_world_3d().navigation_map, 0.15)

func path_between(origin: Vector3, destination: Vector3) -> PackedVector3Array:
	var query = NavigationPathQueryParameters3D.new()
	query.map = get_world_3d().navigation_map
	query.start_position = origin
	query.target_position = destination
	query.path_search_max_polygons = polygon_count + 1
	query.metadata_flags = 0
	query.simplify_path = true
	query.simplify_epsilon = 0.05
	var result = NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return result.get_path()

func wait_ready() -> bool:
	# Map iterations build on a worker thread. Two frames need not be enough.
	if navigation_mesh == null or navigation_mesh.vertices.is_empty():
		return false
	var frames: int = 0
	var reference = navigation_mesh.vertices[0]
	var map = get_world_3d().navigation_map
	while frames < 600:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point_owner(map, reference) == get_rid():
			synchronized = true
			return true
		frames += 1
		await get_tree().physics_frame
	return false
