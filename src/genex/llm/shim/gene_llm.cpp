#include "gene_llm.h"

#include "llama.h"

#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

struct gene_llm_model {
  llama_model *model;
  const llama_vocab *vocab;
  int default_ctx;
};

struct gene_llm_session {
  gene_llm_model *model;
  llama_context *ctx;
  int threads;
  int default_max_tokens;
  float default_temperature;
  float default_top_p;
  int default_top_k;
  uint32_t default_seed;
};

namespace {

std::once_flag g_backend_once;

void ensure_backend_init() {
  std::call_once(g_backend_once, []() {
    ggml_backend_load_all();
    llama_backend_init();
  });
}

void set_error(gene_llm_error *err, int code, const std::string &message) {
  if (!err) {
    return;
  }
  err->code = code;
  std::strncpy(err->message, message.c_str(), sizeof(err->message) - 1);
  err->message[sizeof(err->message) - 1] = '\0';
}

char *dup_cstr(const std::string &src) {
  char *buffer = static_cast<char *>(std::malloc(src.size() + 1));
  if (!buffer) {
    return nullptr;
  }
  std::memcpy(buffer, src.data(), src.size());
  buffer[src.size()] = '\0';
  return buffer;
}

void free_tokens(char **tokens, int count) {
  if (!tokens) {
    return;
  }
  for (int i = 0; i < count; ++i) {
    if (tokens[i]) {
      std::free(tokens[i]);
    }
  }
  std::free(tokens);
}

llama_sampler *build_sampler(float temperature, float top_p, int top_k,
                             uint32_t seed) {
  auto params = llama_sampler_chain_default_params();
  params.no_perf = true;
  llama_sampler *chain = llama_sampler_chain_init(params);

  if (top_k > 0) {
    llama_sampler_chain_add(chain, llama_sampler_init_top_k(top_k));
  }
  if (top_p > 0.0f && top_p < 1.0f) {
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(top_p, 1));
  }
  if (temperature > 0.0f && std::fabs(temperature - 1.0f) > 1e-3f) {
    llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature));
  }

  if (temperature <= 0.0f) {
    llama_sampler_chain_add(chain, llama_sampler_init_greedy());
  } else {
    const uint32_t actual_seed = seed == 0 ? LLAMA_DEFAULT_SEED : seed;
    llama_sampler_chain_add(chain, llama_sampler_init_dist(actual_seed));
  }

  return chain;
}

int32_t tokenize_prompt(const llama_vocab *vocab, const std::string &prompt,
                        std::vector<llama_token> &out_tokens,
                        gene_llm_error *err) {
  const int32_t required =
      llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                     nullptr, 0, true, true);
  if (required == INT32_MIN) {
    set_error(err, 1, "tokenization overflow");
    return -1;
  }
  const int32_t token_count = required < 0 ? -required : required;
  if (token_count <= 0) {
    set_error(err, 1, "prompt produced no tokens");
    return -1;
  }

  out_tokens.resize(token_count);
  const int32_t actual =
      llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                     out_tokens.data(), token_count, true, true);
  if (actual < 0) {
    set_error(err, 1, "failed to tokenize prompt");
    return -1;
  }
  return actual;
}

void fill_completion(const std::string &text,
                     const std::vector<std::string> &tokens,
                     gene_llm_finish_reason reason, int latency_ms,
                     gene_llm_completion *out_completion) {
  out_completion->text = dup_cstr(text);
  out_completion->token_count = static_cast<int>(tokens.size());
  out_completion->latency_ms = latency_ms;
  out_completion->finish_reason = reason;
  out_completion->tokens = nullptr;

  if (!tokens.empty()) {
    out_completion->tokens =
        static_cast<char **>(std::malloc(tokens.size() * sizeof(char *)));
    if (out_completion->tokens) {
      for (size_t i = 0; i < tokens.size(); ++i) {
        out_completion->tokens[i] = dup_cstr(tokens[i]);
      }
    }
  }
}

} // namespace

void gene_llm_backend_init(void) { ensure_backend_init(); }

