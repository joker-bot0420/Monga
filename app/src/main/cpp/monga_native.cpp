#include <atomic>
#include <jni.h>
#include <mutex>
#include <string>
#include <vector>

#include "llama.h"

namespace {

std::mutex g_modelMutex;
llama_model *g_model = nullptr;
std::once_flag g_backendInitFlag;

llama_context *g_context = nullptr;
llama_sampler *g_sampler = nullptr;

std::atomic<bool> g_cancelRequested{false};

int g_generatedTokens = 0;
int g_maxTokens = 0;

void ensureBackendInitialized() {
  std::call_once(g_backendInitFlag, []() { llama_backend_init(); });
}

void clearGenerationLocked() {
  g_cancelRequested.store(false);

  if (g_sampler != nullptr) {
    llama_sampler_free(g_sampler);
    g_sampler = nullptr;
  }

  if (g_context != nullptr) {
    llama_free(g_context);
    g_context = nullptr;
  }

  g_generatedTokens = 0;
  g_maxTokens = 0;
}

void throwIllegalState(JNIEnv *env, const char *message) {
  jclass exceptionClass = env->FindClass("java/lang/IllegalStateException");

  if (exceptionClass != nullptr) {
    env->ThrowNew(exceptionClass, message);
  }
}

} // namespace

extern "C" JNIEXPORT jstring

    JNICALL
    Java_com_monga_app_inference_LlamaNativeBridge_nativePing(JNIEnv *env,
                                                              jobject) {
  return env->NewStringUTF("monga-native-ok");
}

extern "C" JNIEXPORT jlong

    JNICALL
    Java_com_monga_app_inference_LlamaNativeBridge_nativeLlamaTimeUs(JNIEnv *,
                                                                     jobject) {
  return static_cast<jlong>(llama_time_us());
}

