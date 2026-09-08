#include "Sources/ProcessOwnership/include/ProcessOwnership.h"
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdbool.h>

static int report_fd;
static void spawn_on_term(int signal_number) {
    (void)signal_number;
    signal(SIGTERM, SIG_IGN);
    pid_t child = fork();
    if (child == 0) { while (1) pause(); }
    if (child > 0) { ssize_t ignored = write(report_fd, &child, sizeof(child)); (void)ignored; }
}

static int late_child_test(void) {
    int report[2];
    if (pipe(report) != 0) return 4;
    pid_t parent = fork();
    if (parent < 0) return 5;
    if (parent == 0) {
        close(report[0]);
        report_fd = report[1];
        signal(SIGTERM, spawn_on_term);
        while (1) pause();
    }
    close(report[1]);
    usleep(100000);
    int result = f7tty_stop_descendants();
    fcntl(report[0], F_SETFL, O_NONBLOCK);
    pid_t late_child = 0;
    ssize_t bytes = read(report[0], &late_child, sizeof(late_child));
    close(report[0]);
    for (int attempt = 0; attempt < 20 && late_child > 1 && kill(late_child, 0) == 0; attempt++) usleep(50000);
    bool alive = late_child > 1 && kill(late_child, 0) == 0;
    if (alive) kill(late_child, SIGKILL);
    if (result != 0 || bytes != sizeof(late_child) || late_child <= 1 || alive) return 6;
    puts("CLEANUP child forked during TERM grace period PASS");
    return 0;
}

int main(void) {
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) {
        signal(SIGTERM, SIG_IGN);
        while (1) pause();
    }
    usleep(100000);
    if (f7tty_stop_descendants() != 0) return 3;
    int status;
    waitpid(child, &status, WNOHANG);
    if (kill(child, 0) == 0) { kill(child, SIGKILL); return 1; }
    puts("CLEANUP stubborn child PASS");
    return late_child_test();
}
