#include <jni.h>
#include <fstream>
#include <iterator>
#include <stdlib.h>
#include <string>
#include <vector>
#include "needle.h"

namespace {
bool ready = false;

std::string fromJava(JNIEnv* env, jstring value) {
    const char* chars = env->GetStringUTFChars(value, nullptr);
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

jstring toJava(JNIEnv* env, const std::string& value) {
    return env->NewStringUTF(value.c_str());
}
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_workout_1app_MainActivity_nativeInitialize(JNIEnv* env, jobject, jstring modelPath) {
    if (ready) return toJava(env, "ok");

    setenv("NEEDLE_TELEMETRY", "0", 1);
    setenv("DO_NOT_TRACK", "1", 1);

    std::ifstream model(fromJava(env, modelPath), std::ios::binary);
    if (!model) return toJava(env, "Unable to open the Needle3 model.");
    std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(model)), {});
    if (bytes.empty()) return toJava(env, "The Needle3 model is empty.");

    int loaded = needle_load(bytes.data(), bytes.size());
    if (loaded < 0) return toJava(env, needle_last_error());

    const char* system = "You are a workout planning assistant. Select exercises only from the candidate list. Prefer a balanced workout that uses the person's history, includes a few suitable new exercises when requested, and avoids unavailable equipment. Return the selected exercise names in a select_exercises tool call. Never invent exercises.";
    const char* tools = R"([{"type":"function","function":{"name":"select_exercises","description":"Select 4 to 8 suitable exercises from the candidates for this workout.","parameters":{"type":"object","properties":{"exercise_names":{"type":"array","items":{"type":"string"}}},"required":["exercise_names"]}}}])";
    int initialized = needle_init(system, tools, nullptr);
    if (initialized < 0) return toJava(env, needle_last_error());

    ready = true;
    return toJava(env, "ok");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_workout_1app_MainActivity_nativeComplete(JNIEnv* env, jobject, jstring input) {
    if (!ready) return toJava(env, "Needle3 has not been initialized.");
    std::vector<char> output(16384, '\0');
    int result = needle_complete(fromJava(env, input).c_str(), nullptr, 0, 160, output.data(), output.size());
    if (result < 0) return toJava(env, needle_last_error());
    output.back() = '\0';
    return toJava(env, output.data());
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_workout_1app_MainActivity_nativeReset(JNIEnv*, jobject) {
    if (ready) needle_reset();
}
