#include "GemmaLlamaRuntime.h"

#include "chat.h"
#include "llama.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

extern "C" void ggml_backend_cpu_kleidiai_set_enabled(bool enabled);

namespace {

using clock_type = std::chrono::steady_clock;

void set_error(char * buffer, size_t capacity, const std::string & message) {
    if (buffer == nullptr || capacity == 0) {
        return;
    }
    const size_t length = std::min(capacity - 1, message.size());
    std::memcpy(buffer, message.data(), length);
    buffer[length] = '\0';
}

double elapsed_seconds(clock_type::time_point start, clock_type::time_point end) {
    return std::chrono::duration<double>(end - start).count();
}

void runtime_log_callback(ggml_log_level level, const char * text, void *) {
    if (level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR) {
        std::fputs(text, stderr);
    }
}

std::vector<llama_token> tokenize(const llama_vocab * vocab, const std::string & text) {
    const int32_t count = llama_tokenize(
        vocab, text.data(), static_cast<int32_t>(text.size()), nullptr, 0, true, true);
    if (count >= 0) {
        return {};
    }

    std::vector<llama_token> tokens(static_cast<size_t>(-count));
    const int32_t written = llama_tokenize(
        vocab,
        text.data(),
        static_cast<int32_t>(text.size()),
        tokens.data(),
        static_cast<int32_t>(tokens.size()),
        true,
        true);
    if (written < 0) {
        throw std::runtime_error("failed to tokenize prompt");
    }
    tokens.resize(static_cast<size_t>(written));
    return tokens;
}

std::string format_user_prompt(const llama_model * model, const char * user_prompt) {
    auto templates = common_chat_templates_init(model, "");
    if (!templates) {
        throw std::runtime_error("model does not contain a usable chat template");
    }

    common_chat_templates_inputs inputs;
    inputs.use_jinja = true;
    inputs.add_generation_prompt = true;
    inputs.enable_thinking = false;
    common_chat_msg message;
    message.role = "user";
    message.content = user_prompt;
    inputs.messages.push_back(std::move(message));
    return common_chat_templates_apply(templates.get(), inputs).prompt;
}

} // namespace

struct gt_llama_model {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    const llama_vocab * vocab = nullptr;
    int32_t batch_size = 512;

    ~gt_llama_model() {
        if (context != nullptr) {
            llama_free(context);
        }
        if (model != nullptr) {
            llama_model_free(model);
        }
    }
};

struct gt_llama_generation {
    gt_llama_model * owner = nullptr;
    llama_sampler * sampler = nullptr;
    std::vector<llama_token> prompt_tokens;
    size_t prompt_position = 0;
    llama_token pending_token = LLAMA_TOKEN_NULL;
    int32_t max_tokens = 0;
    int32_t generated_tokens = 0;
    bool finished = false;
    clock_type::time_point started_at = clock_type::now();
    clock_type::time_point first_token_at{};
    clock_type::time_point finished_at{};

    ~gt_llama_generation() {
        if (sampler != nullptr) {
            llama_sampler_free(sampler);
        }
    }
};

void gt_llama_backend_initialize(void) {
    static std::once_flag once;
    std::call_once(once, [] {
        llama_log_set(runtime_log_callback, nullptr);
        llama_backend_init();
    });
}

