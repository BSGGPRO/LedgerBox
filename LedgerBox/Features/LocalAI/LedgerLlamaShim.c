#include "LedgerLlamaShim.h"

#include <dlfcn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <TargetConditionals.h>

#include "llama.h"

typedef void *lb_memory_t;

struct lb_llama {
    void *library;

    struct llama_model *model;
    struct llama_context *context;
    const struct llama_vocab *vocab;

    struct llama_model_params (*model_default_params)(void);
    struct llama_model *(*model_load_from_file)(const char *, struct llama_model_params);
    void (*model_free)(struct llama_model *);
    uint64_t (*model_n_params)(const struct llama_model *);
    const struct llama_vocab *(*model_get_vocab)(const struct llama_model *);

    struct llama_context_params (*context_default_params)(void);
    struct llama_context *(*init_from_model)(struct llama_model *, struct llama_context_params);
    void (*free_context)(struct llama_context *);
    lb_memory_t (*get_memory)(const struct llama_context *);
    void (*memory_clear)(lb_memory_t, bool);

    int32_t (*tokenize)(const struct llama_vocab *, const char *, int32_t,
                        llama_token *, int32_t, bool, bool);
    int32_t (*token_to_piece)(const struct llama_vocab *, llama_token, char *,
                              int32_t, int32_t, bool);
    bool (*vocab_is_eog)(const struct llama_vocab *, llama_token);

    struct llama_batch (*batch_get_one)(llama_token *, int32_t);
    int32_t (*decode)(struct llama_context *, struct llama_batch);

    struct llama_sampler_chain_params (*sampler_chain_default_params)(void);
    struct llama_sampler *(*sampler_chain_init)(struct llama_sampler_chain_params);
    void (*sampler_chain_add)(struct llama_sampler *, struct llama_sampler *);
    struct llama_sampler *(*sampler_init_top_k)(int32_t);
    struct llama_sampler *(*sampler_init_top_p)(float, size_t);
    struct llama_sampler *(*sampler_init_temp)(float);
    struct llama_sampler *(*sampler_init_dist)(uint32_t);
    llama_token (*sampler_sample)(struct llama_sampler *, struct llama_context *, int32_t);
    void (*sampler_accept)(struct llama_sampler *, llama_token);
    void (*sampler_free)(struct llama_sampler *);
};

static void lb_error(char *buffer, size_t length, const char *format, ...) {
    if (buffer == NULL || length == 0) {
        return;
    }
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, length, format, args);
    va_end(args);
}

int lb_llama_platform_supported(void) {
#if TARGET_OS_SIMULATOR
    return 0;
#else
    return 1;
#endif
}

static int lb_resolve(void *library, void *target, const char *name,
                      char *error, size_t error_len) {
    void *symbol = dlsym(library, name);
    if (symbol == NULL) {
        lb_error(error, error_len, "缺少符号 %s: %s", name, dlerror());
        return -1;
    }
    *(void **)target = symbol;
    return 0;
}

#define LB_RESOLVE(field, name) \
    do { \
        if (lb_resolve(handle->library, (void *)&handle->field, name, error, error_len) != 0) { \
            goto fail; \
        } \
    } while (0)

