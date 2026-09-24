#!/bin/bash
# Builds the PiperTTS GDExtension without rebuilding godot-cpp (prebuilt static libs).
set -e
cd "$(dirname "$0")"
INC="-Igodot-cpp/gdextension -Igodot-cpp/include -Igodot-cpp/gen/include -Isrc -Isherpa-onnx/include"
mkdir -p obj bin
for t in template_debug template_release; do
  if [ $t = template_debug ]; then DBG="-O2 -DHOT_RELOAD_ENABLED -DDEBUG_ENABLED -DDEBUG_METHODS_ENABLED"; else DBG="-O3"; fi
  # linux
  for f in piper_tts register_types; do
    g++ -o obj/$f.linux.$t.o -c -std=c++17 -fno-exceptions -fPIC -m64 -march=x86-64 -fvisibility=hidden $DBG -DLINUX_ENABLED -DUNIX_ENABLED -DTHREADS_ENABLED -DNDEBUG -DGDEXTENSION $INC src/$f.cpp
  done
  g++ -o bin/libgodot_piper.linux.$t.x86_64.so -m64 -march=x86-64 -fvisibility=hidden -s -Wl,-rpath,'$ORIGIN' -shared obj/piper_tts.linux.$t.o obj/register_types.linux.$t.o godot-cpp/bin/libgodot-cpp.linux.$t.x86_64.a -Lsherpa-onnx/lib -lsherpa-onnx-c-api
  # windows (mingw, links the MSVC-built sherpa-onnx C API DLL directly)
  for f in piper_tts register_types; do
    x86_64-w64-mingw32-g++ -o obj/$f.windows.$t.o -c -std=c++17 -fno-exceptions -fvisibility=hidden $DBG -DWINDOWS_ENABLED -DTHREADS_ENABLED -DNDEBUG -DGDEXTENSION $INC src/$f.cpp
  done
  x86_64-w64-mingw32-g++ -o bin/godot_piper.windows.$t.x86_64.dll -Wl,--no-undefined -static -static-libgcc -static-libstdc++ -fvisibility=hidden -s -shared obj/piper_tts.windows.$t.o obj/register_types.windows.$t.o godot-cpp/bin/libgodot-cpp.windows.$t.x86_64.a sherpa-onnx/lib/win/sherpa-onnx-c-api.dll
done
ls -la bin