gt_llama_model * gt_llama_model_load(
    const char * path,
    gt_llama_model_config config,
    char * error_buffer,
    size_t error_buffer_capacity
) {
    try {
        if (path == nullptr || path[0] == '\0') {
            throw std::runtime_error("model path is empty");
        }
        if (config.quantization != GT_LLAMA_QUANTIZATION_STQ1_0 &&
            config.quantization != GT_LLAMA_QUANTIZATION_Q2_0C) {
            throw std::runtime_error("unsupported curated quantization");
        }

        gt_llama_backend_initialize();
        ggml_backend_cpu_kleidiai_set_enabled(config.quantization == GT_LLAMA_QUANTIZATION_Q2_0C);

        auto result = std::make_unique<gt_llama_model>();
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = 0;
        result->model = llama_model_load_from_file(path, model_params);
        if (result->model == nullptr) {
            throw std::runtime_error("llama.cpp could not load the model file");
        }

        llama_context_params context_params = llama_context_default_params();
        context_params.n_ctx = static_cast<uint32_t>(std::max(1, config.context_size));
        context_params.n_batch = static_cast<uint32_t>(std::max(1, config.batch_size));
        context_params.n_ubatch = context_params.n_batch;
        context_params.n_threads = std::max(1, config.thread_count);
        context_params.n_threads_batch = context_params.n_threads;
        context_params.no_perf = false;
        result->context = llama_init_from_model(result->model, context_params);
        if (result->context == nullptr) {
            throw std::runtime_error("llama.cpp could not create the inference context");
        }
        llama_set_n_threads(result->context, context_params.n_threads, context_params.n_threads_batch);
        result->vocab = llama_model_get_vocab(result->model);
        result->batch_size = static_cast<int32_t>(context_params.n_batch);
        return result.release();
    } catch (const std::exception & error) {
        set_error(error_buffer, error_buffer_capacity, error.what());
        return nullptr;
    } catch (...) {
        set_error(error_buffer, error_buffer_capacity, "unknown model load failure");
        return nullptr;
    }
}

void gt_llama_model_free(gt_llama_model * model) {
    delete model;
}

gt_llama_generation * gt_llama_generation_begin(
    gt_llama_model * model,
    const char * user_prompt,
    gt_llama_sampling_config config,
    char * error_buffer,
    size_t error_buffer_capacity
) {
    try {
        if (model == nullptr || model->context == nullptr || model->vocab == nullptr) {
            throw std::runtime_error("model is not loaded");
        }
        if (user_prompt == nullptr || user_prompt[0] == '\0') {
            throw std::runtime_error("translation prompt is empty");
        }

        llama_memory_clear(llama_get_memory(model->context), true);
        auto result = std::make_unique<gt_llama_generation>();
        result->owner = model;
        result->max_tokens = std::max(1, config.max_tokens);
        result->started_at = clock_type::now();
        result->prompt_tokens = tokenize(model->vocab, format_user_prompt(model->model, user_prompt));
        if (result->prompt_tokens.empty()) {
            throw std::runtime_error("chat template produced an empty prompt");
        }

        llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
        sampler_params.no_perf = false;
        result->sampler = llama_sampler_chain_init(sampler_params);
        if (result->sampler == nullptr) {
            throw std::runtime_error("could not create sampler");
        }
        llama_sampler_chain_add(result->sampler, llama_sampler_init_penalties(
            llama_vocab_n_tokens(model->vocab), 64, config.repetition_penalty, 0.0f, 0.0f));
        llama_sampler_chain_add(result->sampler, llama_sampler_init_top_k(config.top_k));
        llama_sampler_chain_add(result->sampler, llama_sampler_init_top_p(config.top_p, 1));
        llama_sampler_chain_add(result->sampler, llama_sampler_init_temp(config.temperature));
        llama_sampler_chain_add(result->sampler, llama_sampler_init_dist(config.seed));
        return result.release();
    } catch (const std::exception & error) {
        set_error(error_buffer, error_buffer_capacity, error.what());
        return nullptr;
    } catch (...) {
        set_error(error_buffer, error_buffer_capacity, "unknown generation setup failure");
        return nullptr;
    }
}

