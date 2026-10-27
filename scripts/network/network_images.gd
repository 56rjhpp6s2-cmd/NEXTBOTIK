extends RefCounted
## Small, alpha-preserving images for LAN transport. Local originals stay untouched.
const MAX_SIDE: int = 256
const MAX_BYTES: int = 350000
const MAX_IMAGES: int = 128
var textures: Dictionary = {}
var buffers: Dictionary = {}
var sources: Dictionary = {}

func encode(texture: Texture2D) -> Dictionary:
	var source_key = texture.get_instance_id()
	if sources.has(source_key):
		var key = sources[source_key]
		return {"key": key, "bytes": buffers[key]}
	var image = texture.get_image().duplicate()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var side = maxi(image.get_width(), image.get_height())
	if side > MAX_SIDE:
		var factor = float(MAX_SIDE) / side
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	var bytes = image.save_png_to_buffer()
	var key = digest(bytes)
	if accept(key, bytes):
		sources[source_key] = key
		return {"key": key, "bytes": bytes}
	return {}

func accept(key: String, bytes: PackedByteArray) -> bool:
	if textures.has(key):
		return true
	if textures.size() >= MAX_IMAGES or bytes.size() < 33 or bytes.size() > MAX_BYTES:
		return false
	if bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or key.length() != 64 or digest(bytes) != key:
		return false
	var width = (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | int(bytes[19])
	var height = (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | int(bytes[23])
	if width < 1 or height < 1 or width > MAX_SIDE or height > MAX_SIDE:
		return false
	var image = Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return false
	image.generate_mipmaps()
	textures[key] = ImageTexture.create_from_image(image)
	buffers[key] = bytes
	return true

func digest(bytes: PackedByteArray) -> String:
	var hash = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
