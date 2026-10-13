// jack-transcribe-stream — stdin-PCM streaming bridge for Jack dictation.
//
// One-shot mode (meetings, file imports):
//
//     jack-transcribe-stream model.gguf [chunk_ms=160] [right_ms=160]
//
// Reads raw float32 little-endian 16 kHz mono PCM on stdin, feeds it to
// transcribe.cpp's streaming API, and prints one protocol line to stdout
// whenever the transcript changes:
//
//     JT>{"committed":"...","tentative":"..."}
//
// On stdin EOF it finalizes the stream, prints JT>{"final":"..."} and exits.
//
// Server mode (dictation):
//
//     jack-transcribe-stream model.gguf --serve
//
// Loads the model once, prints JT>{"ready":true}, then runs one dictation
// after another without reloading. stdin carries framed commands: a little-
// endian uint32 opcode, a uint32 session id, and a uint32 payload byte count,
// followed by the payload. Every reply line echoes the session id as "sid",
// so a late line from a cancelled session can never be mistaken for the next.
//
//     BEGIN  (1) payload int32 chunk_ms, int32 right_ms  -> starts a stream
//     AUDIO  (2) payload float32 PCM                     -> JT>{"sid":N,"committed":...,"tentative":...}
//     FINISH (3) no payload                              -> JT>{"sid":N,"final":"..."}
//     CANCEL (4) no payload                              -> JT>{"sid":N,"cancelled":true}
//     RUN    (5) payload float32 PCM                     -> JT>{"sid":N,"offline":"..."}
//
// RUN decodes a whole recording at once with full context, the model's most
// accurate mode, for a final pass after the live stream. Errors print
// JT>{"sid":N,"error":"..."}; the server keeps running. EOF on stdin exits.
//
// The "JT>" prefix exists because ggml/Metal may write diagnostics to
// stdout; the Swift side must ignore any line without the prefix.
//
// chunk_ms/right_ms select the parakeet-unified (L,C,R) attention tuple
// (left stays at the model default 5600 ms). 160/160 = 320 ms lookahead,
// the low-latency sweet spot from the model's training menu.

#include "transcribe.h"
#include "transcribe/parakeet.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Feed cadence: 100 ms of audio per transcribe_stream_feed call.
#define FEED_SAMPLES 1600

enum { OP_BEGIN = 1, OP_AUDIO = 2, OP_FINISH = 3, OP_CANCEL = 4, OP_RUN = 5 };

static void print_json_escaped(const char * s) {
    for (; *s; ++s) {
        unsigned char c = (unsigned char) *s;
        switch (c) {
            case '"':  fputs("\\\"", stdout); break;
            case '\\': fputs("\\\\", stdout); break;
            case '\n': fputs("\\n", stdout); break;
            case '\r': fputs("\\r", stdout); break;
            case '\t': fputs("\\t", stdout); break;
            default:
                if (c < 0x20) {
                    fprintf(stdout, "\\u%04x", c);
                } else {
                    fputc(c, stdout);
                }
        }
    }
}

// Session-id prefix for server replies; one-shot mode passes a negative sid and omits it.
static void begin_line(int64_t sid) {
    if (sid >= 0) {
        fprintf(stdout, "JT>{\"sid\":%lld,", (long long) sid);
    } else {
        fputs("JT>{", stdout);
    }
}

static void emit_string(int64_t sid, const char * key, const char * value) {
    begin_line(sid);
    fprintf(stdout, "\"%s\":\"", key);
    print_json_escaped(value ? value : "");
    fputs("\"}\n", stdout);
    fflush(stdout);
}

