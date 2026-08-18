#include <jni.h>
#include "llama.h"

extern "C"
JNIEXPORT jstring JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativePing(
        JNIEnv* env,
        jobject
) {
    return env->NewStringUTF("monga-native-ok");
}

extern "C"
JNIEXPORT jlong JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeLlamaTimeUs(
        JNIEnv*,
        jobject
) {
    return static_cast<jlong>(llama_time_us());
}
