/viewDidAppear/,/^}/c\
- (void)viewDidAppear:(BOOL)animated {\
    %orig;\
    [[WaveManager shared] startRecording];\
}
