extends Node
## Sound effects (autoload "Sfx"): weapons, impacts, explosions, the Halo Lance
## and interface clicks, all synthesised at runtime (no sample files) and played
## on the "Sfx" audio bus, so the Sound effects volume in Options controls them.
## World sounds are positional (the game camera is the listener).

const RATE := 22050
const POOL := 28
const VARIANTS := 3

## Minimum seconds between two plays of the same sound, and how many may overlap.
const LIMITS := {"gun": [0.05, 6], "mg": [0.06, 5], "cannon": [0.08, 4], "rocket": [0.08, 4], "laser": [0.06, 4],
	"sonic": [0.1, 3], "flame": [0.12, 3], "claw": [0.08, 3], "impact": [0.06, 5], "explode_small": [0.08, 5],
	"explode_big": [0.15, 3], "lance": [0.5, 2], "place": [0.1, 2], "sell": [0.1, 2]}

var _bank := {}        # name -> [AudioStreamWAV]
var _pool: Array = []
var _next := 0
var _ui: AudioStreamPlayer
var _last := {}        # name -> time last played
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7331
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Sfx"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 22.0
		p.max_distance = 120.0
		p.panning_strength = 0.6
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	_ui.bus = "Sfx"
	_ui.max_polyphony = 4
	add_child(_ui)


# ================================================================ public

## A sound somewhere in the world.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var lim: Array = LIMITS.get(sound, [0.05, 4])
	if now - float(_last.get(sound, -10.0)) < float(lim[0]):
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > 120.0:
		return
	var playing := 0
	for p in _pool:
		if p.playing and p.get_meta("sound", "") == sound:
			playing += 1
	if playing >= int(lim[1]):
		return
	_last[sound] = now
	var p: AudioStreamPlayer3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _variant(sound)
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.set_meta("sound", sound)
	p.play()


## Interface sound (not positional): click, confirm, error, place, sell.
func ui(sound: String, volume_db := -4.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get("ui_" + sound, -10.0)) < 0.04:
		return
	_last["ui_" + sound] = now
	_ui.stream = _variant(sound)
	_ui.volume_db = volume_db
	_ui.play()


## Weapon discharge, by projectile kind (see data/rules.json).
func weapon(kind: String, pos: Vector3, damage: float) -> void:
	match kind:
		"tracer":
			if damage >= 20.0:
				play_at("mg", pos, -3.0, 0.8)
			else:
				play_at("gun", pos, -6.0)
		"shell": play_at("cannon", pos, -2.0, 1.15 if damage < 60.0 else 0.9)
		"rocket": play_at("rocket", pos, -4.0)
		"laser": play_at("laser", pos, -5.0)
		"sonic": play_at("sonic", pos, -4.0)
		"flame": play_at("flame", pos, -4.0)
		_: play_at("claw", pos, -6.0)


func explosion(pos: Vector3, size: float) -> void:
	if size >= 1.3:
		play_at("explode_big", pos, 0.0, clampf(1.3 / size, 0.6, 1.1))
	elif size >= 0.8:
		play_at("explode_small", pos, -2.0)
	else:
		play_at("impact", pos, -4.0, 1.2)


# ================================================================ synthesis

func _variant(sound: String) -> AudioStreamWAV:
	if not _bank.has(sound):
		var list: Array = []
		for v in VARIANTS:
			list.append(_make(sound, v))
		_bank[sound] = list
	var l: Array = _bank[sound]
	return l[_rng.randi() % l.size()]


func _make(sound: String, variant: int) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = hash(sound) + variant * 977
	var s := PackedFloat32Array()
	match sound:
		"gun": s = _shot(r, 0.14, 0.02, 2600.0, 140.0, 0.5)
		"mg": s = _shot(r, 0.18, 0.03, 1800.0, 110.0, 0.7)
		"cannon":
			s = _boom(r, 0.7, 0.11, 900.0, 180.0, 75.0, 38.0, 0.9)
			_mix(s, _shot(r, 0.05, 0.008, 5000.0, 0.0, 0.0), 0.6)
		"rocket": s = _whoosh(r, 0.75)
		"laser": s = _sweep(r, 0.32, 2200.0 - variant * 200.0, 240.0, 0.09, true)
		"sonic": s = _warble(r, 0.55)
		"flame": s = _flame(r, 0.55)
		"claw": s = _shot(r, 0.12, 0.03, 1400.0, 0.0, 0.0)
		"impact": s = _boom(r, 0.45, 0.07, 1400.0, 250.0, 95.0, 50.0, 0.6)
		"explode_small":
			s = _boom(r, 1.0, 0.2, 1500.0, 160.0, 62.0, 34.0, 1.0)
			_crackle(r, s, 0.5, 40)
		"explode_big":
			s = _boom(r, 2.0, 0.5, 1100.0, 110.0, 50.0, 28.0, 1.2)
			_crackle(r, s, 1.2, 90)
		"lance":
			s = _boom(r, 2.6, 0.8, 1300.0, 90.0, 45.0, 24.0, 1.3)
			_mix(s, _sweep(r, 1.2, 3200.0, 90.0, 0.5, false), 0.7)
			_crackle(r, s, 1.8, 140)
		"place": s = _boom(r, 0.35, 0.06, 600.0, 200.0, 110.0, 60.0, 0.8)
		"click": s = _tone([1250.0], 0.05, 0.012)
		"confirm": s = _tone([660.0, 990.0], 0.16, 0.05)
		"error": s = _tone([196.0, 150.0], 0.24, 0.09, true)
		"sell": s = _tone([1480.0, 1975.0], 0.2, 0.06)
		_: s = _tone([440.0], 0.1, 0.03)
	return _to_wav(s)