static void emit_partial(int64_t sid, struct transcribe_session * session) {
    struct transcribe_stream_text text;
    transcribe_stream_text_init(&text);
    if (transcribe_stream_get_text(session, &text) != TRANSCRIBE_OK) {
        return;
    }
    begin_line(sid);
    fputs("\"committed\":\"", stdout);
    print_json_escaped(text.committed_text ? text.committed_text : "");
    fputs("\",\"tentative\":\"", stdout);
    print_json_escaped(text.tentative_text ? text.tentative_text : "");
    fputs("\"}\n", stdout);
    fflush(stdout);
}

static void emit_final(int64_t sid, struct transcribe_session * session) {
    struct transcribe_stream_text text;
    transcribe_stream_text_init(&text);
    const char * final_text = "";
    if (transcribe_stream_get_text(session, &text) == TRANSCRIBE_OK && text.full_text != NULL) {
        final_text = text.full_text;
    }
    emit_string(sid, "final", final_text);
}

static transcribe_status begin_stream(struct transcribe_session * session, int32_t chunk_ms, int32_t right_ms) {
    // Select the low-latency chunked-attention tuple when the model
    // accepts it (parakeet-unified); otherwise fall back to defaults.
    struct transcribe_parakeet_buffered_stream_ext buffered;
    transcribe_parakeet_buffered_stream_ext_init(&buffered);
    buffered.chunk_ms = chunk_ms;
    buffered.right_ms = right_ms;

    struct transcribe_stream_params stream_params;
    transcribe_stream_params_init(&stream_params);
    if (transcribe_model_accepts_ext_kind(transcribe_get_model(session), TRANSCRIBE_EXT_SLOT_STREAM,
                                          TRANSCRIBE_EXT_KIND_PARAKEET_BUFFERED_STREAM)) {
        stream_params.family = &buffered.ext;
    }
    return transcribe_stream_begin(session, NULL, &stream_params);
}

static transcribe_status feed_all(int64_t sid, struct transcribe_session * session, const float * pcm, size_t count) {
    for (size_t offset = 0; offset < count; offset += FEED_SAMPLES) {
        size_t n = count - offset < FEED_SAMPLES ? count - offset : FEED_SAMPLES;
        struct transcribe_stream_update upd;
        transcribe_stream_update_init(&upd);
        transcribe_status st = transcribe_stream_feed(session, pcm + offset, (int) n, &upd);
        if (st != TRANSCRIBE_OK) {
            return st;
        }
        if (upd.result_changed) {
            emit_partial(sid, session);
        }
    }
    return TRANSCRIBE_OK;
}

static int read_exact(void * buffer, size_t bytes) {
    return fread(buffer, 1, bytes, stdin) == bytes;
}

static int serve(struct transcribe_session * session) {
    fputs("JT>{\"ready\":true}\n", stdout);
    fflush(stdout);

    float * payload = NULL;
    size_t capacity = 0;
    for (;;) {
        uint32_t header[3];
        if (!read_exact(header, sizeof header)) {
            break;  // Jack closed the pipe: exit quietly.
        }
        const uint32_t op = header[0];
        const int64_t sid = header[1];
        const uint32_t bytes = header[2];
        if (bytes > capacity) {
            float * grown = realloc(payload, bytes);
            if (grown == NULL) {
                fprintf(stderr, "error: out of memory for %u-byte payload\n", bytes);
                break;
            }
            payload = grown;
            capacity = bytes;
        }
        if (bytes > 0 && !read_exact(payload, bytes)) {
            break;
        }
        const size_t samples = bytes / sizeof(float);
        transcribe_status st = TRANSCRIBE_OK;

        switch (op) {
            case OP_BEGIN: {
                int32_t * tuple = (int32_t *) payload;
                transcribe_stream_reset(session);
                st = begin_stream(session, bytes >= 8 ? tuple[0] : 160, bytes >= 8 ? tuple[1] : 160);
                break;
            }
            case OP_AUDIO:
                if (transcribe_stream_get_state(session) == TRANSCRIBE_STREAM_ACTIVE) {
                    st = feed_all(sid, session, payload, samples);
                }
                break;
            case OP_FINISH:
                if (transcribe_stream_get_state(session) == TRANSCRIBE_STREAM_ACTIVE) {
                    struct transcribe_stream_update fin;
                    transcribe_stream_update_init(&fin);
                    st = transcribe_stream_finalize(session, &fin);
                }
                if (st == TRANSCRIBE_OK) {
                    emit_final(sid, session);
                }
                transcribe_stream_reset(session);
                break;
            case OP_CANCEL:
                transcribe_stream_reset(session);
                begin_line(sid);
                fputs("\"cancelled\":true}\n", stdout);
                fflush(stdout);
                break;
            case OP_RUN:
                transcribe_stream_reset(session);
                if (samples == 0) {
                    emit_string(sid, "offline", "");
                    break;
                }
                st = transcribe_run(session, payload, (int) samples, NULL);
                if (st == TRANSCRIBE_OK) {
                    emit_string(sid, "offline", transcribe_full_text(session));
                }
                break;
            default:
                st = TRANSCRIBE_ERR_INVALID_ARG;
        }
        if (st != TRANSCRIBE_OK) {
            transcribe_stream_reset(session);
            emit_string(sid, "error", transcribe_status_string(st));
        }
    }
    free(payload);
    return 0;
}

