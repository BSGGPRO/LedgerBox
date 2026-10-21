#ifndef LEDGER_LLAMA_SHIM_H
#define LEDGER_LLAMA_SHIM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque wrapper around a dlopen'ed llama.framework and one model/context.
typedef struct lb_llama lb_llama;

/// Returns 1 when the current platform can attempt to load llama.framework.
int lb_llama_platform_supported(void);

/// Loads `framework_path` and the GGUF model at `model_path`.
/// Returns NULL on failure and writes a UTF-8 message to `error`.
lb_llama *lb_llama_create(const char *framework_path,
                          const char *model_path,
                          int32_t n_ctx,
                          int32_t n_threads,
                          char *error,
                          size_t error_len);

void lb_llama_destroy(lb_llama *handle);

/// Number of parameters reported by the GGUF file, or 0 when unavailable.
uint64_t lb_llama_parameter_count(lb_llama *handle);

/// Runs a single completion. `prompt` must already contain the Qwen chat
/// template. The output is UTF-8, NUL-terminated, and truncated to `out_len`.
/// Returns 0 on success, negative on failure.
int lb_llama_generate(lb_llama *handle,
                      const char *prompt,
                      int32_t max_tokens,
                      float temperature,
                      char *out,
                      size_t out_len,
                      char *error,
                      size_t error_len);

#ifdef __cplusplus
}
#endif

#endif /* LEDGER_LLAMA_SHIM_H */