gt_llama_step_result gt_llama_generation_step(
    gt_llama_generation * generation,
    uint8_t * output_buffer,
    size_t output_buffer_capacity,
    size_t * output_length,
    char * error_buffer,
    size_t error_buffer_capacity
) {
    if (output_length != nullptr) {
        *output_length = 0;
    }
    try {
        if (generation == nullptr || generation->owner == nullptr || generation->sampler == nullptr) {
            throw std::runtime_error("generation is not initialized");
        }
        if (generation->finished) {
            return GT_LLAMA_STEP_EOG;
        }

        gt_llama_model * owner = generation->owner;
        if (generation->pending_token != LLAMA_TOKEN_NULL) {
            llama_batch token_batch = llama_batch_get_one(&generation->pending_token, 1);
            if (llama_decode(owner->context, token_batch) != 0) {
                throw std::runtime_error("llama.cpp failed to decode generated token");
            }
            generation->pending_token = LLAMA_TOKEN_NULL;
        } else if (generation->prompt_position < generation->prompt_tokens.size()) {
            const size_t remaining = generation->prompt_tokens.size() - generation->prompt_position;
            const int32_t count = static_cast<int32_t>(std::min<size_t>(
                remaining, static_cast<size_t>(std::min(owner->batch_size, 64))));
            llama_batch prompt_batch = llama_batch_get_one(
                generation->prompt_tokens.data() + generation->prompt_position, count);
            if (llama_decode(owner->context, prompt_batch) != 0) {
                throw std::runtime_error("llama.cpp failed to decode prompt");
            }
            generation->prompt_position += static_cast<size_t>(count);
            if (generation->prompt_position < generation->prompt_tokens.size()) {
                return GT_LLAMA_STEP_PROGRESS;
            }
        }

        const llama_token token = llama_sampler_sample(generation->sampler, owner->context, -1);
        if (llama_vocab_is_eog(owner->vocab, token) || token == llama_vocab_eos(owner->vocab) ||
            generation->generated_tokens >= generation->max_tokens) {
            generation->finished = true;
            generation->finished_at = clock_type::now();
            return GT_LLAMA_STEP_EOG;
        }

        std::vector<char> piece(256);
        int32_t piece_length = llama_token_to_piece(
            owner->vocab, token, piece.data(), static_cast<int32_t>(piece.size()), 0, false);
        if (piece_length < 0) {
            piece.resize(static_cast<size_t>(-piece_length));
            piece_length = llama_token_to_piece(
                owner->vocab, token, piece.data(), static_cast<int32_t>(piece.size()), 0, false);
        }
        if (piece_length < 0) {
            throw std::runtime_error("llama.cpp failed to decode token bytes");
        }
        if (static_cast<size_t>(piece_length) > output_buffer_capacity ||
            (piece_length > 0 && output_buffer == nullptr)) {
            throw std::runtime_error("token output buffer is too small");
        }
        if (piece_length > 0) {
            std::memcpy(output_buffer, piece.data(), static_cast<size_t>(piece_length));
        }
        if (output_length != nullptr) {
            *output_length = static_cast<size_t>(piece_length);
        }

        generation->pending_token = token;
        generation->generated_tokens += 1;
        if (generation->generated_tokens == 1) {
            generation->first_token_at = clock_type::now();
        }
        return GT_LLAMA_STEP_TOKEN;
    } catch (const std::exception & error) {
        set_error(error_buffer, error_buffer_capacity, error.what());
        if (generation != nullptr) {
            generation->finished = true;
            generation->finished_at = clock_type::now();
        }
        return GT_LLAMA_STEP_ERROR;
    } catch (...) {
        set_error(error_buffer, error_buffer_capacity, "unknown generation failure");
        if (generation != nullptr) {
            generation->finished = true;
            generation->finished_at = clock_type::now();
        }
        return GT_LLAMA_STEP_ERROR;
    }
}

gt_llama_metrics gt_llama_generation_metrics(const gt_llama_generation * generation) {
    gt_llama_metrics metrics{};
    if (generation == nullptr) {
        return metrics;
    }
    metrics.prompt_tokens = static_cast<int32_t>(generation->prompt_tokens.size());
    metrics.generated_tokens = generation->generated_tokens;
    const clock_type::time_point end = generation->finished ? generation->finished_at : clock_type::now();
    metrics.total_seconds = elapsed_seconds(generation->started_at, end);
    if (generation->generated_tokens > 0) {
        metrics.first_token_seconds = elapsed_seconds(generation->started_at, generation->first_token_at);
        const double generation_seconds = elapsed_seconds(generation->first_token_at, end);
        if (generation_seconds > 0.0 && generation->generated_tokens > 1) {
            metrics.tokens_per_second =
                static_cast<double>(generation->generated_tokens - 1) / generation_seconds;
        }
    }
    return metrics;
}

void gt_llama_generation_free(gt_llama_generation * generation) {
    delete generation;
}
