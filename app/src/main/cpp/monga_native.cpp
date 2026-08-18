#include <jni.h>
#include <mutex>

#include "llama.h"

namespace {

    std::mutex g_modelMutex;
    llama_model* g_model = nullptr;
    std::once_flag g_backendInitFlag;

    void ensureBackendInitialized() {
        std::call_once(g_backendInitFlag, []() {
            llama_backend_init();
        });
    }

} // namespace

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

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeLoadModel(
        JNIEnv* env,
        jobject,
        jstring path
) {
    if (path == nullptr) {
        return JNI_FALSE;
    }

    const char* pathChars = env->GetStringUTFChars(path, nullptr);

    if (pathChars == nullptr) {
        return JNI_FALSE;
    }

    std::lock_guard<std::mutex> lock(g_modelMutex);

    ensureBackendInitialized();

    const llama_model_params params = llama_model_default_params();

    llama_model* newModel = llama_model_load_from_file(
            pathChars,
            params
    );

    env->ReleaseStringUTFChars(path, pathChars);

    if (newModel == nullptr) {
        return JNI_FALSE;
    }

    if (g_model != nullptr) {
        llama_model_free(g_model);
    }

    g_model = newModel;

    return JNI_TRUE;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeUnloadModel(
        JNIEnv*,
jobject
) {
std::lock_guard<std::mutex> lock(g_modelMutex);

if (g_model != nullptr) {
llama_model_free(g_model);
g_model = nullptr;
}
}
