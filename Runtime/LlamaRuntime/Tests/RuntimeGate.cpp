#include "GemmaLlamaRuntime.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <mach/mach.h>

namespace {

struct model_deleter {
    void operator()(gt_llama_model * model) const { gt_llama_model_free(model); }
};

struct generation_deleter {
    void operator()(gt_llama_generation * generation) const { gt_llama_generation_free(generation); }
};

using model_ptr = std::unique_ptr<gt_llama_model, model_deleter>;
using generation_ptr = std::unique_ptr<gt_llama_generation, generation_deleter>;

uint64_t resident_bytes() {
    mach_task_basic_info_data_t info{};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                  reinterpret_cast<task_info_t>(&info), &count) != KERN_SUCCESS) {
        return 0;
    }
    return info.resident_size;
}

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
        "Translate the following text into English. Note that you should only output the "
        "translated result without any additional explanation:\n\n"
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
    if (load_seconds > 10.0) {
        std::fprintf(stderr, "model load exceeded 10s: %.3fs\n", load_seconds);
        std::exit(7);
    }

    std::string too_long;
    for (int i = 0; i < 8192; ++i) { too_long += "hello "; }
    if (gt_llama_validate_prompt(model.get(), too_long.c_str(), 1024, error, sizeof(error)) != 1) {
        std::fprintf(stderr, "context preflight failed to reject an oversized prompt\n");
        std::exit(12);
    }
    if (gt_llama_validate_prompt(model.get(), "Translate hello into Chinese", 1024, error, sizeof(error)) != 0) {
        std::fprintf(stderr, "context preflight rejected a short prompt\n");
        std::exit(13);
    }
    cancel_generation(model.get());
    uint64_t fifth_rss = 0;

    for (int index = 0; index < repetitions; ++index) {
        const bool to_chinese = index % 2 == 0;
        const std::string prompt = to_chinese
            ? "Translate the following text into Chinese. Note that you should only output the "
              "translated result without any additional explanation:\n\n"
              "Hello, welcome to GemmaTrans. Your text stays private and is translated entirely on this Mac."
            : "Translate the following text into English. Note that you should only output the "
              "translated result without any additional explanation:\n\n"
              "你好，欢迎使用 GemmaTrans。你的文本不会离开这台 Mac。";
        gt_llama_metrics metrics{};
        const std::string output = translate(model.get(), prompt, &metrics);
        if (output.empty() || output.find("[end of text]") != std::string::npos ||
            output.find("<｜") != std::string::npos) {
            std::fprintf(stderr, "invalid output at iteration %d: %s\n", index + 1, output.c_str());
            std::exit(4);
        }
        if (metrics.first_token_seconds > 3.0 || metrics.tokens_per_second < 8.0) {
            std::fprintf(stderr, "performance gate failed at iteration %d: first=%.3fs speed=%.2ft/s\n",
                         index + 1, metrics.first_token_seconds, metrics.tokens_per_second);
            std::exit(8);
        }
        const uint64_t rss = resident_bytes();
        if (rss > (uint64_t{1536} << 20)) {
            std::fprintf(stderr, "RSS gate failed at iteration %d: %llu bytes\n",
                         index + 1, static_cast<unsigned long long>(rss));
            std::exit(9);
        }
        if (index == 4) {
            fifth_rss = rss;
        }
        if (index == 19 && fifth_rss > 0 && rss > fifth_rss + (uint64_t{200} << 20)) {
            std::fprintf(stderr, "RSS growth gate failed: fifth=%llu twentieth=%llu\n",
                         static_cast<unsigned long long>(fifth_rss),
                         static_cast<unsigned long long>(rss));
            std::exit(10);
        }
        std::printf(
            "iteration=%d load=%.3fs first=%.3fs speed=%.2ft/s tokens=%d rss=%llu output=%s\n",
            index + 1,
            load_seconds,
            metrics.first_token_seconds,
            metrics.tokens_per_second,
            metrics.generated_tokens,
            static_cast<unsigned long long>(rss),
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
