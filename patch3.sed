170,200d
/viewWillDisappear/,/^}/c\
- (void)viewWillDisappear:(BOOL)animated {\
    %orig;\
    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{\
        self.glassOrbView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, -50), CGAffineTransformMakeScale(0.6, 0.6));\
        self.glassOrbView.alpha = 0.0;\
    } completion:nil];\
}\
\
- (void)viewDidDisappear:(BOOL)animated {\
    %orig;\
    [[WaveManager shared] stopRecording];\
}
