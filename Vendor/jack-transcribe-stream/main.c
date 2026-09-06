// jack-transcribe-stream — stdin-PCM streaming bridge for Jack dictation.
//
// Reads raw float32 little-endian 16 kHz mono PCM on stdin, feeds it to
// transcribe.cpp's streaming API, and prints one protocol line to stdout
// whenever the transcript changes:
//
//     JT>{"committed":"...","tentative":"..."}
//
// On stdin EOF it finalizes the stream and prints:
//
//     JT>{"final":"..."}
//
// The "JT>" prefix exists because ggml/Metal may write diagnostics to
// stdout; the Swift side must ignore any line without the prefix.
//
// Usage: jack-transcribe-stream model.gguf [chunk_ms=160] [right_ms=160]
//
// chunk_ms/right_ms select the parakeet-unified (L,C,R) attention tuple
// (left stays at the model default 5600 ms). 160/160 = 320 ms lookahead,
// the low-latency sweet spot from the model's training menu.

#include "transcribe.h"
#include "transcribe/parakeet.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Feed cadence: 100 ms of audio per transcribe_stream_feed call.
#define FEED_SAMPLES 1600

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

static void emit_partial(struct transcribe_session * session) {
    struct transcribe_stream_text text;
    transcribe_stream_text_init(&text);
    if (transcribe_stream_get_text(session, &text) != TRANSCRIBE_OK) {
        return;
    }
    fputs("JT>{\"committed\":\"", stdout);
    print_json_escaped(text.committed_text ? text.committed_text : "");
    fputs("\",\"tentative\":\"", stdout);
    print_json_escaped(text.tentative_text ? text.tentative_text : "");
    fputs("\"}\n", stdout);
    fflush(stdout);
}

static void emit_final(struct transcribe_session * session) {
    struct transcribe_stream_text text;
    transcribe_stream_text_init(&text);
    const char * final_text = "";
    if (transcribe_stream_get_text(session, &text) == TRANSCRIBE_OK && text.full_text != NULL) {
        final_text = text.full_text;
    }
    fputs("JT>{\"final\":\"", stdout);
    print_json_escaped(final_text);
    fputs("\"}\n", stdout);
    fflush(stdout);
}

int main(int argc, char ** argv) {
    if (argc < 2 || argc > 4) {
        fprintf(stderr, "usage: %s model.gguf [chunk_ms=160] [right_ms=160]\n", argv[0]);
        return 2;
    }
    const char *  model_path = argv[1];
    const int32_t chunk_ms   = (argc > 2) ? (int32_t) atoi(argv[2]) : 160;
    const int32_t right_ms   = (argc > 3) ? (int32_t) atoi(argv[3]) : 160;

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

    st = transcribe_stream_begin(session, NULL, &stream_params);
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
        struct transcribe_stream_update upd;
        transcribe_stream_update_init(&upd);
        st = transcribe_stream_feed(session, pcm, (int) got, &upd);
        if (st != TRANSCRIBE_OK) {
            fprintf(stderr, "error: stream_feed: %s\n", transcribe_status_string(st));
            transcribe_session_free(session);
            return 1;
        }
        if (upd.result_changed) {
            emit_partial(session);
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
    emit_final(session);

    transcribe_session_free(session);
    return 0;
}
