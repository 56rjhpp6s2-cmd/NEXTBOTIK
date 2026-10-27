class_name FPSMovementMotor
extends RefCounted
## Accelerate along the desired direction without clamping existing air momentum.
static func accelerate(current: Vector3, wish: Vector3, wish_speed: float, acceleration: float, delta: float) -> Vector3:
	if wish.length_squared() < 0.0001:
		return current
	var direction = wish.normalized()
	var amount = minf(acceleration * delta, maxf(0.0, wish_speed - current.dot(direction)))
	return current + direction * amount

static func friction(current: Vector3, resistance: float, delta: float) -> Vector3:
	var speed = current.length()
	return current * (maxf(0.0, speed - resistance * delta) / speed) if speed > 0.001 else Vector3.ZERO

static func horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)
