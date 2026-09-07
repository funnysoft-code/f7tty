#include "ProcessOwnership.h"
#include <libproc.h>
#include <signal.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>

typedef struct {
    pid_t pid, parent;
    uint64_t start_sec, start_usec;
    bool owned;
} Child;

static bool matches(Child child) {
    struct proc_bsdinfo info;
    return proc_pidinfo(child.pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info)
        && info.pbi_start_tvsec == child.start_sec
        && info.pbi_start_tvusec == child.start_usec;
}

static int discover(Child **known, int *known_count) {
    int capacity = proc_listallpids(NULL, 0) + 256;
    if (capacity <= 0) return -1;
    pid_t *pids = calloc(capacity, sizeof(pid_t));
    Child *children = calloc(capacity, sizeof(Child));
    if (!pids || !children) { free(pids); free(children); return -1; }
    int count = proc_listallpids(pids, capacity * sizeof(pid_t));
    if (count < 0 || count > capacity) { free(pids); free(children); return -1; }
    pid_t owner = getpid();
    for (int i = 0; i < count; i++) {
        struct proc_bsdinfo info;
        if (pids[i] <= 1 || pids[i] == owner) continue;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) continue;
        children[i] = (Child){pids[i], (pid_t)info.pbi_ppid, info.pbi_start_tvsec, info.pbi_start_tvusec, info.pbi_ppid == (uint32_t)owner};
    }
    bool changed;
    do {
        changed = false;
        for (int i = 0; i < count; i++) {
            if (!children[i].pid || children[i].owned) continue;
            for (int j = 0; j < *known_count; j++) {
                if (children[i].parent == (*known)[j].pid && matches((*known)[j])) {
                    children[i].owned = true;
                    changed = true;
                    break;
                }
            }
            if (children[i].owned) continue;
            for (int j = 0; j < count; j++) {
                if (children[j].owned && children[i].parent == children[j].pid) {
                    children[i].owned = true;
                    changed = true;
                    break;
                }
            }
        }
    } while (changed);
    for (int i = 0; i < count; i++) {
        if (!children[i].owned) continue;
        bool found = false;
        for (int j = 0; j < *known_count; j++) {
            if ((*known)[j].pid == children[i].pid
                && (*known)[j].start_sec == children[i].start_sec
                && (*known)[j].start_usec == children[i].start_usec) { found = true; break; }
        }
        if (found) continue;
        Child *expanded = realloc(*known, (size_t)(*known_count + 1) * sizeof(Child));
        if (!expanded) { free(pids); free(children); return -1; }
        *known = expanded;
        (*known)[(*known_count)++] = children[i];
    }
    free(pids);
    free(children);
    return 0;
}

int f7tty_stop_descendants(void) {
    Child *known = NULL;
    int count = 0, signalled = 0, result = 0;
    // Re-scan during the grace period: a TERM handler may create a child.
    // Previously observed descendants retain their identity after reparenting.
    for (int pass = 0; pass < 8; pass++) {
        if (discover(&known, &count) != 0) result = -1;
        for (; signalled < count; signalled++) {
            if (matches(known[signalled]) && kill(known[signalled].pid, SIGTERM) != 0 && errno != ESRCH) result = -1;
        }
        if (pass < 7) usleep(50000);
    }
    for (int i = 0; i < count; i++) {
        if (matches(known[i]) && kill(known[i].pid, SIGKILL) != 0 && errno != ESRCH) result = -1;
    }
    usleep(100000);
    while (waitpid(-1, NULL, WNOHANG) > 0) {}
    free(known);
    return result;
}