func _to_wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _buf(secs: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(secs * RATE))
	return s


func _mix(into: PackedFloat32Array, other: PackedFloat32Array, gain: float) -> void:
	for i in mini(into.size(), other.size()):
		into[i] += other[i] * gain


## Gunshot: bright noise crack plus an optional low thump.
func _shot(r: RandomNumberGenerator, secs: float, tau: float, cutoff: float, thump_hz: float, thump: float) -> PackedFloat32Array:
	var s := _buf(secs)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var n := r.randf_range(-1.0, 1.0)
		lp += (n - lp) * a
		var v := lp * exp(-t / tau)
		if thump > 0.0:
			ph += TAU * thump_hz * (1.0 - 0.4 * t / secs) / RATE
			v += sin(ph) * thump * exp(-t / (tau * 1.6))
		s[i] = v
	return s


## Explosion: low-passed noise whose cutoff falls, over a pitched-down rumble.
func _boom(r: RandomNumberGenerator, secs: float, tau: float, cut0: float, cut1: float, hz0: float, hz1: float, rumble: float) -> PackedFloat32Array:
	var s := _buf(secs)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / secs
		var cutoff := lerpf(cut0, cut1, sqrt(k))
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		lp += (r.randf_range(-1.0, 1.0) - lp) * a
		lp2 += (lp - lp2) * a
		var env := minf(1.0, t / 0.004) * exp(-t / tau)
		ph += TAU * lerpf(hz0, hz1, k) / RATE
		s[i] = lp2 * 2.2 * env + sin(ph) * rumble * exp(-t / (tau * 1.3))
	return s


## Random short pops scattered through the tail of an explosion.
func _crackle(r: RandomNumberGenerator, s: PackedFloat32Array, secs: float, count: int) -> void:
	var n := mini(s.size(), int(secs * RATE))
	for c in count:
		var at := int(pow(r.randf(), 1.6) * n)
		var amp := r.randf_range(0.1, 0.35) * (1.0 - float(at) / n)
		for j in 90:
			if at + j < s.size():
				s[at + j] += r.randf_range(-1.0, 1.0) * amp * exp(-j / 18.0)


## Rocket launch: band-limited hiss that swells and fades.
func _whoosh(r: RandomNumberGenerator, secs: float) -> PackedFloat32Array:
	var s := _buf(secs)
	var lp := 0.0
	var hp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var cutoff := 2500.0 - 1600.0 * t / secs
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		lp += (r.randf_range(-1.0, 1.0) - lp) * a
		hp += (lp - hp) * 0.02
		var env := minf(1.0, t / 0.03) * exp(-t / (secs * 0.35))
		s[i] = (lp - hp) * env
	_mix(s, _shot(r, 0.08, 0.015, 3000.0, 90.0, 0.6), 0.8)
	return s


## Energy weapon: an exponential pitch sweep with a few harmonics.
func _sweep(_r: RandomNumberGenerator, secs: float, f0: float, f1: float, tau: float, buzzy: bool) -> PackedFloat32Array:
	var s := _buf(secs)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := f0 * pow(f1 / f0, t / secs)
		ph += TAU * f / RATE
		var v := sin(ph)
		if buzzy:
			v += 0.35 * sin(ph * 2.0) + 0.2 * sin(ph * 3.0)
		s[i] = v * minf(1.0, t / 0.003) * exp(-t / tau)
	return s


## Sonic / resonance weapon: a throbbing low tone.
func _warble(_r: RandomNumberGenerator, secs: float) -> PackedFloat32Array:
	var s := _buf(secs)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (180.0 + 40.0 * sin(TAU * 9.0 * t)) / RATE
		var am := 0.6 + 0.4 * sin(TAU * 32.0 * t)
		s[i] = (sin(ph) + 0.5 * sin(ph * 1.5)) * am * minf(1.0, t / 0.02) * exp(-t / 0.22)
	return s


## Flamethrower: a roaring low-passed noise burst.
func _flame(r: RandomNumberGenerator, secs: float) -> PackedFloat32Array:
	var s := _buf(secs)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += (r.randf_range(-1.0, 1.0) - lp) * 0.12
		var flutter := 0.7 + 0.3 * sin(TAU * 23.0 * t + r.randf() * 0.3)
		s[i] = lp * flutter * minf(1.0, t / 0.06) * exp(-t / 0.25)
	return s


## Interface tones: a short sequence of soft sine (or square) blips.
func _tone(freqs: Array, secs: float, tau: float, square := false) -> PackedFloat32Array:
	var s := _buf(secs)
	var seg := s.size() / freqs.size()
	for i in s.size():
		var k := mini(i / seg, freqs.size() - 1)
		var t := float(i - k * seg) / RATE
		var v := sin(TAU * float(freqs[k]) * t)
		if square:
			v = signf(v) * 0.5
		s[i] = v * minf(1.0, t / 0.002) * exp(-t / tau)
	return s
