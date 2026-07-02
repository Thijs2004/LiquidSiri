%hook SUICOrbView

- (void)updateWithPowerLevel:(float)power {
    %orig;
    [[WaveManager shared] setTargetPower:(double)power];
}

- (void)setPowerLevel:(float)power {
    %orig;
    [[WaveManager shared] setTargetPower:(double)power];
}

%end