extern "C" JNIEXPORT jboolean

    JNICALL
    Java_com_monga_app_inference_LlamaNativeBridge_nativeLoadModel(
        JNIEnv *env, jobject, jstring path) {
  if (path == nullptr) {
    return JNI_FALSE;
  }

  const char *pathChars = env->GetStringUTFChars(path, nullptr);

  if (pathChars == nullptr) {
    return JNI_FALSE;
  }

  std::lock_guard<std::mutex> lock(g_modelMutex);

  ensureBackendInitialized();

  const llama_model_params params = llama_model_default_params();

  llama_model *newModel = llama_model_load_from_file(pathChars, params);

  env->ReleaseStringUTFChars(path, pathChars);

  if (newModel == nullptr) {
    return JNI_FALSE;
  }

  clearGenerationLocked();

  if (g_model != nullptr) {
    llama_model_free(g_model);
  }

  g_model = newModel;

  return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeUnloadModel(JNIEnv *,
                                                                 jobject) {
  std::lock_guard<std::mutex> lock(g_modelMutex);

  clearGenerationLocked();

  if (g_model != nullptr) {
    llama_model_free(g_model);
    g_model = nullptr;
  }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeStartGeneration(
    JNIEnv *env, jobject, jstring prompt, jint maxTokens) {
  if (prompt == nullptr || maxTokens <= 0) {
    return JNI_FALSE;
  }

  const char *promptChars = env->GetStringUTFChars(prompt, nullptr);

  if (promptChars == nullptr) {
    return JNI_FALSE;
  }

  std::string promptText(promptChars);
  env->ReleaseStringUTFChars(prompt, promptChars);

  std::lock_guard<std::mutex> lock(g_modelMutex);

  if (g_model == nullptr) {
    return JNI_FALSE;
  }

  clearGenerationLocked();

  std::string formattedPrompt = promptText;

  const char *chatTemplate =
      llama_model_chat_template(g_model, /* name */ nullptr);

  if (chatTemplate != nullptr) {
    const llama_chat_message message{
        "user",
        promptText.c_str(),
    };

    std::vector<char> formatted(promptText.size() * 2 + 256);

    int32_t formattedLength = llama_chat_apply_template(
        chatTemplate, &message, 1, true, formatted.data(),
        static_cast<int32_t>(formatted.size()));

    if (formattedLength > static_cast<int32_t>(formatted.size())) {
      formatted.resize(formattedLength);

      formattedLength = llama_chat_apply_template(
          chatTemplate, &message, 1, true, formatted.data(),
          static_cast<int32_t>(formatted.size()));
    }

    if (formattedLength < 0) {
      throwIllegalState(env, "chat template apply failed");
      return false;
    }

    formattedPrompt.assign(formatted.data(),
                           static_cast<size_t>(formattedLength));
  }

  const llama_vocab *vocab = llama_model_get_vocab(g_model);

  const int tokenCount =
      -llama_tokenize(vocab, formattedPrompt.c_str(), formattedPrompt.size(),
                      nullptr, 0, true, true);

  if (tokenCount <= 0) {
    return JNI_FALSE;
  }

  std::vector<llama_token> promptTokens(tokenCount);

  const int tokenized =
      llama_tokenize(vocab, formattedPrompt.c_str(), formattedPrompt.size(),
                     promptTokens.data(), promptTokens.size(), true, true);

  if (tokenized < 0) {
    return JNI_FALSE;
  }

  llama_context_params contextParams = llama_context_default_params();
  contextParams.n_ctx = tokenCount + maxTokens;
  contextParams.n_batch = tokenCount;
  contextParams.no_perf = false;

  g_context = llama_init_from_model(g_model, contextParams);

  if (g_context == nullptr) {
    clearGenerationLocked();
    return JNI_FALSE;
  }

  auto samplerParams = llama_sampler_chain_default_params();
  samplerParams.no_perf = false;

  g_sampler = llama_sampler_chain_init(samplerParams);

  if (g_sampler == nullptr) {
    clearGenerationLocked();
    return JNI_FALSE;
  }

  llama_sampler_chain_add(g_sampler, llama_sampler_init_greedy());

  llama_batch batch = llama_batch_get_one(promptTokens.data(), tokenized);

  if (llama_decode(g_context, batch) != 0) {
    clearGenerationLocked();
    return JNI_FALSE;
  }

  g_generatedTokens = 0;
  g_maxTokens = maxTokens;
  g_cancelRequested.store(false);

  return JNI_TRUE;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeNextToken(JNIEnv *env,
                                                               jobject) {
  std::lock_guard<std::mutex> lock(g_modelMutex);

  if (g_model == nullptr || g_context == nullptr || g_sampler == nullptr) {
    throwIllegalState(env, "Generation has not been started.");
    return nullptr;
  }

  if (g_cancelRequested.load()) {
    return nullptr;
  }

  if (g_generatedTokens >= g_maxTokens) {
    return nullptr;
  }

  const llama_vocab *vocab = llama_model_get_vocab(g_model);

  const llama_token newToken = llama_sampler_sample(g_sampler, g_context, -1);

  if (newToken == LLAMA_TOKEN_NULL) {
    throwIllegalState(env, "Failed to sample the next token.");
    return nullptr;
  }

  if (llama_vocab_is_eog(vocab, newToken)) {
    return nullptr;
  }

  std::vector<char> pieceBuffer(128);

  int pieceLength =
      llama_token_to_piece(vocab, newToken, pieceBuffer.data(),
                           static_cast<int32_t>(pieceBuffer.size()), 0, true);

  if (pieceLength < 0) {
    pieceBuffer.resize(static_cast<size_t>(-pieceLength));

    pieceLength =
        llama_token_to_piece(vocab, newToken, pieceBuffer.data(),
                             static_cast<int32_t>(pieceBuffer.size()), 0, true);
  }

  if (pieceLength < 0) {
    clearGenerationLocked();

    throwIllegalState(env, "Failed to convert token to bytes.");

    return nullptr;
  }

  g_generatedTokens++;

  if (g_generatedTokens < g_maxTokens) {
    llama_token tokenToDecode = newToken;

    llama_batch batch = llama_batch_get_one(&tokenToDecode, 1);

    if (llama_decode(g_context, batch) != 0) {
      clearGenerationLocked();

      throwIllegalState(env, "Failed to decode generated token.");

      return nullptr;
    }
  }

  jbyteArray result = env->NewByteArray(static_cast<jsize>(pieceLength));

  if (result == nullptr) {
    clearGenerationLocked();
    return nullptr;
  }

  if (pieceLength > 0) {
    env->SetByteArrayRegion(
        result, 0, static_cast<jsize>(pieceLength),
        reinterpret_cast<const jbyte *>(pieceBuffer.data()));
  }

  return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeCancelGeneration(JNIEnv *,
                                                                      jobject) {
  g_cancelRequested.store(true);
}

extern "C" JNIEXPORT void JNICALL
Java_com_monga_app_inference_LlamaNativeBridge_nativeFinishGeneration(JNIEnv *,
                                                                      jobject) {
  std::lock_guard<std::mutex> lock(g_modelMutex);
  clearGenerationLocked();
}
