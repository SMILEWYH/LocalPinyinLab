#include <stdio.h>
#include <unistd.h>
#include <signal.h>
int main(void) {
    puts("{\"ready\":true}"); fflush(stdout);
    char buffer[16386];
    if (fgets(buffer, sizeof(buffer), stdin)) {
        // Test fixture: the private query never returns and ignores graceful termination.
        signal(SIGTERM, SIG_IGN);
        for (;;) pause();
    }
    return 0;
}
