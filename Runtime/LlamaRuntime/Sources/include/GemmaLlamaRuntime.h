#ifndef GEMMA_LLAMA_RUNTIME_H
#define GEMMA_LLAMA_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct gt_llama_model gt_llama_model;
typedef struct gt_llama_generation gt_llama_generation;

typedef enum gt_llama_quantization {
    GT_LLAMA_QUANTIZATION_STQ1_0 = 0,
    GT_LLAMA_QUANTIZATION_Q2_0C = 1,
} gt_llama_quantization;

typedef enum gt_llama_step_result {
    GT_LLAMA_STEP_ERROR = -1,
    GT_LLAMA_STEP_PROGRESS = 0,
    GT_LLAMA_STEP_TOKEN = 1,
    GT_LLAMA_STEP_EOG = 2,
} gt_llama_step_result;

typedef struct gt_llama_model_config {
    int32_t context_size;
    int32_t batch_size;
    int32_t thread_count;
    gt_llama_quantization quantization;
} gt_llama_model_config;

typedef struct gt_llama_sampling_config {
    int32_t max_tokens;
    int32_t top_k;
    float top_p;
    float temperature;
    float repetition_penalty;
    uint32_t seed;
} gt_llama_sampling_config;

typedef struct gt_llama_metrics {
    int32_t prompt_tokens;
    int32_t generated_tokens;
    double first_token_seconds;
    double total_seconds;
    double tokens_per_second;
} gt_llama_metrics;

// Initializes llama.cpp once for the lifetime of the process.
void gt_llama_backend_initialize(void);

gt_llama_model * gt_llama_model_load(
    const char * path,
    gt_llama_model_config config,
    char * error_buffer,
    size_t error_buffer_capacity
);

void gt_llama_model_free(gt_llama_model * model);

// Pure preflight using the model's chat template and tokenizer. 0 = valid, 1 = capacity exceeded,
// -1 = invalid model/template. Does not clear or otherwise change the KV cache.
int32_t gt_llama_validate_prompt(
    gt_llama_model * model, const char * user_prompt, int32_t max_tokens,
    char * error_buffer, size_t error_buffer_capacity
);

gt_llama_generation * gt_llama_generation_begin(
    gt_llama_model * model,
    const char * user_prompt,
    gt_llama_sampling_config config,
    char * error_buffer,
    size_t error_buffer_capacity
);

gt_llama_step_result gt_llama_generation_step(
    gt_llama_generation * generation,
    uint8_t * output_buffer,
    size_t output_buffer_capacity,
    size_t * output_length,
    char * error_buffer,
    size_t error_buffer_capacity
);

gt_llama_metrics gt_llama_generation_metrics(const gt_llama_generation * generation);

void gt_llama_generation_free(gt_llama_generation * generation);

#ifdef __cplusplus
}
#endif

#endif
