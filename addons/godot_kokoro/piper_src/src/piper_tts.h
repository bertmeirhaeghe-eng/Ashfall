// PiperTTS: synchronous VITS / Piper text-to-speech through the sherpa-onnx C API.
// Written for Ashfall (MIT). Call generate() from a worker thread.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

struct SherpaOnnxOfflineTts;

namespace godot {

class PiperTTS : public RefCounted {
	GDCLASS(PiperTTS, RefCounted)

	const SherpaOnnxOfflineTts *tts = nullptr;
	int sample_rate = 22050;
	int speakers = 0;

protected:
	static void _bind_methods();

public:
	~PiperTTS();
	bool load_model(const String &model, const String &tokens, const String &data_dir, int num_threads);
	bool is_loaded() const;
	int get_sample_rate() const;
	int get_speaker_count() const;
	PackedByteArray generate(const String &text, float speed, int speaker_id);
	void unload();
};

} // namespace godot
