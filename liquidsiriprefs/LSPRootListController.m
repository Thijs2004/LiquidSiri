#import <Foundation/Foundation.h>
#import "LSPRootListController.h"
#import <spawn.h>
#import <unistd.h>

@implementation LSPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring {
    pid_t pid;
    const char* args[] = {"sbreload", NULL};
    if (access("/var/jb/usr/bin/sbreload", F_OK) == 0) {
        posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
    } else if (access("/usr/bin/sbreload", F_OK) == 0) {
        posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char* const*)args, NULL);
    } else if (access("/var/jb/usr/bin/killall", F_OK) == 0) {
        const char* killargs[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char* const*)killargs, NULL);
    } else {
        const char* killargs[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char* const*)killargs, NULL);
    }
}

@end
