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

    const char* system = "You are HybridLog's on-device workout assistant. For workout planning, select exercises only from the supplied candidates and use select_exercises. For app data, only act when the user's current request explicitly asks for a data operation. Propose exactly one action with manage_data; never claim it was completed. Use only supplied record IDs for existing records. Do not invent or infer IDs. For create, return a complete record matching the supplied record shape. For update, return only fields explicitly requested and preserve unspecified fields. Reads must stay within the supplied local snapshot. Never propose a delete unless the user explicitly requested deletion.";
    const char* tools = R"([{"type":"function","function":{"name":"select_exercises","description":"Select 4 to 8 suitable exercises from the candidates for this workout.","parameters":{"type":"object","properties":{"exercise_names":{"type":"array","items":{"type":"string"}}},"required":["exercise_names"]}}},{"type":"function","function":{"name":"manage_data","description":"Propose one local HybridLog data operation in response to the user's explicit request. Mutations are only proposals and require user approval in the app.","parameters":{"type":"object","properties":{"operation":{"type":"string","enum":["create","read","update","delete"]},"record_type":{"type":"string","enum":["exercise","folder","workout","run"]},"record_id":{"type":"integer"},"record":{"type":"object"},"summary":{"type":"string"}},"required":["operation","record_type","summary"]}}}])";
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