gene_llm_status gene_llm_load_model(const char *path,
                                    const gene_llm_model_options *options,
                                    gene_llm_model **out_model,
                                    gene_llm_error *err) {
  if (!path || !out_model) {
    set_error(err, 1, "invalid arguments");
    return GENE_LLM_ERR_GENERAL;
  }

  ensure_backend_init();

  llama_model_params params = llama_model_default_params();
  if (options) {
    params.n_gpu_layers = std::max(0, options->gpu_layers);
    params.use_mmap = options->use_mmap;
    params.use_mlock = options->use_mlock;
  }

  llama_model *model = llama_model_load_from_file(path, params);
  if (!model) {
    set_error(err, 1, "failed to load GGUF model");
    return GENE_LLM_ERR_GENERAL;
  }

  auto *wrapper = new gene_llm_model();
  wrapper->model = model;
  wrapper->vocab = llama_model_get_vocab(model);
  wrapper->default_ctx = llama_model_n_ctx_train(model);
  if (wrapper->default_ctx <= 0) {
    wrapper->default_ctx = 4096;
  }

  *out_model = wrapper;
  return GENE_LLM_OK;
}

void gene_llm_free_model(gene_llm_model *model) {
  if (!model) {
    return;
  }
  if (model->model) {
    llama_model_free(model->model);
  }
  delete model;
}

gene_llm_status gene_llm_new_session(gene_llm_model *model,
                                     const gene_llm_session_options *options,
                                     gene_llm_session **out_session,
                                     gene_llm_error *err) {
  if (!model || !out_session) {
    set_error(err, 1, "invalid arguments");
    return GENE_LLM_ERR_GENERAL;
  }

  llama_context_params ctx_params = llama_context_default_params();
  const int ctx_len = options && options->context_length > 0
                          ? options->context_length
                          : model->default_ctx;
  ctx_params.n_ctx = ctx_len;
  // Set batch size to context length to allow processing full prompts
  const int batch_size = options && options->batch_size > 0
                             ? options->batch_size
                             : ctx_len;
  ctx_params.n_batch = batch_size;
  ctx_params.n_ubatch = batch_size;  // Physical batch size must also be set
  ctx_params.n_threads = options && options->threads > 0 ? options->threads : 0;
  ctx_params.n_threads_batch = ctx_params.n_threads;
  ctx_params.no_perf = true;

  fprintf(stderr, "[gene_llm] new_session: ctx_len=%d, batch_size=%d, n_batch=%d, n_ubatch=%d\n",
          ctx_len, batch_size, ctx_params.n_batch, ctx_params.n_ubatch);

  llama_context *ctx = llama_init_from_model(model->model, ctx_params);
  if (!ctx) {
    set_error(err, 1, "failed to create llama context");
    return GENE_LLM_ERR_GENERAL;
  }

  auto *session = new gene_llm_session();
  session->model = model;
  session->ctx = ctx;
  session->threads = ctx_params.n_threads;
  session->default_max_tokens =
      options && options->max_tokens > 0 ? options->max_tokens : 256;
  session->default_temperature = options ? options->temperature : 0.7f;
  session->default_top_p = options ? options->top_p : 0.9f;
  session->default_top_k = options && options->top_k > 0 ? options->top_k : 40;
  session->default_seed = options && options->seed != 0
                              ? static_cast<uint32_t>(options->seed)
                              : LLAMA_DEFAULT_SEED;

  *out_session = session;
  return GENE_LLM_OK;
}

void gene_llm_free_session(gene_llm_session *session) {
  if (!session) {
    return;
  }
  if (session->ctx) {
    llama_free(session->ctx);
  }
  delete session;
}

