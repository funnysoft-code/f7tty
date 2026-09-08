#ifndef F7TTY_PROCESS_OWNERSHIP_H
#define F7TTY_PROCESS_OWNERSHIP_H
// Best-effort cleanup of descendants observed during the shutdown grace period.
int f7tty_stop_descendants(void);
#endif