lb_llama *lb_llama_create(const char *framework_path,
                          const char *model_path,
                          int32_t n_ctx,
                          int32_t n_threads,
                          char *error,
                          size_t error_len) {
    if (framework_path == NULL || framework_path[0] == '\0' ||
        model_path == NULL || model_path[0] == '\0') {
        lb_error(error, error_len, "运行时或模型路径为空");
        return NULL;
    }

    lb_llama *handle = calloc(1, sizeof(lb_llama));
    if (handle == NULL) {
        lb_error(error, error_len, "内存不足");
        return NULL;
    }

    handle->library = dlopen(framework_path, RTLD_NOW | RTLD_LOCAL);
    if (handle->library == NULL) {
        lb_error(error, error_len, "无法加载 llama.framework: %s", dlerror());
        free(handle);
        return NULL;
    }

    LB_RESOLVE(model_default_params, "llama_model_default_params");
    LB_RESOLVE(model_load_from_file, "llama_model_load_from_file");
    LB_RESOLVE(model_free, "llama_model_free");
    LB_RESOLVE(model_n_params, "llama_model_n_params");
    LB_RESOLVE(model_get_vocab, "llama_model_get_vocab");
    LB_RESOLVE(context_default_params, "llama_context_default_params");
    LB_RESOLVE(init_from_model, "llama_init_from_model");
    LB_RESOLVE(free_context, "llama_free");
    LB_RESOLVE(get_memory, "llama_get_memory");
    LB_RESOLVE(memory_clear, "llama_memory_clear");
    LB_RESOLVE(tokenize, "llama_tokenize");
    LB_RESOLVE(token_to_piece, "llama_token_to_piece");
    LB_RESOLVE(vocab_is_eog, "llama_vocab_is_eog");
    LB_RESOLVE(batch_get_one, "llama_batch_get_one");
    LB_RESOLVE(decode, "llama_decode");
    LB_RESOLVE(sampler_chain_default_params, "llama_sampler_chain_default_params");
    LB_RESOLVE(sampler_chain_init, "llama_sampler_chain_init");
    LB_RESOLVE(sampler_chain_add, "llama_sampler_chain_add");
    LB_RESOLVE(sampler_init_top_k, "llama_sampler_init_top_k");
    LB_RESOLVE(sampler_init_top_p, "llama_sampler_init_top_p");
    LB_RESOLVE(sampler_init_temp, "llama_sampler_init_temp");
    LB_RESOLVE(sampler_init_dist, "llama_sampler_init_dist");
    LB_RESOLVE(sampler_sample, "llama_sampler_sample");
    LB_RESOLVE(sampler_accept, "llama_sampler_accept");
    LB_RESOLVE(sampler_free, "llama_sampler_free");

    void (*backend_init)(void) = NULL;
    *(void **)(&backend_init) = dlsym(handle->library, "llama_backend_init");
    if (backend_init != NULL) {
        backend_init();
    }

    struct llama_model_params model_params = handle->model_default_params();
    model_params.n_gpu_layers = 99;

    handle->model = handle->model_load_from_file(model_path, model_params);
    if (handle->model == NULL) {
        lb_error(error, error_len, "GGUF 模型加载失败");
        goto fail;
    }

    struct llama_context_params context_params = handle->context_default_params();
    context_params.n_ctx = (uint32_t)(n_ctx > 0 ? n_ctx : 2048);
    context_params.n_batch = 512;
    context_params.n_ubatch = 512;
    context_params.n_threads = n_threads > 0 ? n_threads : 4;
    context_params.n_threads_batch = n_threads > 0 ? n_threads : 4;

    handle->context = handle->init_from_model(handle->model, context_params);
    if (handle->context == NULL) {
        lb_error(error, error_len, "llama context 创建失败");
        goto fail;
    }

    handle->vocab = handle->model_get_vocab(handle->model);
    if (handle->vocab == NULL) {
        lb_error(error, error_len, "词表不可用");
        goto fail;
    }

    return handle;

fail:
    if (handle->context != NULL) {
        handle->free_context(handle->context);
    }
    if (handle->model != NULL && handle->model_free != NULL) {
        handle->model_free(handle->model);
    }
    if (handle->library != NULL) {
        dlclose(handle->library);
    }
    free(handle);
    return NULL;
}

void lb_llama_destroy(lb_llama *handle) {
    if (handle == NULL) {
        return;
    }
    if (handle->context != NULL) {
        handle->free_context(handle->context);
    }
    if (handle->model != NULL) {
        handle->model_free(handle->model);
    }
    if (handle->library != NULL) {
        dlclose(handle->library);
    }
    free(handle);
}

uint64_t lb_llama_parameter_count(lb_llama *handle) {
    if (handle == NULL || handle->model == NULL || handle->model_n_params == NULL) {
        return 0;
    }
    return handle->model_n_params(handle->model);
}