gene_llm_status gene_llm_infer(gene_llm_session *session,
                               const gene_llm_infer_options *options,
                               gene_llm_completion *out_completion,
                               gene_llm_error *err) {
  if (!session || !options || !out_completion || !options->prompt) {
    set_error(err, 1, "invalid arguments");
    return GENE_LLM_ERR_GENERAL;
  }

  const int max_tokens = options->max_tokens > 0 ? options->max_tokens
                                                 : session->default_max_tokens;
  if (max_tokens <= 0) {
    fill_completion("", {}, GENE_LLM_FINISH_CANCELLED, 0, out_completion);
    return GENE_LLM_OK;
  }

  const float temperature = options->temperature > 0.0f
                                ? options->temperature
                                : session->default_temperature;
  const float top_p =
      options->top_p > 0.0f ? options->top_p : session->default_top_p;
  const int top_k =
      options->top_k > 0 ? options->top_k : session->default_top_k;
  const uint32_t seed = options->seed > 0 ? static_cast<uint32_t>(options->seed)
                                          : session->default_seed;

  const llama_vocab *vocab = session->model->vocab;
  std::vector<llama_token> prompt_tokens;
  if (tokenize_prompt(vocab, options->prompt, prompt_tokens, err) < 0) {
    return GENE_LLM_ERR_GENERAL;
  }

  auto *memory = llama_get_memory(session->ctx);
  if (memory) {
    llama_memory_clear(memory, true);
  }

  llama_sampler *sampler = build_sampler(temperature, top_p, top_k, seed);
  if (!sampler) {
    set_error(err, 1, "failed to construct sampler chain");
    return GENE_LLM_ERR_GENERAL;
  }

  llama_batch batch = llama_batch_get_one(
      prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));

  if (llama_model_has_encoder(session->model->model)) {
    if (llama_encode(session->ctx, batch) != 0) {
      llama_sampler_free(sampler);
      set_error(err, 1, "encoder evaluation failed");
      return GENE_LLM_ERR_GENERAL;
    }
    llama_token decoder_start =
        llama_model_decoder_start_token(session->model->model);
    if (decoder_start == LLAMA_TOKEN_NULL) {
      decoder_start = llama_vocab_bos(vocab);
    }
    batch = llama_batch_get_one(&decoder_start, 1);
  }

  const int64_t start_us = llama_time_us();

  fprintf(stderr, "[gene_llm] infer: prompt_tokens=%zu, batch.n_tokens=%d\n",
          prompt_tokens.size(), batch.n_tokens);

  if (llama_decode(session->ctx, batch) != 0) {
    llama_sampler_free(sampler);
    set_error(err, 1, "failed to evaluate prompt");
    return GENE_LLM_ERR_GENERAL;
  }

  std::string completion_text;
  std::vector<std::string> token_texts;
  gene_llm_finish_reason finish_reason = GENE_LLM_FINISH_STOP;
  llama_token new_token = 0;

  for (int generated = 0; generated < max_tokens; ++generated) {
    new_token = llama_sampler_sample(sampler, session->ctx, -1);
    if (llama_vocab_is_eog(vocab, new_token)) {
      finish_reason = GENE_LLM_FINISH_STOP;
      break;
    }

    char buffer[384];
    const int piece_len =
        llama_token_to_piece(vocab, new_token, buffer, sizeof(buffer), 0, true);
    if (piece_len < 0) {
      llama_sampler_free(sampler);
      set_error(err, 1, "failed to convert token to text");
      return GENE_LLM_ERR_GENERAL;
    }
    completion_text.append(buffer, piece_len);
    token_texts.emplace_back(buffer, piece_len);

    llama_batch next_batch = llama_batch_get_one(&new_token, 1);
    if (llama_decode(session->ctx, next_batch) != 0) {
      llama_sampler_free(sampler);
      set_error(err, 1, "failed to evaluate generated token");
      return GENE_LLM_ERR_GENERAL;
    }
  }

  if (static_cast<int>(token_texts.size()) >= max_tokens) {
    finish_reason = GENE_LLM_FINISH_LENGTH;
  }

  const int64_t end_us = llama_time_us();
  const int latency_ms = static_cast<int>((end_us - start_us) / 1000);

  fill_completion(completion_text, token_texts, finish_reason, latency_ms,
                  out_completion);

  llama_sampler_free(sampler);
  return GENE_LLM_OK;
}

void gene_llm_free_completion(gene_llm_completion *completion) {
  if (!completion) {
    return;
  }
  if (completion->text) {
    std::free(completion->text);
    completion->text = nullptr;
  }
  if (completion->tokens) {
    free_tokens(completion->tokens, completion->token_count);
    completion->tokens = nullptr;
  }
  completion->token_count = 0;
}

