// pancakenotch-hook: what Claude Code, Codex, Cursor and Devin run for PancakeNotch's hooks after Connect
// (ADR-0037). Usage: pancakenotch-hook <tool> <event>, with the tool's hook JSON on stdin.
//
// It hands the event to PancakeNotch over a Unix socket and, for a permission request, waits for
// the answer (Allow / Deny from the notch). It never gets in the way: when PancakeNotch isn't running
// (no socket, or not ours) it prints the tool's "no opinion" answer and exits 0 at once, and any
// failure does the same.

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define MAX_INPUT (4 * 1024 * 1024)   // a huge tool input is cut, not refused
#define MAX_ANSWER (64 * 1024)
#define CONNECT_MS 250
#define ANSWER_MS (10 * 60 * 1000)   // then the tool asks in its own window, even if PancakeNotch hangs

// What to print when PancakeNotch has nothing to say. Cursor's beforeSubmitPrompt must allow the prompt;
// everything else accepts an empty object (Codex's Stop needs JSON, so never print nothing).
static const char *no_opinion(const char *tool, const char *event) {
    if (strcmp(tool, "cursor") == 0 && strcmp(event, "beforeSubmitPrompt") == 0) return "{\"continue\":true}";
    return "{}";
}

static int waits_for_answer(const char *tool, const char *event) {
    return strcmp(event, "PermissionRequest") == 0
        && (strcmp(tool, "claude") == 0 || strcmp(tool, "codex") == 0 || strcmp(tool, "devin") == 0);
}

static int has_env(const char *name) {
    const char *value = getenv(name);
    return value && *value;
}

// Devin also runs the hooks in Claude Code's settings files. Those runs aren't Claude Code: Devin's own
// entry (after Connect) reports them, so the Claude one stays out of the way. Devin sets
// DEVIN_PROJECT_DIR for its hooks; Claude Code sets CLAUDE_PROJECT_DIR for its own.
static int is_devin_running_claude_hook(const char *tool) {
    return strcmp(tool, "claude") == 0 && has_env("DEVIN_PROJECT_DIR") && !has_env("CLAUDE_PROJECT_DIR");
}

// `"dir":"<path>",` for the header: Devin's hook input has no working folder, so the helper adds the
// project folder Devin gives it (else its own folder). Empty when there's none or it won't fit.
static void project_dir_field(const char *tool, char *out, size_t size) {
    out[0] = '\0';
    if (strcmp(tool, "devin") != 0) return;
    char here[1024];
    const char *dir = getenv("DEVIN_PROJECT_DIR");
    if (!dir || !*dir) dir = getcwd(here, sizeof here);
    if (!dir || !*dir) return;
    size_t used = (size_t)snprintf(out, size, "\"dir\":\"");
    for (const unsigned char *c = (const unsigned char *)dir; *c; c++) {
        char piece[8];
        if (*c == '"' || *c == '\\') snprintf(piece, sizeof piece, "\\%c", *c);
        else if (*c < 0x20) snprintf(piece, sizeof piece, "\\u%04x", *c);
        else snprintf(piece, sizeof piece, "%c", *c);
        size_t length = strlen(piece);
        if (used + length + 3 > size) {
            out[0] = '\0';
            return;
        }
        memcpy(out + used, piece, length);
        used += length;
    }
    memcpy(out + used, "\",", 3);
}

static int finish(const char *output) {
    fputs(output, stdout);
    fputc('\n', stdout);
    fflush(stdout);
    return 0;
}

