#include "piper_tts.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <sherpa-onnx/c-api/c-api.h>

#include <cstring>

using namespace godot;

void PiperTTS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_model", "model", "tokens", "data_dir", "num_threads"), &PiperTTS::load_model, DEFVAL(2));
	ClassDB::bind_method(D_METHOD("is_loaded"), &PiperTTS::is_loaded);
	ClassDB::bind_method(D_METHOD("get_sample_rate"), &PiperTTS::get_sample_rate);
	ClassDB::bind_method(D_METHOD("get_speaker_count"), &PiperTTS::get_speaker_count);
	ClassDB::bind_method(D_METHOD("generate", "text", "speed", "speaker_id"), &PiperTTS::generate, DEFVAL(1.0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("unload"), &PiperTTS::unload);
}

PiperTTS::~PiperTTS() {
	unload();
}

void PiperTTS::unload() {
	if (tts) {
		SherpaOnnxDestroyOfflineTts(tts);
		tts = nullptr;
	}
}

bool PiperTTS::load_model(const String &model, const String &tokens, const String &data_dir, int num_threads) {
	unload();
	CharString m = model.utf8();
	CharString t = tokens.utf8();
	CharString d = data_dir.utf8();
	// The config lives in a large zeroed buffer: the sherpa-onnx library shipped
	// next to this one may be a slightly different version with a longer struct,
	// and every field it reads that we do not set must be zero (= its default).
	alignas(16) static thread_local unsigned char buf[16384];
	std::memset(buf, 0, sizeof(buf));
	SherpaOnnxOfflineTtsConfig *config = reinterpret_cast<SherpaOnnxOfflineTtsConfig *>(buf);
	config->model.vits.model = m.get_data();
	config->model.vits.tokens = t.get_data();
	config->model.vits.data_dir = d.get_data();
	config->model.vits.noise_scale = 0.667f;
	config->model.vits.noise_scale_w = 0.8f;
	config->model.vits.length_scale = 1.0f;
	config->model.num_threads = num_threads > 0 ? num_threads : 2;
	config->model.provider = "cpu";
	config->max_num_sentences = 1;
	tts = SherpaOnnxCreateOfflineTts(config);
	if (!tts) {
		UtilityFunctions::push_warning("PiperTTS: could not load ", model);
		return false;
	}
	sample_rate = SherpaOnnxOfflineTtsSampleRate(tts);
	speakers = SherpaOnnxOfflineTtsNumSpeakers(tts);
	return true;
}

bool PiperTTS::is_loaded() const {
	return tts != nullptr;
}

int PiperTTS::get_sample_rate() const {
	return sample_rate;
}

int PiperTTS::get_speaker_count() const {
	return speakers;
}

PackedByteArray PiperTTS::generate(const String &text, float speed, int speaker_id) {
	PackedByteArray out;
	if (!tts) {
		return out;
	}
	CharString s = text.utf8();
	const SherpaOnnxGeneratedAudio *audio = SherpaOnnxOfflineTtsGenerate(tts, s.get_data(), speaker_id, speed > 0.1f ? speed : 1.0f);
	if (!audio) {
		return out;
	}
	if (audio->sample_rate > 0) {
		sample_rate = audio->sample_rate;
	}
	out.resize(int64_t(audio->n) * 2);
	uint8_t *w = out.ptrw();
	for (int32_t i = 0; i < audio->n; i++) {
		float f = audio->samples[i];
		f = f > 1.0f ? 1.0f : (f < -1.0f ? -1.0f : f);
		int16_t v = int16_t(f * 32767.0f);
		w[i * 2] = uint8_t(v & 0xff);
		w[i * 2 + 1] = uint8_t((v >> 8) & 0xff);
	}
	SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
	return out;
}
