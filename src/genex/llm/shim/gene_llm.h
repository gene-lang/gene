#ifndef GENE_LLM_H
#define GENE_LLM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct gene_llm_model;
struct gene_llm_session;

typedef enum { GENE_LLM_OK = 0, GENE_LLM_ERR_GENERAL = 1 } gene_llm_status;

typedef enum {
  GENE_LLM_FINISH_STOP = 0,
  GENE_LLM_FINISH_LENGTH = 1,
  GENE_LLM_FINISH_CANCELLED = 2,
  GENE_LLM_FINISH_ERROR = 3
} gene_llm_finish_reason;

typedef struct {
  int context_length;
  int threads;
  int gpu_layers;
  bool use_mmap;
  bool use_mlock;
} gene_llm_model_options;

typedef struct {
  int context_length;
  int batch_size;
  int threads;
  int seed;
  float temperature;
  float top_p;
  int top_k;
  int max_tokens;
} gene_llm_session_options;

typedef struct {
  const char *prompt;
  int max_tokens;
  float temperature;
  float top_p;
  int top_k;
  int seed;
} gene_llm_infer_options;

typedef struct {
  int code;
  char message[512];
} gene_llm_error;

typedef struct {
  char *text;
  char **tokens;
  int token_count;
  int latency_ms;
  gene_llm_finish_reason finish_reason;
} gene_llm_completion;

void gene_llm_backend_init(void);

gene_llm_status gene_llm_load_model(const char *path,
                                    const gene_llm_model_options *options,
                                    struct gene_llm_model **out_model,
                                    gene_llm_error *error);
void gene_llm_free_model(struct gene_llm_model *model);

gene_llm_status gene_llm_new_session(struct gene_llm_model *model,
                                     const gene_llm_session_options *options,
                                     struct gene_llm_session **out_session,
                                     gene_llm_error *error);
void gene_llm_free_session(struct gene_llm_session *session);

gene_llm_status gene_llm_infer(struct gene_llm_session *session,
                               const gene_llm_infer_options *options,
                               gene_llm_completion *out_completion,
                               gene_llm_error *error);
void gene_llm_free_completion(gene_llm_completion *completion);

// Callback invoked for each generated token during streaming inference
// token: the generated token text (null-terminated)
// token_len: length of the token in bytes
// user_data: user-provided context pointer
// Returns: 0 to continue, non-zero to stop generation early
typedef int (*gene_llm_token_callback)(char *token, int token_len,
                                       void *user_data);

// Streaming inference - calls callback for each generated token
gene_llm_status gene_llm_infer_streaming(struct gene_llm_session *session,
                                         const gene_llm_infer_options *options,
                                         gene_llm_token_callback callback,
                                         void *user_data,
                                         gene_llm_completion *out_completion,
                                         gene_llm_error *error);

#ifdef __cplusplus
}
#endif

#endif // GENE_LLM_H