static int write_all(int fd, const char *data, size_t length) {
    while (length > 0) {
        ssize_t written = write(fd, data, length);
        if (written < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        data += written;
        length -= (size_t)written;
    }
    return 0;
}

static char *read_stdin(size_t *length) {
    size_t capacity = 64 * 1024, used = 0;
    char *buffer = malloc(capacity);
    if (!buffer) return NULL;
    char chunk[16 * 1024];
    ssize_t got;
    while ((got = read(STDIN_FILENO, chunk, sizeof chunk)) != 0) {
        if (got < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (used >= MAX_INPUT) continue; // keep draining so the tool never blocks on a full pipe
        size_t keep = (size_t)got;
        if (used + keep > MAX_INPUT) keep = MAX_INPUT - used;
        if (used + keep > capacity) {
            while (used + keep > capacity) capacity *= 2;
            char *grown = realloc(buffer, capacity);
            if (!grown) break;
            buffer = grown;
        }
        memcpy(buffer + used, chunk, keep);
        used += keep;
    }
    *length = used;
    return buffer;
}

// $HOME/Library/Application Support/PancakeNotch/agents.sock, or PANCAKENOTCH_AGENTS_SOCKET in testing builds.
static int socket_path(char *path, size_t size) {
#ifdef PANCAKENOTCH_INTERNAL_TESTING
    const char *override = getenv("PANCAKENOTCH_AGENTS_SOCKET");
    if (override && *override) return snprintf(path, size, "%s", override) < (int)size ? 0 : -1;
#endif
    const char *home = getenv("HOME");
    if (!home || !*home) {
        struct passwd *user = getpwuid(getuid());
        home = user ? user->pw_dir : NULL;
    }
    if (!home) return -1;
    return snprintf(path, size, "%s/Library/Application Support/PancakeNotch/agents.sock", home) < (int)size ? 0 : -1;
}

// Connects only to a socket owned by this user, without waiting long if nobody listens.
static int connect_to_app(void) {
    struct sockaddr_un address;
    memset(&address, 0, sizeof address);
    address.sun_family = AF_UNIX;
    if (socket_path(address.sun_path, sizeof address.sun_path) != 0) return -1;
    struct stat info;
    if (lstat(address.sun_path, &info) != 0 || !S_ISSOCK(info.st_mode) || info.st_uid != getuid()) return -1;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (connect(fd, (struct sockaddr *)&address, sizeof address) != 0) {
        if (errno != EINPROGRESS && errno != EAGAIN) {
            close(fd);
            return -1;
        }
        struct pollfd wait = {.fd = fd, .events = POLLOUT};
        int error = 0;
        socklen_t length = sizeof error;
        if (poll(&wait, 1, CONNECT_MS) != 1 || getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) != 0 || error != 0) {
            close(fd);
            return -1;
        }
    }
    fcntl(fd, F_SETFL, flags);
    return fd;
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    const char *tool = argc > 1 ? argv[1] : "";
    const char *event = argc > 2 ? argv[2] : "";
    const char *fallback = no_opinion(tool, event);

    size_t length = 0;
    char *input = read_stdin(&length);
    if (is_devin_running_claude_hook(tool)) {
        free(input);
        return finish(fallback);
    }
    int fd = input ? connect_to_app() : -1;
    if (fd < 0) {
        free(input);
        return finish(fallback);
    }

    // One header line (with the body's length, so PancakeNotch knows when it has it all and then notices
    // if this process goes away while it waits), then the tool's JSON as it came.
    // Room for the longest macOS path (1024 bytes) even if every byte needs escaping (6 each).
    char dir[6 * 1024 + 16];
    project_dir_field(tool, dir, sizeof dir);
    char header[sizeof dir + 256];
    int waits = waits_for_answer(tool, event);
    int size = snprintf(header, sizeof header,
                        "{\"v\":1,\"tool\":\"%.16s\",\"event\":\"%.40s\",%s\"ppid\":%d,\"waits\":%s,\"length\":%zu}\n",
                        tool, event, dir, (int)getppid(), waits ? "true" : "false", length);
    int failed = size <= 0 || size >= (int)sizeof header || write_all(fd, header, (size_t)size) != 0
        || write_all(fd, input, length) != 0;
    free(input);
    if (failed || !waits) {
        close(fd);
        return finish(fallback);
    }

    // Wait for Allow / Deny. PancakeNotch closing the connection without an answer means "ask in the app",
    // and so does no answer within ANSWER_MS.
    char answer[MAX_ANSWER + 1];
    size_t used = 0;
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    while (used < MAX_ANSWER) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long left = ANSWER_MS - (long)((now.tv_sec - start.tv_sec) * 1000 + (now.tv_nsec - start.tv_nsec) / 1000000);
        struct pollfd wait = {.fd = fd, .events = POLLIN};
        int ready = left > 0 ? poll(&wait, 1, (int)left) : 0;
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) {
            used = 0;
            break;
        }
        ssize_t got = read(fd, answer + used, MAX_ANSWER - used);
        if (got == 0) break;
        if (got < 0) {
            if (errno == EINTR) continue;
            used = 0;
            break;
        }
        used += (size_t)got;
    }
    close(fd);
    answer[used] = '\0';
    while (used > 0 && (answer[used - 1] == '\n' || answer[used - 1] == ' ')) answer[--used] = '\0';
    return finish(used > 0 && answer[0] == '{' ? answer : fallback);
}