gene_llm_status gene_llm_infer_streaming(gene_llm_session *session,
                                         const gene_llm_infer_options *options,
                                         gene_llm_token_callback callback,
                                         void *user_data,
                                         gene_llm_completion *out_completion,
                                         gene_llm_error *err) {
  if (!session || !options || !out_completion || !options->prompt) {
    set_error(err, 1, "invalid arguments");
    return GENE_LLM_ERR_GENERAL;
  }

  const int max_tokens = options->max_tokens > 0 ? options->max_tokens
                                                 : session->default_max_tokens;
  if (max_tokens <= 0) {
    fill_completion("", {}, GENE_LLM_FINISH_CANCELLED, 0, out_completion);
    return GENE_LLM_OK;
  }

  const float temperature = options->temperature > 0.0f
                                ? options->temperature
                                : session->default_temperature;
  const float top_p =
      options->top_p > 0.0f ? options->top_p : session->default_top_p;
  const int top_k =
      options->top_k > 0 ? options->top_k : session->default_top_k;
  const uint32_t seed = options->seed > 0 ? static_cast<uint32_t>(options->seed)
                                          : session->default_seed;

  const llama_vocab *vocab = session->model->vocab;
  std::vector<llama_token> prompt_tokens;
  if (tokenize_prompt(vocab, options->prompt, prompt_tokens, err) < 0) {
    return GENE_LLM_ERR_GENERAL;
  }

  auto *memory = llama_get_memory(session->ctx);
  if (memory) {
    llama_memory_clear(memory, true);
  }

  llama_sampler *sampler = build_sampler(temperature, top_p, top_k, seed);
  if (!sampler) {
    set_error(err, 1, "failed to construct sampler chain");
    return GENE_LLM_ERR_GENERAL;
  }

  llama_batch batch = llama_batch_get_one(
      prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));

  if (llama_model_has_encoder(session->model->model)) {
    if (llama_encode(session->ctx, batch) != 0) {
      llama_sampler_free(sampler);
      set_error(err, 1, "encoder evaluation failed");
      return GENE_LLM_ERR_GENERAL;
    }
    llama_token decoder_start =
        llama_model_decoder_start_token(session->model->model);
    if (decoder_start == LLAMA_TOKEN_NULL) {
      decoder_start = llama_vocab_bos(vocab);
    }
    batch = llama_batch_get_one(&decoder_start, 1);
  }

  const int64_t start_us = llama_time_us();

  fprintf(stderr, "[gene_llm] infer: prompt_tokens=%zu, batch.n_tokens=%d\n",
          prompt_tokens.size(), batch.n_tokens);

  if (llama_decode(session->ctx, batch) != 0) {
    llama_sampler_free(sampler);
    set_error(err, 1, "failed to evaluate prompt");
    return GENE_LLM_ERR_GENERAL;
  }

  std::string completion_text;
  std::vector<std::string> token_texts;
  gene_llm_finish_reason finish_reason = GENE_LLM_FINISH_STOP;
  llama_token new_token = 0;
  bool cancelled = false;

  for (int generated = 0; generated < max_tokens; ++generated) {
    new_token = llama_sampler_sample(sampler, session->ctx, -1);
    if (llama_vocab_is_eog(vocab, new_token)) {
      finish_reason = GENE_LLM_FINISH_STOP;
      break;
    }

    char buffer[384];
    const int piece_len =
        llama_token_to_piece(vocab, new_token, buffer, sizeof(buffer), 0, true);
    if (piece_len < 0) {
      llama_sampler_free(sampler);
      set_error(err, 1, "failed to convert token to text");
      return GENE_LLM_ERR_GENERAL;
    }

    // Null-terminate for callback
    buffer[piece_len] = '\0';

    // Stream token via callback
    if (callback) {
      int result = callback(buffer, piece_len, user_data);
      if (result != 0) {
        cancelled = true;
        finish_reason = GENE_LLM_FINISH_CANCELLED;
        break;
      }
    }

    completion_text.append(buffer, piece_len);
    token_texts.emplace_back(buffer, piece_len);

    llama_batch next_batch = llama_batch_get_one(&new_token, 1);
    if (llama_decode(session->ctx, next_batch) != 0) {
      llama_sampler_free(sampler);
      set_error(err, 1, "failed to evaluate generated token");
      return GENE_LLM_ERR_GENERAL;
    }
  }

  if (!cancelled && static_cast<int>(token_texts.size()) >= max_tokens) {
    finish_reason = GENE_LLM_FINISH_LENGTH;
  }

  const int64_t end_us = llama_time_us();
  const int latency_ms = static_cast<int>((end_us - start_us) / 1000);

  fill_completion(completion_text, token_texts, finish_reason, latency_ms,
                  out_completion);

  llama_sampler_free(sampler);
  return GENE_LLM_OK;
}