int lb_llama_generate(lb_llama *handle,
                      const char *prompt,
                      int32_t max_tokens,
                      float temperature,
                      char *out,
                      size_t out_len,
                      char *error,
                      size_t error_len) {
    if (handle == NULL || prompt == NULL || out == NULL || out_len == 0) {
        lb_error(error, error_len, "参数无效");
        return -1;
    }
    out[0] = '\0';

    int32_t prompt_length = (int32_t)strlen(prompt);
    if (prompt_length <= 0) {
        lb_error(error, error_len, "Prompt 为空");
        return -1;
    }

    int32_t capacity = prompt_length + 64;
    llama_token *tokens = malloc((size_t)capacity * sizeof(llama_token));
    if (tokens == NULL) {
        lb_error(error, error_len, "Token 缓冲区不足");
        return -1;
    }

    int32_t count = handle->tokenize(
        handle->vocab, prompt, prompt_length, tokens, capacity, true, true);
    if (count < 0) {
        capacity = -count + 8;
        llama_token *larger = realloc(tokens, (size_t)capacity * sizeof(llama_token));
        if (larger == NULL) {
            free(tokens);
            lb_error(error, error_len, "Token 扩容失败");
            return -1;
        }
        tokens = larger;
        count = handle->tokenize(
            handle->vocab, prompt, prompt_length, tokens, capacity, true, true);
    }
    if (count <= 0) {
        free(tokens);
        lb_error(error, error_len, "Prompt tokenize 失败");
        return -1;
    }

    if (count + max_tokens + 8 >= 2048) {
        free(tokens);
        lb_error(error, error_len, "Prompt 过长，超出 2048 context");
        return -1;
    }

    if (handle->get_memory != NULL && handle->memory_clear != NULL) {
        handle->memory_clear(handle->get_memory(handle->context), true);
    }

    struct llama_batch batch = handle->batch_get_one(tokens, count);
    if (handle->decode(handle->context, batch) != 0) {
        free(tokens);
        lb_error(error, error_len, "Prompt decode 失败");
        return -1;
    }
    free(tokens);

    struct llama_sampler_chain_params sampler_params =
        handle->sampler_chain_default_params();
    struct llama_sampler *chain = handle->sampler_chain_init(sampler_params);
    if (chain == NULL) {
        lb_error(error, error_len, "Sampler 创建失败");
        return -1;
    }
    handle->sampler_chain_add(chain, handle->sampler_init_top_k(40));
    handle->sampler_chain_add(chain, handle->sampler_init_top_p(0.9f, 1));
    handle->sampler_chain_add(chain, handle->sampler_init_temp(
        temperature > 0.0f ? temperature : 0.2f));
    handle->sampler_chain_add(chain, handle->sampler_init_dist(1234));

    size_t written = 0;
    for (int32_t index = 0; index < max_tokens; index += 1) {
        llama_token token = handle->sampler_sample(chain, handle->context, -1);
        handle->sampler_accept(chain, token);

        if (handle->vocab_is_eog(handle->vocab, token)) {
            break;
        }

        char piece[512];
        int32_t piece_length = handle->token_to_piece(
            handle->vocab, token, piece, (int32_t)sizeof(piece), 0, true);
        char *allocated = NULL;
        if (piece_length < 0) {
            int32_t needed = -piece_length;
            allocated = malloc((size_t)needed);
            if (allocated == NULL) {
                continue;
            }
            piece_length = handle->token_to_piece(
                handle->vocab, token, allocated, needed, 0, true);
        }

        const char *source = allocated != NULL ? allocated : piece;
        if (piece_length > 0 && written + (size_t)piece_length < out_len) {
            memcpy(out + written, source, (size_t)piece_length);
            written += (size_t)piece_length;
            out[written] = '\0';
        }
        free(allocated);

        struct llama_batch next = handle->batch_get_one(&token, 1);
        if (handle->decode(handle->context, next) != 0) {
            handle->sampler_free(chain);
            lb_error(error, error_len, "生成 decode 失败");
            return -1;
        }
    }

    handle->sampler_free(chain);
    return 0;
}
