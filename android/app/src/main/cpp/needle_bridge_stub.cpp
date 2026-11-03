#include <jni.h>

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_workout_1app_MainActivity_nativeInitialize(JNIEnv* env, jobject, jstring) {
    return env->NewStringUTF("Needle3 workout planning requires an ARM Android device.");
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_workout_1app_MainActivity_nativeComplete(JNIEnv* env, jobject, jstring) {
    return env->NewStringUTF("Needle3 workout planning requires an ARM Android device.");
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_workout_1app_MainActivity_nativeReset(JNIEnv*, jobject) {}
