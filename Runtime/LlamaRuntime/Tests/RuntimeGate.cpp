#include "GemmaLlamaRuntime.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>

namespace {

struct model_deleter {
    void operator()(gt_llama_model * model) const { gt_llama_model_free(model); }
};

struct generation_deleter {
    void operator()(gt_llama_generation * generation) const { gt_llama_generation_free(generation); }
};

using model_ptr = std::unique_ptr<gt_llama_model, model_deleter>;
using generation_ptr = std::unique_ptr<gt_llama_generation, generation_deleter>;

std::string translate(gt_llama_model * model, const std::string & prompt, gt_llama_metrics * metrics) {
    char error[512]{};
    gt_llama_sampling_config sampling{
        .max_tokens = 1024,
        .top_k = 20,
        .top_p = 0.6f,
        .temperature = 0.7f,
        .repetition_penalty = 1.05f,
        .seed = 42,
    };
    generation_ptr generation(gt_llama_generation_begin(model, prompt.c_str(), sampling, error, sizeof(error)));
    if (!generation) {
        std::fprintf(stderr, "generation setup failed: %s\n", error);
        std::exit(2);
    }

    std::string output;
    while (true) {
        uint8_t bytes[512]{};
        size_t length = 0;
        const gt_llama_step_result result = gt_llama_generation_step(
            generation.get(), bytes, sizeof(bytes), &length, error, sizeof(error));
        if (result == GT_LLAMA_STEP_ERROR) {
            std::fprintf(stderr, "generation failed: %s\n", error);
            std::exit(3);
        }
        if (result == GT_LLAMA_STEP_EOG) {
            break;
        }
        if (result == GT_LLAMA_STEP_TOKEN) {
            output.append(reinterpret_cast<const char *>(bytes), length);
        }
    }
    *metrics = gt_llama_generation_metrics(generation.get());
    return output;
}

void cancel_generation(gt_llama_model * model) {
    char error[512]{};
    gt_llama_sampling_config sampling{
        .max_tokens = 1024,
        .top_k = 20,
        .top_p = 0.6f,
        .temperature = 0.7f,
        .repetition_penalty = 1.05f,
        .seed = 42,
    };
    generation_ptr generation(gt_llama_generation_begin(
        model,
        "Translate the following text into English. Output only the translation.\n\n"
        "这是一次生成取消测试。",
        sampling,
        error,
        sizeof(error)));
    if (!generation) {
        std::fprintf(stderr, "cancel setup failed: %s\n", error);
        std::exit(5);
    }
    // 模拟 Swift Task 取消：decode 循环边界停止调用 step，立即释放 sampler/KV 临时对象。
    for (int step = 0; step < 2; ++step) {
        uint8_t bytes[512]{};
        size_t length = 0;
        const auto result = gt_llama_generation_step(
            generation.get(), bytes, sizeof(bytes), &length, error, sizeof(error));
        if (result == GT_LLAMA_STEP_ERROR) {
            std::fprintf(stderr, "cancel step failed: %s\n", error);
            std::exit(6);
        }
    }
}

void run_model(const char * path, gt_llama_quantization quantization, int repetitions) {
    char error[512]{};
    gt_llama_model_config config{
        .context_size = 4096,
        .batch_size = 512,
        .thread_count = 6,
        .quantization = quantization,
    };
    const auto load_start = std::chrono::steady_clock::now();
    model_ptr model(gt_llama_model_load(path, config, error, sizeof(error)));
    const double load_seconds = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - load_start).count();
    if (!model) {
        std::fprintf(stderr, "model load failed: %s\n", error);
        std::exit(1);
    }

    cancel_generation(model.get());

    for (int index = 0; index < repetitions; ++index) {
        const bool to_chinese = index % 2 == 0;
        const std::string prompt = to_chinese
            ? "Translate the following text into Simplified Chinese. Output only the translation.\n\n"
              "Hello, welcome to GemmaTrans. Your text stays private and is translated entirely on this Mac."
            : "Translate the following text into English. Output only the translation.\n\n"
              "你好，欢迎使用 GemmaTrans。你的文本不会离开这台 Mac。";
        gt_llama_metrics metrics{};
        const std::string output = translate(model.get(), prompt, &metrics);
        if (output.empty() || output.find("[end of text]") != std::string::npos ||
            output.find("<｜") != std::string::npos) {
            std::fprintf(stderr, "invalid output at iteration %d: %s\n", index + 1, output.c_str());
            std::exit(4);
        }
        std::printf(
            "iteration=%d load=%.3fs first=%.3fs speed=%.2ft/s tokens=%d output=%s\n",
            index + 1,
            load_seconds,
            metrics.first_token_seconds,
            metrics.tokens_per_second,
            metrics.generated_tokens,
            output.c_str());
    }
}

} // namespace

int main(int argc, char ** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "usage: RuntimeGate <1.25-bit-v2.gguf> <2-bit-v2.gguf>\n");
        return 64;
    }
    int repetitions = 20;
    if (const char * value = std::getenv("GT_GATE_REPETITIONS")) {
        repetitions = std::max(1, std::atoi(value));
    }
    gt_llama_backend_initialize();
    run_model(argv[1], GT_LLAMA_QUANTIZATION_STQ1_0, repetitions);
    run_model(argv[2], GT_LLAMA_QUANTIZATION_Q2_0C, repetitions);
    run_model(argv[1], GT_LLAMA_QUANTIZATION_STQ1_0, 2);
    return 0;
}