int main(int argc, char ** argv) {
    if (argc < 2 || argc > 4) {
        fprintf(stderr, "usage: %s model.gguf [chunk_ms=160] [right_ms=160] | --serve\n", argv[0]);
        return 2;
    }
    const char * model_path = argv[1];
    const int    server     = argc == 3 && strcmp(argv[2], "--serve") == 0;
    const int32_t chunk_ms  = (!server && argc > 2) ? (int32_t) atoi(argv[2]) : 160;
    const int32_t right_ms  = (!server && argc > 3) ? (int32_t) atoi(argv[3]) : 160;

    struct transcribe_session * session = NULL;
    transcribe_status           st      = transcribe_open(model_path, NULL, NULL, &session);
    if (st != TRANSCRIBE_OK) {
        fprintf(stderr, "error: transcribe_open: %s\n", transcribe_status_string(st));
        return 1;
    }

    struct transcribe_capabilities caps;
    transcribe_capabilities_init(&caps);
    if (transcribe_model_get_capabilities(transcribe_get_model(session), &caps) != TRANSCRIBE_OK ||
        !caps.supports_streaming) {
        fprintf(stderr, "error: model does not support streaming\n");
        transcribe_session_free(session);
        return 1;
    }

    if (server) {
        int code = serve(session);
        transcribe_session_free(session);
        return code;
    }

    st = begin_stream(session, chunk_ms, right_ms);
    if (st != TRANSCRIBE_OK) {
        fprintf(stderr, "error: stream_begin: %s\n", transcribe_status_string(st));
        transcribe_session_free(session);
        return 1;
    }

    // Signal readiness so the Swift side knows model load is done.
    fputs("JT>{\"ready\":true}\n", stdout);
    fflush(stdout);

    float pcm[FEED_SAMPLES];
    for (;;) {
        size_t got = fread(pcm, sizeof(float), FEED_SAMPLES, stdin);
        if (got == 0) {
            break;  // EOF or error → finalize
        }
        st = feed_all(-1, session, pcm, got);
        if (st != TRANSCRIBE_OK) {
            fprintf(stderr, "error: stream_feed: %s\n", transcribe_status_string(st));
            transcribe_session_free(session);
            return 1;
        }
    }

    struct transcribe_stream_update fin;
    transcribe_stream_update_init(&fin);
    st = transcribe_stream_finalize(session, &fin);
    if (st != TRANSCRIBE_OK) {
        fprintf(stderr, "error: stream_finalize: %s\n", transcribe_status_string(st));
        transcribe_session_free(session);
        return 1;
    }
    emit_final(-1, session);

    transcribe_session_free(session);
    return 0;
}
