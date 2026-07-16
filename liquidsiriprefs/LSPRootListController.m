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

- (void)resetSliders {
    // Write directly to NSUserDefaults
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.yourcompany.liquidsiri.prefs"];
    [defaults setFloat:0.0 forKey:@"yOffset"];
    [defaults setFloat:1.0 forKey:@"orbScale"];
    [defaults synchronize];
    
    // Also explicitly write to rootless path to be completely safe on modern jailbreaks
    NSString *rootlessPath = @"/var/jb/var/mobile/Library/Preferences/com.yourcompany.liquidsiri.prefs.plist";
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:rootlessPath] ?: [NSMutableDictionary dictionary];
    dict[@"yOffset"] = @(0.0);
    dict[@"orbScale"] = @(1.0);
    [dict writeToFile:rootlessPath atomically:YES];
    
    [self reloadSpecifiers];
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
